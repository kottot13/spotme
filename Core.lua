-- SpotMe — a glow around the native player arrow.
--
-- Works on the WORLD MAP (M) and the MINIMAP, each toggled independently.
-- We do not draw our own arrow — the native gray one stays (the engine rotates
-- it correctly); on the world map we enlarge it a bit and draw a smooth glow
-- around it, with themes.
-- Config: GUI panel (Esc -> Options -> AddOns -> SpotMe, or just /sm) or slash.

local _, ns = ...
local L = ns.L

local CONFIG_VERSION = 10
local DEFAULT_PLAYER_SIZE = 27

local UPDATE_INTERVAL = 0.02
local SCALE_MIN, SCALE_MAX = 0.7, 2.5

--=============================================================================
-- Themes
--=============================================================================
local PING_C = "Interface\\Minimap\\UI-Minimap-Ping-Center"
local PING_E = "Interface\\Minimap\\UI-Minimap-Ping-Expand"
local STAR   = "Interface\\Cooldown\\star4"
local BURST  = "Interface\\Cooldown\\starburst"
local RING4  = "Interface\\Cooldown\\ping4"

local THEMES = {
    arcane    = { halo=PING_C, ring=PING_E, color={1.00,0.30,0.95}, pulse=0.90, ringT=1.60, ringMax=2.30, floor=0.45, flicker=true,  fspeed=3.2, spin=0   },
    fire      = { halo=STAR,   ring=RING4,  color={1.00,0.50,0.10}, pulse=0.50, ringT=1.10, ringMax=2.20, floor=0.40, flicker=true,  fspeed=11,  spin=40  },
    lightning = { halo=BURST,  ring=RING4,  color={0.55,0.80,1.00}, pulse=0.35, ringT=0.90, ringMax=2.40, floor=0.30, flicker=true,  fspeed=22,  spin=150 },
    ice       = { halo=PING_C, ring=PING_E, color={0.40,0.85,1.00}, pulse=1.40, ringT=2.00, ringMax=2.10, floor=0.55, flicker=false, fspeed=0,   spin=-15 },
    holy      = { halo=PING_C, ring=RING4,  color={1.00,0.85,0.40}, pulse=1.10, ringT=1.70, ringMax=2.20, floor=0.50, flicker=true,  fspeed=2,   spin=12  },
    shadow    = { halo=STAR,   ring=PING_E, color={0.65,0.20,1.00}, pulse=0.80, ringT=1.50, ringMax=2.30, floor=0.35, flicker=true,  fspeed=5,   spin=-60 },
}
local THEME_ORDER = { "arcane", "fire", "lightning", "ice", "holy", "shadow" }

local PRESETS = {
    neon    = { 1.00, 0.30, 0.95 }, ice     = { 0.25, 0.85, 1.00 },
    fire    = { 1.00, 0.45, 0.08 }, toxic   = { 0.55, 1.00, 0.10 },
    gold    = { 1.00, 0.82, 0.20 }, white   = { 1.00, 1.00, 1.00 },
    crimson = { 1.00, 0.10, 0.20 }, azure   = { 0.15, 0.45, 1.00 },
    emerald = { 0.10, 0.90, 0.45 }, violet  = { 0.65, 0.25, 1.00 },
    sunset  = { 1.00, 0.35, 0.45 }, aqua    = { 0.20, 1.00, 0.85 },
}
local COLOR_ORDER = { "neon","ice","fire","toxic","gold","white","crimson","azure","emerald","violet","sunset","aqua" }

--=============================================================================
-- Config
--=============================================================================
local DEFAULTS = {
    showWorld    = true,
    showMinimap  = false,
    theme        = "arcane",
    colorChoice  = "theme",   -- theme | rainbow | class | <preset> | custom
    mode         = "solid",   -- solid | rainbow | class
    color        = { r = 1.0, g = 0.30, b = 0.95 },
    rainbowSpeed = 0.10,
    arrowSize    = 40,
    glowSize     = 85,
    minimapSize  = 46,
    haloTexture  = PING_C,
    ringTexture  = PING_E,
    pulseTime    = 0.90,
    ringTime     = 1.60,
    ringMaxScale = 2.30,
    glowFloor    = 0.45,
    flicker      = true,
    flickerSpeed = 3.2,
    spin         = 0,
    -- party locator
    minimapButton = { angle = 214, hide = false },
    partyPanel    = {},
    classFilter   = {},
    sortMode      = "roster",   -- roster | near | far | class
    navArrow      = {},
    navColor      = "class",    -- class | red | cyan | green | yellow | black | white
}

