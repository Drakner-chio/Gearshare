-- GearShare: drops and the group's verdict on them.
--
-- A drop turns up three ways: a need/greed roll starts (START_LOOT_ROLL),
-- someone in the group asks for a rating (/gs check), or a verdict arrives
-- from someone else for an item I haven't seen. Each time I rate it for
-- myself (Gear.Evaluate) and send my verdict to the group; the window lists
-- everyone's verdicts, the biggest upgrade first.
--
-- Drops are told apart by item ID, random suffix and bonus IDs: the same in
-- every player's client, unlike the rest of an item string (which holds the
-- player's own level and spec).

local ADDON, ns = ...
local L = ns.L
local Loot = {}
ns.Loot = Loot

Loot.drops = {}     -- newest first
Loot.byKey = {}

local MAX_DROPS = 20

---------------------------------------------------------------------------
-- Item strings
---------------------------------------------------------------------------
local function Fields(itemString)
    local f = {}
    for v in (itemString .. ":"):gmatch("(.-):") do f[#f + 1] = v end
    return f   -- f[1] = "item", f[2] = itemID, f[8] = suffix, f[14] = bonus count
end

function Loot.ItemStringOf(link)
    if not link then return nil end
    return link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)")
end

-- The item string with what differs per player (unique ID, level, spec) left
-- out, so it's the same in everyone's client
function Loot.Normalize(itemString)
    local f = Fields(itemString)
    for i = 9, 11 do if f[i] then f[i] = "" end end
    local s = table.concat(f, ":")
    return (s:gsub(":+$", ""))
end

