-- Headless load test: loads SpotMe against a stubbed WoW API and drives it.
--
-- Run from the addon root:  lua tests/run.lua
--
-- This catches what a linter structurally cannot: errors raised while a file
-- loads, arithmetic on a nil that only appears at runtime, and slash commands
-- that blow up on their first use. It is not a substitute for playing the game
-- — nothing here proves a texture is in the right place — but a change that
-- breaks loading or breaks `/sm <cmd>` fails here in under a second.

package.path = "tests/?.lua;" .. package.path

local stub = require("wow_stub")

-- Bound before stub.install() swaps the global out from under us.
local emit = print

local failures = {}
local checks = 0

local function check(ok, label, detail)
    checks = checks + 1
    if ok then
        emit(string.format("  ok   %s", label))
    else
        emit(string.format("  FAIL %s%s", label, detail and ("  — " .. tostring(detail)) or ""))
        table.insert(failures, label)
    end
end

local function attempt(label, fn)
    local ok, err = pcall(fn)
    check(ok, label, err)
    return ok
end

--=============================================================================
emit("SpotMe headless load test")
emit("")
emit("install stub")
stub.install()

--=============================================================================
emit("load files in SpotMe.toc order")

-- The client calls each addon file with (addonName, sharedTable).
local ns = {}
local ADDON = "SpotMe"
local files = { "Locale.lua", "Core.lua", "Nav.lua", "PartyPanel.lua" }

for _, file in ipairs(files) do
    attempt("load " .. file, function()
        local chunk, err = loadfile(file)
        if not chunk then error(err, 0) end
        chunk(ADDON, ns)
    end)
end

if #failures > 0 then
    emit("")
    emit("a file failed to load — stopping before the runtime checks")
    os.exit(1)
end

--=============================================================================
emit("")
emit("startup")

-- SavedVariables come back before ADDON_LOADED/PLAYER_LOGIN in the client.
_G.SpotMeDB = nil
attempt("ADDON_LOADED fires cleanly", function() stub.FireEvent("ADDON_LOADED", ADDON) end)
attempt("PLAYER_LOGIN fires cleanly", function() stub.FireEvent("PLAYER_LOGIN") end)
attempt("queued timers run cleanly", function() stub.RunTimers() end)

check(type(ns.GetCfg) == "function", "ns.GetCfg is exported")
local cfg = type(ns.GetCfg) == "function" and ns.GetCfg() or nil
check(type(cfg) == "table", "config is populated after login")

--=============================================================================
emit("")
emit("minimap button")

-- The button is created from a RunWhenConfigReady callback. Before this test
-- existed, an error in that callback was swallowed by a bare pcall and the
-- button just silently never appeared.
check(_G.SpotMeMinimapButton ~= nil, "SpotMeMinimapButton exists")

if _G.SpotMeMinimapButton then
    local b = _G.SpotMeMinimapButton
    check(b:GetParent() ~= nil, "button has a parent")

    -- Assert the addon's own placement rather than recomputing it here: a check
    -- that re-implements the logic it is testing passes even when the addon is
    -- broken. UpdateButtonPos puts the button on a ring of minimap radius + 5.
    local x, y = b:GetCenter()
    local mx, my = _G.Minimap:GetCenter()
    local r = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
    local expected = _G.Minimap:GetWidth() / 2 + 5
    check(math.abs(r - expected) < 1,
        string.format("button sits on the ring (r=%.1f expected=%.1f)", r, expected))
end

check(type(_G.SpotMe_Debug) == "function", "SpotMe_Debug is a global")
attempt("SpotMe_Debug runs without error", function() _G.SpotMe_Debug() end)

--=============================================================================
emit("")
emit("slash commands")

local handler = _G.SlashCmdList and _G.SlashCmdList.SPOTME
check(type(handler) == "function", "/sm handler is registered")

if type(handler) == "function" then
    -- Every command the addon answers. A command that throws on first use is
    -- invisible until a player types it; here it is a failed build.
    --
    -- `reset` is deliberately NOT in this list: it does `wipe(SpotMeDB)` and
    -- relies on ReloadUI() rebuilding the config from DEFAULTS. ReloadUI is a
    -- no-op here, so running it mid-sequence leaves every later command reading
    -- an emptied table and reporting failures that cannot happen in game. It
    -- runs last, on its own, below.
    local commands = {
        "", "help", "status", "debug", "world", "mini", "party", "nav",
        "theme", "arrow", "glowsize", "minisize", "color",
        "arrow 30", "glowsize 40", "minisize 20", "color 1 0 0",
        "60 40", "/way 60 40", "nonsense-command"
    }
    for _, cmd in ipairs(commands) do
        attempt(string.format("/sm %s", cmd == "" and "(no args)" or cmd), function() handler(cmd) end)
    end

    -- Last, because it empties the saved variables for everything after it.
    attempt("/sm reset", function() handler("reset") end)
end

--=============================================================================
emit("")
emit("error reporting")

check(type(ns.GetErrors) == "function", "ns.GetErrors is exported")
if type(ns.SafeCall) == "function" then
    ns.SafeCall(function() error("deliberate test failure") end, "selftest")
    local errs = ns.GetErrors()
    check(type(errs) == "table" and #errs > 0, "SafeCall records a raised error")
    check(
        type(errs) == "table" and errs[#errs] and tostring(errs[#errs].msg):find("deliberate", 1, true) ~= nil,
        "recorded error keeps its message"
    )
else
    check(false, "ns.SafeCall is exported")
end

--=============================================================================
local unstubbed = {}
for name in pairs(stub.unstubbed) do table.insert(unstubbed, name) end
table.sort(unstubbed)
if #unstubbed > 0 then
    emit("")
    emit("un-stubbed API calls (no-ops, listed so a confusing failure is easy to explain):")
    emit("  " .. table.concat(unstubbed, ", "))
end

emit("")
if #failures == 0 then
    emit(string.format("PASS — %d checks", checks))
    os.exit(0)
end

emit(string.format("FAIL — %d of %d checks failed:", #failures, checks))
for _, label in ipairs(failures) do emit("  " .. label) end
os.exit(1)