--=============================================================================
-- HSV -> RGB (rainbow)
--=============================================================================
local floor = math.floor
local function HSV(h, s, v)
    local i = floor(h * 6); local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v else return v, p, q end
end

--=============================================================================
-- Glow factory
--=============================================================================
local function BuildGlow(c, cfg, size)
    c:SetSize(size, size)
    c.colored = {}

    local halo = c:CreateTexture(nil, "ARTWORK", nil, 1)
    halo:SetTexture(cfg.haloTexture)
    halo:SetDesaturated(true)   -- ping textures are yellow; desaturate so tint is accurate
    halo:SetBlendMode("ADD")
    halo:SetSize(size, size)
    halo:SetPoint("CENTER")
    table.insert(c.colored, halo)

    local hAG = halo:CreateAnimationGroup(); hAG:SetLooping("REPEAT")
    local a1 = hAG:CreateAnimation("Alpha")
    a1:SetFromAlpha(cfg.glowFloor); a1:SetToAlpha(1.0)
    a1:SetDuration(cfg.pulseTime); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
    local a2 = hAG:CreateAnimation("Alpha")
    a2:SetFromAlpha(1.0); a2:SetToAlpha(cfg.glowFloor)
    a2:SetDuration(cfg.pulseTime); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
    local s1 = hAG:CreateAnimation("Scale")
    s1:SetScaleFrom(0.9, 0.9); s1:SetScaleTo(1.1, 1.1)
    s1:SetOrigin("CENTER", 0, 0); s1:SetDuration(cfg.pulseTime); s1:SetOrder(1); s1:SetSmoothing("IN_OUT")
    local s2 = hAG:CreateAnimation("Scale")
    s2:SetScaleFrom(1.1, 1.1); s2:SetScaleTo(0.9, 0.9)
    s2:SetOrigin("CENTER", 0, 0); s2:SetDuration(cfg.pulseTime); s2:SetOrder(2); s2:SetSmoothing("IN_OUT")
    hAG:Play()

    if cfg.spin and cfg.spin ~= 0 then
        local spinAG = halo:CreateAnimationGroup(); spinAG:SetLooping("REPEAT")
        local rot = spinAG:CreateAnimation("Rotation")
        rot:SetDegrees(cfg.spin >= 0 and 360 or -360)
        rot:SetDuration(360 / math.abs(cfg.spin))
        spinAG:Play()
    end

    local function makeRing()
        local ring = c:CreateTexture(nil, "ARTWORK")
        ring:SetTexture(cfg.ringTexture)
        ring:SetDesaturated(true)
        ring:SetBlendMode("ADD")
        ring:SetSize(size, size)
        ring:SetPoint("CENTER")
        ring:SetAlpha(0)
        table.insert(c.colored, ring)
        local ag = ring:CreateAnimationGroup(); ag:SetLooping("REPEAT")
        local grow = ag:CreateAnimation("Scale")
        grow:SetScaleFrom(0.3, 0.3); grow:SetScaleTo(cfg.ringMaxScale, cfg.ringMaxScale)
        grow:SetOrigin("CENTER", 0, 0); grow:SetDuration(cfg.ringTime); grow:SetSmoothing("OUT")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.7); fade:SetToAlpha(0.0)
        fade:SetDuration(cfg.ringTime); fade:SetSmoothing("IN")
        return ag
    end
    makeRing():Play()
    local ag2 = makeRing()
    C_Timer.After(cfg.ringTime / 2, function() ag2:Play() end)

    function c:Paint(r, g, b)
        for _, tex in ipairs(self.colored) do tex:SetVertexColor(r, g, b) end
    end
    function c:Resize(newSize)
        self:SetSize(newSize, newSize)
        for _, tex in ipairs(self.colored) do tex:SetSize(newSize, newSize) end
    end
