---@module "memo.cache"

---Session-scoped memoization cache backed by `wezterm.GLOBAL`.
---
---TTL and stats are opt-in; when disabled the cache stores bare values with
---zero bookkeeping overhead.  Keys are generated via `memo.hash` (XXH3-64)
---so that complex arguments produce compact, deterministic cache keys without
---the cost of building a full serialization string.

local hash = require "memo.hash" ---@class memo.Hash
local wt = require "wezterm" ---@class Wezterm

local make_cache_key = hash.make_cache_key

-- ───────────────────────────────────────────────────────────────────────────
-- GLOBAL initialization
-- ───────────────────────────────────────────────────────────────────────────

---Ensure a key in `wt.GLOBAL` is a table and recursively fill defaults.
---@param key      string
---@param template table
---@return table
local function ensure_global_tbl(key, template)
  wt.GLOBAL[key] = wt.GLOBAL[key] or {}
  local tgt = wt.GLOBAL[key]

  local function fill(target, tpl)
    for k, v in pairs(tpl) do
      if type(v) == "table" then
        target[k] = target[k] or {}
        fill(target[k], v)
      else
        target[k] = target[k] or v
      end
    end
  end

  fill(tgt, template)
  return tgt
end

---Recursively assign data into a `wt.GLOBAL`-backed table.
---@param target table
---@param source table
local function sync_to_global(target, source)
  for k, v in pairs(source) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then
        target[k] = {}
      end
      sync_to_global(target[k], v)
    else
      target[k] = v
    end
  end
end

-- ───────────────────────────────────────────────────────────────────────────
-- GLOBAL key constants
-- ───────────────────────────────────────────────────────────────────────────

local SLOT_KEY = "__memo_cache"
local STATS_KEY = "__memo_stats"
local STATS_DEFAULT = { hits = 0, misses = 0, evictions = 0 }

-- ───────────────────────────────────────────────────────────────────────────
-- Configuration (singleton)
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.cache.Config
---@field max_entries integer|nil  Max number of cache entries (nil = unlimited).
---@field eviction    string       Eviction policy when max_entries reached ("expire-first").
---@field ttl         table|nil    TTL configuration; nil = disabled.
---@field stats       boolean      Whether to track hit/miss statistics.
---@field debug       boolean      Whether to log debug messages.
---@field clock       fun(): number  Clock function for TTL (injectable).

---@type memo.cache.Config
local _cfg = {
  max_entries = nil,
  eviction = "expire-first",
  ttl = nil,
  stats = false,
  debug = false,
  clock = os.time,
}

-- Set of valid config keys (needed because some defaults are nil).
local _cfg_keys = {}
for k in pairs {
  max_entries = true,
  eviction = true,
  ttl = true,
  stats = true,
  debug = true,
  clock = true,
} do
  _cfg_keys[k] = true
end

ensure_global_tbl(SLOT_KEY, {})

---Get the live cache slot from GLOBAL (survives reconfigure / clear).
---@return table
local function SLOT()
  if not wt.GLOBAL[SLOT_KEY] then
    wt.GLOBAL[SLOT_KEY] = {}
  end
  return wt.GLOBAL[SLOT_KEY]
end

-- ───────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ───────────────────────────────────────────────────────────────────────────

---@return boolean
local function ttl_enabled()
  return _cfg.ttl ~= nil
end

---Get the effective TTL for an entry, respecting per-entry override.
---@param opts table|nil  Per-call options `{ ttl = N }`.
---@return number|nil     TTL in seconds, or nil if TTL is disabled.
local function effective_ttl(opts)
  if not ttl_enabled() then
    return nil
  end
  if opts and opts.ttl then
    return opts.ttl
  end
  return _cfg.ttl and _cfg.ttl.default
end

---Bump stats counters.
---@param counter string  "hits"|"misses"|"evictions"
local function bump(counter)
  if not _cfg.stats then
    return
  end
  local st = wt.GLOBAL[STATS_KEY]
  if not st then
    wt.GLOBAL[STATS_KEY] = { hits = 0, misses = 0, evictions = 0 }
    st = wt.GLOBAL[STATS_KEY]
  end
  st[counter] = (st[counter] or 0) + 1
end

---Check whether a TTL-wrapped entry has expired.
---@param entry table  `{ value, expires_at }`.
---@return boolean
local function is_expired(entry)
  if not entry.expires_at then
    return false
  end
  return _cfg.clock() >= entry.expires_at
end

