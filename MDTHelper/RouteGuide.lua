local H = MDTHelper

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local WIDTH = 240
local FONT = "Fonts\\FRIZQT__.TTF"
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
f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetUserPlaced(false)
f:Hide()
Bg(f, 0.04, 0.04, 0.04, 0.92)
RegisterBg(f, 0.04, 0.04, 0.04, 0.92)

f:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" and not H.db.locked then self:StartMoving() end
end)
f:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    -- Always normalize to TOPLEFT so height changes grow downward
    local scale = self:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local left, top = self:GetLeft(), self:GetTop()
    local x = (left * scale) / uiScale
    local y = (top * scale) / uiScale - UIParent:GetHeight()
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    H.db.framePoint = { "TOPLEFT", "TOPLEFT", x, y }
end)

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

local function NavBtn(parent, label, ox)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(22, 18)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ox, -3)
    b:EnableMouse(true)
    Bg(b, 0.18, 0.18, 0.18, 1)
    RegisterBg(b, 0.18, 0.18, 0.18, 1)
    local t = Text(b, 10, "CENTER")
    t:SetPoint("CENTER")
    t:SetText(label)
    b.label = t
    b:SetScript("OnEnter", function(s) SetBg(s, 0.35, 0.35, 0.35, 1) end)
    b:SetScript("OnLeave", function(s) SetBg(s, 0.18, 0.18, 0.18, 1) end)
    return b
end

local shareBtn = NavBtn(headerBg, "S", -76)
shareBtn:ClearAllPoints()
shareBtn:SetPoint("TOPLEFT", headerBg, "TOPLEFT", 4, -3)
shareBtn:SetScript("OnEnter", function(s)
    SetBg(s, 0.35, 0.35, 0.35, 1)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Share Route", 0, 0.8, 1)
    GameTooltip:AddLine("Left-click: Send to group", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Copy export string", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
shareBtn:SetScript("OnLeave", function(s)
    SetBg(s, 0.18, 0.18, 0.18, 1)
    GameTooltip:Hide()
end)
shareBtn:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then
        H:ShareRoute()
    elseif btn == "RightButton" then
        H:CopyRouteString()
    end
end)
shareBtn.label:SetTextColor(0.3, 0.8, 0.3)

local refreshBtn = NavBtn(headerBg, "R", -76)
refreshBtn:ClearAllPoints()
refreshBtn:SetPoint("LEFT", shareBtn, "RIGHT", 2, 0)
refreshBtn:SetScript("OnEnter", function(s)
    SetBg(s, 0.35, 0.35, 0.35, 1)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Refresh Route", 0, 0.8, 1)
    GameTooltip:AddLine("Reload route from MDT", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
refreshBtn:SetScript("OnLeave", function(s)
    SetBg(s, 0.18, 0.18, 0.18, 1)
    GameTooltip:Hide()
end)
refreshBtn:SetScript("OnMouseDown", function()
    H:BuildRoute()
end)
refreshBtn.label:SetTextColor(0.8, 0.7, 0.3)

local autoBtn = NavBtn(headerBg, "A", -76)
autoBtn:ClearAllPoints()
autoBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 2, 0)
local function UpdateAutoBtnColor()
    if H.db.autoAdvance then
        autoBtn.label:SetTextColor(0.3, 1, 0.3)
    else
        autoBtn.label:SetTextColor(1, 0.3, 0.3)
    end
end
UpdateAutoBtnColor()
autoBtn:SetScript("OnEnter", function(s)
    SetBg(s, 0.35, 0.35, 0.35, 1)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    local state = H.db.autoAdvance and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    GameTooltip:SetText("Auto-Advance: " .. state, 0, 0.8, 1)
    GameTooltip:AddLine("Toggle automatic pull tracking", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
autoBtn:SetScript("OnLeave", function(s)
    SetBg(s, 0.18, 0.18, 0.18, 1)
    GameTooltip:Hide()
end)
autoBtn:SetScript("OnMouseDown", function()
    H.db.autoAdvance = not H.db.autoAdvance
    UpdateAutoBtnColor()
    local state = H.db.autoAdvance and "enabled" or "disabled"
    print("|cff00ccffMDTHelper|r: Auto-advance " .. state)
end)

local minBtn = NavBtn(headerBg, "-", -52)
minBtn:SetScript("OnMouseDown", function()
    H.db.minimized = not H.db.minimized
    H:UpdateUI()
end)

local prevBtn = NavBtn(headerBg, "<", -28)
prevBtn:SetScript("OnMouseDown", function() H:RetreatPull() end)
local nextBtn = NavBtn(headerBg, ">", -4)
nextBtn:SetScript("OnMouseDown", function() H:AdvancePull() end)

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
-- Settings panel
------------------------------------------------------------------------
local settingsFrame = CreateFrame("Frame", "MDTHelperSettings", UIParent, "BackdropTemplate")
settingsFrame:SetSize(220, 280)
settingsFrame:SetPoint("CENTER")
settingsFrame:SetFrameStrata("DIALOG")
settingsFrame:SetMovable(true)
settingsFrame:EnableMouse(true)
settingsFrame:SetClampedToScreen(true)
settingsFrame:Hide()

settingsFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
settingsFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
settingsFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

settingsFrame:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then self:StartMoving() end
end)
settingsFrame:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
end)

-- Title
local settingsTitle = settingsFrame:CreateFontString(nil, "OVERLAY")
settingsTitle:SetFont(FONT, 11, "OUTLINE")
settingsTitle:SetPoint("TOPLEFT", 10, -10)
settingsTitle:SetTextColor(0, 0.8, 1)
settingsTitle:SetText("MDTHelper Settings")

-- Close button
local closeBtn = CreateFrame("Frame", nil, settingsFrame)
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("TOPRIGHT", -6, -6)
closeBtn:EnableMouse(true)
local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
closeTxt:SetFont(FONT, 12, "OUTLINE")
closeTxt:SetPoint("CENTER")
closeTxt:SetText("x")
closeTxt:SetTextColor(0.6, 0.6, 0.6)
closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 0.3, 0.3) end)
closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(0.6, 0.6, 0.6) end)
closeBtn:SetScript("OnMouseDown", function() settingsFrame:Hide() end)

