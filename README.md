# Script Categories

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-blue) [![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A Godot 4 editor plugin that organizes your scripts into categories directly in the Script editor's left panel.

## What is it?

If your project has dozens of scripts, Godot's list of open scripts gets hard to use: you close a script and then dig through folders to find it again. Script Categories replaces that list with one tidy panel where every script in the project is always available, grouped the way you want, without moving a single file.

## Features

- **Categories and subcategories.** Group scripts under your own headers like `--- GAME ---`, with subcategories nested inside a parent. A script can live in several categories.
- **Everything in one list.** Open help pages, text files, shaders and any other tabs get their own sections above the scripts, so nothing disappears when Godot's own list is hidden.
- **Folded by default.** The Scripts section starts closed so it takes a single row. Fold state is remembered per project.
- **Drag and drop.** Select several scripts with Ctrl or Shift and drag them onto a category. Hold Ctrl while dropping to copy instead of move.
- **Search.** Matches file names, paths, class names and what a script extends.
- **Undo.** Ctrl+Z (or the undo button) reverses category changes.
- **Sorting.** By name or by most recently edited.
- **Open state at a glance.** Scripts that are not open are dimmed, and unsaved scripts get a (*) marker.
- **Right-click actions.** Open everything in a category, open the scene that uses a script, show a script in the FileSystem dock, copy its path, close a tab.
- **Safe when files move.** Assignments follow each script's UID, so renaming or moving a script keeps its categories.

## Installation

### GitHub Releases (stable)

1. Download the latest zip from the [releases page](../../releases).
2. Extract it and move the `addons/script_categories` folder into your project's `addons` folder.
3. Enable the plugin in `Project > Project Settings > Plugins`.

### GitHub main (latest, may be unstable)

1. Download the [main branch](../../archive/refs/heads/main.zip).
2. Extract it and move the `addons/script_categories` folder into your project's `addons` folder.
3. Enable the plugin in `Project > Project Settings > Plugins`.

For more help, see [Godot's documentation on installing plugins](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html).

## Usage

- Click the **+** button to create a category, then drag scripts onto it, or right-click a script and choose "Add to".
- Right-click a category header to add a subcategory, rename it, reorder it, open everything in it, or delete it.
- Double-click a header or use its arrow to fold it. The two buttons next to the search box fold or unfold everything.

## Settings

Click the gear button in the panel to open the settings. You can choose which sections to show, whether Scripts starts folded, the style of the headers, spacing between categories, dimming of closed scripts, the default sort order, the number of undo steps and which file extensions count as scripts.

The same options, with their default values, are listed in the `SETTINGS` block at the top of `script_categories.gd`. A value changed in the gear menu is saved per project and takes priority over the default in the file.

## Where data is stored

- Categories and assignments: `res://script_categories.json`. Commit it to share your organization with your team.
- Settings and fold state: the editor's per-project metadata, outside your project files.

## Notes

- Tested on Godot 4.7.
- The plugin finds Godot's script list by looking for its "Filter Scripts" box. If a future editor version changes that layout, the panel falls back to a normal dock and prints a warning in the Output panel.
- Only text scene files (`.tscn`) are searched when looking for the scene that uses a script.

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT License](LICENSE). You are free to use and change this plugin, as long as the copyright notice stays with it.
