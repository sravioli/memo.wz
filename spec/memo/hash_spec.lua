---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local hash = require "memo.hash"

describe("memo.hash", function()
  -- ─────────────────────────────────────────────────────────────────────
  -- xxh3_64
  -- ─────────────────────────────────────────────────────────────────────

  describe("xxh3_64", function()
    local xxh3 = hash.xxh3_64

    it("returns an integer", function()
      assert.are.equal("number", type(xxh3 "hello"))
      assert.are.equal(math.type(xxh3 "hello"), "integer")
    end)

    it("is deterministic", function()
      assert.are.equal(xxh3 "test", xxh3 "test")
    end)

    it("produces different hashes for different inputs", function()
      assert.are_not.equal(xxh3 "foo", xxh3 "bar")
    end)

    it("handles empty string", function()
      local h = xxh3 ""
      assert.are.equal("number", type(h))
    end)

    it("handles short strings (1-3 bytes)", function()
      assert.are.equal("number", type(xxh3 "a"))
      assert.are.equal("number", type(xxh3 "ab"))
      assert.are.equal("number", type(xxh3 "abc"))
    end)

    it("handles medium strings (4-16 bytes)", function()
      assert.are.equal("number", type(xxh3 "abcd"))
      assert.are.equal("number", type(xxh3 "abcdefgh"))
      assert.are.equal("number", type(xxh3 "abcdefghijklmnop"))
    end)

    it("handles larger strings (17-128 bytes)", function()
      local s = ("x"):rep(64)
      assert.are.equal("number", type(xxh3(s)))
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("handles strings 129-240 bytes", function()
      local s = ("y"):rep(200)
      assert.are.equal("number", type(xxh3(s)))
    end)

    it("handles strings > 240 bytes", function()
      local s = ("z"):rep(500)
      assert.are.equal("number", type(xxh3(s)))
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    -- Boundary-length tests: exact transition points between code paths.
    it("boundary: 3 bytes (upper edge of 1-3 path)", function()
      assert.are.equal(xxh3 "xyz", xxh3 "xyz")
      assert.are_not.equal(xxh3 "xyz", xxh3 "abc")
    end)

    it("boundary: 4 bytes (lower edge of 4-8 path)", function()
      assert.are.equal(xxh3 "abcd", xxh3 "abcd")
      assert.are_not.equal(xxh3 "abcd", xxh3 "abce")
    end)

    it("boundary: 8 bytes (upper edge of 4-8 path)", function()
      assert.are.equal(xxh3 "12345678", xxh3 "12345678")
      assert.are_not.equal(xxh3 "12345678", xxh3 "12345679")
    end)

    it("boundary: 9 bytes (lower edge of 9-16 path)", function()
      assert.are.equal(xxh3 "123456789", xxh3 "123456789")
    end)

    it("boundary: 16 bytes (upper edge of 9-16 path)", function()
      local s = ("a"):rep(16)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("boundary: 17 bytes (lower edge of 17-128 path)", function()
      local s = ("b"):rep(17)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("boundary: 128 bytes (upper edge of 17-128 path)", function()
      local s = ("c"):rep(128)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("boundary: 129 bytes (lower edge of 129-240 path)", function()
      local s = ("d"):rep(129)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("boundary: 240 bytes (upper edge of 129-240 path)", function()
      local s = ("e"):rep(240)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("boundary: 241 bytes (lower edge of >240 path)", function()
      local s = ("f"):rep(241)
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("handles multi-block strings > 1088 bytes", function()
      local s = ("g"):rep(2000)
      assert.are.equal("number", type(xxh3(s)))
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("handles very large strings > 3000 bytes", function()
      local s = ("h"):rep(3200)
      assert.are.equal("number", type(xxh3(s)))
      assert.are.equal(xxh3(s), xxh3(s))
    end)

    it("different content at same length produces different hashes", function()
      local a = ("a"):rep(100)
      local b = ("b"):rep(100)
      assert.are_not.equal(xxh3(a), xxh3(b))
    end)

    it("single-byte strings are all distinct", function()
      local seen = {}
      for i = 0, 255 do
        local h = xxh3(string.char(i))
        assert.is_nil(seen[h], "collision at byte " .. i)
        seen[h] = true
      end
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- hash_any
  -- ─────────────────────────────────────────────────────────────────────

  describe("hash_any", function()
    local hash_any = hash.hash_any

    it("hashes nil", function()
      assert.are.equal("number", type(hash_any(nil)))
    end)

    it("hashes booleans distinctly", function()
      assert.are_not.equal(hash_any(true), hash_any(false))
    end)

    it("hashes numbers", function()
      assert.are.equal(hash_any(42), hash_any(42))
      assert.are_not.equal(hash_any(42), hash_any(43))
    end)

    it("hashes strings", function()
      assert.are.equal(hash_any "foo", hash_any "foo")
      assert.are_not.equal(hash_any "foo", hash_any "bar")
    end)

    it("hashes tables deterministically", function()
      local t1 = { a = 1, b = 2 }
      local t2 = { b = 2, a = 1 } -- same content, different insertion order
      assert.are.equal(hash_any(t1), hash_any(t2))
    end)

    it("handles cyclic tables without infinite loop", function()
      local t = {}
      t.self = t
      assert.are.equal("number", type(hash_any(t)))
    end)

    it("hashes empty tables", function()
      assert.are.equal("number", type(hash_any {}))
    end)

    it("empty tables hash the same", function()
      assert.are.equal(hash_any {}, hash_any {})
    end)

    it("different tables produce different hashes", function()
      assert.are_not.equal(hash_any { a = 1 }, hash_any { a = 2 })
    end)

    it("nested tables are hashed", function()
      local t1 = { a = { b = { c = 1 } } }
      local t2 = { a = { b = { c = 1 } } }
      assert.are.equal(hash_any(t1), hash_any(t2))
    end)

    it("nested tables with different values differ", function()
      local t1 = { a = { b = 1 } }
      local t2 = { a = { b = 2 } }
      assert.are_not.equal(hash_any(t1), hash_any(t2))
    end)

    it("nil hashes differently from false", function()
      assert.are_not.equal(hash_any(nil), hash_any(false))
    end)

    it("integer 0 hashes differently from false", function()
      assert.are_not.equal(hash_any(0), hash_any(false))
    end)

    it("hashes floats", function()
      assert.are.equal(hash_any(3.14), hash_any(3.14))
      assert.are_not.equal(hash_any(3.14), hash_any(2.71))
    end)

    it("mutual cycles produce a result", function()
      local a, b = {}, {}
      a.other = b
      b.other = a
      assert.are.equal("number", type(hash_any(a)))
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- make_cache_key
  -- ─────────────────────────────────────────────────────────────────────

  describe("make_cache_key", function()
    local make_key = hash.make_cache_key

    it("returns name alone when no args", function()
      assert.are.equal("foo", make_key "foo")
    end)

    it("joins string args with pipe", function()
      assert.are.equal("ns|a|b", make_key("ns", "a", "b"))
    end)

    it("hashes non-string args as hex", function()
      local key = make_key("ns", 42)
      assert.is_truthy(key:match "^ns|%x+$")
    end)

    it("is deterministic for mixed args", function()
      local k1 = make_key("ns", "a", { x = 1 })
      local k2 = make_key("ns", "a", { x = 1 })
      assert.are.equal(k1, k2)
    end)

    it("single string arg joins with pipe", function()
      assert.are.equal("ns|only", make_key("ns", "only"))
    end)

    it("multiple non-string args all hashed as hex", function()
      local key = make_key("fn", 1, true, { a = 1 })
      -- name + 3 hex chunks
      local parts = {}
      for p in key:gmatch "[^|]+" do
        parts[#parts + 1] = p
      end
      assert.are.equal(4, #parts)
      assert.are.equal("fn", parts[1])
      for i = 2, 4 do
        assert.is_truthy(parts[i]:match "^%x+$")
      end
    end)

    it("boolean args use slow path", function()
      local key = make_key("ns", true)
      assert.is_truthy(key:match "^ns|%x+$")
    end)

    it("different args produce different keys", function()
      local k1 = make_key("ns", "a")
      local k2 = make_key("ns", "b")
      assert.are_not.equal(k1, k2)
    end)
  end)
end)
