local H = MDTHelper

------------------------------------------------------------------------
-- Constants — match MDT exactly: sizex=840, sizey=555
------------------------------------------------------------------------
local MDT_W = 840
local MDT_H = 555
local DEFAULT_W = 300
local DEFAULT_H = 300
local MIN_SIZE = 150
local MAX_SIZE = 800
local FONT = "Fonts\\FRIZQT__.TTF"
local BLIP_SIZE = 13
local BLIP_BOSS_SIZE = 25
local TITLE_H = 24
local ZOOM_BORDER = 50
local SURROUND_RADIUS = 20 -- only show surrounding mobs within this distance of the pull bbox

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local currentDungeonIdx = nil
local currentSublevel = 1
local userZoomOffset = 0 -- manual zoom adjustment: negative = zoom out, positive = zoom in
local userPanOffsetX = 0 -- manual pan offset in panel-space pixels
local userPanOffsetY = 0 -- manual pan offset in panel-space pixels
local lastPullIdx = nil  -- track pull changes to reset zoom offset

------------------------------------------------------------------------
-- Main frame (outer chrome: title bar, backdrop, resize)
------------------------------------------------------------------------
local mf = CreateFrame("Frame", "MDTHelperMapPopout", UIParent, "BackdropTemplate")
mf:SetSize(DEFAULT_W, DEFAULT_H)
mf:SetPoint("CENTER")
mf:SetFrameStrata("MEDIUM")
mf:SetClampedToScreen(true)
mf:EnableMouse(true)
mf:SetMovable(true)
mf:Hide()

mf:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
mf:SetBackdropColor(0.04, 0.04, 0.04, 0.95)
mf:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

------------------------------------------------------------------------
-- Title bar
------------------------------------------------------------------------
local titleBar = CreateFrame("Frame", nil, mf)
titleBar:SetHeight(TITLE_H)
titleBar:SetPoint("TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", 0, 0)
titleBar:EnableMouse(true)

local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
titleBg:SetAllPoints()
titleBg:SetColorTexture(0.08, 0.08, 0.08, 1)

local titleText = titleBar:CreateFontString(nil, "OVERLAY")
titleText:SetFont(FONT, 10, "OUTLINE")
titleText:SetPoint("LEFT", 8, 0)
titleText:SetTextColor(0, 0.8, 1)
titleText:SetText("Map")

local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
closeBtn:SetSize(18, 18)
closeBtn:SetPoint("RIGHT", -2, 0)
closeBtn:SetScript("OnClick", function()
    mf:Hide()
    H.db.mapPopout = false
end)

-- Forward declare UpdateMapPopout so buttons can call it
local UpdateMapPopout

-- Surround mobs toggle button (in title bar, next to close)
local surroundBtn = CreateFrame("Frame", nil, titleBar)
surroundBtn:SetSize(16, 16)
surroundBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
surroundBtn:EnableMouse(true)
local surroundIcon = surroundBtn:CreateTexture(nil, "OVERLAY")
surroundIcon:SetSize(14, 14)
surroundIcon:SetPoint("CENTER")
surroundIcon:SetTexture("Interface\\Minimap\\Tracking\\None")

local function UpdateSurroundBtnColor()
    local on = H.db.mapShowSurround ~= false
    surroundIcon:SetDesaturated(not on)
    surroundIcon:SetAlpha(on and 1 or 0.4)
end

surroundBtn:SetScript("OnEnter", function(self)
    surroundIcon:SetDesaturated(false)
    surroundIcon:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local on = H.db.mapShowSurround ~= false
    GameTooltip:SetText("Surrounding mobs: " .. (on and "shown" or "hidden"), 1, 1, 1)
    GameTooltip:Show()
end)
surroundBtn:SetScript("OnLeave", function()
    UpdateSurroundBtnColor()
    GameTooltip:Hide()
end)
surroundBtn:SetScript("OnMouseDown", function()
    H.db.mapShowSurround = not (H.db.mapShowSurround ~= false)
    UpdateSurroundBtnColor()
    if UpdateMapPopout then UpdateMapPopout() end
end)

