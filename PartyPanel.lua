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
    else
        t[1] = "player"   -- solo: still show yourself
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
local navUnit, navPoint     -- navigating to a group member, or to a fixed map point
local navR, navG, navB = 1, 1, 1
local arrow, pathParent
local pathDots = {}
-- If the arrow points the wrong way in game, flip SIGN (1/-1) or add pi to OFFSET.
local NAV_ROT_SIGN, NAV_ROT_OFFSET = -1, 0
local NAV_COLORS = {
    red    = { 1.00, 0.15, 0.15 }, cyan   = { 0.25, 0.80, 1.00 },
    green  = { 0.20, 1.00, 0.35 }, yellow = { 1.00, 0.90, 0.20 },
    black  = { 0.05, 0.05, 0.05 }, white  = { 1.00, 1.00, 1.00 },
    pink   = { 1.00, 0.40, 0.75 },
}
local UpdateNav, ClearNav   -- forward declarations

-- Resolve a color choice ("class" or a NAV_COLORS palette key) to r, g, b.
-- "class" falls back to the target unit's class color, or the player's for a map point.
local function ResolveNavColor(choice)
    local ccol = NAV_COLORS[choice or "class"]
    if ccol then return ccol[1], ccol[2], ccol[3] end
    if navUnit then return ClassColor(navUnit) end
    return ClassColor("player")
end

local function EnsureArrow()
    if arrow then return end
    arrow = CreateFrame("Frame", "SpotMeNavArrow", UIParent)
    arrow:SetSize(60, 60)
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

    -- black outline behind for pop/contrast
    local outline = arrow:CreateTexture(nil, "ARTWORK")
    outline:SetTexture("Interface\\Minimap\\MinimapArrow")
    outline:SetDesaturated(true)
    outline:SetVertexColor(0, 0, 0, 0.9)
    outline:SetPoint("CENTER")
    outline:SetSize(54, 54)
    arrow.outline = outline

    local tex = arrow:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    tex:SetDesaturated(true)   -- accurate class tint
    tex:SetPoint("CENTER")
    tex:SetSize(46, 46)
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

-- Path-marker shapes: dots (circle), dashes (rotated bar), arrows (rotated), line.
local CIRCLE_TEX = "Interface\\Masks\\CircleMaskScalable"
local DASH_TEX   = "Interface\\Buttons\\WHITE8X8"
local ARROW_TEX  = "Interface\\Minimap\\MinimapArrow"
-- Flip if dashes/arrows point the wrong way in game.
local DASH_ROT_SIGN, ARROW_ROT_SIGN = 1, 1
local FLOW_SPEED = 34   -- screen px/sec for the "marching" animation

-- texture + fill(w,h) + back(w,h) for a marker style
local function MarkerDims(style, size, rim)
    if style == "dashes" then
        local l, t = size * 2.6, math.max(2, size * 0.65)
        return DASH_TEX, l, t, l + 2 * rim, t + 2 * rim
    elseif style == "arrows" then
        local s = size * 2.0
        return ARROW_TEX, s, s, s + 2 * rim, s + 2 * rim
    end
    return CIRCLE_TEX, size, size, size + 2 * rim, size + 2 * rim
end

-- rotation to align a marker with the on-screen path direction (x right, y up)
local function MarkerAngle(style, dx, dy)
    if style == "arrows" then return ARROW_ROT_SIGN * math.atan2(-dx, dy) end
    return DASH_ROT_SIGN * math.atan2(dy, dx)
end

local function StyleMarker(fill, back, style, size, rim, rimOn)
    local tex, fw, fh, bw, bh = MarkerDims(style, size, rim)
    fill:SetTexture(tex); fill:SetSize(fw, fh); fill:SetDesaturated(style == "arrows")
    back:SetTexture(tex); back:SetSize(bw, bh); back:SetDesaturated(style == "arrows")
    back:SetShown(rimOn)
    if style ~= "dashes" and style ~= "arrows" then
        fill:SetRotation(0); back:SetRotation(0)
    end
end

local function StyleWorldMarker(d)
    local c = ns.GetCfg()
    StyleMarker(d.inner.fill, d.inner.back, c.ndWorldStyle, c.ndWorldSize,
        c.ndWorldRimOn and c.ndWorldRim or 0, c.ndWorldRimOn)
end

