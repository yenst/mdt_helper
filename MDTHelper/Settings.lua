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
local SPACING = -20

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

local function MakeSlider(label, min, max, step, fmtFunc, getFunc, setFunc, tooltip)
    -- Label
    local lbl = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", lastWidget == version and 0 or 2, SPACING - 4)

    -- Slider
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

local function PctFmt(val)
    return math.floor(val * 100 + 0.5) .. "%"
end

------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------

-- Auto-Import
MakeCheckbox("Auto-Import Leader Route",
    function() return H.db.autoImport end,
    function(v) H.db.autoImport = v end,
    "Automatically import the party leader's MDT route when entering a dungeon")

-- Auto-Advance
MakeCheckbox("Auto-Advance Pulls",
    function() return H.db.autoAdvance end,
    function(v) H.db.autoAdvance = v end,
    "Automatically advance to the next pull based on enemy forces gained")

-- Lock Frame
MakeCheckbox("Lock Frame",
    function() return H.db.locked end,
    function(v)
        H.db.locked = v
        if H.UpdateUI then H:UpdateUI() end
    end,
    "Prevent moving and resizing the route guide frame")

-- Opacity
MakeSlider("Opacity", 0.1, 1.0, 0.05, PctFmt,
    function() return H.db.bgAlpha or 1 end,
    function(v)
        H.db.bgAlpha = v
        if H.ApplyOpacity then H:ApplyOpacity(v) end
    end,
    "Background transparency of the route guide")

-- Pull Accuracy
MakeSlider("Pull Accuracy", 0.5, 1.0, 0.05, PctFmt,
    function() return H.db.pullThreshold or 0.9 end,
    function(v) H.db.pullThreshold = v end,
    "How much of a pull's forces must be killed before auto-advancing")

-- UI Scale
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

-- Spacer before button
local spacer = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
spacer:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", -2, -16)
spacer:SetText("")
lastWidget = spacer

-- Reset Position & Size button
local resetBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetBtn:SetSize(180, 24)
resetBtn:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -4)
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
