---@module "memo.hash"

---XXH3-64 pure Lua 5.4 implementation and recursive value hasher.
---
---All arithmetic uses Lua 5.4 native 64-bit integers with bitwise
---operators; overflow wraps by two's complement (well-defined).
---
---Reference: https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md

local tconcat, tinsert = table.concat, table.insert
local spack, sunpack = string.pack, string.unpack
local sbyte, sformat = string.byte, string.format

-- ───────────────────────────────────────────────────────────────────────────
-- XXH3-64 — constants
-- ───────────────────────────────────────────────────────────────────────────

local PRIME32_1 = 0x9E3779B1
local PRIME32_3 = 0xC2B2AE3D
local PRIME64_1 = -7046029288634856825 -- 0x9E3779B185EBCA87
local PRIME64_2 = -4417276706812531889 -- 0xC2B2AE63A9653039
local PRIME64_3 = 1609587929392839161 -- 0x165667B19E3779F9
local PRIME64_4 = -8796714831421723037 -- 0x85EBCA77C2B2AE63
local PRIME64_5 = 2870177450012600261 -- 0x27D4EB2F165667C5

-- XXH3 default secret (first 192 bytes).
-- Stored as an array of 24 little-endian u64 values.
local SECRET = {
  -- bytes   0 ..  7
  -5822052841892925955, -- 0xbe4ba423396cfeb8
  -- bytes   8 .. 15
  1444865580509498491, -- 0x1410b3b4a6779a5b
  -- bytes  16 .. 23
  -6542264093376190578, -- 0xa54da0b23bbea18e
  -- bytes  24 .. 31
  6988290926392491466, -- 0x60fd6ba2ba01cfba
  -- bytes  32 .. 39
  -3582311088966905919, -- 0xce3a5e0bb3678ac1
  -- bytes  40 .. 47
  -7457439547111561438, -- 0x987015f0249082a2
  -- bytes  48 .. 55
  -3395649979973498866, -- 0xd0d6050c9e36a02e
  -- bytes  56 .. 63
  4622759000209698900, -- 0x401d838e0c483954
  -- bytes  64 .. 71
  -3305543879768427099, -- 0xd2189014e65cd7a5
  -- bytes  72 .. 79
  -6509227436032551467, -- 0xa5824524c0820765
  -- bytes  80 .. 87
  -1383839843175874536, -- 0xecc8089b03f97118
  -- bytes  88 .. 95
  2149089783498709474, -- 0x1dd2fa23dc7d5fe2
  -- bytes  96 ..103
  -4948223005436068853, -- 0xbb4fbb5a82e842fb
  -- bytes 104 ..111
  -6624011813498908862, -- 0xa41a4110db874be2
  -- bytes 112 ..119
  5285098773195972901, -- 0x495f0b75f7b4c5a5
  -- bytes 120 ..127
  4665826030398261421, -- 0x40b419cc6b982e2d
  -- bytes 128 ..135
  -6609747919040849669, -- 0xa42407cb03a14b0b
  -- bytes 136 ..143
  -3232335909110927445, -- 0xd345189c15bd6b2b
  -- bytes 144 ..151
  4478501005706048723, -- 0x3e2f5c0f7b5e2ed3
  -- bytes 152 ..159
  -3651780025157792137, -- 0xcd58458997e18577
  -- bytes 160 ..167
  1861459776989897976, -- 0x19df1ed1aae08af8
  -- bytes 168 ..175
  7579933567654778923, -- 0x6927fae64c47baab
  -- bytes 176 ..183
  -8207883812393069007, -- 0x8e3f40b3a39d3331
  -- bytes 184 ..191
  4767371653420968462, -- 0x422257cc8463100e
}

-- Rebuild the secret as a flat string for sub-byte reads.
local SECRET_STR
do
  local parts = {}
  for i = 1, #SECRET do
    parts[i] = spack("<i8", SECRET[i])
  end
  SECRET_STR = tconcat(parts)
end

-- ───────────────────────────────────────────────────────────────────────────
-- Low-level helpers
-- ───────────────────────────────────────────────────────────────────────────

---Read a little-endian u32 from position `p` in string `s`.
---@param s string
---@param p integer 1-based byte position
---@return integer
local function read32(s, p)
  return (sunpack("<I4", s, p))
