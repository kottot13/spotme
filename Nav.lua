-- SpotMe navigation module.
--
-- TomTom-style navigation to a group member or a fixed map point: an on-screen
-- arrow plus a customizable path (dots/dashes/arrows/line) on the world map and
-- the minimap. Extracted from PartyPanel.lua; PartyPanel and Core drive it via
-- the shared `ns` table (ns.StartNav / ns.StartNavToPoint / ns.ClearNav /
-- ns.ParseCoords / ns.ResolveInputMap / ns.OnNavTargetChanged).

local _, ns = ...
local L = ns.L

--=============================================================================
-- Unit helpers (shared with PartyPanel via ns)
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

-- Blizzard's own map pin. Setting and super-tracking it makes the GAME draw its white
-- dotted trail and take over quest tracking, and that pin lives in the client — it
-- outlives our route (and the addon) unless we clear it, which is why `ourWaypoint`
-- is tracked and ClearNav drops it.
local ourWaypoint = false

local function SetGameWaypoint(mapID, x, y)
    local c = ns.GetCfg()
    if not (c and c.gameWaypoint) then return end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    ourWaypoint = true
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

local function ClearGameWaypoint()
    if not ourWaypoint then return end   -- never clear a pin the player set themselves
    ourWaypoint = false
    if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
end

-- Drop a Blizzard navigation waypoint on the member's position (not protected).
local function WaypointTo(unit)
    local mapID, x, y = UnitMapPos(unit)
    if not mapID then return end
    SetGameWaypoint(mapID, x, y)
end

--=============================================================================
-- Navigation state: on-screen arrow + dotted map path (class colored)
--=============================================================================
local navUnit               -- navigating to a group member (session only, a unit token
                            -- means nothing after a relog)
-- Routing to fixed points is a QUEUE that lives in SpotMeDB.navChain, so it survives a
-- reload. Element [1] is always the current target, which lets every existing behavior
-- (arrow, distance, arrival, coordinate field, chat message) keep working on the head:
-- an ordinary one-point route is simply a chain of length 1, not a separate code path.
local MAX_CHAIN = 10
local function Chain()
    local c = ns.GetCfg()
    return c and c.navChain
end
local function Head()
    local c = Chain()
    return c and c[1]
end
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

local function StyleMarker(container, fill, back, style, size, rim, rimOn)
    local tex, fw, fh, bw, bh = MarkerDims(style, size, rim)
    container:SetSize(bw, bh)   -- container must have a real size or SetScale renders nothing
    fill:SetTexture(tex); fill:SetSize(fw, fh); fill:SetDesaturated(style == "arrows")
    back:SetTexture(tex); back:SetSize(bw, bh); back:SetDesaturated(style == "arrows")
    back:SetShown(rimOn)
    if style ~= "dashes" and style ~= "arrows" then
        fill:SetRotation(0); back:SetRotation(0)
    end
end

local function StyleWorldMarker(d)
    local c = ns.GetCfg()
    StyleMarker(d.inner, d.inner.fill, d.inner.back, c.ndWorldStyle, c.ndWorldSize,
        c.ndWorldRimOn and c.ndWorldRim or 0, c.ndWorldRimOn)
end

local function EnsurePathParent()
    if pathParent then return end
    pathParent = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pathParent:SetAllPoints()
    pathParent:SetFrameStrata("HIGH")
    -- Keep markers and lines inside the map: a target that resolves outside the
    -- canvas must not trail across the rest of the screen.
    if pathParent.SetClipsChildren then pathParent:SetClipsChildren(true) end
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
    StyleMarker(d, d.fill, d.back, c.ndMiniStyle, c.ndMiniSize,
        c.ndMiniRimOn and c.ndMiniRim or 0, c.ndMiniRimOn)
end

local function GetMiniDot(i)
    local d = miniDots[i]
    if not d then
        -- on the cluster rather than on Minimap itself (see ns.MinimapParent),
        -- anchored to Minimap so the geometry is unchanged
        d = CreateFrame("Frame", nil, ns.MinimapParent())
        d:SetSize(1, 1)
        d:SetFrameStrata("MEDIUM")
        d:SetFrameLevel(3900)
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
-- Pooled on the world map, since a chain needs one line per segment.
local miniLine, miniLineBack
local worldLines = {}
local function GetWorldLine(i)
    local wl = worldLines[i]
    if not wl then
        EnsurePathParent()
        local back = pathParent:CreateLine(nil, "ARTWORK")
        back:SetColorTexture(0, 0, 0, 1)
        local line = pathParent:CreateLine(nil, "OVERLAY")
        line:SetColorTexture(1, 1, 1, 1)
        wl = { line = line, back = back }
        worldLines[i] = wl
    end
    return wl
