local AddonName, NS = ...

local H = NS
H.pulls = {}
H.npcIdToEnemyInfo = {}
H.npcKills = {}
H.currentPullIdx = 1
H.totalForcesGained = 0
H.totalForcesRequired = 0
H.activeDungeon = false
H.completedCriteria = {}
H.keyCompleted = false
H.db = { enabled = true, locked = false }

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
        H.db = MDTHelperDB

        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        H:CheckInstance()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        H:OnKeyCompleted()
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
-- Instance detection
------------------------------------------------------------------------
function H:CheckInstance()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" then
        self.activeDungeon = true
        self:BuildRoute()
    else
        self.activeDungeon = false
        self.keyCompleted = false
        wipe(self.pulls)
        wipe(self.npcKills)
        self.currentPullIdx = 1
        self.totalForcesGained = 0
        self.pullForcesAccum = 0
        wipe(self.completedCriteria)
        prevForces = 0
    end
    if self.UpdateUI then self:UpdateUI() end
end

------------------------------------------------------------------------
-- Build route from MDT
------------------------------------------------------------------------
function H:BuildRoute()
    wipe(self.pulls)
    wipe(self.npcIdToEnemyInfo)
    wipe(self.npcKills)
    self.currentPullIdx = 1
    self.totalForcesGained = 0
    self.totalForcesRequired = 0

    if not MDT or not MDT.GetCurrentPreset then return end

    local preset = MDT:GetCurrentPreset()
    if not preset or not preset.value or not preset.value.pulls then return end

    local db = MDT:GetDB()
    if not db or not db.currentDungeonIdx then return end

    local dungeonIdx = db.currentDungeonIdx
    local enemies = MDT.dungeonEnemies[dungeonIdx]
    if not enemies then return end

    if MDT.dungeonTotalCount and MDT.dungeonTotalCount[dungeonIdx] then
        self.totalForcesRequired = MDT.dungeonTotalCount[dungeonIdx].normal or 0
    end

    for _, enemyData in pairs(enemies) do
        if enemyData.id then
            self.npcIdToEnemyInfo[enemyData.id] = {
                name = enemyData.name or "Unknown",
                forces = enemyData.count or 0,
            }
        end
    end

    for _, pull in ipairs(preset.value.pulls) do
        local pullData = { enemies = {}, totalForces = 0, color = nil, completed = false }

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
                            name = enemyData.name or "Unknown",
                            forces = enemyData.count or 0,
                            numClones = 0,
                            isBoss = enemyData.isBoss or false,
                            displayId = enemyData.displayId,
                        }
                    end
                    for _ in pairs(clones) do
                        npcCounts[npcId].numClones = npcCounts[npcId].numClones + 1
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
-- Auto-advance based on forces gained
------------------------------------------------------------------------
H.pullForcesAccum = 0

function H:CheckAutoAdvance(oldForces, newForces)
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

    -- If we've accumulated at least 80% of this pull's expected forces, complete it
    if pull.totalForces > 0 and self.pullForcesAccum >= pull.totalForces * 0.8 then
        pull.completed = true
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
    local pull = self.pulls[self.currentPullIdx]
    if not pull then return end
    if pull.hasBoss then
        pull.completed = true
        self.pullForcesAccum = 0
        if self.currentPullIdx < #self.pulls then
            self.currentPullIdx = self.currentPullIdx + 1
        end
    end
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------
function H:AdvancePull()
    if self.currentPullIdx < #self.pulls then
        local pull = self.pulls[self.currentPullIdx]
        if pull then pull.completed = true end
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
    elseif cmd == "status" then
        print("|cff00ccffMDTHelper|r: " .. (H.db.enabled and "Enabled" or "Disabled"))
        print("  Active: " .. tostring(H.activeDungeon))
        print("  Pulls: " .. H:GetCompletedCount() .. "/" .. H:GetPullCount())
        print("  Current: " .. H.currentPullIdx)
    else
        print("|cff00ccffMDTHelper|r: /mdth [toggle|lock|next|prev|reset|status]")
    end
end

MDTHelper = H
