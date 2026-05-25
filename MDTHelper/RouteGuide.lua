local H = MDTHelper

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local WIDTH = 240
local FONT = STANDARD_TEXT_FONT
local ROW_H = 26
local MOB_ROW_H = 28
local EXPANDED_TITLE_H = 4

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Bg(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    frame._bg = t
end

-- Track all background textures so we can fade them with the opacity slider
local bgTextures = {} -- { {tex, r, g, b, a}, ... }
local currentOpacity = 1

local function SetBg(frame, r, g, b, a)
    if not frame._bg then return end
    frame._bg:SetColorTexture(r, g, b, a * currentOpacity)
    -- Update tracked base values if registered
    if frame._bgIdx then
        local info = bgTextures[frame._bgIdx]
        info.r, info.g, info.b, info.a = r, g, b, a
    end
end

local function RegisterBg(frame, r, g, b, a)
    if frame._bg then
        bgTextures[#bgTextures + 1] = { tex = frame._bg, r = r, g = g, b = b, a = a }
        frame._bgIdx = #bgTextures
    end
end

local function RegisterTex(tex, r, g, b, a)
    bgTextures[#bgTextures + 1] = { tex = tex, r = r, g = g, b = b, a = a }
end

local function ApplyOpacity(alpha)
    currentOpacity = alpha
    for _, info in ipairs(bgTextures) do
        info.tex:SetColorTexture(info.r, info.g, info.b, info.a * alpha)
    end
end
function H:ApplyOpacity(alpha) ApplyOpacity(alpha) end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetTextColor(1, 1, 1)
    return fs
end

------------------------------------------------------------------------
-- Format forces as percentage of total
------------------------------------------------------------------------
local function ForcePct(forces)
    local needed = H.totalForcesRequired
    if needed and needed > 0 then
        return string.format("+%.1f%%", (forces / needed) * 100)
    end
    return "+" .. forces
end

------------------------------------------------------------------------
-- Safe portrait setter
------------------------------------------------------------------------
local function SetPortrait(texture, displayId)
    if displayId then
        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, texture, displayId)
        if not ok then
            texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local f = CreateFrame("Frame", "MDTHelperGuide", UIParent)
f:SetSize(WIDTH, 300)
f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() - WIDTH - 20, -200)
f:SetFrameStrata("MEDIUM")
f:EnableMouse(true)
f:Hide()
Bg(f, 0.04, 0.04, 0.04, 0.92)
RegisterBg(f, 0.04, 0.04, 0.04, 0.92)

do
    local isDragging = false
    local dragStartX, dragStartY, frameStartX, frameStartY

    f:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not H.db.locked then
            isDragging = true
            local es = self:GetEffectiveScale()
            dragStartX, dragStartY = GetCursorPosition()
            dragStartX = dragStartX / es
            dragStartY = dragStartY / es
            -- Read current TOPLEFT offset
            local _, _, _, ox, oy = self:GetPoint()
            frameStartX = ox or 0
            frameStartY = oy or 0
        end
    end)

    f:SetScript("OnMouseUp", function(self)
        if not isDragging then return end
        isDragging = false
        local _, _, _, x, y = self:GetPoint()
        H.db.framePoint = { "TOPLEFT", "TOPLEFT", x, y }
    end)

    local dragUpdate = CreateFrame("Frame")
    dragUpdate:SetScript("OnUpdate", function()
        if not isDragging then return end
        local es = f:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / es
        cy = cy / es
        local dx = cx - dragStartX
        local dy = cy - dragStartY
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", frameStartX + dx, frameStartY + dy)
    end)
end

------------------------------------------------------------------------
-- Header: "Pull 3/12" with nav buttons
------------------------------------------------------------------------
local headerBg = CreateFrame("Frame", nil, f)
headerBg:SetSize(WIDTH, 24)
headerBg:SetPoint("TOPLEFT", 0, 0)
Bg(headerBg, 0.08, 0.08, 0.08, 1)
RegisterBg(headerBg, 0.08, 0.08, 0.08, 1)

local headerText = Text(headerBg, 11, "CENTER")
headerText:SetPoint("CENTER")
headerText:SetTextColor(0, 0.8, 1)

local NAV_SZ = 16
local ICON_SZ = 12

-- Helper: create a small icon button with highlight
local function IconBtn(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_SZ, NAV_SZ)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:GetHighlightTexture():SetAlpha(0.3)
    return b
end

-- Helper: add a centered atlas icon to a button
local function SetBtnAtlas(btn, atlas, sz)
    local t = btn:CreateTexture(nil, "ARTWORK")
    t:SetSize(sz or ICON_SZ, sz or ICON_SZ)
    t:SetPoint("CENTER")
    t:SetAtlas(atlas, false)
    btn._icon = t
    return t
end

-- Helper: add a centered texture icon to a button
local function SetBtnTexture(btn, path, sz)
    local t = btn:CreateTexture(nil, "ARTWORK")
    t:SetSize(sz or ICON_SZ, sz or ICON_SZ)
    t:SetPoint("CENTER")
    t:SetTexture(path)
    btn._icon = t
    return t
