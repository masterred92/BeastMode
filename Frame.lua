-- Beast Mode window: a small hunter-green and leather box. Blizzard textures and fonts only. It sits beside
-- Blizzard's pet frame and never replaces or moves it. In combat the meter's numbers are secret: they go straight
-- into SetFormattedText (which accepts secret values) and are never compared or added here.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L
local BM = ns.BM

local UI = {}
ns.UI = UI
local frame, db, settings, ticker
local ICON = "Interface\\Icons\\Ability_Hunter_AnimalHandler" -- 132158, Summon Hawk's own icon
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local BG, EDGE = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
UI.DEFAULT_POINT = { "CENTER", 0, -210 }

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

function UI.Place()
  local p = db.point or UI.DEFAULT_POINT
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

function UI.ApplyTheme(th)
  if not frame or not th then return end
  local fr, fg, fb = unpack(th.frame)
  local ar, ag, ab = unpack(th.accent)
  frame:SetBackdropBorderColor(fr, fg, fb, 1)
  frame.title:SetTextColor(unpack(th.title))
  frame.bar:SetStatusBarColor(ar, ag, ab)
  frame.flash:SetColorTexture(ar, ag, ab, 1)
  frame.head:SetTextColor(ar, ag, ab)
  frame.rule:SetColorTexture(fr, fg, fb, 0.9)
  frame.tree:SetText(th.tree or "")
end

function UI.ApplyLayout()
  frame:SetSize(settings.width, settings.height)
  frame:SetScale(settings.scale)
end

-- Shown when the setting is on and the character is a Hunter.
function UI.UpdateVisibility()
  if not frame then return end
  frame:SetShown(settings.shown and BM.ClassMatches())
end

function UI.Build(database, s)
  db, settings = database, s
  frame = CreateFrame("Frame", "KennyBeastModeFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = BG, edgeFile = EDGE, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0.08, 0.06, 0.03, 0.88) -- dark leather
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    db.point = { p, x, y }
  end)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -7)
  frame.title = fs(frame, "GameFontNormal")
  frame.title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
  frame.title:SetText("Beast Mode")
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("TOPRIGHT", -9, -11)
  frame.tree:SetJustifyH("RIGHT")
  frame.title:SetPoint("RIGHT", frame.tree, "LEFT", -4, 0)
  frame.title:SetWordWrap(false)
  frame.rule = frame:CreateTexture(nil, "ARTWORK")
  frame.rule:SetHeight(1)
  frame.rule:SetPoint("TOPLEFT", 8, -28)
  frame.rule:SetPoint("TOPRIGHT", -8, -28)

  -- pet line: name (family) on the left, happiness pip and word on the right
  frame.pet = fs(frame, "GameFontHighlight")
  frame.pet:SetPoint("TOPLEFT", 10, -33)
  frame.pet:SetPoint("RIGHT", -80, 0)
  frame.pet:SetWordWrap(false)
  frame.mood = fs(frame, "GameFontHighlightSmall")
  frame.mood:SetPoint("TOPRIGHT", -10, -35)
  frame.mood:SetJustifyH("RIGHT")
  frame.pip = frame:CreateTexture(nil, "ARTWORK")
  frame.pip:SetSize(8, 8)
  frame.pip:SetPoint("RIGHT", frame.mood, "LEFT", -4, 0)

  frame.head = fs(frame, "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 10, -50)
  frame.head:SetPoint("RIGHT", -10, 0)
  frame.head:SetWordWrap(false)
  frame.lines = fs(frame)
  frame.lines:SetPoint("TOPLEFT", frame.head, "BOTTOMLEFT", 0, -3)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 30)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 30)
  frame.bar:SetHeight(10)
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(0)
  local barBg = frame.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  frame.barText = fs(frame.bar, "GameFontHighlightSmall")
  frame.barText:SetPoint("CENTER")

  local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  reset:SetSize(96, 18)
  reset:SetPoint("BOTTOMLEFT", 8, 7)
  reset:SetText(L["Reset session"])
  reset:SetScript("OnClick", function() BM.ResetSession(); Core.Print(L["session reset."]) end)
  frame.reset = reset

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    settings.width = math.floor(frame:GetWidth() + 0.5)
    settings.height = math.floor(frame:GetHeight() + 0.5)
  end)

  frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.flash:SetPoint("TOPLEFT", 3, -3)
  frame.flash:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.flash:SetBlendMode("ADD")
  frame.flash:SetAlpha(0)

  UI.ApplyLayout()
  UI.Place()
  UI.ApplyTheme(BM.theme)
  UI.UpdateVisibility()
  UI.RefreshPet()
  UI.Refresh()
  return frame
