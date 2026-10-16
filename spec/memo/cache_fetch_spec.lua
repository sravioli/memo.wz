---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local cache = require "memo.cache"
local wt = require "wezterm"

describe("memo.cache fetch / compute_with / plain", function()
  local now

  before_each(function()
    wt._reset()
    cache._reset_config()
    cache.clear()
    now = 1000
    cache.configure {
      clock = function()
        return now
      end,
    }
  end)

  describe("fetch", function()
    it("calls fn once and serves hits from the cache", function()
      local calls = 0
      local fn = function()
        calls = calls + 1
        return "v"
      end
      assert.are.equal("v", cache.fetch("k", fn))
      assert.are.equal("v", cache.fetch("k", fn))
      assert.are.equal(1, calls)
    end)

    it("recomputes after the per-call ttl expires", function()
      local calls = 0
      local fn = function()
        calls = calls + 1
        return calls
      end
      assert.are.equal(1, cache.fetch("k", fn, { ttl = 10 }))
      now = 1005
      assert.are.equal(1, cache.fetch("k", fn, { ttl = 10 }))
      now = 1010
      assert.are.equal(2, cache.fetch("k", fn, { ttl = 10 }))
    end)

    it("bypasses the cache when ttl is 0", function()
      local calls = 0
      local fn = function()
        calls = calls + 1
        return calls
      end
      cache.fetch("k", fn, { ttl = 0 })
      cache.fetch("k", fn, { ttl = 0 })
      assert.are.equal(2, calls)
      assert.is_false(cache.has "k")
    end)

    it("does not cache nil results", function()
      local calls = 0
      local fn = function()
        calls = calls + 1
      end
      cache.fetch("k", fn)
      cache.fetch("k", fn)
      assert.are.equal(2, calls)
    end)

    it("propagates errors without caching", function()
      assert.has_error(function()
        cache.fetch("k", function()
          error "boom"
        end)
      end)
      assert.is_false(cache.has "k")
    end)

    it("returns independent plain copies when asked", function()
      local a = cache.fetch("k", function()
        return { list = { 1, 2 } }
      end, { plain = true })
      a.list[1] = 99
      local b = cache.fetch("k", function()
        error "should hit"
      end, { plain = true })
      assert.are.same({ list = { 1, 2 } }, b)
    end)
  end)

  describe("compute_with", function()
    it("keys by arguments and forwards them, nils included", function()
      local seen = {}
      local fn = function(a, b, c)
        seen[#seen + 1] = { a, b, c }
        return (a or 0) + (c or 0)
      end
      assert.are.equal(3, cache.compute_with("add", nil, fn, 1, nil, 2))
      assert.are.equal(3, cache.compute_with("add", nil, fn, 1, nil, 2))
      assert.are.equal(5, cache.compute_with("add", nil, fn, 2, nil, 3))
      assert.are.equal(2, #seen)
      assert.are.same({ 1, nil, 2 }, seen[1])
    end)

    it("honours ttl", function()
      local calls = 0
      local fn = function()
        calls = calls + 1
        return calls
      end
      cache.compute_with("n", { ttl = 5 }, fn)
      now = 1005
      assert.are.equal(2, cache.compute_with("n", { ttl = 5 }, fn))
    end)
  end)

  describe("namespace", function()
    it("prefixes fetch and compute_with keys", function()
      local ns = cache.namespace "app"
      ns.fetch("k", function()
        return 1
      end)
      ns.compute_with("c", nil, function()
        return 2
      end)
      assert.is_true(cache.has "app:k")
      assert.are.equal(2, #ns.keys())
    end)
  end)

  describe("plain", function()
    it("passes scalars through and deep-copies tables", function()
      assert.are.equal(1, cache.plain(1))
      assert.is_nil(cache.plain(nil))
      local src = { a = { b = { 1 } } }
      local out = cache.plain(src)
      assert.are.same(src, out)
      assert.are_not.equal(src.a, out.a)
    end)
  end)
end)