titleBar:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" and not H.db.locked then mf:StartMoving() end
end)
titleBar:SetScript("OnMouseUp", function()
    mf:StopMovingOrSizing()
    local scale = mf:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    local left, top = mf:GetLeft(), mf:GetTop()
    local x = (left * scale) / uiScale
    local y = (top * scale) / uiScale - UIParent:GetHeight()
    mf:ClearAllPoints()
    mf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    H.db.mapPopoutPoint = { "TOPLEFT", "TOPLEFT", x, y }
end)

------------------------------------------------------------------------
-- ScrollFrame — same pattern as MDT: ScrollFrame > mapPanel (scroll child)
-- ScrollFrame clips, mapPanel holds tiles+blips, SetScale on mapPanel for zoom,
-- SetHorizontalScroll / SetVerticalScroll for panning.
------------------------------------------------------------------------
local scrollFrame = CreateFrame("ScrollFrame", "MDTHelperMapScrollFrame", mf)
scrollFrame:SetPoint("TOPLEFT", 0, -TITLE_H)
scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)

------------------------------------------------------------------------
-- Map panel (scroll child) — base size = scrollFrame size (like MDT)
-- Tiles + blips are children of this frame.
------------------------------------------------------------------------
scrollFrame:EnableMouseWheel(true)
scrollFrame:EnableMouse(true)
scrollFrame:SetScript("OnMouseWheel", function(_, delta)
    userZoomOffset = userZoomOffset + delta * 0.3
    if UpdateMapPopout then UpdateMapPopout() end
end)

-- Left-click drag to pan
local isPanning = false
local panStartX, panStartY = 0, 0

scrollFrame:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then
        isPanning = true
        local es = scrollFrame:GetEffectiveScale()
        panStartX = GetCursorPosition() / es
        panStartY = select(2, GetCursorPosition()) / es
    end
end)

scrollFrame:SetScript("OnMouseUp", function(_, btn)
    if btn == "LeftButton" then isPanning = false end
end)

local mapPanel = CreateFrame("Frame", "MDTHelperMapPanel", nil)
mapPanel:SetSize(MDT_W, MDT_H) -- will be resized to match scrollFrame
scrollFrame:SetScrollChild(mapPanel)

scrollFrame:SetScript("OnUpdate", function()
    if not isPanning then return end
    local es = scrollFrame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx = cx / es
    cy = cy / es
    local dx = cx - panStartX
    local dy = cy - panStartY
    panStartX, panStartY = cx, cy

    local zoomScale = mapPanel:GetScale() or 1
    userPanOffsetX = userPanOffsetX - dx / zoomScale
    userPanOffsetY = userPanOffsetY + dy / zoomScale
    if UpdateMapPopout then UpdateMapPopout() end
end)

------------------------------------------------------------------------
-- Tiles: 4x3 (Blizzard) — square, size = frame:GetWidth()/4
------------------------------------------------------------------------
local tiles4 = {}
for i = 1, 12 do
    tiles4[i] = mapPanel:CreateTexture(nil, "BACKGROUND", nil, 0)
    tiles4[i]:Hide()
end
tiles4[1]:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 0, 0)
tiles4[2]:SetPoint("TOPLEFT", tiles4[1], "TOPRIGHT")
tiles4[3]:SetPoint("TOPLEFT", tiles4[2], "TOPRIGHT")
tiles4[4]:SetPoint("TOPLEFT", tiles4[3], "TOPRIGHT")
tiles4[5]:SetPoint("TOPLEFT", tiles4[1], "BOTTOMLEFT")
tiles4[6]:SetPoint("TOPLEFT", tiles4[5], "TOPRIGHT")
tiles4[7]:SetPoint("TOPLEFT", tiles4[6], "TOPRIGHT")
tiles4[8]:SetPoint("TOPLEFT", tiles4[7], "TOPRIGHT")
tiles4[9]:SetPoint("TOPLEFT", tiles4[5], "BOTTOMLEFT")
tiles4[10]:SetPoint("TOPLEFT", tiles4[9], "TOPRIGHT")
tiles4[11]:SetPoint("TOPLEFT", tiles4[10], "TOPRIGHT")
tiles4[12]:SetPoint("TOPLEFT", tiles4[11], "TOPRIGHT")

