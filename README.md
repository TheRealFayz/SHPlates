# SHPlates

**A highly customizable nameplate addon for OctoWoW**

SHPlates puts threat, cast bars, debuff timers, and combo points right on the nameplates, and lets you build the plate you want: resize every part, recolor it, or drag the pieces around a sample plate until it looks right. It remembers your setup for each talent build and stands on its own, no other addon needed. **Know who has aggro before the mob gets to your healer.**

> **There be dragons here:** the Neon theme still needs a lot of testing. Grey is the one that's been played on. Neon works, but expect rough edges with its layout (combo points, text, and icon spacing). If something looks off, a screenshot and a note on what you were doing helps a lot.

## Installation

1. Download the ZIP from GitHub (Code > Download ZIP) or from OctoWoW's [Gitea](https://octowow.st/git/Fayz/SHPlates)
2. Extract it and rename the folder (for example `SHPlates-main`) to `SHPlates`
3. Move it into `Interface\AddOns`, so the path ends in `Interface\AddOns\SHPlates\SHPlates.toc`
4. Restart WoW, then click the minimap button or type `/shp` to open the settings

## Features

### Two Themes, Two Modes
Pick Grey or Neon, then Tank or DPS. That makes four templates (Grey Tank, Grey DPS, Neon Tank, Neon DPS), and **every template keeps all of its own settings**: sizes, colors, which plates show, layout, everything. Your tank plates and your DPS plates can look and behave completely differently.
- **Tank mode** - Highlights mobs you've lost, so you know what to grab
- **DPS mode** - Highlights mobs that are on you or close to it, so you know when to back off
- **Auto mode** - Switches to Tank in Defensive Stance, Bear Form, or with Righteous Fury, and DPS the rest of the time

Your theme and mode are saved per talent build, so swapping specs swaps SHPlates with you.

### Designer
A sample plate you rearrange with the mouse. Drag any piece wherever you like:
- Name, level, health text, and spell name
- Cast bar and spell icon
- Raid icon and elite star
- Debuffs, class icon, and mob note
- Threat line (shown full length on the sample so you can center it) and the aggro holder's name (separately), threat wheel, and tanked icon

Click a piece to select it and nudge it one step at a time with the arrow buttons, or right-click it to put it back where the theme had it. The sample is drawn by SHPlates itself, so it looks exactly like your plates, and every change shows up on them right away. Each template has its own Designer layout, right at the top of its tab with all of its other settings underneath.

### Size and Style
Set separately for each template:
- **Enemy and neutral plates** - Width, height, and text size
- **Friendly plates** - Their own width, height, and text size, so they can be small and out of the way
- **Cast bars** - Width, height, text size, the spell icon on or off, and your own cast bar color
- **Debuffs** - On or off, icon size, and timers on or off
- **Text** - Font, the aggro holder's name size, health text on the left, center, or right, and your own colors for health text and names
- **Selection box** - Your own color for the box around your target
- **Back to Theme Sizes** puts every size back to 100% in one click

### Threat
- **Server threat** - While you're in a group, SHPlates asks the OctoWoW server for real threat numbers. Solo, it estimates aggro from who each mob is targeting.
- **Tug-o'-Threat** - A line over your target that shows how close you are to pulling, plus who has aggro
- **Threat Wheel** and **Tanked icon** for tanks (a shield when a tank has it, a knife when someone squishy does)
- **Threat colors** on the border or the whole health bar, including a warning color when you're about to pull and a color for "another tank has it"
- **Other tanks** - Tanks are picked up from SHPlates users in Tank mode, GudaPlates users with tank mode on, and any names you add to the Other Tanks list

### Cast Bars
- Cast bars on every plate, not just your target
- **Without SuperWoW**, casts are read from the combat log with real cast times for over 1,200 spells. A spell it doesn't know gets a short bar the first time, and its real cast time is learned once it lands.
- **Uninterruptible casts are learned per mob.** When you or a group member lands an interrupt and the mob keeps casting, SHPlates remembers that mob and spell and shows the "can't interrupt" border from then on. If a later interrupt works, it's forgotten again. Shared by all your characters.
- **Hide cast bars** if you'd rather not see them, in any theme

### Debuffs
- Your debuffs come first. With six slots on a plate, other players' debuffs can't push yours off, so you can always see when yours need refreshing.
- Show all of your debuffs, only the ones on your list, or everyone's
- **Timers** on your debuffs, and on everyone's with Nampower (see [Optional Client Mods](#optional-client-mods))

### Combo Points
A 5-section bar along the top of your target's health bar. Each point lights a section, and the whole bar turns red at 5. The threat line and aggro holder's name move up to make room.

### Raid Marks
- Mark your target with a key (1 through 8, or 0 to clear)
- Pressing the same mark again clears it
- **Works solo too.** Out of a group, marks are local and only you see them.

