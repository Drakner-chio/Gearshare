-- GearShare: settings window (/gs options), the minimap button, and an entry
-- in the game's own AddOns settings that opens the window.

local ADDON, ns = ...
local L, T = ns.L, ns.Theme
local C = T.C
local O = {}
ns.Options = O

local frame
local controls = {}

local function Percent(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end

local function Build()
    local W, PAD = 420, 12
    frame = T.Window("GearShareOptionsFrame", "Settings", W, 560, "optionsPos")
    frame:RestorePosition("CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    local cw = W - 2 * PAD

    -- Loot window
    local y = -40
    local loot = T.Card(frame, "Loot window", PAD, y, cw, 200)
    controls[#controls + 1] = T.Switch(loot, "Open by itself when something drops", 16, -34,
        function() return ns.db.autoShow end, function(v) ns.db.autoShow = v end)
    controls[#controls + 1] = T.Switch(loot, "Hide players who can't use the item", 16, -60,
        function() return ns.db.onlyUsable end,
        function(v) ns.db.onlyUsable = v; ns.LootWindow:Refresh() end)
    controls[#controls + 1] = T.Slider(loot, "Size", 16, -90, cw - 32,
        function() return ns.db.lootScale end,
        function(v) ns.db.lootScale = v; ns.LootWindow:ApplySettings() end,
        0.7, 1.5, 0.05, Percent)
    controls[#controls + 1] = T.Slider(loot, "Height before older drops are hidden", 16, -130, cw - 32,
        function() return ns.db.lootMaxHeight end,
        function(v) ns.db.lootMaxHeight = v; ns.LootWindow:ApplySettings() end,
        250, 1000, 25, "%d px")
    controls[#controls + 1] = T.Slider(loot, "Keep drops for", 16, -170, cw - 32,
        function() return ns.db.keepMinutes end,
        function(v) ns.db.keepMinutes = v end,
        5, 60, 5, L["%d min"])

    -- From which quality on
    y = y - 210
    local qual = T.Card(frame, "Which drops", PAD, y, cw, 70)
    controls[#controls + 1] = T.Choice(qual, "List drops from this quality on", 16, -30, {
        { 1, "Common" }, { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic" },
    }, function() return ns.db.minQuality end, function(v)
        ns.db.minQuality = v
        ns.LootWindow:Refresh()
    end, 84)
    for _, b in ipairs(controls[#controls]) do
        T.Tooltip(b, "Which drops", "Lower drops are still rated for the group, they just don't open or show up in your window.")
    end

    -- Rating
    y = y - 80
    local rate = T.Card(frame, "Rating", PAD, y, cw, 92)
    controls[#controls + 1] = T.Choice(rate, "Rate drops with", 16, -30, {
        { "auto", "Automatic" }, { "pawn", "Pawn" }, { "naowh", "Naowh" },
    }, function() return ns.db.source end, function(v)
        ns.db.source = v
        ns.Comm.SendGear()
    end, 110)
    T.Tooltip(controls[#controls][1], "Automatic", "Pawn when it is installed, otherwise Naowh Forever's Stat Weights, otherwise the item level.")
    T.Tooltip(controls[#controls][3], "Naowh", "The stat weights of Naowh Forever's BiS List for your spec. GearShare compares the item with what you wear in its slot, like with Pawn, so everyone's numbers fit one ranking.")
    local found = T.Text(rate, "", 11, C.faint, true)
    found:SetPoint("TOPLEFT", 16, -76)
    controls[#controls + 1] = { Refresh = function()
        local function yes(on) return on and ("|cff5cd97a" .. L["found"] .. "|r") or ("|cffdb5c5c" .. L["not found"] .. "|r") end
        found:SetText(L["Pawn: %s  ·  Naowh Stat Weights: %s"]:format(
            yes(ns.Gear.HasPawn()), yes(ns.Gear.HasNaowh())))
    end }

    -- Group gear
    y = y - 102
    local group = T.Card(frame, "Group gear", PAD, y, cw, 64)
    controls[#controls + 1] = T.Slider(group, "Size", 16, -30, cw - 32,
        function() return ns.db.groupScale end,
        function(v) ns.db.groupScale = v; ns.GroupWindow:ApplySettings() end,
        0.7, 1.5, 0.05, Percent)

    -- General
    y = y - 74
    local gen = T.Card(frame, "General", PAD, y, cw, 146)
    controls[#controls + 1] = T.Switch(gen, "Minimap button", 16, -34,
        function() return ns.db.minimapButton end,
        function(v) ns.db.minimapButton = v; ns.UpdateMinimapButton() end)
    controls[#controls + 1] = T.Switch(gen, "Use OneForAll's wishlist too", 16, -86,
        function() return ns.db.useOneForAll end,
        function(v) ns.db.useOneForAll = v; ns.Wish.Changed() end)
    controls[#controls + 1] = T.Switch(gen, "Lock windows (no dragging)", 16, -60,
        function() return ns.db.locked end, function(v) ns.db.locked = v end)
    local reset = T.FlatButton(gen, "Reset window positions", 170, 22)
    reset:SetPoint("TOPLEFT", 16, -112)
    reset:SetScript("OnClick", function()
        ns.db.lootPos, ns.db.groupPos, ns.db.wishPos = nil, nil, nil
        ns.WishWindow:ApplySettings(true)
        ns.LootWindow:ApplySettings(true)
        ns.GroupWindow:ApplySettings(true)
    end)
    local test = T.FlatButton(gen, "Test drop", 100, 22)
    test:SetPoint("LEFT", reset, "RIGHT", 6, 0)
    test:SetPrimary(true)
    test:SetScript("OnClick", function() ns.Loot:Demo() end)

    local hint = T.Text(frame, "", 11, C.faint, true)
    hint:SetText("/gs options  ·  /gs help  ·  v" .. tostring(ns.VERSION))
    hint:SetPoint("BOTTOMLEFT", PAD + 2, 12)

    frame:SetHeight(-y + 146 + 40)
    frame:SetScript("OnShow", function() O:Refresh() end)
end

function O:Refresh()
    for _, c in ipairs(controls) do if c.Refresh then c.Refresh() end end
end

function O:Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); O:Refresh() end
end

---------------------------------------------------------------------------
-- Minimap button: drag it round the minimap
---------------------------------------------------------------------------
local button

local function Position()
    local angle = math.rad(ns.db.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function BuildButton()
    if button or not Minimap then return end
    local b = CreateFrame("Button", "GearShareMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture(T.LOGO)
    icon:SetPoint("TOPLEFT", 6, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    b:SetScript("OnClick", function(_, which) ns.HandleClick(which) end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
            Position()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(T.CHAT_PREFIX)
        GameTooltip:AddLine(L["Left-click: loot window"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: group gear"], 1, 1, 1)
        GameTooltip:AddLine(L["Middle or shift-click: settings"], 1, 1, 1)
        GameTooltip:AddLine(L["Ctrl-click: wishlist"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move this button"], C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button = b
    Position()
end

function ns.UpdateMinimapButton()
    if not ns.db then return end
    if ns.db.minimapButton and not button then BuildButton() end
    if button then button:SetShown(ns.db.minimapButton) end
end

---------------------------------------------------------------------------
-- The game's settings (Esc → Options → AddOns → GearShare)
---------------------------------------------------------------------------
local function RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = T.Text(panel, "", 20, C.text, true)
    title:SetText("|cff" .. T.ACCENT_HEX .. "GearShare|r")
    title:SetPoint("TOPLEFT", 16, -16)
    local note = T.Text(panel, "Size, minimap button and everything else is in GearShare's own settings window.", 13, C.muted)
    note:SetPoint("TOPLEFT", 16, -50)
    note:SetWidth(520)
    note:SetWordWrap(true)
    local open = T.FlatButton(panel, "Open settings", 140, 24)
    open:SetPrimary(true)
    open:SetPoint("TOPLEFT", 16, -84)
    open:SetScript("OnClick", function()
        if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
        O:Toggle()
    end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "GearShare")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

ns.OnLoaded = function()
    ns.UpdateMinimapButton()
    RegisterSettings()
end
