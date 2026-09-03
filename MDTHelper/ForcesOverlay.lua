local H = MDTHelper

local issecretvalue = issecretvalue or function() return false end

------------------------------------------------------------------------
-- Get raw forces values for a unit token (12.0.5+ API)
-- Returns rawValue, rawPercent, rawPercentText or nil. Values may be SECRET — do NOT
-- call tonumber/tostring on them. Use SetFormattedText for display.
------------------------------------------------------------------------
local function GetRawForces(unitToken)
    if not unitToken then return nil end
    if not C_ScenarioInfo or not C_ScenarioInfo.GetUnitCriteriaProgressValues then return nil end
    local ok, value, percent, percentText = pcall(C_ScenarioInfo.GetUnitCriteriaProgressValues, unitToken)
    if not ok then return nil end
    return value, percent, percentText
end

-- Non-secret version for calculations (returns nil if values are secret)
function H:GetUnitForcesInfo(unitToken)
    local value, percent = GetRawForces(unitToken)
    if issecretvalue(value) or issecretvalue(percent) then return nil end
    if value == nil or percent == nil then return nil end
    value = tonumber(value) or 0
    percent = tonumber(percent) or 0
    if value <= 0 and percent <= 0 then return nil end
    -- Since 12.0.7 percentValue uses the [0, 1] range. Keep this helper's
    -- historical percentage-point return value for any internal callers.
    if percent <= 1 then percent = percent * 100 end
    return value, percent
end

------------------------------------------------------------------------
-- Safe GUID (returns nil if secret)
------------------------------------------------------------------------
local function SafeUnitGUID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if issecretvalue(guid) then return nil end
    if type(guid) == "string" then return guid end
    return nil
end

------------------------------------------------------------------------
-- Runtime state
------------------------------------------------------------------------
H.livePullPercent = 0
H.livePullValue = 0

------------------------------------------------------------------------
-- Nameplate overlay using SetFormattedText (works with secret values)
------------------------------------------------------------------------
local overlays = {} -- [nameplate frame] = FontString

local function ShouldShowForces()
    if not H.db or not H.db.forcesOverlay then return false end
    if H.db.forcesTestMode then return true end
    return H.activeDungeon
end

local function GetOrCreateOverlay(nameplate)
    local uf = nameplate.unitFrame or nameplate.UnitFrame
    local parent = uf or nameplate
    local fs = overlays[nameplate]
    if not fs or fs:GetParent() ~= parent then
        if fs then fs:Hide() end
        fs = parent:CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 7)
        fs:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        fs:SetTextColor(0.2, 1.0, 0.6, 1.0)
        overlays[nameplate] = fs
    end
    return fs, parent
end

local function ShowOverlay(nameplate, unitToken)
    local _, rawPct, rawPctText = GetRawForces(unitToken)
    if not issecretvalue(rawPct) and rawPct == nil then return false end

    local fs, parent = GetOrCreateOverlay(nameplate)
    fs:ClearAllPoints()
    local uf = nameplate.unitFrame or nameplate.UnitFrame
    local anchor = (uf and uf.healthBar) or nameplate
    local pos = H.db and H.db.forcesPosition or "RIGHT"
    if pos == "BOTTOM" then
        fs:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    elseif pos == "LEFT" then
        fs:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    elseif pos == "RIGHT" then
        fs:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
    else -- "TOP" (default)
        fs:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    end

    -- SetFormattedText handles secret values internally. Blizzard's formatted
    -- return also accounts for percentValue changing to [0, 1] in 12.0.7.
    local ok
    if issecretvalue(rawPctText) or rawPctText ~= nil then
        ok = pcall(fs.SetFormattedText, fs, "%s", rawPctText)
    else
        ok = pcall(fs.SetFormattedText, fs, "%.1f%%", rawPct)
    end
    if ok then
        fs:Show()
        return true
    end
    fs:Hide()
    return false
end

local function HideOverlay(nameplate)
    if overlays[nameplate] then overlays[nameplate]:Hide() end