function Loot.Key(itemString)
    local f = Fields(itemString)
    local id, suffix = f[2] or "0", f[8] or ""
    local bonus = {}
    local n = tonumber(f[14] or "") or 0
    for i = 1, n do bonus[#bonus + 1] = f[14 + i] or "" end
    return id .. ":" .. (suffix ~= "" and suffix or "0") .. ":" .. table.concat(bonus, ",")
end

local function LinkFor(itemString)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return nil end
    local _, link = info(itemString)
    return link
end

---------------------------------------------------------------------------
-- The list of drops
---------------------------------------------------------------------------
local function Prune()
    local keep = ((ns.db and ns.db.keepMinutes) or 15) * 60
    local now = ns.Now()
    for i = #Loot.drops, 1, -1 do
        local d = Loot.drops[i]
        if i > MAX_DROPS or now - d.time > keep then
            Loot.byKey[d.key] = nil
            table.remove(Loot.drops, i)
        end
    end
end

-- Finds or makes the drop for an item string (and a link, when there is one)
function Loot.Get(itemString, link)
    itemString = Loot.Normalize(itemString)
    local key = Loot.Key(itemString)
    local d = Loot.byKey[key]
    if d then
        if link and not d.ownLink then d.link, d.ownLink = link, true end
        return d, false
    end
    d = { key = key, itemString = itemString, link = link or LinkFor(itemString), ownLink = link and true,
        time = ns.Now(), results = {} }
    Loot.byKey[key] = d
    table.insert(Loot.drops, 1, d)
    Prune()
    return d, true
end

local function Refresh()
    if ns.LootWindow and ns.LootWindow.Refresh then ns.LootWindow:Refresh() end
end

-- Item quality (0 grey … 4 epic …), nil until the game has sent the item
function Loot.Quality(d)
    if d.quality then return d.quality end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local _, _, q = info(d.link or d.itemString)
        d.quality = tonumber(ns.Plain(q))
    end
    return d.quality
end

-- Is a drop listed in my window? Drops below the quality set in the settings
-- are still rated and answered (the others' windows wait for my verdict),
-- they just don't show up here. What I asked about myself always shows.
function Loot.Visible(d)
    if d.askedBy == ns.Me() or d.demo then return true end
    local q = Loot.Quality(d)
    if not q then return false end
    return q >= ((ns.db and ns.db.minQuality) or 2)
end

function Loot.VisibleDrops()
    local list = {}
    for _, d in ipairs(Loot.drops) do if Loot.Visible(d) then list[#list + 1] = d end end
    return list
end

local function ShowWindow(d)
    if not (ns.db and ns.db.autoShow and ns.LootWindow) then return end
    if d and not Loot.Visible(d) then return end
    if d then d.opened = true end
    ns.LootWindow:Open()
end

---------------------------------------------------------------------------
-- Rating a drop for myself
---------------------------------------------------------------------------
-- Tries until the game has sent the item and Pawn can rate it
function Loot.RateMine(d, send, tries)
    tries = tries or 0
    d.link = d.link or LinkFor(d.itemString)
    local r
    if d.link then
        local ok, res, why = pcall(ns.Gear.Evaluate, d.link, d.canNeed)
        if ok then r = res elseif geterrorhandler then geterrorhandler()(res) end
    end
    if not r then
        if tries < 20 then
            d.rating = true
            ns.After(0.5, function() Loot.RateMine(d, send, tries + 1) end)
        else
            d.rating = nil
        end
        return
    end
    d.rating = nil
    if r.status == "-" then
        -- Not something you wear: nothing to share
        Loot.byKey[d.key] = nil
        for i, x in ipairs(Loot.drops) do if x == d then table.remove(Loot.drops, i) break end end
        Refresh()
        return
    end
    r.time = ns.Now()
    d.results[ns.Me()] = r
    if send then ns.Comm.SendVerdict(d.itemString, r) end
    Refresh()
end

---------------------------------------------------------------------------
-- Where drops come from
---------------------------------------------------------------------------
-- A need/greed roll started
function Loot.OnRoll(rollID)
    local link = GetLootRollItemLink and ns.Plain(GetLootRollItemLink(rollID))
    if not link then return end
    if not ns.Gear.IsGear(link) then return end
    local itemString = Loot.ItemStringOf(link)
    if not itemString then return end
    local d = Loot.Get(itemString, link)
    d.time = ns.Now()
    if GetLootRollItemInfo then
        local _, _, _, quality, _, canNeed = GetLootRollItemInfo(rollID)
        canNeed = ns.Plain(canNeed)
        if canNeed ~= nil then d.canNeed = canNeed and true or false end
        quality = tonumber(ns.Plain(quality))
        if quality then d.quality = quality end
    end
    d.rollID = rollID
    if ns.Wish then ns.Wish.Learn(ns.Gear.ItemID(link)) end
    Loot.RateMine(d, true)
    ShowWindow(d)
    Refresh()
end

-- Someone else's verdict
function Loot:OnVerdict(sender, itemString, r)
    local d, isNew = Loot.Get(itemString)
    r.time = ns.Now()
    d.results[sender] = r
    -- An item I haven't rated yet (I had no roll for it): rate it too
    if not d.results[ns.Me()] and not d.rating then Loot.RateMine(d, true) end
    if not d.opened then ShowWindow(d) end
    Refresh()
end

-- Someone asks the group to rate an item
function Loot:OnCheck(sender, itemString)
    local d = Loot.Get(itemString)
    d.time = ns.Now()
    d.askedBy = sender
    if not d.rating then Loot.RateMine(d, true) end
    ShowWindow(d)
    Refresh()
end

-- /gs check: I ask the group
function Loot:Check(itemString)
    local d = Loot.Get(itemString)
    d.time = ns.Now()
    d.askedBy = ns.Me()
    d.results[ns.Me()] = nil
    -- The question goes out first, my own verdict right after it
    local inGroup = ns.Comm.SendCheck(d.itemString)
    Loot.RateMine(d, inGroup)
    if not inGroup then ns.Print("You're not in a group: only you rated it.") end
    if ns.LootWindow then ns.LootWindow:Open() end
    Refresh()
end

-- Empties the list; an empty loot window has nothing to show, so it closes
function Loot:Clear()
    wipe(Loot.drops)
    wipe(Loot.byKey)
    if ns.LootWindow and ns.LootWindow.Close then ns.LootWindow:Close() end
    Refresh()
end

---------------------------------------------------------------------------
-- The ranking: everyone in the group (and anyone who answered), best first
---------------------------------------------------------------------------
local ORDER = { E = 1, U = 2, S = 3, wait = 4, X = 5, none = 6 }

function Loot.Ranking(d)
    local list, seen = {}, {}
    local function Add(name, r)
        if seen[name] then return end
        seen[name] = true
        local e = { name = name, r = r }
        if r then
            e.kind = ORDER[r.status] and r.status or "S"
        elseif name == ns.Me() or (ns.members[name] and ns.members[name].version) then
            e.kind = "wait"
        else
            e.kind = "none"
        end
        list[#list + 1] = e
    end
    for _, m in ipairs(ns.Roster()) do Add(m.name, d.results[m.name]) end
    for name, r in pairs(d.results) do Add(name, r) end
    if ns.db and ns.db.onlyUsable then
        for i = #list, 1, -1 do
            if list[i].kind == "X" then table.remove(list, i) end
        end
    end
    table.sort(list, function(a, b)
        local oa, ob = ORDER[a.kind] or 9, ORDER[b.kind] or 9
        if oa ~= ob then return oa < ob end
        local pa, pb = a.r and a.r.pct or -1e9, b.r and b.r.pct or -1e9
        if pa ~= pb then return pa > pb end
        return a.name < b.name
    end)
    return list
end

-- "★ BiS" / "★ 2" after a name, for a drop on that player's Naowh BiS list
function Loot.BisTag(r)
    if not r then return "" end
    local star = "|A:auctionhouse-icon-favorite:12:12|a"
    local out = ""
    if r.bis == 1 then
        out = " " .. star .. "|cffff8a1aBiS|r"
    elseif r.bis then
        out = " " .. star .. "|cffc0c4cc" .. L["%d. pick"]:format(r.bis) .. "|r"
    end
    if r.wish then out = out .. " " .. star .. "|cff9d7bff" .. L["wish"] .. "|r" end
    return out
end

-- "+6.1 %", "+12 ilvl", "empty slot" ... for one verdict
function Loot.Describe(r)
    if not r then return "" end
    if r.status == "E" then return L["empty slot"] end
    if r.status == "X" then
        return r.reason == "armor" and L["wrong armor"] or L["can't use"]
    end
    if r.pct and r.pct >= 999 then return L["new stats"] end
    if r.pct then return ("%+.1f %%"):format(r.pct) end
    return ""
end

---------------------------------------------------------------------------
-- Post the ranking in group chat
---------------------------------------------------------------------------
function Loot:Announce(d)
    local channel = ns.GroupChannel()
    if not channel then ns.Print("You're not in a group.") return end
    local parts = {}
    for _, e in ipairs(Loot.Ranking(d)) do
        if e.kind == "E" or e.kind == "U" then
            local bis = e.r.bis == 1 and " (BiS)" or (e.r.bis and (" (BiS #" .. e.r.bis .. ")")) or ""
            if e.r.wish then bis = bis .. " (" .. L["wish"] .. ")" end
            parts[#parts + 1] = e.name:gsub("%-.*$", "") .. bis .. " " .. Loot.Describe(e.r)
        end
    end
    local body = #parts > 0 and table.concat(parts, ", ") or L["no upgrade for anyone"]
    local text = "GearShare: " .. (d.link or d.itemString) .. " – " .. body
    if #text > 255 then text = text:sub(1, 252) .. "..." end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok = pcall(send, text, channel)
    if not ok then ns.Print("The game didn't let the message through. Try again out of combat.") end
end

---------------------------------------------------------------------------
-- /gs test: a made-up drop with made-up members, to see the window
---------------------------------------------------------------------------
Loot.DEMO_ITEM = "item:7719"   -- Raging Berserker's Helm
function Loot:Demo()
    local fake = {
        { "Thrall", "SHAMAN", { status = "U", pct = 8.4, ilvl = 6, scale = "Enhancement" } },
        { "Varian", "WARRIOR", { status = "U", pct = 3.2, ilvl = 3, scale = "Arms" } },
        { "Jaina", "MAGE", { status = "X", reason = "armor" } },
        { "Anduin", "PRIEST", { status = "S", pct = -4.0, ilvl = -2, scale = "Holy" } },
    }
    local d = Loot.Get(Loot.DEMO_ITEM)
    d.demo = true
    d.time = ns.Now()
    for _, f in ipairs(fake) do
        local m = ns.Comm.Member(f[1])
        m.class, m.demo, m.version = f[2], true, ns.VERSION
        f[3].time = ns.Now()
        d.results[f[1]] = f[3]
    end
    Loot.RateMine(d, false)
    if ns.LootWindow then ns.LootWindow:Open() end
    Refresh()
end

ns.On("START_LOOT_ROLL", function(rollID) Loot.OnRoll(rollID) end)
ns.On("GET_ITEM_INFO_RECEIVED", function()
    for _, d in ipairs(Loot.drops) do
        if not d.link then d.link = LinkFor(d.itemString) end
        -- its quality is known now: open the window if it's a drop worth showing
        if not d.opened and not d.demo and Loot.Visible(d) then ShowWindow(d) end
    end
    Refresh()
end)
