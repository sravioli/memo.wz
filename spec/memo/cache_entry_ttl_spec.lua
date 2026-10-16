---@diagnostic disable: undefined-global

require "spec.mocks.wezterm"

local cache = require "memo.cache"
local wt = require "wezterm"

describe("memo.cache per-entry ttl", function()
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

  it("expires per-entry ttl when global ttl is disabled", function()
    cache.set("k", "v", { ttl = 10 })
    assert.are.equal("v", cache.get "k")
    assert.is_true(cache.is_fresh "k")
    now = 1010
    assert.is_nil(cache.get "k")
    assert.is_false(cache.has "k")
  end)

  it("keeps entries without ttl forever", function()
    cache.set("k", "v")
    now = 99999
    assert.are.equal("v", cache.get "k")
  end)

  it("does not unwrap user tables that carry expires_at", function()
    local value = { expires_at = 1, value = "inner" }
    cache.set("k", value)
    now = 5000
    assert.are.same(value, cache.get "k")
  end)

  it("refreshes an existing key when a ttl is passed", function()
    cache.set("k", "old", { ttl = 5 })
    cache.set("k", "new", { ttl = 5 })
    assert.are.equal("new", cache.get "k")
  end)

  it("expire() invalidates ttl entries", function()
    cache.set("k", "v", { ttl = 100 })
    cache.expire "k"
    assert.is_nil(cache.get "k")
  end)

  it("works through namespaces", function()
    local ns = cache.namespace "harbor"
    ns.set("src", { 1, 2 }, { ttl = 3 })
    assert.are.same({ 1, 2 }, ns.get "src")
    now = 1003
    assert.is_nil(ns.get "src")
  end)
end)
