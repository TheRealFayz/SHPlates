SHPlates - nameplates for 1.12 (Turtle WoW / OctoWoW)
=====================================================
A 1.12 rebuild of Tidy Plates (Grey and Neon themes) with extras borrowed
from GudaPlates. Stands on its own: no other addon is needed.

*** There be dragons here: the Neon theme still needs a lot of testing. ***
Grey is the one that's been played on. Neon works, but expect rough edges
with its layout (combo points, text and icon spacing). If you try it and
something looks off, a screenshot and a note on what you were doing helps
a lot.

Open options:   /shplates   (or /shp)
Commands:       /shplates tank | dps | auto      force or auto-pick the mode
                /shplates theme neon | grey      switch theme
                /shplates status                 shows what was detected
                /shplates debug                  one line per visible plate
                /shplates learned                list learned uninterruptible casts
                /shplates share                  open the Share page
                /shplates reset                  wipe settings and reload

Works best with:
  SuperWoW  - GUIDs on plates: cast bars on every plate, class icons, elite
              borders, raid icons, debuffs on every plate, exact range,
              solo raid marks.
  Nampower  - debuff timers, "only my debuffs", reliable interrupt learning.
              SHPlates switches on the Nampower settings it needs by itself.
Without Nampower, debuff timers fall back to a built-in duration table.

Threat
------
SHPlates asks the Turtle/OctoWoW server for threat directly while you fight
in a group. Solo, or if the server doesn't answer, aggro is estimated from
who each mob is targeting. Tanks are recognised from SHPlates users who
picked Tank mode, GudaPlates users with tank mode on, and the names in the
"Other tanks" list in options.

Specs
-----
Theme and Tank/DPS mode are saved per talent build, so swapping specs swaps
SHPlates too. "Auto" mode picks Tank in Defensive Stance, Bear/Dire Bear Form
or with Righteous Fury.

Raid marks
----------
Key bindings (Esc > Key Bindings > SHPlates) mark your target with 1-8 or
clear it with 0. Pressing the same mark again clears it. Out of a group the
marks are local, visible only to you.

Options (General page)
----------------------
  Overlapping plates, hide pfUI's nameplates, auto show/hide in combat
  Visibility: friendly players/NPCs, critters, click-through plates
  Health bar colors: class colors (enemies / friends / not in PvP),
                     tapped color, stunned color
  Fonts: typeface and size
  Learned interrupts, other tanks, mob notes
The Tank and DPS tabs hold each theme's own settings.

Copying your setup
------------------
Open /shp and go to the Share tab (or type /shp share).
  Export: puts your whole setup in the box as one string. It comes up
          selected, so Ctrl+C copies it.
  Import: paste a string in the box with Ctrl+V. The button turns on once
          the box holds a complete string; press it to load that setup.
The string holds the General page, both theme pages, tank names and mob
notes. Theme and Tank/DPS mode come across for the talent build you're on;
mode only copies between characters of the same class. Tick "Export learned
uninterruptible casts too" to bring those along (they're merged with what
the other account already learned, never removed). Strings are only read as
settings, never run as code, so sharing them is safe.

Uninterruptible casts
---------------------
When you (or a group member) land an interrupt and the mob keeps casting,
SHPlates remembers that mob + spell and shows the "can't interrupt" border
from then on. If a later interrupt works, it's forgotten again. Shared by
all your characters (SHPlatesLearned).

Extending a theme
-----------------
Make a tiny addon with  ## Dependencies: SHPlates  and a Lua file like:

    local theme = SHPlatesThemeList["Grey/DPS"]
    local original = theme.SetAlpha
    local hide = { ["Defias Thug"] = true }
    theme.SetAlpha = function(unit)
        if hide[unit.name] then return 0 end
        return original(unit)
    end
    -- style tweaks: theme.hitbox.width = 145, theme.frame = { y = 6 }, ...

Theme functions: SetStyle, SetScale, SetAlpha, SetHealthbarColor,
SetThreatColor, SetCastbarColor, SetSpecialText, SetSpecialText2,
SetSpecialArt, OnInitialize(plate), OnUpdate(plate, unit), OnContextUpdate.

Unit fields: name, level, health, healthmax, guid, isTarget, isMouseover,
isBoss, isElite, isCasting, spellName, spellIcon, isChanneling, reaction,
type, class, raidIcon, isMarked, isInCombat, isTapped, isStunned, isCritter,
isPvP, power, aggroHolder, holderIsTank, losingAggro, threatSituation
(LOW/MEDIUM/HIGH), red/green/blue, partyID.

Credits: Tidy Plates by Binny the Love Fool. 1.12 rebuild by Fayz.
