-- GearShare: my wishlist. Items I want, per character, each with where it
-- comes from when that is known (instance and boss, or a profession).
--
-- Ways in:
--   Ctrl+Alt+click on an item wherever the game handles item clicks (bags,
--   chat links, character panel, the game's journal, professions, and loot
--   addons that pass clicks on to the game, like AtlasLoot)
--   the key binding "item under the mouse" (works over every item tooltip,
--   also in addons that keep clicks to themselves, like OneForAll)
--   /gs wish [item]
-- OneForAll's own wishlist (Armory > Gear Planner) counts too, read straight
-- from its saved data; GearShare never writes to it.
--
-- A drop on my wishlist gets a star in everyone's ranking (field "wish" in
-- my verdict). Where an item comes from is taken from the window I add it
-- from, or learned when it drops: the instance, and the boss killed just before.

local ADDON, ns = ...
local L, T = ns.L, ns.Theme
local Plain = ns.Plain
local W = {}
ns.Wish = W

local function Char()
    GearShareCharDB = GearShareCharDB or {}
    GearShareCharDB.wish = GearShareCharDB.wish or {}
    return GearShareCharDB
end

function W.List() return Char().wish end

---------------------------------------------------------------------------
-- OneForAll's wishlist (per character, itemID = true; "ench:..." keys are enchants)
---------------------------------------------------------------------------
function W.OneForAll()
    if ns.db and ns.db.useOneForAll == false then return nil end
    local db = rawget(_G, "OneForAllCharDB")
    local list = type(db) == "table" and db.wishlist
    return type(list) == "table" and list or nil
end

-- "gs" (mine), "ofa" (OneForAll's) or nil
function W.On(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if W.List()[itemID] then return "gs" end
    local ofa = W.OneForAll()
    if ofa and ofa[itemID] then return "ofa" end
    return nil
end

---------------------------------------------------------------------------
-- Where an item comes from
---------------------------------------------------------------------------
-- The game's journal, when it's open on a boss: { instance, boss }
local function FromJournal()
    local ej = rawget(_G, "EncounterJournal")
    if not (ej and ej.IsShown and ej:IsShown()) then return nil end
    local instance, boss
    if ej.instanceID and EJ_GetInstanceInfo then
        local ok, name = pcall(EJ_GetInstanceInfo, ej.instanceID)
        if ok then instance = Plain(name) end
    end
    if ej.encounterID and EJ_GetEncounterInfo then
        local ok, name = pcall(EJ_GetEncounterInfo, ej.encounterID)
        if ok then boss = Plain(name) end
    end
    if instance then return { instance = instance, boss = boss } end
    return nil
end

-- An open profession window: { profession }
local function FromProfession()
    local open = false
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local f = rawget(_G, name)
        if f and f.IsShown and f:IsShown() then open = true end
    end
    if not open then return nil end
    local prof
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" then prof = Plain(info.professionName) end
    end
    if not prof and GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        if ok then prof = Plain(name) end
    end
    if prof and prof ~= "" and prof ~= "UNKNOWN" then return { profession = prof } end
    return nil
end

function W.SourceNow()
    return FromJournal() or FromProfession()
end

-- Learned sources, account-wide: [itemID] = { instance, boss }
local function Learned()
    ns.db.sources = ns.db.sources or {}
    return ns.db.sources
end

function W.SourceOf(itemID)
    local e = W.List()[itemID]
    if e and e.source then return e.source end
    return ns.db and ns.db.sources and ns.db.sources[itemID]
end

-- The last boss killed, to tell where a drop came from
local lastBoss, lastBossTime
ns.On("ENCOUNTER_END", function(_, name, _, _, success)
    if Plain(success) == 1 or Plain(success) == true then
        lastBoss, lastBossTime = Plain(name), ns.Now()
    end
end)

-- A drop seen in an instance: remember where it comes from
function W.Learn(itemID)
    itemID = tonumber(itemID)
    if not (itemID and ns.db) then return end
    local inInstance = IsInInstance and IsInInstance()
    if not inInstance then return end
    local instance = GetInstanceInfo and Plain((GetInstanceInfo()))
    if not instance then return end
    local boss = (lastBossTime and ns.Now() - lastBossTime < 300) and lastBoss or nil
    Learned()[itemID] = { instance = instance, boss = boss }
end

---------------------------------------------------------------------------
-- Adding and removing
---------------------------------------------------------------------------
function W.Add(link, quiet)
    local id = ns.Gear.ItemID(link)
    if not id then return false end
    local equipLoc = ns.Gear.EquipLoc(link)
    local slots = ns.Gear.SlotsFor(equipLoc)
    local source = W.SourceNow()
    if source then Learned()[id] = source end
    W.List()[id] = { slot = slots and slots[1], source = source, added = time and time() or 0 }
    if not quiet then ns.Print("On your wishlist: %s", link) end
    W.Changed()
    return true
end

function W.Remove(itemID, quiet)
    itemID = tonumber(itemID)
    if not (itemID and W.List()[itemID]) then return false end
    W.List()[itemID] = nil
    if not quiet then
        local link = select(2, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(itemID))
        ns.Print("Off your wishlist: %s", link or ("item " .. itemID))
    end
    W.Changed()
    return true
end

function W.Toggle(link)
    local id = ns.Gear.ItemID(link)
    if not id then return end
    if W.List()[id] then W.Remove(id) else W.Add(link) end
end

function W.Changed()
    if ns.WishWindow and ns.WishWindow.Refresh then ns.WishWindow:Refresh() end
    if ns.LootWindow and ns.LootWindow.Refresh then ns.LootWindow:Refresh() end
end

---------------------------------------------------------------------------
-- Ctrl+Alt+click, the key binding, the tooltip line
---------------------------------------------------------------------------
local function WishClick()
    return IsControlKeyDown and IsControlKeyDown() and IsAltKeyDown and IsAltKeyDown()
        and not (IsShiftKeyDown and IsShiftKeyDown())
end

local function HookClicks()
    if not (hooksecurefunc and rawget(_G, "HandleModifiedItemClick")) then return end
    hooksecurefunc("HandleModifiedItemClick", function(link)
        link = Plain(link)
        if type(link) == "string" and link:find("item:", 1, true) and WishClick() then W.Toggle(link) end
    end)
end

-- Key binding: the item in the tooltip under the mouse
function GearShare_WishHovered()
    local link
    if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetItem then
        local _, l = GameTooltip:GetItem()
        link = Plain(l)
    end
    if not link then
        ns.Print("Hover an item first, then press the key.")
        return
    end
    W.Toggle(link)
end

local function TooltipLine(tooltip)
    if not (tooltip and tooltip.GetItem) then return end
    local _, link = tooltip:GetItem()
    link = Plain(link)
    local on = link and W.On(ns.Gear.ItemID(link))
    if not on then return end
    local c = T.C.accent
    tooltip:AddLine("|A:auctionhouse-icon-favorite:12:12|a " .. (on == "ofa" and L["On your wishlist (OneForAll)"] or L["On your wishlist (GearShare)"]),
        c[1], c[2], c[3])
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            pcall(TooltipLine, tooltip)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip) pcall(TooltipLine, tooltip) end)
    end
end

BINDING_HEADER_GEARSHARE = "GearShare"
BINDING_NAME_GEARSHARE_WISH = L["Item under the mouse: on/off the wishlist"]

ns.On("PLAYER_LOGIN", function()
    HookClicks()
    HookTooltips()
end)
