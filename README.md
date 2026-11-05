# Script Categories

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-blue) [![License: MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A Godot 4 editor plugin that organizes your scripts into categories directly in the Script editor's left panel.

## What is it?

If your project has dozens of scripts, Godot's list of open scripts gets hard to use: you close a script and then dig through folders to find it again. Script Categories replaces that list with one tidy panel where every script in the project is always available, grouped the way you want, without moving a single file.

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

## License

[MIT License](LICENSE). You are free to use and change this plugin, as long as the copyright notice stays with it.
