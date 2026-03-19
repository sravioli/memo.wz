---@module "memo.key"

---Deterministic cache-key generation via serialization and concatenation.
---
---Each Lua value is converted to an unambiguous string representation and
---the parts are joined with `|`.  This avoids the overhead of hashing while
---still producing compact, collision-free keys.

local tconcat, tinsert, tsort = table.concat, table.insert, table.sort
local sformat = string.format

-- ───────────────────────────────────────────────────────────────────────────
-- Value serialization
-- ───────────────────────────────────────────────────────────────────────────

---Serialize any Lua value into a deterministic string representation.
---
---Tables are serialized recursively with sorted keys.  Cyclic references
---produce the sentinel `"<cycle>"` instead of looping.
---
---@param v    any
---@param seen table<table, boolean>|nil  Cycle-detection set (internal).
---@return string
local function serialize(v, seen)
  local t = type(v)

  if t == "string" then
    return sformat("%q", v)
  elseif t == "number" then
    if math.type(v) == "integer" then
      return sformat("%d", v)
    end
    return sformat("%.17g", v)
  elseif t == "boolean" then
    return v and "T" or "F"
  elseif t == "nil" then
    return "N"
  elseif t == "table" then
    seen = seen or {}
    if seen[v] then
      return "<cycle>"
    end
    seen[v] = true

    local keys = {}
    for k in pairs(v) do
      tinsert(keys, k)
    end
    tsort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)

    local parts = {}
    for i = 1, #keys do
      local k = keys[i]
      parts[#parts + 1] = serialize(k, seen) .. "=" .. serialize(v[k], seen)
    end
    return "{" .. tconcat(parts, ",") .. "}"
  end

  -- function, thread, userdata: use address string (session-stable).
  return tostring(v)
end

-- ───────────────────────────────────────────────────────────────────────────
-- Key generation
-- ───────────────────────────────────────────────────────────────────────────

---Generate a deterministic cache key from a name and variadic arguments.
---
---String arguments are included verbatim; all other types are serialized.
---Parts are joined with `|`.
---
---@param name string  Namespace / context identifier.
---@param ...  any     Arguments that parameterise the cached computation.
---@return string      Deterministic cache key.
local function make_cache_key(name, ...)
  local n = select("#", ...)
  if n == 0 then
    return name
  end

  local parts = { name }
  for i = 1, n do
    local arg = select(i, ...)
    if type(arg) == "string" then
      parts[#parts + 1] = arg
    else
      parts[#parts + 1] = serialize(arg)
    end
  end
  return tconcat(parts, "|")
end

-- ───────────────────────────────────────────────────────────────────────────
-- Module exports
-- ───────────────────────────────────────────────────────────────────────────

return {
  serialize = serialize,
  make_cache_key = make_cache_key,
}