end
local function HideWorldLines(from)
    for i = from or 1, #worldLines do
        worldLines[i].line:Hide(); worldLines[i].back:Hide()
    end
end

-- Index labels (1, 2, 3…) drawn on the chain points; without them a multi-point
-- route does not say which way round it is walked.
local numTags = {}
local function GetNumTag(i)
    local t = numTags[i]
    if not t then
        EnsurePathParent()
        t = pathParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        numTags[i] = t
    end
    return t
end
local function HideNumTags(from)
    for i = from or 1, #numTags do numTags[i]:Hide() end
end
local miniLineHost
local function EnsureMiniLine()
    if miniLine then return end
    -- lines need a host frame off the cluster for the same reason as the dots
    miniLineHost = CreateFrame("Frame", nil, ns.MinimapParent())
    miniLineHost:SetAllPoints(Minimap)
    miniLineHost:SetFrameStrata("MEDIUM")
    miniLineHost:SetFrameLevel(3890)
    miniLineBack = miniLineHost:CreateLine(nil, "ARTWORK")
    miniLineBack:SetColorTexture(0, 0, 0, 1)
    miniLine = miniLineHost:CreateLine(nil, "OVERLAY")
    miniLine:SetColorTexture(1, 1, 1, 1)
end
local function HideMiniLine()  if miniLine then miniLine:Hide(); miniLineBack:Hide() end end

-- Draw one segment of the route as markers, continuing the SHARED marker budget so a
-- 10-point chain cannot multiply the dot count. Returns the new marker count.
local MAX_MARKERS = 200
local function DrawDotSegment(ax, ay, bx, by, n, canvas, w, h, isc, zoom, wcfg, dotR, dotG, dotB)
    local dxp, dyp = (bx - ax) * w, (by - ay) * h
    local pathU = math.sqrt(dxp * dxp + dyp * dyp)
    local stepU = (zoom > 0) and (wcfg.ndWorldGap / zoom) or (math.min(w, h) * 0.02)
    if stepU <= 0 or pathU <= 0 then return n end
    local style = wcfg.ndWorldStyle
    local rot = (style == "dashes" or style == "arrows")
    local ang = rot and MarkerAngle(style, dxp, -dyp) or 0
    local phase = wcfg.ndWorldAnim and ((GetTime() * wcfg.ndWorldFlow * isc) % stepU) or 0
    local dd, steps = (phase > 0 and phase or stepU), 0
    while dd < pathU and n < MAX_MARKERS and steps < 600 do
        local t = dd / pathU
        steps = steps + 1
        dd = dd + stepU
        local mx = ax + (bx - ax) * t
        local my = ay + (by - ay) * t
        -- Skip whatever falls off the map: a target that belongs to another map
        -- projects outside 0-1, and drawing it would run a trail of dots across
        -- the screen toward nothing.
        if mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
            n = n + 1
            local d = GetDot(n)
            d:ClearAllPoints()
            d:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
            d.inner:SetScale(isc)
            d.inner.fill:SetVertexColor(dotR, dotG, dotB)
            if rot then d.inner.fill:SetRotation(ang); d.inner.back:SetRotation(ang) end
            d:Show()
        end
    end
    return n
end

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
    end
    local p = Head()
    if p then
        local cont, wp = C_Map.GetWorldPosFromMapPos(p.mapID, CreateVector2D(p.x, p.y))
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

-- True only when the Blizzard user waypoint is our current target (same world spot). Guards
-- against following a stale/other waypoint left over from a previous or external point.
local function WaypointMatchesNav()
    local p = Head()
    if not (p and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.GetUserWaypoint) then
        return false
    end
    local up = C_Map.GetUserWaypoint()
    if not (up and up.position and up.uiMapID) then return false end
    local _, uw = C_Map.GetWorldPosFromMapPos(up.uiMapID, up.position)
    local _, nw = C_Map.GetWorldPosFromMapPos(p.mapID, CreateVector2D(p.x, p.y))
    if not (uw and nw) then return false end
    return math.abs(uw.x - nw.x) < 5 and math.abs(uw.y - nw.y) < 5
end