------------------------------------------------------------------------
-- Tiles: 15x10 (custom) — square, size = frame:GetWidth()/15
------------------------------------------------------------------------
local tiles15 = {}
for i = 1, 10 do
    tiles15[i] = {}
    for j = 1, 15 do
        local t = mapPanel:CreateTexture(nil, "BACKGROUND", nil, 5)
        t:Hide()
        tiles15[i][j] = t
        if i == 1 and j == 1 then
            t:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 0, 0)
        elseif j == 1 then
            t:SetPoint("TOPLEFT", tiles15[i - 1][j], "BOTTOMLEFT", 0, 0)
        else
            t:SetPoint("TOPLEFT", tiles15[i][j - 1], "TOPRIGHT", 0, 0)
        end
    end
end

------------------------------------------------------------------------
-- Resize tiles to match the mapPanel width. Tiles are square.
------------------------------------------------------------------------
local function ResizeTiles(panelW)
    local sz4 = panelW / 4
    for i = 1, 12 do tiles4[i]:SetSize(sz4, sz4) end
    local sz15 = panelW / 15
    for i = 1, 10 do
        for j = 1, 15 do tiles15[i][j]:SetSize(sz15, sz15) end
    end
end

------------------------------------------------------------------------
-- Texture loading — same logic as MDT:UpdateMap
------------------------------------------------------------------------
local function HideAllTiles()
    for i = 1, 12 do tiles4[i]:Hide() end
    for i = 1, 10 do
        for j = 1, 15 do tiles15[i][j]:Hide() end
    end
end

local function LoadMapTextures(dungeonIdx, sublevel)
    HideAllTiles()
    if not MDT or not MDT.dungeonMaps then return false end
    local mapData = MDT.dungeonMaps[dungeonIdx]
    if not mapData then return false end

    local textureInfo = mapData[sublevel]
    if not textureInfo then return false end

    if type(textureInfo) == "string" then
        -- Blizzard textures
        local mapName = mapData[0] or ""
        local tileFormat = 4
        if MDT.GetTileFormat then
            tileFormat = MDT:GetTileFormat(dungeonIdx, sublevel)
        end
        local path = "Interface\\WorldMap\\" .. mapName .. "\\"
        if tileFormat == 4 then
            for i = 1, 12 do
                tiles4[i]:SetTexture(path .. textureInfo .. i)
                tiles4[i]:Show()
            end
        else
            for i = 1, 10 do
                for j = 1, 15 do
                    local idx = (i - 1) * 15 + j
                    tiles15[i][j]:SetTexture(path .. textureInfo .. idx)
                    tiles15[i][j]:Show()
                end
            end
        end
    elseif type(textureInfo) == "table" and textureInfo.customTextures then
        -- Custom textures — always 15x10
        for i = 1, 10 do
            for j = 1, 15 do
                local idx = (i - 1) * 15 + j
                local texPath = textureInfo.customTextures .. "\\" .. sublevel .. "_" .. idx .. ".png"
                tiles15[i][j]:SetTexture(texPath)
                tiles15[i][j]:Show()
            end
        end
    else
        return false
    end

    currentSublevel = sublevel
    currentDungeonIdx = dungeonIdx
    return true
end

------------------------------------------------------------------------
-- Portrait blip pool — frames on mapPanel with portrait + mask + ring + color overlay
-- Used for ALL mobs; current pull gets pull color overlay, others get red overlay
------------------------------------------------------------------------
local blips = {}
local activeBlipCount = 0

