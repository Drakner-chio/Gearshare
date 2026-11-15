-- GearShare: what I wear, and how much a drop would improve it.
--
-- Every player rates drops for themselves, with their own stat weights: my
-- client can't see anyone else's, and inspecting others only works up close
-- and out of combat. So Evaluate(link) answers "what is this item worth to ME,
-- compared with what I wear", and Comm.lua shares the answer.
--
-- The weights come from Pawn (every scale shown for this character, the best
-- one wins) or from Naowh Forever's Stat Weights (the active spec). Either way
-- the percent is the item against what it replaces, slot by slot, so everyone's
-- numbers can stand in one ranking. Naowh's own percent (over the whole
-- character) is not used for that reason.
--
-- Comparison:
--   rings, trinkets      against the weaker of the two worn
--   one-handers          against the main hand (or the weaker weapon when dual wielding)
--   two-handers          against main hand + off hand together
--   off-hand items       when a two-hander is worn: against half of it
-- Without weights, or for items they give no score (many trinkets), the item
-- level decides. A drop on the player's Naowh BiS list says so (bis = rank).

local ADDON, ns = ...
local L = ns.L
local Plain = ns.Plain
local G = {}
ns.Gear = G

local RANGED_SLOT = 18
local function RangedSlotExists()
    return VgerCore and VgerCore.RangedSlotExists
end

-- Slots in the order the overview lists them
G.SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
    { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
    { 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" },
    { 16, "Main hand" }, { 17, "Off hand" },
}
G.SLOT_NAME = {}
for _, s in ipairs(G.SLOTS) do G.SLOT_NAME[s[1]] = s[2] end
G.SLOT_NAME[RANGED_SLOT] = "Ranged"

local EQUIP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}
local OFFHAND_TYPES = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONMAINHAND = true }

function G.EquipLoc(link)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getInstant or not link then return nil end
    local _, _, _, equipLoc = getInstant(link)
    return equipLoc
end

function G.SlotsFor(equipLoc)
    if RangedSlotExists() and (equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"
        or equipLoc == "INVTYPE_THROWN" or equipLoc == "INVTYPE_RELIC") then
        return { RANGED_SLOT }
    end
    return EQUIP[equipLoc or ""]
end

function G.IsGear(link)
    return G.SlotsFor(G.EquipLoc(link)) ~= nil
end

function G.ItemLevel(link)
    if not link then return nil end
    local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    local ilvl = f and f(link)
    if not ilvl or ilvl == 0 then
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if info then ilvl = select(4, info(link)) end
    end
    return ilvl
end

function G.ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

---------------------------------------------------------------------------
-- Rating sources ("scorers"). Each has:
--   Ready()            can it rate now
--   Scales()           the scale names to rate with
--   Values(link, slot) { [scale] = value } for an item in a slot; nil while
--                      the game hasn't sent the item yet
--   Label(scale)       the name shown for a scale
--   Usable(link)       false when the item is not for this character, nil unknown
---------------------------------------------------------------------------
local Pawn = { key = "pawn" }

-- Pawn keeps "initialized" to itself; PawnIsReady() is how it says so
local function PawnReady()
    if PawnIsReady then
        local ok, ready = pcall(PawnIsReady)
        return ok and ready and true or false
    end
    return PawnIsInitialized and true or false
end

function Pawn.Ready()
    return PawnReady() and PawnGetItemData and PawnGetSingleValueFromItem and PawnCommon and PawnCommon.Scales and true or false
end

function Pawn.Scales()
    local list = {}
    for name in pairs(PawnCommon.Scales) do
        local ok, visible = pcall(PawnIsScaleVisible, name)
        if ok and visible then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end

function Pawn.Values(link, _, scales)
    local ok, item = pcall(PawnGetItemData, link)
    if not ok or not item then return nil end
    local values = {}
    for _, scale in ipairs(scales) do
        local ok2, v = pcall(PawnGetSingleValueFromItem, item, scale)
        values[scale] = ok2 and tonumber(v) or 0
    end
    return values
end

function Pawn.Label(name)
    if PawnGetScaleLocalizedName then
        local ok, label = pcall(PawnGetScaleLocalizedName, name)
        if ok and label then return label end
    end
    return (name:gsub('^"[^"]*":', ""))
end

function Pawn.Usable(link)
    if not PawnIsArmorBestTypeForPlayer then return nil end
    local ok, item = pcall(PawnGetItemData, link)
    if not ok or not item then return nil end
    local ok2, best = pcall(PawnIsArmorBestTypeForPlayer, item)
    if ok2 and best == false then return false end
    return true
end

-- Naowh Forever's Stat Weights (NaowhForever_BiS): one scale, the active spec
local Naowh = { key = "naowh" }
-- Naowh Forever's namespace, kept from when it loads (in case the global goes away later)
local naowhNS
local function NF()
    if type(_G.NaowhForever) == "table" then naowhNS = _G.NaowhForever end
    return naowhNS
