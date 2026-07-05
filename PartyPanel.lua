-- SpotMe Party Locator.
--
-- A minimap button opens a scrollable panel listing the group (party or raid).
-- A row of class icons at the top filters the list by class. Each row shows the
-- member's class-colored name, their map coordinates and a copy button. Clicking
-- a member opens the world map on their zone with a class-colored glow.
--
-- Reuses the glow factory from Core via the shared `ns` table.

local _, ns = ...
local L = ns.L

local SCALE_MIN, SCALE_MAX = 0.7, 2.5

local PANEL_W    = 320
local HEADER_H   = 34
local FILTER_H   = 30            -- class-filter icon row
local ROW_H      = 40
local PAD        = 12
local SB_W       = 24            -- space reserved for the scrollbar
local MAX_VIS    = 9             -- rows visible before scrolling
local ROW_W      = PANEL_W - 2 * PAD - SB_W
local ICON_SIZE  = 22
local ICON_GAP   = 3

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
local CLASS_IDX = {}
for i, cf in ipairs(CLASS_ORDER) do CLASS_IDX[cf] = i end
local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

--=============================================================================
-- Helpers
--=============================================================================
local function ClassFile(unit)
    local _, cf = UnitClass(unit)
    return cf
end

local function ClassColor(unit)
    local cf = ClassFile(unit)
    local c = cf and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(cf)
    c = c or (cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf])
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Returns mapID, x, y (0-1) or nil when the unit's position is unavailable.
local function UnitMapPos(unit)
    local mapID = C_Map.GetBestMapForUnit(unit)
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, unit)
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    return mapID, x, y
end

-- Party -> player + party1..N; raid -> raid1..N; solo -> empty.
local function BuildUnitList()
    local t = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do t[i] = "raid" .. i end
    elseif IsInGroup() then
        t[1] = "player"
        for i = 1, GetNumSubgroupMembers() do t[i + 1] = "party" .. i end
    end
    return t
end

local SORT_MODES = { "roster", "near", "far", "class" }

-- Distance in yards from the player, or nil if not in the same instance.
local function Distance(unit)
    if unit == "player" then return 0 end
    local py, px, _, pInst = UnitPosition("player")
    local uy, ux, _, uInst = UnitPosition(unit)
    if not py or not uy or pInst ~= uInst then return nil end
    local dx, dy = px - ux, py - uy
    return math.sqrt(dx * dx + dy * dy)
end

--=============================================================================
-- World-map highlight of the selected member
--=============================================================================
local highlight, highlightUnit
local hlR, hlG, hlB = 1, 1, 1

local function EnsureHighlight()
    if highlight or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    highlight = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    highlight:SetSize(1, 1)
    highlight:SetFrameStrata("TOOLTIP")
    local inner = CreateFrame("Frame", nil, highlight)
    inner:SetPoint("CENTER")
    ns.BuildGlow(inner, ns.GetCfg(), ns.GetCfg().glowSize or 85)
    highlight.inner = inner
    highlight:Hide()
end

local function UpdateHighlight()
    if not highlight then return end
    if not highlightUnit or not WorldMapFrame:IsShown() or not UnitExists(highlightUnit) then
        highlight:Hide(); return
    end
    local mapID = WorldMapFrame:GetMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, highlightUnit)
    if not pos then highlight:Hide(); return end
    local x, y = pos:GetXY()
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetSize()
    highlight:ClearAllPoints()
    highlight:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
    local sc = 1 / ns.CanvasZoom()
    if sc < SCALE_MIN then sc = SCALE_MIN elseif sc > SCALE_MAX then sc = SCALE_MAX end
    highlight.inner:SetScale(sc)
    highlight.inner:Paint(hlR, hlG, hlB)
    highlight:Show()
end

local function HighlightMember(unit)
    local mapID = UnitMapPos(unit)
    if not mapID then return end
    highlightUnit = unit
    hlR, hlG, hlB = ClassColor(unit)
    EnsureHighlight()
    if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
    WorldMapFrame:SetMapID(mapID)
    UpdateHighlight()