end

--=============================================================================
-- State
--=============================================================================
local cfg
local worldMarker, minimapMarker
local worldPin
local classR, classG, classB = 1, 1, 1
local panelCategory

--=============================================================================
-- Native (gray) player arrow size
--=============================================================================
local function PinScale(pin)
    local map = pin and pin.GetMap and pin:GetMap()
    local s = map and map.GetCanvasScale and map:GetCanvasScale()
    if not s or s <= 0 then return 1 end
    return s
end

local function ApplyArrowSize()
    if not worldPin or not cfg then return end
    local size = cfg.showWorld and cfg.arrowSize or DEFAULT_PLAYER_SIZE
    worldPin:SetPinSize("player", size / PinScale(worldPin))
end

if GroupMembersPinMixin and GroupMembersPinMixin.SynchronizePinSizes then
    hooksecurefunc(GroupMembersPinMixin, "SynchronizePinSizes", function(pin)
        worldPin = pin
        ApplyArrowSize()
    end)
end

--=============================================================================
-- Color
--=============================================================================
local function CurrentColor()
    if cfg.mode == "rainbow" then
        return HSV((GetTime() * cfg.rainbowSpeed) % 1, 1, 1)
    elseif cfg.mode == "class" then
        return classR, classG, classB
    end
    return cfg.color.r, cfg.color.g, cfg.color.b
end

local function SetColorChoice(choice)
    cfg.colorChoice = choice
    if choice == "rainbow" then
        cfg.mode = "rainbow"
    elseif choice == "class" then
        cfg.mode = "class"
    elseif choice == "theme" then
        cfg.mode = "solid"
        local t = THEMES[cfg.theme]
        if t then cfg.color.r, cfg.color.g, cfg.color.b = t.color[1], t.color[2], t.color[3] end
    elseif PRESETS[choice] then
        cfg.mode = "solid"
        local c = PRESETS[choice]
        cfg.color.r, cfg.color.g, cfg.color.b = c[1], c[2], c[3]
    end
end

--=============================================================================
-- Markers
--=============================================================================
local function CanvasZoom()
    if WorldMapFrame.GetCanvasScale then
        local z = WorldMapFrame:GetCanvasScale()
        if z and z > 0 then return z end
    end
    local z = WorldMapFrame:GetCanvas():GetScale()
    return (z and z > 0) and z or 1
end

local function RebuildInner(marker, size)
    if marker.inner then marker.inner:Hide() end
    local inner = CreateFrame("Frame", nil, marker)
    inner:SetPoint("CENTER")
    BuildGlow(inner, cfg, size)
    marker.inner = inner
end

local function EnsureWorldMarker()
    if not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    if not worldMarker then
        worldMarker = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
        worldMarker:SetSize(1, 1)
        worldMarker:SetFrameStrata("HIGH")
        worldMarker:Hide()
    end
    RebuildInner(worldMarker, cfg.glowSize)
end

local function EnsureMinimapMarker()
    if not Minimap then return end
    if not minimapMarker then
        minimapMarker = CreateFrame("Frame", nil, Minimap)
        minimapMarker:SetPoint("CENTER", Minimap, "CENTER")
        minimapMarker:SetFrameStrata(Minimap:GetFrameStrata())
        minimapMarker:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        minimapMarker:Hide()
    end
    RebuildInner(minimapMarker, cfg.minimapSize)
end

--=============================================================================
-- Theme
--=============================================================================
local function ApplyTheme(name)
    local t = THEMES[name]; if not t or not cfg then return end
    cfg.theme = name
    cfg.haloTexture, cfg.ringTexture = t.halo, t.ring
    cfg.pulseTime, cfg.ringTime, cfg.ringMaxScale = t.pulse, t.ringT, t.ringMax
    cfg.glowFloor, cfg.flicker, cfg.flickerSpeed, cfg.spin = t.floor, t.flicker, t.fspeed, t.spin
    if cfg.colorChoice == "theme" then
        cfg.mode = "solid"
        cfg.color.r, cfg.color.g, cfg.color.b = t.color[1], t.color[2], t.color[3]
    end
    if worldMarker then EnsureWorldMarker() end
    if minimapMarker then EnsureMinimapMarker() end
