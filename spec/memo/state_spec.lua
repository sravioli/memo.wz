---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local state = require "memo.state"
local wt = require "wezterm"

-- ─────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────

---Stub `io.open` to intercept file reads/writes in memory.
---Returns a controller table with `.files`, `.reset()`, `.restore()`.
local function stub_io()
  local real_open = io.open
  local ctrl = { files = {}, open_calls = 0 }

  function ctrl.install()
    ---@diagnostic disable-next-line: duplicate-set-field
    io.open = function(path, mode)
      ctrl.open_calls = ctrl.open_calls + 1
      mode = mode or "r"
      if mode:find "r" then
        local content = ctrl.files[path]
        if not content then
          return nil, path .. ": No such file or directory"
        end
        local pos = 1
        return {
          read = function(_, what)
            if what == "*a" then
              local c = content:sub(pos)
              pos = #content + 1
              return c
            end
            return nil
          end,
          close = function() end,
        }
      end
      if mode:find "w" then
        local buf = {}
        return {
          write = function(_, data)
            buf[#buf + 1] = data
          end,
          close = function()
            ctrl.files[path] = table.concat(buf)
          end,
        }
      end
      return real_open(path, mode)
    end
  end

  function ctrl.reset()
    ctrl.files = {}
    ctrl.open_calls = 0
  end

  function ctrl.restore()
    io.open = real_open
  end

  return ctrl
end

describe("memo.state", function()
  local io_ctrl

  before_each(function()
    wt._reset()
    -- Wipe all GLOBAL state slots.
    for k in pairs(wt.GLOBAL) do
      wt.GLOBAL[k] = nil
    end
    io_ctrl = stub_io()
    io_ctrl.install()

    -- Provide a working json_decode mock (no code execution).
    wt.serde.json_decode = function(s)
      local result = {}
      -- Match "key":"value" pairs (string values only — sufficient for tests).
      for k, v in s:gmatch '"([%w_]+)"%s*:%s*"([^"]*)"' do
        result[k] = v
      end
      -- Match "key":number pairs.
      for k, v in s:gmatch '"([%w_]+)"%s*:%s*(%d+%.?%d*)' do
        result[k] = tonumber(v)
      end
      return result
    end
  end)

  after_each(function()
    io_ctrl.restore()
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Factory
  -- ─────────────────────────────────────────────────────────────────────

  describe("new", function()
    it("requires opts.path", function()
      assert.has_error(function()
        state.new {}
      end)
    end)

    it("creates an instance with defaults", function()
      local store = state.new { path = "/tmp/test.json" }
      assert.is_not_nil(store)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Basic CRUD
  -- ─────────────────────────────────────────────────────────────────────

  describe("get / set / has / delete", function()
    it("stores and retrieves values", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("answer", 42)
      assert.are.equal(42, store:get "answer")
    end)

    it("has returns true for existing keys", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("k", "v")
      assert.is_true(store:has "k")
    end)

    it("has returns false for missing keys", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      assert.is_false(store:has "missing")
    end)

    it("delete removes a key", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("k", "v")
      store:delete "k"
      assert.is_nil(store:get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Function guard
  -- ─────────────────────────────────────────────────────────────────────

  describe("function storage guard", function()
    it("rejects function values", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("bad", function() end)
      assert.is_nil(store:get "bad")
      assert.is_true(#wt._calls > 0)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- clear / restore
  -- ─────────────────────────────────────────────────────────────────────

  describe("clear", function()
    it("removes all entries", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("a", 1)
      store:set("b", 2)
      store:clear()
      assert.is_nil(store:get "a")
      assert.is_nil(store:get "b")
    end)
  end)

  describe("restore", function()
    it("returns a shallow copy of all data", function()
      local store = state.new { path = "/tmp/test.json", auto_save = false }
      store:set("x", 10)
      store:set("y", 20)
      local copy = store:restore()
      assert.are.equal(10, copy.x)
      assert.are.equal(20, copy.y)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Persistence: save / load
  -- ─────────────────────────────────────────────────────────────────────

  describe("save / load", function()
    it("round-trips data through JSON", function()
      local path = "/tmp/roundtrip.json"
      local s1 = state.new { path = path, auto_save = false, async = false }
      s1:set("name", "test")
      s1:save()

      -- Verify file was written.
      assert.is_not_nil(io_ctrl.files[path])

      -- Create a new instance pointing at the same path, force a fresh load.
      for k in pairs(wt.GLOBAL) do
        wt.GLOBAL[k] = nil
      end
      local s2 = state.new { path = path, auto_load = false, async = false }
      s2:load()
      assert.are.equal("test", s2:get "name")
    end)

    it("auto_save writes on every set", function()
      local path = "/tmp/autosave.json"
      local store = state.new { path = path, async = false }
      store:set("k", "v")
      assert.is_not_nil(io_ctrl.files[path])
    end)

    it("auto_save=false does not write on set", function()
      local path = "/tmp/no_autosave.json"
      local store = state.new { path = path, auto_save = false, async = false }
      store:set("k", "v")
      assert.is_nil(io_ctrl.files[path])
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Load guard
  -- ─────────────────────────────────────────────────────────────────────

  describe("load guard", function()
    it("reads from disk only once", function()
      local path = "/tmp/guard.json"
      io_ctrl.files[path] = '{"k":"loaded"}'
      local store = state.new { path = path, auto_save = false, async = false }
      -- First access triggers auto_load.
      store:get "k"
      local calls_after_first = io_ctrl.open_calls
      -- Subsequent accesses should not re-read.
      store:get "k"
      store:get "k"
      assert.are.equal(calls_after_first, io_ctrl.open_calls)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- auto_load=false
  -- ─────────────────────────────────────────────────────────────────────

  describe("auto_load=false", function()
    it("does not read from disk on first access", function()
      local path = "/tmp/noauto.json"
      io_ctrl.files[path] = '{"k":"loaded"}'
      local store = state.new { path = path, auto_load = false, async = false }
      assert.is_nil(store:get "k") -- not loaded yet
      assert.are.equal(0, io_ctrl.open_calls)
    end)

    it("allows explicit load()", function()
      local path = "/tmp/noauto2.json"
      io_ctrl.files[path] = '{"k":"loaded"}'
      local store = state.new { path = path, auto_load = false, async = false }
      store:load()
      assert.are.equal("loaded", store:get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Independent instances
  -- ─────────────────────────────────────────────────────────────────────

  describe("independent instances", function()
    it("stores are isolated by path", function()
      local s1 = state.new { path = "/tmp/s1.json", auto_save = false }
      local s2 = state.new { path = "/tmp/s2.json", auto_save = false }
      s1:set("k", "from_s1")
      s2:set("k", "from_s2")
      assert.are.equal("from_s1", s1:get "k")
      assert.are.equal("from_s2", s2:get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Table values (deep copy)
  -- ─────────────────────────────────────────────────────────────────────

  describe("table values", function()
    it("stores table values via deep copy", function()
      local store = state.new { path = "/tmp/tbl.json", auto_save = false }
      store:set("cfg", { theme = "dark", font_size = 14 })
      local v = store:get "cfg"
      assert.are.equal("dark", v.theme)
      assert.are.equal(14, v.font_size)
    end)

    it("merges into existing table on re-set", function()
      local store = state.new { path = "/tmp/merge.json", auto_save = false }
      store:set("t", { a = 1, b = 2 })
      store:set("t", { b = 3, c = 4 })
      local v = store:get "t"
      assert.are.equal(1, v.a)
      assert.are.equal(3, v.b)
      assert.are.equal(4, v.c)
    end)

    it("overwrites non-table value with table without crashing", function()
      local store = state.new { path = "/tmp/overwrite.json", auto_save = false }
      store:set("k", "hello")
      store:set("k", { a = 1 })
      local v = store:get "k"
      assert.are.equal(1, v.a)
    end)

    it("overwrites nested non-table with table via merge", function()
      local store = state.new { path = "/tmp/nested_ow.json", auto_save = false }
      store:set("cfg", { theme = "dark" })
      store:set("cfg", { theme = { name = "dark", variant = "hc" } })
      local v = store:get "cfg"
      assert.are.equal("dark", v.theme.name)
      assert.are.equal("hc", v.theme.variant)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- load edge cases
  -- ─────────────────────────────────────────────────────────────────────

  describe("load edge cases", function()
    it("handles empty file gracefully", function()
      local path = "/tmp/empty.json"
      io_ctrl.files[path] = ""
      local store = state.new { path = path, auto_load = false, async = false }
      store:load()
      -- Should not error; store stays empty.
      assert.is_nil(store:get "anything")
    end)

    it("handles invalid JSON gracefully", function()
      local path = "/tmp/bad.json"
      io_ctrl.files[path] = "not valid json {{{"
      local store = state.new { path = path, auto_load = false, async = false }
      -- json_decode will error; load should catch it and log a warning.
      wt.serde.json_decode = function(s)
        error("invalid JSON: " .. s)
      end
      store:load()
      assert.is_nil(store:get "anything")
      -- Verify a warning was logged.
      local found_warn = false
      for _, call in ipairs(wt._calls) do
        if call.fn == "log_warn" then
          found_warn = true
          break
        end
      end
      assert.is_true(found_warn)
    end)

    it("handles missing file without error", function()
      local store =
        state.new { path = "/tmp/nonexistent.json", auto_load = false, async = false }
      store:load()
      assert.is_nil(store:get "anything")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- serde usage
  -- ─────────────────────────────────────────────────────────────────────

  describe("serde usage", function()
    it("save calls json_encode", function()
      local encode_called = false
      local orig = wt.serde.json_encode
      wt.serde.json_encode = function(v)
        encode_called = true
        return orig(v)
      end
      local store =
        state.new { path = "/tmp/serde_enc.json", auto_save = false, async = false }
      store:set("k", "v")
      store:save()
      assert.is_true(encode_called)
      wt.serde.json_encode = orig
    end)

    it("load calls json_decode", function()
      local decode_called = false
      local orig = wt.serde.json_decode
      wt.serde.json_decode = function(s)
        decode_called = true
        return orig(s)
      end
      io_ctrl.files["/tmp/serde_dec.json"] = '{"k":"v"}'
      local store =
        state.new { path = "/tmp/serde_dec.json", auto_load = false, async = false }
      store:load()
      assert.is_true(decode_called)
      wt.serde.json_decode = orig
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- auto_save on delete and clear
  -- ─────────────────────────────────────────────────────────────────────

  describe("auto_save on mutations", function()
    it("auto_save flushes on delete", function()
      local path = "/tmp/autodel.json"
      local store = state.new { path = path, async = false }
      store:set("k", "v")
      io_ctrl.files[path] = nil -- reset to detect the next write
      store:delete "k"
      assert.is_not_nil(io_ctrl.files[path])
    end)

    it("auto_save flushes on clear", function()
      local path = "/tmp/autoclear.json"
      local store = state.new { path = path, async = false }
      store:set("k", "v")
      io_ctrl.files[path] = nil
      store:clear()
      assert.is_not_nil(io_ctrl.files[path])
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- restore edge cases
  -- ─────────────────────────────────────────────────────────────────────

  describe("restore edge cases", function()
    it("returns empty table for empty store", function()
      local store = state.new { path = "/tmp/empty_restore.json", auto_save = false }
      local copy = store:restore()
      assert.are.same({}, copy)
    end)

    it("returned copy is independent from store", function()
      local store = state.new { path = "/tmp/independent.json", auto_save = false }
      store:set("k", "original")
      local copy = store:restore()
      copy.k = "modified"
      assert.are.equal("original", store:get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- async save
  -- ─────────────────────────────────────────────────────────────────────

  describe("sync save fallback", function()
    it("writes synchronously when background_task is unavailable", function()
      -- background_task is not set in the mock, so _has_bg_task is false.
      -- async=true in opts but the module falls back to sync writes.
      local path = "/tmp/sync_fallback.json"
      local store = state.new { path = path, async = true, auto_save = false }
      store:set("k", "v")
      store:save()
      assert.is_not_nil(io_ctrl.files[path])
    end)
  end)
end)
