---@module "memo.state"

---File-persistent key/value store backed by `wezterm.GLOBAL`.
---
---Each instance owns a dedicated GLOBAL slot, keyed by the file path hash,
---and an on-disk JSON file. Data is loaded from disk once per WezTerm
---process (the "load guard") and optionally flushed after every mutation.

local cache = require "memo.cache" ---@class memo.Cache
local deps = require "memo.deps"
local wt = require "wezterm" ---@class Wezterm

local ensure_global_tbl = cache._ensure_global_tbl
local sync_to_global = cache._sync_to_global
local plain = cache.plain

local _has_serde = wt.serde ~= nil

---@class memo.State
local M = {}

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
  local wrote, write_err = fh:write(content)
  local closed, close_err = fh:close()
  if not wrote or not closed then
    wt.log_warn(("[memo.state] unable to flush %s: %s"):format(path, write_err or close_err))
    return false
  end
  return true
end

---@param path string
---@return string|nil content
local function read_file(path)
  local fh = io.open(path, "rb")
  if not fh then
    return nil
  end
  local content = fh:read "*a"
  fh:close()
  return content
end

---Atomically write `content` to `path` through warp (temp file and rename,
---with a rollback on Windows).
---@param path    string
---@param content string
---@return boolean ok
local function replace(path, content)
  local ok, err = deps.warp().filesystem.write_file(path, content)
  if not ok then
    wt.log_warn(("[memo.state] %s"):format(err))
  end
  return ok
end

---Write `content` to `path` atomically.
---
---Readers never observe a half-written file. Content goes to a unique
---temporary file that is then renamed over the target. Concurrent writers
---cannot interleave (the last complete write wins). When `backup` is true
---the previous file is first copied to `path .. ".bak"` the same way, so
---the primary is never missing, even if the process dies mid-write.
---Exposed for callers that persist whole documents without a Store.
---
---@param path    string
---@param content string
---@param opts    { backup?: boolean }|nil  `backup` keeps the old file as `.bak`.
---@return boolean ok
function M.write_atomic(path, content, opts)
  if opts and opts.backup then
    local previous = read_file(path)
    if previous and not replace(path .. ".bak", previous) then
      wt.log_warn(("[memo.state] unable to back up %s"):format(path))
      return false
    end
  end
  return replace(path, content)
end
local write_atomic = M.write_atomic

-- ───────────────────────────────────────────────────────────────────────────
-- Store class
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.state.Store
---@field _path      string   Absolute path to the JSON file.
---@field _store     table    Reference into `wt.GLOBAL` slot (`{ loaded, data }`).
---@field _auto_load boolean  Load from disk on first access.
---@field _auto_save boolean  Flush to disk on every mutation.
local Store = {}
Store.__index = Store

---Load state from disk when needed, respecting `auto_load` and the load guard.
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

---Get a value by key.
---
---@param key string
---@return any|nil
function Store:get(key)
  ensure_loaded(self)
  return self._store.data[key]
end

---Store a value.
---
---Keys must be strings because JSON object keys are strings. Functions cannot be persisted.
---
---Table values are deep-merged into an existing table by default, so keys
---missing from `value` survive. Pass `{ replace = true }` to overwrite the
---stored value wholesale (e.g. when shrinking a list).
---
---@param key   string
---@param value any
---@param opts  { replace?: boolean }|nil
function Store:set(key, value, opts)
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
    -- Merge in plain Lua, then assign once: GLOBAL objects reject integer
    -- keys, so writing a list through a GLOBAL proxy raises.
    local current = plain(self._store.data[key])
    local merged = {}
    if not (opts and opts.replace) and type(current) == "table" then
      merged = current
    end
    sync_to_global(merged, value)
    value = merged
  end
  self._store.data[key] = value
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
  -- Reassign: a GLOBAL object keeps keys set to nil as nulls.
  self._store.data = {}
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
    -- Replace existing data wholesale (assignment copies into GLOBAL).
    self._store.data = decoded
  end
end

---Flush current state to disk as JSON, synchronously.
function Store:save()
  if not _has_serde then
    return
  end

  local encoded = wt.serde.json_encode(self._store.data)
  local path = self._path
  local write = write_file
  if self._atomic then
    local backup = self._backup
    write = function(p, c)
      return write_atomic(p, c, { backup = backup })
    end
  end

  write(path, encoded)
end

---Return a shallow copy of all stored data.
---
---@return table
function Store:restore()
  ensure_loaded(self)
  local data = self._store.data
  local copy = {}
  -- Read values by index: GLOBAL `pairs` yields userdata, and deleted keys
  -- linger as nulls that index to nil.
  for k in pairs(data) do
    local v = data[k]
    if v ~= nil then
      copy[k] = v
    end
  end
  return copy
end

-- ───────────────────────────────────────────────────────────────────────────
-- Factory
-- ───────────────────────────────────────────────────────────────────────────

---Create a new file-persistent state store.
---
---@param opts table  Options:
---  - `path`      (string, required)  Absolute path to the JSON file.
---  - `auto_load` (boolean, default true)  Load from disk on first access.
---  - `auto_save` (boolean, default true)  Write to disk on every mutation.
---  - `atomic`    (boolean, default true) Write via temp file + rename.
---  - `backup`    (boolean, default false) Keep the previous file as `.bak`
---    (only with `atomic`).
---@return memo.state.Store
function M.new(opts)
  assert(opts and opts.path, "[memo.state] opts.path is required")

  -- The raw path: escaping it would let `a/b` and `a_b` share one slot.
  local slot_key = "__memo_state_" .. opts.path
  local store = ensure_global_tbl(slot_key, { loaded = false, data = {} })

  return setmetatable({
    _path = opts.path,
    _store = store,
    _auto_load = opts.auto_load ~= false,
    _auto_save = opts.auto_save ~= false,
    -- In-place writes leave an empty file if WezTerm dies mid-write.
    _atomic = opts.atomic ~= false,
    _backup = opts.backup == true,
  }, Store)
end

return M