end

--=============================================================================
-- Toggles
--=============================================================================
local function SetWorld(on)
    cfg.showWorld = on
    ApplyArrowSize()
    if not on and worldMarker then worldMarker:Hide() end
end

local function SetMinimap(on)
    cfg.showMinimap = on
    if not on and minimapMarker then minimapMarker:Hide() end
end

--=============================================================================
-- Ticker
--=============================================================================
local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < UPDATE_INTERVAL then return end
    acc = 0
    if not cfg then return end

    local r, g, b = CurrentColor()
    if cfg.flicker then
        local k = 0.85 + 0.15 * math.sin(GetTime() * (cfg.flickerSpeed or 3.2))
        r, g, b = r * k, g * k, b * k
    end

    if worldMarker then
        local ok = cfg.showWorld and WorldMapFrame:IsShown()
        local pos
        if ok then
            local mapID = WorldMapFrame:GetMapID()
            pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        end
        if ok and pos then
            local x, y = pos:GetXY()
            local canvas = WorldMapFrame:GetCanvas()
            local w, h = canvas:GetSize()
            worldMarker:ClearAllPoints()
            worldMarker:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
            local sc = 1 / CanvasZoom()
            if sc < SCALE_MIN then sc = SCALE_MIN elseif sc > SCALE_MAX then sc = SCALE_MAX end
            worldMarker.inner:SetScale(sc)
            worldMarker.inner:Paint(r, g, b)
            worldMarker:Show()
        else
            worldMarker:Hide()
        end
    end

    if minimapMarker then
        if cfg.showMinimap then
            minimapMarker.inner:Paint(r, g, b)
            minimapMarker:Show()
        else
            minimapMarker:Hide()
        end
    end
end)

