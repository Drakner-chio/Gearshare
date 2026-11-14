-- A small fake of the game's API: enough to load GearShare outside the game
-- and drive it. Frames take any method; the ones the tests look at remember
-- what they were given. (Same idea as Gatherline's tests/wowstub.lua.)

LOG = {}
local realPrint = print
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    LOG[#LOG + 1] = table.concat(t, " ")
end
REAL_PRINT = realPrint

ALL_FRAMES = {}
local Methods = {}
local ADDON_METHODS = { SetHover = true, SetPrimary = true, Restyle = true, SetEdgeColor = true, RestorePosition = true }
local MT = {
    __index = function(obj, k)
        if Methods[k] then return Methods[k] end
        if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
        if ADDON_METHODS[k] then return nil end
        return function() end
    end,
}
local function newObj(kind, name, parent)
    local o = setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {}, __children = {},
        __shown = true, __text = "", __w = 100, __h = 20 }, MT)
    if parent and parent.__children then table.insert(parent.__children, o) end
    if name then _G[name] = o end
    ALL_FRAMES[#ALL_FRAMES + 1] = o
    return o
end

function Methods:CreateTexture() return newObj("Texture", nil, self) end
function Methods:CreateFontString() return newObj("FontString", nil, self) end
function Methods:Show()
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Methods:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.__shown end
function Methods:IsVisible()
    local o = self
    while o do
        if not o.__shown then return false end
        o = o.__parent
    end
    return true
end
function Methods:SetScript(k, fn) self.__scripts[k] = fn end
function Methods:GetScript(k) return self.__scripts[k] end
function Methods:SetText(t) self.__text = t == nil and "" or tostring(t) end
function Methods:GetText() return self.__text end
function Methods:SetFontString(fs) self.__fs = fs end
function Methods:GetStringWidth() return #(self.__text or "") * 6 end
function Methods:SetSize(w, h) self.__w, self.__h = w, h end
function Methods:SetWidth(w) self.__w = w end
function Methods:SetHeight(h) self.__h = h end
function Methods:GetWidth() return self.__w end
function Methods:GetHeight() return self.__h end
function Methods:SetPoint(...) self.__points = self.__points or {} table.insert(self.__points, { ... }) end
function Methods:GetPoint() local p = (self.__points or {})[1] or { "CENTER" } return p[1], nil, p[3] or p[1], p[4] or 0, p[5] or 0 end
function Methods:ClearAllPoints() self.__points = {} end
function Methods:GetName() return self.__name end
function Methods:RegisterEvent(e) self.__events = self.__events or {} self.__events[e] = true end
function Methods:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a } end
function Methods:SetTextColor(r, g, b) self.__textColor = { r, g, b } end
function Methods:SetAlpha(a) self.__alpha = a end

function CreateFrame(kind, name, parent) return newObj(kind, name, parent) end
function Click(b, which)
    assert(b.__scripts.OnClick, "nothing to click")
    b.__scripts.OnClick(b, which or "LeftButton")