-- Position (0-1) of one stored point on a given ui map. `isHead` gates the Blizzard
-- waypoint shortcut, which only ever tracks the current target.
local function PointMapPos(pt, mapID, isHead)
    if not (pt and mapID) then return nil end
    if pt.mapID == mapID then
        return pt.x, pt.y   -- same map: stored coords
    end
    -- Blizzard's own cross-map translation of our waypoint: works on parent, sibling
    -- and the world/continent overviews (same position as the yellow waypoint pin).
    -- Only trust it when the Blizzard waypoint is actually our point.
    if isHead and C_Map.GetUserWaypointPositionForMap and WaypointMatchesNav() then
        local wp = C_Map.GetUserWaypointPositionForMap(mapID)
        if wp then local x, y = wp:GetXY(); if x then return x, y end end
    end
    -- fallback: affine world->map projection, but ONLY when the point and the viewed
    -- map are the same continent — cross-continent coords are unrelated and would
    -- project the point to a random (wrong) spot.
    local info = C_Map.GetMapInfo(mapID)
    if info and info.mapType and info.mapType >= 2 then
        local pcont, w2 = C_Map.GetWorldPosFromMapPos(pt.mapID, CreateVector2D(pt.x, pt.y))
        local mcont = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if w2 and pcont == mcont then
            local mx, my = WorldToMapPos(mapID, w2.x, w2.y)
            if mx then return mx, my end
        end
    end
    return nil
end

-- Current target position (0-1) on a given ui map, for the dotted paths.
local function NavTargetMapPos(mapID)
    if not mapID then return nil end
    if navUnit then
        local p = C_Map.GetPlayerMapPosition(mapID, navUnit)
        if p then return p:GetXY() end
        return nil
    end
    return PointMapPos(Head(), mapID, true)
end

-- Player position (0-1) on a given ui map. When the player isn't on the viewed map,
-- project via world coords if it's the SAME continent, so a path to a point in another
-- zone of the same continent still shows (heading off-map toward you). Cross-continent
-- has no shared coordinates, so we return nil there (the world overview still shows it).
local function PlayerMapPos(mapID)
    local p = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if p then local x, y = p:GetXY(); if x then return x, y end end
    local py, px, _, pInst = UnitPosition("player")
    if py and mapID then
        local cont = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if cont == pInst then return WorldToMapPos(mapID, py, px) end
    end
    return nil
end

-- Keep Blizzard's own waypoint pin on the current head point, so the built-in pin and
-- our route never disagree after the chain advances or a point is removed.
local function SyncWaypoint()
    local p = Head()
    if not p then return end
    SetGameWaypoint(p.mapID, p.x, p.y)
end

-- Tell the party panel (or anyone else) what we are navigating to, as display text.
local function NotifyNavTarget()
    if not ns.OnNavTargetChanged then return end
    if navUnit then
        local name = UnitName(navUnit) or "?"
        local _, x, y = UnitMapPos(navUnit)
        if x then
            ns.OnNavTargetChanged(string.format("%s · %.1f, %.1f", name, x * 100, y * 100))
        else
            ns.OnNavTargetChanged(name)
        end
    else
        local p, c = Head(), Chain()
        if p then
            local info = C_Map.GetMapInfo(p.mapID)
            local text = string.format("%.1f, %.1f — %s", p.x * 100, p.y * 100, (info and info.name) or "?")
            if c and #c > 1 then text = text .. string.format(" (1/%d)", #c) end
            ns.OnNavTargetChanged(text)
        else
            ns.OnNavTargetChanged(nil)
        end
    end
end

