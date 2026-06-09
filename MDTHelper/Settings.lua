local H = MDTHelper

------------------------------------------------------------------------
-- WoW Settings panel for MDTHelper
------------------------------------------------------------------------
local optionsFrame = CreateFrame("Frame")
optionsFrame:SetSize(400, 400)
optionsFrame:Hide()

-- Header
local header = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
header:SetPoint("TOPLEFT", 16, -16)
header:SetText("MDTHelper")

local version = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
version:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
version:SetText("Live route guide for MDT dungeon routes")

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local lastWidget = version
local SPACING = -2

local function MakeCheckbox(label, getFunc, setFunc, tooltip)
    local cb = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", lastWidget == version and -2 or 0, SPACING)
    cb:SetScript("OnShow", function(self) self:SetChecked(getFunc()) end)
    cb:SetScript("OnClick", function(self) setFunc(self:GetChecked()) end)

    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    lastWidget = cb
    return cb
end

-- Two checkboxes on one row (left + right columns)
local function MakeCheckboxPair(lbl1, get1, set1, tip1, lbl2, get2, set2, tip2)
    local cb1 = MakeCheckbox(lbl1, get1, set1, tip1)

    local cb2 = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    cb2:SetPoint("LEFT", cb1, "LEFT", 190, 0)
    cb2:SetScript("OnShow", function(self) self:SetChecked(get2()) end)
    cb2:SetScript("OnClick", function(self) set2(self:GetChecked()) end)

    local text2 = cb2:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text2:SetPoint("LEFT", cb2, "RIGHT", 4, 1)
    text2:SetText(lbl2)

    if tip2 then
        cb2:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(lbl2, 1, 1, 1)
            GameTooltip:AddLine(tip2, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb1, cb2
end

local function MakeSlider(label, min, max, step, fmtFunc, getFunc, setFunc, tooltip)
    local lbl = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", lastWidget == version and 0 or 2, -6)

    local slider = CreateFrame("Slider", nil, optionsFrame, "OptionsSliderTemplate")
    slider:SetSize(260, 17)
    slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider.Low:SetText(fmtFunc(min))
    slider.High:SetText(fmtFunc(max))
    slider.Text:SetText("")

    local function UpdateLabel(val)
        lbl:SetText(label .. ": " .. fmtFunc(val))
    end

    slider:SetScript("OnShow", function(self)
        local val = getFunc()
        self:SetValue(val)
        UpdateLabel(val)
    end)
    slider:SetScript("OnValueChanged", function(self, value)
        setFunc(value)
        UpdateLabel(value)
    end)

    if tooltip then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    lastWidget = slider
    return slider, lbl
end

local function MakeDropdown(label, choices, getFunc, setFunc, tooltip)
    local container = CreateFrame("Frame", nil, optionsFrame)
    container:SetSize(200, 28)
    container:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", lastWidget == version and 0 or 2, -6)

    local lbl = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetText(label .. ":")

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(90, 20)
    btn:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local btnText = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER")

    local function UpdateText()
        local cur = getFunc()
        for _, c in ipairs(choices) do
            if c.value == cur then btnText:SetText(c.label); return end
        end
        btnText:SetText(cur or "?")
    end

    btn:SetScript("OnClick", function(self)
        local cur = getFunc()
        for i, c in ipairs(choices) do
            if c.value == cur then
                local next = choices[(i % #choices) + 1]
                setFunc(next.value)
                UpdateText()
                return
            end
        end
        setFunc(choices[1].value)
        UpdateText()
    end)

    btn:SetScript("OnShow", function() UpdateText() end)

    if tooltip then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    lastWidget = container
    return container
end

local function PctFmt(val)
    return math.floor(val * 100 + 0.5) .. "%"
end

------------------------------------------------------------------------
-- Controls (checkboxes in two columns to save space)
------------------------------------------------------------------------

MakeCheckboxPair(
    "Auto-Import Route",
    function() return H.db.autoImport end,
    function(v) H.db.autoImport = v end,
    "Automatically import the party leader's MDT route when entering a dungeon",
    "Auto-Advance Pulls",
    function() return H.db.autoAdvance end,
    function(v) H.db.autoAdvance = v end,
    "Automatically advance to the next pull based on enemy forces gained")

MakeCheckboxPair(
    "Lock Frame",
    function() return H.db.locked end,
    function(v)
        H.db.locked = v
        if H.UpdateUI then H:UpdateUI() end
    end,
    "Prevent moving and resizing the route guide frame",
    "Full Route on Map",
    function() return H.db.mapFullRoute end,
    function(v)
        H.db.mapFullRoute = v
        if H.RefreshMapPopout then H:RefreshMapPopout() end
    end,
    "Show all pulls on the map instead of just the current one")

MakeCheckbox("Edit Pulls on Map",
    function() return H.db.mapEditPulls end,
    function(v) H.db.mapEditPulls = v end,
    "Left-click a mob on the map popout to add it to the current pull, right-click to remove it. Social-aggro linked mobs are included automatically.")

MakeCheckboxPair(
    "Forces on Nameplates",
    function() return H.db.forcesOverlay end,
    function(v) H.db.forcesOverlay = v end,
    "Show forces percentage on enemy nameplates in M+ dungeons",
    "Forces in Tooltip",
    function() return H.db.forcesTooltip end,
    function(v) H.db.forcesTooltip = v end,
    "Show forces percentage in enemy tooltips in M+ dungeons")

MakeDropdown("Forces Position", {
    { label = "Top",    value = "TOP" },
    { label = "Bottom", value = "BOTTOM" },
    { label = "Left",   value = "LEFT" },
    { label = "Right",  value = "RIGHT" },
}, function() return H.db.forcesPosition or "RIGHT" end,
   function(v) H.db.forcesPosition = v end,
   "Where to show the forces % on nameplates (click to cycle)")

MakeCheckbox("Efficiency Tracker",
    function() return H.db.efficiencyTracker end,
    function(v) H.db.efficiencyTracker = v end,
    "Show ahead/behind indicator comparing actual vs planned forces")

------------------------------------------------------------------------
-- Sliders
------------------------------------------------------------------------

MakeSlider("Opacity", 0.1, 1.0, 0.05, PctFmt,
    function() return H.db.bgAlpha or 1 end,
    function(v)
        H.db.bgAlpha = v
        if H.ApplyOpacity then H:ApplyOpacity(v) end
    end,
    "Background transparency of the route guide")

MakeSlider("Pull Accuracy", 0.5, 1.0, 0.05, PctFmt,
    function() return H.db.pullThreshold or 0.9 end,
    function(v) H.db.pullThreshold = v end,
    "How much of a pull's forces must be killed before auto-advancing")

MakeSlider("UI Scale", 0.5, 2.0, 0.05, PctFmt,
    function() return H.db.uiScale or 1 end,
    function(v)
        H.db.uiScale = v
        local guide = _G["MDTHelperGuide"]
        if guide then
            guide:SetScale(v)
            local point, _, _, ox, oy = guide:GetPoint()
            if ox and oy and point == "TOPLEFT" then
                local maxX = UIParent:GetWidth() / v - 240
                local minY = -(UIParent:GetHeight() / v - 24)
                local newX = math.max(0, math.min(ox, maxX))
                local newY = math.max(minY, math.min(oy, 0))
                if newX ~= ox or newY ~= oy then
                    guide:ClearAllPoints()
                    guide:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newX, newY)
                    H.db.framePoint = { "TOPLEFT", "TOPLEFT", newX, newY }
                end
            end
        end
    end,
    "Scale of the route guide frame")

local function PxFmt(val) return math.floor(val + 0.5) .. "px" end

MakeSlider("Map Width", 150, 800, 10, PxFmt,
    function()
        return H.db.mapPopoutSize and H.db.mapPopoutSize[1] or 300
    end,
    function(v)
        if not H.db.mapPopoutSize then H.db.mapPopoutSize = { 300, 300 } end
        H.db.mapPopoutSize[1] = v
        local mf = _G["MDTHelperMapPopout"]
        if mf then mf:SetWidth(v) end
        if H.RefreshMapPopout then H:RefreshMapPopout() end
    end,
    "Width of the map popout window")

MakeSlider("Map Height", 150, 800, 10, PxFmt,
    function()
        return H.db.mapPopoutSize and H.db.mapPopoutSize[2] or 300
    end,
    function(v)
        if not H.db.mapPopoutSize then H.db.mapPopoutSize = { 300, 300 } end
        H.db.mapPopoutSize[2] = v
        local mf = _G["MDTHelperMapPopout"]
        if mf then mf:SetHeight(v) end
        if H.RefreshMapPopout then H:RefreshMapPopout() end
    end,
    "Height of the map popout window")

------------------------------------------------------------------------
-- Reset button
------------------------------------------------------------------------
local resetBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetBtn:SetSize(180, 24)
resetBtn:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", -2, -10)
resetBtn:SetText("Reset Position & Size")
resetBtn:SetScript("OnClick", function()
    H.db.framePoint = nil
    H.db.frameHeight = nil
    H.db.uiScale = 1
    local guide = _G["MDTHelperGuide"]
    if guide then
        guide:SetScale(1)
        guide:ClearAllPoints()
        guide:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() - 260, -200)
    end
    if H.UpdateUI then H:UpdateUI() end
    print("|cff00ccffMDTHelper|r: Position and size reset to default")
end)

------------------------------------------------------------------------
-- Required callbacks
------------------------------------------------------------------------
optionsFrame.OnCommit = function() end
optionsFrame.OnDefault = function() end
optionsFrame.OnRefresh = function() end

------------------------------------------------------------------------
-- Register with WoW Settings
------------------------------------------------------------------------
H.settingsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, "MDTHelper")
Settings.RegisterAddOnCategory(H.settingsCategory)
