local AddonName, NS = ...

-- Keybinding display names (must be globals for Blizzard Key Bindings UI)
BINDING_HEADER_MDTHELPER = "MDT Helper"
BINDING_NAME_MDTHELPER_NEXT_PULL = "Next Pull"
BINDING_NAME_MDTHELPER_PREV_PULL = "Previous Pull"

local H = NS

-- Localize enemy name via MDT's translation table
local function LocalName(name)
    if not name then return "Unknown" end
    local L = MDT and MDT.L
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
function H:SyncMDTDungeon()
    if not MDT or not MDT.GetDB then return end

    local db = MDT:GetDB()
    if not db then return end

    local dungeonIdx
    if self.db.dungeonOverride then
        -- Validate the override still exists in MDT
        if MDT.dungeonEnemies and MDT.dungeonEnemies[self.db.dungeonOverride] then
            dungeonIdx = self.db.dungeonOverride
        else
            self.db.dungeonOverride = nil
        end
    end

    if not dungeonIdx then
        -- Auto-detect from zone
        if not MDT.zoneIdToDungeonIdx then return end
        local zoneId = C_Map.GetBestMapForUnit("player")
        dungeonIdx = zoneId and MDT.zoneIdToDungeonIdx[zoneId]
    end

    if not dungeonIdx then return end

    if db.currentDungeonIdx ~= dungeonIdx then
        db.currentDungeonIdx = dungeonIdx
        if MDT.UpdateToDungeon then
            pcall(MDT.UpdateToDungeon, MDT, dungeonIdx)
        end
    end
end

