---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local key = require "memo.key"

describe("memo.key", function()
  -- ─────────────────────────────────────────────────────────────────────
  -- serialize
  -- ─────────────────────────────────────────────────────────────────────

  describe("serialize", function()
    local serialize = key.serialize

    it("serializes strings with quoting", function()
      assert.are.equal('"hello"', serialize "hello")
    end)

    it("serializes integers", function()
      assert.are.equal("42", serialize(42))
      assert.are.equal("-1", serialize(-1))
      assert.are.equal("0", serialize(0))
    end)

    it("serializes floats with full precision", function()
      local s = serialize(3.14)
      assert.are.equal("string", type(s))
      assert.are.equal(3.14, tonumber(s))
    end)

    it("serializes booleans", function()
      assert.are.equal("T", serialize(true))
      assert.are.equal("F", serialize(false))
    end)

    it("serializes nil", function()
      assert.are.equal("N", serialize(nil))
    end)

    it("serializes empty tables", function()
      assert.are.equal("{}", serialize {})
    end)

    it("serializes flat tables deterministically", function()
      local t1 = { a = 1, b = 2 }
      local t2 = { b = 2, a = 1 }
      assert.are.equal(serialize(t1), serialize(t2))
    end)

    it("serializes nested tables", function()
      local t = { a = { b = 1 } }
      local s = serialize(t)
      assert.is_truthy(s:find "{")
      assert.are.equal(serialize(t), serialize { a = { b = 1 } })
    end)

    it("handles cyclic tables without infinite loop", function()
      local t = {}
      t.self = t
      local s = serialize(t)
      assert.is_truthy(s:find "<cycle>")
    end)

    it("handles mutual cycles", function()
      local a, b = {}, {}
      a.other = b
      b.other = a
      local s = serialize(a)
      assert.are.equal("string", type(s))
      assert.is_truthy(s:find "<cycle>")
    end)

    it("serializes functions via tostring fallback", function()
      local fn = function() end
      local s = serialize(fn)
      assert.are.equal("string", type(s))
      -- tostring(fn) produces something like "function: 0x...".
      assert.is_truthy(s:find "^function")
    end)

    it("serializes tables with mixed key types deterministically", function()
      local t = { [1] = "a", ["x"] = "b", [true] = "c" }
      local s1 = serialize(t)
      local s2 = serialize(t)
      assert.are.equal(s1, s2)
      assert.is_truthy(s1:find "{")
    end)

    it("serializes deeply nested tables", function()
      local t = { a = { b = { c = { d = 1 } } } }
      local s = serialize(t)
      assert.are.equal(serialize { a = { b = { c = { d = 1 } } } }, s)
    end)

    it("different values produce different strings", function()
      assert.are_not.equal(serialize(true), serialize(false))
      assert.are_not.equal(serialize(nil), serialize(false))
      assert.are_not.equal(serialize(0), serialize(false))
      assert.are_not.equal(serialize "1", serialize(1))
      assert.are_not.equal(serialize { a = 1 }, serialize { a = 2 })
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- make_cache_key
  -- ─────────────────────────────────────────────────────────────────────

  describe("make_cache_key", function()
    local make_key = key.make_cache_key

    it("returns name alone when no args", function()
      assert.are.equal("foo", make_key "foo")
    end)

    it("joins string args with pipe", function()
      assert.are.equal("ns|a|b", make_key("ns", "a", "b"))
    end)

    it("serializes non-string args", function()
      local k = make_key("ns", 42)
      assert.are.equal("ns|42", k)
    end)

    it("serializes boolean args", function()
      assert.are.equal("ns|T", make_key("ns", true))
      assert.are.equal("ns|F", make_key("ns", false))
    end)

    it("serializes table args", function()
      local k = make_key("ns", { a = 1 })
      assert.is_truthy(k:find "^ns|{")
    end)

    it("is deterministic for mixed args", function()
      local k1 = make_key("ns", "a", { x = 1 })
      local k2 = make_key("ns", "a", { x = 1 })
      assert.are.equal(k1, k2)
    end)

    it("different args produce different keys", function()
      local k1 = make_key("ns", "a")
      local k2 = make_key("ns", "b")
      assert.are_not.equal(k1, k2)
    end)

    it("single string arg joins with pipe", function()
      assert.are.equal("ns|only", make_key("ns", "only"))
    end)

    it("multiple non-string args all serialized", function()
      local k = make_key("fn", 1, true, { a = 1 })
      local parts = {}
      for p in k:gmatch "[^|]+" do
        parts[#parts + 1] = p
      end
      assert.are.equal(4, #parts)
      assert.are.equal("fn", parts[1])
      assert.are.equal("1", parts[2])
      assert.are.equal("T", parts[3])
    end)

    it("handles nil arguments via serialize", function()
      local k = make_key("ns", nil)
      assert.are.equal("ns|N", k)
    end)

    it("handles function arguments via serialize", function()
      local fn = function() end
      local k = make_key("ns", fn)
      assert.is_truthy(k:find "^ns|function")
    end)
  end)
end)
