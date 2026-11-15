---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local state = require "memo.state"
local wt = require "wezterm"

local function read(path)
  local fh = io.open(path, "rb")
  if not fh then
    return nil
  end
  local c = fh:read "*a"
  fh:close()
  return c
end

local function exists(path)
  return read(path) ~= nil
end

---Sibling files `path.<token>.tmp` / `.old` left behind by a write.
local function leftovers(path)
  local out = {}
  local dir, base = path:match "^(.*)[/\\]([^/\\]+)$"
  local ok, entries = pcall(function()
    local fh = io.popen(('ls -a "%s"'):format(dir))
    local list = fh:read "*a"
    fh:close()
    return list
  end)
  if ok then
    for name in entries:gmatch "[^\n]+" do
      if name:sub(1, #base + 1) == base .. "." and (name:match "%.tmp$" or name:match "%.old$") then
        out[#out + 1] = name
      end
    end
  end
  return out
end

local function is_tmp(p, path)
  return p:sub(1, #path + 1) == path .. "." and p:match "%.tmp$" ~= nil
end

---Make os.rename behave like Windows: it refuses to replace an existing file.
local function windows_rename(rename)
  return function(from, to)
    if exists(to) then
      return nil, "file exists"
    end
    return rename(from, to)
  end
end

describe("memo.state atomic writes", function()
  local path

  before_each(function()
    wt._reset()
    path = os.tmpname()
    -- os.tmpname on some platforms already creates the file.
    os.remove(path)
  end)

  after_each(function()
    for _, p in ipairs { path, path .. ".bak" } do
      os.remove(p)
    end
  end)

  it("creates the file when missing", function()
    assert.is_true(state.write_atomic(path, "one"))
    assert.are.equal("one", read(path))
    assert.is_false(exists(path .. ".tmp"))
  end)

  it("replaces an existing file without leftovers", function()
    state.write_atomic(path, "one")
    assert.is_true(state.write_atomic(path, "two"))
    assert.are.equal("two", read(path))
    assert.is_false(exists(path .. ".tmp"))
    assert.is_false(exists(path .. ".old"))
    assert.is_false(exists(path .. ".bak"))
  end)

  it("keeps the previous file as .bak when requested", function()
    state.write_atomic(path, "one")
    assert.is_true(state.write_atomic(path, "two", { backup = true }))
    assert.are.equal("two", read(path))
    assert.are.equal("one", read(path .. ".bak"))
  end)

  it("fails without touching the target when the temp file cannot be written", function()
    state.write_atomic(path, "one")
    local real_open = io.open
    ---@diagnostic disable-next-line: duplicate-set-field
    io.open = function(p, mode)
      if is_tmp(p, path) then
        return nil, "denied"
      end
      return real_open(p, mode)
    end
    local ok = state.write_atomic(path, "two")
    io.open = real_open
    assert.is_false(ok)
    assert.are.equal("one", read(path))
  end)

  it("uses a distinct temporary file for every write", function()
    local real_open = io.open
    local tmps = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    io.open = function(p, mode)
      if is_tmp(p, path) then
        tmps[#tmps + 1] = p
      end
      return real_open(p, mode)
    end
    state.write_atomic(path, "one")
    state.write_atomic(path, "two", { backup = true })
    io.open = real_open
    assert.equal(3, #tmps)
    assert.not_equal(tmps[1], tmps[2])
    assert.not_equal(tmps[2], tmps[3])
    assert.not_equal(tmps[1], tmps[3])
    assert.same({}, leftovers(path))
  end)

  it("stores saved through an atomic Store", function()
    local store = state.new { path = path, atomic = true, backup = true, async = false }
    store:set("a", "1")
    store:set("a", "2")
    assert.is_truthy(read(path):find('"a":"2"', 1, true))
    assert.is_truthy(read(path .. ".bak"):find('"a":"1"', 1, true))
  end)

  it("does not replace target on write or close failure", function()
    for _, failing in ipairs { "write", "close" } do
      state.write_atomic(path, "original")
      local real_open = io.open
      io.open = function(p, mode)
        if is_tmp(p, path) and not p:find(".bak.", 1, true) then
          return {
            write = function()
              if failing == "write" then
                return nil, "disk full"
              end
              return true
            end,
            close = function()
              if failing == "close" then
                return nil, "flush failed"
              end
              return true
            end,
          }
        end
        return real_open(p, mode)
      end
      local ok = state.write_atomic(path, "broken", { backup = true })
      io.open = real_open
      assert.is_false(ok)
      assert.equal("original", read(path))
    end
  end)

  it("preserves an orphan backup when primary is missing", function()
    state.write_atomic(path .. ".bak", "recoverable")
    assert.is_true(state.write_atomic(path, "new", { backup = true }))
    assert.equal("recoverable", read(path .. ".bak"))
  end)

  it("never moves the primary aside when keeping a backup", function()
    state.write_atomic(path, "original")
    local rename = os.rename
    os.rename = function(from, to)
      assert.not_equal(path, from)
      return rename(from, to)
    end
    local ok = state.write_atomic(path, "new", { backup = true })
    os.rename = rename
    assert.is_true(ok)
    assert.equal("new", read(path))
    assert.equal("original", read(path .. ".bak"))
  end)

  it("leaves the primary untouched when the backup copy fails", function()
    state.write_atomic(path, "original")
    state.write_atomic(path .. ".bak", "previous")
    local real_open = io.open
    io.open = function(p, mode)
      if is_tmp(p, path .. ".bak") then
        return nil, "denied"
      end
      return real_open(p, mode)
    end
    local ok = state.write_atomic(path, "new", { backup = true })
    io.open = real_open
    assert.is_false(ok)
    assert.equal("original", read(path))
    assert.equal("previous", read(path .. ".bak"))
  end)

  describe("when rename cannot replace a file (Windows)", function()
    local rename
    before_each(function()
      rename = os.rename
    end)
    after_each(function()
      os.rename = rename
    end)

    it("replaces the target and the backup without leftovers", function()
      state.write_atomic(path, "one")
      state.write_atomic(path, "two", { backup = true })
      os.rename = windows_rename(rename)
      assert.is_true(state.write_atomic(path, "three", { backup = true }))
      os.rename = rename
      assert.equal("three", read(path))
      assert.equal("two", read(path .. ".bak"))
      assert.same({}, leftovers(path))
    end)

    it("keeps the primary if it cannot be moved aside", function()
      state.write_atomic(path, "original")
      local windows = windows_rename(rename)
      os.rename = function(from, to)
        if from == path then
          return nil, "denied"
        end
        return windows(from, to)
      end
      local ok = state.write_atomic(path, "new")
      os.rename = rename
      assert.is_false(ok)
      assert.equal("original", read(path))
    end)

    it("puts the primary back when the final rename fails", function()
      state.write_atomic(path, "original")
      local windows = windows_rename(rename)
      os.rename = function(from, to)
        if to == path and is_tmp(from, path) then
          return nil, "denied"
        end
        return windows(from, to)
      end
      local ok = state.write_atomic(path, "new")
      os.rename = rename
      assert.is_false(ok)
      assert.equal("original", read(path))
      assert.same({}, leftovers(path))
    end)
  end)
end)

describe("memo.state set replace", function()
  local path

  before_each(function()
    wt._reset()
    path = os.tmpname()
    os.remove(path)
  end)

  after_each(function()
    os.remove(path)
  end)

  it("merges tables by default", function()
    local store = state.new { path = path, auto_save = false }
    store:set("t", { a = 1, b = 2 })
    store:set("t", { a = 3 })
    assert.are.equal(3, store:get("t").a)
    assert.are.equal(2, store:get("t").b)
  end)

  it("replaces tables wholesale with { replace = true }", function()
    local store = state.new { path = path, auto_save = false }
    store:set("l", { "x", "y", "z" })
    store:set("l", { "q" }, { replace = true })
    local l = store:get "l"
    assert.are.equal("q", l[1])
    assert.is_nil(l[2])
    assert.is_nil(l[3])
  end)
end)
