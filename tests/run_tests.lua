-- GearShare tests. Run from the repo root: lua5.1 tests/run.lua

local function STEP(name) LOG[#LOG + 1] = "STEP " .. name end
local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-6) end
local function logHas(text)
    for i = #LOG, 1, -1 do if LOG[i]:find(text, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
-- The items of the tests
---------------------------------------------------------------------------
ITEMS = {
    [100] = { name = "Old Helm", equipLoc = "INVTYPE_HEAD", ilvl = 30, values = { A = 100, B = 80 } },
    [101] = { name = "New Helm", equipLoc = "INVTYPE_HEAD", ilvl = 33, values = { A = 110, B = 96 } },
    [102] = { name = "Cloth Hood", equipLoc = "INVTYPE_HEAD", ilvl = 40, values = { A = 50, B = 50 }, armorOK = false },
    [110] = { name = "Ring One", equipLoc = "INVTYPE_FINGER", ilvl = 30, values = { A = 40 } },
    [111] = { name = "Ring Two", equipLoc = "INVTYPE_FINGER", ilvl = 28, values = { A = 20 } },
    [112] = { name = "New Ring", equipLoc = "INVTYPE_FINGER", ilvl = 32, values = { A = 30 } },
    [120] = { name = "Sword", equipLoc = "INVTYPE_WEAPON", ilvl = 30, values = { A = 60 } },
    [121] = { name = "Shield", equipLoc = "INVTYPE_SHIELD", ilvl = 30, values = { A = 40 } },
    [122] = { name = "Greataxe", equipLoc = "INVTYPE_2HWEAPON", ilvl = 33, values = { A = 120 } },
    [123] = { name = "Big Shield", equipLoc = "INVTYPE_SHIELD", ilvl = 35, values = { A = 70 } },
    [124] = { name = "New Sword", equipLoc = "INVTYPE_WEAPON", ilvl = 34, values = { A = 72 } },
    [130] = { name = "Boots", equipLoc = "INVTYPE_FEET", ilvl = 31, values = { A = 50 } },
    [140] = { name = "Odd Trinket", equipLoc = "INVTYPE_TRINKET", ilvl = 35, values = {} },
    [141] = { name = "Worn Trinket", equipLoc = "INVTYPE_TRINKET", ilvl = 30, values = {} },
    [142] = { name = "Worn Trinket 2", equipLoc = "INVTYPE_TRINKET", ilvl = 32, values = {} },
    [150] = { name = "Potion", equipLoc = "", ilvl = 1 },
    [7719] = { name = "Raging Berserker's Helm", equipLoc = "INVTYPE_HEAD", ilvl = 42, values = { A = 130, B = 90 } },
}
local function wear()
    WORN = {
        [1] = "item:100::::::::30:71", [11] = "item:110::::::::30:71", [12] = "item:111::::::::30:71",
        [13] = "item:141::::::::30:71", [14] = "item:142::::::::30:71",
        [16] = "item:120::::::::30:71", [17] = "item:121::::::::30:71",
    }
end
wear()
InstallPawn({ "A", "B" })

local ns = LoadAddon(".")
FireEvent("ADDON_LOADED", "GearShare")
check(ns.db and ns.db.autoShow == true, "settings are made with their defaults")
local G, Loot, Comm = ns.Gear, ns.Loot, ns.Comm
local function eval(id, canNeed) return G.Evaluate(MakeLink("item:" .. id .. "::::::::30:71"), canNeed) end

---------------------------------------------------------------------------
STEP("item keys are the same in every client")
local mine = "item:101:0:0:0:0:0:0:123456:30:71:0:0:0"
local theirs = "item:101:0:0:0:0:0:0:987654:28:262:0:0:0"
check(Loot.Key(mine) == Loot.Key(theirs), "level, spec and unique ID don't change the key")
check(Loot.Normalize(mine) == Loot.Normalize(theirs), "nor the item string that is sent")
check(Loot.Key("item:101:0:0:0:0:0:-12:1") ~= Loot.Key("item:101:0:0:0:0:0:-14:1"), "a random suffix does")
check(Loot.Key("item:101::::::::30:71::5:2:400:401") ~= Loot.Key("item:101::::::::30:71::5:1:400"), "bonus IDs do")
check(Loot.Key("item:101::::::::30:71::5:2:400:401") == "101:0:400,401", "key: id, suffix, bonus IDs")
check(Loot.ItemStringOf(MakeLink("item:101::::::::30:71")) == "item:101::::::::30:71", "item string out of a link")

---------------------------------------------------------------------------
STEP("rating: the best Pawn scale against what I wear")
local r = eval(101)
check(r.status == "U", "a better helm is an upgrade")
check(near(r.pct, 20), "scale B gains 20 % (A only 10 %): the best scale counts, got " .. tostring(r.pct))
check(r.scale == "Scale B", "and its name comes along")
check(r.ilvl == 3 and r.slot == 1, "item level difference and slot")

r = eval(100)
check(r.status == "S" and r.pct == 0, "the helm I wear is no upgrade")

