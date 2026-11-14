-- GearShare: the loot window. One card per drop, newest on top; in each card
-- the group, the biggest upgrade first, with a violet mark on the winner.

local ADDON, ns = ...
local L, T = ns.L, ns.Theme
local C = T.C
local W = {}
ns.LootWindow = W

local WIDTH = 360
local ROW_H = 18
local HEAD_H = 40
local frame, body, empty, more
local cards = {}

local KIND_COLOR = {
    E = C.good, U = C.good, S = C.muted, X = C.bad, wait = C.faint, none = C.faint,
}

local function Ago(t)
    local s = math.max(0, ns.Now() - t)
    if s < 60 then return L["just now"] end
    return L["%d min ago"]:format(math.floor(s / 60))
end

local function ItemIcon(d)
    local id = ns.Gear.ItemID(d.link or d.itemString)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return (f and id and f(id)) or 134400   -- question mark
end

---------------------------------------------------------------------------
-- A row: one group member's verdict
---------------------------------------------------------------------------
local function NewRow(card)
    local r = CreateFrame("Frame", nil, card)
    r:SetHeight(ROW_H)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(2, ROW_H - 6)
    r.mark:SetPoint("LEFT", 10, 0)
    r.mark:SetColorTexture(unpack(C.accent))
    r.name = T.Text(r, "", 12, C.text, true)
    r.name:SetPoint("LEFT", 18, 0)
    r.value = T.Text(r, "", 12, C.text, true)
    r.value:SetPoint("RIGHT", -12, 0)
    r.value:SetJustifyH("RIGHT")
    r.value:SetWidth(80)
    r.scale = T.Text(r, "", 11, C.faint, true)
    r.scale:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.scale:SetJustifyH("RIGHT")
    r.scale:SetWidth(110)
    return r
end

local function PaintRow(r, e, first)
    r.mark:SetShown(first and (e.kind == "U" or e.kind == "E"))
    r.name:SetText(ns.ColoredName(e.name))
    local c = KIND_COLOR[e.kind] or C.text
    local value, scale = "", ""
    if e.kind == "wait" then
        value = L["rating…"]
    elseif e.kind == "none" then
        value = L["no GearShare"]
    else
        value = ns.Loot.Describe(e.r)
        if e.r.scale then scale = e.r.scale end
        if e.r.ilvl and e.kind ~= "X" and e.kind ~= "E" and e.r.ilvl ~= 0 then
            scale = (scale ~= "" and (scale .. "  ") or "") .. ("%+d ilvl"):format(e.r.ilvl)
        elseif e.kind == "E" and e.r.ilvl then
            scale = ("ilvl %d"):format(e.r.ilvl)
        end
    end
    r.value:SetText(value)
    r.value:SetTextColor(c[1], c[2], c[3])
    r.scale:SetText(scale)
    r.name:SetAlpha((e.kind == "X" or e.kind == "none") and 0.55 or 1)
end

---------------------------------------------------------------------------
-- A card: one drop
---------------------------------------------------------------------------
local function NewCard()
    local card = CreateFrame("Frame", nil, body)
    card:SetWidth(WIDTH - 20)
    T.Fill(card, C.card)
    T.Border(card, C.line)

    local iconBtn = CreateFrame("Button", nil, card)
    iconBtn:SetSize(26, 26)
    iconBtn:SetPoint("TOPLEFT", 8, -7)
    iconBtn.tex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconBtn.tex:SetAllPoints()
    iconBtn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconBtn:SetScript("OnEnter", function(self)
        local d = card.drop
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:SetText(d.itemString) end
        GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconBtn:SetScript("OnClick", function()
        local d = card.drop
        if d and d.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            ChatEdit_InsertLink(d.link)
        end
    end)
    card.icon = iconBtn

    card.name = T.Text(card, "", 13, C.text, true)
    card.name:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, 0)
    card.name:SetPoint("RIGHT", card, "RIGHT", -70, 0)
    card.name:SetWordWrap(false)
    card.sub = T.Text(card, "", 11, C.muted, true)
    card.sub:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 8, 0)

    card.post = T.FlatButton(card, "Post", 56, 20)
    card.post:SetPoint("TOPRIGHT", -8, -8)
    T.Tooltip(card.post, "Post in group chat", "Writes who gains most from this item into party or raid chat.")
    card.post:SetScript("OnClick", function() if card.drop then ns.Loot:Announce(card.drop) end end)

    card.rows = {}
    return card
