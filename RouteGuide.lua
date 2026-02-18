local H = MDTHelper

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local WIDTH = 240
local FONT = "Fonts\\FRIZQT__.TTF"

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

-- Prev / Next
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
-- Current pull section — big, prominent
------------------------------------------------------------------------
local currentSection = CreateFrame("Frame", nil, f)
currentSection:SetPoint("TOPLEFT", 4, -40)
currentSection:SetSize(WIDTH - 8, 20)
Bg(currentSection, 0.12, 0.1, 0.02, 0.9)

local currentTitle = Text(currentSection, 11, "LEFT")
currentTitle:SetPoint("TOPLEFT", 6, -4)
currentTitle:SetTextColor(1, 0.85, 0)

-- Mob rows inside current pull
local currentMobRows = {}

local function GetCurrentMobRow(i)
    if currentMobRows[i] then return currentMobRows[i] end

    local row = CreateFrame("Frame", nil, currentSection)
    row:SetSize(WIDTH - 20, 16)
    row:SetPoint("TOPLEFT", 8, -(20 + (i - 1) * 17))

    row.skull = row:CreateTexture(nil, "ARTWORK")
    row.skull:SetSize(12, 12)
    row.skull:SetPoint("LEFT", 1, 0)
    row.skull:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    row.skull:Hide()

    row.name = Text(row, 10)
    row.name:SetPoint("LEFT", 14, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -48, 0)
    row.name:SetWordWrap(false)

    row.forces = Text(row, 9, "RIGHT")
    row.forces:SetPoint("RIGHT", -2, 0)
    row.forces:SetWidth(46)
    row.forces:SetTextColor(0.5, 0.7, 1)

    row:Hide()
    currentMobRows[i] = row
    return row
end

------------------------------------------------------------------------
-- Pull list section — compact rows below
------------------------------------------------------------------------
local listSection = CreateFrame("Frame", nil, f)
listSection:SetPoint("TOPLEFT", 0, -100) -- repositioned in UpdateUI
listSection:SetSize(WIDTH, 100)

local listContent = CreateFrame("Frame", nil, listSection)
listContent:SetPoint("TOPLEFT", 4, 0)
listContent:SetSize(WIDTH - 8, 1)
listSection:SetClipsChildren(true)

local pullRows = {}

local function GetPullRow(i)
    if pullRows[i] then return pullRows[i] end

    local row = CreateFrame("Frame", nil, listContent)
    row:SetSize(WIDTH - 8, 18)
    Bg(row, 0.08, 0.08, 0.08, 0.7)

    row.num = Text(row, 9, "CENTER")
    row.num:SetPoint("LEFT", 2, 0)
    row.num:SetWidth(18)

    row.bossIcon = row:CreateTexture(nil, "ARTWORK")
    row.bossIcon:SetSize(12, 12)
    row.bossIcon:SetPoint("CENTER", row.num, "CENTER")
    row.bossIcon:SetAtlas("UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    row.bossIcon:Hide()

    row.summary = Text(row, 8)
    row.summary:SetPoint("LEFT", row.num, "RIGHT", 2, 0)
    row.summary:SetPoint("RIGHT", row, "RIGHT", -44, 0)
    row.summary:SetWordWrap(false)

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
-- Scroll for pull list
------------------------------------------------------------------------
local scrollOffset = 0
f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta)
    local n = #H.pulls
    local maxOff = math.max(0, n * 19 - listSection:GetHeight())
    scrollOffset = math.max(0, math.min(scrollOffset - delta * 38, maxOff))
    listContent:SetPoint("TOPLEFT", 4, scrollOffset)
