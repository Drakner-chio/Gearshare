-- GearShare: the core. Saved settings, events, the group roster, chat output
-- and the slash commands. The parts:
--   Gear.lua         what I wear, and how much a drop would improve it (Pawn)
--   Comm.lua         addon messages to and from the rest of the group
--   Loot.lua         drops, everyone's verdict on them, the ranking
--   LootWindow.lua   the window with the ranking per drop
--   GroupWindow.lua  the overview of everyone's gear, slot by slot

local ADDON, ns = ...
local L, T = ns.L, ns.Theme

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
if ns.VERSION:find("@", 1, true) then ns.VERSION = "dev" end

local DEFAULTS = {
    autoShow = true,       -- open the loot window when something drops
    onlyUsable = false,    -- hide group members who can't use the drop
    keepMinutes = 15,      -- how long a drop stays in the window
    lootScale = 1,         -- size of the loot window
    lootMaxHeight = 600,   -- the loot window grows up to this, then hides older drops
    groupScale = 1,        -- size of the group gear window
    locked = false,        -- windows can't be dragged
    minimapButton = true,
    minimapAngle = 215,
    minQuality = 2,        -- drops from this quality on are listed (2 uncommon, 3 rare, 4 epic)
    source = "auto",       -- rate with: "auto" (Pawn, else Naowh), "pawn", "naowh"
}

---------------------------------------------------------------------------
-- Little helpers
---------------------------------------------------------------------------
function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and L[fmt]:format(...) or L[fmt]
    print(T.CHAT_PREFIX .. ": " .. text)
end

-- Midnight hides some values from addons ("secret values"); treat them as unknown
function ns.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local Plain = ns.Plain

function ns.After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

function ns.Now() return GetTime() end

---------------------------------------------------------------------------
-- Names and the roster. A name is "Name" for my realm, "Name-Realm" otherwise,
-- the same way GetUnitName(unit, true) and Ambiguate(sender, "none") write it.
---------------------------------------------------------------------------
function ns.UnitKey(unit)
    local n = Plain(GetUnitName and GetUnitName(unit, true))
    if not n or n == "" or n == UNKNOWNOBJECT then return nil end
    return n
end

function ns.SenderKey(sender)
    if not sender then return nil end
    if Ambiguate then return Ambiguate(sender, "none") end
    return sender
end

ns.ME = nil
function ns.Me()
    ns.ME = ns.ME or ns.UnitKey("player")
    return ns.ME
end

