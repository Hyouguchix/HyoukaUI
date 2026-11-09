# HyoukaUI

![Uploading Screenshot_1.png…]()


A flat, dark, modular interface for **Azeroth Survivors**, styled after a retail WoW layout: 1 physical pixel black borders, accent `#7381FF`, Expressway font. Built from scratch as a replacement for SurvivorUI. Works on the game's WoW 1.12 API (Lua 5.0).

Плоский тёмный модульный интерфейс для **Azeroth Survivors** в стиле ретейл-раскладки: рамки в 1 физический пиксель, акцент `#7381FF`, шрифт Expressway. Написан с нуля как замена SurvivorUI.

## Modules / Модули

| Module | What it does |
|---|---|
| `frames` | Player, target and party frames, ability column with cooldowns, XP bar, level-up, revive |
| `meter` | Damage meter: per-second damage, party page, per-ability breakdown, healing |
| `tracker` | Run panel (timers, kills, gold, chests), boss frames and banners, run schedule, loot log, world markers for chests, bosses and lairs, minimap pins |
| `build` | Build list with cooldowns, jewelry, character window |
| `plates` | Flat nameplates with kind markers (elite, guardian, boss) |
| `chat` | Retail-style chat panel with tabs, loot and party feeds |

Every module has three modes: **Off**, **Alongside** (draws next to the stock UI) and **Replace** (hides the stock part it replaces). All modules are Off by default.

```
/hui modules                         list modules and their modes
/hui module <name|all> <off|alongside|replace>
/hui options                         settings window
/hui move                            move mode: drag, scale and reset every piece
/hui selftest                        health check
/hui errors                          Lua error log
```

To roll everything back: `/hui module all off`, then `/hui hud reset`.

## Install / Установка

1. Copy this folder into the game's `AddOns` directory so that you get `AddOns/HyoukaUI/HyoukaUI.toc`.
2. Start the game and enable the modules you want, for example `/hui module meter replace`.
3. Adding new files or editing the `.toc` needs a full game restart; `/reload` is enough for edits of existing files.

HyoukaUI can run alongside SurvivorUI and SurvivorUITweaks (optional dependencies). Use the same module only in one of them, or hide the stock part with **Replace**.

## Languages / Языки

Russian and English. The language follows the game (`azsLanguage`) by default and can be set in `/hui options`, page General.

## Layout of the repository / Структура

```
Core/      boot, events, saved settings, theme, layout, move mode, HUD claims
Data/      the only layer that reads the game's AZS_* data
Widgets/   shared UI widgets (bars, lists, text)
Options/   settings window
Modules/   frames, meter, tracker, build, plates, chat
Media/     fonts and textures
```

Modules never read `AZS_*` globals directly, only the `Data` layer.

## Status

Version 0.1.0. Verified on mocks against the game's real Lua API files and partly in the game; see the in-game `/hui selftest` for the current state.

## Credits

Built for Azeroth Survivors by Hyouguchix. The design follows the SurvivorUI project and a retail WoW interface profile.