function UpdateNav()
    if not navUnit and not Head() then
        if arrow then arrow:Hide() end
        HideDots(); HideMiniDots(); HideWorldLines(1); HideNumTags(1); HideMiniLine()
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

    -- Arrived. With points still queued the head is dropped and the next one becomes the
    -- target; otherwise the route is cleared rather than left as a stale trail for hours.
    local arrive = ns.GetCfg().navArrive or 0
    if worldDist and arrive > 0 and worldDist <= arrive then
        local chain = Chain()
        if not navUnit and chain and #chain > 1 then
            table.remove(chain, 1)
            print("|cffff33aaSpotMe|r: " .. string.format(L.CHAIN_REACHED, #chain))
            SyncWaypoint()
            NotifyNavTarget()
            return
        end
        local wasChain = (not navUnit) and ns.GetCfg().chainMode
        ClearNav()
        print("|cffff33aaSpotMe|r: " .. (wasChain and L.CHAIN_DONE or L.NAV_ARRIVED))
        return
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
        -- Vertices: the player, then every target that resolves on the viewed map. A
        -- point that cannot be placed here ends the list — bridging over it would draw
        -- a segment to somewhere that is not actually the next stop.
        local verts = {}
        if pmx then
            verts[1] = { x = pmx, y = pmy }
            if navUnit then
                local tx2, ty2 = NavTargetMapPos(mapID)
                if tx2 then verts[2] = { x = tx2, y = ty2 } end
            else
                local chain = Chain() or {}
                for i = 1, #chain do
                    local cx, cy = PointMapPos(chain[i], mapID, i == 1)
                    if not cx then break end
                    verts[#verts + 1] = { x = cx, y = cy, idx = i }
                end
            end
        end

        if #verts >= 2 then
            local canvas = WorldMapFrame:GetCanvas()
            local w, h = canvas:GetSize()
            local zoom = ns.CanvasZoom()
            local isc = (zoom > 0) and (1 / zoom) or 1
            if isc < 0.5 then isc = 0.5 elseif isc > 3 then isc = 3 end
            local style = wcfg.ndWorldStyle
            local nDot, nLine = 0, 0

            for s = 1, #verts - 1 do
                local a, b = verts[s], verts[s + 1]
                if style == "line" then
                    nLine = nLine + 1
                    local wl = GetWorldLine(nLine)
                    local rim = wcfg.ndWorldRimOn and wcfg.ndWorldRim or 0
                    wl.line:SetThickness(wcfg.ndWorldSize * isc)
                    wl.line:SetStartPoint("TOPLEFT", canvas, a.x * w, -a.y * h)
                    wl.line:SetEndPoint("TOPLEFT", canvas, b.x * w, -b.y * h)
                    wl.line:SetColorTexture(dotR, dotG, dotB, 1)
                    wl.line:Show()
                    if wcfg.ndWorldRimOn then
                        wl.back:SetThickness((wcfg.ndWorldSize + 2 * rim) * isc)
                        wl.back:SetStartPoint("TOPLEFT", canvas, a.x * w, -a.y * h)
                        wl.back:SetEndPoint("TOPLEFT", canvas, b.x * w, -b.y * h)
                        wl.back:Show()
                    else wl.back:Hide() end
                else
                    nDot = DrawDotSegment(a.x, a.y, b.x, b.y, nDot,
                        canvas, w, h, isc, zoom, wcfg, dotR, dotG, dotB)
                end
            end

            -- number the stops once there is more than one, so the order is readable
            local nTag = 0
            if #verts > 2 then
                for s = 2, #verts do
                    local v = verts[s]
                    if v.idx and v.x >= 0 and v.x <= 1 and v.y >= 0 and v.y <= 1 then
                        nTag = nTag + 1
                        local t = GetNumTag(nTag)
                        t:ClearAllPoints()
                        t:SetPoint("CENTER", canvas, "TOPLEFT", v.x * w, -v.y * h)
                        t:SetText(tostring(v.idx))
                        t:SetTextColor(dotR, dotG, dotB)
                        t:SetScale(isc)
                        t:Show()
                    end
                end
            end
            HideNumTags(nTag + 1)

            if style == "line" then
                HideDots(); HideWorldLines(nLine + 1)
            else
                HideWorldLines(1)
                for i = nDot + 1, #pathDots do pathDots[i]:Hide() end
            end
        else
            HideDots(); HideWorldLines(1); HideNumTags(1)
        end
    else
        HideDots(); HideWorldLines(1); HideNumTags(1)
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
                local phase = (mcfg.ndMiniAnim and step > 0) and ((GetTime() * mcfg.ndMiniFlow) % step) or 0
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
    ClearGameWaypoint()     -- the game's pin and its white trail outlive us otherwise
    navUnit = nil
    local c = Chain()
    if c then wipe(c) end   -- wipe, not reassign: the table lives in SpotMeDB
    if arrow then arrow:Hide() end
    if mapClearBtn then mapClearBtn:Hide() end
    HideDots(); HideMiniDots(); HideWorldLines(1); HideNumTags(1); HideMiniLine()
    NotifyNavTarget()
end

-- /sm navtest — prints why the world-map path may not resolve on the current map.
function ns.NavDebug()
    local function p(s) print("|cffff33aaSpotMe|r: " .. s) end
    local head, chain = Head(), Chain()
    if not (navUnit or head) then
        p("no active route — right-click a member or Shift+click the map first"); return
    end
    p("navUnit=" .. tostring(navUnit) .. " points=" .. (chain and #chain or 0) .. " head=" ..
        (head and (head.mapID .. " " .. string.format("%.1f,%.1f", head.x * 100, head.y * 100)) or "nil"))
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then p("world map is not open"); return end
    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    p("map=" .. tostring(mapID) .. " type=" .. tostring(info and info.mapType) .. " (" .. tostring(info and info.name) .. ")")
    local pp = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if pp then local x, y = pp:GetXY(); p(string.format("player: %.1f, %.1f", (x or 0) * 100, (y or 0) * 100))
    else p("player: NIL (not resolvable on this map)") end
    p("HasUserWaypoint=" .. tostring(C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()))
    if C_Map.GetUserWaypointPositionForMap and mapID then
        local wp = C_Map.GetUserWaypointPositionForMap(mapID)
        if wp then local x, y = wp:GetXY(); p(string.format("waypoint-on-map: %.1f, %.1f", (x or 0) * 100, (y or 0) * 100))
        else p("waypoint-on-map: NIL") end
    end
    local tmx, tmy = NavTargetMapPos(mapID)
    if tmx then p(string.format("target resolved: %.1f, %.1f  -> path SHOULD draw", tmx * 100, tmy * 100))
    else p("target resolved: NIL -> no path") end
end

local function StartNav(unit)
    if navUnit == unit then ClearNav(); return end   -- right-click again to stop
    local mapID = UnitMapPos(unit)
    if not mapID then return end
    navUnit = unit
    local c = Chain()
    if c then wipe(c) end
    navR, navG, navB = ClassColor(unit)
    EnsureArrow()
    WaypointTo(unit)   -- also drop the Blizzard minimap pin
    NotifyNavTarget()
    UpdateNav()
end

-- Navigate to any point on the world map (Shift + left-click on the map, the
-- panel coordinate field, or /sm <x> <y>).
local function StartNavToPoint(mapID, x, y)
    navUnit = nil
    local c = Chain()
    if not c then return end
    wipe(c)
    c[1] = { mapID = mapID, x = x, y = y }
    EnsureArrow()
    SyncWaypoint()
    local info = C_Map.GetMapInfo(mapID)
    print("|cffff33aaSpotMe|r: " .. string.format(L.PL_ROUTE_SET, x * 100, y * 100, (info and info.name) or "?"))
    NotifyNavTarget()
    UpdateNav()
end

-- Ctrl+Shift+click: append a stop, or remove the one clicked on (same gesture toggles).
local HIT_RADIUS = 20   -- screen pixels around a point that count as clicking it
local function AddOrRemoveChainPoint(mapID, x, y)
    local c = Chain()
    if not c then return end

    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local w, h
    if canvas then w, h = canvas:GetSize() end   -- `and` would truncate this to one value
    local zoom = ns.CanvasZoom() or 1
    for i = 1, #c do
        local px, py = PointMapPos(c[i], mapID, i == 1)
        if px and w then
            -- canvas units scale with zoom, so convert to screen pixels before comparing
            local dx, dy = (px - x) * w * zoom, (py - y) * h * zoom
            if math.sqrt(dx * dx + dy * dy) <= HIT_RADIUS then
                table.remove(c, i)
                print("|cffff33aaSpotMe|r: " .. string.format(L.CHAIN_REMOVED, i, #c))
                if i == 1 then SyncWaypoint() end
                NotifyNavTarget()
                UpdateNav()
                return
            end
        end
    end

    if #c >= MAX_CHAIN then
        print("|cffff33aaSpotMe|r: " .. string.format(L.CHAIN_FULL, MAX_CHAIN))
        return
    end
    c[#c + 1] = { mapID = mapID, x = x, y = y }
    EnsureArrow()
    if #c == 1 then SyncWaypoint() end
    local info = C_Map.GetMapInfo(mapID)
    print("|cffff33aaSpotMe|r: " .. string.format(L.CHAIN_ADDED, #c, x * 100, y * 100, (info and info.name) or "?"))
    NotifyNavTarget()
    UpdateNav()
end

-- Shift + left-click anywhere on the world map starts a path to that spot.
--
-- Registered through Blizzard's own canvas click handler rather than a raw
-- OnMouseUp hook on the scroll container. OnMouseUp also fires when the player
-- finishes PANNING the map, so the old hook dropped a route whenever the map
-- was dragged with Shift held. The engine calls a canvas click handler only
-- after WouldCursorPositionBeClick() passes, and skips it when a pin already
-- consumed the click. Returning true stops the map from also zooming in.
local mapClickHooked = false
local function HookMapClick()
    if mapClickHooked then return end
    if not (WorldMapFrame and WorldMapFrame.AddCanvasClickHandler) then return end
    mapClickHooked = true
    WorldMapFrame:AddCanvasClickHandler(function(_, button, cursorX, cursorY)
        if button ~= "LeftButton" or not IsShiftKeyDown() then return false end
        if not (cursorX and cursorY) then return false end
        if cursorX < 0 or cursorX > 1 or cursorY < 0 or cursorY > 1 then return false end
        local mapID = WorldMapFrame:GetMapID()
        if not mapID then return false end
        if IsControlKeyDown() then
            if not ns.GetCfg().chainMode then
                print("|cffff33aaSpotMe|r: " .. L.CHAIN_OFF)
            else
                AddOrRemoveChainPoint(mapID, cursorX, cursorY)
            end
        else
            StartNavToPoint(mapID, cursorX, cursorY)
        end
        return true
    end)
end

--=============================================================================
-- Coordinate input: parser + target-map resolution (used by /sm and the
-- party-panel coordinate field)
--=============================================================================

-- Parse "41.8 66.6", "41 66", "41.8, 66.6", "41.8,66.6" or "41,8 66,6"
-- (decimal comma) into x, y percentages. Returns nil for anything else,
-- including out-of-range values and ambiguous forms like "41,8,66,6".
local function ParseCoords(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or text:find("[^%d%s.,]") then return nil end
    local tokens = {}
    for tok in text:gmatch("%S+") do tokens[#tokens + 1] = tok end
    local a, b
    if #tokens == 2 then
        a = tokens[1]:gsub(",$", "")
        b = tokens[2]:gsub(",$", "")
        -- a comma inside a token is a decimal comma ("41,8") — turn it into a dot
        a = a:gsub(",", ".")
        b = b:gsub(",", ".")
    elseif #tokens == 1 then
        a, b = tokens[1]:match("^([%d%.]+),([%d%.]+)$")
    end
    local x, y = a and tonumber(a), b and tonumber(b)
    if not x or not y then return nil end
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    return x, y
end

-- Map that typed coordinates refer to: the map open on screen wins (so you can
-- flip to another zone and set a point there), otherwise the player's zone.
local function ResolveInputMap()
    if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID then
        local mapID = WorldMapFrame:GetMapID()
        if mapID then return mapID end
    end
    return C_Map.GetBestMapForUnit("player")
end

--=============================================================================
-- Exports + load
--=============================================================================
ns.StartNav = StartNav
ns.StartNavToPoint = StartNavToPoint
ns.ClearNav = ClearNav
ns.ParseCoords = ParseCoords
ns.ResolveInputMap = ResolveInputMap
ns.ClassFile = ClassFile
ns.ClassColor = ClassColor
ns.UnitMapPos = UnitMapPos

-- A route to a spot in another instance/continent cannot be walked to and would
-- only project far off the viewed map, so drop it when the player changes world.
local function DropRouteIfWorldChanged()
    if not (navUnit or Head()) then return end
    local _, _, _, pI = UnitPosition("player")
    local _, _, tI = NavTargetWorld()
    if pI and tI and pI ~= tI then
        ClearNav()
        print("|cffff33aaSpotMe|r: " .. L.NAV_DROPPED)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        -- Blizzard_WorldMap can load after us; register the click handler then.
        if addonName == "Blizzard_WorldMap" then HookMapClick() end
        return
    end
    HookMapClick()
    if event == "PLAYER_LOGIN" then
        -- A saved route comes back with the session. Say so out loud: a route that
        -- silently reappears is exactly the "it showed up on its own" complaint that
        -- v0.15.1 was about. Runs through Core's queue because the config is filled in
        -- on this same event and the order between files is not guaranteed.
        ns.RunWhenConfigReady(function()
            local c = Chain()
            if c and #c > 0 then
                EnsureArrow()
                print("|cffff33aaSpotMe|r: " .. string.format(L.CHAIN_RESTORED, #c))
                NotifyNavTarget()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- position data is not reliable the instant a zone finishes loading
        C_Timer.After(2, DropRouteIfWorldChanged)
    end
end)

-- Follow the active route (~33/s), same cadence the shared PartyPanel ticker used.
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.03 then return end
    acc = 0
    if navUnit or Head() then UpdateNav() end
end)