local MDT_RING_TEX = "Interface\\AddOns\\MythicDungeonTools\\Textures\\UI-EncounterJournalTextures"
local MDT_RING_L, MDT_RING_R, MDT_RING_T, MDT_RING_B = 0.85, 0.97, 0.43, 0.4865

local function CreateBlip()
    local bf = CreateFrame("Frame", nil, mapPanel)
    bf:SetSize(16, 16)
    bf:EnableMouse(true)

    -- Portrait texture (BORDER layer — below ring)
    local portrait = bf:CreateTexture(nil, "BORDER")
    portrait:SetAllPoints()
    bf.portrait = portrait

    -- Circular mask
    local mask = bf:CreateMaskTexture()
    mask:SetAllPoints(portrait)
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    portrait:AddMaskTexture(mask)

    -- Color overlay (ARTWORK layer — between portrait and ring)
    local overlay = bf:CreateTexture(nil, "ARTWORK")
    overlay:SetAllPoints()
    overlay:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    overlay:AddMaskTexture(mask)
    bf.overlay = overlay

    -- Ring (OVERLAY layer — on top)
    local ring = bf:CreateTexture(nil, "OVERLAY")
    ring:SetPoint("CENTER")
    ring:SetTexture(MDT_RING_TEX)
    ring:SetTexCoord(MDT_RING_L, MDT_RING_R, MDT_RING_T, MDT_RING_B)
    bf.ring = ring

    -- Tooltip
    bf:SetScript("OnEnter", function(self)
        if self.mobName then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            local txt = self.mobName
            if self.mobForces and self.mobForces > 0 then
                local pct = H.totalForcesRequired > 0
                    and string.format("%.1f%%", self.mobForces / H.totalForcesRequired * 100)
                    or "?"
                txt = txt .. "\n|cffffffff" .. self.mobForces .. " forces (" .. pct .. ")|r"
            end
            if self.mobIsBoss then txt = txt .. "\n|cffffff00Boss|r" end
            if self.isSurrounding then txt = txt .. "\n|cffff4444Skip|r" end
            GameTooltip:SetText(txt)
            GameTooltip:Show()
        end
    end)
    bf:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bf:Hide()
    return bf
end

local function GetBlip(idx)
    if blips[idx] then return blips[idx] end
    blips[idx] = CreateBlip()
    return blips[idx]
end

local function HideAllBlips()
    for i = 1, activeBlipCount do blips[i]:Hide() end
    activeBlipCount = 0
end

------------------------------------------------------------------------
-- Sublevel detection
------------------------------------------------------------------------
local function GetPullSublevel(pull)
    if not pull or not pull.clonePositions or #pull.clonePositions == 0 then
        return 1
    end
    local counts = {}
    for _, cp in ipairs(pull.clonePositions) do
        local sl = cp.sublevel or 1
        counts[sl] = (counts[sl] or 0) + 1
    end
    local bestSL, bestCount = 1, 0
    for sl, c in pairs(counts) do
        if c > bestCount then bestSL, bestCount = sl, c end
    end
    return bestSL
end

------------------------------------------------------------------------
-- Sublevel buttons (in title bar)
------------------------------------------------------------------------
local sublevelButtons = {}

local function UpdateSublevelHighlight()
    for _, btn in ipairs(sublevelButtons) do
        if btn.idx == currentSublevel then
            btn.text:SetTextColor(0, 0.8, 1)
        else
            btn.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

local UpdateBlips -- forward declare