-- Reset Position button
local resetPosBtn = CreateFrame("Frame", nil, settingsFrame)
resetPosBtn:SetSize(200, 22)
resetPosBtn:SetPoint("TOPLEFT", 10, -32)
resetPosBtn:EnableMouse(true)
Bg(resetPosBtn, 0.18, 0.18, 0.18, 1)

local resetPosTxt = resetPosBtn:CreateFontString(nil, "OVERLAY")
resetPosTxt:SetFont(FONT, 10, "OUTLINE")
resetPosTxt:SetPoint("CENTER")
resetPosTxt:SetText("Reset Position & Size")
resetPosTxt:SetTextColor(0.9, 0.9, 0.9)

resetPosBtn:SetScript("OnEnter", function(self)
    SetBg(self, 0.35, 0.35, 0.35, 1)
end)
resetPosBtn:SetScript("OnLeave", function(self)
    SetBg(self, 0.18, 0.18, 0.18, 1)
end)
resetPosBtn:SetScript("OnMouseDown", function()
    H.db.framePoint = nil
    H.db.frameHeight = nil
    H.db.uiScale = 1
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)
    H:UpdateUI()
    print("|cff00ccffMDTHelper|r: Position and size reset to default")
end)

-- Transparency slider label
local alphaLabel = settingsFrame:CreateFontString(nil, "OVERLAY")
alphaLabel:SetFont(FONT, 9, "OUTLINE")
alphaLabel:SetPoint("TOPLEFT", 10, -62)
alphaLabel:SetTextColor(0.7, 0.7, 0.7)