end

-- Drop a Blizzard navigation waypoint on the member's position (not protected).
local function WaypointTo(unit)
    local mapID, x, y = UnitMapPos(unit)
    if not mapID then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

--=============================================================================
-- TomTom-style navigation: on-screen arrow + dotted map path (class colored)
--=============================================================================
local navUnit
local navR, navG, navB = 1, 1, 1
local arrow, pathParent
local pathDots = {}
local NAV_DOTS = 22
-- If the arrow points the wrong way in game, flip SIGN (1/-1) or add pi to OFFSET.
local NAV_ROT_SIGN, NAV_ROT_OFFSET = -1, 0
local UpdateNav, ClearNav   -- forward declarations

local function EnsureArrow()
    if arrow then return end
    arrow = CreateFrame("Frame", "SpotMeNavArrow", UIParent)
    arrow:SetSize(52, 52)
    arrow:SetMovable(true)
    arrow:EnableMouse(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetScript("OnDragStart", arrow.StartMoving)
    arrow:SetScript("OnDragStop", function()
        arrow:StopMovingOrSizing()
        local p, _, rp, x, y = arrow:GetPoint()
        ns.GetCfg().navArrow = { p, rp, x, y }
    end)
    arrow:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" then ClearNav() end
    end)

    local tex = arrow:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    tex:SetPoint("CENTER")
    tex:SetSize(42, 42)
    arrow.tex = tex

    local dist = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dist:SetPoint("TOP", arrow, "BOTTOM", 0, 0)
    arrow.dist = dist

    local pt = ns.GetCfg().navArrow
    if pt and pt[1] then
        arrow:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
    arrow:Hide()
end

local function GetDot(i)
    local d = pathDots[i]
    if not d then
        if not pathParent then
            pathParent = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
            pathParent:SetAllPoints()
            pathParent:SetFrameStrata("HIGH")
        end
        d = CreateFrame("Frame", nil, pathParent)
        d:SetSize(18, 18)
        -- solid black outline for contrast on bright maps
        local back = d:CreateTexture(nil, "ARTWORK")
        back:SetTexture("Interface\\Masks\\CircleMaskScalable")
        back:SetVertexColor(0, 0, 0, 1)
        back:SetAllPoints()
        -- solid class-colored core
        local fill = d:CreateTexture(nil, "OVERLAY")
        fill:SetTexture("Interface\\Masks\\CircleMaskScalable")
        fill:SetPoint("CENTER")
        fill:SetSize(12, 12)
        d.fill = fill
        pathDots[i] = d
    end
    return d
end

local function HideDots()
    for _, d in ipairs(pathDots) do d:Hide() end
end

local miniDots = {}
local MINI_ROT_SIGN = 1   -- flip if the minimap path mirrors when rotateMinimap is on

local function GetMiniDot(i)
    local d = miniDots[i]
    if not d then
        d = CreateFrame("Frame", nil, Minimap)
        d:SetSize(12, 12)
        d:SetFrameStrata(Minimap:GetFrameStrata())
        d:SetFrameLevel(Minimap:GetFrameLevel() + 9)
        local back = d:CreateTexture(nil, "ARTWORK")
        back:SetTexture("Interface\\Masks\\CircleMaskScalable")
        back:SetVertexColor(0, 0, 0, 1); back:SetAllPoints()
        local fill = d:CreateTexture(nil, "OVERLAY")
        fill:SetTexture("Interface\\Masks\\CircleMaskScalable")
        fill:SetPoint("CENTER"); fill:SetSize(8, 8)
        d.fill = fill
        miniDots[i] = d
    end
    return d
end

local function HideMiniDots()
    for _, d in ipairs(miniDots) do d:Hide() end
end

