package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
M.class, M.className = "HUNTER", "Hunter"
M.trees = { { 50, "Beast Mastery", 31 }, { 163, "Marksmanship", 5 }, { 51, "Survival", 0 } }
M.pet = { name = "Fang", family = "Wolf", familyID = 1, happiness = 3 }
M.spellNames = { [17253] = "Bite", [16827] = "Claw" }
local ns = M.loadAddon(".", "BeastMode")
local BM, UI = KennyBeastMode, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
check(KennyBeastModeDB and KennyBeastModeDB.session, "saved variables set up")
check(UI.Frame() ~= nil and UI.Frame():IsShown(), "window built and shown for a Hunter")
local pt = UI.Frame().points[#UI.Frame().points]
check(pt[1] == "CENTER" and pt[4] == 0 and pt[5] == -210, "default spot CENTER 0,-210")
check(BM.theme.tree == "Beast Mastery" and BM.theme.sound == 1266218, "Beast Mastery theme, hawk screech")
for _, sl in ipairs(ns.THEME.order) do check(ns.THEME.trees[sl], "tree " .. sl .. " has an entry") end

-- pet identity and happiness colours
check(UI.Frame().pet:GetText():find("Fang", 1, true) and UI.Frame().pet:GetText():find("Wolf", 1, true), "pet name and family")
check(UI.Frame().mood:GetText():find("34C759", 1, true) and UI.Frame().mood:GetText():find("Happy", 1, true), "happy = green")
M.pet.happiness = 2; M.fire("UNIT_HAPPINESS", "pet")
check(UI.Frame().mood:GetText():find("FFD60A", 1, true), "content = yellow")
M.pet.happiness = 1; M.fire("UNIT_HAPPINESS", "pet")
check(UI.Frame().mood:GetText():find("FF3B30", 1, true), "unhappy = red")
M.pet.happiness = 3; M.fire("UNIT_HAPPINESS", "pet")
local savedPet = M.pet; M.pet = nil; M.fire("UNIT_PET", "player")
check(BM.petInfo == nil and UI.Frame().pet:GetText():find("No pet out", 1, true), "no pet out")
M.pet = savedPet; M.fire("UNIT_PET", "player")
local secretName = {}; M.secret[secretName] = true
M.pet.family = secretName; M.fire("UNIT_PET", "player")
check(BM.petInfo.family == nil and BM.petInfo.name == "Fang", "secret family is left out, not guessed")
M.pet.family = "Wolf"; M.fire("UNIT_PET", "player")

-- pet abilities and the Hawk
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "p1", 17253)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "p1b", 17253) -- same instant: deduped
check(BM.fight.pet == 1 and UI.Frame().head:GetText() == "BITE!", "pet ability flashes and counts once")
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "p2", 16827)
check(BM.fight.pet == 2 and BM.fight.abilities[16827] == 1, "second ability counted by spell")
check(#M.sounds == 0, "default sound mode: pet abilities are quiet")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h1", 1293527)
check(BM.fight.hawks == 1 and UI.Frame().head:GetText() == "HAWK!" and #M.sounds == 1 and M.sounds[1][1] == 1266218, "Hawk: flash, count and screech")
local secretID = {}; M.secret[secretID] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "p3", secretID)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "p4", 17253)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "p5", 75) -- Auto Shot
check(BM.fight.pet == 2 and BM.fight.hawks == 1, "secret IDs, other units and other player spells ignored")
local secretTotal = setmetatable({}, { __tostring = function() return "SECRET" end }); M.secret[secretTotal] = true
M.meter = { total = secretTotal, rows = { { 75, secretTotal } } }
UI.RenderLive()
check(true, "live render with secret values")
check(UI.Frame().reset.shown == false, "Reset button hidden in combat")

-- after combat: you / pet / Hawk split from the meter's creature names
M.combat = false
M.meter = { total = 10000, rows = { { 75, 4000 }, { 3044, 1000 }, { 6603, 2000, "Fang" }, { 17253, 1000, "Fang" },
  { 1293527, 500 }, { 6603, 1500, "Hawk" } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
local f = BM.lastFight
check(f and f.you == 5000 and f.petDmg == 3000 and f.hawkDmg == 2000, "split: you 5000, pet 3000, Hawk 2000")
check(math.abs(f.youShare - 0.5) < 1e-9 and math.abs(f.petShare - 0.3) < 1e-9 and math.abs(f.hawkShare - 0.2) < 1e-9, "split shares")
local s = BM.SessionStats()
check(s.pet == 2 and s.hawks == 1 and s.petDmg == 3000 and s.total == 10000, "session totals")
check(KennyBeastModeDB.petSplits == true, "learned that the meter lists pet lines")
check(table.concat(UI.Lines(), "\n"):find("Pet 30%", 1, true), "window shows the pet share")
check(UI.Frame().reset.shown == true, "Reset back after combat")
-- meter folds the pet into the Hunter: counting pet casts only
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "p9", 17253)
M.combat = false; M.meter = { total = 3000, rows = { { 75, 3000 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
check(BM.lastFight.petDmg == 0 and KennyBeastModeDB.petSplits == false, "no pet lines: nothing made up")
check(table.concat(UI.Lines(), "\n"):find("counting pet casts only", 1, true), "window says counting pet casts only")
-- secret creature names after combat: no split
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.combat = false; M.meter = { total = 100, rows = { { 6603, 100, secretName } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(10)
check(BM.lastFight.total == nil, "secret creature name: no split")

-- slash commands (both names)
M.slash("/beastmode", "reset")
check(BM.SessionStats().pet == 0, "reset")
M.slash("/bmode", "size 9999 1")
check(BM.Settings().width == UI.MAX_W and BM.Settings().height == UI.MIN_H, "size is clamped")
M.slash("/bmode", "scale 9")
check(BM.Settings().scale == 2, "scale is clamped")
M.sounds = {}
M.slash("/bmode", "soundfile owl")
check(BM.Settings().soundFile == "owl" and M.sounds[1][1] == 557977, "sound file preview")
M.slash("/bmode", "sound every")
M.sounds = {}
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "pz", 16827)
check(#M.sounds == 1, "sound every: pet abilities play too")
M.slash("/bmode", "sound bogus")
check(BM.Settings().sound == "every", "unknown sound mode refused")
M.prints = {}
M.slash("/bmode", "meter")
check(M.printed("your damage") or M.printed("no readable"), "meter command answers")
M.combat = true; M.prints = {}
M.slash("/bmode", "test")
check(M.printed("not in combat"), "no test in combat")
M.combat = false
M.slash("/bmode", "lock")
check(BM.Settings().locked, "lock")
M.slash("/bmode", "resetpos")
check(KennyBeastModeDB.point == nil, "resetpos")
M.class = "ROGUE"; M.prints = {}
M.slash("/bmode", "show")
check(not UI.Frame():IsShown() and M.printed("only shows on a Hunter"), "hidden for non-Hunters")
M.class = "HUNTER"; M.slash("/bmode", "show")
check(UI.Frame():IsShown(), "show")
M.done("BeastMode")
