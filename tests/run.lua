-- Headless load test: loads SpotMe against a stubbed WoW API and drives it.
--
-- Run from the addon root:  lua tests/run.lua
--
-- This catches what a linter structurally cannot: errors raised while a file
-- loads, arithmetic on a nil that only appears at runtime, and slash commands
-- that blow up on their first use. It is not a substitute for playing the game
-- — nothing here proves a texture is in the right place — but a change that
-- breaks loading or breaks `/sm <cmd>` fails here in under a second.
--
-- Everything runs TWICE, with PLAYER_LOGIN delivered in both directions. The
-- client does not promise an order between separate frames' OnEvent handlers,
-- and 0.16.1 shipped a crash that only happened when PartyPanel's handler beat
-- Core's to the config. One-directional testing would never have seen it.

package.path = "tests/?.lua;" .. package.path

local stub = require("wow_stub")

-- Bound before stub.install() swaps the global out from under us.
local emit = print

local failures = {}
local checks = 0
local scenario = ""

local function check(ok, label, detail)
    checks = checks + 1
    local full = string.format("[%s] %s", scenario, label)
    if ok then
        emit(string.format("  ok   %s", label))
    else
        emit(string.format("  FAIL %s%s", label, detail and ("  — " .. tostring(detail)) or ""))
        table.insert(failures, full)
    end
end

local function attempt(label, fn)
    local ok, err = pcall(fn)
    check(ok, label, err)
    return ok
end

local ADDON = "SpotMe"
local FILES = { "Locale.lua", "Core.lua", "Nav.lua", "PartyPanel.lua" }

local function runScenario(name, reverse)
    scenario = name
    emit("")
    emit("=== " .. name .. " ===")
    stub.install()

    -- The client calls each addon file with (addonName, sharedTable).
    local ns = {}
    for _, file in ipairs(FILES) do
        attempt("load " .. file, function()
            local chunk, err = loadfile(file)
            if not chunk then error(err, 0) end
            chunk(ADDON, ns)
        end)
    end
    if #failures > 0 then
        emit("  a file failed to load — skipping the runtime checks")
        return
    end

    attempt("ADDON_LOADED fires cleanly", function() stub.FireEvent("ADDON_LOADED", reverse, ADDON) end)
    attempt("PLAYER_LOGIN fires cleanly", function() stub.FireEvent("PLAYER_LOGIN", reverse) end)
    attempt("queued timers run cleanly", function() stub.RunTimers() end)

    check(type(ns.GetCfg) == "function", "ns.GetCfg is exported")
    check(type(ns.GetCfg) == "function" and type(ns.GetCfg()) == "table", "config is populated after login")

    -- The button must exist regardless of which handler ran first. Before the
    -- config-ready queue, losing this race left it unbuilt.
    check(_G.SpotMeMinimapButton ~= nil, "SpotMeMinimapButton exists")

    -- Nothing may have been recorded as an error during a clean startup —
    -- SafeCall keeps the addon alive through a failure, so without this check a
    -- crash in a queued callback would look like a pass.
    local errs = ns.GetErrors and ns.GetErrors() or {}
    check(#errs == 0, "startup recorded no errors",
        #errs > 0 and (errs[1].label .. ": " .. errs[1].msg) or nil)

    if _G.SpotMeMinimapButton then
        local b = _G.SpotMeMinimapButton
        check(b:GetParent() ~= nil, "button has a parent")

        -- Assert the addon's own placement rather than recomputing it here: a
        -- check that re-implements the logic it tests passes even when the
        -- addon is broken. The button belongs on a ring of minimap radius + 5.
        local x, y = b:GetCenter()
        local mx, my = _G.Minimap:GetCenter()
        local r = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
        local expected = _G.Minimap:GetWidth() / 2 + 5
        check(math.abs(r - expected) < 1,
            string.format("button sits on the ring (r=%.1f expected=%.1f)", r, expected))
    end

    check(type(_G.SpotMe_Debug) == "function", "SpotMe_Debug is a global")
    attempt("SpotMe_Debug runs without error", function() _G.SpotMe_Debug() end)

    local handler = _G.SlashCmdList and _G.SlashCmdList.SPOTME
    check(type(handler) == "function", "/sm handler is registered")

    if type(handler) == "function" then
        -- `reset` is deliberately last: it does wipe(SpotMeDB) and relies on
        -- ReloadUI() rebuilding the config from DEFAULTS. ReloadUI is a no-op
        -- here, so anything after it would read an emptied table and report
        -- failures that cannot happen in game.
        local commands = {
            "", "help", "status", "debug", "world", "mini", "party", "nav",
            "theme", "arrow", "glowsize", "minisize", "color",
            "arrow 30", "glowsize 40", "minisize 20", "color 1 0 0",
            "60 40", "/way 60 40", "nonsense-command", "reset"
        }
        for _, cmd in ipairs(commands) do
            attempt(string.format("/sm %s", cmd == "" and "(no args)" or cmd), function() handler(cmd) end)
        end
    end

    -- Error plumbing itself, checked last so the deliberate failure below does
    -- not pollute the "startup recorded no errors" check above.
    check(type(ns.GetErrors) == "function", "ns.GetErrors is exported")
    if type(ns.SafeCall) == "function" then
        ns.SafeCall(function() error("deliberate test failure") end, "selftest")
        local after = ns.GetErrors()
        check(#after > 0, "SafeCall records a raised error")
        check(after[#after] and tostring(after[#after].msg):find("deliberate", 1, true) ~= nil,
            "recorded error keeps its message")
    else
        check(false, "ns.SafeCall is exported")
    end
end

emit("SpotMe headless load test")
runScenario("PLAYER_LOGIN in registration order", false)
runScenario("PLAYER_LOGIN in reverse order", true)

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
    emit(string.format("PASS — %d checks across 2 event orderings", checks))
    os.exit(0)
end

emit(string.format("FAIL — %d of %d checks failed:", #failures, checks))
for _, label in ipairs(failures) do emit("  " .. label) end
os.exit(1)