end

---Read a little-endian u64 from position `p` in string `s`.
---The result is a signed i64 (Lua 5.4 integer).
---@param s string
---@param p integer 1-based byte position
---@return integer
local function read64(s, p)
  return (sunpack("<i8", s, p))
end

---Read a little-endian u64 from the secret at byte offset `off` (0-based).
---@param off integer 0-based byte offset into the secret
---@return integer
local function secret64(off)
  return (sunpack("<i8", SECRET_STR, off + 1))
end

---Read a little-endian u32 from the secret at byte offset `off` (0-based).
---@param off integer 0-based byte offset into the secret
---@return integer
local function secret32(off)
  return (sunpack("<I4", SECRET_STR, off + 1))
end

---Multiply two i64 values and return the full 128-bit product as (lo, hi).
---Pure Lua 5.4: split each operand into 32-bit halves, compute 4 partial
---products, and recombine. Overflow in the lo part is handled by discarding
---the upper bits naturally (i64 wrap).
---@param a integer
---@param b integer
---@return integer lo  Lower 64 bits
---@return integer hi  Upper 64 bits
local function mul128(a, b)
  local a_lo = a & 0xFFFFFFFF
  local a_hi = (a >> 32) & 0xFFFFFFFF
  local b_lo = b & 0xFFFFFFFF
  local b_hi = (b >> 32) & 0xFFFFFFFF

  local ll = a_lo * b_lo
  local lh = a_lo * b_hi
  local hl = a_hi * b_lo
  local hh = a_hi * b_hi

  local lo = ll + ((lh & 0xFFFFFFFF) << 32) + ((hl & 0xFFFFFFFF) << 32)
  local carry = ((ll >> 32) + (lh & 0xFFFFFFFF) + (hl & 0xFFFFFFFF)) >> 32
  local hi = hh + (lh >> 32) + (hl >> 32) + carry
  return lo, hi
end

---XXH3 mul128_fold64: multiply two 64-bit values, return lo XOR hi.
---@param a integer
---@param b integer
---@return integer
local function mul128_fold(a, b)
  local lo, hi = mul128(a, b)
  return lo ~ hi
end

---XXH3 avalanche / bit mixer.
---@param h integer
---@return integer
local function xxh3_avalanche(h)
  h = h ~ (h >> 37)
  h = h * PRIME64_4 -- 0x85EBCA77C2B2AE63
  h = h ~ (h >> 32)
  return h
end

---rrmxmx finalizer used for lengths 1-3.
---@param h integer
---@return integer
local function xxh3_rrmxmx(h, len)
  h = h ~ ((h >> 49) ~ (h >> 24))
  h = h * PRIME64_2 -- 0xC2B2AE63A9653039
  h = h ~ ((h >> 35) + len)
  h = h * PRIME64_2
  h = h ~ (h >> 28)
  return h
end

-- ───────────────────────────────────────────────────────────────────────────
-- xxh3_64
-- ───────────────────────────────────────────────────────────────────────────

