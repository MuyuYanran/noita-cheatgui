# Noita CheatGUI Chinese Fork & Modding Toolkit

中文 | [English](README_EN.md)

---

A collection of Noita modding tools: a Chinese-localized fork of CheatGUI, three standalone unlock scripts, and Noita component/Lua API reference documentation.

## Project Contents

| Item | Description |
|------|-------------|
| `component_documentation.txt` | Complete documentation of Noita's entity component system — member variables, types, defaults, and descriptions for all available components. |
| `lua_api_documentation.txt` | Noita Lua Modding API reference (API version 12) — all C++-exported functions usable in Lua scripts. |
| `dextrome_unlock_enemies.lua` | Standalone script to instantly unlock **all 400+ enemy** progress entries in your in-game progress menu. |
| `dextrome_unlock_perks_picked.lua` | Standalone script to instantly unlock **all ~107 perk** progress entries. |
| `dextrome_unlock_spells_used.lua` | Standalone script to instantly unlock **all ~460 spell** progress entries. |
| `noita-cheatgui/` | The CheatGUI cheat/debug menu mod — Chinese fork v1.6.0 (detailed below). |

## Directory Structure

```
noita-cheatgui/
├── .gitignore
├── LICENSE                        # MIT License
├── README.md                      # Chinese docs
├── README_EN.md                   # English docs (this file)
├── mod.xml                        # Mod metadata
├── init.lua                       # Entry point
├── screenshot.jpg                 # Screenshot
├── gen_spawnlist.py               # Python generation script
├── data/hax/
│   ├── cheatgui.lua               # Main GUI (~1900 lines)
│   ├── config.lua                 # Persistent configuration
│   ├── console.lua                # WebSocket remote console
│   ├── i18n.lua                   # Internationalization (zh/en)
│   ├── alchemy.lua                # Alchemy recipe data
│   ├── fungal.lua                 # Fungal shift data
│   ├── gun_builder.lua            # Wand builder
│   ├── materials.lua              # Material data
│   ├── spawnables.lua             # Spawnable entity lists
│   ├── special_spawnables.lua     # Special spawnables
│   ├── superhackykb.lua           # Keyboard input support
│   ├── utils.lua                  # Utility functions
│   ├── wand_empty.xml             # Empty wand template
│   ├── wand_hax.lua / .xml        # Cheat wand logic & template
│   └── lib/
│       ├── json.lua               # JSON parser
│       └── pollnet.lua            # Network polling (WebSocket)
└── www/                           # Web console frontend
    ├── index.html                 # Web console page
    ├── css/
    │   └── themes/                # dracula.css, eclipse.css
    ├── js/
    │   └── noitaconsole.js        # Console JS logic
    └── lib/
        ├── codemirror.js / .css   # Code editor
        ├── jquery-2.2.2.min.js
        ├── xterm.js / .css        # Terminal emulator
        ├── xterm-addon-fit.js
        └── modes/lua/             # Lua syntax highlighting
```

## CheatGUI Features

