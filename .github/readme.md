# memo.wz

[![Tests](https://img.shields.io/github/actions/workflow/status/sravioli/memo.wz/tests.yaml?label=Tests&logo=Lua)](https://github.com/sravioli/memo.wz/actions?workflow=tests)
[![Lint](https://img.shields.io/github/actions/workflow/status/sravioli/memo.wz/lint.yaml?label=Lint&logo=Lua)](https://github.com/sravioli/memo.wz/actions?workflow=lint)
[![Coverage](https://img.shields.io/coverallsCoverage/github/sravioli/memo.wz?label=Coverage&logo=coveralls)](https://coveralls.io/github/sravioli/memo.wz)

Memoization, caching, and persistent state for
[WezTerm](https://wezfurlong.org/wezterm/) plugins and configuration code.

- Session-scoped memoization cache backed by `wezterm.GLOBAL`
- File-persistent key/value store with auto-load/save and async writes
- Deterministic key generation via serialization and concatenation
- Configurable TTL, eviction policies, and hit/miss statistics
- Namespaced cache partitions with scoped keys
- `compute()` for automatic memoization of function results

## Installation

```lua
local wezterm = require "wezterm"

-- from git
local memo = wezterm.plugin.require "https://github.com/sravioli/memo.wz"

-- from a local checkout
local memo = wezterm.plugin.require("file:///" .. wezterm.config_dir .. "/plugins/memo.wz")
```

## Usage

```lua
-- cache a computed value
memo.cache.set("theme", "tokyonight")
memo.cache.get("theme") -- "tokyonight"

-- memoize a function
local result = memo.cache.compute("expensive", function(x)
  return x * x
end, 42)

-- persistent state across WezTerm restarts
local store = memo.state.new { path = wezterm.home_dir .. "/.local/share/wezterm/my-state.json" }
store:set("last_workspace", "dev")
store:get("last_workspace") -- "dev"
```

## Modules

The plugin exposes three sub-modules via its public API:

```lua
local memo = wezterm.plugin.require "https://github.com/sravioli/memo.wz"
memo.cache -- session-scoped memoization cache
memo.key   -- serialization and key generation utilities
memo.state -- file-persistent key/value store factory
```

## Cache

Session-scoped memoization cache backed by `wezterm.GLOBAL`. TTL and stats
are opt-in; when disabled the cache stores bare values with zero bookkeeping
overhead.

### Configuration

```lua
memo.cache.configure {
  max_entries = 1000,                -- nil = unlimited
  eviction    = "expire-first",      -- eviction policy
  ttl         = { default = 60 },    -- TTL in seconds; nil = disabled
  stats       = true,                -- track hit/miss/eviction counters
  debug       = false,               -- log debug messages
}
```

| Field         | Type            | Default          | Description                                |
| ------------- | --------------- | ---------------- | ------------------------------------------ |
| `max_entries` | integer?        | `nil`            | Max cache entries. `nil` = unlimited.      |
| `eviction`    | string          | `"expire-first"` | Eviction policy when limit reached.        |
| `ttl`         | table?          | `nil`            | `{ default = N }` in seconds. `nil` = off. |
| `stats`       | boolean         | `false`          | Track hit/miss/eviction statistics.        |
| `debug`       | boolean         | `false`          | Log debug messages.                        |
| `clock`       | `fun(): number` | `os.time`        | Clock function for TTL (injectable).       |

Pass `false` for `ttl` or `max_entries` to explicitly disable them.

### Methods

| Method                         | Description                                           |
| ------------------------------ | ----------------------------------------------------- |
| `cache.get(key)`               | Retrieve a cached value.                              |
| `cache.set(key, value, opts?)` | Store a value. Optional `{ ttl = N }` per-call TTL.   |
| `cache.has(key)`               | Check whether a key exists and is fresh.              |
| `cache.delete(key)`            | Delete a single entry.                                |
| `cache.clear(selector?)`       | Clear all or filtered entries.                        |
| `cache.expire(key)`            | Mark a key as expired immediately (TTL mode).         |
| `cache.is_fresh(key)`          | Check whether an entry is still fresh.                |
| `cache.touch(key)`             | Reset the TTL on an existing key.                     |
| `cache.compute(name, fn, ...)` | Memoize: cache `fn(...)` result under a derived key.  |
| `cache.keys(selector?)`        | Return all cache keys, optionally filtered by prefix. |
| `cache.stats()`                | Return `{ hits, misses, evictions, entries }`.        |
| `cache.namespace(name)`        | Create a prefixed cache partition.                    |
| `cache.configure(opts)`        | Merge options into the current configuration.         |

#### Selectors

`clear` and `keys` accept an optional selector table:

- `{ prefix = "foo" }` — match keys starting with `"foo"`.
- `{ older_than = N }` — match entries older than N seconds (TTL mode).

### Namespaces

```lua
local ns = memo.cache.namespace "my-plugin"
ns.set("key", "value")
ns.get("key") -- "value"
```

All keys are automatically prefixed with `"my-plugin:"`. The namespace
wrapper exposes the same API as `memo.cache` but scoped to the prefix.

## Key

Deterministic cache-key generation via serialization and concatenation.
Each Lua value is converted to an unambiguous string representation and
the parts are joined with `|`. Tables are serialized recursively with
sorted keys; cyclic references produce the sentinel `"<cycle>"`.

### Functions

| Function                        | Description                                                       |
| ------------------------------- | ----------------------------------------------------------------- |
| `key.serialize(value, seen?)`   | Serialize any Lua value into a deterministic string (cycle-safe). |
| `key.make_cache_key(name, ...)` | Generate a deterministic key from name + arguments.               |

```lua
memo.key.serialize({ nested = { 1, 2, 3 } }) -- deterministic string
memo.key.make_cache_key("fn", "a", "b")       -- "fn|a|b"
```

## State

File-persistent key/value store backed by `wezterm.GLOBAL`. Each instance
owns a dedicated GLOBAL slot and an on-disk JSON file. Data is loaded from
disk once per WezTerm process and optionally flushed after every mutation.

### Factory

```lua
local store = memo.state.new {
  path      = "/path/to/state.json", -- required
  auto_load = true,                  -- load from disk on first access
  auto_save = true,                  -- flush to disk on every mutation
  async     = true,                  -- use wezterm.background_task if available
}
```

| Option      | Type    | Default | Description                                   |
| ----------- | ------- | ------- | --------------------------------------------- |
| `path`      | string  | —       | Absolute path to the JSON file. **Required.** |
| `auto_load` | boolean | `true`  | Load from disk on first access.               |
| `auto_save` | boolean | `true`  | Write to disk on every mutation.              |
| `async`     | boolean | `true`  | Use `wezterm.background_task` when available. |

### Methods

| Method              | Description                               |
| ------------------- | ----------------------------------------- |
| `store:get(key)`    | Retrieve a value by key.                  |
| `store:set(key, v)` | Store a value (no functions).             |
| `store:has(key)`    | Check whether a key exists.               |
| `store:delete(key)` | Delete a single key.                      |
| `store:clear()`     | Clear all entries.                        |
| `store:load()`      | Reload state from the JSON file.          |
| `store:save()`      | Flush current state to disk.              |
| `store:restore()`   | Return a shallow copy of all stored data. |

## Examples

Memoize an expensive computation:

```lua
local result = memo.cache.compute("heavy-calc", function(n)
  -- expensive work
  return n * n
end, 42)
```

Cache with TTL:

```lua
memo.cache.configure { ttl = { default = 300 } }
memo.cache.set("temp", "value")           -- expires in 5 minutes
memo.cache.set("short", "value", { ttl = 10 }) -- expires in 10 seconds
```

Persistent state across restarts:

```lua
local store = memo.state.new {
  path = wezterm.home_dir .. "/.local/share/wezterm/my-plugin.json",
}
store:set("window_count", 3)
-- after WezTerm restart:
store:get("window_count") -- 3
```

## License

Code is licensed under the [GNU General Public License v2](../LICENSE). Documentation
is licensed under [Creative Commons Attribution-NonCommercial 4.0 International](../LICENSE-DOCS).