---XXH3-64 hash of a string.
---
---Implements the complete XXH3 64-bit algorithm with the default secret for
---all input sizes.  All arithmetic uses Lua 5.4 native 64-bit integers with
---bitwise operators; overflow wraps by two's complement (well-defined).
---
---@param input string
---@return integer  64-bit hash as a Lua integer (signed i64)
local function xxh3_64(input)
  local len = #input

  -- ── len == 0 ────────────────────────────────────────────────────────
  if len == 0 then
    return xxh3_avalanche(secret64(56) ~ secret64(64))
  end

  -- ── 1 <= len <= 3 ──────────────────────────────────────────────────
  if len <= 3 then
    local b1 = sbyte(input, 1)
    local b2 = sbyte(input, (len >> 1) + 1)
    local b3 = sbyte(input, len)
    local combined = (b1 << 16) | (len << 8) | b3
    local combined64 = combined | (b2 << 24)
    return xxh3_rrmxmx((secret32(0) ~ secret32(4)) * 1 + combined64, len)
  end

  -- ── 4 <= len <= 8 ──────────────────────────────────────────────────
  if len <= 8 then
    local lo = read32(input, 1)
    local hi = read32(input, len - 3) -- overlapping read
    local combined = lo | (hi << 32)
    local s = (secret64(8) ~ secret64(16))
    local bitflip = s
    return xxh3_rrmxmx(
      (bitflip ~ combined) * 1, -- XXH3_INIT_ACC disabled for short
      len
    )
  end

  -- ── 9 <= len <= 16 ─────────────────────────────────────────────────
  if len <= 16 then
    local lo = read64(input, 1)
    local hi = read64(input, len - 7)
    local bitflip_lo = secret64(24) ~ secret64(32)
    local bitflip_hi = secret64(40) ~ secret64(48)
    local input_lo = lo ~ bitflip_lo
    local input_hi = hi ~ bitflip_hi
    local acc = len + input_lo + input_hi + mul128_fold(input_lo, input_hi)
    return xxh3_avalanche(acc)
  end

  -- ── 17 <= len <= 128 ───────────────────────────────────────────────
  if len <= 128 then
    local acc = len * PRIME64_1
    local nb_rounds = ((len - 1) >> 5) -- 0..3
    for i = 0, nb_rounds do
      local off = i * 16
      local lo = read64(input, 1 + off)
      local hi = read64(input, 1 + off + 8)
      acc = acc + mul128_fold(lo ~ secret64(off * 2), hi ~ secret64(off * 2 + 8))

      -- mirror read from end
      local e_off = len - (i + 1) * 16
      local elo = read64(input, 1 + e_off)
      local ehi = read64(input, 1 + e_off + 8)
      acc = acc + mul128_fold(elo ~ secret64(off * 2 + 16), ehi ~ secret64(off * 2 + 24))
    end
    return xxh3_avalanche(acc)
  end

  -- ── 129 <= len <= 240 ──────────────────────────────────────────────
  if len <= 240 then
    local acc = len * PRIME64_1
    for i = 0, 7 do
      local off = i * 16
      local lo = read64(input, 1 + off)
      local hi = read64(input, 1 + off + 8)
      acc = acc + mul128_fold(lo ~ secret64(off), hi ~ secret64(off + 8))
    end
    acc = xxh3_avalanche(acc)

    local nb_extra = ((len - 128) >> 4) -- rounds beyond the first 128 bytes
    for i = 0, nb_extra - 1 do
      local off = 128 + i * 16
      local s_off = 3 + i * 16 -- secret offset for rounds 8+
      local lo = read64(input, 1 + off)
      local hi = read64(input, 1 + off + 8)
      acc = acc + mul128_fold(lo ~ secret64(s_off), hi ~ secret64(s_off + 8))
    end

    return xxh3_avalanche(acc)
  end

  -- ── len > 240: stripe-based accumulation ───────────────────────────
  local acc_lanes = {
    PRIME32_3,
    PRIME64_1,
    PRIME64_2,
    PRIME64_3,
    PRIME64_4,
    PRIME64_5,
    -PRIME64_1,
    -PRIME64_2,
  }

  local STRIPE_LEN = 64
  local NB_KEYS = ((192 - 64) >> 3) + 1 -- 17
  local block_len = STRIPE_LEN * NB_KEYS -- 1088
  local nb_blocks = (len - 1) // block_len

  ---Accumulate one 64-byte stripe into the 8 lanes.
  ---@param base integer  1-based byte position in input.
  ---@param sk   integer  0-based byte offset into the secret (stride 8 per stripe).
  local function accumulate_stripe(base, sk)
    for j = 0, 7 do
      local data = read64(input, base + j * 8)
      local key = secret64(sk + j * 8)
      local mixed = data ~ key
      local data_next = read64(input, base + ((j ~ 1) * 8))
      acc_lanes[j + 1] = acc_lanes[j + 1] + mul128_fold(mixed, data_next)
    end
  end

  ---Scramble the 8 lanes using the secret at the given offset.
  ---@param off integer  0-based byte offset into the secret (128 for default).
  local function scramble_acc(off)
    for j = 0, 7 do
      local a = acc_lanes[j + 1]
      a = (a ~ (a >> 47) ~ secret64(off + j * 8)) * PRIME32_1
      acc_lanes[j + 1] = a
    end
  end

  for n = 0, nb_blocks - 1 do
    for s = 0, NB_KEYS - 1 do
      accumulate_stripe(n * block_len + s * STRIPE_LEN + 1, s * 8)
    end
    scramble_acc(128)
  end

  -- Remaining stripes after the last full block.
  local nb_stripes = ((len - 1 - nb_blocks * block_len) // STRIPE_LEN)
  for s = 0, nb_stripes - 1 do
    accumulate_stripe(nb_blocks * block_len + s * STRIPE_LEN + 1, s * 8)
  end

  -- Last stripe: aligned to end of input, uses secret offset 121.
  accumulate_stripe(len - STRIPE_LEN + 1, 121)

  -- Merge the 8 lanes into a single result.
  local result = len * PRIME64_1
  for j = 0, 7 do
    result = result + mul128_fold(acc_lanes[j + 1], secret64(11 + j * 8))
  end
  return xxh3_avalanche(result)
end

-- ───────────────────────────────────────────────────────────────────────────
-- hash_any — recursive value hasher (no intermediate strings)
-- ───────────────────────────────────────────────────────────────────────────

-- Pre-computed constants for primitive types.
local HASH_NIL = xxh3_64 "nil"
local HASH_TRUE = xxh3_64 "\1"
local HASH_FALSE = xxh3_64 "\0"

---Mix a 64-bit hash value for better avalanche.
---@param h integer
---@return integer
local function mix64(h)
  h = h ~ (h >> 37)
  h = h * PRIME64_2
  h = h ~ (h >> 32)
  return h
end

---Compute a 64-bit hash of any Lua value (recursive, cycle-safe).
---
---Returns a Lua integer (signed i64) directly — no intermediate string is
---ever allocated.  Tables are hashed by sorting their keys for determinism;
---cyclic references produce a fixed sentinel instead of looping.
---
---@param v    any
---@param seen table<table, boolean>|nil  Cycle-detection set (internal).
---@return integer
local function hash_any(v, seen)
  local t = type(v)

  if t == "nil" then
    return HASH_NIL
  elseif t == "boolean" then
    return v and HASH_TRUE or HASH_FALSE
  elseif t == "number" then
    return xxh3_64(spack("<d", v))
  elseif t == "string" then
    return xxh3_64(v)
  elseif t == "table" then
    seen = seen or {}
    if seen[v] then
      return 0
    end
    seen[v] = true

    local keys = {}
    for k in pairs(v) do
      tinsert(keys, k)
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)

    local h = PRIME64_3 -- seed for table hashing
    for i = 1, #keys do
      local k = keys[i]
      h = mix64(h ~ hash_any(k, seen))
      h = h ~ mix64(hash_any(v[k], seen))
    end
    return h
  end

  -- function, thread, userdata: hash the address string (session-stable)
  return xxh3_64(tostring(v))