`noita-cheatgui` is a feature-rich in-game cheat/debug menu mod — a Chinese-localized fork of [probable-basilisk/cheatgui](https://github.com/probable-basilisk/cheatgui) (v1.6.0).

### Panels

| Panel | Description |
|-------|-------------|
| **Wand Builder** | Create custom wands with full control over mana, slots, multicast, spread, cast delay, recharge time, speed, shuffle, and always-cast spells. |
| **Teleport** | Teleport to arbitrary coordinates or one-click jump to preset locations (main path Holy Mountains, Orbs, Essences, Bosses, Essence Eaters, side biomes, etc.). |
| **Health** | View current HP, modify max HP, quick +25/+100 max HP boosts. |
| **Gold** | Get/set gold amount, quick +100/+500/+2000. |
| **Spells** | Spawn any spell into the game world, with search and sort filtering. |
| **Perks** | Spawn any perk, with search filtering. |
| **Flasks** | Spawn any potion (bottle/pouch), with adjustable quantity multiplier. |
| **Wands** | Spawn wands at any level, or the cheat wand (Haxx). |
| **Items** | Spawn any game item or entity. |
| **Fungal Shifts** | View the next three fungal shift results, choose materials to force a shift. |
| **Info Widgets** | Real-time display: playtime, areas visited, gold, hearts, items, shots fired, kicks, kills, damage taken, frame count, coordinates. |
| **Console** | Start/stop the WebSocket remote console (see below). |
| **Settings** | Switch language (中文/English), toggle localized name display. |
| **Other** | Edit wands everywhere, spell refresh, full heal, end fungal trip, reset fungal timer, spawn orbs, one-click unlock all progress, tourist mode, etc. |

### Web Remote Console

- Built-in WebSocket server (port **9777**) and HTTP server (port **8777**)
- After loading a save, open `http://localhost:8777` in your browser
- Interactive Lua REPL with CodeMirror syntax highlighting and xterm.js terminal output
- Token-based authentication, localhost access only

### Alchemy Recipes

The info widget can display LC (Lively Concoction) and AP (Alchemic Precursor) recipes for your current location, making alchemy experimentation easier.

## Installation

1. Copy the entire `noita-cheatgui` folder to Noita's mods directory:
   ```
   <Steam>/steamapps/common/Noita/mods/noita-cheatgui/
   ```
2. Enable "**Cheatgui中文分支**" in the in-game Mods menu.
3. (Optional) To use the Web Remote Console, open `http://localhost:8777` in your browser after loading a save.

> **About the permission warning**: CheatGUI requires `request_no_api_restrictions="1"` to support keyboard input filtering and Web console functionality. This is expected and safe to enable.

## Persistent Configuration

CheatGUI saves user preferences using Noita's `GlobalsSetValue` / `GlobalsGetValue` API. Settings persist across game restarts. Configuration is defined in `data/hax/config.lua`.

### Config Items

| Config Key | Globals Key | Type | Default | Description |
|------------|-------------|------|---------|-------------|
| `language` | `cheatgui.config.language` | `string` | `"zh"` | UI language. `"zh"` for Chinese, `"en"` for English. Change via Settings → Language. |
| `show_localized_names` | `cheatgui.config.show_localized_names` | `boolean` | `true` | Show game-localized names for items. When `true`, spell/perk/item list entries display translated names; when `false`, they show raw internal IDs. Change via Settings → Show localized names. |

### How It Works

```lua
-- Storage: all values are persisted as strings via GlobalsSetValue
_config:set("language", "zh")
-- → GlobalsSetValue("cheatgui.config.language", "zh")

-- Retrieval: read from Globals and auto-convert back to original type
local lang = _config:get("language")
-- → GlobalsGetValue("cheatgui.config.language") → "zh"

-- Startup flow (in cheatgui.lua):
_config:load()                             -- Load all config from Globals
_i18n.language = _config:get("language")   -- Apply language setting
```

- **Namespace prefix**: `cheatgui.config.` — avoids key conflicts with other mods
- **Type conversion**: On load, values are automatically converted from strings back to `boolean`/`number`/`string` based on the default value's type
- **Lazy loading**: `_config:load()` caches values into `_config.values` on first call; subsequent reads/writes operate in memory
- **Immediate persistence**: `_config:set()` writes to both memory and Globals simultaneously

### Extending

To add a new persistent config item, just two steps:

```lua
-- 1. Add default value to config.lua's defaults table
_config.defaults.my_new_option = "default_value"

-- 2. In cheatgui.lua:
_config:load()
local val = _config:get("my_new_option")
-- When the user changes it:
_config:set("my_new_option", new_value)
```


## License

CheatGUI: MIT License. See `noita-cheatgui/LICENSE` for details.

---

*For Noita modding API reference, see `component_documentation.txt` and `lua_api_documentation.txt` in this repository.*
