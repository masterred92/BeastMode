-- Beast Mode: a pet and Hawk box for Hunters on WoW: Forever. Written from scratch (MIT).
--
-- What it reads:
--   * Pet identity: UnitName("pet"), UnitCreatureFamily("pet") and C_PetInfo.GetPetHappiness() (1 = unhappy,
--     2 = content, 3 = happy, the same scale Blizzard's own PetHappiness.lua uses).
--   * Pet abilities: the pet's own UNIT_SPELLCAST_SUCCEEDED. Each one flashes the box and counts.
--   * Hawk: Summon Hawk ranks 1293241, 1293525, 1293526, 1293527 (SkillLineAbility, Beast Mastery 50, Hunter class
--     mask; wago.tools db2, build 1.60.1.70862). The hawk dives, then stays for 18 seconds as a summoned helper.
--   * After combat, Blizzard's own damage meter (C_DamageMeter). Its spell lines carry a creatureName for damage done
--     by a pet or other helper (Blizzard_DamageMeter formats those as "spell (creature)"), so the split is:
--     you = lines with no creature; pet = lines from your pet's name; Hawk = Summon Hawk lines and any other helper.
--
-- Addons on this client get no combat log and every hit amount is a secret value, so nothing here guesses a number.
-- The split is only worked out after combat, when the meter's numbers are plain. Blizzard's pet frame is left alone.
local ADDON, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L

-- Slash commands: the first is the main one shown in help text. Change them here only.
ns.SLASH = { "/bmode", "/beastmode" }

local BM = {}
KennyBeastMode = BM
ns.BM = BM

local SCHEMA = 1
local DEDUPE = 0.25

BM.HAWK = { [1293241] = 1, [1293525] = 2, [1293526] = 3, [1293527] = 4 }
-- Happiness colours: red / yellow / green.
BM.HAPPINESS = { [1] = { label = L["Unhappy"], color = "FF3B30" }, [2] = { label = L["Content"], color = "FFD60A" },
  [3] = { label = L["Happy"], color = "34C759" } }

-- Built-in sound files (FileDataIDs, from the community listfile; checked by tools/verify_media.sh). No bundled audio.
BM.SOUNDS = {
  screech = 1266218, -- sound/creature/eagle/mon_eagle_aggro_01.ogg
  owl = 557977,      -- sound/creature/owl/owlaggro.ogg
  dragonhawk = 547519, -- sound/creature/dragonhawk/dragonhawkaggro.ogg
}
BM.SOUND_MODES = { hawk = true, every = true, off = true }

BM.DEFAULTS = {
  shown = true, locked = false, scale = 1, width = 240, height = 150, sound = "hawk", soundFile = "theme",
}

local db, settings
local migrations = {} -- schema 1 is the first release

local function now() return C.Clock() end

local function newFight()
  return { pet = 0, hawks = 0, abilities = {}, petNames = {}, start = now() }
end
local function newSession()
  return { pet = 0, hawks = 0, fights = 0, total = 0, you = 0, petDmg = 0, hawkDmg = 0, since = C.Now() }
end

BM.fight = newFight()
BM.lastFight = nil
BM.petInfo = nil -- { name, family, happiness } or nil when no pet is out

function BM.DB() return db end
function BM.Settings() return settings end
function BM.Session() return db and db.session end

function BM.ClassFile() return C.Safe(UnitClass and select(2, UnitClass("player"))) end
function BM.ClassMatches() return BM.ClassFile() == "HUNTER" end

function BM.Play()
  local pick = settings and settings.soundFile or "theme"
  local id = (pick == "theme" and BM.theme and BM.theme.sound) or BM.SOUNDS[pick] or BM.SOUNDS.screech
  local ok, willPlay = pcall(PlaySoundFile, id, "Master")
  return ok and willPlay ~= false
end

-- ---------- pet ----------
function BM.ReadPet()
  local exists = UnitExists and C.Safe(UnitExists("pet"))
  if not exists then return nil end
  local name = UnitName and C.Safe(UnitName("pet"))
  local family = UnitCreatureFamily and C.Safe(UnitCreatureFamily("pet"))
  local happiness
  if C_PetInfo and C_PetInfo.GetPetHappiness then
    local ok, h = pcall(C_PetInfo.GetPetHappiness)
    if ok then happiness = C.SafeNumber(h) end
  end
  return { name = name, family = family, happiness = happiness }
end

function BM.UpdatePet()
  BM.petInfo = BM.ReadPet()
  if BM.petInfo and BM.petInfo.name then BM.fight.petNames[BM.petInfo.name] = true end
  if ns.UI then ns.UI.RefreshPet() end
  return BM.petInfo
end

-- ---------- casts ----------
local lastSeen = {}
local function fresh(key, t)
  if lastSeen[key] and t - lastSeen[key] < DEDUPE then return false end
  lastSeen[key] = t
  return true
end

function BM.OnPetAbility(spellID, t)
  t = t or now()
  if not fresh("pet" .. tostring(spellID), t) then return false end
  local f = BM.fight
  f.pet = f.pet + 1
  f.abilities[spellID] = (f.abilities[spellID] or 0) + 1
  if db then db.session.pet = db.session.pet + 1 end
  if settings and settings.sound == "every" then BM.Play() end
  local name = C_Spell and C_Spell.GetSpellName and C.Safe(C_Spell.GetSpellName(spellID))
  if ns.UI then ns.UI.OnAbility(name) end
  return true
end

function BM.OnHawk(t)
  t = t or now()
  if not fresh("hawk", t) then return false end
  local f = BM.fight
  f.hawks = f.hawks + 1
  if db then db.session.hawks = db.session.hawks + 1 end
  local mode = settings and settings.sound or BM.DEFAULTS.sound
  if mode == "hawk" or mode == "every" then BM.Play() end
  if ns.UI then ns.UI.OnHawk() end
  return true
end

function BM.OnSpellcast(unit, _, spellID)
  if C.IsSecret(spellID) or type(spellID) ~= "number" then return end
  if unit == "pet" then BM.OnPetAbility(spellID)
  elseif unit == "player" and BM.HAWK[spellID] then BM.OnHawk() end
end

-- ---------- Blizzard's damage meter ----------
local function playerGUID() return UnitGUID and UnitGUID("player") end

function BM.MeterAvailable()
  if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then return false, "no C_DamageMeter" end
  local ok, avail, why = pcall(C_DamageMeter.IsDamageMeterAvailable)
  if not ok then return false, tostring(avail) end
  return avail == true, why
end

function BM.MeterSource()
  if not C_DamageMeter then return nil end
  local guid = playerGUID()
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  if C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionSourceFromID then
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    local newest
    if ok and type(list) == "table" then
      for _, s in ipairs(list) do
        local id = C.SafeNumber(s.sessionID)
        if id and (not newest or id > newest) then newest = id end
      end
    end
    if newest then
      local ok2, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, newest, dmg, guid)
      if ok2 and type(src) == "table" then return src end
    end
  end
  if C_DamageMeter.GetCombatSessionSourceFromType then
    local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, guid)
    if ok and type(src) == "table" then return src end
  end
  return nil