end

-- ───────────────────────────────────────────────────────────────────────────
-- Key generation
-- ───────────────────────────────────────────────────────────────────────────

---Generate a deterministic cache key from a name and variadic arguments.
---
---Fast path: when all arguments are strings the key is a readable pipe-
---delimited string (`"name|arg1|arg2"`).  Slow path: non-string arguments
---are hashed via `hash_any` and formatted as 16-char hex.
---
---@param name string  Namespace / context identifier.
---@param ...  any     Arguments that parameterise the cached computation.
---@return string      Deterministic cache key.
local function make_cache_key(name, ...)
  local n = select("#", ...)
  if n == 0 then
    return name
  end

  -- Fast path: all args are strings (the overwhelmingly common case).
  local all_str = true
  for i = 1, n do
    if type(select(i, ...)) ~= "string" then
      all_str = false
      break
    end
  end

  if all_str then
    local parts = { name }
    for i = 1, n do
      parts[#parts + 1] = select(i, ...)
    end
    return tconcat(parts, "|")
  end

  -- Slow path: hash non-string args.
  local parts = { name }
  for i = 1, n do
    local arg = select(i, ...)
    if type(arg) == "string" then
      parts[#parts + 1] = arg
    else
      parts[#parts + 1] = sformat("%016x", hash_any(arg))
    end
  end
  return tconcat(parts, "|")
end

-- ───────────────────────────────────────────────────────────────────────────
-- Module exports
-- ───────────────────────────────────────────────────────────────────────────

return {
  xxh3_64 = xxh3_64,
  hash_any = hash_any,
  make_cache_key = make_cache_key,
}
