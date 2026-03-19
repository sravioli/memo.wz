---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local cache = require "memo.cache"
local wt = require "wezterm"

describe("memo.cache", function()
  before_each(function()
    wt._reset()
    -- Wipe the GLOBAL slot so each test starts clean.
    wt.GLOBAL.__memo_cache = nil
    wt.GLOBAL.__memo_stats = nil
    -- Reset all configuration to defaults.
    cache._reset_config()
    cache.clear()
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Basic CRUD
  -- ─────────────────────────────────────────────────────────────────────

  describe("get / set / has / delete", function()
    it("returns nil for missing keys", function()
      assert.is_nil(cache.get "nonexistent")
    end)

    it("stores and retrieves a string", function()
      cache.set("greeting", "hello")
      assert.are.equal("hello", cache.get "greeting")
    end)

    it("stores and retrieves a number", function()
      cache.set("answer", 42)
      assert.are.equal(42, cache.get "answer")
    end)

    it("stores and retrieves a boolean", function()
      cache.set("flag", true)
      assert.is_true(cache.get "flag")
    end)

    it("stores and retrieves a table", function()
      cache.set("tbl", { a = 1, b = 2 })
      local v = cache.get "tbl"
      assert.are.equal(1, v.a)
      assert.are.equal(2, v.b)
    end)

    it("has() returns true for existing keys", function()
      cache.set("x", "y")
      assert.is_true(cache.has "x")
    end)

    it("has() returns false for missing keys", function()
      assert.is_false(cache.has "missing")
    end)

    it("delete() removes a key", function()
      cache.set("x", "y")
      cache.delete "x"
      assert.is_nil(cache.get "x")
      assert.is_false(cache.has "x")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Function guard
  -- ─────────────────────────────────────────────────────────────────────

  describe("function storage guard", function()
    it("rejects function values with an error log", function()
      cache.set("bad", function() end)
      assert.is_nil(cache.get "bad")
      -- Verify the error was logged.
      assert.is_true(#wt._calls > 0)
      local last = wt._calls[#wt._calls]
      assert.are.equal("log_error", last.fn)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- clear()
  -- ─────────────────────────────────────────────────────────────────────

  describe("clear", function()
    it("clears all entries when called without arguments", function()
      cache.set("a", 1)
      cache.set("b", 2)
      cache.clear()
      assert.is_nil(cache.get "a")
      assert.is_nil(cache.get "b")
    end)

    it("clears only entries matching a prefix", function()
      cache.set("ns:a", 1)
      cache.set("ns:b", 2)
      cache.set("other", 3)
      cache.clear { prefix = "ns:" }
      assert.is_nil(cache.get "ns:a")
      assert.is_nil(cache.get "ns:b")
      assert.are.equal(3, cache.get "other")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- keys()
  -- ─────────────────────────────────────────────────────────────────────

  describe("keys", function()
    it("returns all keys", function()
      cache.set("a", 1)
      cache.set("b", 2)
      local ks = cache.keys()
      table.sort(ks)
      assert.are.same({ "a", "b" }, ks)
    end)

    it("filters by prefix", function()
      cache.set("ns:a", 1)
      cache.set("ns:b", 2)
      cache.set("other", 3)
      local ks = cache.keys { prefix = "ns:" }
      table.sort(ks)
      assert.are.same({ "ns:a", "ns:b" }, ks)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- compute()
  -- ─────────────────────────────────────────────────────────────────────

  describe("compute", function()
    it("caches the result of a function call", function()
      local calls = 0
      local fn = function(x)
        calls = calls + 1
        return x * 2
      end

      local r1 = cache.compute("double", fn, "5")
      local r2 = cache.compute("double", fn, "5")

      assert.are.equal(10, r1)
      assert.are.equal(10, r2)
      assert.are.equal(1, calls) -- fn called only once
    end)

    it("differentiates keys by arguments", function()
      local fn = function(x)
        return x * 2
      end

      local r1 = cache.compute("double", fn, "3")
      local r2 = cache.compute("double", fn, "5")

      assert.are.equal(6, r1)
      assert.are.equal(10, r2)
    end)

    it("propagates errors from the function", function()
      local fn = function()
        error("boom", 0)
      end
      assert.has_error(function()
        cache.compute("err", fn)
      end, "boom")
    end)

    it("works with table arguments (slow path)", function()
      local calls = 0
      local fn = function(t)
        calls = calls + 1
        return t.a + t.b
      end
      local arg = { a = 1, b = 2 }
      local r1 = cache.compute("add", fn, arg)
      local r2 = cache.compute("add", fn, arg)
      assert.are.equal(3, r1)
      assert.are.equal(3, r2)
      assert.are.equal(1, calls)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- namespace()
  -- ─────────────────────────────────────────────────────────────────────

  describe("namespace", function()
    it("prefixes keys correctly", function()
      local ns = cache.namespace "test"
      ns.set("k", "v")
      assert.are.equal("v", ns.get "k")
      -- Verify the actual key in the global slot.
      assert.are.equal("v", cache.get "test:k")
    end)

    it("has/delete are scoped", function()
      local ns = cache.namespace "test"
      ns.set("k", 1)
      assert.is_true(ns.has "k")
      ns.delete "k"
      assert.is_false(ns.has "k")
    end)

    it("clear only removes namespaced keys", function()
      local ns = cache.namespace "ns1"
      ns.set("a", 1)
      ns.set("b", 2)
      cache.set("global_key", 3)
      ns.clear()
      assert.is_false(ns.has "a")
      assert.is_false(ns.has "b")
      assert.are.equal(3, cache.get "global_key")
    end)

    it("keys returns un-prefixed keys", function()
      local ns = cache.namespace "ns"
      ns.set("x", 1)
      ns.set("y", 2)
      local ks = ns.keys()
      table.sort(ks)
      assert.are.same({ "x", "y" }, ks)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- TTL (opt-in)
  -- ─────────────────────────────────────────────────────────────────────

  describe("TTL", function()
    local clock

    before_each(function()
      clock = 1000
      cache.configure {
        ttl = { default = 10 },
        clock = function()
          return clock
        end,
      }
    end)

    it("returns value before TTL expires", function()
      cache.set("k", "v")
      clock = 1005 -- 5s later, within TTL
      assert.are.equal("v", cache.get "k")
    end)

    it("returns nil after TTL expires", function()
      cache.set("k", "v")
      clock = 1011 -- 11s later, past the 10s TTL
      assert.is_nil(cache.get "k")
    end)

    it("expire() forces immediate expiration", function()
      cache.set("k", "v")
      cache.expire "k"
      assert.is_nil(cache.get "k")
    end)

    it("is_fresh returns false for expired entries", function()
      cache.set("k", "v")
      clock = 1011
      assert.is_false(cache.is_fresh "k")
    end)

    it("touch() resets the TTL", function()
      cache.set("k", "v")
      clock = 1008 -- 8s in, still fresh
      cache.touch "k"
      clock = 1015 -- 7s after touch, still within new 10s TTL
      assert.are.equal("v", cache.get "k")
    end)

    it("per-entry TTL overrides default", function()
      cache.set("short", "v", { ttl = 2 })
      clock = 1001 -- 1s, within per-entry TTL
      assert.are.equal("v", cache.get "short")
      clock = 1003 -- 3s, past the 2s TTL
      assert.is_nil(cache.get "short")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- TTL no-ops when disabled
  -- ─────────────────────────────────────────────────────────────────────

  describe("TTL disabled (default)", function()
    -- _reset_config() in the outer before_each already sets ttl = nil.

    it("is_fresh returns true for existing keys", function()
      cache.set("k", "v")
      assert.is_true(cache.is_fresh "k")
    end)

    it("expire is a no-op", function()
      cache.set("k", "v")
      cache.expire "k"
      assert.are.equal("v", cache.get "k")
    end)

    it("touch is a no-op", function()
      cache.set("k", "v")
      cache.touch "k"
      assert.are.equal("v", cache.get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Stats (opt-in)
  -- ─────────────────────────────────────────────────────────────────────

  describe("stats", function()
    before_each(function()
      cache.configure { stats = true }
    end)

    it("tracks hits and misses", function()
      cache.set("k", "v")
      cache.get "k" -- hit
      cache.get "k" -- hit
      cache.get "missing" -- miss
      local st = cache.stats()
      assert.are.equal(2, st.hits)
      assert.are.equal(1, st.misses)
    end)

    it("counts entries", function()
      cache.set("a", 1)
      cache.set("b", 2)
      local st = cache.stats()
      assert.are.equal(2, st.entries)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- max_entries / eviction
  -- ─────────────────────────────────────────────────────────────────────

  describe("max_entries", function()
    it("evicts when limit is reached", function()
      cache.configure { max_entries = 2 }
      cache.set("a", 1)
      cache.set("b", 2)
      cache.set("c", 3) -- should evict one of a/b
      local ks = cache.keys()
      assert.are.equal(2, #ks)
      assert.are.equal(3, cache.get "c") -- newest survives
    end)

    it("prefers expired entries as eviction victims", function()
      local clock = 1000
      cache.configure {
        max_entries = 2,
        ttl = { default = 5 },
        clock = function()
          return clock
        end,
      }
      cache.set("old", "x")
      clock = 1006 -- old is now expired
      cache.set("fresh", "y") -- still within limit (old expired)
      cache.set("newer", "z") -- eviction needed; old is preferred victim
      assert.is_nil(cache.get "old")
      assert.are.equal("z", cache.get "newer")
    end)

    it("tracks evictions in stats", function()
      cache.configure { max_entries = 1, stats = true }
      cache.set("a", 1)
      cache.set("b", 2) -- evicts a
      local st = cache.stats()
      assert.is_true(st.evictions > 0)
    end)

    it("disabling max_entries with false stops eviction", function()
      cache.configure { max_entries = 1 }
      cache.set("a", 1)
      cache.configure { max_entries = false }
      cache.set("b", 2)
      cache.set("c", 3)
      assert.are.equal(3, #cache.keys())
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- configure edge cases
  -- ─────────────────────────────────────────────────────────────────────

  describe("configure", function()
    it("is a no-op when called with nil", function()
      cache.configure(nil)
      -- Should not error; config remains default.
      cache.set("k", "v")
      assert.are.equal("v", cache.get "k")
    end)

    it("ignores unknown keys", function()
      cache.configure { unknown_option = 42, stats = true }
      local st = cache.stats()
      assert.are.equal(0, st.hits)
    end)

    it("false sentinel disables ttl for new entries", function()
      local clock = 1000
      cache.configure {
        ttl = { default = 10 },
        clock = function()
          return clock
        end,
      }
      cache.configure { ttl = false }
      -- TTL disabled now; new entries are bare values.
      cache.set("k", "v")
      clock = 9999
      assert.are.equal("v", cache.get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- clear with older_than selector
  -- ─────────────────────────────────────────────────────────────────────

  describe("clear with older_than", function()
    it("removes entries older than threshold", function()
      local clock = 1000
      cache.configure {
        ttl = { default = 60 },
        clock = function()
          return clock
        end,
      }
      cache.set("old", "x")
      clock = 1050
      cache.set("new", "y")
      -- Clear entries created more than 30s ago.
      cache.clear { older_than = 30 }
      assert.is_nil(cache.get "old")
      assert.are.equal("y", cache.get "new")
    end)

    it("is a no-op when TTL is disabled", function()
      cache.set("k", "v")
      cache.clear { older_than = 0 }
      assert.are.equal("v", cache.get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Edge cases for expire / is_fresh / touch
  -- ─────────────────────────────────────────────────────────────────────

  describe("expire / is_fresh / touch edge cases", function()
    it("expire on non-existent key is a no-op (TTL enabled)", function()
      cache.configure { ttl = { default = 10 } }
      cache.expire "ghost"
      assert.is_false(cache.has "ghost")
    end)

    it("is_fresh returns false for non-existent key (TTL disabled)", function()
      assert.is_false(cache.is_fresh "nope")
    end)

    it("is_fresh returns true for fresh entry (TTL enabled)", function()
      cache.configure { ttl = { default = 10 } }
      cache.set("k", "v")
      assert.is_true(cache.is_fresh "k")
    end)

    it("touch on non-existent key is a no-op (TTL enabled)", function()
      cache.configure { ttl = { default = 10 } }
      cache.touch "ghost"
      assert.is_false(cache.has "ghost")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Overwriting values
  -- ─────────────────────────────────────────────────────────────────────

  describe("value overwrite", function()
    it("set overwrites existing value", function()
      cache.set("k", "old")
      cache.set("k", "new")
      assert.are.equal("new", cache.get "k")
    end)

    it("set overwrites with different type", function()
      cache.set("k", 42)
      cache.set("k", "hello")
      assert.are.equal("hello", cache.get "k")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Legacy bare value with TTL enabled
  -- ─────────────────────────────────────────────────────────────────────

  describe("legacy bare value", function()
    it("returns bare value when TTL is enabled after insert", function()
      cache.set("bare", "legacy")
      -- Enable TTL after the bare value was stored.
      cache.configure { ttl = { default = 10 } }
      assert.are.equal("legacy", cache.get "bare")
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Stats edge cases
  -- ─────────────────────────────────────────────────────────────────────

  describe("stats edge cases", function()
    it("returns zeros when stats disabled", function()
      local st = cache.stats()
      assert.are.equal(0, st.hits)
      assert.are.equal(0, st.misses)
      assert.are.equal(0, st.evictions)
    end)

    it("compute tracks hits and misses", function()
      cache.configure { stats = true }
      local fn = function()
        return "result"
      end
      cache.compute("fn", fn) -- miss
      cache.compute("fn", fn) -- hit
      local st = cache.stats()
      assert.are.equal(1, st.hits)
      assert.are.equal(1, st.misses)
    end)
  end)

  -- ─────────────────────────────────────────────────────────────────────
  -- Namespace: additional methods
  -- ─────────────────────────────────────────────────────────────────────

  describe("namespace (extended)", function()
    it("compute is scoped", function()
      local ns = cache.namespace "ns"
      local calls = 0
      local fn = function()
        calls = calls + 1
        return "val"
      end
      local r1 = ns.compute("work", fn)
      local r2 = ns.compute("work", fn)
      assert.are.equal("val", r1)
      assert.are.equal("val", r2)
      assert.are.equal(1, calls)
    end)

    it("expire / is_fresh / touch are scoped", function()
      local clock = 1000
      cache.configure {
        ttl = { default = 10 },
        clock = function()
          return clock
        end,
      }
      local ns = cache.namespace "ns"
      ns.set("k", "v")
      assert.is_true(ns.is_fresh "k")
      ns.expire "k"
      assert.is_false(ns.is_fresh "k")
    end)

    it("touch resets TTL through namespace", function()
      local clock = 1000
      cache.configure {
        ttl = { default = 10 },
        clock = function()
          return clock
        end,
      }
      local ns = cache.namespace "ns"
      ns.set("k", "v")
      clock = 1008
      ns.touch "k"
      clock = 1015
      assert.are.equal("v", ns.get "k")
    end)

    it("keys with sub-prefix filter", function()
      local ns = cache.namespace "ns"
      ns.set("foo:a", 1)
      ns.set("foo:b", 2)
      ns.set("bar:c", 3)
      local ks = ns.keys { prefix = "foo:" }
      table.sort(ks)
      assert.are.same({ "foo:a", "foo:b" }, ks)
    end)

    it("clear with sub-prefix", function()
      local ns = cache.namespace "ns"
      ns.set("foo:a", 1)
      ns.set("bar:b", 2)
      ns.clear { prefix = "foo:" }
      assert.is_false(ns.has "foo:a")
      assert.is_true(ns.has "bar:b")
    end)
  end)
end)