-- Everyone in the group, me first: { name, unit, class }
function ns.Roster()
    local list = {}
    local me = ns.Me()
    local _, myClass = UnitClass("player")
    list[1] = { name = me, unit = "player", class = Plain(myClass) }
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if n == 0 then return list end
    local prefix, count = raid and "raid" or "party", raid and n or (n - 1)
    for i = 1, count do
        local unit = prefix .. i
        local name = ns.UnitKey(unit)
        if name and name ~= me then
            local _, class = UnitClass(unit)
            list[#list + 1] = { name = name, unit = unit, class = Plain(class) }
        end
    end
    return list
end

function ns.ClassOf(name)
    for _, m in ipairs(ns.Roster()) do if m.name == name then return m.class end end
    local d = ns.members and ns.members[name]
    return d and d.class
end

function ns.ColoredName(name)
    local short = name and name:gsub("%-.*$", "") or "?"
    return "|cff" .. T.ClassHex(ns.ClassOf(name)) .. short .. "|r"
end

-- The channel group messages go to, or nil when alone
function ns.GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

---------------------------------------------------------------------------
-- Events: ns.On("EVENT", fn) — several listeners per event are fine
---------------------------------------------------------------------------
local listeners = {}
local events = CreateFrame("Frame")
ns.eventFrame = events
function ns.On(event, fn)
    if not listeners[event] then
        listeners[event] = {}
        events:RegisterEvent(event)
    end
    table.insert(listeners[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(listeners[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GearShareDB = GearShareDB or {}
    for k, v in pairs(DEFAULTS) do
        if GearShareDB[k] == nil then GearShareDB[k] = v end
    end
    ns.db = GearShareDB
    if ns.OnLoaded then ns.OnLoaded() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
    ns.Print("Commands:")
    print("  /gs  – " .. L["open or close the loot window"])
    print("  /gs gear  – " .. L["the group's gear, slot by slot"])
    print("  /gs check [item]  – " .. L["ask the group to rate an item (shift-click it in)"])
    print("  /gs auto on|off  – " .. L["open the loot window by itself when something drops"])
    print("  /gs clear  – " .. L["empty the loot window"])
    print("  /gs test  – " .. L["a made-up drop with made-up members, to try the window"])
    print("  /gs options  – " .. L["settings: size, minimap button, ..."])
    print("  /gs minimap on|off  – " .. L["show or hide the minimap button"])
end

local function OnOff(arg, current)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not current
end

SLASH_GEARSHARE1 = "/gs"
SLASH_GEARSHARE2 = "/gearshare"
SlashCmdList.GEARSHARE = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns.LootWindow:Toggle()
    elseif cmd == "gear" or cmd == "group" then
        ns.GroupWindow:Toggle()
    elseif cmd == "check" then
        local itemString = rest:match("|H(item:[^|]+)|h") or rest:match("(item:[%-%d:]+)")
        if not itemString then
            local id = tonumber(rest)
            if id then itemString = "item:" .. id end
        end
        if not itemString then
            ns.Print("Shift-click an item into the line: /gs check [item]")
            return
        end
        ns.Loot:Check(itemString)
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.Options:Toggle()
    elseif cmd == "minimap" then
        ns.db.minimapButton = OnOff(rest:lower(), ns.db.minimapButton)
        ns.UpdateMinimapButton()
    elseif cmd == "auto" then
        ns.db.autoShow = OnOff(rest:lower(), ns.db.autoShow)
        ns.Print(ns.db.autoShow and "The loot window opens by itself when something drops." or "The loot window only opens with /gs.")
    elseif cmd == "clear" then
        ns.Loot:Clear()
    elseif cmd == "test" then
        ns.Loot:Demo()
    elseif cmd == "debug" then
        local G = ns.Gear
        local nf = G.NF()
        local sw = nf and nf.StatWeights
        print(T.CHAT_PREFIX .. " debug")
        print("  Pawn: PawnIsReady=" .. tostring(PawnIsReady and PawnIsReady()) .. " PawnGetItemData=" .. tostring(PawnGetItemData ~= nil)
            .. " PawnCommon.Scales=" .. tostring(PawnCommon and PawnCommon.Scales ~= nil) .. " -> " .. tostring(G.HasPawn()))
        if G.HasPawn() then print("  Pawn scales: " .. table.concat(G.Pawn.Scales(), ", ")) end
        print("  Naowh: NaowhForever=" .. type(_G.NaowhForever) .. " kept=" .. tostring(nf ~= nil) .. " StatWeights=" .. tostring(sw ~= nil)
            .. " IsBisItem=" .. tostring(nf and nf.IsBisItem ~= nil) .. " -> " .. tostring(G.HasNaowh()))
        if sw then
            print("  Naowh SW: For=" .. tostring(sw.For ~= nil) .. " ActiveSpec=" .. tostring(sw.ActiveSpec ~= nil) .. " Stats=" .. tostring(sw.Stats ~= nil)
                .. " Worth=" .. tostring(sw.Worth ~= nil) .. " DpsShare=" .. tostring(sw.DpsShare ~= nil))
        end
        local s = G.Scorer()
        print("  rating with: " .. (s and s.key or "item level") .. " (setting " .. tostring(ns.db.source) .. ")")
    elseif cmd == "version" then
        ns.Print("Version %s. Seen in the group:", ns.VERSION)
        for name, d in pairs(ns.members or {}) do
            print("  " .. ns.ColoredName(name) .. "  " .. tostring(d.version or "?"))
        end
    else
        Help()
    end
end

-- Addon list button (the compartment in the minimap corner)
-- Clicks on the minimap button and the addon list button
function ns.HandleClick(button)
    if button == "MiddleButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
        ns.Options:Toggle()
    elseif button == "RightButton" then
        ns.GroupWindow:Toggle()
    else
        ns.LootWindow:Toggle()
    end
end

function GearShare_OnCompartmentClick(_, button) ns.HandleClick(button) end