end

-- Share button (chat bubble icon)
local shareBtn = IconBtn(headerBg)
shareBtn:SetPoint("TOPLEFT", headerBg, "TOPLEFT", 4, -3)
SetBtnTexture(shareBtn, "Interface\\GossipFrame\\ChatBubbleGossipIcon", 14)
shareBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
shareBtn:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Share Route", 0, 0.8, 1)
    GameTooltip:AddLine("Left-click: Send to group", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Copy export string", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
shareBtn:SetScript("OnLeave", GameTooltip_Hide)
shareBtn:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then
        H:ShareRoute()
    elseif btn == "RightButton" then
        H:CopyRouteString()
    end
end)

-- Map popout button (minimap tracking icon)
local mapBtn = IconBtn(headerBg)
mapBtn:SetPoint("LEFT", shareBtn, "RIGHT", 2, 0)
SetBtnAtlas(mapBtn, "poi-islands-table", 14)
mapBtn:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Map Popout", 0, 0.8, 1)
    GameTooltip:AddLine("Toggle dungeon map overlay", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
mapBtn:SetScript("OnLeave", GameTooltip_Hide)
mapBtn:SetScript("OnClick", function()
    if H.ToggleMapPopout then H:ToggleMapPopout() end
end)

-- Auto-advance toggle (green arrow = on, rotated to play-style right arrow)
local autoBtn = IconBtn(headerBg)
autoBtn:SetPoint("LEFT", mapBtn, "RIGHT", 2, 0)
local autoIcon = SetBtnAtlas(autoBtn, "Warfronts-BaseMapIcons-Empty-Heroes-Minimap", 12)
local function UpdateAutoBtnColor()
    autoIcon:SetAtlas(H.db.autoAdvance and "Warfronts-BaseMapIcons-Alliance-ConstructionHeroes-Minimap" or "Warfronts-BaseMapIcons-Empty-Heroes-Minimap", false)
end
UpdateAutoBtnColor()
autoBtn:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    local state = H.db.autoAdvance and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    GameTooltip:SetText("Auto-Advance: " .. state, 0, 0.8, 1)
    GameTooltip:AddLine("Toggle automatic pull tracking", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
autoBtn:SetScript("OnLeave", GameTooltip_Hide)
autoBtn:SetScript("OnClick", function()
    H.db.autoAdvance = not H.db.autoAdvance
    UpdateAutoBtnColor()
    local state = H.db.autoAdvance and "enabled" or "disabled"
    print("|cff00ccffMDTHelper|r: Auto-advance " .. state)
end)

-- Dungeon selector button (dropdown to manually pick dungeon)
local dungeonSelBtn = IconBtn(headerBg)
dungeonSelBtn:SetPoint("LEFT", autoBtn, "RIGHT", 2, 0)
SetBtnTexture(dungeonSelBtn, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", 12)

------------------------------------------------------------------------
-- Dungeon dropdown
------------------------------------------------------------------------
local DD_W = 200
local DD_BTN_H = 20
local DD_MAX_VISIBLE = 15

-- Full-screen overlay to close dropdown when clicking outside
local ddOverlay = CreateFrame("Button", nil, UIParent)
ddOverlay:SetFrameStrata("DIALOG")
ddOverlay:SetAllPoints()
ddOverlay:RegisterForClicks("LeftButtonUp")
ddOverlay:SetFrameLevel(1)
ddOverlay:Hide()

local dungeonDD = CreateFrame("Frame", "MDTHelperDungeonDD", UIParent, "BackdropTemplate")
dungeonDD:SetFrameStrata("DIALOG")
dungeonDD:SetFrameLevel(10)
dungeonDD:SetClampedToScreen(true)
dungeonDD:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
dungeonDD:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
dungeonDD:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
dungeonDD:Hide()
tinsert(UISpecialFrames, "MDTHelperDungeonDD")

ddOverlay:SetScript("OnClick", function() dungeonDD:Hide() end)
dungeonDD:SetScript("OnShow", function() ddOverlay:Show() end)
dungeonDD:SetScript("OnHide", function() ddOverlay:Hide() end)

-- Scrollable content area
local ddClip = CreateFrame("Frame", nil, dungeonDD)
ddClip:SetPoint("TOPLEFT", 2, -2)
ddClip:SetPoint("BOTTOMRIGHT", -2, 2)
ddClip:SetClipsChildren(true)

local ddContent = CreateFrame("Frame", nil, ddClip)
ddContent:SetPoint("TOPLEFT")
ddContent:SetSize(DD_W - 4, 1)

local ddScrollOff = 0
dungeonDD:EnableMouseWheel(true)
dungeonDD:SetScript("OnMouseWheel", function(_, delta)
    local contentH = ddContent:GetHeight()
    local viewH = ddClip:GetHeight()
    local maxOff = math.max(0, contentH - viewH)
    ddScrollOff = math.max(0, math.min(ddScrollOff - delta * DD_BTN_H * 3, maxOff))
    ddContent:SetPoint("TOPLEFT", 0, ddScrollOff)
end)

local ddButtons = {}

local function MakeDDButton()
    local btn = CreateFrame("Button", nil, ddContent)
    btn:SetSize(DD_W - 4, DD_BTN_H)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    btn:GetHighlightTexture():SetAlpha(0.2)

    btn.check = btn:CreateFontString(nil, "OVERLAY")
    btn.check:SetFont(FONT, 8, "OUTLINE")
    btn.check:SetPoint("LEFT", 4, 0)
    btn.check:SetWidth(10)
    btn.check:SetTextColor(0, 0.8, 1)

    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetFont(FONT, 9, "OUTLINE")
    btn.label:SetPoint("LEFT", 14, 0)
    btn.label:SetPoint("RIGHT", -4, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)

    return btn
end

local function ShowDungeonDropdown()
    local list = H:GetDungeonList()
    if #list == 0 then
        print("|cff00ccffMDTHelper|r: No dungeon data from MDT")
        return
    end

    local currentIdx
    if MDT and MDT.GetDB then
        local db = MDT:GetDB()
        if db then currentIdx = db.currentDungeonIdx end
    end
    local isOverride = H.db.dungeonOverride ~= nil
    local totalEntries = #list + 1 -- +1 for "Auto"

    -- Ensure enough buttons exist
    for i = #ddButtons + 1, totalEntries do
        ddButtons[i] = MakeDDButton()
    end

    -- "Auto" option at the top
    local ab = ddButtons[1]
    ab:SetPoint("TOPLEFT", 0, 0)
    ab.label:SetText("Auto (detect from zone)")
    ab.label:SetTextColor(0.5, 0.8, 1)
    ab.check:SetText(not isOverride and ">" or "")
    ab:SetScript("OnClick", function()
        H:SetDungeonOverride(nil)
        dungeonDD:Hide()
    end)
    ab:Show()

    -- Dungeon entries
    for i, info in ipairs(list) do
        local btn = ddButtons[i + 1]
        btn:SetPoint("TOPLEFT", 0, -(i * DD_BTN_H))
        btn.label:SetText(info.name)
        btn.label:SetTextColor(1, 1, 1)

        local sel = (isOverride and info.idx == H.db.dungeonOverride)
            or (not isOverride and info.idx == currentIdx)
        btn.check:SetText(sel and ">" or "")

        local idx = info.idx
        btn:SetScript("OnClick", function()
            H:SetDungeonOverride(idx)
            dungeonDD:Hide()
        end)
        btn:Show()
    end

    -- Hide extra buttons from previous showing
    for i = totalEntries + 1, #ddButtons do
        ddButtons[i]:Hide()
    end

    -- Size and position
    local contentH = totalEntries * DD_BTN_H
    ddContent:SetHeight(contentH)
    local visH = math.min(contentH + 4, DD_MAX_VISIBLE * DD_BTN_H + 4)
    dungeonDD:SetSize(DD_W, visH)
    dungeonDD:SetScale(f:GetScale())
    dungeonDD:ClearAllPoints()
    dungeonDD:SetPoint("TOPLEFT", dungeonSelBtn, "BOTTOMLEFT", 0, -2)

    ddScrollOff = 0
    ddContent:SetPoint("TOPLEFT", 0, 0)

    dungeonDD:Show()
end

-- Button tooltip and click
dungeonSelBtn:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    local name = H:GetCurrentDungeonName() or "Unknown"
    local mode = H.db.dungeonOverride and "|cffff8800Manual|r" or "|cff00ff00Auto|r"
    GameTooltip:SetText("Dungeon: " .. name, 0, 0.8, 1)
    GameTooltip:AddLine("Mode: " .. mode, 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Click to select dungeon", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
dungeonSelBtn:SetScript("OnLeave", GameTooltip_Hide)
dungeonSelBtn:SetScript("OnClick", function()
    if dungeonDD:IsShown() then
        dungeonDD:Hide()
    else
        ShowDungeonDropdown()
    end
end)

-- Minimize/expand button (arrow pointing down/up)
local minBtn = IconBtn(headerBg)
minBtn:SetPoint("TOPRIGHT", headerBg, "TOPRIGHT", -52, -3)
local minIcon = SetBtnAtlas(minBtn, "UI-HUD-Minimap-Zoom-Out", 12)
minBtn:SetScript("OnClick", function()
    H.db.minimized = not H.db.minimized
    H:UpdateUI()
end)

-- Previous pull (arrow pointing left)
local prevBtn = IconBtn(headerBg)
prevBtn:SetPoint("TOPRIGHT", headerBg, "TOPRIGHT", -28, -3)
local prevIcon = SetBtnAtlas(prevBtn, "shop-icon-carousel-next-hover", 12)
prevIcon:SetTexCoord(1, 0, 0, 1) -- mirror horizontally to point left
prevBtn:SetScript("OnClick", function() H:RetreatPull() end)

-- Next pull (arrow pointing right)
local nextBtn = IconBtn(headerBg)
nextBtn:SetPoint("TOPRIGHT", headerBg, "TOPRIGHT", -4, -3)
local nextIcon = SetBtnAtlas(nextBtn, "shop-icon-carousel-next-hover", 12)
nextBtn:SetScript("OnClick", function() H:AdvancePull() end)

------------------------------------------------------------------------
-- Forces bar
------------------------------------------------------------------------
local barFrame = CreateFrame("Frame", nil, f)
barFrame:SetSize(WIDTH - 8, 10)
barFrame:SetPoint("TOPLEFT", 4, -26)
Bg(barFrame, 0.1, 0.1, 0.1, 1)
RegisterBg(barFrame, 0.1, 0.1, 0.1, 1)

local barFill = barFrame:CreateTexture(nil, "ARTWORK", nil, 1)
barFill:SetPoint("TOPLEFT")
barFill:SetSize(1, 10)
barFill:SetColorTexture(0.2, 0.55, 1, 1)
RegisterTex(barFill, 0.2, 0.55, 1, 1)

local barText = Text(barFrame, 8, "CENTER")
barText:SetPoint("CENTER")

------------------------------------------------------------------------
-- Pull list content area
------------------------------------------------------------------------
local listSection = CreateFrame("Frame", nil, f)
listSection:SetPoint("TOPLEFT", 0, -40)
listSection:SetSize(WIDTH, 100)
listSection:SetClipsChildren(true)

local listContent = CreateFrame("Frame", nil, listSection)
listContent:SetPoint("TOPLEFT", 4, 0)
listContent:SetSize(WIDTH - 8, 1)

------------------------------------------------------------------------
-- Compact pull rows (reused for non-current pulls)
------------------------------------------------------------------------
local pullRows = {}

local LIST_PORTRAIT_SIZE = 20
local LIST_PORTRAIT_OVERLAP = 24
local MAX_PORTRAITS = 7

local function GetPullRow(i)
    if pullRows[i] then return pullRows[i] end

    local row = CreateFrame("Frame", nil, listContent)
    row:SetSize(WIDTH - 8, ROW_H)
    Bg(row, 0.08, 0.08, 0.08, 0.7)
    RegisterBg(row, 0.08, 0.08, 0.08, 0.7)

    row.num = Text(row, 9, "CENTER")
    row.num:SetPoint("LEFT", 2, 0)
    row.num:SetWidth(18)

    row.bossIcon = row:CreateTexture(nil, "ARTWORK")
    row.bossIcon:SetSize(14, 14)
    row.bossIcon:SetPoint("CENTER", row.num, "CENTER")
    row.bossIcon:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    row.bossIcon:Hide()

    -- Stacked portraits with circle border + count badge
    row.portraits = {}
    for j = 1, MAX_PORTRAITS do
        local pf = CreateFrame("Frame", nil, row)
        pf:SetSize(LIST_PORTRAIT_SIZE + 2, LIST_PORTRAIT_SIZE + 2)
        pf:SetPoint("LEFT", 20 + (j - 1) * LIST_PORTRAIT_OVERLAP, 0)
        pf:SetFrameLevel(row:GetFrameLevel() + j)

        -- Circle border
        pf.border = pf:CreateTexture(nil, "BACKGROUND")
        pf.border:SetAllPoints()
        pf.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
        pf.border:SetVertexColor(0.4, 0.4, 0.4, 1)

        -- Portrait
        pf.tex = pf:CreateTexture(nil, "ARTWORK")
        pf.tex:SetSize(LIST_PORTRAIT_SIZE, LIST_PORTRAIT_SIZE)
        pf.tex:SetPoint("CENTER")

        -- Circular mask
        local mask = pf:CreateMaskTexture()
        mask:SetAllPoints(pf.tex)
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall", "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE")
        pf.tex:AddMaskTexture(mask)

        -- Count badge on a high-level sub-frame so it's never covered
        pf.countFrame = CreateFrame("Frame", nil, pf)
        pf.countFrame:SetAllPoints()
        pf.countFrame:SetFrameLevel(row:GetFrameLevel() + MAX_PORTRAITS + 1)
        pf.count = pf.countFrame:CreateFontString(nil, "OVERLAY")
        pf.count:SetFont(FONT, 10, "OUTLINE")
        pf.count:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 2, -2)
        pf.count:SetTextColor(1, 1, 1)
        pf.count:Hide()

        -- Tooltip
        pf:EnableMouse(true)
        pf.mobName = ""
        pf.mobForces = ""
        pf:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.mobName, 1, 1, 1)
            if self.mobForces ~= "" then
                GameTooltip:AddLine(self.mobForces, 0.5, 0.7, 1)
            end
            GameTooltip:Show()
        end)
        pf:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pf:Hide()
        row.portraits[j] = pf
    end

    row.cumPct = Text(row, 8, "RIGHT")
    row.cumPct:SetPoint("RIGHT", -2, 0)
    row.cumPct:SetWidth(42)
    row.cumPct:SetTextColor(0.55, 0.55, 0.55)

    row.check = Text(row, 9, "CENTER")
    row.check:SetPoint("CENTER", row.num, "CENTER")
    row.check:SetTextColor(0.2, 1, 0.2)
    row.check:SetText("v")
    row.check:Hide()

    row:Hide()
    pullRows[i] = row
    return row
end

------------------------------------------------------------------------
-- Expanded pull block (for current pull, rendered inline)
------------------------------------------------------------------------
local expandedBlock = CreateFrame("Frame", nil, listContent)
expandedBlock:SetSize(WIDTH - 8, EXPANDED_TITLE_H)
Bg(expandedBlock, 0.12, 0.1, 0.02, 0.9)
RegisterBg(expandedBlock, 0.12, 0.1, 0.02, 0.9)
expandedBlock:Hide()

local expandedCumPct = Text(expandedBlock, 8, "RIGHT")
expandedCumPct:SetPoint("TOPRIGHT", -2, -(EXPANDED_TITLE_H + (MOB_ROW_H - 8) / 2))
expandedCumPct:SetWidth(42)
expandedCumPct:SetTextColor(0.55, 0.55, 0.55)

-- Orange border for incomplete pulls
local incompleteBorder = CreateFrame("Frame", nil, expandedBlock, "BackdropTemplate")
incompleteBorder:SetPoint("TOPLEFT", -1, 1)
incompleteBorder:SetPoint("BOTTOMRIGHT", 1, -1)
incompleteBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
incompleteBorder:SetBackdropBorderColor(1, 0.5, 0.1, 1)
incompleteBorder:SetFrameLevel(expandedBlock:GetFrameLevel() + 10)
incompleteBorder:Hide()

local expandedMobRows = {}

local PORTRAIT_SIZE = 24
local COL_COUNT_W = 20

local function GetExpandedMobRow(i)
    if expandedMobRows[i] then return expandedMobRows[i] end

    local row = CreateFrame("Frame", nil, expandedBlock)
    row:SetSize(WIDTH - 16, MOB_ROW_H)
    row:SetPoint("TOPLEFT", 6, -(EXPANDED_TITLE_H + (i - 1) * (MOB_ROW_H + 1)))
    row:EnableMouse(true)

    -- Column 1: count or boss icon
    row.count = Text(row, 10, "CENTER")
    row.count:SetPoint("LEFT", 0, 0)
    row.count:SetWidth(COL_COUNT_W)
    row.count:SetTextColor(0.7, 0.7, 0.7)

    row.skull = row:CreateTexture(nil, "ARTWORK")
    row.skull:SetSize(14, 14)
    row.skull:SetPoint("CENTER", row.count, "CENTER")
    row.skull:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    row.skull:Hide()

    -- Column 2: portrait with circle border
    row.portraitBorder = row:CreateTexture(nil, "BACKGROUND")
    row.portraitBorder:SetSize(PORTRAIT_SIZE + 2, PORTRAIT_SIZE + 2)
    row.portraitBorder:SetPoint("LEFT", COL_COUNT_W + 2, 0)
    row.portraitBorder:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    row.portraitBorder:SetVertexColor(0.4, 0.4, 0.4, 1)

    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    row.portrait:SetPoint("CENTER", row.portraitBorder, "CENTER")

    local mask = row:CreateMaskTexture()
    mask:SetAllPoints(row.portrait)
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall", "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE")
    row.portrait:AddMaskTexture(mask)

    -- Name text (shown next to portrait, smaller)
    row.name = Text(row, 9)
    row.name:SetPoint("LEFT", row.portrait, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.name:SetWordWrap(false)

    -- Tooltip on hover (includes forces)
    row.mobName = ""
    row.mobForces = ""
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.mobName, 1, 1, 1)
        if self.mobForces ~= "" then
            GameTooltip:AddLine(self.mobForces, 0.5, 0.7, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:Hide()
    expandedMobRows[i] = row
    return row
end

------------------------------------------------------------------------
-- Scroll
------------------------------------------------------------------------
local scrollOffset = 0
f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta)
    local contentH = listContent:GetHeight()
    local viewH = listSection:GetHeight()
    local maxOff = math.max(0, contentH - viewH)
    scrollOffset = math.max(0, math.min(scrollOffset - delta * 38, maxOff))
    listContent:SetPoint("TOPLEFT", 4, scrollOffset)
end)

