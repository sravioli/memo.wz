---@module "memo.state"

---File-persistent key/value store backed by `wezterm.GLOBAL`.
---
---Each instance owns a dedicated GLOBAL slot (keyed by the file path hash)
---and an on-disk JSON file.  Data is loaded from disk once per WezTerm
---process (the "load guard") and optionally flushed after every mutation.

local cache = require "memo.cache" ---@class memo.Cache
local wt = require "wezterm" ---@class Wezterm

local ensure_global_tbl = cache._ensure_global_tbl
local sync_to_global = cache._sync_to_global

local _has_serde = wt.serde ~= nil
local _has_bg_task = type(wt.background_task) == "function"

-- ───────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ───────────────────────────────────────────────────────────────────────────

---Write `content` to `path` synchronously.
---@param path    string
---@param content string
---@return boolean ok
local function write_file(path, content)
  local fh, err = io.open(path, "w")
  if not fh then
    wt.log_warn(("[memo.state] unable to write %s: %s"):format(path, err))
    return false
  end
  fh:write(content)
  fh:close()
  return true
end

-- ───────────────────────────────────────────────────────────────────────────
-- Store class
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.state.Store
---@field _path      string   Absolute path to the JSON file.
---@field _store     table    Reference into `wt.GLOBAL` slot (`{ loaded, data }`).
---@field _auto_load boolean  Load from disk on first access.
---@field _auto_save boolean  Flush to disk on every mutation.
---@field _async     boolean  Use background_task for writes if available.
local Store = {}
Store.__index = Store

---Ensure state has been loaded from disk (respects auto_load and load guard).
---@param self memo.state.Store
local function ensure_loaded(self)
  if self._store.loaded then
    return
  end
  if self._auto_load then
    self:load()
  end
end

---Flush state to disk if auto_save is enabled.
---@param self memo.state.Store
local function auto_flush(self)
  if self._auto_save then
    self:save()
  end
end

-- ───────────────────────────────────────────────────────────────────────────
-- Instance API
-- ───────────────────────────────────────────────────────────────────────────

---Retrieve a value by key.
---
---@param key string
---@return any|nil
function Store:get(key)
  ensure_loaded(self)
  return self._store.data[key]
end

---Store a value.
---
---Keys must be strings (JSON limitation).  Functions cannot be persisted.
---
---@param key   string
---@param value any
function Store:set(key, value)
  if type(key) ~= "string" then
    wt.log_error("[memo.state] keys must be strings, got " .. type(key))
    return
  end
  if type(value) == "function" then
    wt.log_error(
      "[memo.state] functions cannot be stored; "
        .. "only string, number, boolean, and table values are supported"
    )
    return
  end
  ensure_loaded(self)
  if type(value) == "table" then
    if type(self._store.data[key]) ~= "table" then
      self._store.data[key] = {}
    end
    sync_to_global(self._store.data[key], value)
  else
    self._store.data[key] = value
  end
  auto_flush(self)
end

---Check whether a key exists.
---
---@param key string
---@return boolean
function Store:has(key)
  ensure_loaded(self)
  return self._store.data[key] ~= nil
end

---Delete a single key.
---
---@param key string
function Store:delete(key)
  ensure_loaded(self)
  self._store.data[key] = nil
  auto_flush(self)
end

---Clear all entries.
function Store:clear()
  ensure_loaded(self)
  for k in pairs(self._store.data) do
    self._store.data[k] = nil
  end
  auto_flush(self)
end

---Load state from the JSON file on disk.
---
---This always reads from disk (bypasses the load guard) and marks the store
---as loaded so subsequent `ensure_loaded` calls are no-ops.
function Store:load()
  self._store.loaded = true

  if not _has_serde then
    return
  end

  local fh, open_err = io.open(self._path, "r")
  if not fh then
    if open_err and not open_err:find "No such file" then
      wt.log_warn(("[memo.state] unable to read %s: %s"):format(self._path, open_err))
    end
    return
  end

  local content = fh:read "*a"
  fh:close()

  if not content or content == "" then
    return
  end

  local ok, decoded = pcall(wt.serde.json_decode, content)
  if not ok then
    wt.log_warn(("[memo.state] invalid JSON in %s: %s"):format(self._path, decoded))
    return
  end

  if type(decoded) == "table" then
    -- Wipe existing data, then deep-copy decoded values.
    for k in pairs(self._store.data) do
      self._store.data[k] = nil
    end
    sync_to_global(self._store.data, decoded)
  end
end

---Flush current state to disk as JSON.
---
---Uses `wezterm.background_task` when available and `async` is enabled;
---otherwise writes synchronously.
function Store:save()
  if not _has_serde then
    return
  end

  local encoded = wt.serde.json_encode(self._store.data)

  if self._async and _has_bg_task then
    local path = self._path
    wt.background_task(function()
      write_file(path, encoded)
    end)
  else
    write_file(self._path, encoded)
  end
end

---Return a shallow copy of all stored data.
---
---@return table
function Store:restore()
  ensure_loaded(self)
  local copy = {}
  for k, v in pairs(self._store.data) do
    copy[k] = v
  end
  return copy
end

-- ───────────────────────────────────────────────────────────────────────────
-- Factory
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.State
local M = {}

---Create a new file-persistent state store.
---
---@param opts table  Options:
---  - `path`      (string, required)  Absolute path to the JSON file.
---  - `auto_load` (boolean, default true)  Load from disk on first access.
---  - `auto_save` (boolean, default true)  Write to disk on every mutation.
---  - `async`     (boolean, default true)  Use background_task when available.
---@return memo.state.Store
function M.new(opts)
  assert(opts and opts.path, "[memo.state] opts.path is required")

  local slot_key = "__memo_state_" .. opts.path:gsub("[^%w_%-%.]", "_")
  local store = ensure_global_tbl(slot_key, { loaded = false, data = {} })

  return setmetatable({
    _path = opts.path,
    _store = store,
    _auto_load = opts.auto_load ~= false,
    _auto_save = opts.auto_save ~= false,
    _async = opts.async ~= false,
  }, Store)
end

return M