local function UpdateSublevelButtons(dungeonIdx)
    for _, btn in ipairs(sublevelButtons) do btn:Hide() end
    if not MDT or not MDT.dungeonSubLevels then return end
    local sublevels = MDT.dungeonSubLevels[dungeonIdx]
    if not sublevels or #sublevels <= 1 then return end

    for i = 1, #sublevels do
        if not sublevelButtons[i] then
            local btn = CreateFrame("Frame", nil, titleBar)
            btn:SetSize(16, 16)
            btn:EnableMouse(true)
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.15, 0.15, 0.15, 1)
            local txt = btn:CreateFontString(nil, "OVERLAY")
            txt:SetFont(FONT, 9, "OUTLINE")
            txt:SetPoint("CENTER")
            btn.text = txt
            btn.idx = i
            btn:SetScript("OnMouseDown", function(self)
                if not H.dungeonIdx then return end
                LoadMapTextures(H.dungeonIdx, self.idx)
                UpdateSublevelHighlight()
                if UpdateBlips then UpdateBlips() end
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local sl = MDT and MDT.dungeonSubLevels and H.dungeonIdx
                    and MDT.dungeonSubLevels[H.dungeonIdx]
                GameTooltip:SetText(sl and sl[self.idx] or ("Floor " .. self.idx), 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            sublevelButtons[i] = btn
        end
        sublevelButtons[i].text:SetText(tostring(i))
        sublevelButtons[i].idx = i
        sublevelButtons[i]:ClearAllPoints()
        sublevelButtons[i]:SetPoint("RIGHT", surroundBtn, "LEFT", -4 - (#sublevels - i) * 20, 0)
        sublevelButtons[i]:Show()
    end
    UpdateSublevelHighlight()
end

------------------------------------------------------------------------
-- Zoom to pull
------------------------------------------------------------------------
local function GetBaseScale()
    local sw = scrollFrame:GetWidth()
    if sw <= 0 then return 1 end
    return sw / MDT_W
end

local function ZoomToPull(pull)
    local sw = scrollFrame:GetWidth()
    local sh = scrollFrame:GetHeight()
    if sw <= 0 or sh <= 0 then return end

    local baseScale = sw / MDT_W
    local panelW = MDT_W * baseScale
    local panelH = MDT_H * baseScale
    mapPanel:SetSize(panelW, panelH)
    ResizeTiles(panelW)

    -- Collect bounding box of clones on current sublevel
    local minX, maxX, minY, maxY
    if pull and pull.clonePositions then
        for _, cp in ipairs(pull.clonePositions) do
            if cp.sublevel == currentSublevel then
                if not minX or cp.x < minX then minX = cp.x end
                if not maxX or cp.x > maxX then maxX = cp.x end
                if not minY or cp.y < minY then minY = cp.y end
                if not maxY or cp.y > maxY then maxY = cp.y end
            end
        end
    end

    if not minX then
        mapPanel:SetScale(1)
        scrollFrame:SetHorizontalScroll(0)
        scrollFrame:SetVerticalScroll(0)
        return
    end

    -- Pad bounding box
    minX = minX - ZOOM_BORDER
    maxX = maxX + ZOOM_BORDER
    minY = minY - ZOOM_BORDER
    maxY = maxY + ZOOM_BORDER

    local diffX = maxX - minX
    local diffY = -(minY - maxY)
    if diffX < 1 then diffX = 1 end
    if diffY < 1 then diffY = 1 end

    local zoomScale = math.min(sw / (diffX * baseScale), sh / (diffY * baseScale))
    zoomScale = zoomScale + userZoomOffset
    if zoomScale < 1 then zoomScale = 1 end
    if zoomScale > 10 then zoomScale = 10 end

    mapPanel:SetScale(zoomScale)

    local centerX = (minX + maxX) / 2 * baseScale
    local centerY = -(minY + maxY) / 2 * baseScale

    local scrollH = centerX - sw / (2 * zoomScale) + userPanOffsetX
    local scrollV = centerY - sh / (2 * zoomScale) + userPanOffsetY

    -- Clamp
    local maxScrollH = (panelW * zoomScale - panelW) / zoomScale
    local maxScrollV = (panelH * zoomScale - panelH) / zoomScale
    if maxScrollH < 0 then maxScrollH = 0 end
    if maxScrollV < 0 then maxScrollV = 0 end
    if scrollH < 0 then scrollH = 0 end
    if scrollH > maxScrollH then scrollH = maxScrollH end
    if scrollV < 0 then scrollV = 0 end
    if scrollV > maxScrollV then scrollV = maxScrollV end

    scrollFrame:SetHorizontalScroll(scrollH)
    scrollFrame:SetVerticalScroll(scrollV)
end

------------------------------------------------------------------------
-- Blip rendering
------------------------------------------------------------------------
local function SetupBlip(blip, cp, baseScale, sz, overlayR, overlayG, overlayB, overlayA)
    blip:SetSize(sz, sz)
    blip.ring:SetSize(sz * 1.28, sz * 1.28)

    -- Portrait
    if cp.displayId then
        SetPortraitTextureFromCreatureDisplayID(blip.portrait, cp.displayId)
    else
        blip.portrait:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    end
    blip.portrait:SetVertexColor(1, 1, 1, 1)

    -- Color overlay
    blip.overlay:SetVertexColor(overlayR, overlayG, overlayB, overlayA)

    -- Ring color matches overlay
    blip.ring:SetVertexColor(overlayR, overlayG, overlayB, 1)

    -- Tooltip data
    blip.mobName = cp.name
    blip.mobForces = cp.forces
    blip.mobIsBoss = cp.isBoss

    blip:ClearAllPoints()
    blip:SetPoint("CENTER", tiles4[1], "TOPLEFT", cp.x * baseScale, cp.y * baseScale)
    blip:Show()
end

UpdateBlips = function()
    HideAllBlips()
    if not H.pulls or not H.currentPullIdx then return end
    local pull = H.pulls[H.currentPullIdx]
    if not pull or not pull.clonePositions then return end

    local baseScale = GetBaseScale()
    local zoomScale = mapPanel:GetScale() or 1

    -- Build lookup of all clones in pulls up to and including current (already killed or being pulled)
    local pullCloneKeys = {}
    for i = 1, H.currentPullIdx do
        local p = H.pulls[i]
        if p and p.clonePositions then
            for _, cp in ipairs(p.clonePositions) do
                if cp.enemyIdx and cp.cloneIdx then
                    pullCloneKeys[cp.enemyIdx .. "_" .. cp.cloneIdx] = true
                end
            end
        end
    end

    -- Compute pull bounding box for proximity filtering (in original MDT coords)
    local minX, maxX, minY, maxY
    for _, cp in ipairs(pull.clonePositions) do
        if cp.sublevel == currentSublevel then
            if not minX or cp.x < minX then minX = cp.x end
            if not maxX or cp.x > maxX then maxX = cp.x end
            if not minY or cp.y < minY then minY = cp.y end
            if not maxY or cp.y > maxY then maxY = cp.y end
        end
    end

    local idx = 0

    -- 1) Surrounding mobs: nearby clones on this sublevel NOT in current pull — red overlay
    local showSurround = H.db.mapShowSurround ~= false
    local allClones = H.allClonePositions and H.allClonePositions[currentSublevel]
    if showSurround and allClones and minX then
        local rad = SURROUND_RADIUS
        for _, cp in ipairs(allClones) do
            local key = cp.enemyIdx .. "_" .. cp.cloneIdx
            if not pullCloneKeys[key] then
                if cp.x >= minX - rad and cp.x <= maxX + rad
                    and cp.y >= minY - rad and cp.y <= maxY + rad then
                    idx = idx + 1
                    local blip = GetBlip(idx)
                    local sz = BLIP_SIZE / zoomScale
                    if cp.isBoss then sz = BLIP_BOSS_SIZE / zoomScale end
                    SetupBlip(blip, cp, baseScale, sz, 0.7, 0.1, 0.1, 0.6)
                    blip.isSurrounding = true
                    blip:SetFrameLevel(mapPanel:GetFrameLevel() + 2)
                end
            end
        end
    end

    -- 2) Current pull mobs on top — no color overlay, just portraits
    for _, cp in ipairs(pull.clonePositions) do
        if cp.sublevel == currentSublevel then
            idx = idx + 1
            local blip = GetBlip(idx)
            local sz = BLIP_SIZE / zoomScale
            if cp.isBoss then sz = BLIP_BOSS_SIZE / zoomScale end
            SetupBlip(blip, cp, baseScale, sz, 0, 0, 0, 0)
            blip.isSurrounding = false
            blip:SetFrameLevel(mapPanel:GetFrameLevel() + 5)
        end
    end

    activeBlipCount = idx
end

------------------------------------------------------------------------
-- Map control buttons (bottom-right overlay on the map area)
------------------------------------------------------------------------
local BTN_SZ = 20
local BTN_GAP = 1

-- Container frame anchored to bottom-right of the map, above resize handle
local controlBar = CreateFrame("Frame", nil, mf)
controlBar:SetSize(3 * BTN_SZ + 2 * BTN_GAP, BTN_SZ)
controlBar:SetPoint("BOTTOMRIGHT", -4, 8)
controlBar:SetFrameLevel(mf:GetFrameLevel() + 8) -- above map, below resize

-- Zoom +
local zoomInBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
zoomInBtn:SetSize(BTN_SZ, BTN_SZ)
zoomInBtn:SetPoint("RIGHT", controlBar, "RIGHT", 0, 0)
zoomInBtn:SetText("+")
zoomInBtn:SetNormalFontObject("GameFontNormalSmall")
zoomInBtn:SetScript("OnClick", function()
    userZoomOffset = userZoomOffset + 0.3
    if UpdateMapPopout then UpdateMapPopout() end
end)

-- Zoom -
local zoomOutBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
zoomOutBtn:SetSize(BTN_SZ, BTN_SZ)
zoomOutBtn:SetPoint("RIGHT", zoomInBtn, "LEFT", -BTN_GAP, 0)
zoomOutBtn:SetText("-")
zoomOutBtn:SetNormalFontObject("GameFontNormalSmall")
zoomOutBtn:SetScript("OnClick", function()
    userZoomOffset = userZoomOffset - 0.3
    if UpdateMapPopout then UpdateMapPopout() end
end)

-- Reset view
local resetBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
resetBtn:SetSize(BTN_SZ, BTN_SZ)
resetBtn:SetPoint("RIGHT", zoomOutBtn, "LEFT", -BTN_GAP, 0)
resetBtn:SetNormalFontObject("GameFontNormalSmall")
-- Use a circular arrow icon texture instead of text
local resetIcon = resetBtn:CreateTexture(nil, "OVERLAY")
resetIcon:SetSize(12, 12)
resetIcon:SetPoint("CENTER")
resetIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
resetBtn:SetScript("OnClick", function()
    userZoomOffset = 0
    userPanOffsetX = 0
    userPanOffsetY = 0
    if UpdateMapPopout then UpdateMapPopout() end
end)
resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Reset view", 1, 1, 1)
    GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

------------------------------------------------------------------------
-- Resize handle
------------------------------------------------------------------------
local resizeHandle = CreateFrame("Frame", nil, mf)
resizeHandle:SetHeight(6)
resizeHandle:SetPoint("BOTTOMLEFT", 0, 0)
resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0)
resizeHandle:EnableMouse(true)
resizeHandle:SetFrameLevel(mf:GetFrameLevel() + 10)

local resizeIndicator = resizeHandle:CreateTexture(nil, "OVERLAY")
resizeIndicator:SetSize(30, 2)
resizeIndicator:SetPoint("CENTER")
resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4)

