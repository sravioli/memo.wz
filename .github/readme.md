# memo.wz [![Release](https://img.shields.io/github/v/release/sravioli/memo.wz?style=flat&label=Release&logo=github)](https://github.com/sravioli/memo.wz/releases/latest)

[![Awesome](https://awesome.re/mentioned-badge.svg)](https://github.com/michaelbrusegard/awesome-wezterm)
[![Tests](https://img.shields.io/github/actions/workflow/status/sravioli/memo.wz/tests.yaml?style=flat&label=Tests&logo=githubactions)](https://github.com/sravioli/memo.wz/actions/workflows/tests.yaml)
[![Lint](https://img.shields.io/github/actions/workflow/status/sravioli/memo.wz/lint.yaml?style=flat&label=Lint&logo=githubactions)](https://github.com/sravioli/memo.wz/actions/workflows/lint.yaml)
[![Coverage](https://img.shields.io/coverallsCoverage/github/sravioli/memo.wz?style=flat&label=Coverage&logo=coveralls)](https://coveralls.io/github/sravioli/memo.wz)
[![Code license](https://img.shields.io/badge/Code-GPL--2.0-blue?style=flat&logo=gnu)](../LICENSE)
[![Docs license](https://img.shields.io/badge/Docs-CC_BY--NC_4.0-blue?style=flat&logo=creativecommons)](../LICENSE-DOCS)

Cache computed values and persist small settings for [WezTerm](https://wezterm.org/).

Use the shared session cache to avoid repeated work, or save values in JSON
when they must survive a restart. Namespaces and per-entry expiry let each
plugin manage its data without changing another plugin's cache settings.

[Quick start](#quick-start) · [Usage](#usage) · [Configuration](#configuration) · [API reference](#api-reference) · [Troubleshooting](#troubleshooting) · [Development](#development) · [License](#license)

## Quick start

### Requirements

Caching requires **WezTerm [`20230320-124340-559cb7b0`](https://wezterm.org/config/lua/wezterm/GLOBAL.html)
or newer** and Git. Persistent stores also need a
**[nightly with serde support (2024-02-08) or newer](https://github.com/wezterm/wezterm/commit/8596422abf6257ecfb57b32396c56318c8231886)**
and a writable destination with an existing parent directory.
No other plugins or special fonts are required.

### Install and run

Put this in `wezterm.lua`:

```lua
local wezterm = require "wezterm"
local memo = wezterm.plugin.require "https://github.com/sravioli/memo.wz"
local config = wezterm.config_builder()

local cache = memo.cache.namespace "my-config"
cache.set("theme", "Kanagawa (Gogh)")
config.color_scheme = cache.get "theme"

return config
```

Reload to apply the cached theme. The first value remains in the cache across
config reloads until deleted or WezTerm exits. In an existing config, add the
import and cache calls before its final return. Reuse its config builder.

## Usage

### Reuse a lookup briefly

After the imports, wrap a repeated computation with `fetch`:

```lua
local cache = memo.cache.namespace "my-config"
local timestamp = cache.fetch("timestamp", function()
  return os.date "%H:%M:%S"
end, { ttl = 30 })
wezterm.log_info(timestamp)
```

Calls within 30 seconds reuse the result. `fetch` uses your exact key.
`compute_with` derives one from a name and arguments. Both accept
`{ ttl = 0 }` to bypass caching and `{ plain = true }` to return a mutable
plain-table copy. Errors propagate and are not cached.

### Keep a setting across restarts

Choose a file whose parent directory already exists, outside the watched
config directory:

```lua
local store = memo.state.new {
  path = wezterm.home_dir .. "/.wezterm-example-state.json",
  atomic = true,
  backup = true,
}
store:set("last_workspace", "dev")
wezterm.log_info(store:get "last_workspace")
```

Save when a setting changes rather than on every reload. By default, stores
load on first access and save after mutations. Instances using the same
normalized path slot share process state.

### Replace a stored table

```lua
store:set("favorites", { "dev", "notes" })
store:set("favorites", { "dev" }, { replace = true })
```

Without `replace = true`, table assignments merge recursively and retain
keys absent from the new value, including old list elements.

## Configuration

### Example

There is no top-level `memo.setup`. All consumers of `memo.cache` share its
optional settings, so prefer per-call TTLs in reusable plugins.
If your host config owns the whole cache, you can configure it here:

```lua
memo.cache.configure {
  max_entries = 500,
  ttl = { default = 60 },
  stats = true,
}
```

These values override the defaults. Persistent stores take their options in
`memo.state.new`, as shown in [Usage](#keep-a-setting-across-restarts).

### Options

#### Cache configuration

Pass these to `memo.cache.configure`.

| Option        | Type                  | Default          | Description                                                                                       |
| ------------- | --------------------- | ---------------- | ------------------------------------------------------------------------------------------------- |
| `max_entries` | `integer\|false\|nil` | `nil`            | Global entry cap. Use a positive integer. `false` disables the cap.                               |
| `eviction`    | `string`              | `"expire-first"` | Only expire-first eviction is implemented: prefer expired entries, otherwise an arbitrary victim. |
| `ttl.default` | `number?`             | `nil`            | Default lifetime in seconds. `ttl` itself defaults to `nil`. Pass `ttl = false` to disable it.    |
| `stats`       | `boolean`             | `false`          | Count hits, misses, and evictions.                                                                |
| `debug`       | `boolean`             | `false`          | Accepted setting. No current cache operation emits debug output from it.                          |
| `clock`       | `fun(): number`       | `os.time`        | Clock in seconds for expiry. Injectable for tests.                                                |

#### Persistent store options

Pass these to `memo.state.new`.

| Option      | Type      | Default  | Description                                                                       |
| ----------- | --------- | -------- | --------------------------------------------------------------------------------- |
| `path`      | `string`  | Required | Destination JSON file. Supply an absolute path with an existing parent directory. |
| `auto_load` | `boolean` | `true`   | Load on first access, once per process slot.                                      |
| `auto_save` | `boolean` | `true`   | Save after `set`, `delete`, and `clear`.                                          |
| `async`     | `boolean` | `true`   | Use `wezterm.background_task` if that API exists. Otherwise write synchronously.  |
| `atomic`    | `boolean` | `true`   | Write a unique `.tmp` file before replacing the destination.                      |
| `backup`    | `boolean` | `false`  | Retain the previous file as `.bak`. Requires `atomic = true`.                     |

### Behavior and precedence

Cache configuration retains omitted fields and ignores unknown keys without
validation. `false` explicitly clears `ttl` or `max_entries`. `nil` cannot
clear a field in a Lua options table. Per-call `ttl` overrides the default.
Avoid global cache changes that would clear or resize another plugin's data.

`cache.set` normally keeps an existing fresh value. Pass `{ force = true }`
or an explicit TTL to overwrite it. `set(key, nil)` deletes it. Functions
cannot be stored with `set`, which logs an error for them. Cache callbacks
should return serializable values compatible with `wezterm.GLOBAL`.

Cache entries and store mirrors survive config reloads in `wezterm.GLOBAL`,
but cache configuration is Lua-local and must be reapplied. Only store files
survive a full restart. `store:load()` explicitly rereads disk. Editing its
file does not automatically refresh an already loaded store.

Memo logs file-write failures, but `store:save()` returns no success flag.
JSON encoding can raise. Without serde, store load and save do nothing.
Every write goes to its own uniquely named temporary file, renamed over the
destination, so concurrent writers never interleave: the last complete write
wins. The store does not provide transactions or merge concurrent changes.

`write_atomic` checks write and close results before replacing the primary.
With `backup`, it first copies the current primary to `.bak` the same way and
leaves the primary untouched if that fails. On POSIX the primary is never
missing. On Windows, where rename cannot replace a file, the destination is
moved aside to a `.old` file and put back if the final rename fails. If that
also fails, the log names the file to recover. Creating a missing primary keeps
an orphan backup. There is no `fsync` guarantee.

## API reference

The [API reference](../docs/api.md) lists every function, method, and value
with its parameters and return values. It is generated from the LuaLS
annotations in `plugin/`, so it matches the code. It has these sections:

- [memo.cache](../docs/api.md#memocache)
- [memo.key](../docs/api.md#memokey)
- [memo.state](../docs/api.md#memostate)
- [memo.cache.Namespace](../docs/api.md#memocachenamespace)
- [memo.state.Store](../docs/api.md#memostatestore)

`?` marks optional arguments or nullable results. Mutators returning `nil`
do not report persistence success. Public module names below use `memo`.
Underscore-prefixed helpers are internal.

### Session cache

`compute` caches only one return value. Use `fetch`/`compute_with` for per-call
TTLs and to avoid caching unsupported results. GLOBAL-backed tables are not
ordinary mutable tables. Use `plain` before editing a returned structure.
`clear`'s `older_than` selector estimates age from the global default TTL.
It is unsuitable for precise age filtering of mixed per-entry lifetimes.

### Namespace wrappers

All wrapper calls use `.`, not `:`. They share global limits and settings.

### Keys and persistent stores

Generated keys are deterministic for ordinary data, not cryptographic hashes.
Raw strings containing `|` can collide across argument boundaries. Functions
and userdata serialize by their address-like string, not a portable identity.
Stores derive GLOBAL slots by replacing path punctuation with `_`, so distinct
paths can also collide. Choose unambiguous paths and namespace names.

## Troubleshooting

### A cached value will not change

`set` is insert-if-absent unless forced. Delete the key, supply
`{ force = true }`, or use a per-entry TTL. Avoid clearing the entire shared
cache to invalidate one plugin's data.

### A store does not survive restart

Check the debug overlay, parent-directory permissions, and serde availability.
Check for a `.bak` recovery copy after a replacement failure.
Do not write beneath the watched config directory or share one file between
independent writers.

Update with `wezterm.plugin.update_all()` from the debug overlay and reload.
For [issues](https://github.com/sravioli/memo.wz/issues), include the plugin
revision, WezTerm version, options, and a reduced example without private data.

## Development

### Local checkout

Load the working tree directly, so edits take effect on the next config
reload without a commit or a plugin update. Adjust the path to your clone:

```lua
local wezterm = require "wezterm"
local root = wezterm.home_dir .. "/path/to/memo.wz/plugin/"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path
local memo = require "memo.api"
```

### Editor support

Follow the [wezterm-types setup](https://github.com/DrKJeff16/wezterm-types):

```lua
---@type Memo
local memo = wezterm.plugin.require "https://github.com/sravioli/memo.wz"
```

The [published definitions](https://github.com/DrKJeff16/wezterm-types/blob/main/lua/wezterm/types/plugins/memo.lua)
omit `fetch`, `compute_with`, `plain`, atomic-write
options/helpers, and `store:set`'s replacement option. Consult the local
[cache](../plugin/memo/cache.lua) and [state](../plugin/memo/state.lua)
annotations for this revision. Local class names use lowercase `memo`.

### Checks and contributions

From the repository root, with Lua 5.4 and the named tools installed:

```sh
busted --verbose
luacheck plugin spec
selene --display-style=quiet plugin
stylua --check plugin spec
```

The suite uses a WezTerm mock. See the [contribution guide](contributing.md)
and use Conventional Commits.

## License

Code: [GNU GPL v2](../LICENSE). Documentation:
[CC BY-NC 4.0](../LICENSE-DOCS). Preserve existing attribution.