--=============================================================================
-- Settings panel (Settings API), wrapped in pcall so a failure never breaks core
--=============================================================================
local function SetupPanel()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("SpotMe")

    local function header(text)
        if CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end
    local function checkbox(key, label, tip, getter, setter)
        local s = Settings.RegisterProxySetting(category, "SpotMe_" .. key,
            Settings.VarType.Boolean, label, DEFAULTS[key], getter, setter)
        Settings.CreateCheckbox(category, s, tip)
    end
    local function slider(key, label, tip, minv, maxv, step, getter, setter)
        local s = Settings.RegisterProxySetting(category, "SpotMe_" .. key,
            Settings.VarType.Number, label, DEFAULTS[key], getter, setter)
        local opts = Settings.CreateSliderOptions(minv, maxv, step)
        Settings.CreateSlider(category, s, opts, tip)
    end
    local createDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    local function dropdown(key, label, tip, current, optionsFn, setter)
        local s = Settings.RegisterProxySetting(category, "SpotMe_" .. key,
            Settings.VarType.String, label, current, function() return current() end, setter)
        if createDropdown then createDropdown(category, s, optionsFn, tip) end
    end

    header(L.WHERE)
    checkbox("showWorld", L.WORLD_CB, L.WORLD_TIP,
        function() return cfg.showWorld end, function(v) SetWorld(v) end)
    checkbox("showMinimap", L.MINI_CB, L.MINI_TIP,
        function() return cfg.showMinimap end, function(v) SetMinimap(v) end)

    header(L.LOOK)
    dropdown("theme", L.THEME_LBL, L.THEME_TIP,
        function() return cfg.theme end,
        function()
            local c = Settings.CreateControlTextContainer()
            for _, n in ipairs(THEME_ORDER) do c:Add(n, L["T_" .. n] or n) end
            return c:GetData()
        end,
        function(v) ApplyTheme(v) end)
    dropdown("color", L.COLOR_LBL, L.COLOR_TIP,
        function() return cfg.colorChoice end,
        function()
            local c = Settings.CreateControlTextContainer()
            c:Add("theme", L.COL_THEME)
            c:Add("rainbow", L.COL_RAINBOW)
            c:Add("class", L.COL_CLASS)
            for _, n in ipairs(COLOR_ORDER) do c:Add(n, n) end
            return c:GetData()
        end,
        function(v) SetColorChoice(v) end)
    checkbox("flicker", L.FLICKER_CB, L.FLICKER_TIP,
        function() return cfg.flicker end, function(v) cfg.flicker = v end)
    dropdown("navColor", L.NAVCOL_LBL, L.NAVCOL_TIP,
        function() return cfg.navColor end,
        function()
            local c = Settings.CreateControlTextContainer()
            c:Add("class", L.NAVCOL_CLASS)
            c:Add("red", L.NAVCOL_RED)
            c:Add("cyan", L.NAVCOL_CYAN)
            c:Add("green", L.NAVCOL_GREEN)
            c:Add("yellow", L.NAVCOL_YELLOW)
            c:Add("black", L.NAVCOL_BLACK)
            c:Add("white", L.NAVCOL_WHITE)
            return c:GetData()
        end,
        function(v) cfg.navColor = v end)

    header(L.SIZES)
    slider("arrowSize", L.ARROW_SL, L.ARROW_TIP, 20, 80, 1,
        function() return cfg.arrowSize end, function(v) cfg.arrowSize = v; ApplyArrowSize() end)
    slider("glowSize", L.GLOW_SL, nil, 40, 160, 5,
        function() return cfg.glowSize end,
        function(v) cfg.glowSize = v; if worldMarker and worldMarker.inner then worldMarker.inner:Resize(v) end end)
    slider("minimapSize", L.MINI_SL, nil, 20, 100, 2,
        function() return cfg.minimapSize end,
        function(v) cfg.minimapSize = v; if minimapMarker and minimapMarker.inner then minimapMarker.inner:Resize(v) end end)
    slider("rainbowSpeed", L.SPEED_SL, nil, 0, 0.5, 0.01,
        function() return cfg.rainbowSpeed end, function(v) cfg.rainbowSpeed = v end)

    if Settings.RegisterAddOnCategory then Settings.RegisterAddOnCategory(category) end
    panelCategory = category
end

local function OpenPanel()
    if panelCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(panelCategory:GetID())
        return true
    end
    return false
end

--=============================================================================
-- Exports for PartyPanel.lua (party locator feature)
--=============================================================================
ns.BuildGlow = BuildGlow
ns.CanvasZoom = CanvasZoom
function ns.GetCfg() return cfg end

--=============================================================================
-- Loading
--=============================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    SpotMeDB = SpotMeDB or {}
    if SpotMeDB._v ~= CONFIG_VERSION then
        wipe(SpotMeDB); SpotMeDB._v = CONFIG_VERSION
    end
    for k, v in pairs(DEFAULTS) do
        if SpotMeDB[k] == nil then
            SpotMeDB[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    cfg = SpotMeDB

    local _, classFile = UnitClass("player")
    local cc = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if cc then classR, classG, classB = cc.r, cc.g, cc.b end

    EnsureWorldMarker()
    EnsureMinimapMarker()
    ApplyArrowSize()

    local ok = pcall(SetupPanel)
    if not ok then panelCategory = nil end
end)

local mapWatcher = CreateFrame("Frame")
mapWatcher:RegisterEvent("ADDON_LOADED")
mapWatcher:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_WorldMap" and cfg then EnsureWorldMarker() end
end)

--=============================================================================
-- Slash commands
--=============================================================================
local function say(msg) print("|cffff33aaSpotMe|r: " .. msg) end