function UpdateNav()
    if not navUnit or not UnitExists(navUnit) then
        if arrow then arrow:Hide() end
        HideDots()
        HideMiniDots()
        return
    end

    -- on-screen arrow
    local py, px, _, pI = UnitPosition("player")
    local ty, tx, _, tI = UnitPosition(navUnit)
    local facing = GetPlayerFacing()
    if arrow then
        if py and ty and pI == tI and facing then
            local dx, dy = tx - px, ty - py
            local dist = math.sqrt(dx * dx + dy * dy)
            local bearing = math.atan2(dx, dy)
            arrow.tex:SetRotation(NAV_ROT_SIGN * (facing - bearing) + NAV_ROT_OFFSET)
            arrow.tex:SetVertexColor(navR, navG, navB)
            arrow.dist:SetText(string.format("%d %s", dist, L.PL_YD))
            arrow.dist:SetTextColor(navR, navG, navB)
            arrow:Show()
        else
            arrow:Hide()
        end
    end

    -- dotted path on the world map (straight line — WoW has no routing)
    if WorldMapFrame:IsShown() and WorldMapFrame.GetCanvas then
        local mapID = WorldMapFrame:GetMapID()
        local pp = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local tp = mapID and C_Map.GetPlayerMapPosition(mapID, navUnit)
        if pp and tp then
            local pmx, pmy = pp:GetXY()
            local tmx, tmy = tp:GetXY()
            local canvas = WorldMapFrame:GetCanvas()
            local w, h = canvas:GetSize()
            for i = 1, NAV_DOTS do
                local t = i / (NAV_DOTS + 1)
                local mx = pmx + (tmx - pmx) * t
                local my = pmy + (tmy - pmy) * t
                local d = GetDot(i)
                d:ClearAllPoints()
                d:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
                d.fill:SetVertexColor(navR, navG, navB)
                d:Show()
            end
            for i = NAV_DOTS + 1, #pathDots do pathDots[i]:Hide() end
        else
            HideDots()
        end
    else
        HideDots()
    end

    -- dotted path on the minimap: direction from the zone map (north-up, matches
    -- the world map), dots spaced by a fixed pixel step so they never overlap.
    local zmap = C_Map.GetBestMapForUnit("player")
    local pp = zmap and C_Map.GetPlayerMapPosition(zmap, "player")
    local tp = zmap and C_Map.GetPlayerMapPosition(zmap, navUnit)
    if pp and tp then
        local pmx, pmy = pp:GetXY()
        local tmx, tmy = tp:GetXY()
        local dirx, diry = tmx - pmx, -(tmy - pmy)   -- east = +x, north = -mapY (up)
        local len = math.sqrt(dirx * dirx + diry * diry)
        if len > 0.00001 then
            local ux, uy = dirx / len, diry / len
            if GetCVarBool("rotateMinimap") and facing then
                local a = MINI_ROT_SIGN * facing
                local sa, ca = math.sin(a), math.cos(a)
                ux, uy = ux * ca - uy * sa, ux * sa + uy * ca
            end
            local radius = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()) or 200
            local half = Minimap:GetWidth() / 2
            local worldDist = Distance(navUnit) or 0
            local pixelLen = math.min(worldDist * (half / radius), half - 6)
            local step, n, dd = 12, 0, 12
            while dd <= pixelLen do
                n = n + 1
                local d = GetMiniDot(n)
                d:ClearAllPoints()
                d:SetPoint("CENTER", Minimap, "CENTER", ux * dd, uy * dd)
                d.fill:SetVertexColor(navR, navG, navB)
                d:Show()
                dd = dd + step
            end
            for i = n + 1, #miniDots do miniDots[i]:Hide() end
        else
            HideMiniDots()
        end
    else
        HideMiniDots()
    end
end

function ClearNav()
    navUnit = nil
    if arrow then arrow:Hide() end
    HideDots()
    HideMiniDots()
end

local function StartNav(unit)
    if navUnit == unit then ClearNav(); return end   -- right-click again to stop
    local mapID = UnitMapPos(unit)
    if not mapID then return end
    navUnit = unit
    navR, navG, navB = ClassColor(unit)
    EnsureArrow()
    WaypointTo(unit)   -- also drop the Blizzard minimap pin
    UpdateNav()
end