local function EnsurePathParent()
    if pathParent then return end
    pathParent = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pathParent:SetAllPoints()
    pathParent:SetFrameStrata("HIGH")
end

local function GetDot(i)
    local d = pathDots[i]
    if not d then
        EnsurePathParent()
        d = CreateFrame("Frame", nil, pathParent)   -- positioner (canvas coords, scale 1)
        d:SetSize(1, 1)
        local inner = CreateFrame("Frame", nil, d)   -- constant on-screen size (counter-scaled)
        inner:SetPoint("CENTER")
        local back = inner:CreateTexture(nil, "ARTWORK")
        back:SetVertexColor(0, 0, 0, 1)
        back:SetPoint("CENTER")
        local fill = inner:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("CENTER")
        inner.back = back
        inner.fill = fill
        d.inner = inner
        pathDots[i] = d
        StyleWorldMarker(d)
    end
    return d
end

local function HideDots()
    for _, d in ipairs(pathDots) do d:Hide() end
end

local miniDots = {}
local MINI_ROT_SIGN = 1   -- flip if the minimap path mirrors when rotateMinimap is on

local function StyleMiniMarker(d)
    local c = ns.GetCfg()
    StyleMarker(d.fill, d.back, c.ndMiniStyle, c.ndMiniSize,
        c.ndMiniRimOn and c.ndMiniRim or 0, c.ndMiniRimOn)
end

local function GetMiniDot(i)
    local d = miniDots[i]
    if not d then
        d = CreateFrame("Frame", nil, Minimap)
        d:SetSize(1, 1)
        d:SetFrameStrata(Minimap:GetFrameStrata())
        d:SetFrameLevel(Minimap:GetFrameLevel() + 9)
        local back = d:CreateTexture(nil, "ARTWORK")
        back:SetVertexColor(0, 0, 0, 1); back:SetPoint("CENTER")
        local fill = d:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("CENTER")
        d.back = back
        d.fill = fill
        miniDots[i] = d
        StyleMiniMarker(d)
    end
    return d
end

local function HideMiniDots()
    for _, d in ipairs(miniDots) do d:Hide() end
end

-- Re-apply marker styles to every pooled marker (called when a style/size setting changes).
local function RestyleDots()
    for _, d in ipairs(pathDots) do StyleWorldMarker(d) end
    for _, d in ipairs(miniDots) do StyleMiniMarker(d) end
end
ns.RestyleDots = RestyleDots

-- Solid-line style: a colored line plus a black line behind it for the outline.
local worldLine, worldLineBack, miniLine, miniLineBack
local function EnsureWorldLine()
    if worldLine then return end
    EnsurePathParent()
    worldLineBack = pathParent:CreateLine(nil, "ARTWORK")
    worldLineBack:SetColorTexture(0, 0, 0, 1)
    worldLine = pathParent:CreateLine(nil, "OVERLAY")
    worldLine:SetColorTexture(1, 1, 1, 1)
end
local function EnsureMiniLine()
    if miniLine then return end
    miniLineBack = Minimap:CreateLine(nil, "ARTWORK")
    miniLineBack:SetColorTexture(0, 0, 0, 1)
    miniLine = Minimap:CreateLine(nil, "OVERLAY")
    miniLine:SetColorTexture(1, 1, 1, 1)
end
local function HideWorldLine() if worldLine then worldLine:Hide(); worldLineBack:Hide() end end
local function HideMiniLine()  if miniLine then miniLine:Hide(); miniLineBack:Hide() end end

-- "Clear route" button on the world map, shown while a route is active so the
-- route can be cleared without leaving the map.
local mapClearBtn
local function EnsureMapClearBtn()
    if mapClearBtn or not WorldMapFrame then return end
    local b = CreateFrame("Button", "SpotMeMapClearBtn", WorldMapFrame, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b:SetText(L.PL_CLEAR_ROUTE)
    b:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 500)   -- above the map pins
    b:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer or WorldMapFrame, "BOTTOM", 0, 14)
    b:SetScript("OnClick", function() ClearNav() end)
    b:Hide()
    mapClearBtn = b
end

