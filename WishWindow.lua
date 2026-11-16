-- GearShare: the wishlist window (/gs wish). Grouped by where the items come
-- from (instance and boss, profession, unknown), each group by slot. Items of
-- OneForAll's wishlist are listed too, marked, and are removed in OneForAll.

local ADDON, ns = ...
local L, T = ns.L, ns.Theme
local C = T.C
local WW = {}
ns.WishWindow = WW

local WIDTH, ROW_H, HEAD_H, VISIBLE = 380, 20, 24, 20
local frame, body, empty, scrollText
local lines, rows = {}, {}
local offset = 0

local SLOT_ORDER = {}
for i, s in ipairs(ns.Gear.SLOTS) do SLOT_ORDER[s[1]] = SLOT_ORDER[s[1]] or i end

local function ItemInfo(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return nil end
    local name, link, quality, _, _, _, _, _, equipLoc = info(id)
    return name, link, quality, equipLoc
end

local function Have(id)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return false end
    local ok, n = pcall(count, id, true)
    return ok and (tonumber(n) or 0) > 0
end

-- Flat list of what to draw: group headers and items
local function Build()
    wipe(lines)
    local groups, order = {}, {}
    local function Put(id, from)
        local src = ns.Wish.SourceOf(id)
        local key, label
        if src and src.instance then
            key = "1" .. src.instance .. "\0" .. (src.boss or "")
            label = src.instance .. (src.boss and ("  ·  " .. src.boss) or "")
        elseif src and src.profession then
            key = "2" .. src.profession
            label = L["Profession: %s"]:format(src.profession)
        else
            key, label = "9", L["Where from: not known yet"]
        end
        if not groups[key] then
            groups[key] = { label = label, items = {} }
            order[#order + 1] = key
        end
        local _, _, _, equipLoc = ItemInfo(id)
        local slots = ns.Gear.SlotsFor(equipLoc)
        local entry = ns.Wish.List()[id]
        local slot = (entry and entry.slot) or (slots and slots[1])
        table.insert(groups[key].items, { id = id, from = from, slot = slot })
    end
    for id in pairs(ns.Wish.List()) do Put(id, "gs") end
    local ofa = ns.Wish.OneForAll()
    if ofa then
        for id in pairs(ofa) do
            if type(id) == "number" and not ns.Wish.List()[id] then Put(id, "ofa") end
        end
    end
    table.sort(order)
    for _, key in ipairs(order) do
        local g = groups[key]
        table.sort(g.items, function(a, b)
            local sa, sb = SLOT_ORDER[a.slot or 0] or 99, SLOT_ORDER[b.slot or 0] or 99
            if sa ~= sb then return sa < sb end
            return a.id < b.id
        end)
        lines[#lines + 1] = { head = g.label, count = #g.items }
        for _, it in ipairs(g.items) do lines[#lines + 1] = it end
    end
end

local function NewRow()
    local r = CreateFrame("Button", nil, body)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = T.Text(r, "", 12, C.text, true)
    r.text:SetPoint("LEFT", 28, 0)
    r.text:SetPoint("RIGHT", -120, 0)
    r.text:SetWordWrap(false)
    r.slot = T.Text(r, "", 11, C.faint, true)
    r.slot:SetPoint("RIGHT", -28, 0)
    r.slot:SetJustifyH("RIGHT")
    r.remove = CreateFrame("Button", nil, r)
    r.remove:SetSize(20, 20)
    r.remove:SetPoint("RIGHT", -4, 0)
    local x = T.Text(r.remove, "", 14, C.muted, true)
    x:SetText("×")
    x:SetPoint("CENTER")
    r.remove:SetScript("OnClick", function() if r.item then ns.Wish.Remove(r.item.id) end end)
    r:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local _, link = ItemInfo(self.item.id)
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText("item " .. self.item.id) end
        if self.item.from == "ofa" then
            GameTooltip:AddLine(L["From OneForAll's wishlist: remove it there (Armory > Gear Planner)."], C.muted[1], C.muted[2], C.muted[3], true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if not self.item then return end
        local _, link = ItemInfo(self.item.id)
        if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
    end)
    return r
end

local function Paint()
    if not frame then return end
    Build()
    local maxOffset = math.max(0, #lines - VISIBLE)
    offset = math.min(math.max(offset, 0), maxOffset)
    for i = 1, VISIBLE do
        local line = lines[offset + i]
        local r = rows[i] or NewRow()
        rows[i] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
        if not line then
            r:Hide()
        elseif line.head then
            r.item = nil
            r.icon:Hide()
            r.remove:Hide()
            r.bg:SetColorTexture(1, 1, 1, 0.04)
            r.text:SetText("|cff" .. T.ACCENT_HEX .. T.Upper(line.head) .. "|r")
            r.slot:SetText(tostring(line.count))
            r:Show()
        else
            r.item = line
            local name, _, quality = ItemInfo(line.id)
            local hex = "ffffff"
            local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if qc and qc.hex then hex = qc.hex:gsub("^|c", ""):sub(3) end
            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(line.id)) or 134400
            r.icon:SetTexture(icon)
            r.icon:Show()
            r.bg:SetColorTexture(0, 0, 0, 0)
            local mark = Have(line.id) and ("  |cff5cd97a" .. L["you have it"] .. "|r") or ""
            local ofa = line.from == "ofa" and "  |cff8a909b(OneForAll)|r" or ""
            r.text:SetText("|cff" .. hex .. (name or ("item " .. line.id)) .. "|r" .. ofa .. mark)
            r.slot:SetText(line.slot and ns.Gear.SLOT_NAME[line.slot] and L[ns.Gear.SLOT_NAME[line.slot]] or "")
            r.remove:SetShown(line.from == "gs")
            r:Show()
        end
    end
    empty:SetShown(#lines == 0)
    scrollText:SetText(#lines > VISIBLE and ("%d–%d / %d"):format(offset + 1, math.min(offset + VISIBLE, #lines), #lines) or "")
end

local function Create()
    frame = T.Window("GearShareWishFrame", "Wishlist", WIDTH, 38 + VISIBLE * ROW_H + 44, "wishPos")
    frame:RestorePosition("CENTER", -200, 0)
    body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 10, -36)
    body:SetPoint("TOPRIGHT", -10, -36)
    body:SetHeight(VISIBLE * ROW_H)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; Paint() end)

    empty = T.Text(body, "Your wishlist is empty. Ctrl+Alt+click an item (bags, chat, journal, AtlasLoot, professions), or hover it and press your GearShare key (Key Bindings > AddOns). OneForAll's wishlist shows up here by itself.", 12, C.muted)
    empty:SetPoint("TOPLEFT", 4, -4)
    empty:SetWidth(WIDTH - 28)
    empty:SetWordWrap(true)

    local hint = T.Text(frame, "", 11, C.faint, true)
    hint:SetText(L["Ctrl+Alt+click: on/off"])
    hint:SetPoint("BOTTOMLEFT", 12, 13)
    scrollText = T.Text(frame, "", 11, C.faint, true)
    scrollText:SetPoint("BOTTOMRIGHT", -12, 13)
    frame:SetScript("OnShow", Paint)
end

function WW:Refresh()
    if frame and frame:IsShown() then Paint() end
end

function WW:Toggle()
    if not frame then Create() end
    if frame:IsShown() then frame:Hide() else frame:Show(); Paint() end
end

function WW:ApplySettings(resetPosition)
    if frame and resetPosition then frame:RestorePosition("CENTER", -200, 0) end
end