-- Transparency slider
local alphaSlider = CreateFrame("Slider", "MDTHelperAlphaSlider", settingsFrame, "OptionsSliderTemplate")
alphaSlider:SetSize(200, 16)
alphaSlider:SetPoint("TOPLEFT", 10, -80)
alphaSlider:SetMinMaxValues(0.1, 1.0)
alphaSlider:SetValueStep(0.05)
alphaSlider:SetObeyStepOnDrag(true)

-- Style the slider text
alphaSlider.Low:SetText("10%")
alphaSlider.High:SetText("100%")
alphaSlider.Text:SetText("")

local function UpdateAlphaLabel(val)
    alphaLabel:SetText("Opacity: " .. math.floor(val * 100 + 0.5) .. "%")
end

alphaSlider:SetScript("OnValueChanged", function(self, value)
    H.db.bgAlpha = value
    UpdateAlphaLabel(value)
    ApplyOpacity(value)
end)

-- Pull accuracy slider label
local threshLabel = settingsFrame:CreateFontString(nil, "OVERLAY")
threshLabel:SetFont(FONT, 9, "OUTLINE")
threshLabel:SetPoint("TOPLEFT", 10, -102)
threshLabel:SetTextColor(0.7, 0.7, 0.7)

-- Pull accuracy slider
local threshSlider = CreateFrame("Slider", "MDTHelperThreshSlider", settingsFrame, "OptionsSliderTemplate")
threshSlider:SetSize(200, 16)
threshSlider:SetPoint("TOPLEFT", 10, -120)
threshSlider:SetMinMaxValues(0.5, 1.0)
threshSlider:SetValueStep(0.05)
threshSlider:SetObeyStepOnDrag(true)

threshSlider.Low:SetText("50%")
threshSlider.High:SetText("100%")
threshSlider.Text:SetText("")

local function UpdateThreshLabel(val)
    threshLabel:SetText("Pull Accuracy: " .. math.floor(val * 100 + 0.5) .. "%")
end

threshSlider:SetScript("OnValueChanged", function(self, value)
    H.db.pullThreshold = value
    UpdateThreshLabel(value)
end)

-- UI Scale slider label
local scaleLabel = settingsFrame:CreateFontString(nil, "OVERLAY")
scaleLabel:SetFont(FONT, 9, "OUTLINE")
scaleLabel:SetPoint("TOPLEFT", 10, -142)
scaleLabel:SetTextColor(0.7, 0.7, 0.7)

-- UI Scale slider
local scaleSlider = CreateFrame("Slider", "MDTHelperScaleSlider", settingsFrame, "OptionsSliderTemplate")
scaleSlider:SetSize(200, 16)
scaleSlider:SetPoint("TOPLEFT", 10, -160)
scaleSlider:SetMinMaxValues(0.5, 2.0)
scaleSlider:SetValueStep(0.05)
scaleSlider:SetObeyStepOnDrag(true)

scaleSlider.Low:SetText("50%")
scaleSlider.High:SetText("200%")
scaleSlider.Text:SetText("")

local function UpdateScaleLabel(val)
    scaleLabel:SetText("UI Scale: " .. math.floor(val * 100 + 0.5) .. "%")
end

scaleSlider:SetScript("OnValueChanged", function(self, value)
    H.db.uiScale = value
    UpdateScaleLabel(value)
    f:SetScale(value)
end)

-- Auto-import toggle
local autoImportBtn = CreateFrame("Frame", nil, settingsFrame)
autoImportBtn:SetSize(200, 22)
autoImportBtn:SetPoint("TOPLEFT", 10, -188)
autoImportBtn:EnableMouse(true)
Bg(autoImportBtn, 0.18, 0.18, 0.18, 1)

