# SHPlates

**A highly customizable nameplate addon for OctoWoW**

SHPlates puts threat, cast bars, debuff timers, and combo points right on the nameplates, and remembers your setup for each talent build. It stands on its own, no other addon needed. **Know who has aggro before the mob gets to your healer.**

> **There be dragons here:** the Neon theme still needs a lot of testing. Grey is the one that's been played on. Neon works, but expect rough edges with its layout (combo points, text, and icon spacing). If something looks off, a screenshot and a note on what you were doing helps a lot.

## Features

### Two Themes, Two Modes
Pick Grey or Neon, then Tank or DPS. Each mode has its own settings page, so your tank plates and your DPS plates can look completely different.
- **Tank mode** - Highlights mobs you've lost, so you know what to grab
- **DPS mode** - Highlights mobs that are on you or close to it, so you know when to back off
- **Auto mode** - Switches to Tank in Defensive Stance, Bear Form, or with Righteous Fury, and DPS the rest of the time

### Threat
- **Server threat** - While you're in a group, SHPlates asks the OctoWoW server for real threat numbers. Solo, it estimates aggro from who each mob is targeting.
- **Tug-o'-Threat** - A line over your target that shows how close you are to pulling, plus who has aggro
- **Threat Wheel** and **Tanked icon** for tanks (a shield when a tank has it, a knife when someone squishy does)
- **Threat colors** on the border or the whole health bar, including a warning color when you're about to pull and a color for "another tank has it"
- **Other tanks** - Tanks are picked up from SHPlates users in Tank mode, GudaPlates users with tank mode on, and any names you add to the Other Tanks list

### Cast Bars
- Cast bars on every plate, not just your target (needs SuperWoW)
- **Uninterruptible casts are learned per mob.** When you or a group member lands an interrupt and the mob keeps casting, SHPlates remembers that mob and spell and shows the "can't interrupt" border from then on. If a later interrupt works, it's forgotten again. Shared by all your characters.

### Debuffs
- Your debuffs on every plate with timers (exact with Nampower, a built-in duration table without it)
- Show all of your debuffs, only the ones on your list, or everyone's debuffs

### Combo Points
A 5-section bar along the top of your target's health bar. Each point lights a section, and the whole bar turns red at 5. The threat line and aggro holder's name move up to make room.

### Raid Marks
- Mark your target with a key (1 through 8, or 0 to clear)
- Pressing the same mark again clears it
- **Works solo too.** Out of a group, marks are local and only you see them.

### Which Plates Show
- **Friendly plates** - Show or hide friendly players and NPCs
- **Critters** - Hide them
- **Neutral mobs** - Hide them until they join the fight. Once a neutral mob goes after you or your group, it stays shown until it dies or the fight is over.
- **Non-elites** - Hide them out of combat. Once you're fighting, every hostile plate shows, including totems and summoned adds.
- **Hide by name** - A list of mob names to always hide
- Your target always shows, no matter what's filtered

### Looks
- **Class colors** for enemy players, friendly players, or both, with an option to keep PvP-flagged enemies plain red
- **Tapped color** for mobs tagged by someone outside your group
- **Stunned color** so you can see stuns at a glance
- **Mana, rage, and energy bar** inside the bottom of the health bar, for enemies, friends, or everyone
- **Health text** as percent, actual numbers, deficit, total and percent, plus-and-minus, or unit level
- Font choice and size, class icons, unit level, selection box, mob notes, and range (Neon)
- Raid icons and the elite star sit outside the bar so nothing covers the health

### Plate Stacking
Plates spread out by default so they don't pile on top of each other. Turn on overlapping if you'd rather have them stack, and click-through if you want to click past them.

### Share Your Setup
The Share tab turns your whole setup into one string. Copy it, paste it on another character or account, and press Import.
- Includes the General page, both mode pages, the Other Tanks list, and mob notes
- Theme and mode come across for the talent build you're on. Mode only copies between characters of the same class, so a warrior's Tank mode won't turn your mage into a tank.
- Tick the box to bring your learned uninterruptible casts along too. They're added to what the other account already learned, never removed.
- **Strings are only read as settings, never run as code**, so sharing them in guild chat is safe

