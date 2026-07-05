-- SpotMe Party Locator.
--
-- A minimap button opens a scrollable panel listing the group (party or raid).
-- Each row shows the member's class-colored name, their map coordinates and a
-- copy button. Clicking a member opens the world map on their zone with a
-- class-colored glow on their position.
--
-- Reuses the glow factory from Core via the shared `ns` table.

local _, ns = ...
local L = ns.L

local SCALE_MIN, SCALE_MAX = 0.7, 2.5

local PANEL_W    = 320
local HEADER_H   = 34
local ROW_H      = 40
local PAD        = 12
local SB_W       = 24            -- space reserved for the scrollbar
local MAX_VIS    = 9             -- rows visible before scrolling
local ROW_W      = PANEL_W - 2 * PAD - SB_W

--=============================================================================
-- Helpers
--=============================================================================
local function ClassColor(unit)
    local _, classFile = UnitClass(unit)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile)
    c = c or (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
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

-- Party -> player + party1..N; raid -> raid1..N; solo -> just the player.
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
-- Party panel (scrollable list)
--=============================================================================
local panel, content, rowPool

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

    row:SetScript("OnClick", function(self)
        if self.unit and self.coordText then HighlightMember(self.unit) end
    end)
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

local function EnsurePanel()
    if panel then return end
    panel = CreateFrame("Frame", "SpotMePartyPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, HEADER_H + ROW_H + PAD)
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

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOP", 0, -(HEADER_H + 10))
    empty:SetText(L.PL_NOPARTY)
    panel.empty = empty

    local scroll = CreateFrame("ScrollFrame", "SpotMePartyScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -HEADER_H)
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

    rowPool = {}

    local pt = ns.GetCfg().partyPanel
    if pt and pt[1] then
        panel:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        panel:SetPoint("CENTER")
    end
    panel:Hide()
end

local function Refresh()
    if not panel or not panel:IsShown() then return end

    if not IsInGroup() then
        panel.title:SetText("SpotMe · " .. L.PL_TITLE)
        panel.empty:Show()
        for _, row in pairs(rowPool) do row:Hide() end
        content:SetHeight(1)
        panel:SetHeight(HEADER_H + 48)
        return
    end
    panel.empty:Hide()

    local units = BuildUnitList()
    for i, unit in ipairs(units) do
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
            row.coordsFS:SetText(row.coordText)
            row.coordsFS:SetTextColor(0.85, 0.85, 0.85)
            row.copyBtn:Enable()
        else
            row.coordText = nil
            row.coordsFS:SetText(L.PL_OUTOFAREA)
            row.coordsFS:SetTextColor(0.5, 0.5, 0.5)
            row.copyBtn:Disable()
        end
    end
    for i = #units + 1, #rowPool do rowPool[i]:Hide() end

    content:SetHeight(math.max(1, #units * ROW_H))
    local vis = math.min(#units, MAX_VIS)
    panel:SetHeight(HEADER_H + vis * ROW_H + PAD)
    panel.title:SetText(string.format("SpotMe · %s  (%d)", L.PL_TITLE, #units))
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
roster:SetScript("OnEvent", Refresh)

-- Follow the highlighted member (~33/s) and refresh coords in the panel (~5/s).
local ticker = CreateFrame("Frame")
local slowAcc, fastAcc = 0, 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    fastAcc = fastAcc + elapsed
    if fastAcc >= 0.03 then
        fastAcc = 0
        if highlightUnit then UpdateHighlight() end
    end
    slowAcc = slowAcc + elapsed
    if slowAcc >= 0.2 then
        slowAcc = 0
        if panel and panel:IsShown() then Refresh() end
    end
end)