--=============================================================================
-- Copy-coordinates popup (WoW has no clipboard API — use a selected EditBox)
--=============================================================================
local copyBox
local function ShowCopyBox(anchor, text)
    if not copyBox then
        copyBox = CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
        copyBox:SetAutoFocus(false)
        copyBox:SetSize(96, 20)
        copyBox:SetFontObject("GameFontHighlightSmall")
        copyBox:SetScript("OnEscapePressed", copyBox.Hide)
        copyBox:SetScript("OnEnterPressed", copyBox.Hide)
        copyBox:SetScript("OnEditFocusLost", copyBox.Hide)
    end
    copyBox:ClearAllPoints()
    copyBox:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    copyBox:SetText(text)
    copyBox:Show()
    copyBox:SetFocus()
    copyBox:HighlightText()
end

--=============================================================================
-- Party panel (scrollable list + class filter)
--=============================================================================
local panel, content, filterBar
local rowPool, filterIcons = {}, {}
local Refresh, RebuildFilterBar   -- forward declarations

local function CreateRow()
    local row = CreateFrame("Button", nil, content)
    row:SetSize(ROW_W, ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, -3)
    accent:SetPoint("BOTTOMLEFT", 0, 4)
    accent:SetWidth(3)
    row.accent = accent

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", 12, -5)
    row.nameFS = name

    local coords = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coords:SetPoint("BOTTOMLEFT", 12, 7)
    row.coordsFS = coords

    local copy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copy:SetSize(76, 22)
    copy:SetPoint("RIGHT", -6, 0)
    copy:SetText(L.PL_COPY)
    copy:SetScript("OnClick", function()
        if row.coordText then ShowCopyBox(copy, row.coordText) end
    end)
    row.copyBtn = copy

    local divider = row:CreateTexture(nil, "OVERLAY")
    divider:SetPoint("BOTTOMLEFT", 4, 0)
    divider:SetPoint("BOTTOMRIGHT", -4, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.10)

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    if hl then hl:SetColorTexture(1, 1, 1, 0.08) end

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if not self.unit or not self.coordText then return end
        if button == "RightButton" then
            StartNav(self.unit)
        else
            HighlightMember(self.unit)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.unit then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(UnitName(self.unit) or "")
            GameTooltip:AddLine(L.PL_ROW_TIP, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function AcquireRow(i)
    local row = rowPool[i]
    if not row then
        row = CreateRow()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        rowPool[i] = row
    end
    return row
end

local function UpdateSortButton()
    if not (panel and panel.sortBtn) then return end
    local m = ns.GetCfg().sortMode
    if m == "near" then
        panel.sortBtn:SetText(L.PL_SORT_NEAR)
    elseif m == "far" then
        panel.sortBtn:SetText(L.PL_SORT_FAR)
    elseif m == "class" then
        panel.sortBtn:SetText(L.PL_SORT_CLASS)
    else
        panel.sortBtn:SetText(L.PL_SORT_ROSTER)
    end
end

local function CycleSort()
    local c = ns.GetCfg()
    local idx = 1
    for k, v in ipairs(SORT_MODES) do if v == c.sortMode then idx = k end end
    c.sortMode = SORT_MODES[(idx % #SORT_MODES) + 1]
    UpdateSortButton()
    Refresh()
end

local function CreateFilterIcon()
    local b = CreateFrame("Button", nil, filterBar)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(CLASS_TEX)
    b.tex = tex
    b:SetScript("OnEnter", function(self)
        if self.classFile then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.classFile]) or self.classFile)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        local db = ns.GetCfg().classFilter
        if db[self.classFile] then db[self.classFile] = nil else db[self.classFile] = true end
        Refresh()
    end)
    return b
end

function RebuildFilterBar(present)
    local db = ns.GetCfg().classFilter
    local x = 0
    for idx, cf in ipairs(present) do
        local b = filterIcons[idx]
        if not b then b = CreateFilterIcon(); filterIcons[idx] = b end
        b.classFile = cf
        b:ClearAllPoints()
        b:SetPoint("LEFT", filterBar, "LEFT", x, 0)
        x = x + ICON_SIZE + ICON_GAP
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
        if tc then b.tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        local hidden = db[cf] and true or false
        b.tex:SetDesaturated(hidden)
        b.tex:SetAlpha(hidden and 0.35 or 1)
        b:Show()
    end
    for i = #present + 1, #filterIcons do filterIcons[i]:Hide() end