## Settings and Keybinds

Type `/shp` (or `/shplates`) to open the settings window.

- **General** - Theme and mode for this talent build, stacking, pfUI, auto-hide, which plates show, health bar colors, fonts, learned interrupts, other tanks, and mob notes
- **Tank** and **DPS** - The current theme's settings for each mode: opacity, scale, widgets, threat colors, health text, debuffs, and more
- **Share** - Export and import your setup

Your theme and mode are saved per talent build, so swapping specs swaps SHPlates with you.

Keybinds are in ESC > Key Bindings > SHPlates: Mark target with each raid icon, and Clear target mark.

### Commands
| Command | What it does |
|---|---|
| `/shp` | Open the settings window |
| `/shp tank`, `/shp dps`, `/shp auto` | Set the mode for this talent build |
| `/shp theme grey`, `/shp theme neon` | Switch theme |
| `/shp share` | Open the Share tab |
| `/shp learned` | List the uninterruptible casts learned so far |
| `/shp status` | Show what SHPlates detected (theme, mode, SuperWoW, Nampower) |
| `/shp debug` | Print one line per visible plate, handy for bug reports |
| `/shp reset` | Wipe your settings and reload |

## Optional Client Mods

SHPlates works on a plain client, but these unlock a lot:

- **SuperWoW** - Cast bars, debuffs, class icons, and elite borders on every plate (not just your target), exact range, solo raid marks, and reliable neutral mob tracking. Strongly recommended.
- **Nampower** - Exact debuff timers, "only my debuffs", and more reliable interrupt learning. SHPlates turns on the Nampower settings it needs by itself.
- **pfUI** - SHPlates turns off pfUI's nameplates while it's running, so you don't get two sets. This can be turned off on the General page.

**GudaPlates** can't run alongside SHPlates, since both take over the same nameplates. If GudaPlates is active, SHPlates turns itself off and shows a warning with a button to disable GudaPlates and reload.

## For Developers

Files are split by job: `Core` holds the engine, settings, and shared data, `Widgets` holds the threat, aura, combo, and other widgets, and `Themes` holds Grey, Neon, and the code they share.

You can tweak a theme from a tiny addon of your own. Give it `## Dependencies: SHPlates` and a Lua file like this:

```lua
local theme = SHPlatesThemeList["Grey/DPS"]
local original = theme.SetAlpha
local hide = { ["Defias Thug"] = true }
theme.SetAlpha = function(unit)
    if hide[unit.name] then return 0 end
    return original(unit)
end
```

Theme functions: `SetStyle`, `SetScale`, `SetAlpha`, `SetHealthbarColor`, `SetThreatColor`, `SetCastbarColor`, `SetSpecialText`, `SetSpecialText2`, `SetSpecialArt`, `OnInitialize(plate)`, `OnUpdate(plate, unit)`, `OnContextUpdate`.

Unit fields: `name`, `level`, `health`, `healthmax`, `guid`, `isTarget`, `isMouseover`, `isBoss`, `isElite`, `isCasting`, `spellName`, `spellIcon`, `isChanneling`, `reaction`, `type`, `class`, `raidIcon`, `isMarked`, `isInCombat`, `isTapped`, `isStunned`, `isCritter`, `isPvP`, `power`, `aggroHolder`, `holderIsTank`, `losingAggro`, `threatSituation` (LOW, MEDIUM, HIGH), `red`, `green`, `blue`, `partyID`.

## Feedback

Found a bug or have a feature request? Please open an issue on GitHub. If something looks wrong on a plate, include a screenshot and the output of `/shp debug`. If an error shows up in chat, include that line too.

This addon is provided as-is for use with OctoWoW. If you'd like to edit or fork it, feel free to reach out.

**Please keep forks private.** Public copies floating around make it hard for people to tell which version is the original one and where to get updates or report bugs. If you want your own copy to tinker with, please clone it into a private repo. If you have a change or feature you think everyone would benefit from, please open an issue and we can look at getting it into the main addon.

Special thanks to all the testers and community members who gave feedback during development.

**May you always know who has aggro!**