end

function BM.LiveSource()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
  local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, playerGUID())
  if ok and type(src) == "table" then return src end
  return nil
end

-- Plain-number split: { total, you, pet, hawk, petSplit, hawkSplit, rows }, or nil while anything is secret.
-- petNames = set of the pet names seen this fight.
function BM.ReadMeter(src, petNames)
  src = src or BM.MeterSource()
  petNames = petNames or BM.fight.petNames
  if type(src) ~= "table" then return nil, "no meter data" end
  local total = C.SafeNumber(src.totalAmount)
  if not total then return nil, "secret" end
  local out = { total = total, you = 0, pet = 0, hawk = 0, rows = {}, petSplit = false, hawkSplit = false }
  for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id, amount = C.SafeNumber(sp.spellID), C.SafeNumber(sp.totalAmount)
    local creature = sp.creatureName
    if not (id and amount) or C.IsSecret(creature) then return nil, "secret" end
    creature = type(creature) == "string" and creature or ""
    local who
    if BM.HAWK[id] then who = "hawk"
    elseif creature ~= "" then who = petNames[creature] and "pet" or "hawk"
    else who = "you" end
    out[who] = out[who] + amount
    if who == "pet" then out.petSplit = true elseif who == "hawk" then out.hawkSplit = true end
    out.rows[#out.rows + 1] = { spellID = id, amount = amount, creature = creature, who = who }
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

-- ---------- fights ----------
function BM.StartFight()
  BM.fight = newFight()
  BM.fight.inCombat = true
  BM.UpdatePet()
  if ns.UI then ns.UI.OnCombat(true) end
end

function BM.EndFight()
  local f = BM.fight
  f.inCombat = false
  f.duration = math.max(0, now() - f.start)
  if ns.UI then ns.UI.OnCombat(false) end
  local tries = 0
  local function attempt()
    tries = tries + 1
    if BM.fight ~= f or f.done then return end
    local r = BM.ReadMeter(nil, f.petNames)
    if r or tries >= 4 then BM.FinishFight(f, r) return end
    C_Timer.After(1, attempt)
  end
  C_Timer.After(0.5, attempt)
end

local function share(part, total) return total > 0 and part / total or 0 end

function BM.FinishFight(f, r)
  f.done = true
  local res = { pet = f.pet, hawks = f.hawks, duration = f.duration or 0 }
  if r then
    res.total, res.you, res.petDmg, res.hawkDmg = r.total, r.you, r.pet, r.hawk
    res.petSplit, res.hawkSplit = r.petSplit, r.hawkSplit
    res.youShare, res.petShare, res.hawkShare = share(r.you, r.total), share(r.pet, r.total), share(r.hawk, r.total)
  end
  BM.lastFight = res
  if db and (f.pet > 0 or f.hawks > 0 or (r and r.total > 0)) then
    local s = db.session
    s.fights = s.fights + 1
    if r then
      s.total, s.you, s.petDmg, s.hawkDmg = s.total + r.total, s.you + r.you, s.petDmg + r.pet, s.hawkDmg + r.hawk
      if f.pet > 0 then db.petSplits = r.petSplit end
    end
  end
  if ns.UI then ns.UI.Refresh() end
  return res
end

function BM.ResetSession()
  if not db then return end
  db.session = newSession()
  BM.lastFight = nil
  if ns.UI then ns.UI.Refresh() end
end

function BM.SessionStats()
  local s = db and db.session
  if not s then return nil end
  local t = s.total
  return { pet = s.pet, hawks = s.hawks, fights = s.fights, total = t, you = s.you, petDmg = s.petDmg, hawkDmg = s.hawkDmg,
    youShare = t > 0 and s.you / t or nil, petShare = t > 0 and s.petDmg / t or nil, hawkShare = t > 0 and s.hawkDmg / t or nil }
end

-- ---------- theme: Hunter colours, then the talent tree with the most points ----------
local function hex(h)
  h = tostring(h or "FFFFFF")
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
BM.Hex = hex

function BM.TreePoints()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  configID = ok and C.SafeNumber(configID)
  if not configID then return nil end
  local ok2, cfg = pcall(C_Traits.GetConfigInfo, configID)
  local treeID = ok2 and type(cfg) == "table" and type(cfg.treeIDs) == "table" and C.SafeNumber(cfg.treeIDs[1])
  if not treeID then return nil end
  local ok3, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not ok3 or type(displays) ~= "table" or #displays == 0 then return nil end
  local ids = {}
  for i, d in ipairs(displays) do ids[i] = d.groupID end
  local ok4, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not ok4 or type(groups) ~= "table" then return nil end
  local spentBy = {}
  for _, g in ipairs(groups) do
    local cur = type(g.currencyInfos) == "table" and g.currencyInfos[1]
    local id = C.SafeNumber(g.traitNodeGroupID)
    if id and cur then spentBy[id] = C.SafeNumber(cur.spent) end
  end
  local out = {}
  for _, d in ipairs(displays) do
    out[#out + 1] = { skillLine = C.SafeNumber(d.skillLineID), order = C.SafeNumber(d.orderIndex) or #out,
      name = C.Safe(d.displayName), spent = spentBy[C.SafeNumber(d.groupID) or -1] or 0 }
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

function BM.PickTree(classTheme, points)
  if type(points) ~= "table" or not classTheme then return nil end
  local best, bestPos, second = nil, nil, -1
  for pos, t in ipairs(points) do
    if not best or t.spent > best.spent then
      if best then second = best.spent end
      best, bestPos = t, pos
    elseif t.spent > second then second = t.spent end
  end
  if not best or best.spent <= 0 or best.spent == second then return nil end
  local trees = classTheme.trees or {}
  if best.skillLine and trees[best.skillLine] then return trees[best.skillLine], best end
  local byOrder = classTheme.order and classTheme.order[bestPos]
  if byOrder and trees[byOrder] then return trees[byOrder], best end
  return nil
end

function BM.ResolveTheme(points)
  local base = ns.THEME
  local tree, info = BM.PickTree(base, points)
  local th = { tree = info and info.name, sound = tree and tree.sound or base.sound }
  th.frame = { hex(base.frame) }
  th.accent = { hex(tree and tree.accent or base.accent) }
  th.title = { hex(base.title or base.frame) }
  th.hawk = { hex(base.hawk or base.accent) }
  return th
end

function BM.UpdateTheme()
  BM.theme = BM.ResolveTheme(BM.TreePoints())
  if ns.UI and ns.UI.ApplyTheme then ns.UI.ApplyTheme(BM.theme) end
  return BM.theme
end
BM.theme = BM.ResolveTheme(nil)

-- ---------- text helpers ----------
function BM.Short(n)
  n = C.SafeNumber(n)
  if not n then return "?" end
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fK"):format(n / 1e3) end
  return tostring(math.floor(n + 0.5))
end
function BM.Pct(x) return x and ("%d%%"):format(math.floor(x * 100 + 0.5)) or "-" end

function BM.StateLines()
  local s = BM.SessionStats() or {}
  local avail, why = BM.MeterAvailable()
  local p = BM.petInfo
  local f = BM.lastFight
  return {
    "settings: sound=" .. tostring(settings and settings.sound) .. " file=" .. tostring(settings and settings.soundFile),
    "class: " .. tostring(BM.ClassFile()) .. " / tree: " .. tostring(BM.theme and BM.theme.tree or "class default"),
    "pet: " .. (p and ("%s / %s / happiness %s"):format(tostring(p.name), tostring(p.family), tostring(p.happiness)) or "none"),
    "damage meter available: " .. tostring(avail) .. (why and why ~= "" and (" (" .. tostring(why) .. ")") or ""),
    "meter lists pet lines: " .. tostring(db and db.petSplits),
    ("session: %s pet abilities, %s hawks, %s fights"):format(tostring(s.pet), tostring(s.hawks), tostring(s.fights)),
    "last fight: " .. (f and ("%d pet abilities, %d hawks, you %s pet %s hawk %s"):format(f.pet, f.hawks, BM.Short(f.you), BM.Short(f.petDmg), BM.Short(f.hawkDmg)) or "none"),
  }
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
ev:RegisterUnitEvent("UNIT_PET", "player")
ev:RegisterEvent("UNIT_HAPPINESS")
for _, e in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do ev:RegisterEvent(e) end

local handlers = {
  PLAYER_REGEN_DISABLED = function() BM.StartFight() end,
  PLAYER_REGEN_ENABLED = function()
    BM.EndFight()
    if BM.themeStale then BM.themeStale = false; BM.UpdateTheme() end
  end,
  UNIT_SPELLCAST_SUCCEEDED = BM.OnSpellcast,
  UNIT_PET = function() BM.UpdatePet() end,
  UNIT_HAPPINESS = function() BM.UpdatePet() end,
  PLAYER_LOGIN = function()
    BM.UpdateTheme()
    BM.UpdatePet()
    if ns.UI then ns.UI.UpdateVisibility() end
  end,
}
local function talentsChanged() if C.InCombat() then BM.themeStale = true else BM.UpdateTheme() end end
handlers.TRAIT_CONFIG_UPDATED, handlers.ACTIVE_TALENT_GROUP_CHANGED, handlers.PLAYER_TALENT_UPDATE = talentsChanged, talentsChanged, talentsChanged

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyBeastModeDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    KennyBeastModeDB = db
    settings = Core.Settings(db.settings, BM.DEFAULTS)
    if ns.UI then Core.SafeCall("build", ns.UI.Build, db, settings) end
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = ns.SLASH[1],
  required = { "C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.GetAvailableCombatSessions",
    "C_DamageMeter.GetCombatSessionSourceFromID", "PlaySoundFile", "C_Timer.After", "UnitGUID", "UnitName" },
  optional = { "C_PetInfo.GetPetHappiness", "UnitCreatureFamily", "C_DamageMeter.IsDamageMeterAvailable", "AbbreviateNumbers",
    "C_ClassTalents.GetActiveConfigID", "C_Traits.GetGroupDisplayInfoByTreeID", "C_Traits.GetGroupCurrencyInfo" },
  db = function() return db end,
  firstRun = { L["Pet and Hawk box ready. Drag the box to move it; type %s for options."]:format(ns.SLASH[1]) },
  debugLines = function() return BM.StateLines() end })
