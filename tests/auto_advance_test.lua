-- Run from the repository root: lua tests/auto_advance_test.lua
-- Exercise real Core event handlers with deterministic scenario updates.
local passed = 0
local function setup(saved)
    local frames = {}
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, callback) self.callback = callback end
        frames[#frames + 1] = frame
        return frame
    end
    _G.MDTHelperDB = saved
    _G.SlashCmdList = {}
    _G.strlower = string.lower
    _G.strtrim = function(s) return s:match("^%s*(.-)%s*$") end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
    local H = {}
    _G.GetLocale = function() return "enUS" end
    assert(loadfile("MDTHelper/Locales.lua"))("MDTHelper", H)
    assert(loadfile("MDTHelper/Core.lua"))("MDTHelper", H)
    H.HookMDTComm = function() end
    local s = {}
    function s:emit(event, arg)
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame.callback(frame, event, arg) end
        end
    end
    function s:forces(quantity, boss)
        _G.C_Scenario = { GetStepInfo = function() return nil, nil, 2 end }
        _G.C_ScenarioInfo = { GetCriteriaInfo = function(i)
            if i == 1 then
                return { isWeightedProgress = true, quantityString = tostring(quantity), totalQuantity = 1000 }
            end
            return { completed = boss or false }
        end }
        self:emit("SCENARIO_CRITERIA_UPDATE")
    end
    s:emit("ADDON_LOADED", "MDTHelper")
    H.activeDungeon = true
    H.pulls = { { totalForces = 100 }, { totalForces = 100 }, { totalForces = 100 } }
    return H, s
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

test("new settings default to 100 percent and preserve saved tolerance", function()
    local H = setup()
    assert(H.db.autoAdvance and H.db.pullThreshold == 1)
    H = setup({ pullThreshold = 0.9, autoAdvance = false })
    assert(H.db.pullThreshold == 0.9 and not H.db.autoAdvance)
end)

test("first kill counts and full pull is required", function()
    local H, s = setup()
    s:forces(20)
    assert(H.pullForcesAccum == 20)
    s:forces(99)
    assert(H.currentPullIdx == 1 and not H.pulls[1].completed)
    s:forces(100)
    assert(H.currentPullIdx == 2 and H.pulls[1].completed and H.pullForcesAccum == 0)
end)

test("missing threshold uses 100 percent", function()
    local H, s = setup()
    H.db.pullThreshold = nil
    s:forces(90)
    assert(H.currentPullIdx == 1)
    s:forces(100)
    assert(H.currentPullIdx == 2)
end)

test("configured tolerance still advances early", function()
    local H, s = setup({ pullThreshold = 0.9 })
    s:forces(89)
    assert(H.currentPullIdx == 1)
    s:forces(90)
    assert(H.currentPullIdx == 2 and H.pullForcesAccum == 0)
end)

test("batched kills complete multiple pulls and carry excess once", function()
    local H, s = setup()
    s:forces(250)
    assert(H.currentPullIdx == 3 and H.pullForcesAccum == 50)
    assert(H.pulls[1].completed and H.pulls[2].completed and not H.pulls[3].completed)
    s:forces(250)
    assert(H.pullForcesAccum == 50)
    s:forces(300)
    assert(H.pulls[3].completed and H.pullForcesAccum == 0)
    s:forces(310)
    assert(H.currentPullIdx == 3 and H.pullForcesAccum == 10)
end)

test("manual navigation discards progress from the previous selection", function()
    local H, s = setup()
    s:forces(80)
    H:AdvancePull()
    s:forces(100)
    assert(H.currentPullIdx == 2 and H.pullForcesAccum == 20)
    H:RetreatPull()
    assert(H.currentPullIdx == 1 and H.pullForcesAccum == 0 and not H.pulls[1].completed)
end)

test("manual mode ignores gains and resuming starts fresh", function()
    local H, s = setup()
    s:forces(80)
    H:SetAutoAdvance(false)
    s:forces(300)
    H:AdvancePull()
    H:SetAutoAdvance(true)
    s:forces(320)
    assert(H.currentPullIdx == 2 and H.pullForcesAccum == 20)
end)

test("combat end does not mark an untouched next pull incomplete", function()
    local H, s = setup()
    H.pulls[2].totalForces = 200
    s:emit("PLAYER_REGEN_DISABLED")
    s:forces(100)
    s:emit("PLAYER_REGEN_ENABLED")
    assert(H.currentPullIdx == 2 and not H.pulls[2].incomplete)
end)

test("combat end flags only the partially completed current pull", function()
    local H, s = setup()
    s:emit("PLAYER_REGEN_DISABLED")
    s:forces(150)
    s:emit("PLAYER_REGEN_ENABLED")
    assert(H.currentPullIdx == 2 and H.pulls[2].incomplete)
    s:emit("PLAYER_REGEN_DISABLED")
    s:forces(200)
    s:emit("PLAYER_REGEN_ENABLED")
    assert(H.pulls[2].completed and not H.pulls[2].incomplete and not H.pulls[3].incomplete)
end)

test("combat state updates while auto advance is disabled", function()
    local H, s = setup()
    H:SetAutoAdvance(false)
    s:forces(30)
    s:emit("PLAYER_REGEN_DISABLED")
    assert(H.inCombat and H.combatForcesSnapshot == 30)
    s:emit("PLAYER_REGEN_ENABLED")
    assert(not H.inCombat)
end)

test("mixed pull waits for boss after trash and consumes excess once", function()
    local H, s = setup()
    H.pulls[1].hasBoss = true
    s:forces(150)
    assert(H.currentPullIdx == 1)
    s:forces(150, true)
    assert(H.currentPullIdx == 2 and H.pullForcesAccum == 50)
    s:forces(150, true)
    assert(H.currentPullIdx == 2 and H.pullForcesAccum == 50)
end)

test("mixed pull waits for trash after boss", function()
    local H, s = setup()
    H.pulls[1].hasBoss = true
    s:forces(0, true)
    assert(H.currentPullIdx == 1 and H.pulls[1].bossDefeated)
    s:forces(100, true)
    assert(H.currentPullIdx == 2 and H.pulls[1].completed)
end)

test("batched forces stop at a boss and continue after its kill", function()
    local H, s = setup()
    H.pulls[2] = { totalForces = 0, hasBoss = true }
    s:forces(200)
    assert(H.currentPullIdx == 2 and not H.pulls[2].completed)
    s:forces(200, true)
    assert(H.pulls[2].completed and H.pulls[3].completed and H.pullForcesAccum == 0)
end)

test("zero-forces enemies still require manual navigation", function()
    local H, s = setup()
    H.pulls[1].totalForces = 0
    H.pulls[1].enemies = { { name = "Non-counting enemy" } }
    s:forces(200)
    assert(H.currentPullIdx == 1 and not H.pulls[1].completed)
end)

test("empty pulls are skipped without consuming forces", function()
    local H, s = setup()
    H.pulls[1] = { totalForces = 0, enemies = {} }
    s:forces(150)
    assert(H.pulls[1].completed and H.pulls[2].completed)
    assert(H.currentPullIdx == 3 and H.pullForcesAccum == 50)
end)

test("an entirely empty route terminates at the last pull", function()
    local H = setup()
    for i = 1, 3 do H.pulls[i] = { totalForces = 0, enemies = {} } end
    H:AdvanceSatisfiedPulls()
    assert(H.currentPullIdx == 3 and H.pulls[3].completed and H.pullForcesAccum == 0)
end)

test("previously completed pulls do not stall or consume forces twice", function()
    local H, s = setup()
    H.pulls[2].completed = true
    s:forces(150)
    assert(H.currentPullIdx == 3 and H.pullForcesAccum == 50)
end)

test("dragging partially killed packs into the next fight retains progress", function()
    local H, s = setup()
    s:emit("PLAYER_REGEN_DISABLED")
    s:forces(70)
    s:emit("PLAYER_REGEN_ENABLED")
    s:emit("PLAYER_REGEN_DISABLED")
    s:forces(250)
    assert(H.currentPullIdx == 3 and H.pullForcesAccum == 50)
    assert(H.pulls[1].completed and not H.pulls[1].incomplete and H.pulls[2].completed)
end)

test("compact mode defaults off and preserves saved preferences", function()
    local H = setup()
    assert(H.db.compactMode == false)
    H = setup({ compactMode = true, minimized = true })
    assert(H.db.compactMode and H.db.minimized)
    SlashCmdList.MDTHELPER("compact")
    assert(not H.db.compactMode and H.db.minimized)
end)

test("reset clears partial forces and pull completion state", function()
    local H, s = setup()
    s:forces(150)
    H.pulls[2].incomplete = true
    H.pulls[2].bossDefeated = true
    SlashCmdList.MDTHELPER("reset")
    assert(H.currentPullIdx == 1 and H.pullForcesAccum == 0)
    for _, pull in ipairs(H.pulls) do
        assert(not pull.completed and not pull.incomplete and not pull.bossDefeated)
    end
    s:forces(170)
    assert(H.pullForcesAccum == 20)
end)

print(string.format("%d auto-advance tests passed", passed))