end
G.NF = NF
ns.On("ADDON_LOADED", function() NF() end)
NF()
local function SW()
    local nf = NF()
    return nf and nf.StatWeights
end

function Naowh.Ready()
    local sw = SW()
    return sw and sw.For and sw.ActiveSpec and sw.Stats and sw.Worth and sw.DpsShare and true or false
end

function Naowh.Scales()
    local ok, key = pcall(SW().ActiveSpec)
    return (ok and key) and { key } or {}
end

function Naowh.Values(link, slot, scales)
    local sw = SW()
    local key = scales[1]
    local ok, weights = pcall(sw.For, key)
    if not ok or not weights then return {} end
    local ok2, stats = pcall(sw.Stats, link)
    if not ok2 or not stats then return nil end
    local ok3, worth = pcall(sw.Worth, stats, weights, sw.DpsShare(slot or 0))
    return { [key] = (ok3 and tonumber(worth)) or 0 }
end

function Naowh.Label(key)
    local ok, spec = pcall(SW().Spec, key)
    return "Naowh: " .. ((ok and spec and spec.name) or key)
end

function Naowh.Usable(link)
    local sw = SW()
    if not sw.Usable then return nil end
    local id = G.ItemID(link)
    local ok, usable = pcall(sw.Usable, id, link)
    if not ok then return nil end
    return usable
end

G.Pawn, G.Naowh = Pawn, Naowh

function G.HasPawn() return Pawn.Ready() end
function G.HasNaowh() return Naowh.Ready() end

-- The source to rate with, by the setting: "auto" (Pawn, else Naowh), "pawn" or "naowh".
-- nil: none there, the item level decides.
function G.Scorer()
    local want = ns.db and ns.db.source or "auto"
    if want == "naowh" then
        if Naowh.Ready() then return Naowh end
        if Pawn.Ready() then return Pawn end
    else
        if Pawn.Ready() then return Pawn end
        if Naowh.Ready() then return Naowh end
    end
    return nil
end

-- Where the drop stands on my Naowh BiS list: 1 = BiS, 2 = second pick ...; nil when not on it
function G.BisRank(link)
    local nf = NF()
    if not (nf and nf.IsBisItem) then return nil end
    local ok, rank = pcall(nf.IsBisItem, G.ItemID(link))
    rank = ok and tonumber(rank) or nil
    if rank and rank >= 1 then return math.floor(rank) end
    return nil
end

-- Highest value in a { [scale] = value } table (0 when empty)
local function BestOf(values)
    local best = 0
    for _, v in pairs(values or {}) do if v > best then best = v end end
    return best
end

---------------------------------------------------------------------------
-- What I wear
---------------------------------------------------------------------------
-- link of the item in a slot; false when empty; nil when not loaded yet
local function Worn(slot)
    local link = GetInventoryItemLink("player", slot)
    if link then return link end
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if id then return nil end
    return false
end
G.Worn = Worn