end)

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
-- Format summary
------------------------------------------------------------------------
local function ShortSummary(pull)
    local p = {}
    for _, e in ipairs(pull.enemies) do
        if e.numClones > 1 then
            p[#p + 1] = e.numClones .. "x " .. e.name
        else
            p[#p + 1] = e.name
        end
    end
    return table.concat(p, ", ")
end

------------------------------------------------------------------------
-- Update UI
------------------------------------------------------------------------
function H:UpdateUI()
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

    -- Header
    headerText:SetText("Pull " .. cur .. " / " .. total .. "  |cff888888(" .. done .. " done)|r")

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

    -- Current pull detail
    local pull = self.pulls[cur]
    if pull then
        local r, g, b = 1, 0.85, 0
        if pull.color then
            r = tonumber(pull.color[1]) or 1
            g = tonumber(pull.color[2]) or 1
            b = tonumber(pull.color[3]) or 1
            if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
        end

        currentTitle:SetText("PULL " .. cur .. "  |cffffffff" .. ForcePct(pull.totalForces) .. "|r")
        currentTitle:SetTextColor(r, g, b)

        local numEnemies = #pull.enemies
        for i = 1, math.max(numEnemies, #currentMobRows) do
            local row = GetCurrentMobRow(i)
            if i <= numEnemies then
                local e = pull.enemies[i]
                local prefix = ""
                if e.numClones > 1 then prefix = e.numClones .. "x " end
                row.name:SetText(prefix .. e.name)
                if e.isBoss then
                    row.skull:Show()
                    row.name:SetTextColor(1, 0.82, 0)
                else
                    row.skull:Hide()
                    row.name:SetTextColor(0.95, 0.95, 0.95)
                end
                if e.forces > 0 then
                    row.forces:SetText(ForcePct(e.forces * e.numClones))
                else
                    row.forces:SetText("")
                end
                row:Show()
            else
                row:Hide()
                row.skull:Hide()
            end
        end

        local currentHeight = 24 + numEnemies * 17
        currentSection:SetHeight(currentHeight)
    else
        currentTitle:SetText("")
        currentSection:SetHeight(24)
        for _, row in ipairs(currentMobRows) do row:Hide() end
    end

    -- Pull list position (below current section)
    local currentBottom = 40 + currentSection:GetHeight() + 4
    listSection:SetPoint("TOPLEFT", 0, -currentBottom)

    -- Pull list rows
    local n = #self.pulls
    local listHeight = n * 19
    listContent:SetHeight(math.max(listHeight, 1))

    for i = 1, math.max(n, #pullRows) do
        local row = GetPullRow(i)
        if i <= n then
            local p = self.pulls[i]
            row:Show()
            row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -((i - 1) * 19))

            row.num:SetText(tostring(i))
            local pr, pg, pb = 0.7, 0.7, 0.7
            if p.color then
                pr = tonumber(p.color[1]) or 0.7
                pg = tonumber(p.color[2]) or 0.7
                pb = tonumber(p.color[3]) or 0.7
                if pr > 1 or pg > 1 or pb > 1 then pr, pg, pb = pr / 255, pg / 255, pb / 255 end
            end

            row.summary:SetText(ShortSummary(p))

            if p.totalForces > 0 then
                row.forces:SetText(ForcePct(p.totalForces))
            else
                row.forces:SetText("")
            end

            if p.completed then
                SetBg(row, 0.06, 0.06, 0.06, 0.7)
                row.num:Hide()
                row.bossIcon:Hide()
                row.check:Show()
                row.summary:SetTextColor(0.35, 0.35, 0.35)
                row.forces:SetTextColor(0.25, 0.25, 0.25)
            elseif i == cur then
                SetBg(row, 0.25, 0.2, 0, 0.7)
                row.check:Hide()
                if p.hasBoss then
                    row.num:Hide()
                    row.bossIcon:Show()
                else
                    row.num:Show()
                    row.bossIcon:Hide()
                end
                row.num:SetTextColor(1, 0.85, 0)
                row.summary:SetTextColor(1, 1, 1)
                row.forces:SetTextColor(0.5, 0.7, 1)
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
                row.summary:SetTextColor(0.6, 0.6, 0.6)
                row.forces:SetTextColor(0.4, 0.55, 0.7)
            end
        else
            row:Hide()
        end
    end

    -- Size the frame to fit
    local maxListRows = math.min(n, 15)
    local totalHeight = currentBottom + (maxListRows * 19) + 6
    f:SetHeight(totalHeight)
    listSection:SetHeight(maxListRows * 19)

    -- Auto scroll to keep current visible in list
    if n > maxListRows then
        local tgt = math.max(0, (cur - 3) * 19)
        local mx = math.max(0, listHeight - listSection:GetHeight())
        scrollOffset = math.min(tgt, mx)
        listContent:SetPoint("TOPLEFT", 4, scrollOffset)
    else
        scrollOffset = 0
        listContent:SetPoint("TOPLEFT", 4, 0)
    end
end