end
-- All font strings under a frame, as text (to look for words in a window)
function AllText(f, out)
    out = out or {}
    if f.__kind == "FontString" and f.__shown then out[#out + 1] = f.__text end
    for _, c in ipairs(f.__children) do if c.__shown then AllText(c, out) end end
    return table.concat(out, "\n")
end

UIParent = newObj("Frame", "UIParent")
GameTooltip = newObj("GameTooltip", "GameTooltip")
Minimap = newObj("Frame", "Minimap")
Minimap.__w, Minimap.__h = 140, 140
function Methods:GetCenter() return 500, 400 end
function Methods:GetEffectiveScale() return 1 end
function Methods:SetScale(s) self.__scale = s end
function Methods:SetValue(v)
    self.__value = v
    if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
end
function GetCursorPosition() return 600, 400 end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
SETTINGS_CATEGORIES = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(c) SETTINGS_CATEGORIES[#SETTINGS_CATEGORIES + 1] = c end,
}
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
UNKNOWNOBJECT = "Unknown"
LE_PARTY_CATEGORY_INSTANCE = 2

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(e) error(e, 0) end end
SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return v == SECRET end
function GetLocale() return LOCALE or "enUS" end

FAKE_TIME = 1000
function GetTime() return FAKE_TIME end

-- Timers run when the test says so
TIMERS = {}
C_Timer = { After = function(s, fn) TIMERS[#TIMERS + 1] = { at = FAKE_TIME + s, fn = fn } end }
function RunTimers(seconds)
    local stop = FAKE_TIME + (seconds or 60)
    while true do
        table.sort(TIMERS, function(a, b) return a.at < b.at end)
        local t = TIMERS[1]
        if not t or t.at > stop then break end
        table.remove(TIMERS, 1)
        FAKE_TIME = math.max(FAKE_TIME, t.at)
        t.fn()
    end
    FAKE_TIME = stop
end

IN_COMBAT = false
function InCombatLockdown() return IN_COMBAT end

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
PLAYER = { name = "Alex", class = "WARRIOR" }
GROUP = {}   -- party1.. = { name, class }
function GetUnitName(unit, withRealm)
    if unit == "player" then return PLAYER.name end
    local i = tonumber(unit:match("^party(%d+)$"))
    return i and GROUP[i] and GROUP[i].name
end
function UnitClass(unit)
    if unit == "player" then return PLAYER.class, PLAYER.class end
    local i = tonumber(unit:match("^party(%d+)$"))
    local m = i and GROUP[i]
    if m then return m.class, m.class end
end
function IsInRaid() return false end
function IsInGroup(cat) if cat then return false end return #GROUP > 0 end
function GetNumGroupMembers() return #GROUP > 0 and #GROUP + 1 or 0 end
function Ambiguate(name) return (name:gsub("%-MyRealm$", "")) end

SENT = {}           -- addon messages that went out
SEND_RESULT = 0     -- what SendAddonMessage answers (0 = sent)
CHAT = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel)
        assert(#text <= 255, "addon message too long: " .. #text)
        if SEND_RESULT ~= 0 then return SEND_RESULT end
        SENT[#SENT + 1] = { prefix = prefix, text = text, channel = channel }
        return 0
    end,
}
function SendChatMessage(text, channel) CHAT[#CHAT + 1] = { text = text, channel = channel } end

---------------------------------------------------------------------------
-- Items and what I wear
---------------------------------------------------------------------------
-- ITEMS[id] = { name, equipLoc, ilvl, values = { [scale] = v }, armorOK = bool }
ITEMS = {}
NOT_LOADED = {}     -- [id] = true: the game hasn't sent this item yet
WORN = {}           -- [slot] = item string
DUAL_WIELD = false
function CanDualWield() return DUAL_WIELD end

local function IdOf(link) return link and tonumber(tostring(link):match("item:(%d+)")) end
function MakeLink(itemString)
    local id = IdOf(itemString)
    return "|cffa335ee|H" .. itemString .. "|h[" .. (ITEMS[id] and ITEMS[id].name or "?") .. "]|h|r"
end
C_Item = {
    GetItemInfoInstant = function(link)
        local it = ITEMS[IdOf(link)]
        if not it then return nil end
        return IdOf(link), "Armor", "Misc", it.equipLoc, 1
    end,
    GetItemInfo = function(link)
        local id = IdOf(link)
        local it = ITEMS[id]
        if not it or NOT_LOADED[id] then return nil end
        local itemString = tostring(link):match("(item:[%-%d:]+)")
        return it.name, MakeLink(itemString), 4, it.ilvl
    end,
    GetDetailedItemLevelInfo = function(link)
        local id = IdOf(link)
        if NOT_LOADED[id] then return nil end
        return ITEMS[id] and ITEMS[id].ilvl
    end,
    GetItemIconByID = function() return 134400 end,
}
function GetInventoryItemLink(unit, slot)
    local s = WORN[slot]
    if not s then return nil end
    if NOT_LOADED[IdOf(s)] then return nil end
    return MakeLink(s)
end
function GetInventoryItemID(unit, slot) return IdOf(WORN[slot]) end

ROLLS = {}   -- [rollID] = { itemString, canNeed }
function GetLootRollItemLink(id) return ROLLS[id] and MakeLink(ROLLS[id][1]) end
function GetLootRollItemInfo(id)
    local r = ROLLS[id]
    return 134400, "x", 1, 4, true, r and r.canNeed ~= false
end

---------------------------------------------------------------------------
-- A fake Pawn: values per scale come from ITEMS
---------------------------------------------------------------------------
function InstallPawn(scales)
    PawnIsInitialized = true
    PawnCommon = { Scales = {} }
    for _, s in ipairs(scales) do PawnCommon.Scales[s] = { visible = true } end
    function PawnIsScaleVisible(name) return PawnCommon.Scales[name] and PawnCommon.Scales[name].visible end
    function PawnGetScaleLocalizedName(name) return "Scale " .. name end
    function PawnGetItemData(link)
        local id = IdOf(link)
        if NOT_LOADED[id] or not ITEMS[id] then return nil end
        return { ID = id, Link = link }
    end
    function PawnGetSingleValueFromItem(item, scale)
        local it = ITEMS[item.ID]
        return it.values and it.values[scale] or 0
    end
    function PawnIsArmorBestTypeForPlayer(item) return ITEMS[item.ID].armorOK ~= false end
end
function RemovePawn()
    PawnIsInitialized, PawnCommon, PawnGetItemData, PawnGetSingleValueFromItem = nil, nil, nil, nil
    PawnIsScaleVisible, PawnIsArmorBestTypeForPlayer = nil, nil
end

function FireEvent(event, ...)
    for _, f in ipairs(ALL_FRAMES) do
        if f.__events and f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end

-- Loads the addon's files in .toc order
function LoadAddon(dir)
    local ns = {}
    for line in io.lines(dir .. "/GearShare.toc") do
        if line:match("%.lua%s*$") then
            local chunk = assert(loadfile(dir .. "/" .. line:gsub("%s+$", "")))
            chunk("GearShare", ns)
        end
    end
    return ns
end