end

local function EnsurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "SpotMePartyPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, HEADER_H + FILTER_H + ROW_H + PAD)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 22,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local p, _, rp, x, y = panel:GetPoint()
        ns.GetCfg().partyPanel = { p, rp, x, y }
    end)
    panel:SetClampedToScreen(true)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -11)
    panel.title = title

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 1, 1)

    local sortBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    sortBtn:SetSize(84, 20)
    sortBtn:SetPoint("TOPLEFT", 10, -8)
    sortBtn:SetScript("OnClick", CycleSort)
    panel.sortBtn = sortBtn
    UpdateSortButton()

    filterBar = CreateFrame("Frame", nil, panel)
    filterBar:SetPoint("TOPLEFT", PAD, -HEADER_H - 2)
    filterBar:SetPoint("TOPRIGHT", -PAD, -HEADER_H - 2)
    filterBar:SetHeight(ICON_SIZE)

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -(HEADER_H + FILTER_H + 10))
    empty:SetText(L.PL_NOPARTY)
    panel.empty = empty

    local scroll = CreateFrame("ScrollFrame", "SpotMePartyScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + FILTER_H))
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 4, PAD)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = self:GetVerticalScrollRange()
        local new = self:GetVerticalScroll() - delta * ROW_H
        if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
        self:SetVerticalScroll(new)
    end)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(content)

    local pt = ns.GetCfg().partyPanel
    if pt and pt[1] then
        panel:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        panel:SetPoint("CENTER")
    end
    panel:Hide()
end

