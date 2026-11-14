-- GearShare: the group's gear, slot by slot. One column per member (from the
-- gear their GearShare sent), one row per slot, the item level in each cell.
-- Each member's two weakest slots are marked: where a drop helps them most.

local ADDON, ns = ...
local L, T = ns.L, ns.Theme
local C = T.C
local W = {}
ns.GroupWindow = W

local LABEL_W, COL_W, ROW_H = 92, 66, 18
local PER_PAGE = 8
local frame, grid, pageText, prevBtn, nextBtn, note
local page = 1
local headers, cells, labels, avgCells = {}, {}, {}, {}

local function Slots()
    local list = {}
    for _, s in ipairs(ns.Gear.SLOTS) do list[#list + 1] = s end
    if VgerCore and VgerCore.RangedSlotExists then list[#list + 1] = { 18, "Ranged" } end
    return list
end

-- { [slot] = { itemID, ilvl, score, link } or false } for a member, nil without data
local function GearOf(name)
    if name == ns.Me() then
        local g = {}
        for _, e in ipairs(ns.Gear.Snapshot()) do
            g[e.slot] = e.itemID > 0 and e or false
        end
        return g
    end
    local m = ns.members[name]
    if m and m.gearTime then return m.gear end
    return nil
end

local function Cell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(COL_W, ROW_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0)
    b.text = T.Text(b, "", 12, C.text, true)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.link then GameTooltip:SetHyperlink(e.link)
        elseif e.itemID and GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.itemID) end
        if e.score then
            GameTooltip:AddLine(("Pawn: %.1f"):format(e.score), C.accent[1], C.accent[2], C.accent[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build()
    frame = T.Window("GearShareGroupFrame", "Group gear", 400, 300, "groupPos")
    frame:RestorePosition("CENTER", 0, 40)

    grid = CreateFrame("Frame", nil, frame)
    grid:SetPoint("TOPLEFT", 10, -36)
    grid:SetSize(10, 10)

    local slots = Slots()
    for i, s in ipairs(slots) do
        local lab = T.Text(grid, s[2], 12, C.muted)
        lab:SetPoint("TOPLEFT", 2, -(22 + (i - 1) * ROW_H) - 3)
        labels[i] = lab
        if i % 2 == 0 then
            local stripe = grid:CreateTexture(nil, "BACKGROUND")
            stripe:SetPoint("TOPLEFT", 0, -(22 + (i - 1) * ROW_H))
            stripe:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
            stripe:SetHeight(ROW_H)
            stripe:SetColorTexture(1, 1, 1, 0.025)
        end
    end
    local avgY = -(22 + #slots * ROW_H) - 4
    local sep = grid:CreateTexture(nil, "BORDER")
    sep:SetPoint("TOPLEFT", 0, avgY)
    sep:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(unpack(C.line))
    local avgLab = T.Text(grid, "Avg. item level", 12, C.text)
    avgLab:SetPoint("TOPLEFT", 2, avgY - 5)
    grid.avgY = avgY - 2

    local refresh = T.FlatButton(frame, "Ask again", 90, 20)
    refresh:SetPoint("BOTTOMLEFT", 10, 9)
    refresh:SetScript("OnClick", function()
        ns.Comm.SendHello()
        W:Refresh()
    end)
    T.Tooltip(refresh, "Ask again", "Asks everyone's GearShare to send their gear again.")

    prevBtn = T.FlatButton(frame, "<", 22, 20)
    nextBtn = T.FlatButton(frame, ">", 22, 20)
    nextBtn:SetPoint("BOTTOMRIGHT", -10, 9)
    pageText = T.Text(frame, "", 11, C.muted, true)
    pageText:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
    prevBtn:SetPoint("RIGHT", pageText, "LEFT", -6, 0)
    prevBtn:SetScript("OnClick", function() page = page - 1; W:Paint() end)
    nextBtn:SetScript("OnClick", function() page = page + 1; W:Paint() end)

    note = T.Text(frame, "", 11, C.faint, true)
    note:SetPoint("LEFT", refresh, "RIGHT", 10, 0)

    frame:SetScript("OnShow", function() W:Paint() end)
end

function W:Paint()
    if not frame then return end
    local slots = Slots()
    local roster = ns.Roster()
    local pages = math.max(1, math.ceil(#roster / PER_PAGE))
    page = math.min(math.max(page, 1), pages)
    local first = (page - 1) * PER_PAGE + 1
    local cols = math.min(PER_PAGE, #roster - first + 1)

    local missing = 0
    for c = 1, cols do
        local m = roster[first + c - 1]
        local x = LABEL_W + (c - 1) * COL_W
        local h = headers[c]
        if not h then
            h = T.Text(grid, "", 12, C.text, true)
            h:SetJustifyH("CENTER")
            h:SetWidth(COL_W - 4)
            headers[c] = h
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", x + 2, -2)
        h:SetText(ns.ColoredName(m.name))
        h:Show()

        local gear = GearOf(m.name)
        if not gear then missing = missing + 1 end

        -- the two weakest slots
        local weak = {}
        if gear then
            local list = {}
            for _, s in ipairs(slots) do
                local e = gear[s[1]]
                -- an empty off hand next to a main-hand weapon is a two-hander, not a gap
                if not (s[1] == 17 and not e and gear[16]) then
                    list[#list + 1] = { slot = s[1], ilvl = e and e.ilvl or 0 }
                end
            end
            table.sort(list, function(a, b) return a.ilvl < b.ilvl end)
            for i = 1, math.min(2, #list) do weak[list[i].slot] = true end
        end

        cells[c] = cells[c] or {}
        local sum, n = 0, 0
        for i, s in ipairs(slots) do
            local cell = cells[c][i] or Cell(grid)
            cells[c][i] = cell
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", x, -(22 + (i - 1) * ROW_H))
            local e = gear and gear[s[1]]
            cell.entry = e or nil
            if not gear then
                cell.text:SetText("·")
                cell.text:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
            elseif not e then
                cell.text:SetText("–")
                local col = (s[1] == 17 and gear[16]) and C.faint or C.bad
                cell.text:SetTextColor(col[1], col[2], col[3])
            else
                cell.text:SetText(tostring(math.floor(e.ilvl + 0.5)))
                local col = weak[s[1]] and C.warn or C.text
                cell.text:SetTextColor(col[1], col[2], col[3])
                sum, n = sum + e.ilvl, n + 1
            end
            if weak[s[1]] and gear then
                cell.bg:SetColorTexture(C.warn[1], C.warn[2], C.warn[3], 0.08)
            else
                cell.bg:SetColorTexture(0, 0, 0, 0)
            end
            cell:Show()
        end
        for i = #slots + 1, #cells[c] do cells[c][i]:Hide() end

        local a = avgCells[c]
        if not a then
            a = T.Text(grid, "", 12, C.accent, true)
            a:SetJustifyH("CENTER")
            a:SetWidth(COL_W)
            avgCells[c] = a
        end
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", x, grid.avgY - 3)
        a:SetText(n > 0 and ("%.1f"):format(sum / n) or "")
        a:Show()
    end
    for c = cols + 1, #headers do
        headers[c]:Hide()
        for _, cell in ipairs(cells[c] or {}) do cell:Hide() end
        if avgCells[c] then avgCells[c]:Hide() end
    end

    local width = 10 + LABEL_W + math.max(cols, 1) * COL_W + 12
    frame:SetWidth(math.max(width, 330))
    frame:SetHeight(36 + 22 + #slots * ROW_H + 30 + 40)
    local paged = pages > 1
    prevBtn:SetShown(paged); nextBtn:SetShown(paged); pageText:SetShown(paged)
    pageText:SetText(("%d/%d"):format(page, pages))
    note:SetText(missing > 0 and L["%d without GearShare data"]:format(missing) or "")
end

local pending = false
function W:Refresh()
    if not frame or not frame:IsShown() or pending then return end
    pending = true
    ns.After(0.2, function() pending = false; W:Paint() end)
end

function W:Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); W:Paint() end
end