end

local function OnNameplateAdded(unitToken)
    if not ShouldShowForces() then return end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not nameplate then return end
    if not ShowOverlay(nameplate, unitToken) then
        HideOverlay(nameplate)
    end
end

local function OnNameplateRemoved(unitToken)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if nameplate then HideOverlay(nameplate) end
end

local function RefreshAllNameplates()
    if not ShouldShowForces() then return end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            OnNameplateAdded(unit)
        end
    end
end

------------------------------------------------------------------------
-- Tooltip: show forces % on mouseover
------------------------------------------------------------------------
local function InitTooltip()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not H.db or not H.db.forcesTooltip then return end
        if not H.activeDungeon then return end
        local _, rawPct, rawPctText = GetRawForces("mouseover")
        if not issecretvalue(rawPct) and rawPct == nil then return end
        tooltip:AddLine(" ")
        local n = tooltip:NumLines()
        local textLeft = _G[tooltip:GetName() .. "TextLeft" .. n]
        if textLeft then
            if issecretvalue(rawPctText) or rawPctText ~= nil then
                pcall(textLeft.SetFormattedText, textLeft, "|cFF33FF99Forces:|r %s", rawPctText)
            else
                pcall(textLeft.SetFormattedText, textLeft, "|cFF33FF99Forces:|r %.2f%%", rawPct)
            end
            tooltip:Show()
        end
    end)
end

------------------------------------------------------------------------
-- Pull forces scan — uses scenario criteria (not per-mob secret values)
-- Per-mob values are secret so we can't sum them in Lua.
-- Instead, estimate pull forces from scenario delta during combat.
------------------------------------------------------------------------
function H:ScanPullForces()
    -- Use the scenario criteria delta approach from Core.lua's combat tracking
    -- This is already handled by combatForcesSnapshot in Core.lua
    -- Return the delta since combat started
    if not self.activeDungeon then return 0, 0 end
    local gained = self.totalForcesGained or 0
    local snapshot = self.combatForcesSnapshot or 0
    local needed = self.totalForcesRequired or 0
    local delta = math.max(0, gained - snapshot)
    local deltaPct = needed > 0 and (delta / needed * 100) or 0
    return deltaPct, delta
end

------------------------------------------------------------------------
-- Debug: /mdth forcesrefresh
------------------------------------------------------------------------
function H:ForcesRefresh()
    print("|cff00ccffMDTHelper|r: --- Forces Refresh ---")
    print("  ShouldShow: " .. tostring(ShouldShowForces()))
    RefreshAllNameplates()
    local shown = 0
    for _, fs in pairs(overlays) do
        if fs:IsShown() then shown = shown + 1 end
    end
    print("  Overlays shown: " .. shown)
    print("  --- End ---")
end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local ef = CreateFrame("Frame")
    ef:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ef:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ef:RegisterEvent("PLAYER_TARGET_CHANGED")
    ef:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

    ef:SetScript("OnEvent", function(_, event, ...)
        if event == "NAME_PLATE_UNIT_ADDED" then
            OnNameplateAdded(...)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            OnNameplateRemoved(...)
        elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
            if ShouldShowForces() then
                RefreshAllNameplates()
            end
        end
    end)

    InitTooltip()

    -- Periodic refresh for overlays
    C_Timer.NewTicker(1.0, function()
        if ShouldShowForces() then
            RefreshAllNameplates()
        end
    end)

    -- Live pull forces during combat (scenario delta approach)
    C_Timer.NewTicker(0.5, function()
        if not H.activeDungeon then return end
        if InCombatLockdown() then
            local pct, val = H:ScanPullForces()
            H.livePullPercent = pct
            H.livePullValue = val
            if H.UpdatePullForcesDisplay then H:UpdatePullForcesDisplay() end
        elseif H.livePullPercent > 0 then
            H.livePullPercent = 0
            H.livePullValue = 0
            if H.UpdateUI then H:UpdateUI() end
        end
    end)
end)
