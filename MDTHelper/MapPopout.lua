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
local FONT = STANDARD_TEXT_FONT
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
titleText:SetTextColor(0, 0.8, 1)
titleText:SetText("Map")

-- Nav buttons (prev/next pull)
local prevPullBtn = CreateFrame("Button", nil, titleBar)
prevPullBtn:SetSize(16, TITLE_H)
prevPullBtn:SetPoint("LEFT", 2, 0)
prevPullBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
prevPullBtn:GetHighlightTexture():SetAlpha(0.3)
local prevPullTxt = prevPullBtn:CreateFontString(nil, "OVERLAY")
prevPullTxt:SetFont(FONT, 12, "OUTLINE")
prevPullTxt:SetPoint("CENTER")
prevPullTxt:SetText("<")
prevPullTxt:SetTextColor(0.7, 0.7, 0.7)
prevPullBtn:SetScript("OnClick", function() H:RetreatPull() end)
prevPullBtn:SetScript("OnEnter", function(self)
    prevPullTxt:SetTextColor(0, 0.8, 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Previous pull", 1, 1, 1)
    GameTooltip:Show()
end)
prevPullBtn:SetScript("OnLeave", function()
    prevPullTxt:SetTextColor(0.7, 0.7, 0.7)
    GameTooltip:Hide()
end)

titleText:SetPoint("LEFT", prevPullBtn, "RIGHT", 0, 0)

local nextPullBtn = CreateFrame("Button", nil, titleBar)
nextPullBtn:SetSize(16, TITLE_H)
nextPullBtn:SetPoint("LEFT", titleText, "RIGHT", 0, 0)
nextPullBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
nextPullBtn:GetHighlightTexture():SetAlpha(0.3)
local nextPullTxt = nextPullBtn:CreateFontString(nil, "OVERLAY")
nextPullTxt:SetFont(FONT, 12, "OUTLINE")
nextPullTxt:SetPoint("CENTER")
nextPullTxt:SetText(">")
nextPullTxt:SetTextColor(0.7, 0.7, 0.7)
nextPullBtn:SetScript("OnClick", function() H:AdvancePull() end)
nextPullBtn:SetScript("OnEnter", function(self)
    nextPullTxt:SetTextColor(0, 0.8, 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Next pull", 1, 1, 1)
    GameTooltip:Show()
end)
nextPullBtn:SetScript("OnLeave", function()
    nextPullTxt:SetTextColor(0.7, 0.7, 0.7)
    GameTooltip:Hide()
end)

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
local surroundBtn = CreateFrame("Button", nil, titleBar)
surroundBtn:SetSize(16, 16)
surroundBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
local surroundIcon = surroundBtn:CreateTexture(nil, "ARTWORK")
surroundIcon:SetSize(14, 14)
surroundIcon:SetPoint("CENTER")
surroundIcon:SetAtlas("Waypoint-MapPin-Untracked", false)
surroundBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
surroundBtn:GetHighlightTexture():SetAlpha(0.3)

local function UpdateSurroundBtnColor()
    if H.db.mapFullRoute then
        surroundIcon:SetAtlas("Waypoint-MapPin-Tracked", false)
        surroundIcon:SetDesaturated(true)
        surroundIcon:SetAlpha(0.3)
    else
        local on = H.db.mapShowSurround ~= false
        surroundIcon:SetAtlas(on and "Waypoint-MapPin-Untracked" or "Waypoint-MapPin-Tracked", false)
        surroundIcon:SetDesaturated(false)
        surroundIcon:SetAlpha(1)
    end
end

surroundBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if H.db.mapFullRoute then
        GameTooltip:SetText("Surrounding mobs", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Not available in full route view", 0.5, 0.5, 0.5)
    else
        local on = H.db.mapShowSurround ~= false
        GameTooltip:SetText("Surrounding mobs: " .. (on and "shown" or "hidden"), 1, 1, 1)
    end
    GameTooltip:Show()
end)
surroundBtn:SetScript("OnLeave", function()
    UpdateSurroundBtnColor()
    GameTooltip:Hide()
end)
surroundBtn:SetScript("OnMouseDown", function()
    if H.db.mapFullRoute then return end
    H.db.mapShowSurround = not (H.db.mapShowSurround ~= false)
    UpdateSurroundBtnColor()
    if UpdateMapPopout then UpdateMapPopout() end
end)

-- Full route toggle button (in title bar, next to surround toggle)
local fullRouteBtn = CreateFrame("Button", nil, titleBar)
fullRouteBtn:SetSize(16, 16)
fullRouteBtn:SetPoint("RIGHT", surroundBtn, "LEFT", -2, 0)
fullRouteBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
fullRouteBtn:GetHighlightTexture():SetAlpha(0.3)
local fullRouteIcon = fullRouteBtn:CreateTexture(nil, "ARTWORK")
fullRouteIcon:SetSize(14, 14)
fullRouteIcon:SetPoint("CENTER")

local function UpdateFullRouteBtnColor()
    if H.db.mapFullRoute then
        fullRouteIcon:SetAtlas("orderhall-commandbar-mapbutton-down", false)
    else
        fullRouteIcon:SetAtlas("orderhall-commandbar-mapbutton-up", false)
    end
end

fullRouteBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local on = H.db.mapFullRoute
    GameTooltip:SetText("Full route: " .. (on and "all pulls" or "current pull only"), 1, 1, 1)
    GameTooltip:AddLine("Toggle between current pull and full route view", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
fullRouteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
fullRouteBtn:SetScript("OnMouseDown", function()
    H.db.mapFullRoute = not H.db.mapFullRoute
    userZoomOffset = 0
    userPanOffsetX = 0
    userPanOffsetY = 0
    UpdateFullRouteBtnColor()
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
                txt = txt .. "\n|cffffffff" .. pct .. "|r"
            end
            if self.mobIsBoss then txt = txt .. "\n|cffffff00Boss|r" end
            if self.isSurrounding then txt = txt .. "\n|cffff4444Skip|r" end
            GameTooltip:SetText(txt)
            GameTooltip:Show()
        end
    end)
    bf:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click-to-edit: add/remove this mob from the current pull. Track the cursor
    -- on mouse-down so a press that turns into a drag doesn't toggle the pull.
    bf:SetScript("OnMouseDown", function(self)
        self._downX, self._downY = GetCursorPosition()
    end)
    bf:SetScript("OnMouseUp", function(self, button)
        if not H.db.mapEditPulls then return end
        if not self.enemyIdx or not self.cloneIdx then return end
        if self._downX then
            local x, y = GetCursorPosition()
            local dx, dy = x - self._downX, y - self._downY
            if (dx * dx + dy * dy) > 100 then return end -- moved >10px → treat as drag
        end
        if button == "LeftButton" then
            H:TogglePullMob(self.enemyIdx, self.cloneIdx, true)
        elseif button == "RightButton" then
            H:TogglePullMob(self.enemyIdx, self.cloneIdx, false)
        end
    end)

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
-- Pull number label pool — frames that hide on hover so blips get clicks
------------------------------------------------------------------------
local pullLabels = {}
local activeLabelCount = 0

local function GetPullLabel(idx)
    if pullLabels[idx] then return pullLabels[idx] end
    local lf = CreateFrame("Frame", nil, mapPanel)
    lf:SetSize(24, 18)
    lf:SetFrameLevel(mapPanel:GetFrameLevel() + 20)
    lf:EnableMouse(false) -- pass through mouse to blips below
    lf.text = lf:CreateFontString(nil, "OVERLAY")
    lf.text:SetPoint("CENTER")
    lf:Hide()
    pullLabels[idx] = lf
    return lf
end

local function HideAllLabels()
    for i = 1, activeLabelCount do pullLabels[i]:Hide() end
    activeLabelCount = 0
end

local GetBaseScale -- forward declare; defined in "Zoom to pull" section
local UpdateAllOutlines -- forward declare; defined after UpdateOutlines

------------------------------------------------------------------------
-- Pull outline drawing (convex hull, same approach as MDT PullOutlines)
------------------------------------------------------------------------
local OUTLINE_ALPHA = 0.8

local function hullIsLowerLeft(a, b)
    if a[1] < b[1] then return true end
    if a[1] > b[1] then return false end
    return a[2] < b[2]
end

local function hullIsLeftOf(a, b, c)
    return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) < 0
end

local function ComputeConvexHull(pts)
    if not pts or #pts == 0 then return nil end
    if #pts <= 2 then return pts end
    local ll = 1
    for i = 2, #pts do
        if not pts[i][1] or not pts[ll][1] then return nil end
        if hullIsLowerLeft(pts[i], pts[ll]) then ll = i end
    end
    local hull, final, tries = {}, 1, 0
    repeat
        hull[#hull + 1] = ll
        final = 1
        for j = 2, #pts do
            if ll == final or hullIsLeftOf(pts[ll], pts[final], pts[j]) then final = j end
        end
        ll = final
        tries = tries + 1
    until final == hull[1] or tries > 100
    local out = {}
    for _, idx in ipairs(hull) do out[#out + 1] = pts[idx] end
    return out
end

local function ComputeCentroid(pts)
    local rx, ry = 0, 0
    for _, v in ipairs(pts) do
        if not v[1] or not v[2] then return nil end
        rx, ry = rx + v[1], ry + v[2]
    end
    return rx / #pts, ry / #pts
end

local function ExpandPolygon(poly, nPts, radius)
    local res = {}
    for i = 1, #poly do
        local x, y = poly[i][1], poly[i][2]
        if not x or not y then return nil end
        for j = 1, nPts do
            res[#res + 1] = {
                x + radius * math.cos(2 * math.pi / nPts * j),
                y + radius * math.sin(2 * math.pi / nPts * j),
            }
        end
    end
    return res
end

-- Texture pools for hull outlines
local hullTextures, hullPool = {}, {}
local SQUARE_TEX = "Interface\\AddOns\\MythicDungeonTools\\Textures\\Square_White"
local CIRCLE_TEX = "Interface\\AddOns\\MythicDungeonTools\\Textures\\Circle_White"

local function GetHullTex()
    if #hullPool > 0 then
        local t = table.remove(hullPool)
        t:SetRotation(0)
        t:SetTexCoord(0, 1, 0, 1)
        t:ClearAllPoints()
        return t
    end
    return mapPanel:CreateTexture(nil, "ARTWORK", nil, -5)
end

local function ReleaseOutlines()
    for i = #hullTextures, 1, -1 do
        hullTextures[i]:Hide()
        hullPool[#hullPool + 1] = hullTextures[i]
        hullTextures[i] = nil
    end
end

local function DrawOutlineCircle(x, y, sz, r, g, b, a)
    local t = GetHullTex()
    t:SetTexture(CIRCLE_TEX)
    t:SetVertexColor(r, g, b, a)
    t:SetSize(sz * 1.1, sz * 1.1)
    t:SetPoint("CENTER", tiles4[1], "TOPLEFT", x, y)
    t:Show()
    hullTextures[#hullTextures + 1] = t
end

local function DrawOutlineLine(x1, y1, x2, y2, thickness, r, g, b, a)
    local t = GetHullTex()
    t:SetTexture(SQUARE_TEX)
    t:SetVertexColor(r, g, b, a)
    DrawLine(t, tiles4[1], x1, y1, x2, y2, thickness, 1.1, "TOPLEFT")
    t:Show()
    hullTextures[#hullTextures + 1] = t
    DrawOutlineCircle(x1, y1, thickness * 0.9, r, g, b, a)
end

local UpdateOutlines -- forward declare

UpdateOutlines = function()
    ReleaseOutlines()
    if not H.pulls or not H.currentPullIdx then return end

    local pull = H.pulls[H.currentPullIdx]
    if not pull or not pull.clonePositions or #pull.clonePositions == 0 then return end

    local baseScale = GetBaseScale()
    local zoomScale = mapPanel:GetScale() or 1

    -- Collect vertices in mapPanel coordinates
    local verts = {}
    for _, cp in ipairs(pull.clonePositions) do
        if cp.sublevel == currentSublevel then
            verts[#verts + 1] = { cp.x * baseScale, cp.y * baseScale }
        end
    end
    if #verts == 0 then return end

    -- Pull color (default cyan)
    local cr, cg, cb = 0, 0.8, 1
    if pull.color and pull.color[1] then cr, cg, cb = pull.color[1], pull.color[2], pull.color[3] end

    local thickness = 2 / zoomScale
    local expandR = (BLIP_SIZE / 2 + 5) / zoomScale

    -- Compute hull → expand → recompute for smooth rounded outline
    local hull = ComputeConvexHull(verts)
    if not hull then return end
    local expanded = ExpandPolygon(hull, 20, expandR)
    if not expanded then return end
    hull = ComputeConvexHull(expanded)
    if not hull or #hull < 2 then return end

    -- Draw outline segments with smooth corners
    for i = 1, #hull do
        local a = hull[i]
        local b = (i < #hull) and hull[i + 1] or hull[1]
        DrawOutlineLine(a[1], a[2], b[1], b[2], thickness, cr, cg, cb, OUTLINE_ALPHA)
    end

end

------------------------------------------------------------------------
-- Full route outlines — all pulls at once
------------------------------------------------------------------------
UpdateAllOutlines = function()
    ReleaseOutlines()
    if not H.pulls then return end

    local baseScale = GetBaseScale()
    local zoomScale = mapPanel:GetScale() or 1

    -- Draw non-current pulls first (below), then current pull on top
    for pass = 1, 2 do
        for pullIdx, pull in ipairs(H.pulls) do
            local isCurrent = (pullIdx == H.currentPullIdx)
            if (pass == 1 and not isCurrent) or (pass == 2 and isCurrent) then
                if pull.clonePositions and #pull.clonePositions > 0 then
                    local verts = {}
                    for _, cp in ipairs(pull.clonePositions) do
                        if cp.sublevel == currentSublevel then
                            verts[#verts + 1] = { cp.x * baseScale, cp.y * baseScale }
                        end
                    end
                    if #verts > 0 then
                        -- Current pull: cyan, others: white
                        local cr, cg, cb = 1, 1, 1
                        local alpha, thickness
                        if isCurrent then
                            cr, cg, cb = 0, 0.8, 1
                            alpha = 1.0
                            thickness = 4 / zoomScale
                        elseif pull.completed then
                            alpha = 0.35
                            thickness = 1.5 / zoomScale
                        else
                            alpha = 0.6
                            thickness = 2 / zoomScale
                        end

                        local expandR = (BLIP_SIZE / 2 + 5) / zoomScale

                        local hull = ComputeConvexHull(verts)
                        if hull then
                            local expanded = ExpandPolygon(hull, 20, expandR)
                            if expanded then
                                hull = ComputeConvexHull(expanded)
                                if hull and #hull >= 2 then
                                    for i = 1, #hull do
                                        local a = hull[i]
                                        local b = (i < #hull) and hull[i + 1] or hull[1]
                                        DrawOutlineLine(a[1], a[2], b[1], b[2], thickness, cr, cg, cb, alpha)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
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
local UpdateFullRouteBlips -- forward declare
local UpdateFullRouteLabels -- forward declare

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
                if H.db.mapFullRoute then
                    if UpdateAllOutlines then UpdateAllOutlines() end
                    if UpdateFullRouteBlips then UpdateFullRouteBlips() end
                    if UpdateFullRouteLabels then UpdateFullRouteLabels() end
                else
                    if UpdateBlips then UpdateBlips() end
                end
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
        sublevelButtons[i]:SetPoint("RIGHT", fullRouteBtn, "LEFT", -4 - (#sublevels - i) * 20, 0)
        sublevelButtons[i]:Show()
    end
    UpdateSublevelHighlight()
end

------------------------------------------------------------------------
-- Zoom to pull
------------------------------------------------------------------------
GetBaseScale = function()
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

    local baseZoom = math.min(sw / (diffX * baseScale), sh / (diffY * baseScale))
    local zoomScale = baseZoom + userZoomOffset
    if zoomScale < 1 then zoomScale = 1 end
    if zoomScale > 10 then zoomScale = 10 end
    userZoomOffset = zoomScale - baseZoom

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
-- Zoom for full route mode — show entire map
------------------------------------------------------------------------
local FULL_ROUTE_ZOOM_BORDER = 60 -- slightly wider than single-pull (50) for surrounding context

local function ZoomToFullRoute()
    local sw = scrollFrame:GetWidth()
    local sh = scrollFrame:GetHeight()
    if sw <= 0 or sh <= 0 then return end

    local baseScale = sw / MDT_W
    local panelW = MDT_W * baseScale
    local panelH = MDT_H * baseScale
    mapPanel:SetSize(panelW, panelH)
    ResizeTiles(panelW)

    -- Center on the current pull's bounding box with generous padding
    local pull = H.pulls and H.pulls[H.currentPullIdx]
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
        -- No current pull on this sublevel — show whole map
        mapPanel:SetScale(1)
        scrollFrame:SetHorizontalScroll(0)
        scrollFrame:SetVerticalScroll(0)
        return
    end

    -- Wide padding so you see surrounding pulls too
    minX = minX - FULL_ROUTE_ZOOM_BORDER
    maxX = maxX + FULL_ROUTE_ZOOM_BORDER
    minY = minY - FULL_ROUTE_ZOOM_BORDER
    maxY = maxY + FULL_ROUTE_ZOOM_BORDER

    local diffX = maxX - minX
    local diffY = -(minY - maxY)
    if diffX < 1 then diffX = 1 end
    if diffY < 1 then diffY = 1 end

    local baseZoom = math.min(sw / (diffX * baseScale), sh / (diffY * baseScale))
    local zoomScale = baseZoom + userZoomOffset
    if zoomScale < 0.5 then zoomScale = 0.5 end
    if zoomScale > 10 then zoomScale = 10 end
    userZoomOffset = zoomScale - baseZoom

    mapPanel:SetScale(zoomScale)

    local centerX = (minX + maxX) / 2 * baseScale
    local centerY = -(minY + maxY) / 2 * baseScale

    local scrollH = centerX - sw / (2 * zoomScale) + userPanOffsetX
    local scrollV = centerY - sh / (2 * zoomScale) + userPanOffsetY

    -- Clamp
    local maxScrollH = math.max(0, (panelW * zoomScale - panelW) / zoomScale)
    local maxScrollV = math.max(0, (panelH * zoomScale - panelH) / zoomScale)
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

    -- Identity for click-to-edit (which dungeon enemy/clone this blip represents)
    blip.enemyIdx = cp.enemyIdx
    blip.cloneIdx = cp.cloneIdx
    blip.sublevel = cp.sublevel

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
-- Full route blip rendering — all pulls at once
------------------------------------------------------------------------
UpdateFullRouteBlips = function()
    HideAllBlips()
    if not H.allClonePositions then return end

    local allClones = H.allClonePositions[currentSublevel]
    if not allClones then return end

    -- Build lookup: clone key -> pullIdx (first pull that contains it)
    local cloneKeyToPull = {}
    for pullIdx, pull in ipairs(H.pulls) do
        if pull.clonePositions then
            for _, cp in ipairs(pull.clonePositions) do
                if cp.enemyIdx and cp.cloneIdx then
                    local key = cp.enemyIdx .. "_" .. cp.cloneIdx
                    if not cloneKeyToPull[key] then
                        cloneKeyToPull[key] = pullIdx
                    end
                end
            end
        end
    end

    local baseScale = GetBaseScale()
    local zoomScale = mapPanel:GetScale() or 1
    local idx = 0

    for _, cp in ipairs(allClones) do
        idx = idx + 1
        local blip = GetBlip(idx)
        local sz = BLIP_SIZE / zoomScale
        if cp.isBoss then sz = BLIP_BOSS_SIZE / zoomScale end

        local key = cp.enemyIdx .. "_" .. cp.cloneIdx
        local pIdx = cloneKeyToPull[key]
        if pIdx then
            -- Part of a pull: full brightness portrait
            SetupBlip(blip, cp, baseScale, sz, 0, 0, 0, 0)
            blip:SetFrameLevel(mapPanel:GetFrameLevel() + 3)
        else
            -- Not in any pull: grey out
            SetupBlip(blip, cp, baseScale, sz, 0.3, 0.3, 0.3, 0.6)
            blip:SetFrameLevel(mapPanel:GetFrameLevel() + 1)
        end
        blip.isSurrounding = false
    end

    activeBlipCount = idx
end

------------------------------------------------------------------------
-- Full route pull number labels
------------------------------------------------------------------------
UpdateFullRouteLabels = function()
    HideAllLabels()
    if not H.pulls or #H.pulls == 0 then return end

    local baseScale = GetBaseScale()
    local zoomScale = mapPanel:GetScale() or 1
    local labelIdx = 0

    for pullIdx, pull in ipairs(H.pulls) do
        if pull.clonePositions and #pull.clonePositions > 0 then
            local cx, cy, count = 0, 0, 0
            for _, cp in ipairs(pull.clonePositions) do
                if cp.sublevel == currentSublevel then
                    cx = cx + cp.x
                    cy = cy + cp.y
                    count = count + 1
                end
            end

            if count > 0 then
                cx = cx / count
                cy = cy / count
                labelIdx = labelIdx + 1
                local lf = GetPullLabel(labelIdx)
                local isCurrent = (pullIdx == H.currentPullIdx)
                local isCompleted = pull.completed

                local fontSize
                if isCurrent then
                    fontSize = 18 / zoomScale
                else
                    fontSize = 12 / zoomScale
                end
                fontSize = math.max(fontSize, 6)
                fontSize = math.min(fontSize, 40)
                lf.text:SetFont(FONT, fontSize, "OUTLINE")

                -- Gold text, dimmed for completed
                if isCompleted then
                    lf.text:SetTextColor(0.5, 0.45, 0.2, 0.6)
                elseif isCurrent then
                    lf.text:SetTextColor(1, 0.82, 0, 1)
                else
                    lf.text:SetTextColor(1, 0.82, 0, 0.9)
                end

                lf.text:SetText(tostring(pullIdx))
                lf:SetSize(math.max(fontSize * 2, 16) / zoomScale, math.max(fontSize * 1.4, 12) / zoomScale)
                lf:ClearAllPoints()
                lf:SetPoint("CENTER", tiles4[1], "TOPLEFT", cx * baseScale, cy * baseScale)
                lf:SetAlpha(1)
                lf:Show()
            end
        end
    end

    activeLabelCount = labelIdx
end

------------------------------------------------------------------------
-- Map control buttons (bottom-right overlay on the map area)
------------------------------------------------------------------------
local BTN_SZ = 22
local BTN_GAP = 2

-- Container frame anchored to bottom-right of the map, above resize handle
local controlBar = CreateFrame("Frame", nil, mf)
controlBar:SetSize(3 * BTN_SZ + 2 * BTN_GAP, BTN_SZ)
controlBar:SetPoint("BOTTOMRIGHT", -4, 8)
controlBar:SetFrameLevel(mf:GetFrameLevel() + 8) -- above map, below resize

-- Helper: create a small icon button with highlight
local function MapIconBtn(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BTN_SZ, BTN_SZ)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:GetHighlightTexture():SetAlpha(0.3)
    return b
end

-- Zoom + (green arrow pointing up)
local zoomInBtn = MapIconBtn(controlBar)
zoomInBtn:SetPoint("RIGHT", controlBar, "RIGHT", 0, 0)
local zoomInTex = zoomInBtn:CreateTexture(nil, "ARTWORK")
zoomInTex:SetSize(14, 14)
zoomInTex:SetPoint("CENTER")
zoomInTex:SetAtlas("UI-HUD-Minimap-Zoom-In", false)
zoomInBtn:SetScript("OnClick", function()
    userZoomOffset = userZoomOffset + 0.3
    if UpdateMapPopout then UpdateMapPopout() end
end)
zoomInBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Zoom in", 1, 1, 1)
    GameTooltip:Show()
end)
zoomInBtn:SetScript("OnLeave", GameTooltip_Hide)

-- Zoom - (green arrow pointing down)
local zoomOutBtn = MapIconBtn(controlBar)
zoomOutBtn:SetPoint("RIGHT", zoomInBtn, "LEFT", -BTN_GAP, 0)
local zoomOutTex = zoomOutBtn:CreateTexture(nil, "ARTWORK")
zoomOutTex:SetSize(14, 14)
zoomOutTex:SetPoint("CENTER")
zoomOutTex:SetAtlas("UI-HUD-Minimap-Zoom-Out", false)
zoomOutBtn:SetScript("OnClick", function()
    userZoomOffset = userZoomOffset - 0.3
    if UpdateMapPopout then UpdateMapPopout() end
end)
zoomOutBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Zoom out", 1, 1, 1)
    GameTooltip:Show()
end)
zoomOutBtn:SetScript("OnLeave", GameTooltip_Hide)

-- Reset view (green cross icon)
local resetBtn = MapIconBtn(controlBar)
resetBtn:SetPoint("RIGHT", zoomOutBtn, "LEFT", -BTN_GAP, 0)
local resetTex = resetBtn:CreateTexture(nil, "ARTWORK")
resetTex:SetSize(14, 14)
resetTex:SetPoint("CENTER")
resetTex:SetAtlas("UI-RefreshButton", false)
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
resetBtn:SetScript("OnLeave", GameTooltip_Hide)

------------------------------------------------------------------------
-- Resize handle (corner grip — adjusts both width and height)
------------------------------------------------------------------------
local resizeHandle = CreateFrame("Frame", nil, mf)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0)
resizeHandle:EnableMouse(true)
resizeHandle:SetFrameLevel(mf:GetFrameLevel() + 10)

local resizeIndicator = resizeHandle:CreateTexture(nil, "OVERLAY")
resizeIndicator:SetSize(10, 10)
resizeIndicator:SetPoint("BOTTOMRIGHT", -2, 2)
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
        local es = mf:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        mf.resizeStartX = cx / es
        mf.resizeStartY = cy / es
        mf.resizeStartW = mf:GetWidth()
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
    local es = mf:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local curX = cx / es
    local curY = cy / es
    local deltaX = curX - mf.resizeStartX
    local deltaY = mf.resizeStartY - curY
    local newW = math.max(MIN_SIZE, math.min(mf.resizeStartW + deltaX, MAX_SIZE))
    local newH = math.max(MIN_SIZE, math.min(mf.resizeStartH + deltaY, MAX_SIZE))
    mf:SetSize(newW, newH)
    if H.db.mapFullRoute then
        ZoomToFullRoute()
        pcall(UpdateAllOutlines)
        pcall(UpdateFullRouteBlips)
        pcall(UpdateFullRouteLabels)
    else
        local pull = H.pulls and H.pulls[H.currentPullIdx]
        if pull then
            ZoomToPull(pull)
            UpdateOutlines()
            UpdateBlips()
        end
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
UpdateMapPopout = function(skipZoom)
    if not mf:IsShown() then return end
    if not H.dungeonIdx or not H.pulls or #H.pulls == 0 then
        mf:Hide()
        return
    end

    local pull = H.pulls[H.currentPullIdx]
    if not pull then return end

    local isFullRoute = H.db.mapFullRoute

    -- Reset manual zoom/pan when pull changes (only in single-pull mode)
    if not isFullRoute and lastPullIdx ~= H.currentPullIdx then
        userZoomOffset = 0
        userPanOffsetX = 0
        userPanOffsetY = 0
        lastPullIdx = H.currentPullIdx
    elseif isFullRoute then
        lastPullIdx = H.currentPullIdx
    end

    local sublevel = GetPullSublevel(pull)

    if currentDungeonIdx ~= H.dungeonIdx or currentSublevel ~= sublevel then
        LoadMapTextures(H.dungeonIdx, sublevel)
    end

    if isFullRoute then
        titleText:SetText("Route - Pull " .. H.currentPullIdx .. " / " .. #H.pulls)
    else
        titleText:SetText("Pull " .. H.currentPullIdx .. " / " .. #H.pulls)
    end
    UpdateSurroundBtnColor()
    UpdateFullRouteBtnColor()
    UpdateSublevelButtons(H.dungeonIdx)

    mf:SetMovable(not H.db.locked)
    resizeHandle:EnableMouse(not H.db.locked)
    if H.db.locked then
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0)
    else
        resizeIndicator:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    end

    ApplyMapOpacity(H.db.bgAlpha or 1)

    if isFullRoute then
        -- skipZoom: re-render in place (e.g. after editing a pull) so the
        -- camera doesn't jump when the pull's bounding box changes.
        if not skipZoom then ZoomToFullRoute() end
        -- pcall each step so one failure doesn't block the rest
        local ok, err = pcall(UpdateAllOutlines)
        if not ok then print("|cffff0000MDTHelper map outlines error:|r " .. tostring(err)) end
        ok, err = pcall(UpdateFullRouteBlips)
        if not ok then print("|cffff0000MDTHelper map blips error:|r " .. tostring(err)) end
        ok, err = pcall(UpdateFullRouteLabels)
        if not ok then print("|cffff0000MDTHelper map labels error:|r " .. tostring(err)) end
    else
        HideAllLabels()
        if not skipZoom then ZoomToPull(pull) end
        UpdateOutlines()
        UpdateBlips()
    end
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
        -- Build route from MDT if no pulls loaded (works outside dungeons)
        if not self.pulls or #self.pulls == 0 then
            self:SyncMDTDungeon()
            self:BuildRoute()
        end
        if not self.pulls or #self.pulls == 0 then
            print("|cff00ccffMDTHelper|r: No route loaded in MDT")
            return
        end
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
    -- _editingPull is set while the user is adding/removing mobs on the map so
    -- this deferred refresh re-renders in place instead of re-centering the camera.
    local skipZoom = H._editingPull
    H._editingPull = nil
    if H.db.mapPopout and H.pulls and #H.pulls > 0 then
        if not mf:IsShown() then mf:Show() end
        UpdateMapPopout(skipZoom)
    elseif mf:IsShown() and (not H.db.mapPopout or not H.pulls or #H.pulls == 0) then
        mf:Hide()
    end
end)

------------------------------------------------------------------------
-- Expose update for external callers (e.g. Settings sliders)
------------------------------------------------------------------------
function H:RefreshMapPopout(skipZoom)
    if UpdateMapPopout then UpdateMapPopout(skipZoom) end
end

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