------------------------------------------------------------------------
-- Dungeon list & manual override
------------------------------------------------------------------------
function H:GetDungeonList()
    if not MDT or not MDT.dungeonList then return {} end

    -- Use current season's dungeon indices if available
    local allowedIdx
    if MDT.dungeonSelectionToIndex and #MDT.dungeonSelectionToIndex > 0 then
        allowedIdx = {}
        -- First entry is the current season for retail
        local seasonDungeons = MDT.dungeonSelectionToIndex[1]
        if seasonDungeons then
            for _, idx in ipairs(seasonDungeons) do
                allowedIdx[idx] = true
            end
        end
    end

    local list = {}
    for idx, name in pairs(MDT.dungeonList) do
        if type(idx) == "number" and type(name) == "string" and name ~= "" then
            if not allowedIdx or allowedIdx[idx] then
                local clean = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                if clean ~= "" and MDT.dungeonEnemies and MDT.dungeonEnemies[idx] then
                    list[#list + 1] = { idx = idx, name = clean }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function H:GetCurrentDungeonName()
    if not MDT or not MDT.GetDB then return nil end
    local db = MDT:GetDB()
    if not db or not db.currentDungeonIdx then return nil end
    if MDT.dungeonList and MDT.dungeonList[db.currentDungeonIdx] then
        local name = MDT.dungeonList[db.currentDungeonIdx]
        return name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    return nil
end

function H:SetDungeonOverride(idx)
    self.db.dungeonOverride = idx
    self:SyncMDTDungeon()
    self:BuildRoute()
end

------------------------------------------------------------------------
-- Instance detection
------------------------------------------------------------------------
function H:CheckInstance()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        self.activeDungeon = true
        self.db.mapPopout = true
        self:SyncMDTDungeon()
        self:BuildRoute()
    else
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
function H:RebuildPullData()
    wipe(self.pulls)
    wipe(self.npcIdToEnemyInfo)
    self.totalForcesRequired = 0

    if not MDT or not MDT.GetCurrentPreset then return end

    local preset = MDT:GetCurrentPreset()
    if not preset or not preset.value or not preset.value.pulls then return end

    local db = MDT:GetDB()
    if not db or not db.currentDungeonIdx then return end

    local dungeonIdx = db.currentDungeonIdx
    self.dungeonIdx = dungeonIdx
    local enemies = MDT.dungeonEnemies[dungeonIdx]
    if not enemies then return end

    if MDT.dungeonTotalCount and MDT.dungeonTotalCount[dungeonIdx] then
        self.totalForcesRequired = MDT.dungeonTotalCount[dungeonIdx].normal or 0
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
    if not MDT or not self.dungeonIdx then return result end
    local enemies = MDT.dungeonEnemies[self.dungeonIdx]
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
    if not MDT or not MDT.GetCurrentPreset then return end
    local preset = MDT:GetCurrentPreset()
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
    if MDT.main_frame and MDT.main_frame.IsShown and MDT.main_frame:IsShown() then
        pcall(function()
            if MDT.ReloadPullButtons then MDT:ReloadPullButtons() end
            if MDT.UpdateProgressbar then MDT:UpdateProgressbar() end
            if MDT.SetSelectionToPull and MDT.GetCurrentPull then
                MDT:SetSelectionToPull(MDT:GetCurrentPull())
            end
        end)
    end

    -- Rebuild our route view without losing live-run progress, preserving the
    -- per-pull completion flags (pull indices are stable across mob add/remove).
    local prevCompleted, prevIncomplete = {}, {}
    for i, p in ipairs(self.pulls) do
        prevCompleted[i] = p.completed
        prevIncomplete[i] = p.incomplete
    end
    self:RebuildPullData()
    for i, p in ipairs(self.pulls) do
        p.completed = prevCompleted[i]
        p.incomplete = prevIncomplete[i]
    end
    if self.currentPullIdx > #self.pulls then
        self.currentPullIdx = math.max(#self.pulls, 1)
    end

    if self.RefreshMapPopout then self:RefreshMapPopout(true) end
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
function H:ShareRoute()
    if not MDT or not MDT.GetCurrentPreset or not MDT.TableToString then
        print("|cff00ccffMDTHelper|r: MDT not loaded")
        return
    end

    local distribution = MDT:IsPlayerInGroup()
    if not distribution then
        print("|cff00ccffMDTHelper|r: You must be in a group to share")
        return
    end

    local preset = MDT:GetCurrentPreset()
    if not preset then
        print("|cff00ccffMDTHelper|r: No active preset")
        return
    end

    MDT:SetUniqueID(preset)
    local db = MDT:GetDB()
    if db then preset.difficulty = db.currentDifficulty end

    local export = MDT:TableToString(preset, false, 5)

    -- Use MDT's registered comm object to send the data
    local commObj = LibStub and LibStub("AceAddon-3.0"):GetAddon("MDTCommsObject")
    if commObj and commObj.SendCommMessage then
        commObj:SendCommMessage("MDTPreset", export, distribution, nil, "BULK")
    end

    -- Post the clickable chat link (same format MDT uses)
    local dungeonName = ""
    if db and db.currentDungeonIdx then
        if MDT.GetDungeonName then
            dungeonName = MDT:GetDungeonName(db.currentDungeonIdx, true) or ""
        elseif MDT.dungeonList then
            dungeonName = MDT.dungeonList[db.currentDungeonIdx] or ""
            dungeonName = dungeonName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    local presetName = preset.text or "Unknown"
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName():gsub("%s+", "")
    -- MDT uses "+" between name and realm in the chat link, "-" in the cache key
    name = UnitFullName(name) or name -- re-resolve for correct case (MDT compat)
    local chatName = name .. "+" .. realm
    local msg = "[MDT_v2: " .. chatName .. " - " .. dungeonName .. ": " .. presetName .. "]"
    C_ChatInfo.SendChatMessage(msg, distribution)

    print("|cff00ccffMDTHelper|r: Route shared to " .. strlower(distribution))
end

function H:CopyRouteString()
    if not MDT or not MDT.GetCurrentPreset or not MDT.TableToString then
        print("|cff00ccffMDTHelper|r: MDT not loaded")
        return
    end

    local preset = MDT:GetCurrentPreset()
    if not preset then
        print("|cff00ccffMDTHelper|r: No active preset")
        return
    end

    MDT:SetUniqueID(preset)
    local db = MDT:GetDB()
    if db then preset.difficulty = db.currentDifficulty end
    local export = MDT:TableToString(preset, true, 5)

    -- Show a simple copy dialog
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
    local senderName = Ambiguate(sender, "none")
    if UnitIsGroupLeader("player") and senderName == UnitName("player") then
        return false
    end
    for i = 1, GetNumGroupMembers() - 1 do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitName(unit) == senderName and UnitIsGroupLeader(unit) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Auto-import: hook MDT comm to receive leader routes
------------------------------------------------------------------------
function H:HookMDTComm()
    if self.commHooked then return end
    if not MDTcommsObject then return end
    self.commHooked = true

    -- Hook comm for auto-import from party leader
    local origOnCommReceived = MDTcommsObject.OnCommReceived
    MDTcommsObject.OnCommReceived = function(obj, prefix, message, distribution, sender)
        origOnCommReceived(obj, prefix, message, distribution, sender)
        if prefix ~= "MDTPreset" then return end
        if not H.db.autoImport then return end
        if not H:IsSenderPartyLeader(sender) then return end

        local ok, preset = pcall(MDT.StringToTable, MDT, message, false)
        if not ok or not preset then return end
        if not MDT:ValidateImportPreset(preset) then return end

        preset.uid = nil
        MDT:ImportPreset(preset)
        H:BuildRoute()
        print("|cff00ccffMDTHelper|r: Auto-imported route from party leader")
    end

    -- Hook MDT preset changes so any import/switch rebuilds our route
    if MDT and MDT.UpdatePresetDropDown then
        hooksecurefunc(MDT, "UpdatePresetDropDown", function()
            if H.activeDungeon or H.db.mapPopout then
                H:BuildRoute()
            end
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