---Raw read from the cache slot, handling TTL transparently.
---@param key string
---@return any value  The stored value, or nil if missing/expired.
---@return boolean hit  True if value was found and fresh.
local function raw_get(key)
  local slot = SLOT()
  local entry = slot[key]
  if entry == nil then
    return nil, false
  end

  if not ttl_enabled() then
    return entry, true
  end

  -- TTL-wrapped entry: { value = ..., expires_at = ... }
  if type(entry) == "table" and entry.expires_at ~= nil then
    if is_expired(entry) then
      slot[key] = nil
      bump "evictions"
      return nil, false
    end
    return entry.value, true
  end

  -- Legacy bare value (set before TTL was enabled).
  return entry, true
end

---Raw write into the cache slot, wrapping with TTL metadata when needed.
---@param key   string
---@param value any
---@param opts  table|nil  Per-call options `{ ttl = N }`.
local function raw_set(key, value, opts)
  local slot = SLOT()
  local ttl = effective_ttl(opts)
  if ttl then
    slot[key] = { value = value, expires_at = _cfg.clock() + ttl }
  else
    slot[key] = value
  end
end

---Count entries currently in the cache.
---@return integer
local function entry_count()
  local count = 0
  for _ in pairs(SLOT()) do
    count = count + 1
  end
  return count
end

---Evict entries if max_entries is set and exceeded.
---Prefers expired entries when TTL is enabled; otherwise picks an arbitrary
---victim ("expire-first" policy).
local function maybe_evict()
  if not _cfg.max_entries then
    return
  end
  while entry_count() >= _cfg.max_entries do
    -- Prefer expired entries first.
    local victim = nil
    if ttl_enabled() then
      for k, v in pairs(SLOT()) do
        if type(v) == "table" and v.expires_at and is_expired(v) then
          victim = k
          break
        end
      end
    end
    if not victim then
      -- Pick arbitrary entry.
      for k in pairs(SLOT()) do
        victim = k
        break
      end
    end
    if not victim then
      break
    end
    SLOT()[victim] = nil
    bump "evictions"
  end
end

-- ───────────────────────────────────────────────────────────────────────────
-- Public API
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.Cache
local M = {}

---Configure the cache.
---
---Merges the provided options into the current configuration.  Pass `false`
---for nullable fields (`ttl`, `max_entries`) to explicitly disable them.
---
---@param opts table  Partial config table (see `memo.cache.Config` fields).
function M.configure(opts)
  if not opts then
    return
  end
  for k, v in pairs(opts) do
    if _cfg_keys[k] then
      -- `false` on nullable fields means "set to nil / disable".
      if v == false and (k == "ttl" or k == "max_entries") then
        _cfg[k] = nil
      else
        _cfg[k] = v
      end
    end
  end
  if _cfg.stats then
    ensure_global_tbl(STATS_KEY, STATS_DEFAULT)
  end
end

---Reset all configuration to defaults.
---
---Intended for test teardown; not part of the normal public API.
function M._reset_config()
  _cfg.max_entries = nil
  _cfg.eviction = "expire-first"
  _cfg.ttl = nil
  _cfg.stats = false
  _cfg.debug = false
  _cfg.clock = os.time
end

---Retrieve a cached value.
---
---@param key string  Cache key.
---@return any|nil    Stored value or nil.
function M.get(key)
  local value, hit = raw_get(key)
  if hit then
    bump "hits"
  else
    bump "misses"
  end
  return value
end

---Store a value in the cache.
---
---Functions cannot be stored in `wezterm.GLOBAL`.  Attempting to store a
---function logs an error and returns without writing.
---
---@param key   string     Cache key.
---@param value any        Value to store (must not be a function).
---@param opts  table|nil  Per-call options `{ ttl = N }`.
function M.set(key, value, opts)
  if type(value) == "function" then
    wt.log_error(
      "[memo.cache] functions cannot be stored in wezterm.GLOBAL; "
        .. "use cache.compute() to cache the function's return value instead"
    )
    return
  end
  maybe_evict()
  raw_set(key, value, opts)
end

---Check whether a key exists and is fresh.
---
---@param key string  Cache key.
---@return boolean
function M.has(key)
  local _, hit = raw_get(key)
  return hit
end

---Delete a single cache entry.
---
---@param key string  Cache key.
function M.delete(key)
  SLOT()[key] = nil
end

---Clear cache entries.
---
---Without arguments, clears the entire cache.  With a selector table:
---- `{ prefix = "foo" }` — delete all keys starting with `"foo"`.
---- `{ older_than = N }` — delete entries older than N seconds (TTL mode).
---
---@param selector table|nil
function M.clear(selector)
  local slot = SLOT()
  if not selector then
    for k in pairs(slot) do
      slot[k] = nil
    end
    return
  end

  if selector.prefix then
    local prefix = selector.prefix
    local plen = #prefix
    for k in pairs(slot) do
      if k:sub(1, plen) == prefix then
        slot[k] = nil
      end
    end
  end

  if selector.older_than and ttl_enabled() then
    local cutoff = _cfg.clock() - selector.older_than
    for k, v in pairs(slot) do
      if type(v) == "table" and v.expires_at then
        local created = v.expires_at - (effective_ttl() or 0)
        if created < cutoff then
          slot[k] = nil
          bump "evictions"
        end
      end
    end
  end