-- Current nav target's world position (UnitPosition order: 1st ~ y/north,
-- 2nd ~ x/east) + instance, used for the arrow bearing and distance.
local function NavTargetWorld()
    if navUnit then
        if not UnitExists(navUnit) then return nil end
        local ty, tx, _, tI = UnitPosition(navUnit)
        return ty, tx, tI
    elseif navPoint then
        local cont, wp = C_Map.GetWorldPosFromMapPos(navPoint.mapID, CreateVector2D(navPoint.x, navPoint.y))
        if cont and wp then return wp.x, wp.y, cont end   -- swap to wp.y, wp.x if the point arrow mirrors
    end
    return nil
end

-- Convert a world position to 0-1 coords on a given ui map by solving the map's
-- affine world<->map transform from three corners. Convention-agnostic (no axis
-- guessing) and works across related maps, the way Blizzard resolves unit pins.
local function WorldToMapPos(mapID, wx, wy)
    local _, o  = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, ux = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
    local _, uy = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
    if not (o and ux and uy) then return nil end
    local axx, axy = ux.x - o.x, ux.y - o.y
    local ayx, ayy = uy.x - o.x, uy.y - o.y
    local det = axx * ayy - axy * ayx
    if det == 0 then return nil end
    local px, py = wx - o.x, wy - o.y
    return (px * ayy - py * ayx) / det, (axx * py - axy * px) / det
end

-- Target position (0-1) on a given ui map, for the dotted paths.
local function NavTargetMapPos(mapID)
    if not mapID then return nil end
    if navUnit then
        local p = C_Map.GetPlayerMapPosition(mapID, navUnit)
        if p then return p:GetXY() end
    elseif navPoint then
        if navPoint.mapID == mapID then
            return navPoint.x, navPoint.y   -- same map: stored coords
        end
        -- Blizzard's own cross-map translation of our waypoint (parent/child/sibling zones)
        if C_Map.GetUserWaypointPositionForMap then
            local wp = C_Map.GetUserWaypointPositionForMap(mapID)
            if wp then local x, y = wp:GetXY(); if x then return x, y end end
        end
        -- fallback: project via world coordinates
        local _, w2 = C_Map.GetWorldPosFromMapPos(navPoint.mapID, CreateVector2D(navPoint.x, navPoint.y))
        if w2 then
            local mx, my = WorldToMapPos(mapID, w2.x, w2.y)
            if mx then return mx, my end
        end
    end
    return nil
end

-- Player position (0-1) on a given ui map. Projects via world coords when the
-- player is not standing in the viewed zone, so the path shows on other zones too.
local function PlayerMapPos(mapID)
    local p = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if p then local x, y = p:GetXY(); if x then return x, y end end
    local py, px = UnitPosition("player")
    if py and mapID then return WorldToMapPos(mapID, py, px) end
    return nil
end