------------------------------------------------------------------------
-- Resize handle (bottom edge)
------------------------------------------------------------------------
local MIN_FRAME_HEIGHT = 80
local MAX_FRAME_HEIGHT = 800

local resizeHandle = CreateFrame("Frame", nil, f)
resizeHandle:SetSize(WIDTH, 6)
resizeHandle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
resizeHandle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
resizeHandle:EnableMouse(true)
resizeHandle:SetFrameLevel(f:GetFrameLevel() + 10)

local resizeIndicator = resizeHandle:CreateTexture(nil, "OVERLAY")
resizeIndicator:SetSize(30, 2)
resizeIndicator:SetPoint("CENTER", resizeHandle, "CENTER", 0, 0)
resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0)

local function UpdateResizeHandleVisibility()
    if H.db.locked then
        resizeHandle:EnableMouse(false)
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0)
    else
        resizeHandle:EnableMouse(true)
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    end
end

resizeHandle:SetScript("OnEnter", function()
    if not H.db.locked then
        resizeIndicator:SetColorTexture(0, 0.8, 1, 0.7)
    end
end)
resizeHandle:SetScript("OnLeave", function()
    if not H.db.locked then
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    end
end)

local isResizing = false
resizeHandle:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" and not H.db.locked then
        isResizing = true
        f.resizeStartY = select(2, GetCursorPosition()) / f:GetEffectiveScale()
        f.resizeStartH = f:GetHeight()
    end
