-- Beast Mode theme: hunter green and leather brown, then the talent tree with the most points. Plain data, easy to tweak.
--   frame = border colour, title = title text, accent = bar, flash and highlights, hawk = Hawk text (hex RRGGBB),
--   sound = built-in FileDataID. A tree entry overrides only what it lists. Trees are keyed by the client's SkillLine
--   ID (SkillLine table, build 1.60.1.70862: Beast Mastery 50, Marksmanship 163, Survival 51).
-- Every sound and texture here was checked to exist in build 1.60.1.70862 (see tools/verify_media.sh).
local _, ns = ...

ns.THEME = { frame = "8B5A2B", title = "ABD473", accent = "8FBF5A", hawk = "A99BE0", sound = 1266218, -- eagle aggro screech
  order = { 50, 163, 51 },
  trees = { [50] = { accent = "D08A3C" },    -- Beast Mastery: amber
            [163] = { accent = "C8E09A" },   -- Marksmanship: pale green
            [51] = { accent = "8FBF5A" } } } -- Survival: hunter green