function UpdateNav()
    if not navUnit and not navPoint then
        if arrow then arrow:Hide() end
        HideDots(); HideMiniDots(); HideWorldLine(); HideMiniLine()
        return
    end
    if navUnit and not UnitExists(navUnit) then ClearNav(); return end

    EnsureMapClearBtn()
    if mapClearBtn then mapClearBtn:SetShown(WorldMapFrame:IsShown()) end

    -- arrow color (navColor) and dot color (dotColor) resolved independently
    navR, navG, navB = ResolveNavColor(ns.GetCfg().navColor)
    local dotR, dotG, dotB = ResolveNavColor(ns.GetCfg().dotColor)

    -- world position of the player and the target (for the arrow + distance)
    local py, px, _, pI = UnitPosition("player")
    local ty, tx, tI = NavTargetWorld()
    local facing = GetPlayerFacing()
    local worldDist
    if py and ty and pI == tI then
        local ddx, ddy = tx - px, ty - py
        worldDist = math.sqrt(ddx * ddx + ddy * ddy)
    end

    -- on-screen arrow
    if arrow then
        if py and ty and pI == tI and facing then
            local dx, dy = tx - px, ty - py
            local bearing = math.atan2(dx, dy)
            local arot = NAV_ROT_SIGN * (facing - bearing) + NAV_ROT_OFFSET
            arrow.tex:SetRotation(arot)
            arrow.outline:SetRotation(arot)
            arrow.tex:SetVertexColor(navR, navG, navB)
            arrow.dist:SetText(string.format("%d %s", worldDist or 0, L.PL_YD))
            arrow.dist:SetTextColor(navR, navG, navB)
            arrow:Show()
        else
            arrow:Hide()
        end
    end

    -- path on the world map (dots / dashes / arrows / line; straight — no routing)
    local wcfg = ns.GetCfg()
    if wcfg.ndWorldShow and WorldMapFrame:IsShown() and WorldMapFrame.GetCanvas then
        local mapID = WorldMapFrame:GetMapID()
        local pmx, pmy = PlayerMapPos(mapID)
        local tmx, tmy = NavTargetMapPos(mapID)
        if pmx and tmx then
            local canvas = WorldMapFrame:GetCanvas()
            local w, h = canvas:GetSize()
            local zoom = ns.CanvasZoom()
            local isc = (zoom > 0) and (1 / zoom) or 1
            if isc < 0.5 then isc = 0.5 elseif isc > 3 then isc = 3 end
            local style = wcfg.ndWorldStyle
            if style == "line" then
                HideDots()
                EnsureWorldLine()
                local rim = wcfg.ndWorldRimOn and wcfg.ndWorldRim or 0
                worldLine:SetThickness(wcfg.ndWorldSize * isc)
                worldLine:SetStartPoint("TOPLEFT", canvas, pmx * w, -pmy * h)
                worldLine:SetEndPoint("TOPLEFT", canvas, tmx * w, -tmy * h)
                worldLine:SetColorTexture(dotR, dotG, dotB, 1)
                worldLine:Show()
                if wcfg.ndWorldRimOn then
                    worldLineBack:SetThickness((wcfg.ndWorldSize + 2 * rim) * isc)
                    worldLineBack:SetStartPoint("TOPLEFT", canvas, pmx * w, -pmy * h)
                    worldLineBack:SetEndPoint("TOPLEFT", canvas, tmx * w, -tmy * h)
                    worldLineBack:Show()
                else worldLineBack:Hide() end
            else
                HideWorldLine()
                local dxp, dyp = (tmx - pmx) * w, (tmy - pmy) * h
                local pathU = math.sqrt(dxp * dxp + dyp * dyp)
                local stepU = (zoom > 0) and (wcfg.ndWorldGap / zoom) or (math.min(w, h) * 0.02)
                local rot = (style == "dashes" or style == "arrows")
                local ang = rot and MarkerAngle(style, dxp, -dyp) or 0
                local phase = (wcfg.ndWorldAnim and stepU > 0) and ((GetTime() * FLOW_SPEED * isc) % stepU) or 0
                local n, dd = 0, (phase > 0 and phase or stepU)
                while stepU > 0 and dd < pathU and n < 200 do
                    local t = dd / pathU
                    n = n + 1
                    local mx = pmx + (tmx - pmx) * t
                    local my = pmy + (tmy - pmy) * t
                    local d = GetDot(n)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
                    d.inner:SetScale(isc)
                    d.inner.fill:SetVertexColor(dotR, dotG, dotB)
                    if rot then d.inner.fill:SetRotation(ang); d.inner.back:SetRotation(ang) end
                    d:Show()
                    dd = dd + stepU
                end
                for i = n + 1, #pathDots do pathDots[i]:Hide() end
            end
        else
            HideDots(); HideWorldLine()
        end
    else
        HideDots(); HideWorldLine()
    end

    -- dotted path on the minimap: direction from the zone map (north-up, matches
    -- the world map), dots spaced by a fixed pixel step so they never overlap.
    local mcfg = ns.GetCfg()
    local zmap = C_Map.GetBestMapForUnit("player")
    local pp = zmap and C_Map.GetPlayerMapPosition(zmap, "player")
    local tmx, tmy = NavTargetMapPos(zmap)
    if mcfg.ndMiniShow and pp and tmx then
        local pmx, pmy = pp:GetXY()
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
            local pixelLen = math.min((worldDist or 0) * (half / radius), half - 6)
            local style = mcfg.ndMiniStyle
            if style == "line" then
                HideMiniDots()
                EnsureMiniLine()
                local rim = mcfg.ndMiniRimOn and mcfg.ndMiniRim or 0
                miniLine:SetThickness(mcfg.ndMiniSize)
                miniLine:SetStartPoint("CENTER", Minimap, 0, 0)
                miniLine:SetEndPoint("CENTER", Minimap, ux * pixelLen, uy * pixelLen)
                miniLine:SetColorTexture(dotR, dotG, dotB, 1)
                miniLine:Show()
                if mcfg.ndMiniRimOn then
                    miniLineBack:SetThickness(mcfg.ndMiniSize + 2 * rim)
                    miniLineBack:SetStartPoint("CENTER", Minimap, 0, 0)
                    miniLineBack:SetEndPoint("CENTER", Minimap, ux * pixelLen, uy * pixelLen)
                    miniLineBack:Show()
                else miniLineBack:Hide() end
            else
                HideMiniLine()
                local rot = (style == "dashes" or style == "arrows")
                local ang = rot and MarkerAngle(style, ux, uy) or 0
                local step = mcfg.ndMiniGap
                local phase = (mcfg.ndMiniAnim and step > 0) and ((GetTime() * FLOW_SPEED) % step) or 0
                local n, dd = 0, (phase > 0 and phase or step)
                while dd <= pixelLen do
                    n = n + 1
                    local d = GetMiniDot(n)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", Minimap, "CENTER", ux * dd, uy * dd)
                    d.fill:SetVertexColor(dotR, dotG, dotB)
                    if rot then d.fill:SetRotation(ang); d.back:SetRotation(ang) end
                    d:Show()
                    dd = dd + step
                end
                for i = n + 1, #miniDots do miniDots[i]:Hide() end
            end
        else
            HideMiniDots(); HideMiniLine()
        end
    else
        HideMiniDots(); HideMiniLine()
    end