resizeHandle:SetScript("OnEnter", function()
    if not H.db.locked then resizeIndicator:SetColorTexture(0, 0.8, 1, 0.7) end
end)
resizeHandle:SetScript("OnLeave", function()
    if not H.db.locked then resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4) end
end)

local isResizing = false
resizeHandle:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" and not H.db.locked then
        isResizing = true
        mf.resizeStartY = select(2, GetCursorPosition()) / mf:GetEffectiveScale()
        mf.resizeStartH = mf:GetHeight()
    end
end)

resizeHandle:SetScript("OnMouseUp", function()
    if isResizing then
        isResizing = false
        H.db.mapPopoutSize = { mf:GetWidth(), mf:GetHeight() }
    end
end)

resizeHandle:SetScript("OnUpdate", function()
    if not isResizing then return end
    local curY = select(2, GetCursorPosition()) / mf:GetEffectiveScale()
    local delta = mf.resizeStartY - curY
    local newH = math.max(MIN_SIZE, math.min(mf.resizeStartH + delta, MAX_SIZE))
    mf:SetHeight(newH)
    local pull = H.pulls and H.pulls[H.currentPullIdx]
    if pull then
        ZoomToPull(pull)
        UpdateBlips()
    end
end)

------------------------------------------------------------------------
-- Opacity
------------------------------------------------------------------------
local function ApplyMapOpacity(alpha)
    mf:SetBackdropColor(0.04, 0.04, 0.04, 0.95 * alpha)
    titleBg:SetColorTexture(0.08, 0.08, 0.08, alpha)
