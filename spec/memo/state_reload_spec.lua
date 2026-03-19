---@diagnostic disable: undefined-global

--- Tests that require reloading memo.state under different mock conditions.
--- These cover module-level branches (`_has_serde`, `_has_bg_task`) that are
--- captured at require-time and cannot be toggled in normal tests.

require "spec.mocks.wezterm"

local wt = require "wezterm"

-- ─────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────

---Stub `io.open` identically to the one in state_spec.
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

---Force-reload memo.state (and only memo.state) so module-level locals
---like `_has_serde` and `_has_bg_task` are re-evaluated.
local function reload_state()
  package.loaded["memo.state"] = nil
  return require "memo.state"
end

-- ─────────────────────────────────────────────────────────────────────────
-- Tests: _has_serde = false
-- ─────────────────────────────────────────────────────────────────────────

describe("memo.state (serde unavailable)", function()
  local io_ctrl
  local saved_serde

  setup(function()
    saved_serde = wt.serde
    wt.serde = nil -- make _has_serde evaluate to false
  end)

  teardown(function()
    wt.serde = saved_serde
    reload_state() -- restore module with serde available
  end)

  before_each(function()
    wt._reset()
    for k in pairs(wt.GLOBAL) do
      wt.GLOBAL[k] = nil
    end
    io_ctrl = stub_io()
    io_ctrl.install()
  end)

  after_each(function()
    io_ctrl.restore()
  end)

  it("save is a no-op when serde is unavailable", function()
    local state = reload_state()
    local path = "/tmp/no_serde_save.json"
    local store = state.new { path = path, auto_save = false, async = false }
    store:set("k", "v")
    store:save()
    -- No file should have been written since serde is nil.
    assert.is_nil(io_ctrl.files[path])
  end)

  it("load is a no-op when serde is unavailable", function()
    local state = reload_state()
    local path = "/tmp/no_serde_load.json"
    io_ctrl.files[path] = '{"k":"from_disk"}'
    local store = state.new { path = path, auto_load = false, async = false }
    store:load()
    -- Data should NOT have been loaded from disk.
    assert.is_nil(store:get "k")
    -- io.open should not have been called (early return before io.open).
    assert.are.equal(0, io_ctrl.open_calls)
  end)
end)

-- ─────────────────────────────────────────────────────────────────────────
-- Tests: _has_bg_task = true
-- ─────────────────────────────────────────────────────────────────────────

describe("memo.state (background_task available)", function()
  local io_ctrl
  local bg_tasks

  setup(function()
    bg_tasks = {}
    wt.background_task = function(fn)
      bg_tasks[#bg_tasks + 1] = fn
    end
  end)

  teardown(function()
    wt.background_task = nil
    reload_state() -- restore module without background_task
  end)

  before_each(function()
    wt._reset()
    for k in pairs(wt.GLOBAL) do
      wt.GLOBAL[k] = nil
    end
    bg_tasks = {}
    io_ctrl = stub_io()
    io_ctrl.install()
  end)

  after_each(function()
    io_ctrl.restore()
  end)

  it("save uses background_task when async=true and background_task exists", function()
    local state = reload_state()
    local path = "/tmp/bg_save.json"
    local store = state.new { path = path, auto_save = false, async = true }
    store:set("k", "v")
    store:save()

    -- File should NOT yet be written (queued in background_task).
    assert.is_nil(io_ctrl.files[path])
    -- A background task should have been scheduled.
    assert.are.equal(1, #bg_tasks)

    -- Execute the background task.
    bg_tasks[1]()
    -- Now the file should be written.
    assert.is_not_nil(io_ctrl.files[path])
  end)

  it("save writes synchronously when async=false despite background_task", function()
    local state = reload_state()
    local path = "/tmp/sync_save_with_bg.json"
    local store = state.new { path = path, auto_save = false, async = false }
    store:set("k", "v")
    store:save()

    -- File should be written immediately (sync path because async=false).
    assert.is_not_nil(io_ctrl.files[path])
    -- No background task should have been scheduled.
    assert.are.equal(0, #bg_tasks)
  end)
end)