SLASH_SPOTME1 = "/spotme"
SLASH_SPOTME2 = "/sm"
SLASH_SPOTME3 = "/fa"   -- legacy alias from the old name
SlashCmdList.SPOTME = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")

    local function onoff(v) return v and L.ON or L.OFF end

    if cmd == "" or cmd == "config" or cmd == "options" then
        if not OpenPanel() then say(L.PANEL_NA) end
    elseif cmd == "help" then
        say(L.HELP_SCREENS)
        say(L.HELP_PARTY)
        say(string.format(L.HELP_THEMES, table.concat(THEME_ORDER, "/")))
        say(string.format(L.HELP_COLORS, table.concat(COLOR_ORDER, " ")))
        say(L.HELP_MISC)
    elseif cmd == "world" then
        SetWorld(not cfg.showWorld); say(string.format(L.WORLD_STATE, onoff(cfg.showWorld)))
    elseif cmd == "minimap" or cmd == "mini" then
        SetMinimap(not cfg.showMinimap); say(string.format(L.MINI_STATE, onoff(cfg.showMinimap)))
    elseif cmd == "on" then
        SetWorld(true); SetMinimap(true); say(L.ALL_ON)
    elseif cmd == "off" then
        SetWorld(false); SetMinimap(false); say(L.ALL_OFF)
    elseif cmd == "party" then
        if ns.ToggleParty then ns.ToggleParty() end
    elseif cmd == "button" then
        if ns.ToggleMinimapButton then
            say(string.format(L.PL_BUTTON_STATE, ns.ToggleMinimapButton() and L.ON or L.OFF))
        end
    elseif cmd == "navcolor" then
        local okcol = { class = 1, red = 1, cyan = 1, green = 1, yellow = 1, black = 1, white = 1 }
        if okcol[rest] then cfg.navColor = rest; say(string.format(L.NAVCOL_SET, rest))
        else say(L.NAVCOL_FMT) end
    elseif cmd == "theme" then
        if THEMES[rest] then ApplyTheme(rest); say(string.format(L.THEME_SET, L["T_" .. rest] or rest))
        else say(string.format(L.THEMES_LIST, table.concat(THEME_ORDER, " "))) end
    elseif cmd == "reset" then
        wipe(SpotMeDB); ReloadUI()
    elseif cmd == "flicker" then
        cfg.flicker = not cfg.flicker; say(string.format(L.FLICKER_STATE, onoff(cfg.flicker)))
    elseif cmd == "rainbow" then
        SetColorChoice("rainbow"); say(L.MODE_RAINBOW)
    elseif cmd == "class" then
        SetColorChoice("class"); say(L.MODE_CLASS)
    elseif cmd == "speed" then
        local n = tonumber(rest)
        if n then cfg.rainbowSpeed = n; say(string.format(L.SPEED_SET, n)) else say(L.SPEED_FMT) end
    elseif cmd == "arrow" then
        local n = tonumber(rest)
        if n then cfg.arrowSize = n; ApplyArrowSize(); say(string.format(L.ARROW_SET, n))
        else say(L.ARROW_FMT) end
    elseif cmd == "glowsize" then
        local n = tonumber(rest)
        if n then cfg.glowSize = n; if worldMarker and worldMarker.inner then worldMarker.inner:Resize(n) end; say(string.format(L.GLOW_SET, n))
        else say(L.GLOW_FMT) end
    elseif cmd == "minisize" then
        local n = tonumber(rest)
        if n then cfg.minimapSize = n; if minimapMarker and minimapMarker.inner then minimapMarker.inner:Resize(n) end; say(string.format(L.MSIZE_SET, n))
        else say(L.MSIZE_FMT) end
    elseif cmd == "status" then
        say("world=" .. tostring(cfg.showWorld) .. " mini=" .. tostring(cfg.showMinimap)
            .. " theme=" .. tostring(cfg.theme) .. " colorChoice=" .. tostring(cfg.colorChoice)
            .. " panel=" .. tostring(panelCategory ~= nil))
    elseif PRESETS[cmd] then
        SetColorChoice(cmd); say(string.format(L.COLOR_SET, cmd))
    elseif cmd == "color" then
        local r, g, b = rest:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
        if r then
            cfg.mode = "solid"; cfg.colorChoice = "custom"
            cfg.color.r, cfg.color.g, cfg.color.b = tonumber(r), tonumber(g), tonumber(b)
            say(L.COLOR_DONE)
        else say(L.COLOR_FMT) end
    else
        say(L.UNKNOWN)
    end
end
