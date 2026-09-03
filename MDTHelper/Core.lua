local AddonName, NS = ...

-- Keybinding display names (must be globals for Blizzard Key Bindings UI)
BINDING_HEADER_MDTHELPER = "MDT Helper"
BINDING_NAME_MDTHELPER_NEXT_PULL = "Next Pull"
BINDING_NAME_MDTHELPER_PREV_PULL = "Previous Pull"

local H = NS

-- MDT 6.2 split its route UI/data into a load-on-demand addon and removed the
-- old global `MDT` table. Keep the legacy path, but use the public API and the
-- rendered MDT frame as a compatibility bridge on newer versions.
local function GetLegacyMDT()
    return rawget(_G, "MDT")
end

function H:GetMDTAPI()
    return GetLegacyMDT() or rawget(_G, "MythicDungeonToolsAPI")
end

function H:GetMDTDB()
    local api = self:GetMDTAPI()
    if not api or not api.GetDB then return nil end
    local ok, db = pcall(api.GetDB, api)
    return ok and db or nil
end

function H:GetCurrentMDTPreset()
    local legacy = GetLegacyMDT()
    if legacy and legacy.GetCurrentPreset then
        local ok, preset = pcall(legacy.GetCurrentPreset, legacy)
        return ok and preset or nil
    end

    local db = self:GetMDTDB()
    if not db or not db.currentDungeonIdx or not db.currentPreset or not db.presets then return nil end
    local dungeonPresets = db.presets[db.currentDungeonIdx]
    local presetIdx = db.currentPreset[db.currentDungeonIdx]
    return dungeonPresets and presetIdx and dungeonPresets[presetIdx] or nil
end

function H:IsModernMDT()
    return not GetLegacyMDT() and rawget(_G, "MythicDungeonToolsAPI") ~= nil
end

local MDT2_PREFIX = "!~MDT2~"
local UID_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"

-- MDT 6.2 keeps its serializer in the private, load-on-demand UI addon. The
-- wire format itself uses public WoW APIs, so mirror it here for sharing and
-- copying without reaching into MDT's private addon table.
function H:EncodeMDTPreset(preset, fromChat)
    local legacy = GetLegacyMDT()
    if legacy and legacy.TableToString then
        local ok, encoded = pcall(legacy.TableToString, legacy, preset, fromChat, 5)
        return ok and encoded or nil
    end

    if type(preset) ~= "table" or not C_EncodingUtil or not Enum
        or not Enum.CompressionMethod or not Enum.CompressionMethod.Deflate then
        return nil
    end
    local ok, encoded = pcall(function()
        local serialized = C_EncodingUtil.SerializeCBOR(preset)
        local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate)
        return MDT2_PREFIX .. C_EncodingUtil.EncodeBase64(compressed)
    end)
    return ok and encoded or nil
end

