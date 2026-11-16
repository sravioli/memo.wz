---Minimal config for bug reports. Run it in isolation from your own config:
---
---    wezterm --config-file minit.lua
---
---Put your reproduction below the marker. Keep it as small as possible and
---paste the edited file into the bug report.
local wezterm = require "wezterm"
local memo = wezterm.plugin.require "https://github.com/sravioli/memo.wz"
local config = wezterm.config_builder()

-- Edit below this line --------------------------------------------------------

local cache = memo.cache.namespace "my-config"
cache.set("theme", "Kanagawa (Gogh)")
config.color_scheme = cache.get "theme"

return config