end)

resizeHandle:SetScript("OnMouseUp", function()
    if isResizing then
        isResizing = false
        -- Save the list section height as the user's custom height
        local listTop = H.db.minimized and 26 or 40
        local customH = f:GetHeight() - listTop - 6
        if customH >= 40 then
            H.db.frameHeight = customH
        end
    end
end)

resizeHandle:SetScript("OnUpdate", function()
    if not isResizing then return end
    local curY = select(2, GetCursorPosition()) / f:GetEffectiveScale()
    local delta = f.resizeStartY - curY
    local newH = math.max(MIN_FRAME_HEIGHT, math.min(f.resizeStartH + delta, MAX_FRAME_HEIGHT))
    f:SetHeight(newH)
    local listTop = H.db.minimized and 26 or 40
    local listH = newH - listTop - 6
    listSection:SetHeight(math.max(listH, 20))
end)

------------------------------------------------------------------------
-- Hover: boost opacity when frame is transparent
------------------------------------------------------------------------
local HOVER_ALPHA = 0.85

f:SetScript("OnEnter", function()
    local alpha = H.db.bgAlpha or 1
    if alpha < HOVER_ALPHA then
        ApplyOpacity(HOVER_ALPHA)
    end
end)
f:SetScript("OnLeave", function()
    ApplyOpacity(H.db.bgAlpha or 1)
end)

