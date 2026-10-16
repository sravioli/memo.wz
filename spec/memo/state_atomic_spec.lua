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

describe("memo.state atomic writes", function()
  local path

  before_each(function()
    wt._reset()
    path = os.tmpname()
    -- os.tmpname on some platforms already creates the file.
    os.remove(path)
  end)

  after_each(function()
    for _, p in ipairs { path, path .. ".tmp", path .. ".bak", path .. ".old" } do
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
      if p == path .. ".tmp" then
        return nil, "denied"
      end
      return real_open(p, mode)
    end
    local ok = state.write_atomic(path, "two")
    io.open = real_open
    assert.is_false(ok)
    assert.are.equal("one", read(path))
  end)

  it("stores saved through an atomic Store", function()
    local store = state.new { path = path, atomic = true, backup = true, async = false }
    store:set("a", "1")
    store:set("a", "2")
    assert.is_truthy(read(path):find('"a":"2"', 1, true))
    assert.is_truthy(read(path .. ".bak"):find('"a":"1"', 1, true))
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