local autoImportTxt = autoImportBtn:CreateFontString(nil, "OVERLAY")
autoImportTxt:SetFont(FONT, 10, "OUTLINE")
autoImportTxt:SetPoint("CENTER")
autoImportTxt:SetTextColor(0.9, 0.9, 0.9)

local function UpdateAutoImportLabel()
    local state = H.db.autoImport and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    autoImportTxt:SetText("Auto-Import Leader Route: " .. state)
end

autoImportBtn:SetScript("OnEnter", function(self)
    SetBg(self, 0.35, 0.35, 0.35, 1)
end)
autoImportBtn:SetScript("OnLeave", function(self)
    SetBg(self, 0.18, 0.18, 0.18, 1)
end)
autoImportBtn:SetScript("OnMouseDown", function()
    H.db.autoImport = not H.db.autoImport
    UpdateAutoImportLabel()
end)

-- Unlock Frame toggle (allows moving + resizing height)
local unlockBtn = CreateFrame("Frame", nil, settingsFrame)
unlockBtn:SetSize(200, 22)
unlockBtn:SetPoint("TOPLEFT", 10, -218)
unlockBtn:EnableMouse(true)
Bg(unlockBtn, 0.18, 0.18, 0.18, 1)

local unlockTxt = unlockBtn:CreateFontString(nil, "OVERLAY")
unlockTxt:SetFont(FONT, 10, "OUTLINE")
unlockTxt:SetPoint("CENTER")
unlockTxt:SetTextColor(0.9, 0.9, 0.9)

local function UpdateUnlockLabel()
    local state = H.db.locked and "|cff00ff00Locked|r" or "|cffff4444Unlocked|r"
    unlockTxt:SetText("Frame: " .. state)
end

unlockBtn:SetScript("OnEnter", function(self)
    SetBg(self, 0.35, 0.35, 0.35, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Lock / Unlock Frame", 0, 0.8, 1)
    GameTooltip:AddLine("When unlocked, drag to move and", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("drag bottom edge to resize height", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
unlockBtn:SetScript("OnLeave", function(self)
    SetBg(self, 0.18, 0.18, 0.18, 1)
    GameTooltip:Hide()
end)
unlockBtn:SetScript("OnMouseDown", function()
    H.db.locked = not H.db.locked
    UpdateUnlockLabel()
    H:UpdateUI()
end)

function H:ToggleSettings()
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        alphaSlider:SetValue(H.db.bgAlpha or 1)
        UpdateAlphaLabel(H.db.bgAlpha or 1)
        threshSlider:SetValue(H.db.pullThreshold or 0.8)
        UpdateThreshLabel(H.db.pullThreshold or 0.8)
        scaleSlider:SetValue(H.db.uiScale or 1)
        UpdateScaleLabel(H.db.uiScale or 1)
        UpdateAutoImportLabel()
        UpdateUnlockLabel()
        settingsFrame:Show()
    end
end

------------------------------------------------------------------------
-- Update UI
------------------------------------------------------------------------
function H:UpdateUI()
    local uiOk, uiErr = pcall(function() H:_DoUpdateUI() end)
    if not uiOk then
        print("|cffff0000MDTHelper UI error:|r " .. tostring(uiErr))
    end
end

function H:_DoUpdateUI()
    -- Restore position
    if self.db and self.db.framePoint then
        local p = self.db.framePoint
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end

    if not self.db or not self.db.enabled or not self.activeDungeon or #self.pulls == 0 then
        f:Hide()
        return
    end
    f:Show()
    f:SetScale(self.db.uiScale or 1)
    ApplyOpacity(self.db.bgAlpha or 1)
    UpdateAutoBtnColor()

    local total = self:GetPullCount()
    local cur = self.currentPullIdx
    local n = #self.pulls
    local minimized = self.db.minimized

    -- Update minimize button label
    minBtn.label:SetText(minimized and "+" or "-")

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
        barText:SetText(gained .. "/" .. needed .. "  " .. math.floor(pct * 100) .. "%")
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
end
