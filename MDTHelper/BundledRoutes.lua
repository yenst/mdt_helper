local _, H = ...

-- Community MDT2 exports supplied by the addon maintainer and sourced from
-- Keystone.guru. These are one-time seeds: a route is never replaced, and
-- deleting a seeded route does not make it reappear. The matching route is
-- selected on dungeon entry only when the active preset has no route.
local routes = {
    {
        id = "midnight-s2-murder-row-v1",
        dungeonIdx = 160,
        encoded = [[!~MDT2~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]],
    },
    {
        id = "midnight-s2-altar-of-fangs-v1",
        dungeonIdx = 164,
        encoded = [[!~MDT2~TZJbT9swHMXxJY6ba0tbaY/wAVYRysr6iKAwKFrZ2CbtCbWNXbK5yZQLK3siSYs0aZ+CdTDtYZ9uvM9BUPXBsqxzfuf4L/vuIBh8YsM4ym92/Psdd9ZptV42tvefOy2nsQ3ue8fvT9+tiX4Urw2CKFp/cjkbm40t6dpuNtrg/vjB9SURYs1ZWJqbD5ZNp914AZctrfUj1+PcGyYivqztfWXs80rnoi8S9vvNMAlD5sd7iT9igX/oTp7NDyMm5A29wL/qPsonMgYcxIyNPX+00g09Hvc4j1gcXXWKiujHLUgBmSmEQqB+JyotYQAVpKVAz8uV1c4wEEG4z3mTcf4LpJDkJYTVrK7rea1efZQLsc3mIEUkM3T1erVi2aaxxDaZZCVWq2oZgiQzrQXZluyNlYKFmw+abA6vy5YNATJSgHK5LxUV6lTBKjFSiFK81NJmdzA3Dd2WUKbpRorqGYAVuZZwzudoapiWXUqBOQMQYWUR0S6qlWspytFpCs2pplv2Ai7wOcnKtjldrVbK2qK87xT1tyAjipnV6jTF1RSUl2YqyBPms/HlThR5I38snya6BTOVUqqiPwBDgigmGtaJQU1sERuQv0CRg2MMFEwIRSWiY4OYxMI2LhN6Aymm2pTKBCOXKb3HBz9NBoJdMAH2YjaJe0x48bckPOuLuB+eObtj1/v5moeMnQfCPQo8n7n/Xj2dweGAjRJPyK8CdhPP7W68Pf8gPsaTSffgPw==]],
    },
    {
        id = "midnight-s2-den-of-nalorakk-v1",
        dungeonIdx = 161,
        encoded = [[!~MDT2~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]],
    },
    {
        id = "midnight-s2-the-blinding-vale-v1",
        dungeonIdx = 162,
        encoded = [[!~MDT2~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]],
    },
    {
        id = "midnight-s2-voidscar-arena-v1",
        dungeonIdx = 163,
        encoded = [[!~MDT2~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]],
    },
    {
        id = "midnight-s2-ruby-life-pools-v1",
        dungeonIdx = 42,
        encoded = [[!~MDT2~nZdLb9tGEMdDiiL1cuNXWh83pxZFzPIpkoceXFt2HaeNCydAegoocSmxpkiVD9nupaESwwH6BXq1m0db9KP1WN07u7JlByjQpQUI2J+4M//hzM6s/X4n7v6Ae1n6+mLDO6ty3HRboZ9Ppxvhr391LE2R1e113W7LOoAqWwQU2WEHQzYALIMZNi3NhGXbZliCYVtuE9DKgC1rAGb7FqDKZlkwzPKgO2Vg9nK6XgZ02dha1zWLZalQQ6hrmxlUS3YAVLMMmPTgKE4ZMKioopcDONSaY90CNFljB52IXjlgA3graxaoygyqSprnyhsLbILoZZgsS2dmpv7vEg6BJuskMND6r5Hy9/VIMWSLnkkKtC6MoGu0ljBfdHawKVg2qQsjGHBmoAOsNsMSGp4EaNG6s0JbNom5wrCEwUVnHu0TVnBmM08hYowAA5g4MA3ZZgeb9rBhlwCoJJ15GikOK5j0jtDb5YCI6goVLQUa+GEHnfajSu8kVlBoEqH9DWawzNkco83DCqpsk/60SwBcruas/0vAbI7ZFkk8I5jWDFSSEFZQSdtpls2wNOhdoUE+dGYg5gTobGUFi879cnALnatAdZJwVrDISNYspwSYyizhJo2AEehwI2BdbETTDe90y5nVDbZp3PTRo6cHT9AoD0Ok3r/c0VEthciq8IeAzk2fffaVG2SoN3CTPk5REGUxOnLBwD1yT5CfxEN0NMDhKJ3ba7Y2U9VlB+y7B5nbOwQRzwtx+gB1ibssTiLXi2846Scj1MWDIPLQKAhDN0FpjBI36mMP9dwIvmmGjoJsEOcZGrjjIOqDFzSMx1i+Um7DHQzKBgwNnb/5cuY8OMvU6JXbtmSbnz77+eAwGM3dBtE4SL9IB0mceyhI0ShO06AbYtSFh8OgP8hQgn/MgwRDCoKMhODHCYpHWTB0QzRysyQOiRU8iyO58TTFH/qEgN1xHHhX5vOwdJLzzjo0vAFRfXmjLAoChZC8fBeieYA8PMKRR6TjCIEuTpBLcpZgHyc46uH7D73A94NeHmYnq1tHGB/e6YzdMMe/f9fLE9iSbeWQ1Tja9Y7XPt9NcQj/bUC4L/YuH++DLreTYTwElTt7SeBnj30/xVn6okNiSn95yxUcf1rnKrxQOa1xYlUQJlyl04vDONn2fR37/nuu4PmXUk2sFHXhlSTWa9WXa8qauqaJBXe5k+xz8IU0/4GY6vhNs+AaE7HSmvDXOx3Y+7ZZ8AsF35gI1dak0pgb+V0wakw4vlmAkVC74Z4+kBrNQmhNxPoNGdC9+0Egvv9u6Yy8UVX8eBl8tQpp8YzjK0KjXm0U16YOEVt6fa/ZWpBq9cZKwS1OatLcEXH1ZrXgls4WV1fuLn/0yb25iqsS4X0c4eHJBhysfjSEbKd/cpNajT8XJOEdJ1YEUZDEGleviIXU+IMTIcOCAAkWRcih1BCar2rwaZ1L4sI5Ly2D6UpRe3xZuYMcDusYh9xWho+zb3AYZD/lyfMkHD1XN4de8Nu3foLxIA69h3EQYe+fr6+Y2+3ifh6EUHFuMw+8PSWN9zvfR8fHezv/Ag==]],
    },
    {
        id = "midnight-s2-kings-rest-v1",
        dungeonIdx = 17,
        encoded = [[!~MDT2~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]],
    },
    {
        id = "midnight-s2-temple-of-sethraliss-v1",
        dungeonIdx = 20,
        encoded = [[!~MDT2~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]],
    },
}

local MDT2_PREFIX = "!~MDT2~"

local function DecodeRoute(encoded)
    local legacy = rawget(_G, "MDT")
    if legacy and legacy.StringToTable then
        local ok, preset = pcall(legacy.StringToTable, legacy, encoded, true)
        return ok and preset or nil
    end

    if type(encoded) ~= "string" or encoded:sub(1, #MDT2_PREFIX) ~= MDT2_PREFIX then return nil end
    if not C_EncodingUtil or not Enum or not Enum.CompressionMethod then return nil end

    local ok, preset = pcall(function()
        local decoded = C_EncodingUtil.DecodeBase64(encoded:sub(#MDT2_PREFIX + 1))
        if not decoded then return nil end
        local decompressed = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
        if not decompressed then return nil end
        return C_EncodingUtil.DeserializeCBOR(decompressed)
    end)
    return ok and preset or nil
end

local function IsValidPreset(preset, expectedDungeonIdx)
    return type(preset) == "table"
        and type(preset.text) == "string"
        and type(preset.value) == "table"
        and preset.value.currentDungeonIdx == expectedDungeonIdx
        and type(preset.value.pulls) == "table"
end

local function AlreadyPresent(presets, preset, seedID)
    for _, existing in pairs(presets) do
        if type(existing) == "table" then
            if existing.mdtHelperSeedID == seedID then return true end
            if preset.uid and existing.uid == preset.uid then return true end
            if existing.text == preset.text then return true end
        end
    end
    return false
end

local function InsertWithoutSelecting(db, dungeonIdx, preset)
    local presets = db.presets and db.presets[dungeonIdx]
    if type(presets) ~= "table" then return false end

    local insertAt = #presets + 1
    if presets[#presets] and presets[#presets].value == 0 then insertAt = #presets end
    table.insert(presets, insertAt, preset)

    -- Preserve the selected preset even in the unusual case where MDT's
    -- <New Preset> sentinel was selected.
    local selected = db.currentPreset and db.currentPreset[dungeonIdx]
    if selected and selected >= insertAt then db.currentPreset[dungeonIdx] = selected + 1 end
    return true
end

local function FindBundledRoutePreset(db, route)
    local presets = db.presets and db.presets[route.dungeonIdx]
    if type(presets) ~= "table" then return nil end

    local bundledPreset = DecodeRoute(route.encoded)
    if not IsValidPreset(bundledPreset, route.dungeonIdx) then return nil end

    for presetIdx, preset in ipairs(presets) do
        if type(preset) == "table" and preset.value ~= 0 then
            if preset.mdtHelperSeedID == route.id
                or (bundledPreset.uid and preset.uid == bundledPreset.uid)
                or preset.text == bundledPreset.text then
                return presetIdx
            end
        end
    end
    return nil
end

local function HasRoutedEnemies(preset)
    local pulls = type(preset) == "table"
        and type(preset.value) == "table"
        and preset.value.pulls
    if type(pulls) ~= "table" then return false end

    for _, pull in pairs(pulls) do
        if type(pull) == "table" then
            for enemyIdx, clones in pairs(pull) do
                if type(enemyIdx) == "number" and type(clones) == "table" and next(clones) then
                    return true
                end
            end
        end
    end
    return false
end

function H:SelectBundledRoute(dungeonIdx)
    local mdtDB = self:GetMDTDB()
    if not mdtDB or type(mdtDB.currentPreset) ~= "table" then return false, false end

    local route
    for _, candidate in ipairs(routes) do
        if candidate.dungeonIdx == dungeonIdx then
            route = candidate
            break
        end
    end
    if not route then return false, false end

    -- A bundled route is only a fallback. Never replace the player's active
    -- choice when that preset already contains a routed enemy.
    local dungeonPresets = mdtDB.presets and mdtDB.presets[dungeonIdx]
    local currentPresetIdx = mdtDB.currentPreset[dungeonIdx]
    local currentPreset = dungeonPresets and currentPresetIdx and dungeonPresets[currentPresetIdx]
    if HasRoutedEnemies(currentPreset) then return true, false end

    local presetIdx = FindBundledRoutePreset(mdtDB, route)
    if not presetIdx then return false, false end
    if mdtDB.currentPreset[dungeonIdx] == presetIdx then return true, false end

    mdtDB.currentPreset[dungeonIdx] = presetIdx
    if mdtDB.currentDungeonIdx == dungeonIdx then
        local legacy = rawget(_G, "MDT")
        if legacy then
            if legacy.UpdatePresetDropDown then pcall(legacy.UpdatePresetDropDown, legacy) end
            if legacy.UpdateMap then pcall(legacy.UpdateMap, legacy) end
        else
            -- Modern MDT keeps its implementation private, but its visible
            -- AceGUI dropdown exposes the same callback used by a player click.
            local frame = rawget(_G, "MDTFrame")
            local group = frame and frame.sidePanel and frame.sidePanel.WidgetGroup
            local dropdown = group and group.PresetDropDown
            if dropdown then
                if dropdown.SetValue then dropdown:SetValue(presetIdx) end
                if dropdown.Fire then dropdown:Fire("OnValueChanged", presetIdx) end
            end
        end
    end
    return true, true
end

function H:SeedBundledRoutes()
    if not self.db then return false end
    self.db.bundledRouteSeeds = self.db.bundledRouteSeeds or {}

    local mdtDB = self:GetMDTDB()
    if not mdtDB or type(mdtDB.presets) ~= "table" then return false end

    local added = 0
    for _, route in ipairs(routes) do
        if not self.db.bundledRouteSeeds[route.id] then
            local preset = DecodeRoute(route.encoded)
            local dungeonPresets = mdtDB.presets[route.dungeonIdx]
            if IsValidPreset(preset, route.dungeonIdx) and type(dungeonPresets) == "table" then
                if not AlreadyPresent(dungeonPresets, preset, route.id) then
                    preset.mdtHelperSeedID = route.id
                    if InsertWithoutSelecting(mdtDB, route.dungeonIdx, preset) then added = added + 1 end
                end
                self.db.bundledRouteSeeds[route.id] = true
            end
        end
    end

    if added > 0 then
        print(("|cff00ccffMDTHelper|r: Added %d bundled community routes to MDT; existing routes were unchanged."):format(added))
    end
    return true
end

-- Seed as soon as MDT's UI/data layer becomes available, without forcing that
-- load at login. The normal dungeon sync also calls SeedBundledRoutes as a
-- fallback for MDT versions that do not expose UI initializers.
local api = rawget(_G, "MythicDungeonToolsAPI")
if api and api.RegisterUIInitializer then
    api:RegisterUIInitializer(function()
        C_Timer.After(0, function()
            if H.db then H:SeedBundledRoutes() end
        end)
    end)
elseif rawget(_G, "MDT") then
    C_Timer.After(0, function()
        if H.db then H:SeedBundledRoutes() end
    end)
end