function Refresh()
    if not panel or not panel:IsShown() then return end

    if not IsInGroup() then
        panel.title:SetText("SpotMe · " .. L.PL_TITLE)
        panel.empty:Show()
        for _, row in pairs(rowPool) do row:Hide() end
        for _, b in pairs(filterIcons) do b:Hide() end
        content:SetHeight(1)
        panel:SetHeight(HEADER_H + FILTER_H + 44)
        return
    end
    panel.empty:Hide()

    local units = BuildUnitList()
    local db = ns.GetCfg().classFilter

    -- classes present in the group, in fixed order
    local presentSet, present = {}, {}
    for _, unit in ipairs(units) do
        local cf = ClassFile(unit)
        if cf then presentSet[cf] = true end
    end
    for _, cf in ipairs(CLASS_ORDER) do
        if presentSet[cf] then present[#present + 1] = cf end
    end
    RebuildFilterBar(present)

    -- filter by class
    local shown = {}
    for _, unit in ipairs(units) do
        local cf = ClassFile(unit)
        if not (cf and db[cf]) then shown[#shown + 1] = unit end
    end

    -- distances + optional sort
    local dist = {}
    for _, unit in ipairs(shown) do dist[unit] = Distance(unit) end
    local mode = ns.GetCfg().sortMode
    if mode == "near" or mode == "far" then
        table.sort(shown, function(a, b)
            local da, dbv = dist[a], dist[b]
            if da and dbv then
                if mode == "near" then return da < dbv else return da > dbv end
            elseif da then return true      -- known distance before unknown
            elseif dbv then return false
            end
            return false
        end)
    elseif mode == "class" then
        table.sort(shown, function(a, b)
            local ca = CLASS_IDX[ClassFile(a)] or 99
            local cb = CLASS_IDX[ClassFile(b)] or 99
            if ca ~= cb then return ca < cb end
            return (UnitName(a) or "") < (UnitName(b) or "")
        end)
    end

    -- render
    for i, unit in ipairs(shown) do
        local row = AcquireRow(i)
        row.unit = unit
        row:Show()
        local r, g, b = ClassColor(unit)
        row.nameFS:SetText(UnitName(unit) or "?")
        row.nameFS:SetTextColor(r, g, b)
        row.accent:SetColorTexture(r, g, b, 0.9)
        row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.05 or 0.0)

        local mapID, x, y = UnitMapPos(unit)
        if mapID then
            row.coordText = string.format("%.1f, %.1f", x * 100, y * 100)
            local d = dist[unit]
            if unit == "player" then
                row.coordsFS:SetText(row.coordText .. "  ·  " .. L.PL_YOU)
            elseif d then
                row.coordsFS:SetText(string.format("%s  ·  %d %s", row.coordText, d, L.PL_YD))
            else
                row.coordsFS:SetText(row.coordText)
            end
            row.coordsFS:SetTextColor(0.85, 0.85, 0.85)
            row.copyBtn:Enable()
        else
            row.coordText = nil
            row.coordsFS:SetText(L.PL_OUTOFAREA)
            row.coordsFS:SetTextColor(0.5, 0.5, 0.5)
            row.copyBtn:Disable()
        end
    end
    local n = #shown
    for i = n + 1, #rowPool do rowPool[i]:Hide() end

    content:SetHeight(math.max(1, n * ROW_H))
    local vis = math.max(1, math.min(n, MAX_VIS))
    panel:SetHeight(HEADER_H + FILTER_H + vis * ROW_H + PAD)
    panel.title:SetText(string.format("SpotMe · %s  (%d)", L.PL_TITLE, n))
end

function ns.ToggleParty()
    EnsurePanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        Refresh()
    end
end

--=============================================================================
-- Minimap button
--=============================================================================
local mbtn

local function UpdateButtonPos()
    if not mbtn then return end
    local angle = math.rad(ns.GetCfg().minimapButton.angle or 214)
    local r = (Minimap:GetWidth() / 2) + 5
    mbtn:ClearAllPoints()
    mbtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function ButtonDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.GetCfg().minimapButton.angle = math.deg(math.atan2(cy - my, cx - mx))
    UpdateButtonPos()
end

local function EnsureButton()
    if mbtn or not Minimap then return end
    mbtn = CreateFrame("Button", "SpotMeMinimapButton", Minimap)
    mbtn:SetSize(31, 31)
    mbtn:SetFrameStrata("MEDIUM")
    mbtn:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    mbtn:RegisterForClicks("LeftButtonUp")
    mbtn:RegisterForDrag("LeftButton")

    local icon = mbtn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = mbtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    mbtn:SetScript("OnDragStart", function() mbtn:SetScript("OnUpdate", ButtonDragUpdate) end)
    mbtn:SetScript("OnDragStop", function() mbtn:SetScript("OnUpdate", nil) end)
    mbtn:SetScript("OnClick", function() ns.ToggleParty() end)
    mbtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SpotMe")
        GameTooltip:AddLine(L.PL_BTN_TIP, 1, 1, 1)
        GameTooltip:Show()
    end)
    mbtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdateButtonPos()
end

function ns.ToggleMinimapButton()
    local db = ns.GetCfg().minimapButton
    db.hide = not db.hide
    if mbtn then mbtn:SetShown(not db.hide) end
    return not db.hide
end

--=============================================================================
-- Load + tickers
--=============================================================================
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    EnsureButton()
    if mbtn then mbtn:SetShown(not ns.GetCfg().minimapButton.hide) end
end)

local roster = CreateFrame("Frame")
roster:RegisterEvent("GROUP_ROSTER_UPDATE")
roster:SetScript("OnEvent", function() Refresh() end)

-- Follow the highlighted member (~33/s) and refresh coords in the panel (~5/s).
local ticker = CreateFrame("Frame")
local slowAcc, fastAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    fastAcc = fastAcc + elapsed
    if fastAcc >= 0.03 then
        fastAcc = 0
        if highlightUnit then UpdateHighlight() end
        if navUnit then UpdateNav() end
    end
    slowAcc = slowAcc + elapsed
    if slowAcc >= 0.2 then
        slowAcc = 0
        if panel and panel:IsShown() then Refresh() end
    end
end)