r = eval(102)
check(r.status == "X" and r.reason == "armor", "Pawn says: not my armor type")
r = eval(101, false)
check(r.status == "X" and r.reason == "need", "I can't roll need on it")
r = eval(150)
check(r.status == "-", "a potion is nothing you wear")

r = eval(112)
check(r.status == "U" and near(r.pct, 50), "a ring is measured against the weaker ring (20 -> 30 = +50 %)")
check(r.slot == 12, "and would go where the weaker one is")

r = eval(130)
check(r.status == "E" and r.slot == 8, "boots where I have none fill an empty slot")

r = eval(140)
check(r.status == "U" and near(r.pct, 5 / 30 * 100), "a trinket Pawn can't score: the item level decides, against the weaker one")
check(r.scale == nil, "and no scale is named then")

---------------------------------------------------------------------------
STEP("rating: weapons")
r = eval(122)
check(r.status == "U" and r.slot == 16, "two-hander against sword + shield together")
check(near(r.pct, 20), "120 against 60 + 40 = +20 %, got " .. tostring(r.pct))
r = eval(124)
check(near(r.pct, 20) and r.slot == 16, "a one-hander against the main hand when not dual wielding")
r = eval(123)
check(near(r.pct, 75) and r.slot == 17, "a shield against the shield")

WORN[16], WORN[17] = "item:122::::::::30:71", nil
r = eval(123)
check(near(r.pct, (70 - 60) / 60 * 100), "a shield next to a two-hander: against half of it")
r = eval(124)
check(near(r.pct, 20), "a one-hander next to a two-hander too: 72 against 60")

WORN[16], WORN[17] = "item:120::::::::30:71", "item:124::::::::30:71"
DUAL_WIELD = true
ITEMS[125] = { name = "Third Sword", equipLoc = "INVTYPE_WEAPON", ilvl = 34, values = { A = 66 } }
r = eval(125)
check(r.slot == 16 and near(r.pct, 10), "dual wielding: against the weaker weapon")
DUAL_WIELD = false
wear()

---------------------------------------------------------------------------
STEP("rating: waits for item data, works without Pawn")
NOT_LOADED[101] = true
local r1, why = eval(101)
check(r1 == nil and why == "wait", "not loaded yet: wait")
NOT_LOADED[101] = nil
NOT_LOADED[100] = true
r1, why = eval(101)
check(r1 == nil and why == "wait", "the worn helm not loaded yet: wait too")
NOT_LOADED[100] = nil

RemovePawn()
r = eval(101)
check(r.status == "U" and near(r.pct, 10) and r.scale == nil, "without Pawn the item level decides (30 -> 33)")
r = eval(102)
check(r.status == "U", "without Pawn nothing knows the armor type")
InstallPawn({ "A", "B" })

