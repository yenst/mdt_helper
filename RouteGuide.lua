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

local function SetBg(frame, r, g, b, a)
    if frame._bg then frame._bg:SetColorTexture(r, g, b, a) end
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
f:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:SetMovable(true)
f:SetUserPlaced(false)
f:Hide()
Bg(f, 0.04, 0.04, 0.04, 0.92)

f:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" and not H.db.locked then self:StartMoving() end
end)
f:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    H.db.framePoint = { p, rp, x, y }
end)

------------------------------------------------------------------------
-- Header: "Pull 3/12" with nav buttons
------------------------------------------------------------------------
local headerBg = CreateFrame("Frame", nil, f)
headerBg:SetSize(WIDTH, 24)
headerBg:SetPoint("TOPLEFT", 0, 0)
Bg(headerBg, 0.08, 0.08, 0.08, 1)

local headerText = Text(headerBg, 11, "CENTER")
headerText:SetPoint("CENTER")
headerText:SetTextColor(0, 0.8, 1)

local function NavBtn(parent, label, ox)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(22, 18)
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ox, -3)
    b:EnableMouse(true)
    Bg(b, 0.18, 0.18, 0.18, 1)
    local t = Text(b, 10, "CENTER")
    t:SetPoint("CENTER")
    t:SetText(label)
    b:SetScript("OnEnter", function(s) SetBg(s, 0.35, 0.35, 0.35, 1) end)
    b:SetScript("OnLeave", function(s) SetBg(s, 0.18, 0.18, 0.18, 1) end)
    return b
end

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

local barFill = barFrame:CreateTexture(nil, "ARTWORK", nil, 1)
barFill:SetPoint("TOPLEFT")
barFill:SetSize(1, 10)
barFill:SetColorTexture(0.2, 0.55, 1, 1)

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
        pf:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.mobName, 1, 1, 1)
            GameTooltip:Show()
        end)
        pf:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pf:Hide()
        row.portraits[j] = pf
    end

    row.forces = Text(row, 8, "RIGHT")
    row.forces:SetPoint("RIGHT", -2, 0)
    row.forces:SetWidth(42)

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
expandedBlock:Hide()

local expandedMobRows = {}

local PORTRAIT_SIZE = 24
local COL_COUNT_W = 20
local COL_PCT_W = 46

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
    row.name:SetPoint("RIGHT", row, "RIGHT", -(COL_PCT_W + 2), 0)
    row.name:SetWordWrap(false)

    -- Column 3: % forces
    row.forces = Text(row, 9, "RIGHT")
    row.forces:SetPoint("RIGHT", -2, 0)
    row.forces:SetWidth(COL_PCT_W)
    row.forces:SetTextColor(0.5, 0.7, 1)

    -- Tooltip on hover
    row.mobName = ""
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.mobName, 1, 1, 1)
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

    local total = self:GetPullCount()
    local done = self:GetCompletedCount()
    local cur = self.currentPullIdx
    local n = #self.pulls

    -- Header
    headerText:SetText("Pull " .. cur .. " / " .. total .. " |r")

    -- Forces bar
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
                    row.forces:SetText(ForcePct(e.forces * e.numClones))
                else
                    row.forces:SetText("")
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
    else
        expandedBlock:Hide()
    end

    -- Layout all pulls in the list, inserting expanded block at current pull
    local yOff = 0

    for i = 1, math.max(n, #pullRows) do
        local row = GetPullRow(i)
        if i <= n then
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

                if p.totalForces > 0 then
                    row.forces:SetText(ForcePct(p.totalForces))
                else
                    row.forces:SetText("")
                end

                local dimPortraits = false
                if p.completed then
                    SetBg(row, 0.06, 0.06, 0.06, 0.7)
                    row.num:Hide()
                    row.bossIcon:Hide()
                    row.check:Show()
                    row.forces:SetTextColor(0.25, 0.25, 0.25)
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
                    row.forces:SetTextColor(0.4, 0.55, 0.7)
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
    local maxListH = math.min(yOff, 500)
    local totalHeight = 40 + maxListH + 6
    f:SetHeight(totalHeight)
    listSection:SetHeight(maxListH)

    -- Auto scroll to keep current pull visible
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
