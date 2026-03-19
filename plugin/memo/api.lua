---@module "memo.api"

---Public API for memo.wz.
---
---`plugin/init.lua` requires this module after bootstrapping `package.path`.
---The two sub-tables — `cache` and `state` — are the entire public surface.

---@class memo.API
---@field cache memo.Cache  Session-scoped memoization cache (wezterm.GLOBAL).
---@field hash  memo.Hash   XXH3-64 hashing and key generation utilities.
---@field state memo.State  File-persistent key/value store factory.
return {
  cache = require "memo.cache",
  hash = require "memo.hash",
  state = require "memo.state",
}
