---@diagnostic disable: undefined-global

-- Runs memo inside a real WezTerm Lua state, because the spec mock models
-- `wezterm.GLOBAL` as a plain table and cannot reproduce its proxy semantics
-- (nested tables are userdata, `t[k] = nil` keeps a null, `next` raises,
-- objects reject integer keys). Skipped when the `wezterm` binary is absent.

local function sh(cmd)
  local p = io.popen(cmd)
  if not p then
    return nil
  end
  local out = p:read "*a"
  p:close()
  return out
end

local has_wezterm = package.config:sub(1, 1) == "/"
  and (sh "command -v wezterm 2>/dev/null" or "") ~= ""

local HARNESS = [==[
local wt = require "wezterm"
local plugin = os.getenv "MEMO_PLUGIN"
-- warp from the sibling checkout, not whatever version WezTerm has installed.
package.path = plugin .. "/?.lua;" .. plugin .. "/../../warp.wz/plugin/?.lua;" .. package.path
local out = {}
local function check(name, fn)
  local ok, res = pcall(fn)
  out[#out + 1] = ((ok and res) and "ok " or "FAIL ") .. name .. (ok and "" or (" " .. tostring(res)))
end
local cache = require "memo.cache"
local now = 1000
cache.configure { clock = function() return now end }
check("ttl entries unwrap", function()
  cache.set("ttl", "v", { ttl = 10 })
  return cache.get "ttl" == "v"
end)
check("ttl entries expire", function()
  now = now + 11
  return cache.get "ttl" == nil
end)
check("fetch with ttl serves lists on a hit", function()
  local produce = function() return { { kind = "dir" }, { kind = "dir" } } end
  cache.fetch("src", produce, { ttl = 30, plain = true })
  local hit = cache.fetch("src", produce, { ttl = 30, plain = true })
  return #hit == 2 and hit[1].kind == "dir"
end)
check("plain returns plain leaves", function()
  cache.set("tbl", { s = "x", n = 2, t = { 1 } }, { force = true })
  local p = cache.plain(cache.get "tbl")
  return type(p) == "table" and p.s == "x" and p.n == 2 and p.t[1] == 1
end)
check("delete hides keys", function()
  cache.set("gone", 1)
  cache.delete "gone"
  return not cache.has "gone" and #cache.keys { prefix = "gone" } == 0
end)
check("clear removes all keys", function()
  cache.clear()
  return #cache.keys() == 0
end)
check("max_entries evicts", function()
  cache.configure { max_entries = 2 }
  cache.set("a", 1)
  cache.set("b", 2)
  cache.set("c", 3)
  cache.configure { max_entries = false }
  return #cache.keys() == 2
end)
local state = require "memo.state"
local path = os.getenv "MEMO_OUT" .. ".json"
os.remove(path)
local s = state.new { path = path, async = false }
check("state merges tables", function()
  s:set("t", { a = 1, b = 2 })
  s:set("t", { a = 5 })
  return s:get("t").a == 5 and s:get("t").b == 2
end)
check("state stores lists", function()
  s:set("list", { { id = "x" }, { id = "y" } }, { replace = true })
  return s:get("list")[2].id == "y"
end)
check("state restore skips deleted keys", function()
  s:delete "t"
  local r = s:restore()
  return r.t == nil and type(r.list) == "userdata"
end)
check("state loads lists from disk", function()
  local f = assert(io.open(path, "w"))
  f:write '{"hist":[{"id":"a","at":1}]}'
  f:close()
  s:load()
  return s:get("hist")[1].id == "a"
end)
check("state clear empties data", function()
  s:clear()
  return next(s:restore()) == nil
end)
os.remove(path)
local f = assert(io.open(os.getenv "MEMO_OUT", "w"))
f:write(table.concat(out, "\n"))
f:close()
return {}
]==]

local describe_real = has_wezterm and describe or pending

describe_real("memo in a real wezterm.GLOBAL", function()
  local results = {}

  setup(function()
    local dir = os.tmpname()
    os.remove(dir)
    local cfg, out = dir .. ".lua", dir .. ".out"
    local f = assert(io.open(cfg, "w"))
    f:write(HARNESS)
    f:close()
    local plugin = (sh "pwd"):gsub("%s+$", "") .. "/plugin"
    os.execute(
      ("MEMO_PLUGIN='%s' MEMO_OUT='%s' wezterm --config-file '%s' ls-fonts --text a >/dev/null 2>&1"):format(
        plugin,
        out,
        cfg
      )
    )
    local rf = io.open(out)
    if rf then
      for line in rf:lines() do
        local status, name = line:match "^(%S+) (.*)$"
        results[#results + 1] = { status = status, name = name }
      end
      rf:close()
    end
    os.remove(cfg)
    os.remove(out)
  end)

  it("runs every harness check without failures", function()
    assert.is_true(#results >= 12, "harness did not report; is wezterm runnable here?")
    for _, r in ipairs(results) do
      assert.are.equal("ok", r.status, r.name)
    end
  end)
end)