### Which Plates Show and How They Stack
- **Friendly plates** - Hide friendly players and NPCs. Players only count as enemies when you can attack them, so on a cross-faction server the other faction stays friendly unless PvP is on.
- **Critters** - Hidden by default
- **Neutral mobs** - Hide them until they join the fight. Once a neutral mob goes after you or your group, it stays shown until it dies or the fight is over.
- **Non-elites** - Hide them out of combat. Once you're fighting, every hostile plate shows, including totems and summoned adds.
- **Hide by name** - A list of mob names to always hide
- **Unit levels** - Shown on every plate in every theme, with an option to hide them
- Your target always shows, no matter what's filtered
- **Stacking** - Plates spread out so they don't pile on top of each other. Turn on overlapping if you'd rather have them stack, and click-through if you want to click past them.

### Colors and Extras
- **Class colors** for enemy players, friendly players, or both, with an option to keep PvP-flagged enemies plain red
- **Tapped color** for mobs tagged by someone outside your group
- **Stunned color** so you can see stuns at a glance
- **Mana, rage, and energy bar** inside the bottom of the health bar, for enemies, friends, or everyone
- **Health text** as percent, actual numbers, deficit, total and percent, plus-and-minus, or unit level
- Enemy class icons, a selection box, mob notes, and a range watcher (Neon)

### Share Your Setup
The Share tab turns your whole setup into one string. Copy it, paste it on another character or account, and press Import.
- Includes every template's settings and Designer layout, the Other Tanks list, and mob notes
- Theme and mode come across for the talent build you're on. Mode only copies between characters of the same class, so a warrior's Tank mode won't turn your mage into a tank.
- Your settings window size stays your own, since it depends on your screen
- Tick the box to bring your learned uninterruptible casts along too. They're added to what the other account already learned, never removed.
- **Strings are only read as settings, never run as code**, so sharing them in guild chat is safe

## Settings and Keybinds

Click the minimap button or type `/shp` (or `/shplates`) to open the settings window. Right-click and drag the minimap button to move it. The tabs run down the right side:

- **General** - Theme and mode for this talent build, raid mark keys, the pfUI and ShaguTweaks switches, and hiding the minimap button
- **One tab per template** (Grey Tank, Grey DPS, Neon Tank, Neon DPS) - The Designer stays at the top, and every setting for that template scrolls underneath it: stacking, which plates show, levels, cast bars, colors, sizes, fonts, opacity, scale, widgets, threat colors, debuffs, and more. Changes show up on the sample right away.
- **Casts, Tanks and Notes** - Learned uninterruptible casts, your Other Tanks list, and mob notes
- **Share** - Export and import your setup

You can edit any template no matter which one you're playing with. Hover over a template's tab to see which one is in use right now. Your learned casts, Other Tanks list, and mob notes are shared by every template.

Drag the grip in the bottom-right corner to make the window bigger or smaller, and right-click it to go back to normal size. Hover over most options for a short explanation.

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

SHPlates works on a plain client, but **SuperWoW** is strongly recommended, and **Nampower** adds exact debuff timers. SHPlates turns on the Nampower settings it needs by itself.

| | Plain client | + SuperWoW | + Nampower |
|---|---|---|---|
| Cast bars | From the combat log, on every plate with the caster's name | Exact, on the right plate | |
| Debuffs on plates | Your target and mouseover | Every plate | |
| Debuff timers | No | Your own debuffs (built-in duration list) | Every debuff, exact |
| "Only my debuffs" | No | Debuffs it has timers for | Every debuff |
| Class icons and elite borders | No | Every plate | |
| Critters | Learned by name when you target or mouse over them | Detected on every plate | |
| Neutral mobs joining a fight | From the aggro glow | Exact | |
| Range watcher (Neon) | Rough, in steps | Exact | |
| Solo raid marks | No | Yes | |
| Interrupt learning | No | Yes | More reliable |

A blank cell means it works the same as the column before it.

### Other Addons
- **pfUI** - SHPlates turns off pfUI's nameplates while it's running, so you don't get two sets. This can be turned off on the General tab.
- **ShaguTweaks** - SHPlates switches off ShaguTweaks' nameplate tweaks (class colors, scale, castbar, dark border) while it's running, for the same reason. Also on the General tab.
- **GudaPlates** can't run alongside SHPlates, since both take over the same nameplates. If GudaPlates is active, SHPlates turns itself off and shows a warning with a button to disable GudaPlates and reload.

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

The cast time table used without SuperWoW comes from [ShaguTweaks](https://github.com/shagu/ShaguTweaks) by Shagu, under the MIT License. Thanks, Shagu!

## Feedback

Found a bug or have a feature request? Please open an issue on GitHub. If something looks wrong on a plate, include a screenshot and the output of `/shp debug`. If an error shows up in chat, include that line too.

This addon is provided as-is for use with OctoWoW. If you'd like to edit or fork it, feel free to reach out.

**Please keep forks private.** Public copies floating around make it hard for people to tell which version is the original one and where to get updates or report bugs. If you want your own copy to tinker with, please clone it into a private repo. If you have a change or feature you think everyone would benefit from, please open an issue and we can look at getting it into the main addon.

Special thanks to all the testers and community members who gave feedback during development.

**May you always know who has aggro!**
