-- Run from the repository root: lua tests/ui_locale_test.lua
-- Exercise real settings and route layout; does not emulate WoW font rendering.
local objects = {}
local methods = {}
local function newObject(parent)
    local obj = setmetatable({ parent = parent, shown = true, scripts = {}, width = 0, height = 0 }, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            if key:match('^Set') or key:match('^Enable') or key:match('^Register')
                or key:match('^Clear') or key:match('^Add') then return function() end end
        end,
    })
    objects[#objects + 1] = obj
    return obj
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetText(text) self.text = text end
function methods:GetText() return self.text end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return 'TOPLEFT', nil, 'TOPLEFT', 0, 0 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:GetFrameLevel() return 1 end
function methods:GetScale() return 1 end
function methods:GetChecked() return self.checked end
methods.CreateFontString = newObject
methods.CreateTexture = newObject
methods.CreateMaskTexture = newObject
methods.GetHighlightTexture = newObject

local function setup(locale)
    objects = {}
    _G.GetLocale = function() return locale end
    _G.CreateFrame = function(_, name, parent, template)
        local obj = newObject(parent)
        if name then _G[name] = obj end
        if template == 'OptionsSliderTemplate' then
            obj.Low, obj.High, obj.Text = newObject(obj), newObject(obj), newObject(obj)
        end
        return obj
    end
    _G.UIParent = newObject()
    UIParent:SetSize(1920, 1080)
    _G.STANDARD_TEXT_FONT = 'client-font'
    _G.SlashCmdList = {}
    _G.tinsert = table.insert
    _G.UISpecialFrames = {}
    _G.C_Timer = { After = function(_, callback) callback() end }
    _G.Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
    local H = {}
    assert(loadfile('MDTHelper/Locales.lua'))('MDTHelper', H)
    assert(loadfile('MDTHelper/Core.lua'))('MDTHelper', H)
    assert(loadfile('MDTHelper/RouteGuide.lua'))('MDTHelper', H)
    assert(loadfile('MDTHelper/Settings.lua'))('MDTHelper', H)
    H.activeDungeon = true
    H.totalForcesRequired = 300
    for i = 1, 3 do
        H.pulls[i] = { totalForces = 100, enemies = {
            { name = 'Enemy A', numClones = 2, forces = 25 },
            { name = 'Enemy B', numClones = 2, forces = 25 },
        } }
    end
    return H
end

local function findText(text)
    for _, obj in ipairs(objects) do if obj.text == text then return obj end end
    error('Missing text: ' .. text)
end

for _, locale in ipairs({ 'enUS', 'zhCN', 'deDE' }) do
    local H = setup(locale)
    local chinese = locale == 'zhCN'
    assert(H.L['Compact Mode'] == (chinese and '紧凑模式' or 'Compact Mode'))
    assert(H.L['Untranslated fallback'] == 'Untranslated fallback')
    -- Verify all substitutions and color codes survive translation.
    local function tokens(text, pattern)
        local result = {}
        for token in text:gmatch(pattern) do result[#result + 1] = token end
        return table.concat(result, ',')
    end
    for key, value in pairs(H.L) do
        assert(tokens(key, '%%[%d%.]*[dsf%%]') == tokens(value, '%%[%d%.]*[dsf%%]'), key)
        assert(tokens(key, '|c%x%x%x%x%x%x%x%x') == tokens(value, '|c%x%x%x%x%x%x%x%x'), key)
    end
    H:_DoUpdateUI()
    local plannedPercent = findText('33.3%')
    H.totalForcesGained = 30
    H.livePullPercent = 5
    H:UpdatePullForcesDisplay()
    assert(plannedPercent.text == '33.3%', 'combat must preserve the planned pull target')
    findText('30/300  10%  |cFFFFCC00+5.0%|r')
    H:_DoUpdateUI()
    assert(plannedPercent.text == '33.3%', 'full refresh must also preserve the target in combat')
    H.livePullPercent = 0
    H:_DoUpdateUI()
    assert(plannedPercent.text == '33.3%', 'planned target must remain visible after combat')
    local expandedHeight = MDTHelperGuide:GetHeight()
    local mobName = findText('Enemy A')
    assert(mobName:IsVisible())
    findText(chinese and '第 1 / 3 波 |r' or 'Pull 1 / 3 |r')
    local checkbox = findText(H.L['Compact Mode']).parent
    checkbox.checked = true
    checkbox.scripts.OnClick(checkbox)
    assert(H.db.compactMode and not mobName:IsVisible())
    assert(MDTHelperGuide:GetHeight() < expandedHeight)
    local fullCompactHeight = MDTHelperGuide:GetHeight()
    local current = findText('1').parent
    assert(current:IsVisible() and current._bg.color[1] == 0.18)
    H.db.minimized = true
    H:_DoUpdateUI()
    assert(MDTHelperGuide:GetHeight() < fullCompactHeight and not mobName:IsVisible())
    H:AdvancePull()
    assert(H.currentPullIdx == 2 and not mobName:IsVisible())
    checkbox.checked = false
    checkbox.scripts.OnClick(checkbox)
    assert(not H.db.compactMode and mobName:IsVisible())
    _G.hooksecurefunc = function(object, method, hook)
        local original = object[method]
        object[method] = function(...)
            original(...)
            hook(...)
        end
    end
    assert(loadfile('MDTHelper/MapPopout.lua'))('MDTHelper', H)
    local mapOnlyCheckbox = findText(H.L['Map Only']).parent
    assert(H.db.mapOnly == false, 'map-only mode must be opt-in')
    -- Keep the real visibility hook; isolate map rendering from these layout tests.
    -- Map rendering expects MDT textures and scroll geometry supplied by the game.
    H.dungeonIdx = nil
    local mapShow = MDTHelperMapPopout.Show
    local showCount = 0
    MDTHelperMapPopout.Show = function(self)
        showCount = showCount + 1
        mapShow(self)
    end
    mapOnlyCheckbox.checked = true
    mapOnlyCheckbox.scripts.OnClick(mapOnlyCheckbox)
    assert(H.db.mapOnly and H.db.mapPopout and not MDTHelperGuide:IsShown())
    assert(showCount > 0, 'map-only mode must open the map through the UI hook')
    local currentPull = H.currentPullIdx
    H:AdvancePull()
    assert(H.currentPullIdx == currentPull + 1 and not MDTHelperGuide:IsShown(),
        'navigation must continue with the guide hidden')
    _G.strlower = string.lower
    _G.strtrim = function(value) return value:match('^%s*(.-)%s*$') end
    SlashCmdList.MDTHELPER('maponly')
    assert(not H.db.mapOnly and MDTHelperGuide:IsShown(), 'command must restore the guide')
    SlashCmdList.MDTHELPER('maponly')
    assert(H.db.mapOnly and not MDTHelperGuide:IsShown(), 'command must hide the guide')
    mapOnlyCheckbox.checked = false
    mapOnlyCheckbox.scripts.OnClick(mapOnlyCheckbox)
    assert(not H.db.mapOnly and MDTHelperGuide:IsShown(), 'settings must restore the guide')
    H.db.mapPopout = true
    H.dungeonIdx = 1
    MDTHelperMapPopout:Show()
    H.db.enabled = false
    H:_DoUpdateUI()
    assert(not MDTHelperGuide:IsShown() and not MDTHelperMapPopout:IsShown(),
        'disabling the addon must hide both the guide and the map')
    H:_DoUpdateUI()
    assert(not MDTHelperMapPopout:IsShown(), 'refresh must not reopen a disabled map')
    print('PASS layout, settings toggle, advancement, and localization: ' .. locale)
end
