# zDPS

Compact, lightweight damage meter for the 1.12 client (OctoWoW / Turtle-style
servers). One small window, class-coloured bars, click-through breakdowns, no
per-event logging.

## Install

Copy the folder to `Interface/AddOns/z_DPS` (or clone this repository there)
and enable **zDPS**. No native DLL is required. SuperWoW and Nampower are
optional and only change how the server reports combat; zDPS reads the normal
combat log.

## Using it

- **Left-click the title** to pick a metric: DPS, Damage, HPS, Healing,
  Overhealing, Damage taken, Dispels, Interrupts, CC used, CC breaks, Deaths,
  Consumables, Threat.
- **Right-click the title** to switch between the current fight, the running
  total and the last fights kept in history, or to report the view to party,
  raid or say.
- **Click a player** to open the detail popup: summary tiles (total, per
  second, share of the group, active time), a share graph of the breakdown, the
  breakdown list (spells, heals, abilities taken, consumables...) and, for the
  selected entry, an outcome graph with hits, crits, misses, dodges, parries,
  blocks, resists, absorbs, immunes, glancing/crushing, partial
  absorbs/blocks/resists, min/max and totals. Heals show effective versus
  overheal. The popup follows the main window's metric and fight while open.
  Hovering a player on the main window shows their top five entries.
- DPS and HPS rows show the total in parentheses: `1.2k (45.3k)  31%`. Damage
  and Healing rows show it the other way round, the total with DPS or HPS in
  parentheses: `45.3k (1.2k)  31%` (settings toggle, on by default).
- The detail popup has a **Spells | Targets** switch for DPS, Damage, HPS,
  Healing and Overhealing. *Targets* lists where that player's damage or
  healing went, with each target's share; heals also show effective versus
  overheal per target. Mobs with the same name count as one target.
- Rows carry class icons (settings toggle). Pets, totems and minions are merged
  into their owner (settings toggle, on by default).
- Drag the window by its title. Drag the dots in the bottom-right corner
  to resize. Title bar buttons: `+` opens another meter window with its
  own metric and fight selection (windows are remembered between sessions),
  the circular arrow resets the current fight and history (shift-click resets
  only the total), the gear opens settings, the padlock locks position and
  size of all windows, and `x` closes that window (the first window only
  hides; `/zdps` brings everything back).
- Mouse wheel scrolls long lists.
- **Text outline** (settings): None, Thin or Thick, for readability over bright
  bars. Applies to every window, the detail popup and the settings window.

### Slash commands

`/zdps` toggles the window. Also `show`, `hide`, `lock`, `reset`, `config`,
`mode current|total`, `metric <key>`, `report [party|raid|say|<name>]`, `mem`.

## What counts

- A **fight** opens when you enter combat, when any party or raid member is in
  combat, or when a group member deals or takes damage. It closes two seconds
  after nobody in the group is in combat. The window keeps showing the last
  fight until the next one starts.
- **Total** accumulates every fight since the last manual reset. Settings offer
  automatic resets: never, when joining a group, when entering a new zone or
  instance, or on every pull.
- **Pets, totems and minions** are merged into their owner by default (shown as
  `Cat: Claw`). Totems belong to the only shaman in the group; with several
  shamans they stay unattributed. Turn merging off in settings to list pets as
  their own rows.
- **DPS** divides by fight time by default. Choose *Active* in settings to divide
  by each player's own time between hits instead.
- **Healing** is effective healing; **Overhealing** is the estimated part that
  exceeded the target's missing health, using the health deficit the client
  reports for group members. Heals on non-group units count as fully effective.
- **Dispels** count casts of dispel, cleanse, cure, purge and devour spells,
  minus server "fails to dispel" lines. **Interrupts** count "X interrupts Y's
  Z" lines.
- **CC used** counts casts of crowd-control spells. **CC breaks** credits the
  group member whose damage landed on a crowd-controlled target within a second
  before the CC faded; natural expiry is not a break.
- **Consumables** count buff gains (flasks, elixirs, food, scrolls, juju,
  weapon oils), potions and healthstones by their heal or mana lines, and
  explosives by their damage lines (each throw once). Anything used in the
  minute before a pull is credited to that pull.
- **Threat** uses the server's threat API, the same `TWT_UDTSv4` addon message
  protocol as TWThreat, for the live target. If TWThreat is loaded its replies
  are reused instead of sending duplicate queries. It needs a party or raid.

## Performance notes

- Each combat log line is matched against the handful of patterns that can
  appear on its event, split once more by whether it contains ` for `. A typical
  hit resolves in the first few `string.find` calls; no tables, closures or
  strings are created per line.
- Aggregates are updated in place for the current fight and the total. Spell
  records only hold the counters that were touched. Per-target totals add one
  number per target name (one small record per healed target); repeat hits
  only update it.
- The window refreshes at most twice a second, and only while it is shown and a
  fight is running or something changed. Rows are pooled frames; menus and the
  settings window are built on first use.
- Memory in use: `/zdps mem`.

## Development

Tests run headless with `lupa` (Lua 5.1 runtime with a small 1.12 widget stub):

```
pip install lupa pytest
python -m pytest tests
```

The addon itself is written for the Lua 5.0 flavour the 1.12 client ships
(`table.getn`, no `#`, `this`/`arg1`/`event` globals in handlers).
