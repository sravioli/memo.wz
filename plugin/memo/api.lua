---@module "memo.api"

---Public API for memo.wz.
---
---`plugin/init.lua` requires this module after bootstrapping `package.path`.
---The `cache`, `key`, and `state` sub-tables make up the public surface.

---@class memo.API
---@field cache memo.Cache  Session-scoped memoization cache (wezterm.GLOBAL).
---@field key   memo.Key    Serialization and key generation utilities.
---@field state memo.State  File-persistent key/value store factory.
return {
  cache = require "memo.cache",
  key = require "memo.key",
  state = require "memo.state",
}