end

local HOVER_ALPHA = 0.85
mf:SetScript("OnEnter", function()
    local alpha = H.db.bgAlpha or 1
    if alpha < HOVER_ALPHA then ApplyMapOpacity(HOVER_ALPHA) end
end)
mf:SetScript("OnLeave", function()
    ApplyMapOpacity(H.db.bgAlpha or 1)
end)

------------------------------------------------------------------------
-- Main update
------------------------------------------------------------------------
UpdateMapPopout = function()
    if not mf:IsShown() then return end
    if not H.dungeonIdx or not H.pulls or #H.pulls == 0 then
        mf:Hide()
        return
    end

    local pull = H.pulls[H.currentPullIdx]
    if not pull then return end

    -- Reset manual zoom/pan when pull changes
    if lastPullIdx ~= H.currentPullIdx then
        userZoomOffset = 0
        userPanOffsetX = 0
        userPanOffsetY = 0
        lastPullIdx = H.currentPullIdx
    end

    local sublevel = GetPullSublevel(pull)

    if currentDungeonIdx ~= H.dungeonIdx or currentSublevel ~= sublevel then
        LoadMapTextures(H.dungeonIdx, sublevel)
    end

    titleText:SetText("Pull " .. H.currentPullIdx .. " / " .. #H.pulls)
    UpdateSurroundBtnColor()
    UpdateSublevelButtons(H.dungeonIdx)

    mf:SetMovable(not H.db.locked)
    resizeHandle:EnableMouse(not H.db.locked)
    if H.db.locked then
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0)
    else
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    end

    ApplyMapOpacity(H.db.bgAlpha or 1)
    ZoomToPull(pull)
    UpdateBlips()
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function H:ToggleMapPopout()
    if mf:IsShown() then
        mf:Hide()
        self.db.mapPopout = false
        print("|cff00ccffMDTHelper|r: Map popout hidden")
    else
        self.db.mapPopout = true
        mf:Show()
        UpdateMapPopout()
        print("|cff00ccffMDTHelper|r: Map popout shown")
    end
end

------------------------------------------------------------------------
-- Hook into UI update cycle
------------------------------------------------------------------------
hooksecurefunc(H, "_DoUpdateUI", function()
    if H.db.mapPopout and H.activeDungeon and H.pulls and #H.pulls > 0 then
        if not mf:IsShown() then mf:Show() end
        UpdateMapPopout()
    elseif mf:IsShown() and (not H.activeDungeon or not H.pulls or #H.pulls == 0) then
        mf:Hide()
    end
end)

------------------------------------------------------------------------
-- Restore saved position and size
------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    if H.db.mapPopoutPoint then
        local p = H.db.mapPopoutPoint
        mf:ClearAllPoints()
        mf:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    if H.db.mapPopoutSize then
        mf:SetSize(H.db.mapPopoutSize[1], H.db.mapPopoutSize[2])
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
