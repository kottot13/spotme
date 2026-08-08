-- Minimal stand-in for the WoW client API, enough to load SpotMe outside the
-- game and drive it.
--
-- Why this exists: luacheck only proves that names resolve. It cannot see that
-- `local mx, my = Minimap and Minimap:GetCenter()` truncates the pair and
-- leaves `my` nil, so the next line does arithmetic on nil. Loading the addon
-- for real does see it.
--
-- Design: geometry and state getters return realistic values so arithmetic
-- works; anything else falls back to a no-op that returns the frame. Unknown
-- calls therefore never crash the harness — API typos are luacheck's job
-- (`read_globals` in .luacheckrc), not this file's.

local stub = {}

-- Every frame/texture/animation this creates, so tests can inspect them.
stub.frames = {}
-- Names of methods that fell through to the generic no-op, useful when a test
-- fails for a reason that turns out to be a missing stub.
stub.unstubbed = {}

local frameMT = {}

local function record(list, name)
    list[name] = (list[name] or 0) + 1
end

-- Methods with real behaviour. Everything here either returns a number the
-- addon does arithmetic on, or state the addon branches on.
local methods = {}

function methods:GetName() return self.__name end
function methods:GetParent() return self.__parent end
function methods:GetObjectType() return self.__type end

function methods:SetSize(w, h) self.__w, self.__h = w, h or w end
function methods:SetWidth(w) self.__w = w end
function methods:SetHeight(h) self.__h = h end
function methods:GetWidth() return self.__w or 100 end
function methods:GetHeight() return self.__h or 100 end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end

function methods:SetScale(s) self.__scale = s end
function methods:GetScale() return self.__scale or 1 end
function methods:GetEffectiveScale() return self.__scale or 1 end

function methods:Show() self.__shown = true end
function methods:Hide() self.__shown = false end
function methods:SetShown(v) self.__shown = v and true or false end
function methods:IsShown() return self.__shown ~= false end
-- Visible only when this frame and every ancestor is shown, same as the client.
function methods:IsVisible()
    local f = self
    while f do
        if f.__shown == false then return false end
        f = f.__parent
    end
    return true
end

function methods:SetAlpha(a) self.__alpha = a end
function methods:GetAlpha() return self.__alpha or 1 end

function methods:SetFrameStrata(s) self.__strata = s end
function methods:GetFrameStrata() return self.__strata or "MEDIUM" end
function methods:SetFrameLevel(l) self.__level = l end
function methods:GetFrameLevel() return self.__level or 1 end

function methods:ClearAllPoints() self.__points = {} end
function methods:SetPoint(point, rel, relPoint, x, y)
    self.__points = self.__points or {}
    table.insert(self.__points, { point, rel, relPoint, x or 0, y or 0 })
    -- Track the offset so GetCenter can answer something meaningful.
    if type(x) == "number" then self.__ox, self.__oy = x, y or 0 end
end
function methods:GetPoint()
    local p = self.__points and self.__points[1]
    if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5]
end
function methods:SetAllPoints(rel) self.__parent = rel or self.__parent end

-- Center in screen coordinates: the anchor's center plus our stored offset.
function methods:GetCenter()
    local base = self.__parent
    local bx, by = 400, 300
    if base and base ~= self and base.GetCenter then bx, by = base:GetCenter() end
    return bx + (self.__ox or 0), by + (self.__oy or 0)
end

function methods:SetScript(name, fn) self.__scripts[name] = fn end
function methods:HookScript(name, fn) self.__hooks[name] = fn end
function methods:GetScript(name) return self.__scripts[name] end
function methods:RegisterEvent(event)
    self.__events[event] = true
    stub.registered[event] = stub.registered[event] or {}
    table.insert(stub.registered[event], self)
end
function methods:UnregisterEvent(event) self.__events[event] = nil end

function methods:CreateTexture() return stub.NewFrame("Texture", nil, self) end
function methods:CreateFontString() return stub.NewFrame("FontString", nil, self) end
function methods:CreateLine() return stub.NewFrame("Line", nil, self) end
function methods:CreateAnimationGroup() return stub.NewFrame("AnimationGroup", nil, self) end
function methods:CreateAnimation() return stub.NewFrame("Animation", nil, self) end
function methods:GetHighlightTexture() return stub.NewFrame("Texture", nil, self) end

function methods:SetText(t) self.__text = t end
function methods:GetText() return self.__text or "" end
function methods:HasFocus() return false end

function methods:GetVerticalScroll() return self.__scroll or 0 end
function methods:SetVerticalScroll(v) self.__scroll = v end
function methods:GetVerticalScrollRange() return 0 end

frameMT.__index = function(_, key)
    local m = methods[key]
    if m then return m end
    -- Anything capitalised is treated as an unstubbed API method: record it and
    -- hand back a no-op. Returning nil instead would turn every un-stubbed call
    -- into "attempt to call a nil value" and bury the real failure.
    if type(key) == "string" and key:match("^[A-Z]") then
        record(stub.unstubbed, key)
        return function() return nil end
    end
    return nil
