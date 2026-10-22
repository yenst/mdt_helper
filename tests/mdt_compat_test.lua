-- Run from the repository root: lua tests/mdt_compat_test.lua
-- WoW APIs are mocked; in-game sending/receiving still needs a two-client check.
local realPrint = print
local passed = 0

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function preset(name)
    return {
        text = name or "Route",
        value = { currentDungeonIdx = 1, currentPull = 1, currentSublevel = 1, pulls = { { [1] = { 1 } } } },
    }
end

local function newFrame()
    return setmetatable({ scripts = {}, shown = false }, {
        __index = function(_, key)
            if key == "SetScript" then return function(self, event, callback) self.scripts[event] = callback end end
            if key == "GetScript" then return function(self, event) return self.scripts[event] end end
            if key == "CreateFontString" or key == "CreateTexture" then return newFrame end
            if key == "SetText" then return function(self, text) self.text = text end end
            if key == "Show" then return function(self) self.shown = true end end
            if key == "Hide" then return function(self) self.shown = false end end
            if key == "IsShown" then return function(self) return self.shown end end
            return function() end
        end,
    })
end

local function setup()
    local state = { timers = {}, messages = {}, sends = {}, registrations = {}, units = {}, rebuilds = 0 }
    state.grouped = true
    state.units.player = { "Tester", "HomeRealm" }
    state.units.party1 = { "Leader", "OtherRealm", leader = true }
    state.db = { currentDungeonIdx = 1, currentDifficulty = 12, currentPreset = { [1] = 1 },
        presets = { [1] = { preset(), { text = "<New Preset>", value = 0 } } } }

    _G.MDT = nil
    _G.MDTcommsObject = nil
    _G.MDTFrame = nil
    _G.MDTHelperDB = nil
    _G.SlashCmdList = {}
    _G.CreateFrame = newFrame
    _G.print = function(message) state.messages[#state.messages + 1] = message end
    _G.strlower = string.lower
    _G.wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end end
    _G.GetRealmName = function() return "Home Realm" end
    _G.GetNormalizedRealmName = function() return "HomeRealm" end
    _G.UnitFullName = function(unit)
        local info = state.units[unit]
        if info then return info[1], info[2] end
        if unit == "Tester" then return "Tester", "HomeRealm" end
    end
    _G.UnitName = UnitFullName
    _G.UnitIsGroupLeader = function(unit) return state.units[unit] and state.units[unit].leader or false end
    _G.IsInRaid = function() return state.raid or false end
    _G.UnitInRaid = IsInRaid
    _G.IsInGroup = function() return state.grouped end
    _G.GetNumGroupMembers = function() return state.grouped and (state.groupSize or 2) or 0 end
    _G.C_Timer = { After = function(_, callback) state.timers[#state.timers + 1] = callback end }
    _G.C_ChatInfo = { SendChatMessage = function(message, distribution)
        state.chat = { message, distribution }
    end }
    _G.hooksecurefunc = function(object, method, hook)
        local original = object[method]
        object[method] = function(...)
            local result = original(...)
            hook(...)
            return result
        end
    end
    local aceComm = {}
    function aceComm:Embed(object)
        object.RegisterComm = function(_, prefix, callback)
            state.registrations[#state.registrations + 1] = { prefix, callback }
        end
    end
    _G.LibStub = function(name) if name == "AceComm-3.0" then return aceComm end end

    local serialized = {}
    _G.Enum = { CompressionMethod = { Deflate = 0 } }
    _G.C_EncodingUtil = {
        SerializeCBOR = function(value)
            local token = tostring(#serialized + 1)
            serialized[#serialized + 1] = copy(value)
            return token
        end,
        CompressString = function(value, method) assert(method == 0); return "deflate:" .. value end,
        EncodeBase64 = function(value) return "base64:" .. value end,
        DecodeBase64 = function(value) return value:match("^base64:(.*)$") end,
        DecompressString = function(value, method) assert(method == 0); return value:match("^deflate:(.*)$") end,
        DeserializeCBOR = function(value) return copy(serialized[tonumber(value)]) end,
    }
    _G.MythicDungeonToolsAPI = {
        GetDB = function() return state.db end,
        GetDungeonName = function(_, idx, forceEnglish)
            if idx == 1 then return forceEnglish and "Dungeon" or "Localized Dungeon" end
        end,
        SendCommMessage = function(_, prefix, message, distribution, target, priority, callback)
            state.sends[#state.sends + 1] = { prefix, message, distribution, target, priority }
            state.progress = callback
        end,
        RegisterUIInitializer = function(_, callback) state.initializer = callback end,
    }

    local H = {}
    _G.GetLocale = function() return "enUS" end
    assert(loadfile("MDTHelper/Locales.lua"))("MDTHelper", H)
    assert(loadfile("MDTHelper/Core.lua"))("MDTHelper", H)
    H.BuildRoute = function() state.rebuilds = state.rebuilds + 1 end
    H.EnsureModernMDTReady = function() state.loadRequests = (state.loadRequests or 0) + 1 end
    state.H = H
    function state:flush()
        local count = 0
        while #self.timers > 0 do
            count = count + 1
            assert(count < 1000, "timer loop did not settle")
            local callback = table.remove(self.timers, 1)
            callback()
        end
    end
    function state:dropdown()
        local dropdown = {
            SetList = function(_, labels) self.labels = labels end,
            SetValue = function(_, value) self.selection = value end,
            Fire = function(_, event, value) self.fired = { event, value } end,
        }
        _G.MDTFrame = { sidePanel = { WidgetGroup = { PresetDropDown = dropdown } } }
        return dropdown
    end
    -- MDT 6.3.10+ side panel: kit controls nested under the panel, found by id.
    function state:kit(pullItems, blips)
        local function control(props)
            return {
                kitProps = props,
                Emit = function(control, name, ...) return control.kitProps[name](...) end,
                GetChildren = function() end,
            }
        end
        local routes = control({ id = "routes", onActivate = function(item)
            self.db.currentPreset[self.db.currentDungeonIdx] = item.idx
            self.activated = item.idx
        end })
        local search = control({ id = "routeSearch", value = "", onChange = function(text)
            self.routeRefreshes = (self.routeRefreshes or 0) + 1
            self.routeQuery = text
        end })
        search.GetValue = function(control) return control.kitProps.value end
        local pulls = control({ id = "pulls", items = pullItems or {} })
        local stack = { GetChildren = function() return search, routes, pulls end }
        _G.MDTFrame = {
            sidePanel = { GetChildren = function() return stack end },
            mapPanelFrame = { GetChildren = function() return unpack(blips or {}) end },
        }
        return routes, pulls
    end
    return state, H
end

local function test(name, run)
    local ok, err = pcall(run)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    realPrint("PASS " .. name)
end

local function setInstance(inInstance, instanceType, instanceID)
    _G.IsInInstance = function() return inInstance, instanceType end
    _G.GetInstanceInfo = function()
        return "Localized Dungeon", instanceType, 0, "", 5, 0, false, instanceID
    end
end

test("garrison party type never activates a dungeon or loads a route", function()
    local s, H = setup()
    H.activeDungeon = true
    H.db.mapPopout = true
    H.pulls = { { totalForces = 100 } }
    H._modernMDTLoading = true
    setInstance(false, "party", 1159)
    H:CheckInstance()
    assert(not H.activeDungeon and not H.db.mapPopout and #H.pulls == 0)
    assert(not H._modernMDTLoading and not s.loadRequests and s.rebuilds == 0)
    H.db.enabled = false
    H:CheckInstance() -- another notification while leaving the garrison
    setInstance(false, "none", 1116)
    H:CheckInstance()
    assert(not H.db.enabled and not H.db.mapPopout and not H.activeDungeon)
    assert(not s.loadRequests and s.rebuilds == 0)
end)

test("dungeon entry opens the map once and repeated events preserve progress", function()
    local s, H = setup()
    setInstance(true, "party", 1234)
    H:CheckInstance()
    assert(H.activeDungeon and H.db.mapPopout and s.rebuilds == 1)
    H.pulls = { { totalForces = 100, completed = true }, { totalForces = 100 } }
    H.currentPullIdx, H.totalForcesGained, H.pullForcesAccum = 2, 120, 20
    H.db.mapPopout = false
    H:CheckInstance()
    assert(not H.db.mapPopout and s.rebuilds == 1)
    assert(H.currentPullIdx == 2 and H.totalForcesGained == 120 and H.pullForcesAccum == 20)
    setInstance(true, "party", 5678)
    H:CheckInstance()
    assert(H.db.mapPopout and s.rebuilds == 2)
    setInstance(false, "none", 1116)
    H:CheckInstance()
    assert(not H.activeDungeon and not H.db.mapPopout and #H.pulls == 0)
end)

test("disabled addon stays disabled on dungeon entry", function()
    local s, H = setup()
    H.db.enabled, H.db.mapPopout = false, false
    setInstance(true, "party", 1234)
    H:CheckInstance()
    assert(not H.db.enabled and not H.db.mapPopout)
end)

test("raid and scenario instances do not activate the dungeon guide", function()
    for _, instanceType in ipairs({ "raid", "scenario" }) do
        local s, H = setup()
        setInstance(true, instanceType, 1234)
        H:CheckInstance()
        assert(not H.activeDungeon and not H.db.mapPopout and s.rebuilds == 0)
    end
end)

test("modern share works without the removed MDT global", function()
    local s, H = setup()
    H:ShareRoute()
    assert(#s.sends == 1 and s.sends[1][1] == "MDTPreset")
    assert(s.sends[1][2]:sub(1, 7) == "!~MDT2~")
    assert(s.sends[1][3] == "PARTY" and s.sends[1][5] == "BULK")
    assert(not s.chat)
    s.progress(nil, 1, 100, true)
    s:flush()
    assert(not s.chat, "partial sends must not announce")
    s.progress(nil, 100, 100, false)
    s:flush()
    assert(not s.chat, "failed sends must not announce")
    s.progress(nil, 100, 100, true)
    s.progress(nil, 100, 100, true)
    s:flush()
    assert(s.chat[1] == "[MDT_v2: Tester+HomeRealm - Dungeon: Route]")
    local decoded = H:DecodeMDTPreset(s.sends[1][2])
    assert(decoded.difficulty == 12 and #decoded.uid == 11)
end)

test("modern copy uses the current export format and existing dialog", function()
    local s, H = setup()
    H:CopyRouteString()
    assert(H.exportFrame.shown)
    local decoded = H:DecodeMDTPreset(H.exportFrame.editBox.text)
    assert(decoded.text == "Route" and decoded.difficulty == 12)
    assert(#s.sends == 0)
end)

test("malformed exports and unavailable encoding fail safely", function()
    local s, H = setup()
    assert(H:DecodeMDTPreset("!~MDT2~broken") == nil)
    assert(H:DecodeMDTPreset(nil) == nil)
    C_EncodingUtil.SerializeCBOR = nil
    H:ShareRoute()
    assert(#s.sends == 0 and not s.chat)
    assert(s.messages[#s.messages]:find("Failed to encode", 1, true))
end)

test("sharing waits for lazy-loaded data and rechecks group membership", function()
    local s, H = setup()
    local saved = s.db.presets
    s.db.presets = nil
    H:ShareRoute()
    H:ShareRoute()
    assert(s.loadRequests == 1 and #s.sends == 0)
    s.db.presets = saved
    s.grouped = false
    s:flush()
    assert(#s.sends == 0)
    assert(s.messages[#s.messages]:find("must be in a group", 1, true))
end)

test("lazy-loaded copy times out without misreporting MDT as absent", function()
    local s, H = setup()
    s.db.presets = nil
    H:CopyRouteString()
    s:flush()
    assert(not H.exportFrame)
    assert(s.messages[#s.messages]:find("did not finish loading", 1, true))
    assert(not H._pendingPresetActions.copy)
end)

test("legacy sharing and printable export remain supported", function()
    local s, H = setup()
    local route = s.db.presets[1][1]
    _G.MDT = {
        GetDB = function() return s.db end,
        GetCurrentPreset = function() return route end,
        SendToGroup = function(_, distribution, silent, selected)
            assert(distribution == "PARTY" and silent == false and selected == route)
            s.legacyShared = true
        end,
        SetUniqueID = function(_, selected) selected.uid = "legacyuid" end,
        TableToString = function(_, selected, printable, level)
            assert(selected == route and printable == true and level == 5)
            return "legacy-printable-export"
        end,
    }
    H:ShareRoute()
    H:CopyRouteString()
    assert(s.legacyShared and #s.sends == 0)
    assert(H.exportFrame.editBox.text == "legacy-printable-export")
end)

test("leader matching includes realm and the last raid member", function()
    local s, H = setup()
    assert(H:IsSenderPartyLeader("Leader-OtherRealm"))
    assert(not H:IsSenderPartyLeader("Leader-HomeRealm"))
    assert(not H:IsSenderPartyLeader("Tester-HomeRealm"))
    s.raid = true
    s.groupSize = 3
    s.units.raid3 = { "RaidLeader", "OtherRealm", leader = true }
    assert(H:IsSenderPartyLeader("RaidLeader-OtherRealm"))
end)

test("AceComm subscription is independent and registered only once", function()
    local s, H = setup()
    H:HookMDTComm()
    H:HookMDTComm()
    assert(#s.registrations == 1 and s.registrations[1][1] == "MDTPreset")
    local seen
    H.OnMDTPresetReceived = function(_, ...) seen = { ... } end
    s.registrations[1][2]("MDTPreset", "assembled-message", "PARTY", "Leader-OtherRealm")
    assert(seen[2] == "assembled-message" and seen[4] == "Leader-OtherRealm")
end)

test("modern auto-import inserts a copy and preserves existing routes", function()
    local s, H = setup()
    s:dropdown()
    local existing = s.db.presets[1][1]
    existing.uid = "sameuid"
    local incoming = preset("Route")
    incoming.uid = "sameuid"
    H:OnMDTPresetReceived("MDTPreset", H:EncodeMDTPreset(incoming), "PARTY", "Leader-OtherRealm")
    s:flush()
    local presets = s.db.presets[1]
    assert(#presets == 3 and presets[1] == existing)
    assert(presets[2].text == "Route 2" and presets[2].uid ~= existing.uid)
    assert(presets[3].value == 0 and s.db.currentPreset[1] == 2)
    assert(s.fired[1] == "OnValueChanged" and s.fired[2] == 2)
    assert(s.rebuilds == 1)
end)

test("auto-import ignores disabled, non-leader and malformed messages", function()
    local s, H = setup()
    s:dropdown()
    local encoded = H:EncodeMDTPreset(preset())
    H:OnMDTPresetReceived("MDTPreset", encoded, "PARTY", "Stranger-OtherRealm")
    H.db.autoImport = false
    H:OnMDTPresetReceived("MDTPreset", encoded, "PARTY", "Leader-OtherRealm")
    H.db.autoImport = true
    H:OnMDTPresetReceived("MDTPreset", H:EncodeMDTPreset({ text = "bad", value = {} }), "PARTY", "Leader-OtherRealm")
    local malformed = preset()
    malformed.value.pulls[1] = true
    H:OnMDTPresetReceived("MDTPreset", H:EncodeMDTPreset(malformed), "PARTY", "Leader-OtherRealm")
    local unknown = preset()
    unknown.value.currentDungeonIdx = 999
    H:OnMDTPresetReceived("MDTPreset", H:EncodeMDTPreset(unknown), "PARTY", "Leader-OtherRealm")
    s:flush()
    assert(#s.db.presets[1] == 2 and not H._pendingModernImport)
    assert(s.db.currentDungeonIdx == 1 and not s.loadRequests)
end)

test("queued imports are cancelled if the sender is no longer leader", function()
    local s, H = setup()
    s:dropdown()
    H:QueueModernPresetImport(preset("Incoming"), "Leader-OtherRealm")
    s.units.party1.leader = false
    s:flush()
    assert(#s.db.presets[1] == 2 and not H._modernImportPolling)
end)

test("modern preset changes refresh once without resetting unchanged routes", function()
    local s, H = setup()
    local dropdown = s:dropdown()
    H.activeDungeon = true
    assert(H:HookModernPresetChanges())
    dropdown:SetValue(1)
    s:flush()
    assert(s.rebuilds == 0)
    s.db.presets[1][2] = preset("Changed")
    dropdown:SetValue(2) -- the widget changes before its callback updates MDT's DB
    s.db.currentPreset[1] = 2
    s:flush()
    assert(s.rebuilds == 1)
    dropdown:SetValue(2)
    s:flush()
    assert(s.rebuilds == 1)
end)

test("preset hook attaches after the modern UI initializes", function()
    local s, H = setup()
    H:HookMDTComm()
    assert(s.initializer and not H._modernPresetChangesHooked)
    s.initializer()
    s:dropdown()
    s:flush()
    assert(H._modernPresetChangesHooked)
end)

test("MDT 6.3.10 route changes use the public route callback", function()
    local s, H = setup()
    local callbacks = {}
    MythicDungeonToolsAPI.RegisterRouteChangedCallback = function(_, callback) callbacks[#callbacks + 1] = callback end
    H.db = { mapPopout = true }
    assert(H:HookModernPresetChanges() and H:HookModernPresetChanges())
    assert(#callbacks == 1)
    s.db.presets[1][3] = s.db.presets[1][2]
    s.db.presets[1][2] = preset("Other")
    s.db.currentPreset[1] = 2
    callbacks[1](1, 2)
    s:flush()
    assert(s.rebuilds == 1)
    callbacks[1](1, 2)
    s:flush()
    assert(s.rebuilds == 1)
end)

test("MDT 6.3.10 auto-import selects through the route list", function()
    local s, H = setup()
    s:kit()
    H.db = { autoImport = true }
    assert(H:ImportModernPreset(preset("Leader Route")))
    assert(#s.db.presets[1] == 3 and s.db.presets[1][2].text == "Leader Route")
    assert(s.db.presets[1][3].value == 0)
    assert(s.activated == 2 and s.db.currentPreset[1] == 2)
    assert(s.routeRefreshes == 1 and s.routeQuery == "")
end)

test("MDT 6.3.10 mob edits redraw through the route list", function()
    local s, H = setup()
    s:kit()
    H.pulls = { { completed = true, incomplete = false } }
    H.RebuildPullData = function()
        assert(s.activated == 1)
        H.pulls = { { completed = false } }
        s.editedRebuild = true
    end
    H:TogglePullMob(1, 2, true)
    assert(not s.editedRebuild, "modern pull data must redraw first")
    s:flush()
    assert(s.editedRebuild and H.pulls[1].completed == true)
end)

test("MDT 6.3.10 pull data comes from the kit pull list and map", function()
    local s, H = setup()
    local route = preset()
    route.value.pulls = {
        { [1] = { 1, 2 }, [2] = { 1 }, color = "ff0000" },
        { [3] = { 1 } },
    }
    s.db.presets[1][1] = route
    local skitter = { id = 101, name = "Skitter", count = 4, displayId = 11, scale = 1,
        clones = { { x = 1, y = 2, sublevel = 1 }, { x = 3, y = 4, sublevel = 1, count = 6 } } }
    local brute = { id = 102, name = "Brute", count = 10, isBoss = false, scale = 1,
        clones = { { x = 5, y = 6, sublevel = 1 } } }
    local function blip(enemyIdx, cloneIdx, data)
        return { enemyIdx = enemyIdx, cloneIdx = cloneIdx, data = data, clone = data.clones[cloneIdx],
            IsShown = function() return true end }
    end
    s:kit({
        { kind = "pull", index = 1, color = { 1, 0, 0 },
            portraits = { { enemyIdx = 2, npcId = 102, name = "Brute", count = 10, quantity = 1 } } },
        -- Enemy 3 is on another floor: only its pull portrait knows it.
        { kind = "pull", index = 2, color = { 0, 1, 0 },
            portraits = { { enemyIdx = 3, npcId = 103, name = "Boss", count = 0, quantity = 1, isBoss = true } } },
        { kind = "newPull", key = "new" },
    }, { blip(1, 1, skitter), blip(1, 2, skitter), blip(2, 1, brute) })
    MythicDungeonToolsAPI.GetEnemyForces = function(_, npcId) return 4, 200 end

    assert(H:RebuildModernPullData())
    assert(#H.pulls == 2)
    local first = H.pulls[1]
    assert(first.totalForces == 4 + 6 + 10, first.totalForces)
    assert(#first.enemies == 3 and #first.clonePositions == 3)
    assert(first.color[1] == 1 and first.color[2] == 0)
    assert(H.pulls[2].hasBoss and H.pulls[2].enemies[1].npcId == 103)
    assert(H.totalForcesRequired == 200)
    assert(H.npcIdToEnemyInfo[102].forces == 10)
end)

test("modern mob edits redraw MDT before rebuilding and preserve progress", function()
    local s, H = setup()
    s:dropdown()
    H.pulls = { { completed = true, incomplete = false } }
    H.RebuildPullData = function()
        assert(s.fired and s.fired[1] == "OnValueChanged")
        H.pulls = { { completed = false } }
        s.editedRebuild = true
    end
    H:TogglePullMob(1, 2, true)
    assert(not s.editedRebuild, "modern portrait data must redraw first")
    assert(#s.db.presets[1][1].value.pulls[1][1] == 2)
    s:flush()
    assert(s.editedRebuild and H.pulls[1].completed == true)
end)

test("mob edits immediately recheck forces after the deferred redraw", function()
    local s, H = setup()
    s:dropdown()
    H.pulls = { { totalForces = 100 }, { totalForces = 100 } }
    H.pullForcesAccum = 80
    H.RebuildPullData = function()
        H.pulls = { { totalForces = 60 }, { totalForces = 140 } }
    end
    H:TogglePullMob(1, 2, true)
    assert(H.currentPullIdx == 1)
    s:flush()
    assert(H.currentPullIdx == 2 and H.pulls[1].completed and H.pullForcesAccum == 20)
end)

test("mob edits keep manual tracking manual", function()
    local s, H = setup()
    s:dropdown()
    H.db.autoAdvance = false
    H.pulls = { { totalForces = 100 } }
    H.RebuildPullData = function()
        H.pulls = { { totalForces = 0, enemies = {} }, { totalForces = 100 } }
    end
    H:TogglePullMob(1, 2, true)
    s:flush()
    assert(H.currentPullIdx == 1 and not H.pulls[1].completed)
end)

-- The native codec is mocked as above, but use the actual bundled record list
-- so every shipped route participates in import/readiness/duplicate checks.
local function setupBundles()
    local s, H = setup()
    local file = assert(io.open("MDTHelper/BundledRoutes.lua", "r"))
    local source = file:read("*a")
    file:close()
    local decoded = {}
    s.bundleIndices = {}
    for idxText, encoded in source:gmatch("dungeonIdx = (%d+),%s+encoded = %[%[(.-)%]%]") do
        local idx = tonumber(idxText)
        local route = preset("Starter " .. idx)
        route.value.currentDungeonIdx = idx
        route.uid = "bundled" .. idx
        decoded[encoded:sub(8)] = route
        s.bundleIndices[#s.bundleIndices + 1] = idx
        s.db.presets[idx] = { preset("My route"), { text = "<New Preset>", value = 0 } }
        s.db.presets[idx][1].value.currentDungeonIdx = idx
        s.db.currentPreset[idx] = 1
    end
    assert(#s.bundleIndices == 8)
    s.db.currentDungeonIdx = s.bundleIndices[1]
    C_EncodingUtil.DecodeBase64 = function(value) return value end
    C_EncodingUtil.DecompressString = function(value) return value end
    C_EncodingUtil.DeserializeCBOR = function(value) return copy(decoded[value]) end
    assert(loadfile("MDTHelper/BundledRoutes.lua"))("MDTHelper", H)
    s:dropdown()
    return s, H
end

test("automatic seeds appear alongside existing routes without changing selection", function()
    local s, H = setupBundles()
    local idx = s.db.currentDungeonIdx
    local selected = s.db.presets[idx][1]
    H:HookModernPresetChanges()
    local ready, added = H:SeedBundledRoutes()
    s:flush()
    assert(ready and added == 8 and #s.db.presets[idx] == 3)
    assert(s.labels[2] == "Starter " .. idx)
    assert(s.db.presets[idx][s.db.currentPreset[idx]] == selected)
    assert(not s.fired and s.rebuilds == 0)
    H:SelectBundledRoute(idx)
    assert(s.db.currentPreset[idx] == 1, "nonempty user routes must remain selected")
end)

test("manual import restores deleted seeds and remains idempotent", function()
    local s, H = setupBundles()
    H:SeedBundledRoutes()
    local idx = s.db.currentDungeonIdx
    table.remove(s.db.presets[idx], 2)
    H:SeedBundledRoutes()
    assert(#s.db.presets[idx] == 2, "automatic seeding must honor deliberate deletion")
    H:ImportBundledRoutes()
    assert(#s.db.presets[idx] == 3)
    assert(s.messages[#s.messages]:find("1 imported, 7 already present, 0 unavailable", 1, true))
    s.labels = nil
    H:ImportBundledRoutes()
    assert(#s.db.presets[idx] == 3 and s.db.currentPreset[idx] == 1)
    assert(s.labels[2] == "Starter " .. idx, "even an idempotent import refreshes the list")
    assert(s.messages[#s.messages]:find("0 imported, 8 already present", 1, true))
end)

test("manual import recovers an MDT reset and preserves the selected sentinel", function()
    local s, H = setupBundles()
    H:SeedBundledRoutes()
    for _, idx in ipairs(s.bundleIndices) do
        s.db.presets[idx] = { { text = "<New Preset>", value = 0 } }
        s.db.currentPreset[idx] = 1
    end
    H:ImportBundledRoutes()
    for _, idx in ipairs(s.bundleIndices) do
        assert(#s.db.presets[idx] == 2 and s.db.currentPreset[idx] == 2)
        assert(s.db.presets[idx][2].value == 0)
    end
    assert(s.selection == 2 and not s.fired)
    assert(s.messages[#s.messages]:find("8 imported, 0 already present", 1, true))
end)

test("same-name user presets do not block seeds or become the bundled fallback", function()
    local s, H = setupBundles()
    local idx = s.db.currentDungeonIdx
    local userRoute = s.db.presets[idx][1]
    userRoute.text = "Starter " .. idx
    userRoute.value.pulls = {}
    H:ImportBundledRoutes()
    assert(s.db.presets[idx][1] == userRoute and not userRoute.mdtHelperSeedID)
    assert(s.db.presets[idx][2].text == "Starter " .. idx .. " 2")
    assert(s.db.currentPreset[idx] == 1)
    H:SelectBundledRoute(idx)
    assert(s.db.currentPreset[idx] == 2)
    s.db.presets[idx][2].text = "Renamed bundled route"
    H:ImportBundledRoutes()
    assert(#s.db.presets[idx] == 3 and s.db.currentPreset[idx] == 2)
end)

test("manual import loads modern MDT once and waits for data", function()
    local s, H = setupBundles()
    local saved = s.db.presets
    s.db.presets = nil
    MythicDungeonToolsAPI.ShowInterface = function()
        s.shows = (s.shows or 0) + 1
        C_Timer.After(0, function()
            s.db.presets = saved
            s.initializer()
        end)
    end
    H:ImportBundledRoutes()
    H:ImportBundledRoutes()
    assert(s.shows == 1 and H._bundledImportPending)
    s:flush()
    assert(not H._bundledImportPending)
    assert(s.messages[#s.messages]:find("8 imported, 0 already present", 1, true))
end)

test("partial readiness waits and reports accurate import totals", function()
    local s, H = setupBundles()
    local idx = s.bundleIndices[2]
    local saved = s.db.presets[idx]
    s.db.presets[idx] = nil
    H:ImportBundledRoutes()
    assert(H._bundledImportPending)
    s.db.presets[idx] = saved
    s:flush()
    assert(s.messages[#s.messages]:find("8 imported, 0 already present, 0 unavailable", 1, true))
end)

test("unavailable dungeons are reported and can be imported after retry", function()
    local s, H = setupBundles()
    local idx = s.bundleIndices[2]
    local saved = s.db.presets[idx]
    s.db.presets[idx] = nil
    H:ImportBundledRoutes()
    s:flush()
    assert(not H._bundledImportPending)
    assert(s.messages[#s.messages - 1]:find("7 imported, 0 already present, 1 unavailable", 1, true))
    s.db.presets[idx] = saved
    H:ImportBundledRoutes()
    assert(s.messages[#s.messages]:find("1 imported, 7 already present, 0 unavailable", 1, true))
end)

test("unavailable MDT data times out with a retryable error", function()
    local s, H = setupBundles()
    s.db.presets = nil
    H:ImportBundledRoutes()
    s:flush()
    assert(not H._bundledImportPending)
    assert(s.messages[#s.messages]:find("Could not load MDT routes", 1, true))
end)

test("legacy manual import refreshes the dropdown without firing selection", function()
    local s, H = setupBundles()
    _G.MDT = { GetDB = function() return s.db end, main_frame = MDTFrame }
    _G.MythicDungeonToolsAPI = nil
    _G.MDTFrame = nil
    H:ImportBundledRoutes()
    assert(s.labels[2] and s.selection == 1 and not s.fired)
    assert(s.messages[#s.messages]:find("8 imported, 0 already present", 1, true))
end)

realPrint(string.format("%d compatibility tests passed", passed))