end

function UI.Frame() return frame end

local flashLeft = 0
local function flashTick(_, elapsed)
  flashLeft = flashLeft - elapsed
  if flashLeft <= 0 then frame.flash:SetAlpha(0); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(0.4 * flashLeft / 0.5)
end
local function flash()
  flashLeft = 0.5
  frame.flash:SetAlpha(0.4)
  frame:SetScript("OnUpdate", flashTick)
end

function UI.RefreshPet()
  if not frame then return end
  local p = BM.petInfo
  if not p then
    frame.pet:SetText("|cff999999" .. L["No pet out"] .. "|r")
    frame.mood:SetText(""); frame.pip:Hide()
    return
  end
  local name = p.name or L["Pet"]
  frame.pet:SetText(p.family and ("%s |cffaaaaaa(%s)|r"):format(name, p.family) or name)
  local h = p.happiness and BM.HAPPINESS[p.happiness]
  if h then
    local r, g, b = BM.Hex(h.color)
    frame.pip:SetColorTexture(r, g, b, 1); frame.pip:Show()
    frame.mood:SetText(("|cff%s%s|r"):format(h.color, h.label))
  else
    frame.mood:SetText(""); frame.pip:Hide()
  end
end

function UI.OnAbility(name)
  if not frame then return end
  frame.head:SetText(((name or L["Pet ability"]):upper()) .. "!")
  flash()
  UI.Refresh()
end

function UI.OnHawk()
  if not frame then return end
  frame.head:SetText(L["HAWK!"])
  flash()
  UI.Refresh()
end

function UI.OnCombat(inCombat)
  if frame then frame.reset:SetShown(not inCombat) end -- no Reset button in combat
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

local function hawkColour()
  local c = BM.theme and BM.theme.hawk or { 0.66, 0.6, 0.88 }
  return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Plain-number view (out of combat): last fight + session.