end

function ClearNav()
    navUnit = nil
    navPoint = nil
    if arrow then arrow:Hide() end
    if mapClearBtn then mapClearBtn:Hide() end
    HideDots(); HideMiniDots(); HideWorldLine(); HideMiniLine()
end

local function StartNav(unit)
    if navUnit == unit then ClearNav(); return end   -- right-click again to stop
    local mapID = UnitMapPos(unit)
    if not mapID then return end
    navUnit = unit
    navPoint = nil
    navR, navG, navB = ClassColor(unit)
    EnsureArrow()
    WaypointTo(unit)   -- also drop the Blizzard minimap pin
    UpdateNav()
end

-- Navigate to any point on the world map (Shift + left-click on the map).
local function StartNavToPoint(mapID, x, y)
    navUnit = nil
    navPoint = { mapID = mapID, x = x, y = y }
    EnsureArrow()
    if not (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID)) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
    UpdateNav()
end

-- Shift + left-click anywhere on the world map starts a path to that spot.
local function HookMapClick()
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not sc or sc.spotmeNavHooked then return end
    sc.spotmeNavHooked = true
    sc:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        if not self.GetNormalizedCursorPosition then return end
        local nx, ny = self:GetNormalizedCursorPosition()
        if not nx or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
        local mapID = WorldMapFrame:GetMapID()
        if mapID then StartNavToPoint(mapID, nx, ny) end
    end)
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

    -- settings button, same style as the sort ("By class") button, top-right
    local setBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    setBtn:SetSize(80, 20)
    setBtn:SetPoint("RIGHT", close, "LEFT", 0, -4)
    setBtn:SetText(L.PL_SETTINGS)
    setBtn:SetScript("OnClick", function() if ns.OpenSettings then ns.OpenSettings() end end)
    panel.setBtn = setBtn

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
    empty:SetPoint("TOP", 0, -(HEADER_H + 8))   -- filter-row strip (shown when solo)
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

    local inGroup = IsInGroup()
    local units = BuildUnitList()          -- includes "player" even when solo
    local db = ns.GetCfg().classFilter

    if inGroup then
        panel.empty:Hide()
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
    else
        panel.empty:Show()                 -- keep "You are not in a party"
        for _, b in pairs(filterIcons) do b:Hide() end
    end

    -- filter by class (only applies in a group)
    local shown = {}
    for _, unit in ipairs(units) do
        local cf = ClassFile(unit)
        if not inGroup or not (cf and db[cf]) then shown[#shown + 1] = unit end
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
    if inGroup then
        panel.title:SetText(string.format("%s  (%d)", L.PL_TITLE, n))
    else
        panel.title:SetText(L.PL_TITLE)
    end
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
        GameTooltip:AddLine(L.PL_MAP_HINT, 0.7, 0.7, 0.7, true)
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
    HookMapClick()
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
        if navUnit or navPoint then UpdateNav() end
    end
    slowAcc = slowAcc + elapsed
    if slowAcc >= 0.2 then
        slowAcc = 0
        if panel and panel:IsShown() then Refresh() end
    end
end)