end

local function PaintCard(card, d)
    card.drop = d
    card.icon.tex:SetTexture(ItemIcon(d))
    card.name:SetText(d.link or d.itemString)
    local slot = d.results[ns.Me()] and d.results[ns.Me()].slot
    local parts = {}
    if slot and ns.Gear.SLOT_NAME[slot] then parts[#parts + 1] = L[ns.Gear.SLOT_NAME[slot]] end
    if d.demo then
        parts[#parts + 1] = L["test"]
    elseif d.askedBy and d.askedBy ~= ns.Me() then
        parts[#parts + 1] = L["asked by %s"]:format(d.askedBy:gsub("%-.*$", ""))
    end
    parts[#parts + 1] = Ago(d.time)
    card.sub:SetText(table.concat(parts, "  ·  "))
    card.post:SetShown(ns.GroupChannel() ~= nil and not d.demo)

    local ranking = ns.Loot.Ranking(d)
    for i, e in ipairs(ranking) do
        local r = card.rows[i] or NewRow(card)
        card.rows[i] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(HEAD_H + (i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", 0, -(HEAD_H + (i - 1) * ROW_H))
        PaintRow(r, e, i == 1)
        r:Show()
    end
    for i = #ranking + 1, #card.rows do card.rows[i]:Hide() end
    local h = HEAD_H + #ranking * ROW_H + 8
    card:SetHeight(h)
    return h
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Build()
    frame = T.Window("GearShareLootFrame", "Loot", WIDTH, 200, "lootPos")
    frame:RestorePosition("RIGHT", -260, 60)
    frame:ApplyScale("lootScale")

    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 10, -38)
    body:SetPoint("TOPRIGHT", -10, -38)
    body:SetHeight(10)

    empty = T.Text(body, "Nothing has dropped yet. When a need/greed roll starts, everyone's verdict shows up here.", 12, C.muted)
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetWidth(WIDTH - 28)
    empty:SetWordWrap(true)

    more = T.Text(frame, "", 11, C.faint, true)

    local clear = T.FlatButton(frame, "Clear", 70, 20)
    clear:SetPoint("BOTTOMLEFT", 10, 9)
    clear:SetScript("OnClick", function() ns.Loot:Clear() end)
    local gear = T.FlatButton(frame, "Group gear", 100, 20)
    gear:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    gear:SetScript("OnClick", function() ns.GroupWindow:Toggle() end)
    T.Tooltip(gear, "Group gear", "Everyone's gear slot by slot, as their GearShare sent it.")
    more:SetPoint("BOTTOMRIGHT", -12, 13)

    frame:SetScript("OnShow", function() W:Refresh() end)
    -- the "x min ago" lines
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 20 then acc = 0; W:Refresh() end
    end)
end

local pending = false
function W:Refresh()
    if not frame or not frame:IsShown() then return end
    if pending then return end
    pending = true
    ns.After(0.05, function()
        pending = false
        W:Paint()
    end)
end

function W:Paint()
    if not frame then return end
    local y, shown, full = 0, 0, false
    local drops = ns.Loot.drops
    for i, d in ipairs(drops) do
        local card = cards[i] or NewCard()
        cards[i] = card
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        local h = PaintCard(card, d)
        if full or (y + h > ((ns.db and ns.db.lootMaxHeight) or 600) and shown > 0) then
            full = true
            card:Hide()
        else
            card:Show()
            y = y + h + 8
            shown = shown + 1
        end
    end
    for i = #drops + 1, #cards do cards[i]:Hide() end
    empty:SetShown(#drops == 0)
    if #drops == 0 then y = 50 end
    more:SetText(#drops > shown and L["+%d older"]:format(#drops - shown) or "")
    body:SetHeight(math.max(y, 10))
    frame:SetHeight(38 + y + 34)
end

function W:Open()
    if not frame then Build() end
    frame:Show()
    W:Paint()
end

function W:Toggle()
    if frame and frame:IsShown() then frame:Hide() else W:Open() end
end

-- After a setting changed (size, height, position reset)
function W:ApplySettings(resetPosition)
    if not frame then return end
    frame:ApplyScale("lootScale")
    if resetPosition then frame:RestorePosition("RIGHT", -260, 60) end
    if frame:IsShown() then W:Paint() end
end

function W:IsShown() return frame and frame:IsShown() end
