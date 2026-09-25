# Kehet's TimeToLevelUp

A World of Warcraft addon that estimates how long it takes to reach your next level.

## Time-to-level box

A small box on the screen shows the estimate, for example `TTL: 1h 25m`. The estimate uses the XP per hour you have gained since login or since your last level up, whichever is later. At max level the box shows `TTL: Max level`.

Drag the box to move it. The addon saves its position between sessions. Lock the box to stop it from moving and to let clicks pass through it.

## XP report

Type `/xp` or `/ttl` to print an XP report to chat:

- Total XP for this level, XP gained and XP still needed
- Rested XP
- XP gained this session
- Kills to level, based on the XP from your last kill
- XP gains to level, based on your last non-kill XP gain
- XP per hour for this level and for this session
- Time to level at the level rate and at the session rate

## Commands

| Command | Action |
|---|---|
| `/xp` or `/ttl` | Print the XP report |
| `/ttl lock` | Lock the box |
| `/ttl unlock` | Unlock the box so you can drag it |

## Requirements

- World of Warcraft: Mists of Pandaria Classic
- The [Ace3](https://www.curseforge.com/wow/addons/ace3) addon
