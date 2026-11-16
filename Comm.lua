-- GearShare: talking to the rest of the group with addon messages.
--
-- Messages (prefix "GearShare", fields split by ^):
--   H^<protocol>^<version>          hello: I'm here, please send your gear
--   G^<slot>:<itemID>:<ilvl>:<score>;...   (part of) my gear; score is my best
--                                   Pawn score for the item, empty without Pawn
--   E^<item>^<status>^<pct>^<ilvl>^<scale>^<reason>^<bis>^<wish>   my verdict on a drop
--                                   (bis: its rank on my Naowh BiS list; wish: 1 when on my
--                                   wishlist; both empty when not)
--   C^<item>                        please rate this item (/gs check)
-- <item> is an item string ("item:12345:..."), never a full link.
--
-- Midnight doesn't let addons send messages at all times (in combat in
-- instances, for one), so everything goes through a queue that waits until
-- leaving combat and tries again when the game refuses a message.

local ADDON, ns = ...
local Plain = ns.Plain
local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "GearShare"
Comm.PROTOCOL = 1
local MAX_LEN = 250
local SEP = "^"

ns.members = ns.members or {}   -- [name] = { version, gear = { [slot] = { itemID, ilvl, score } }, gearTime }

local function Member(name)
    local m = ns.members[name]
    if not m then
        m = { gear = {} }
        ns.members[name] = m
    end
    return m
end
Comm.Member = Member