end

---Mark a key as expired immediately.
---
---No-op when TTL is disabled.
---
---@param key string  Cache key.
function M.expire(key)
  if not ttl_enabled() then
    return
  end
  local entry = SLOT()[key]
  if type(entry) == "table" and entry.expires_at ~= nil then
    entry.expires_at = 0
  end
end

---Check whether a cached entry is still fresh.
---
---Always returns `true` when TTL is disabled (entries never expire).
---
---@param key string  Cache key.
---@return boolean
function M.is_fresh(key)
  if not ttl_enabled() then
    return SLOT()[key] ~= nil
  end
  local _, hit = raw_get(key)
  return hit
end

---Reset the TTL on an existing key (bump its expiry to now + default TTL).
---
---No-op when TTL is disabled or the key does not exist.
---
---@param key string  Cache key.
function M.touch(key)
  if not ttl_enabled() then
    return
  end
  local entry = SLOT()[key]
  if type(entry) == "table" and entry.expires_at ~= nil then
    local ttl = _cfg.ttl and _cfg.ttl.default
    if ttl then
      entry.expires_at = _cfg.clock() + ttl
    end
  end
end

---Execute a function and cache its result using an argument-derived key.
---
---Generates a deterministic key from `name` plus the serialised arguments,
---checks the cache first, and only calls `fn(...)` on a miss.
---
---@param name string              Namespace / context identifier.
---@param fn   fun(...: any): any  Function to execute on cache miss.
---@param ...  any                 Arguments forwarded to `fn`.
---@return any                     Cached or freshly computed result.
function M.compute(name, fn, ...)
  local key = make_cache_key(name, ...)
  local value, hit = raw_get(key)
  if hit then
    bump "hits"
    return value
  end
  bump "misses"
  local ok, res = pcall(fn, ...)
  if not ok then
    error(res)
  end
  maybe_evict()
  raw_set(key, res)
  return res
end

---Return all cache keys, optionally filtered.
---
---@param selector table|nil  `{ prefix = "foo" }` to filter.
---@return string[]
function M.keys(selector)
  local result = {}
  local prefix = selector and selector.prefix
  for k in pairs(SLOT()) do
    if not prefix or k:sub(1, #prefix) == prefix then
      result[#result + 1] = k
    end
  end
  return result
end

---Return cache statistics.
---
---Only meaningful when `configure({ stats = true })` has been called.
---Returns a table with `hits`, `misses`, `evictions`, and `entries`.
---
---@return table
function M.stats()
  local st = wt.GLOBAL[STATS_KEY] or STATS_DEFAULT
  st.entries = entry_count()
  return st
end

-- ───────────────────────────────────────────────────────────────────────────
-- Namespace wrapper
-- ───────────────────────────────────────────────────────────────────────────

---@class memo.cache.Namespace
---@field _prefix string

---Create a namespaced cache wrapper.
---
---All keys are automatically prefixed with `name .. ":"`.  The returned
---wrapper exposes the same API as `memo.cache` but scoped to the prefix.
---
---@param name string  Namespace identifier.
---@return memo.cache.Namespace
function M.namespace(name)
  local prefix = name .. ":"

  ---@class memo.cache.Namespace
  local ns = { _prefix = prefix }

  function ns.get(key)
    return M.get(prefix .. key)
  end

  function ns.set(key, value, opts)
    return M.set(prefix .. key, value, opts)
  end

  function ns.has(key)
    return M.has(prefix .. key)
  end

  function ns.delete(key)
    return M.delete(prefix .. key)
  end

  function ns.compute(ns_name, fn, ...)
    return M.compute(prefix .. ns_name, fn, ...)
  end

  function ns.expire(key)
    return M.expire(prefix .. key)
  end

  function ns.is_fresh(key)
    return M.is_fresh(prefix .. key)
  end

  function ns.touch(key)
    return M.touch(prefix .. key)
  end

  function ns.clear(selector)
    M.clear { prefix = prefix .. (selector and selector.prefix or "") }
  end

  function ns.keys(selector)
    local sel = { prefix = prefix .. (selector and selector.prefix or "") }
    local raw_keys = M.keys(sel)
    local result = {}
    local plen = #prefix
    for i = 1, #raw_keys do
      result[i] = raw_keys[i]:sub(plen + 1)
    end
    return result
  end

  return ns
end

-- ───────────────────────────────────────────────────────────────────────────
-- Exported internals for sibling modules
-- ───────────────────────────────────────────────────────────────────────────

M._ensure_global_tbl = ensure_global_tbl
M._sync_to_global = sync_to_global

return M