end

function stub.NewFrame(frameType, name, parent)
    local f = {
        __type = frameType or "Frame",
        __name = name,
        __parent = parent,
        __scripts = {},
        __hooks = {},
        __events = {},
        __points = {},
        __shown = true
    }
    setmetatable(f, frameMT)
    table.insert(stub.frames, f)
    if name then _G[name] = f end
    return f
end

stub.registered = {}

-- Fire an event at every frame that registered for it, the way the client does.
function stub.FireEvent(event, ...)
    for _, f in ipairs(stub.registered[event] or {}) do
        local handler = f.__scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end

-- Run every queued C_Timer.After callback, ignoring the delay.
stub.timers = {}
function stub.RunTimers()
    local queued = stub.timers
    stub.timers = {}
    for _, fn in ipairs(queued) do fn() end
end

function stub.install()
    _G.CreateFrame = function(frameType, name, parent) return stub.NewFrame(frameType, name, parent) end

    _G.UIParent = stub.NewFrame("Frame", "UIParent")
    _G.UIParent:SetSize(1920, 1080)
    _G.Minimap = stub.NewFrame("Frame", "Minimap", _G.UIParent)
    _G.Minimap:SetSize(140, 140)
    _G.MinimapCluster = stub.NewFrame("Frame", "MinimapCluster", _G.UIParent)
    _G.WorldMapFrame = stub.NewFrame("Frame", "WorldMapFrame", _G.UIParent)
    _G.GameTooltip = stub.NewFrame("Frame", "GameTooltip", _G.UIParent)

    _G.C_Timer = { After = function(_, fn) table.insert(stub.timers, fn) end }
    _G.C_Map = {
        GetBestMapForUnit = function() return 84 end,
        GetMapInfo = function(id) return { mapID = id or 84, name = "Stormwind City", parentMapID = 13 } end,
        GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
        GetWorldPosFromMapPos = function() return 0, CreateVector2D(0, 0) end,
        HasUserWaypoint = function() return false end,
        GetUserWaypoint = function() return nil end,
        GetUserWaypointPositionForMap = function() return nil end,
        SetUserWaypoint = function() return true end,
        ClearUserWaypoint = function() end,
        CanSetUserWaypointOnMap = function() return true end
    }
    _G.C_Minimap = { GetViewRadius = function() return 133 end }
    _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    _G.C_ClassColor = { GetClassColor = function() return { r = 0.5, g = 0.5, b = 0.9 } end }
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "0.0.0-test" or nil end }

    _G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    _G.CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 0.25, 0, 0.25 } end })
    _G.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })

    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.UnitExists = function(unit) return unit == "player" end
    _G.UnitName = function() return "Tester", nil end
    _G.UnitPosition = function() return 100, 200, 0, 1 end
    _G.GetPlayerFacing = function() return 0 end
    _G.IsInGroup = function() return false end
    _G.IsInRaid = function() return false end
    _G.GetNumGroupMembers = function() return 0 end
    _G.GetNumSubgroupMembers = function() return 0 end
    _G.GetCVarBool = function() return false end
    _G.GetCursorPosition = function() return 500, 400 end
    _G.GetTime = function() return 1000 end
    _G.GetLocale = function() return "enUS" end
    _G.GetBuildInfo = function() return "12.0.7", "60000", "Jan 1 2026", 120007 end
    _G.IsShiftKeyDown = function() return false end
    _G.IsControlKeyDown = function() return false end
    _G.hooksecurefunc = function() end
    _G.ReloadUI = function() end
    _G.ShowUIPanel = function() end
    _G.OpenWorldMap = function() end
    _G.debugstack = function() return "stubbed stack" end
    _G.geterrorhandler = function() return function() end end

    _G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function() return x, y end } end
    _G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = CreateVector2D(x, y) } end }

    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.CopyTable = function(t)
        local out = {}
        for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
        return out
    end

    -- Settings API: every constructor returns a chainable stub frame.
    _G.Settings = setmetatable({}, {
        __index = function(_, key)
            record(stub.unstubbed, "Settings." .. key)
            return function() return stub.NewFrame("SettingsControl") end
        end
    })
    _G.CreateSettingsListSectionHeaderInitializer = function() return stub.NewFrame("Initializer") end
    _G.GroupMembersPinMixin = {}
    _G.hash_SlashCmdList = {}
    _G.SlashCmdList = {}

    -- The addon's chat output is captured rather than printed, so the harness
    -- output stays readable. Keep the real print for the harness itself —
    -- replacing the global without this makes the test look like it died
    -- silently right after install.
    stub.realPrint = print
    stub.printed = {}
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(stub.printed, table.concat(parts, " "))
    end
end

return stub