local function AllSlots()
    local slots = {}
    for _, s in ipairs(G.SLOTS) do slots[#slots + 1] = s[1] end
    if RangedSlotExists() then slots[#slots + 1] = RANGED_SLOT end
    return slots
end

-- Everything worn, for sharing: { {slot, itemID, ilvl, score}, ... }.
-- score is the best score by my rating source (nil without one).
function G.Snapshot()
    local scorer = G.Scorer()
    local scales = scorer and scorer.Scales() or nil
    local list = {}
    for _, slot in ipairs(AllSlots()) do
        local link = Worn(slot)
        local e = { slot = slot, itemID = 0, ilvl = 0 }
        if link then
            e.itemID = G.ItemID(link) or 0
            e.ilvl = G.ItemLevel(link) or 0
            e.link = link
            if scales and #scales > 0 then
                local values = scorer.Values(link, slot, scales)
                if values then e.score = BestOf(values) end
            end
        end
        list[#list + 1] = e
    end
    return list
end

---------------------------------------------------------------------------
-- Evaluate a drop for me
--
-- Returns a result table, or nil (+ "wait") when item data isn't loaded yet:
--   status  "U" upgrade · "E" fills an empty slot · "S" no upgrade
--           "X" can't use it · "-" not something you wear
--   pct     upgrade in percent (by the best scale, or by item level)
--   ilvl    item level difference to what it replaces
--   scale   the scale's name, or nil when the item level decided
--   slot    the slot it would go into
--   reason  for "X": "need" (can't roll need) or "armor" (not for you)
--   bis     its rank on my Naowh BiS list (1 = BiS), or nil
---------------------------------------------------------------------------
function G.Evaluate(link, canNeed)
    local equipLoc = G.EquipLoc(link)
    local slots = G.SlotsFor(equipLoc)
    if not slots then return { status = "-" } end
    local bis = G.BisRank(link)
    if canNeed == false then return { status = "X", reason = "need", slot = slots[1], bis = bis } end

    local newIlvl = G.ItemLevel(link)
    if not newIlvl then return nil, "wait" end

    local scorer = G.Scorer()
    local scales = scorer and scorer.Scales() or {}
    if #scales == 0 then scorer = nil end
    if scorer then
        local usable = scorer.Usable(link)
        if usable == false then return { status = "X", reason = "armor", slot = slots[1], bis = bis } end
    end

    -- What is worn in the slots this item could take: per slot { ilvl, values, id } or false
    local worn = {}
    local function Read(slot)
        if worn[slot] ~= nil then return worn[slot] end
        local w = Worn(slot)
        if w == nil then return nil end
        if w == false then worn[slot] = false return false end
        local e = { ilvl = G.ItemLevel(w) or 0, id = G.ItemID(w), equipLoc = G.EquipLoc(w) }
        if scorer then
            e.values = scorer.Values(w, slot, scales)
            if not e.values then return nil end
        end
        worn[slot] = e
        return e
    end
    local mh = Read(16)
    local oh = Read(17)
    for _, slot in ipairs(slots) do if Read(slot) == nil then return nil, "wait" end end
    if mh == nil or oh == nil then return nil, "wait" end

    -- The thing it replaces: { ilvl, values, id } or false for an empty slot
    local old, slot
    local twoHanderWorn = mh and mh.equipLoc == "INVTYPE_2HWEAPON"
    if equipLoc == "INVTYPE_2HWEAPON" then
        slot = 16
        if not mh and not oh then
            old = false
        else
            old = { ilvl = 0, values = {}, id = mh and mh.id }
            local n = 0
            for _, e in ipairs({ mh or false, oh or false }) do
                if e then
                    n = n + 1
                    old.ilvl = old.ilvl + e.ilvl
                    for k, v in pairs(e.values or {}) do old.values[k] = (old.values[k] or 0) + v end
                end
            end
            old.ilvl = old.ilvl / math.max(n, 1)
            if not scorer then old.values = nil end
        end
    elseif twoHanderWorn and OFFHAND_TYPES[equipLoc] then
        -- A one-hander or off-hand item where a two-hander is worn: it would
        -- take half the two-hander's job
        slot = slots[1]
        old = { ilvl = mh.ilvl, id = nil }
        if mh.values then
            old.values = {}
            for k, v in pairs(mh.values) do old.values[k] = v / 2 end
        end
    elseif equipLoc == "INVTYPE_WEAPON" then
        local dualWield = (CanDualWield and CanDualWield()) and (not oh or oh.equipLoc == "INVTYPE_WEAPON"
            or oh.equipLoc == "INVTYPE_WEAPONOFFHAND" or oh.equipLoc == "INVTYPE_WEAPONMAINHAND")
        slots = dualWield and { 16, 17 } or { 16 }
    end

    if old == nil then
        -- Single slot, or the weaker of two
        local best
        for _, s in ipairs(slots) do
            local e = worn[s]
            if e == nil then e = Read(s) end
            if e == false then best, slot = false, s break end
            local score = e.values and BestOf(e.values) or e.ilvl
            if best == nil or score < best.score then best, slot = { e = e, score = score }, s end
        end
        old = best and best.e or false
    end

    local result = { slot = slot, bis = bis }
    if not old then
        result.status = "E"
        result.ilvl = newIlvl
        return result
    end
    result.ilvl = newIlvl - (old.ilvl or 0)

    local thisID = G.ItemID(link)
    if old.id and thisID and old.id == thisID then
        result.status, result.pct = "S", 0
        return result
    end

    -- The new item's values in the slot it goes into (weapon damage counts
    -- differently in the off hand for Naowh)
    local newValues
    if scorer then
        newValues = scorer.Values(link, slot, scales)
        if not newValues then return nil, "wait" end
    end

    -- Best scale
    local bestPct, bestScale
    if newValues and old.values then
        for _, scale in ipairs(scales) do
            local nv, ov = newValues[scale] or 0, old.values[scale] or 0
            if nv > 0 and ov > 0 then
                local pct = (nv - ov) / ov * 100
                if not bestPct or pct > bestPct then bestPct, bestScale = pct, scale end
            elseif nv > 0 and ov <= 0 then
                bestPct, bestScale = math.huge, scale
            end
        end
    end
    if bestPct then
        result.pct = bestPct
        result.scale = scorer.Label(bestScale)
    else
        -- No weights, or they have nothing to say about this item: item level
        local o = old.ilvl or 0
        result.pct = o > 0 and (newIlvl - o) / o * 100 or 0
    end
    if result.pct == math.huge then result.pct = 999 end
    result.status = result.pct > 0.05 and "U" or "S"
    return result
end