function H:DecodeMDTPreset(encoded)
    local legacy = GetLegacyMDT()
    if legacy and legacy.StringToTable then
        local ok, preset = pcall(legacy.StringToTable, legacy, encoded, false)
        return ok and type(preset) == "table" and preset or nil
    end

    if type(encoded) ~= "string" or encoded:sub(1, #MDT2_PREFIX) ~= MDT2_PREFIX
        or not C_EncodingUtil or not Enum or not Enum.CompressionMethod then
        return nil
    end
    local ok, preset = pcall(function()
        local decoded = C_EncodingUtil.DecodeBase64(encoded:sub(#MDT2_PREFIX + 1))
        if not decoded then return nil end
        local decompressed = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
        if not decompressed then return nil end
        return C_EncodingUtil.DeserializeCBOR(decompressed)
    end)
    return ok and type(preset) == "table" and preset or nil
end

function H:EnsureMDTPresetUID(preset)
    if type(preset) ~= "table" or preset.uid then return end
    local legacy = GetLegacyMDT()
    if legacy and legacy.SetUniqueID then
        pcall(legacy.SetUniqueID, legacy, preset)
        return
    end

    local db = self:GetMDTDB()
    for _ = 1, 100 do
        local chars = {}
        for i = 1, 11 do
            local idx = math.random(1, #UID_CHARACTERS)
            chars[i] = UID_CHARACTERS:sub(idx, idx)
        end
        local candidate = table.concat(chars)
        local inUse = false
        if db and db.presets then
            for _, dungeonPresets in pairs(db.presets) do
                for _, existing in pairs(dungeonPresets) do
                    if type(existing) == "table" and existing.uid == candidate then
                        inUse = true
                        break
                    end
                end
                if inUse then break end
            end
        end
        if not inUse then
            preset.uid = candidate
            return
        end
    end
end

local function NormalizeDungeonName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name:lower() or nil
end

-- MDT's modern public API does not expose its zone-to-dungeon table. Resolve
-- the current instance by matching Blizzard's localized instance/challenge
-- name to MDT's localized dungeon names instead.
function H:GetModernInstanceDungeonIdx()
    local api = self:GetMDTAPI()
    if not api or not api.GetDungeonName then return nil end

    local wantedNames = {}
    local instanceName, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        local normalized = NormalizeDungeonName(instanceName)
        if normalized then wantedNames[normalized] = true end
    end

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetMapUIInfo then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and mapID and (not issecretvalue or not issecretvalue(mapID)) then
            local infoOK, challengeName = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if infoOK then
                local normalized = NormalizeDungeonName(challengeName)
                if normalized then wantedNames[normalized] = true end
            end
        end
    end

    if not next(wantedNames) then return nil end
    for idx = 1, 200 do
        local ok, name = pcall(api.GetDungeonName, api, idx)
        if ok and wantedNames[NormalizeDungeonName(name)] then return idx end
    end
    return nil
end

local function ModernRouteFrameReady(expectedDungeonIdx)
    local frame = rawget(_G, "MDTFrame")
    if not frame or not frame.sidePanel or not frame.sidePanel.newPullButtons then return false end

    local db = H:GetMDTDB()
    local preset = H:GetCurrentMDTPreset()
    local pulls = preset and preset.value and preset.value.pulls
    if not db or not pulls then return false end
    if expectedDungeonIdx and db.currentDungeonIdx ~= expectedDungeonIdx then return false end

    for pullIdx, pull in ipairs(pulls) do
        local hasEnemies = false
        for enemyIdx, clones in pairs(pull) do
            if enemyIdx ~= "color" and type(clones) == "table" and next(clones) then
                hasEnemies = true
                break
            end
        end
        local button = frame.sidePanel.newPullButtons[pullIdx]
        if hasEnemies and (not button or not button.enemyPortraits) then return false end
        if hasEnemies then
            local hasPortraitData = false
            for _, portrait in pairs(button.enemyPortraits) do
                if portrait.enemyData and (not portrait.IsShown or portrait:IsShown()) then
                    hasPortraitData = true
                    break
                end
            end
            if not hasPortraitData then return false end
        end
    end
    return true
end

-- MDT 6.2's public API cannot select a dungeon directly. Its visible dungeon
-- buttons do have public frame scripts, so use the same click path a player
-- would use. This also bypasses MDT:CheckCurrentZone intentionally doing
-- nothing while C_ChallengeMode.IsChallengeModeActive() is true.
local function SelectModernDungeon(dungeonIdx)
    if not dungeonIdx then return true, false end
    local db = H:GetMDTDB()
    if not db then return false, false end

    local mdtFrame = rawget(_G, "MDTFrame")
    if not mdtFrame then
        local changed = db.currentDungeonIdx ~= dungeonIdx
        db.currentDungeonIdx = dungeonIdx
        return true, changed
    end

    for idx = 1, 40 do
        local button = rawget(_G, "MDTDungeonButton" .. idx)
        if button and button.dungeonIdx == dungeonIdx then
            if db.currentDungeonIdx == dungeonIdx then return true, false end
            local onClick = button.GetScript and button:GetScript("OnClick")
            if not onClick then return false, false end
            local ok = pcall(onClick, button, "LeftButton")
            return ok and db.currentDungeonIdx == dungeonIdx, ok
        end
    end

    return db.currentDungeonIdx == dungeonIdx, false
end

function H:CancelModernMDTLoad()
    if not self._modernMDTLoading then return end
    self._modernMDTLoadGeneration = (self._modernMDTLoadGeneration or 0) + 1
    self._modernMDTLoading = nil
    self._modernExpectedDungeonIdx = nil
    local mdtFrame = rawget(_G, "MDTFrame")
    if mdtFrame then
        if mdtFrame:IsShown() then mdtFrame:Hide() end
        mdtFrame:SetAlpha(1)
    end
end

function H:EnsureModernMDTReady(forceRefresh, expectedDungeonIdx)
    if not self:IsModernMDT() then return true end
    if self.SeedBundledRoutes then self:SeedBundledRoutes() end
    if expectedDungeonIdx ~= self._modernExpectedDungeonIdx then
        self._modernExpectedDungeonIdx = expectedDungeonIdx
        self._modernMDTSettlePolls = 0
    end

    local selected, changed = SelectModernDungeon(expectedDungeonIdx)
    if selected and forceRefresh and self.SelectBundledRoute then
        local _, presetChanged = self:SelectBundledRoute(expectedDungeonIdx)
        changed = changed or presetChanged
    end
    if changed then self._modernMDTSettlePolls = 0 end
    if selected and ModernRouteFrameReady(expectedDungeonIdx) and not forceRefresh then
        if self.SeedBundledRoutes then self:SeedBundledRoutes() end
        self:HookModernPresetChanges()
        return true
    end
    if self._modernMDTLoading then return false end

    local api = self:GetMDTAPI()
    if not api or not api.ShowInterface then return false end
    self._modernMDTLoading = true
    self._modernMDTPollCount = 0
    self._modernMDTSettlePolls = 0
    self._modernMDTLoadGeneration = (self._modernMDTLoadGeneration or 0) + 1
    local loadGeneration = self._modernMDTLoadGeneration
    local existingFrame = rawget(_G, "MDTFrame")
    if existingFrame then existingFrame:SetAlpha(0) end

    -- MDT only constructs route/enemy data after its load-on-demand UI starts.
    -- Start it once, keep the window transparent, then close it when our data is
    -- ready so entering a dungeon does not leave the planner open.
    pcall(api.ShowInterface, api, true)

    local function PollMDT()
        if self._modernMDTLoadGeneration ~= loadGeneration then return end
        self._modernMDTPollCount = self._modernMDTPollCount + 1
        local mdtFrame = rawget(_G, "MDTFrame")
        if mdtFrame and not self._modernMDTHideHooked then
            self._modernMDTHideHooked = true
            mdtFrame:SetAlpha(0)
            mdtFrame:HookScript("OnShow", function(frame)
                if H._modernMDTLoading then
                    C_Timer.After(0, function()
                        if H._modernMDTLoading and frame:IsShown() then frame:Hide() end
                    end)
                end
            end)
            mdtFrame:HookScript("OnHide", function()
                if not H._modernMDTLoading and H.activeDungeon then
                    C_Timer.After(0.2, function()
                        if H.activeDungeon then H:RebuildPullData() end
                    end)
                end
            end)
        end
        self:HookModernPresetChanges()
        local spinner = rawget(_G, "MDTInitSpinner")
        if spinner and self._modernMDTLoading then spinner:Hide() end

        local dungeonSelected, selectionChanged = SelectModernDungeon(self._modernExpectedDungeonIdx)
        if dungeonSelected and forceRefresh and self.SelectBundledRoute then
            local _, presetChanged = self:SelectBundledRoute(self._modernExpectedDungeonIdx)
            selectionChanged = selectionChanged or presetChanged
        end
        if selectionChanged then
            self._modernMDTSettlePolls = 0
        elseif dungeonSelected then
            self._modernMDTSettlePolls = self._modernMDTSettlePolls + 1
        end

        -- Dungeon selection redraws MDT asynchronously. Require a short stable
        -- period before reading its rendered pull buttons and map children.
        local minimumSettlePolls = forceRefresh and 10 or 1
        if dungeonSelected and self._modernMDTSettlePolls >= minimumSettlePolls
            and ModernRouteFrameReady(self._modernExpectedDungeonIdx) then
            if mdtFrame then
                if mdtFrame:IsShown() then mdtFrame:Hide() end
                mdtFrame:SetAlpha(1)
            end
            self._modernMDTLoading = nil
            if self.SeedBundledRoutes then self:SeedBundledRoutes() end
            if self.activeDungeon then self:BuildRoute() end
            return
        end

        if self._modernMDTPollCount < 100 then
            C_Timer.After(0.1, PollMDT)
        else
            self._modernMDTLoading = nil
            if mdtFrame then mdtFrame:SetAlpha(1) end
        end
    end
    C_Timer.After(0, PollMDT)
    return false
end

-- Localize enemy name via MDT's translation table
local function LocalName(name)
    if not name then return "Unknown" end
    local legacy = GetLegacyMDT()
    local L = legacy and legacy.L
    return L and L[name] or name
end

H.pulls = {}
H.npcIdToEnemyInfo = {}
H.npcKills = {}
H.currentPullIdx = 1
H.totalForcesGained = 0
H.totalForcesRequired = 0
H.activeDungeon = false
H.completedCriteria = {}
H.keyCompleted = false
H.db = { enabled = true, locked = false, minimized = false, bgAlpha = 1, autoImport = true, autoAdvance = true, frameHeight = nil, pullThreshold = 0.9, mapEditPulls = true }
H.inCombat = false
H.combatForcesSnapshot = 0
H.livePullPercent = 0
H.livePullValue = 0

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AddonName then
        MDTHelperDB = MDTHelperDB or {}
        if MDTHelperDB.enabled == nil then MDTHelperDB.enabled = true end
        if MDTHelperDB.locked == nil then MDTHelperDB.locked = false end
        if MDTHelperDB.minimized == nil then MDTHelperDB.minimized = false end
        if MDTHelperDB.bgAlpha == nil then MDTHelperDB.bgAlpha = 1 end
        if MDTHelperDB.autoImport == nil then MDTHelperDB.autoImport = true end
        if MDTHelperDB.autoAdvance == nil then MDTHelperDB.autoAdvance = true end
        if MDTHelperDB.pullThreshold == nil then MDTHelperDB.pullThreshold = 0.9 end
        if MDTHelperDB.mapPopout == nil then MDTHelperDB.mapPopout = true end
        if MDTHelperDB.mapShowSurround == nil then MDTHelperDB.mapShowSurround = true end
        if MDTHelperDB.mapFullRoute == nil then MDTHelperDB.mapFullRoute = false end
        if MDTHelperDB.mapEditPulls == nil then MDTHelperDB.mapEditPulls = true end
        if MDTHelperDB.forcesOverlay == nil then MDTHelperDB.forcesOverlay = true end
        if MDTHelperDB.forcesPosition == nil then MDTHelperDB.forcesPosition = "RIGHT" end
        if MDTHelperDB.forcesTooltip == nil then MDTHelperDB.forcesTooltip = true end
        if MDTHelperDB.efficiencyTracker == nil then MDTHelperDB.efficiencyTracker = true end
        -- frameHeight: nil means auto-size (default behavior)
        H.db = MDTHelperDB

        H:HookMDTComm()
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        H:HookMDTComm()
        H:CheckInstance()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        H:OnKeyCompleted()
    end
end)

------------------------------------------------------------------------
-- Combat tracking — detect incomplete pulls
------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

combatFrame:SetScript("OnEvent", function(_, event)
    if not H.activeDungeon then return end
    if not H.db.autoAdvance then return end

    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: snapshot current forces
        H.inCombat = true
        H.combatForcesSnapshot = H.totalForcesGained
    elseif event == "PLAYER_REGEN_ENABLED" then
        H.inCombat = false
        local pull = H.pulls[H.currentPullIdx]
        if pull and not pull.completed and pull.totalForces > 0 then
            local forcesGainedThisCombat = H.totalForcesGained - H.combatForcesSnapshot
            local threshold = H.db.pullThreshold or 0.8
            if forcesGainedThisCombat > 0 and forcesGainedThisCombat < pull.totalForces * threshold then
                pull.incomplete = true
                if H.UpdateUI then H:UpdateUI() end
            end
        end
    end
end)

------------------------------------------------------------------------
-- Scenario criteria — forces progress only
------------------------------------------------------------------------
local scenFrame = CreateFrame("Frame")
scenFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
local prevForces = 0

scenFrame:SetScript("OnEvent", function()
    if not H.activeDungeon then return end
    if H.keyCompleted then return end
    local ok, numCriteria = pcall(function() return select(3, C_Scenario.GetStepInfo()) end)
    if not ok or not numCriteria then return end
    local bossKilled = false
    for ci = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, ci)
        if ok2 and info then
            if info.isWeightedProgress then
                local qty = tonumber(info.quantityString:match("%d+"))
                if qty then
                    H.totalForcesGained = qty
                    H.totalForcesRequired = info.totalQuantity or H.totalForcesRequired
                    H:CheckAutoAdvance(prevForces, qty)
                    prevForces = qty
                end
            elseif info.completed and not H.completedCriteria[ci] then
                -- A boss criterion just completed
                H.completedCriteria[ci] = true
                bossKilled = true
            end
        end
    end
    if bossKilled then
        H:CheckBossAdvance()
    end
    if H.UpdateUI then H:UpdateUI() end
end)

------------------------------------------------------------------------
-- Key completed — freeze state, mark all pulls done
------------------------------------------------------------------------
function H:OnKeyCompleted()
    self.keyCompleted = true
    self.totalForcesGained = self.totalForcesRequired
    for _, pull in ipairs(self.pulls) do
        pull.completed = true
    end
    self.currentPullIdx = #self.pulls
    if self.UpdateUI then self:UpdateUI() end
end

------------------------------------------------------------------------
-- Sync MDT to the dungeon the player is currently in
------------------------------------------------------------------------
function H:SyncMDTDungeon(forceRefresh)
    local legacy = GetLegacyMDT()
    if not legacy then
        local dungeonIdx = self.db.dungeonOverride or self:GetModernInstanceDungeonIdx()
        return self:EnsureModernMDTReady(forceRefresh, dungeonIdx)
    end

    if not legacy.GetDB then return end

    local db = legacy:GetDB()
    if not db then return end
    if self.SeedBundledRoutes then self:SeedBundledRoutes() end

    local dungeonIdx
    if self.db.dungeonOverride then
        -- Validate the override still exists in MDT
        if legacy.dungeonEnemies and legacy.dungeonEnemies[self.db.dungeonOverride] then
            dungeonIdx = self.db.dungeonOverride
        else
            self.db.dungeonOverride = nil
        end
    end

    if not dungeonIdx then
        -- Auto-detect from zone
        if not legacy.zoneIdToDungeonIdx then return end
        local zoneId = C_Map.GetBestMapForUnit("player")
        dungeonIdx = zoneId and legacy.zoneIdToDungeonIdx[zoneId]
    end

    if not dungeonIdx then return end

    if db.currentDungeonIdx ~= dungeonIdx then
        db.currentDungeonIdx = dungeonIdx
        if legacy.UpdateToDungeon then
            pcall(legacy.UpdateToDungeon, legacy, dungeonIdx)
        end
    end
    if forceRefresh and self.SelectBundledRoute then
        self:SelectBundledRoute(dungeonIdx)
    end
    return true
end

------------------------------------------------------------------------
-- Dungeon list & manual override
------------------------------------------------------------------------
function H:GetDungeonList()
    local legacy = GetLegacyMDT()
    if not legacy then
        local api = self:GetMDTAPI()
        local db = self:GetMDTDB()
        if not api or not api.GetDungeonName or not db then return {} end
        local list = {}
        -- MDT's public API deliberately hides its season table. Query its
        -- supported numeric dungeon range and keep only named entries.
        for idx = 1, 200 do
            local ok, name = pcall(api.GetDungeonName, api, idx)
            if ok and type(name) == "string" and name ~= "" and name ~= "-" then
                local clean = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                list[#list + 1] = { idx = idx, name = clean }
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list
    end

    if not legacy.dungeonList then return {} end

    -- Use current season's dungeon indices if available
    local allowedIdx
    if legacy.dungeonSelectionToIndex and #legacy.dungeonSelectionToIndex > 0 then
        allowedIdx = {}
        -- First entry is the current season for retail
        local db = legacy.GetDB and legacy:GetDB()
        local selectedList = db and db.selectedDungeonList or 1
        local seasonDungeons = legacy.dungeonSelectionToIndex[selectedList]
        if seasonDungeons then
            for _, idx in ipairs(seasonDungeons) do
                allowedIdx[idx] = true
            end
        end
    end

    local list = {}
    for idx, name in pairs(legacy.dungeonList) do
        if type(idx) == "number" and type(name) == "string" and name ~= "" then
            if not allowedIdx or allowedIdx[idx] then
                local clean = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                if clean ~= "" and legacy.dungeonEnemies and legacy.dungeonEnemies[idx] then
                    list[#list + 1] = { idx = idx, name = clean }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function H:GetCurrentDungeonName()
    local api = self:GetMDTAPI()
    local db = self:GetMDTDB()
    if not db or not db.currentDungeonIdx then return nil end
    local legacy = GetLegacyMDT()
    if legacy and legacy.dungeonList and legacy.dungeonList[db.currentDungeonIdx] then
        local name = legacy.dungeonList[db.currentDungeonIdx]
        return name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    if api and api.GetDungeonName then
        local ok, name = pcall(api.GetDungeonName, api, db.currentDungeonIdx)
        if ok and type(name) == "string" then
            return name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    return nil
end

function H:SetDungeonOverride(idx)
    self.db.dungeonOverride = idx
    if self:SyncMDTDungeon(true) ~= false then
        self:BuildRoute()
    else
        wipe(self.pulls)
        self.dungeonIdx = nil
        self.currentPullIdx = 1
        if self.UpdateUI then self:UpdateUI() end
    end
end

------------------------------------------------------------------------
-- Instance detection
------------------------------------------------------------------------
function H:CheckInstance()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "party" then
        local newInstance = self._lastInstanceID ~= instanceID
        self._lastInstanceID = instanceID
        self.activeDungeon = true
        self.db.mapPopout = true
        if self:SyncMDTDungeon(newInstance) ~= false then
            self:BuildRoute()
        elseif newInstance then
            -- Do not display the previous dungeon while MDT redraws this one.
            wipe(self.pulls)
            self.dungeonIdx = nil
            self.currentPullIdx = 1
        end
    else
        self:CancelModernMDTLoad()
        self._lastInstanceID = nil
        self.activeDungeon = false
        self.db.mapPopout = false
        self.db.dungeonOverride = nil
        self.keyCompleted = false
        wipe(self.npcKills)
        self.totalForcesGained = 0
        self.pullForcesAccum = 0
        self.livePullPercent = 0
        self.livePullValue = 0
        wipe(self.completedCriteria)
        prevForces = 0
        wipe(self.pulls)
        self.currentPullIdx = 1
    end
    if self.UpdateUI then self:UpdateUI() end
end

------------------------------------------------------------------------
-- Build route from MDT
------------------------------------------------------------------------
function H:BuildRoute()
    -- Full (re)build: resets live-run progress, then rebuilds the pull composition.
    wipe(self.npcKills)
    self.currentPullIdx = 1
    self.totalForcesGained = 0
    self.pullForcesAccum = 0
    self:RebuildPullData()
end

-- Rebuilds the pull/enemy composition from MDT's current preset WITHOUT resetting
-- live-run state (currentPullIdx, kills, forces gained). Safe to call mid-run, e.g.
-- after the user edits the current pull on the map popout.
function H:RebuildModernPullData()
    if not ModernRouteFrameReady(self._modernExpectedDungeonIdx) then
        self:EnsureModernMDTReady(false, self._modernExpectedDungeonIdx)
        return false
    end

    local api = self:GetMDTAPI()
    local db = self:GetMDTDB()
    local preset = self:GetCurrentMDTPreset()
    local frame = rawget(_G, "MDTFrame")
    if not api or not db or not preset or not frame then return false end

    local rawPulls = preset.value and preset.value.pulls
    local pullButtons = frame.sidePanel and frame.sidePanel.newPullButtons
    if not rawPulls or not pullButtons then return false end

    wipe(self.pulls)
    wipe(self.npcIdToEnemyInfo)
    self.totalForcesRequired = 0
    self.dungeonIdx = db.currentDungeonIdx
    self.allClonePositions = {}
    self.mdtEnemies = {}

    -- The current map's enemy buttons retain the private MDT enemy/clone data
    -- that was used to render them. Capture it without reaching into MDT's
    -- deliberately private addon namespace.
    local cloneLookup = {}
    local mapPanel = frame.mapPanelFrame
    if mapPanel and mapPanel.GetChildren then
        local children = { mapPanel:GetChildren() }
        for _, child in ipairs(children) do
            local enemyData, cloneData = child.data, child.clone
            local enemyIdx, cloneIdx = child.enemyIdx, child.cloneIdx
            if enemyData and cloneData and enemyIdx and cloneIdx
                and (not child.IsShown or child:IsShown()) then
                self.mdtEnemies[enemyIdx] = enemyData
                cloneLookup[enemyIdx] = cloneLookup[enemyIdx] or {}
                cloneLookup[enemyIdx][cloneIdx] = cloneData
                local sl = cloneData.sublevel or 1
                self.allClonePositions[sl] = self.allClonePositions[sl] or {}
                self.allClonePositions[sl][#self.allClonePositions[sl] + 1] = {
                    x = cloneData.x,
                    y = cloneData.y,
                    sublevel = sl,
                    npcId = enemyData.id,
                    name = LocalName(enemyData.name),
                    forces = enemyData.count or 0,
                    isBoss = enemyData.isBoss or false,
                    displayId = enemyData.displayId,
                    enemyScale = enemyData.scale or 1,
                    cloneScale = cloneData.scale or 1,
                    enemyIdx = enemyIdx,
                    cloneIdx = cloneIdx,
                }
            end
        end
    end

    for pullIdx, rawPull in ipairs(rawPulls) do
        local button = pullButtons[pullIdx]
        local pullData = { enemies = {}, clonePositions = {}, totalForces = 0, color = nil, completed = false }
        if button and button.color then
            pullData.color = { button.color.r or button.color[1], button.color.g or button.color[2], button.color.b or button.color[3] }
        elseif rawPull.color then
            pullData.color = { rawPull.color[1], rawPull.color[2], rawPull.color[3] }
        end

        if button and button.enemyPortraits then
            for _, portrait in pairs(button.enemyPortraits) do
                local data = portrait.enemyData
                if data and data.npcId and (not portrait.IsShown or portrait:IsShown()) then
                    local info = {
                        npcId = data.npcId,
                        name = LocalName(data.name),
                        forces = data.count or 0,
                        numClones = data.quantity or 0,
                        isBoss = data.isBoss or false,
                        displayId = data.displayId,
                    }
                    pullData.totalForces = pullData.totalForces + info.forces * info.numClones
                    pullData.enemies[#pullData.enemies + 1] = info
                    self.npcIdToEnemyInfo[info.npcId] = { name = info.name, forces = info.forces }

                    if self.totalForcesRequired == 0 and api.GetEnemyForces then
                        local ok, _, total = pcall(api.GetEnemyForces, api, info.npcId)
                        if ok and type(total) == "number" then self.totalForcesRequired = total end
                    end
                end
            end
        end

        for enemyIdx, clones in pairs(rawPull) do
            if enemyIdx ~= "color" and type(clones) == "table" then
                local enemyData = self.mdtEnemies[enemyIdx]
                for _, cloneIdx in pairs(clones) do
                    local cloneData = cloneLookup[enemyIdx] and cloneLookup[enemyIdx][cloneIdx]
                    if enemyData and cloneData then
                        pullData.clonePositions[#pullData.clonePositions + 1] = {
                            x = cloneData.x,
                            y = cloneData.y,
                            sublevel = cloneData.sublevel or 1,
                            npcId = enemyData.id,
                            name = LocalName(enemyData.name),
                            forces = enemyData.count or 0,
                            isBoss = enemyData.isBoss or false,
                            displayId = enemyData.displayId,
                            enemyScale = enemyData.scale or 1,
                            cloneScale = cloneData.scale or 1,
                            enemyIdx = enemyIdx,
                            cloneIdx = cloneIdx,
                        }
                    end
                end
            end
        end

        local hasBoss = false
        for _, info in ipairs(pullData.enemies) do
            if info.isBoss then hasBoss = true; break end
        end
        pullData.hasBoss = hasBoss
        table.sort(pullData.enemies, function(a, b) return a.name < b.name end)
        self.pulls[#self.pulls + 1] = pullData
    end

    if self.totalForcesRequired <= 0 then
        for _, pull in ipairs(self.pulls) do
            self.totalForcesRequired = self.totalForcesRequired + pull.totalForces
        end
    end
    if self.UpdateUI then self:UpdateUI() end
    return true
end

function H:RebuildPullData()
    if self:IsModernMDT() then
        self:RebuildModernPullData()
        return
    end

    wipe(self.pulls)
    wipe(self.npcIdToEnemyInfo)
    self.totalForcesRequired = 0

    local legacy = GetLegacyMDT()
    if not legacy or not legacy.GetCurrentPreset then return end

    local preset = legacy:GetCurrentPreset()
    if not preset or not preset.value or not preset.value.pulls then return end

    local db = legacy:GetDB()
    if not db or not db.currentDungeonIdx then return end

    local dungeonIdx = db.currentDungeonIdx
    self.dungeonIdx = dungeonIdx
    local enemies = legacy.dungeonEnemies[dungeonIdx]
    if not enemies then return end

    if legacy.dungeonTotalCount and legacy.dungeonTotalCount[dungeonIdx] then
        self.totalForcesRequired = legacy.dungeonTotalCount[dungeonIdx].normal or 0
    end

    for _, enemyData in pairs(enemies) do
        if enemyData.id then
            self.npcIdToEnemyInfo[enemyData.id] = {
                name = LocalName(enemyData.name),
                forces = enemyData.count or 0,
            }
        end
    end

    -- Collect ALL clone positions for the dungeon (used by map popout for surrounding mobs)
    self.allClonePositions = {}
    for enemyIdx, enemyData in pairs(enemies) do
        if enemyData.id and enemyData.clones then
            for cloneIdx, cloneData in pairs(enemyData.clones) do
                if cloneData.x and cloneData.y then
                    local sl = cloneData.sublevel or 1
                    if not self.allClonePositions[sl] then self.allClonePositions[sl] = {} end
                    self.allClonePositions[sl][#self.allClonePositions[sl] + 1] = {
                        x = cloneData.x,
                        y = cloneData.y,
                        sublevel = sl,
                        npcId = enemyData.id,
                        name = LocalName(enemyData.name),
                        forces = enemyData.count or 0,
                        isBoss = enemyData.isBoss or false,
                        displayId = enemyData.displayId,
                        enemyScale = enemyData.scale or 1,
                        cloneScale = cloneData.scale or 1,
                        enemyIdx = enemyIdx,
                        cloneIdx = cloneIdx,
                    }
                end
            end
        end
    end

    for _, pull in ipairs(preset.value.pulls) do
        local pullData = { enemies = {}, clonePositions = {}, totalForces = 0, color = nil, completed = false }

        if pull.color then
            pullData.color = { pull.color[1], pull.color[2], pull.color[3] }
        end

        local npcCounts = {}
        for enemyIdx, clones in pairs(pull) do
            if enemyIdx ~= "color" and type(clones) == "table" then
                local enemyData = enemies[enemyIdx]
                if enemyData and enemyData.id then
                    local npcId = enemyData.id
                    if not npcCounts[npcId] then
                        npcCounts[npcId] = {
                            npcId = npcId,
                            name = LocalName(enemyData.name),
                            forces = enemyData.count or 0,
                            numClones = 0,
                            isBoss = enemyData.isBoss or false,
                            displayId = enemyData.displayId,
                        }
                    end
                    for _, cloneIdx in pairs(clones) do
                        npcCounts[npcId].numClones = npcCounts[npcId].numClones + 1
                        local cloneData = enemyData.clones and enemyData.clones[cloneIdx]
                        if cloneData and cloneData.x and cloneData.y then
                            pullData.clonePositions[#pullData.clonePositions + 1] = {
                                x = cloneData.x,
                                y = cloneData.y,
                                sublevel = cloneData.sublevel or 1,
                                npcId = npcId,
                                name = LocalName(enemyData.name),
                                forces = enemyData.count or 0,
                                isBoss = enemyData.isBoss or false,
                                displayId = enemyData.displayId,
                                enemyScale = enemyData.scale or 1,
                                cloneScale = cloneData.scale or 1,
                                enemyIdx = enemyIdx,
                                cloneIdx = cloneIdx,
                            }
                        end
                    end
                end
            end
        end

        local hasBoss = false
        for _, info in pairs(npcCounts) do
            pullData.totalForces = pullData.totalForces + (info.forces * info.numClones)
            pullData.enemies[#pullData.enemies + 1] = info
            if info.isBoss then hasBoss = true end
        end
        pullData.hasBoss = hasBoss
        table.sort(pullData.enemies, function(a, b) return a.name < b.name end)
        self.pulls[#self.pulls + 1] = pullData
    end

    if self.UpdateUI then self:UpdateUI() end
end

------------------------------------------------------------------------
-- Live pull editing (click mobs on the map popout to add/remove them)
------------------------------------------------------------------------

-- Returns the list of clones that should be toggled together with the clicked
-- one. Mobs that pull together via social aggro share a numeric "g" group on
-- their clone data (scoped per sublevel), so we include every clone matching
-- that group — mirroring MDT's own linked-mob handling.
function H:GetLinkedClones(enemyIdx, cloneIdx)
    local result = { { enemyIdx = enemyIdx, cloneIdx = cloneIdx } }
    if not self.dungeonIdx then return result end
    local legacy = GetLegacyMDT()
    local enemies = legacy and legacy.dungeonEnemies and legacy.dungeonEnemies[self.dungeonIdx] or self.mdtEnemies
    if not enemies then return result end

    local srcEnemy = enemies[enemyIdx]
    local srcClone = srcEnemy and srcEnemy.clones and srcEnemy.clones[cloneIdx]
    if not srcClone or not srcClone.g then return result end

    local g = srcClone.g
    local sublevel = srcClone.sublevel or 1
    for eIdx, enemyData in pairs(enemies) do
        if enemyData.clones then
            for cIdx, cloneData in pairs(enemyData.clones) do
                if not (eIdx == enemyIdx and cIdx == cloneIdx)
                    and cloneData.g == g
                    and (cloneData.sublevel or 1) == sublevel then
                    result[#result + 1] = { enemyIdx = eIdx, cloneIdx = cIdx }
                end
            end
        end
    end
    return result
end

-- Remove a specific clone from one pull. Returns true if anything changed.
local function removeCloneFromPull(pull, enemyIdx, cloneIdx)
    local changed = false
    local list = pull[enemyIdx]
    if type(list) == "table" then
        for k = #list, 1, -1 do
            if list[k] == cloneIdx then
                table.remove(list, k)
                changed = true
            end
        end
    end
    return changed
end

-- Add or remove a single clone in the target pull. A clone may only belong to
-- one pull, so adding strips it from every other pull first (matching MDT).
local function setCloneInPull(pulls, pullIdx, enemyIdx, cloneIdx, add)
    local changed = false
    if add then
        for pIdx, pull in ipairs(pulls) do
            if pIdx ~= pullIdx and removeCloneFromPull(pull, enemyIdx, cloneIdx) then
                changed = true
            end
        end
        local target = pulls[pullIdx]
        target[enemyIdx] = target[enemyIdx] or {}
        local found = false
        for _, v in ipairs(target[enemyIdx]) do
            if v == cloneIdx then found = true; break end
        end
        if not found then
            table.insert(target[enemyIdx], cloneIdx)
            changed = true
        end
    else
        changed = removeCloneFromPull(pulls[pullIdx], enemyIdx, cloneIdx)
    end
    return changed
end

-- Add (add=true) or remove (add=false) a mob — plus any social-aggro linked
-- mobs — from the current pull, writing through to MDT's preset and refreshing.
function H:TogglePullMob(enemyIdx, cloneIdx, add)
    if not enemyIdx or not cloneIdx then return end
    local preset = self:GetCurrentMDTPreset()
    if not preset or not preset.value or not preset.value.pulls then return end

    local pulls = preset.value.pulls
    local pullIdx = self.currentPullIdx or 1
    if not pulls[pullIdx] then return end

    local changed = false
    for _, c in ipairs(self:GetLinkedClones(enemyIdx, cloneIdx)) do
        if setCloneInPull(pulls, pullIdx, c.enemyIdx, c.cloneIdx, add) then
            changed = true
        end
    end
    if not changed then return end

    -- Tell the map's deferred refresh to re-render in place (no camera jump).
    self._editingPull = true

    -- Keep MDT's own window in sync if the user happens to have it open.
    local legacy = GetLegacyMDT()
    if legacy and legacy.main_frame and legacy.main_frame.IsShown and legacy.main_frame:IsShown() then
        pcall(function()
            if legacy.ReloadPullButtons then legacy:ReloadPullButtons() end
            if legacy.UpdateProgressbar then legacy:UpdateProgressbar() end
            if legacy.SetSelectionToPull and legacy.GetCurrentPull then
                legacy:SetSelectionToPull(legacy:GetCurrentPull())
            end
        end)
    end

    local function RebuildEditedPulls()
        if H:GetCurrentMDTPreset() ~= preset then return end
        H._editingPull = true
        -- Pull indices are stable across mob add/remove. Preserve the latest
        -- completion state, including progress made during a deferred redraw.
        local prevCompleted, prevIncomplete = {}, {}
        for i, p in ipairs(H.pulls) do
            prevCompleted[i] = p.completed
            prevIncomplete[i] = p.incomplete
        end
        H:RebuildPullData()
        for i, p in ipairs(H.pulls) do
            p.completed = prevCompleted[i]
            p.incomplete = prevIncomplete[i]
        end
        if H.currentPullIdx > #H.pulls then
            H.currentPullIdx = math.max(#H.pulls, 1)
        end
        if H.RefreshMapPopout then H:RefreshMapPopout(true) end
    end

    if self:IsModernMDT() then
        local mdtFrame = rawget(_G, "MDTFrame")
        local group = mdtFrame and mdtFrame.sidePanel and mdtFrame.sidePanel.WidgetGroup
        local dropdown = group and group.PresetDropDown
        local db = self:GetMDTDB()
        if dropdown and dropdown.Fire and db and db.currentPreset then
            -- Modern pull data comes from rendered portraits. Redraw MDT first
            -- or the helper would immediately read the old enemy quantities.
            dropdown:Fire("OnValueChanged", db.currentPreset[db.currentDungeonIdx])
            C_Timer.After(0.2, RebuildEditedPulls)
            return
        end
    end
    RebuildEditedPulls()
end

------------------------------------------------------------------------
-- Auto-advance based on forces gained
------------------------------------------------------------------------
H.pullForcesAccum = 0

function H:CheckAutoAdvance(oldForces, newForces)
    if not self.db.autoAdvance then return end
    if oldForces == 0 and newForces > 0 then
        -- First update of the run, set baseline
        self.pullForcesAccum = 0
        return
    end
    local delta = newForces - oldForces
    if delta <= 0 then return end

    self.pullForcesAccum = self.pullForcesAccum + delta

    local pull = self.pulls[self.currentPullIdx]
    if not pull then return end

    -- If we've accumulated enough of this pull's expected forces, complete it
    local threshold = self.db.pullThreshold or 0.8
    if pull.totalForces > 0 and self.pullForcesAccum >= pull.totalForces * threshold then
        pull.completed = true
        pull.incomplete = nil
        self.pullForcesAccum = self.pullForcesAccum - pull.totalForces
        if self.pullForcesAccum < 0 then self.pullForcesAccum = 0 end
        if self.currentPullIdx < #self.pulls then
            self.currentPullIdx = self.currentPullIdx + 1
        end
    end
end

------------------------------------------------------------------------
-- Auto-advance boss pulls
------------------------------------------------------------------------
function H:CheckBossAdvance()
    if not self.db.autoAdvance then return end
    local pull = self.pulls[self.currentPullIdx]
    if not pull then return end
    if pull.hasBoss then
        pull.completed = true
        pull.incomplete = nil
        self.pullForcesAccum = 0
        if self.currentPullIdx < #self.pulls then
            self.currentPullIdx = self.currentPullIdx + 1
        end
    end
end

------------------------------------------------------------------------
-- Share route
------------------------------------------------------------------------
function H:RunWithCurrentMDTPreset(actionName, callback)
    local preset = self:GetCurrentMDTPreset()
    if preset and type(preset.value) == "table" then return callback(preset) end

    if not self:IsModernMDT() then
        print("|cff00ccffMDTHelper|r: No active MDT preset")
        return false
    end

    self._pendingPresetActions = self._pendingPresetActions or {}
    if self._pendingPresetActions[actionName] then return false end
    self._pendingPresetActions[actionName] = true
    self:EnsureModernMDTReady(false, nil)

    local attempts = 0
    local function PollPreset()
        attempts = attempts + 1
        local current = H:GetCurrentMDTPreset()
        if current and type(current.value) == "table" then
            H._pendingPresetActions[actionName] = nil
            callback(current)
        elseif attempts < 100 then
            C_Timer.After(0.1, PollPreset)
        else
            H._pendingPresetActions[actionName] = nil
            print("|cff00ccffMDTHelper|r: MDT route data did not finish loading")
        end
    end
    C_Timer.After(0, PollPreset)
    return false
end

local function GetGroupDistribution()
    return (UnitInRaid("player") and "RAID") or (IsInGroup() and "PARTY")
end

function H:ShareRoute()
    local distribution = GetGroupDistribution()
    if not distribution then
        print("|cff00ccffMDTHelper|r: You must be in a group to share")
        return
    end

    self:RunWithCurrentMDTPreset("share", function(preset)
        -- Group membership may have changed while the load-on-demand UI loaded.
        distribution = GetGroupDistribution()
        if not distribution then
            print("|cff00ccffMDTHelper|r: You must be in a group to share")
            return
        end
        local legacy = GetLegacyMDT()
        if legacy and legacy.SendToGroup then
            local ok = pcall(legacy.SendToGroup, legacy, distribution, false, preset)
            if not ok then
                print("|cff00ccffMDTHelper|r: Failed to share the MDT route")
                return
            end
            print("|cff00ccffMDTHelper|r: Route shared to " .. strlower(distribution))
            return
        end

        local api = self:GetMDTAPI()
        if not api or not api.SendCommMessage then
            print("|cff00ccffMDTHelper|r: MDT communication API is unavailable")
            return
        end

        self:EnsureMDTPresetUID(preset)
        local db = self:GetMDTDB()
        if db then preset.difficulty = db.currentDifficulty end
        local export = self:EncodeMDTPreset(preset, false)
        if not export then
            print("|cff00ccffMDTHelper|r: Failed to encode the MDT route")
            return
        end

        -- Announce only after AceComm has finished sending the payload, with
        -- the same extra delivery delay as current MDT's own sender.
        -- MDT's receiver caches links under the English dungeon name, even on
        -- localized clients. A localized name here produces an unopenable link.
        local dungeonName = ""
        if api.GetDungeonName then
            local ok, name = pcall(api.GetDungeonName, api, preset.value.currentDungeonIdx, true)
            if ok and type(name) == "string" then dungeonName = name end
        end
        local presetName = preset.text or "Unknown"
        local name, realm = UnitFullName("player")
        realm = realm or GetRealmName():gsub("%s+", "")
        if name then
            name = UnitFullName(name) or name -- preserve unusual character-name casing
        end
        local chatName = (name or UnitName("player") or "Unknown") .. "+" .. realm
        local msg = "[MDT_v2: " .. chatName .. " - " .. dungeonName .. ": " .. presetName .. "]"
        local announced = false
        local function OnProgress(_, bytesSent, bytesTotal, didSend)
            if announced or bytesSent ~= bytesTotal or didSend == false then return end
            announced = true
            C_Timer.After(0.5, function()
                C_ChatInfo.SendChatMessage(msg, distribution)
                print("|cff00ccffMDTHelper|r: Route shared to " .. strlower(distribution))
            end)
        end
        local ok = pcall(api.SendCommMessage, api, "MDTPreset", export, distribution, nil, "BULK", OnProgress)
        if not ok then
            print("|cff00ccffMDTHelper|r: Failed to send the MDT route")
        end
    end)
end

function H:CopyRouteString()
    self:RunWithCurrentMDTPreset("copy", function(preset)
        self:EnsureMDTPresetUID(preset)
        local db = self:GetMDTDB()
        if db then preset.difficulty = db.currentDifficulty end
        local export = self:EncodeMDTPreset(preset, true)
        if not export then
            print("|cff00ccffMDTHelper|r: Failed to encode the MDT route")
            return
        end
        self:ShowRouteExport(export)
    end)
end

function H:ShowRouteExport(export)
    if not H.exportFrame then
        local ef = CreateFrame("Frame", "MDTHelperExport", UIParent, "BackdropTemplate")
        ef:SetSize(340, 100)
        ef:SetPoint("CENTER")
        ef:SetFrameStrata("DIALOG")
        ef:SetMovable(true)
        ef:EnableMouse(true)
        ef:SetClampedToScreen(true)
        ef:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        ef:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
        ef:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        ef:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" then self:StartMoving() end
        end)
        ef:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

        local title = ef:CreateFontString(nil, "OVERLAY")
        title:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetTextColor(0, 0.8, 1)
        title:SetText("MDTHelper - Copy Route String")

        local closeBtn = CreateFrame("Frame", nil, ef)
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:EnableMouse(true)
        local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
        closeTxt:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
        closeTxt:SetPoint("CENTER")
        closeTxt:SetText("x")
        closeTxt:SetTextColor(0.6, 0.6, 0.6)
        closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 0.3, 0.3) end)
        closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(0.6, 0.6, 0.6) end)
        closeBtn:SetScript("OnMouseDown", function() ef:Hide() end)

        local editBox = CreateFrame("EditBox", nil, ef, "BackdropTemplate")
        editBox:SetSize(320, 24)
        editBox:SetPoint("TOPLEFT", 10, -34)
        editBox:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        editBox:SetAutoFocus(true)
        editBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        editBox:SetBackdropColor(0.02, 0.02, 0.02, 1)
        editBox:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        editBox:SetTextInsets(4, 4, 0, 0)
        editBox:SetScript("OnEscapePressed", function() ef:Hide() end)

        local hint = ef:CreateFontString(nil, "OVERLAY")
        hint:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        hint:SetPoint("TOPLEFT", 10, -64)
        hint:SetTextColor(0.5, 0.5, 0.5)
        hint:SetText("Ctrl+C to copy, Esc to close")

        ef.editBox = editBox
        H.exportFrame = ef
    end

    H.exportFrame.editBox:SetText(export)
    H.exportFrame:Show()
    H.exportFrame.editBox:SetFocus()
    H.exportFrame.editBox:HighlightText()
end

------------------------------------------------------------------------
-- Auto-import: check if sender is party leader (not ourselves)
------------------------------------------------------------------------
function H:IsSenderPartyLeader(sender)
    if type(sender) ~= "string" then return false end
    local localRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("%s+", "")
    local function NormalizeName(name, realm)
        if not name then return nil end
        return (name .. "-" .. (realm and realm ~= "" and realm or localRealm)):gsub("%s+", ""):lower()
    end
    local senderName, senderRealm = sender:match("^([^-]+)%-(.+)$")
    local fullSender = NormalizeName(senderName or sender, senderRealm)
    if fullSender == NormalizeName(UnitFullName("player")) then return false end

    local inRaid = IsInRaid()
    local count = GetNumGroupMembers() - (inRaid and 0 or 1)
    for i = 1, count do
        local unit = (inRaid and "raid" or "party") .. i
        if UnitIsGroupLeader(unit) and fullSender == NormalizeName(UnitFullName(unit)) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Auto-import: hook MDT comm to receive leader routes
------------------------------------------------------------------------
local function IsStructurallyValidPreset(preset)
    if type(preset) ~= "table" or type(preset.text) ~= "string"
        or type(preset.value) ~= "table" or type(preset.value.pulls) ~= "table" then
        return false
    end
    local function IsIndex(value)
        return type(value) == "number" and value >= 1 and value < math.huge and value % 1 == 0
    end
    if not IsIndex(preset.value.currentDungeonIdx) or not IsIndex(preset.value.currentPull)
        or not IsIndex(preset.value.currentSublevel) then return false end
    for pullIdx, pull in pairs(preset.value.pulls) do
        if not IsIndex(pullIdx) or type(pull) ~= "table" then return false end
        for enemyIdx, clones in pairs(pull) do
            if enemyIdx ~= "color" then
                if not IsIndex(enemyIdx) or type(clones) ~= "table" then return false end
                for _, cloneIdx in pairs(clones) do
                    if not IsIndex(cloneIdx) then return false end
                end
            elseif type(clones) ~= "table" then
                return false
            end
        end
    end
    return true
end

function H:ImportModernPreset(preset)
    if not IsStructurallyValidPreset(preset) or self._modernMDTLoading then return false end
    local db = self:GetMDTDB()
    local dungeonIdx = preset.value.currentDungeonIdx
    local presets = db and db.presets and db.presets[dungeonIdx]
    local mdtFrame = rawget(_G, "MDTFrame")
    local group = mdtFrame and mdtFrame.sidePanel and mdtFrame.sidePanel.WidgetGroup
    local dropdown = group and group.PresetDropDown
    if type(presets) ~= "table" or not db.currentPreset or not dropdown or not dropdown.Fire then
        return false
    end
    if not SelectModernDungeon(dungeonIdx) then return false end

    -- Match the old auto-import behavior: create a copy, never overwrite one
    -- of the player's routes (including a route with the same incoming UID).
    preset.uid = nil
    self:EnsureMDTPresetUID(preset)
    local names = {}
    for _, existing in pairs(presets) do
        if type(existing) == "table" then names[existing.text or ""] = true end
    end
    local originalName = preset.text
    local suffix = 2
    while names[preset.text] do
        preset.text = originalName .. " " .. suffix
        suffix = suffix + 1
    end

    local presetIdx = #presets + 1
    if type(presets[#presets]) == "table" and presets[#presets].value == 0 then
        presetIdx = #presets
    end
    table.insert(presets, presetIdx, preset)
    db.currentPreset[dungeonIdx] = presetIdx
    self._modernExpectedDungeonIdx = dungeonIdx

    -- Refresh through the same exposed dropdown callback used by a player.
    -- It invokes MDT's own map/pull normalization and rendering.
    local labels = {}
    for idx, existing in pairs(presets) do labels[idx] = existing.text end
    if dropdown.SetList then dropdown:SetList(labels) end
    if dropdown.SetValue then dropdown:SetValue(presetIdx) end
    dropdown:Fire("OnValueChanged", presetIdx)
    C_Timer.After(0.2, function() H:BuildRoute() end)
    return true
end

function H:QueueModernPresetImport(preset, sender)
    if not IsStructurallyValidPreset(preset) then return false end
    local api = self:GetMDTAPI()
    if not api or not api.GetDungeonName then return false end
    local ok, dungeonName = pcall(api.GetDungeonName, api, preset.value.currentDungeonIdx, true)
    if not ok or type(dungeonName) ~= "string" or dungeonName == "" or dungeonName == "-" then
        return false
    end
    self._pendingModernImport = { preset = preset, sender = sender }
    self:EnsureModernMDTReady(false, preset.value.currentDungeonIdx)
    if self._modernImportPolling then return end
    self._modernImportPolling = true

    local attempts = 0
    local function PollImport()
        attempts = attempts + 1
        local pending = H._pendingModernImport
        if not pending or not H.db.autoImport or not H:IsSenderPartyLeader(pending.sender) then
            H._pendingModernImport = nil
            H._modernImportPolling = nil
            return
        end
        if H:ImportModernPreset(pending.preset) then
            H._pendingModernImport = nil
            H._modernImportPolling = nil
            print("|cff00ccffMDTHelper|r: Auto-imported route from party leader")
        elseif attempts < 100 then
            C_Timer.After(0.1, PollImport)
        else
            H._pendingModernImport = nil
            H._modernImportPolling = nil
            print("|cff00ccffMDTHelper|r: Could not auto-import the leader's route")
        end
    end
    C_Timer.After(0, PollImport)
end

function H:OnMDTPresetReceived(prefix, message, distribution, sender)
    if prefix ~= "MDTPreset" or not self.db.autoImport then return end
    if not self:IsSenderPartyLeader(sender) then return end
    local preset = self:DecodeMDTPreset(message)
    if not preset then return end

    local legacy = GetLegacyMDT()
    if legacy then
        if not legacy.ValidateImportPreset or not legacy.ImportPreset
            or not legacy:ValidateImportPreset(preset) then return end
        preset.uid = nil
        legacy:ImportPreset(preset)
        self:BuildRoute()
        print("|cff00ccffMDTHelper|r: Auto-imported route from party leader")
    elseif IsStructurallyValidPreset(preset) then
        self:QueueModernPresetImport(preset, sender)
    end
end

function H:HookModernPresetChanges()
    if not self:IsModernMDT() then return false end
    if self._modernPresetDropdownHooked then return true end
    local mdtFrame = rawget(_G, "MDTFrame")
    local group = mdtFrame and mdtFrame.sidePanel and mdtFrame.sidePanel.WidgetGroup
    local dropdown = group and group.PresetDropDown
    if not dropdown or not dropdown.SetValue then return false end

    self._modernPresetDropdownHooked = true
    self._observedMDTPreset = self:GetCurrentMDTPreset()
    hooksecurefunc(dropdown, "SetValue", function()
        C_Timer.After(0.1, function()
            local preset = H:GetCurrentMDTPreset()
            if preset ~= H._observedMDTPreset then
                H._observedMDTPreset = preset
                if H.activeDungeon or H.db.mapPopout then H:BuildRoute() end
            end
        end)
    end)
    return true
end

function H:HookMDTComm()
    if not self.commHooked then
        local aceComm = LibStub and LibStub("AceComm-3.0", true)
        if aceComm then
            -- A separate AceComm subscriber receives reassembled messages
            -- without replacing MDT's private receiver or missing long routes.
            local listener = {}
            aceComm:Embed(listener)
            listener:RegisterComm("MDTPreset", function(prefix, message, distribution, sender)
                H:OnMDTPresetReceived(prefix, message, distribution, sender)
            end)
            self.mdtCommListener = listener
            self.commHooked = true
        end
    end

    local legacy = GetLegacyMDT()
    if legacy and legacy.UpdatePresetDropDown and not self._legacyPresetHooked then
        self._legacyPresetHooked = true
        hooksecurefunc(legacy, "UpdatePresetDropDown", function()
            if H.activeDungeon or H.db.mapPopout then H:BuildRoute() end
        end)
    end

    self:HookModernPresetChanges()
    local api = self:GetMDTAPI()
    if self:IsModernMDT() and api.RegisterUIInitializer and not self._presetUIInitializerRegistered then
        self._presetUIInitializerRegistered = true
        api:RegisterUIInitializer(function()
            local attempts = 0
            local function PollDropdown()
                attempts = attempts + 1
                if not H:HookModernPresetChanges() and attempts < 100 then
                    C_Timer.After(0.1, PollDropdown)
                end
            end
            C_Timer.After(0, PollDropdown)
        end)
    end
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------
function H:AdvancePull()
    if self.currentPullIdx < #self.pulls then
        local pull = self.pulls[self.currentPullIdx]
        if pull then
            pull.completed = true; pull.incomplete = nil
        end
        self.currentPullIdx = self.currentPullIdx + 1
        if self.UpdateUI then self:UpdateUI() end
    end
end

function H:RetreatPull()
    if self.currentPullIdx > 1 then
        self.currentPullIdx = self.currentPullIdx - 1
        local pull = self.pulls[self.currentPullIdx]
        if pull then pull.completed = false end
        if self.UpdateUI then self:UpdateUI() end
    end
end

function H:GetPullCount() return #self.pulls end

function H:GetCompletedCount()
    local c = 0
    for _, p in ipairs(self.pulls) do if p.completed then c = c + 1 end end
    return c
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_MDTHELPER1 = "/mdthelper"
SLASH_MDTHELPER2 = "/mdth"
SlashCmdList["MDTHELPER"] = function(msg)
    local cmd = strlower(strtrim(msg))
    if cmd == "toggle" or cmd == "" then
        H.db.enabled = not H.db.enabled
        if H.UpdateUI then H:UpdateUI() end
        print("|cff00ccffMDTHelper|r: " .. (H.db.enabled and "Enabled" or "Disabled"))
    elseif cmd == "lock" then
        H.db.locked = not H.db.locked
        print("|cff00ccffMDTHelper|r: Frame " .. (H.db.locked and "locked" or "unlocked"))
    elseif cmd == "min" then
        H.db.minimized = not H.db.minimized
        if H.UpdateUI then H:UpdateUI() end
        print("|cff00ccffMDTHelper|r: " .. (H.db.minimized and "Minimized" or "Expanded"))
    elseif cmd == "next" then
        H:AdvancePull()
    elseif cmd == "prev" then
        H:RetreatPull()
    elseif cmd == "reset" then
        wipe(H.npcKills)
        H.currentPullIdx = 1
        for _, pull in ipairs(H.pulls) do pull.completed = false end
        if H.UpdateUI then H:UpdateUI() end
        print("|cff00ccffMDTHelper|r: Reset pull progress")
    elseif cmd == "pos" then
        H.db.framePoint = nil
        H.db.frameHeight = nil
        H.db.uiScale = 1
        H._positionRestored = true
        local guide = _G["MDTHelperGuide"]
        if guide then
            guide:SetScale(1)
            guide:ClearAllPoints()
            guide:SetPoint("TOPLEFT", UIParent, "TOPLEFT", UIParent:GetWidth() - 260, -200)
        end
        if H.UpdateUI then H:UpdateUI() end
        print("|cff00ccffMDTHelper|r: Position and size reset to default")
    elseif cmd == "settings" or cmd == "config" then
        if H.ToggleSettings then H:ToggleSettings() end
    elseif cmd == "share" then
        H:ShareRoute()
    elseif cmd == "copy" then
        H:CopyRouteString()
    elseif cmd == "map" then
        if H.ToggleMapPopout then H:ToggleMapPopout() end
    elseif cmd == "autoimport" then
        H.db.autoImport = not H.db.autoImport
        print("|cff00ccffMDTHelper|r: Auto-import leader route " .. (H.db.autoImport and "enabled" or "disabled"))
    elseif cmd == "status" then
        print("|cff00ccffMDTHelper|r: " .. (H.db.enabled and "Enabled" or "Disabled"))
        print("  Active: " .. tostring(H.activeDungeon))
        print("  Pulls: " .. H:GetCompletedCount() .. "/" .. H:GetPullCount())
        print("  Current: " .. H.currentPullIdx)
    else
        print("|cff00ccffMDTHelper|r: /mdth [toggle|lock|min|next|prev|reset|pos|settings|share|copy|map|autoimport|status]")
    end
end

MDTHelper = H