------------------------------------------------------------------------
-- Open WoW Settings panel to MDTHelper
------------------------------------------------------------------------
function H:ToggleSettings()
    if H.settingsCategory then
        Settings.OpenToCategory(H.settingsCategory:GetID())
    end
end

------------------------------------------------------------------------
-- Update UI
------------------------------------------------------------------------
function H:UpdateUI()
    if self._updatePending then return end
    self._updatePending = true
    C_Timer.After(0, function()
        self._updatePending = false
        local uiOk, uiErr = pcall(function() H:_DoUpdateUI() end)
        if not uiOk then
            print("|cffff0000MDTHelper UI error:|r " .. tostring(uiErr))
        end
    end)
end

function H:_DoUpdateUI()
    -- Restore position & scale only once on load
    if not self._positionRestored then
        f:SetScale(self.db and self.db.uiScale or 1)
        if self.db and self.db.framePoint then
            local p = self.db.framePoint
            f:ClearAllPoints()
            f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        self._positionRestored = true
    end

    if not self.db or not self.db.enabled or not self.activeDungeon or #self.pulls == 0 then
        f:Hide()
        return
    end
    f:Show()
    f:SetScale(self.db.uiScale or 1)
    ApplyOpacity(self.db.bgAlpha or 1)
    UpdateAutoBtnColor()

    -- Highlight dungeon button orange when manually overridden
    if dungeonSelBtn._icon then
        if self.db.dungeonOverride then
            dungeonSelBtn._icon:SetVertexColor(1, 0.5, 0)
        else
            dungeonSelBtn._icon:SetVertexColor(0.7, 0.7, 0.7)
        end
    end

    local total = self:GetPullCount()
    local cur = self.currentPullIdx
    local n = #self.pulls
    local minimized = self.db.minimized

    -- Update minimize button icon direction
    minIcon:SetAtlas(minimized and "UI-HUD-Minimap-Zoom-In" or "UI-HUD-Minimap-Zoom-Out", false)

    -- Header
    headerText:SetText("Pull " .. cur .. " / " .. total .. " |r")

    -- Forces bar — hide when minimized
    if minimized then
        barFrame:Hide()
        listSection:SetPoint("TOPLEFT", 0, -26)
    else
        barFrame:Show()
        listSection:SetPoint("TOPLEFT", 0, -40)
    end

    -- Forces bar values (update even if hidden, so it's ready when expanded)
    local gained = self.totalForcesGained
    local needed = self.totalForcesRequired
    if needed <= 0 then
        needed = 0
        for _, pull in ipairs(self.pulls) do needed = needed + pull.totalForces end
    end
    local bw = WIDTH - 8
    if needed > 0 then
        local pct = math.min(gained / needed, 1)
        barFill:SetWidth(math.max(pct * bw, 1))
        local baseText = gained .. "/" .. needed .. "  " .. math.floor(pct * 100) .. "%"

        -- Efficiency tracking: actual vs planned forces through completed pulls
        if self.db.efficiencyTracker and cur > 1 then
            local plannedThrough = 0
            for i = 1, cur - 1 do
                if self.pulls[i] and self.pulls[i].completed then
                    plannedThrough = plannedThrough + self.pulls[i].totalForces
                end
            end
            local plannedPct = (plannedThrough / needed) * 100
            local actualPct = (gained / needed) * 100
            local diff = actualPct - plannedPct
            if diff >= 0.1 then
                baseText = baseText .. string.format("  |cFF00FF00+%.1f%%|r", diff)
            elseif diff <= -0.1 then
                baseText = baseText .. string.format("  |cFFFF4444%.1f%%|r", diff)
            end
        end

        barText:SetText(baseText)
    else
        barFill:SetWidth(1)
        barText:SetText("")
    end

    -- Pre-compute cumulative forces for each pull
    local cumForces = {}
    local runningForces = 0
    for i = 1, n do
        runningForces = runningForces + self.pulls[i].totalForces
        cumForces[i] = runningForces
    end

    -- Build the expanded block for the current pull
    local pull = self.pulls[cur]
    local expandedHeight = EXPANDED_TITLE_H
    if pull then
        local numEnemies = #pull.enemies
        for i = 1, math.max(numEnemies, #expandedMobRows) do
            local row = GetExpandedMobRow(i)
            if i <= numEnemies then
                local e = pull.enemies[i]
                if e.isBoss then
                    row.count:Hide()
                    row.skull:Show()
                    row.name:SetTextColor(1, 0.82, 0)
                    row.portraitBorder:SetVertexColor(0.9, 0.75, 0.1, 1)
                else
                    row.skull:Hide()
                    row.count:SetText(tostring(e.numClones))
                    row.count:Show()
                    row.name:SetTextColor(0.95, 0.95, 0.95)
                    row.portraitBorder:SetVertexColor(0.4, 0.4, 0.4, 1)
                end
                -- Portrait
                SetPortrait(row.portrait, e.displayId)
                row.mobName = e.name
                row.name:SetText(e.name)
                if e.forces > 0 then
                    row.mobForces = e.numClones ..
                    "x " .. ForcePct(e.forces) .. " = " .. ForcePct(e.forces * e.numClones)
                else
                    row.mobForces = ""
                end
                row:SetPoint("TOPLEFT", 6, -(EXPANDED_TITLE_H + (i - 1) * (MOB_ROW_H + 1)))
                row:Show()
            else
                row:Hide()
                row.skull:Hide()
                row.count:Hide()
            end
        end

        expandedHeight = EXPANDED_TITLE_H + numEnemies * (MOB_ROW_H + 1) + 4
        expandedBlock:SetHeight(expandedHeight)
        expandedBlock:Show()

        -- Cumulative % on expanded block
        if needed > 0 and cumForces[cur] then
            expandedCumPct:SetText(string.format("%.1f%%", (cumForces[cur] / needed) * 100))
            expandedCumPct:Show()
        else
            expandedCumPct:Hide()
        end

        -- Incomplete pull — orange outline
        if pull.incomplete then
            incompleteBorder:Show()
        else
            incompleteBorder:Hide()
        end

    else
        expandedBlock:Hide()
    end

    -- Determine which pulls to show
    -- In minimized mode: only current pull (expanded) + next pull (compact)
    -- In full mode: all pulls
    local showPull = {}
    if minimized then
        showPull[cur] = true
        if cur + 1 <= n then showPull[cur + 1] = true end
    else
        for i = 1, n do showPull[i] = true end
    end

    -- Layout pulls in the list
    local yOff = 0

    for i = 1, math.max(n, #pullRows) do
        local row = GetPullRow(i)
        if i <= n and showPull[i] then
            local p = self.pulls[i]

            if i == cur then
                -- Place the expanded block here instead of a compact row
                expandedBlock:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -yOff)
                yOff = yOff + expandedHeight + 2
                row:Hide()
            else
                row:Show()
                row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -yOff)
                yOff = yOff + ROW_H + 1

                row.num:SetText(tostring(i))
                local pr, pg, pb = 0.7, 0.7, 0.7
                if p.color then
                    pr = tonumber(p.color[1]) or 0.7
                    pg = tonumber(p.color[2]) or 0.7
                    pb = tonumber(p.color[3]) or 0.7
                    if pr > 1 or pg > 1 or pb > 1 then pr, pg, pb = pr / 255, pg / 255, pb / 255 end
                end

                -- Populate stacked portraits (one per enemy type)
                local ptIdx = 0
                for _, e in ipairs(p.enemies) do
                    ptIdx = ptIdx + 1
                    if ptIdx > MAX_PORTRAITS then break end
                    local pf = row.portraits[ptIdx]
                    SetPortrait(pf.tex, e.displayId)
                    pf.mobName = e.name
                    if e.forces > 0 then
                        pf.mobForces = e.numClones ..
                        "x " .. ForcePct(e.forces) .. " = " .. ForcePct(e.forces * e.numClones)
                    else
                        pf.mobForces = ""
                    end
                    if e.isBoss then
                        pf.border:SetVertexColor(0.9, 0.75, 0.1, 1)
                        pf.count:Hide()
                    elseif e.numClones > 1 then
                        pf.border:SetVertexColor(0.4, 0.4, 0.4, 1)
                        pf.count:SetText(tostring(e.numClones))
                        pf.count:Show()
                    else
                        pf.border:SetVertexColor(0.4, 0.4, 0.4, 1)
                        pf.count:Hide()
                    end
                    pf:Show()
                end
                -- Hide unused portraits
                for j = ptIdx + 1, MAX_PORTRAITS do
                    row.portraits[j]:Hide()
                end

                -- Cumulative % up to this pull
                if needed > 0 and cumForces[i] then
                    row.cumPct:SetText(string.format("%.1f%%", (cumForces[i] / needed) * 100))
                    row.cumPct:Show()
                else
                    row.cumPct:Hide()
                end

                local dimPortraits = false
                if p.completed then
                    SetBg(row, 0.06, 0.06, 0.06, 0.7)
                    row.num:Hide()
                    row.bossIcon:Hide()
                    row.check:Show()
                    row.cumPct:SetTextColor(0.25, 0.25, 0.25)
                    dimPortraits = true
                else
                    SetBg(row, 0.08, 0.08, 0.08, 0.7)
                    row.check:Hide()
                    if p.hasBoss then
                        row.num:Hide()
                        row.bossIcon:Show()
                    else
                        row.num:Show()
                        row.bossIcon:Hide()
                    end
                    row.num:SetTextColor(pr, pg, pb)
                    row.cumPct:SetTextColor(0.55, 0.55, 0.55)
                end
                -- Dim portraits for completed pulls
                for j = 1, math.min(ptIdx, MAX_PORTRAITS) do
                    row.portraits[j]:SetAlpha(dimPortraits and 0.3 or 1)
                end
            end
        else
            row:Hide()
            for j = 1, MAX_PORTRAITS do
                row.portraits[j]:Hide()
            end
        end
    end

    listContent:SetHeight(math.max(yOff, 1))

    -- Size the frame to fit
    local listTop = minimized and 26 or 40
    local customH = self.db.frameHeight
    local maxListH
    if customH and not minimized then
        maxListH = customH
    else
        maxListH = math.min(yOff, 500)
    end
    local totalHeight = listTop + maxListH + 6
    f:SetHeight(totalHeight)
    listSection:SetHeight(maxListH)
    UpdateResizeHandleVisibility()

    -- Auto scroll / reset scroll
    if minimized then
        scrollOffset = 0
        listContent:SetPoint("TOPLEFT", 4, 0)
    else
        local contentH = yOff
        local viewH = listSection:GetHeight()
        if contentH > viewH then
            -- Find the Y offset of the expanded block
            local curY = 0
            for i = 1, cur - 1 do
                if self.pulls[i] then
                    curY = curY + ROW_H + 1
                end
            end
            -- Center the expanded block in view if possible
            local tgt = math.max(0, curY - 40)
            local mx = math.max(0, contentH - viewH)
            scrollOffset = math.min(tgt, mx)
            listContent:SetPoint("TOPLEFT", 4, scrollOffset)
        else
            scrollOffset = 0
            listContent:SetPoint("TOPLEFT", 4, 0)
        end
    end

    -- Overlay live pull forces during combat
    if self.UpdatePullForcesDisplay then self:UpdatePullForcesDisplay() end
end

------------------------------------------------------------------------
-- Live pull forces display (updated by ForcesOverlay.lua during combat)
------------------------------------------------------------------------
function H:UpdatePullForcesDisplay()
    if not f:IsShown() then return end
    if not self.livePullPercent or self.livePullPercent <= 0 then return end

    local gained = self.totalForcesGained
    local needed = self.totalForcesRequired
    if needed <= 0 then
        needed = 0
        for _, pull in ipairs(self.pulls) do needed = needed + pull.totalForces end
    end

    -- Append live pull % to the forces bar text
    if needed > 0 then
        local pct = math.min(gained / needed, 1)
        local base = gained .. "/" .. needed .. "  " .. math.floor(pct * 100) .. "%"
        barText:SetText(base .. "  |cFFFFCC00+" .. string.format("%.1f%%", self.livePullPercent) .. "|r")
    end

    -- Show predicted total on the expanded block
    if expandedCumPct:IsShown() then
        local currentPct = needed > 0 and (gained / needed * 100) or 0
        local predicted = currentPct + self.livePullPercent
        expandedCumPct:SetText(string.format("|cFFFFCC00\xe2\x86\x92%.1f%%|r", predicted))
    end
end