---------------------------------------------------------------------------
STEP("gear messages")
local snap = G.Snapshot()
check(#snap == 16, "16 slots shared")
local msgs = Comm.GearMessages(snap)
for _, m in ipairs(msgs) do check(#m <= 250, "a gear message fits") end
-- lots of big numbers still fit
for _, e in ipairs(snap) do e.itemID, e.ilvl, e.score = 234567, 640, 12345.6 end
msgs = Comm.GearMessages(snap)
check(#msgs >= 2, "and are split when needed")
for _, m in ipairs(msgs) do check(#m <= 250, "every part fits") end
for _, m in ipairs(msgs) do Comm.Receive(m, "Thrall-MyRealm") end
local th = ns.members.Thrall
check(th and th.gear[1].itemID == 234567 and th.gear[1].ilvl == 640 and near(th.gear[1].score, 12345.6), "gear arrives whole")
check(th.gear[18] == nil and th.gear[17].itemID == 234567, "every slot of it")
Comm.Receive("G^8:0:0:", "Thrall-MyRealm")
check(th.gear[8] == false, "an empty slot is sent as empty")
Comm.Receive("G^1:100:30:", SECRET)
check(ns.members[SECRET] == nil, "a hidden sender is ignored")

---------------------------------------------------------------------------
STEP("a roll: rate, send, show")
GROUP = { { name = "Thrall", class = "SHAMAN" }, { name = "Jaina", class = "MAGE" }, { name = "Varian", class = "WARRIOR" } }
FireEvent("GROUP_ROSTER_UPDATE")
check(ns.members.Thrall, "people still in the group are kept")
Comm.Receive("H^1^0.1.0", "Thrall-MyRealm")
Comm.Receive("H^1^0.1.0", "Varian")
RunTimers(5)
SENT = {}
ROLLS[7] = { "item:101::::::::30:71" }
FireEvent("START_LOOT_ROLL", 7, 60000)
RunTimers(1)
local d = Loot.drops[1]
check(d and d.key == "101:0:", "the drop is listed")
check(d.results.Alex and d.results.Alex.status == "U", "and I rated it")
local sentE
for _, m in ipairs(SENT) do if m.text:sub(1, 2) == "E^" then sentE = m end end
check(sentE and sentE.channel == "PARTY", "my verdict went to the party")
check(sentE.text == "E^item:101^U^20.0^3^Scale B^", "as one short line: " .. tostring(sentE and sentE.text))
check(GearShareLootFrame and GearShareLootFrame:IsShown(), "the loot window opened by itself")

-- the others answer (Thrall's client saw the drop with his own level and spec)
Comm.Receive("E^item:101::::::::28:262^U^35.5^5^Enhancement^", "Thrall-MyRealm")
Comm.Receive("E^item:101^X^^^^armor", "Varian")
RunTimers(1)
check(#Loot.drops == 1, "their verdicts land on the same drop")
local rank = Loot.Ranking(d)
check(rank[1].name == "Thrall" and rank[2].name == "Alex", "biggest upgrade first")
check(rank[3].name == "Varian" and rank[3].kind == "X", "then who can't use it")
check(rank[4].name == "Jaina" and rank[4].kind == "none", "Jaina has no GearShare: last")
local text = AllText(GearShareLootFrame)
check(text:find("+35.5 %", 1, true) and text:find("wrong armor", 1, true) and text:find("no GearShare", 1, true), "the window shows it all")
check(text:find("Enhancement", 1, true), "with the scale")

-- an item that is new to me (no roll window for me): I rate it as well
SENT = {}
Comm.Receive("E^item:130^E^^31^^", "Thrall-MyRealm")
RunTimers(1)
local boots = Loot.byKey["130:0:"]
check(boots and boots.results.Alex and boots.results.Alex.status == "E", "I rated the boots too")
check(#SENT == 1 and SENT[1].text:find("^E%^item:130"), "and sent it")
check(Loot.Ranking(boots)[1].kind == "E", "an empty slot ranks first")

-- a potion verdict is no drop
Comm.Receive("E^item:150^U^5^1^^", "Thrall-MyRealm")
RunTimers(1)
check(Loot.byKey["150:0:"] == nil or Loot.byKey["150:0:"].results.Thrall, "a potion is not rated by me")

---------------------------------------------------------------------------
STEP("posting the ranking")
CHAT = {}
Loot:Announce(d)
check(#CHAT == 1 and CHAT[1].channel == "PARTY", "one line to the party")
check(CHAT[1].text:find("Thrall +35.5 %", 1, true) and CHAT[1].text:find("Alex +20.0 %", 1, true), "who gains how much: " .. CHAT[1].text)
check(not CHAT[1].text:find("Varian", 1, true), "only those it helps")

---------------------------------------------------------------------------
STEP("/gs check")
SENT = {}
SlashCmdList.GEARSHARE("check " .. MakeLink("item:112::::::::30:71"))
RunTimers(2)
check(SENT[1] and SENT[1].text == "C^item:112", "the question goes out first")
check(SENT[2] and SENT[2].text:find("^E%^item:112%^U"), "then my own verdict")
SENT = {}
Comm.Receive("C^item:130", "Varian")
RunTimers(2)
check(#SENT == 1 and SENT[1].text:find("^E%^item:130%^E"), "someone else's question gets my answer")

---------------------------------------------------------------------------
STEP("the queue waits for the end of combat and for the game")
SENT = {}
IN_COMBAT = true
Comm.SendGear()
RunTimers(3)
check(#SENT == 0, "nothing goes out in combat")
IN_COMBAT = false
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers(3)
check(#SENT >= 1 and SENT[1].text:sub(1, 2) == "G^", "it goes out after combat")
SENT = {}
SEND_RESULT = 3
Comm.SendHello()
RunTimers(3)
check(#SENT == 0, "the game says no: nothing sent")
SEND_RESULT = 0
RunTimers(5)
check(#SENT >= 2 and SENT[1].text:sub(1, 2) == "H^", "it is tried again")

---------------------------------------------------------------------------
STEP("group overview")
SlashCmdList.GEARSHARE("gear")
RunTimers(1)
check(GearShareGroupFrame and GearShareGroupFrame:IsShown(), "it opens")
local g = AllText(GearShareGroupFrame)
check(g:find("Thrall", 1, true) and g:find("640", 1, true), "Thrall's gear is in it")
check(g:find("2 without GearShare data", 1, true), "Jaina and Varian sent no gear")

---------------------------------------------------------------------------
STEP("slash commands and the test drop")
Loot:Clear()
check(#Loot.drops == 0, "cleared")
SlashCmdList.GEARSHARE("test")
RunTimers(1)
check(#Loot.drops == 1 and Loot.drops[1].demo and Loot.drops[1].results.Alex, "a test drop with my own verdict")
check(AllText(GearShareLootFrame):find("Thrall", 1, true), "and made-up members")
SlashCmdList.GEARSHARE("auto off")
check(ns.db.autoShow == false and logHas("only opens"), "auto off")
SlashCmdList.GEARSHARE("help")
check(logHas("/gs check"), "help lists the commands")
SlashCmdList.GEARSHARE("")
check(not GearShareLootFrame:IsShown(), "/gs closes the window")

---------------------------------------------------------------------------
STEP("German")
LOCALE = "deDE"
local before = #ALL_FRAMES
local nsDE = LoadAddon(".")
check(nsDE.L["Head"] == "Kopf" and nsDE.L["empty slot"] == "leerer Platz", "German words")
LOCALE = nil

LOG[#LOG + 1] = "ALL TESTS PASSED"