function UI.Lines()
  local f, s = BM.lastFight, BM.SessionStats() or {}
  local out = {}
  local cur = f or BM.fight
  out[#out + 1] = ("%s: %d %s, %d %s"):format(L["Fight"], cur.pet, L["pet abilities"], cur.hawks, L["hawks"])
  if f and f.total then
    out[#out + 1] = ("%s %s  %s %s  |cff%s%s %s|r"):format(L["You"], BM.Pct(f.youShare), L["Pet"], BM.Pct(f.petShare), hawkColour(), L["Hawk"], BM.Pct(f.hawkShare))
  end
  out[#out + 1] = ("%s: %s %s  %s %s  %s %s"):format(L["Session"], L["You"], BM.Pct(s.youShare), L["Pet"], BM.Pct(s.petShare), L["Hawk"], BM.Pct(s.hawkShare))
  if db and db.petSplits == false then out[#out + 1] = "|cffaaaaaa" .. L["Meter shows no pet lines: counting pet casts only."] .. "|r" end
  return out
end

function UI.Refresh()
  if not frame then return end
  if BM.fight.inCombat then UI.RenderLive() return end
  if not frame.head:GetText() or frame.head:GetText() == "" then frame.head:SetText(L["Ready to hunt"]) end
  frame.lines:SetText(table.concat(UI.Lines(), "\n"))
  local f, s = BM.lastFight, BM.SessionStats() or {}
  local petPart
  if f and f.total then petPart = (f.petShare or 0) + (f.hawkShare or 0)
  elseif s.petShare then petPart = s.petShare + (s.hawkShare or 0) end
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(petPart or 0)
  frame.barText:SetText(L["Pet + Hawk share"] .. " " .. BM.Pct(petPart))
end

-- Live view (in combat). Counts are plain; your meter total may be secret and is only handed to the widget.
function UI.RenderLive()
  if not frame then return end
  local f = BM.fight
  local head = ("%s: %d %s, %d %s"):format(L["Fight"], f.pet, L["pet abilities"], f.hawks, L["hawks"])
  local src = BM.LiveSource and BM.LiveSource()
  local total = src and src.totalAmount
  if total ~= nil and AbbreviateNumbers then
    frame.lines:SetFormattedText("%s\n%s: %s\n%s", head, L["Damage"], AbbreviateNumbers(total), L["You / pet / Hawk split after combat"])
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H

-- ---------- slash command (names live in ns.SLASH, top of BeastMode.lua) ----------
local function help()
  local c = ns.SLASH[1]
  Core.Print(c .. " show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print(c .. " sound hawk|every|off  |  soundfile theme|screech|owl|dragonhawk")
  Core.Print(c .. " meter (last fight's damage-meter lines) | theme | debug | report")
end

for i, cmd in ipairs(ns.SLASH) do _G["SLASH_KENNYBEASTMODE" .. i] = cmd end
SlashCmdList.KENNYBEASTMODE = function(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then
    settings.shown = true
    if not BM.ClassMatches() then Core.Print(L["this box only shows on a Hunter."]) end
    UI.UpdateVisibility(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; UI.UpdateVisibility()
  elseif cmd == "lock" then settings.locked = true; Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; Core.Print(L["frame unlocked."])
  elseif cmd == "resetpos" then
    db.point = nil; settings.width, settings.height, settings.scale = BM.DEFAULTS.width, BM.DEFAULTS.height, 1
    UI.ApplyLayout(); UI.Place(); Core.Print(L["frame moved back to its default spot and size."])
  elseif cmd == "scale" and tonumber(a) then
    settings.scale = math.max(0.5, math.min(2, tonumber(a))); UI.ApplyLayout()
  elseif cmd == "size" and tonumber(a) and tonumber(b) then
    settings.width = math.max(MIN_W, math.min(MAX_W, math.floor(tonumber(a))))
    settings.height = math.max(MIN_H, math.min(MAX_H, math.floor(tonumber(b))))
    UI.ApplyLayout()
  elseif cmd == "reset" then BM.ResetSession(); Core.Print(L["session reset."])
  elseif cmd == "sound" and BM.SOUND_MODES[a] then settings.sound = a; Core.Print(L["sound:"] .. " " .. a)
  elseif cmd == "soundfile" and (a == "theme" or BM.SOUNDS[a]) then settings.soundFile = a; BM.Play()
  elseif cmd == "test" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    UI.OnHawk(); BM.Play()
  elseif cmd == "theme" then
    local th = BM.UpdateTheme()
    Core.Print(L["theme"] .. ": " .. tostring(th.tree or L["class default"]))
  elseif cmd == "meter" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    local r, why = BM.ReadMeter(nil, BM.fight.petNames)
    if not r then Core.Print(L["no readable meter data"] .. " (" .. tostring(why) .. ")") return end
    Core.Print(("%s %s"):format(L["your damage:"], BM.Short(r.total)))
    for i = 1, math.min(8, #r.rows) do
      local row = r.rows[i]
      local name = C_Spell and C_Spell.GetSpellName and C.Safe(C_Spell.GetSpellName(row.spellID)) or "?"
      local who = row.creature ~= "" and (" (" .. row.creature .. ")") or ""
      Core.Print(("  %d  %s%s  %s  <- %s"):format(row.spellID, tostring(name), who, BM.Short(row.amount), row.who))
    end
  elseif cmd == "debug" then Core.PrintDebug()
  elseif cmd == "report" then Core.ShowReport(BM.StateLines())
  else help() end
end