local function Clean(s, maxLen)
    s = tostring(s or ""):gsub("[%^%c|]", "")
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function Split(text)
    local out = {}
    for field in (text .. SEP):gmatch("(.-)%" .. SEP) do out[#out + 1] = field end
    return out
end
Comm.Split = Split

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local queue = {}
local busy = false

local function SendNow(text, channel)
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if not send then return true end
    local ok, res = pcall(send, Comm.PREFIX, text, channel)
    if not ok then return false end
    -- Older clients return nothing, newer ones true or a result code (0 = sent)
    return res == nil or res == true or res == 0
end

local function Pump()
    if #queue == 0 then busy = false return end
    busy = true
    if InCombatLockdown and InCombatLockdown() then
        -- PLAYER_REGEN_ENABLED starts the pump again
        busy = false
        return
    end
    local channel = ns.GroupChannel()
    if not channel then wipe(queue); busy = false return end
    local msg = queue[1]
    if SendNow(msg.text, channel) then
        table.remove(queue, 1)
        ns.After(0.2, Pump)
    else
        msg.tries = (msg.tries or 0) + 1
        if msg.tries > 30 then table.remove(queue, 1) end
        ns.After(1.5, Pump)
    end
end

-- kind: messages of the same kind and key replace an older one still waiting
function Comm.Queue(text, kind, key)
    if #text > 255 then return end
    if kind then
        for i = #queue, 1, -1 do
            if queue[i].kind == kind and queue[i].key == key then table.remove(queue, i) end
        end
    end
    queue[#queue + 1] = { text = text, kind = kind, key = key }
    if not busy then Pump() end
end
Comm.queue = queue

function Comm.SendHello()
    if not ns.GroupChannel() then return end
    Comm.Queue(table.concat({ "H", Comm.PROTOCOL, Clean(ns.VERSION, 20) }, SEP), "H")
    Comm.SendGear()
end

-- My gear in as few messages as fit
function Comm.GearMessages(snapshot)
    local msgs, parts, len = {}, {}, 2
    for _, e in ipairs(snapshot) do
        local part = ("%d:%d:%d:%s"):format(e.slot, e.itemID or 0, math.floor((e.ilvl or 0) + 0.5),
            e.score and ("%.1f"):format(e.score) or "")
        if len + #part + 1 > MAX_LEN then
            msgs[#msgs + 1] = "G" .. SEP .. table.concat(parts, ";")
            parts, len = {}, 2
        end
        parts[#parts + 1] = part
        len = len + #part + 1
    end
    if #parts > 0 then msgs[#msgs + 1] = "G" .. SEP .. table.concat(parts, ";") end
    return msgs
end

function Comm.SendGear()
    if not ns.GroupChannel() then return end
    for i, text in ipairs(Comm.GearMessages(ns.Gear.Snapshot())) do
        Comm.Queue(text, "G", i)
    end
end

function Comm.SendVerdict(itemString, r)
    if not ns.GroupChannel() then return end
    local pct = r.pct and ("%.1f"):format(r.pct) or ""
    local text = table.concat({ "E", itemString, r.status or "", pct,
        r.ilvl and tostring(math.floor(r.ilvl + 0.5)) or "", Clean(r.scale, 30), Clean(r.reason, 10),
        r.bis and tostring(r.bis) or "", r.wish and "1" or "" }, SEP)
    Comm.Queue(text, "E", itemString)
end

function Comm.SendCheck(itemString)
    if not ns.GroupChannel() then return false end
    Comm.Queue("C" .. SEP .. itemString, "C", itemString)
    return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local lastGearAnswer = 0

function Comm.Receive(text, sender)
    text, sender = Plain(text), ns.SenderKey(Plain(sender))
    if not text or not sender or sender == ns.Me() then return end
    local f = Split(text)
    local kind = f[1]
    local m = Member(sender)
    m.seen = ns.Now()

    if kind == "H" then
        m.version = f[3]
        -- Answer with my gear (once for a burst of hellos)
        if ns.Now() - lastGearAnswer > 3 then
            lastGearAnswer = ns.Now()
            ns.After(math.random and (0.5 + math.random() * 1.5) or 1, Comm.SendGear)
        end
    elseif kind == "G" then
        for entry in (f[2] or ""):gmatch("[^;]+") do
            local slot, id, ilvl, score = entry:match("^(%d+):(%d+):(%d+):([%d%.%-]*)$")
            slot = tonumber(slot)
            if slot then
                id = tonumber(id)
                if id and id > 0 then
                    m.gear[slot] = { itemID = id, ilvl = tonumber(ilvl) or 0, score = tonumber(score) }
                else
                    m.gear[slot] = false
                end
            end
        end
        m.gearTime = ns.Now()
        if ns.GroupWindow and ns.GroupWindow.Refresh then ns.GroupWindow:Refresh() end
    elseif kind == "E" then
        local itemString = f[2]
        if not itemString or not itemString:match("^item:%d+") then return end
        ns.Loot:OnVerdict(sender, itemString, {
            status = f[3] ~= "" and f[3] or "?",
            pct = tonumber(f[4]),
            ilvl = tonumber(f[5]),
            scale = f[6] ~= "" and f[6] or nil,
            reason = f[7] ~= "" and f[7] or nil,
            bis = tonumber(f[8] or ""),
            wish = f[9] == "1" and 1 or nil,
        })
    elseif kind == "C" then
        local itemString = f[2]
        if itemString and itemString:match("^item:%d+") then ns.Loot:OnCheck(sender, itemString) end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local knownRoster = {}
local function RosterChanged()
    local now, new = {}, false
    for _, m in ipairs(ns.Roster()) do
        now[m.name] = true
        if not knownRoster[m.name] then new = true end
        local mem = ns.members[m.name]
        if mem then mem.class = m.class end
    end
    -- Forget people who left
    for name in pairs(ns.members) do
        if not now[name] then ns.members[name] = nil end
    end
    knownRoster = now
    if new and ns.GroupChannel() then ns.After(2, Comm.SendHello) end
    if ns.GroupWindow and ns.GroupWindow.Refresh then ns.GroupWindow:Refresh() end
end
Comm.RosterChanged = RosterChanged

local equipPending = false
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if equipPending then return end
    equipPending = true
    ns.After(3, function()
        equipPending = false
        Comm.SendGear()
        if ns.GroupWindow and ns.GroupWindow.Refresh then ns.GroupWindow:Refresh() end
    end)
end)
ns.On("GROUP_ROSTER_UPDATE", RosterChanged)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(4, RosterChanged) end)
ns.On("PLAYER_REGEN_ENABLED", function() if not busy then Pump() end end)
ns.On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if Plain(prefix) ~= Comm.PREFIX then return end
    Comm.Receive(text, sender)
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
end
