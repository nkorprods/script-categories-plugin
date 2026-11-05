@tool
extends EditorPlugin

# Script Categories
# Lists every script in the project in the Script editor's left panel, grouped
# under your own categories. Open help pages and other tabs get their own
# sections. Categories are stored in res://script_categories.json.

# Defaults for every option. The gear button in the panel overrides them per
# project; "Reset to defaults" there goes back to the values below.

const SETTINGS := {
	# layout
	"hide_builtin_list": {
		"group": "Layout", "default": true,
		"label": "Hide Godot's own script list",
		"desc": "This panel replaces it. Turn off to see both lists.",
	},
	"scripts_first": {
		"group": "Layout", "default": false,
		"label": "Show Scripts above Documentation",
		"desc": "Normally Documentation (and the other open tabs) come first.",
	},
	"scripts_collapsed_by_default": {
		"group": "Layout", "default": true,
		"label": "Start with the Scripts section folded",
		"desc": "Keeps the list short. Your last fold/unfold is remembered per project.",
	},
	# sections
	"show_docs": {
		"group": "Sections", "default": true,
		"label": "Documentation section",
		"desc": "Open help pages. If a section is off, its tabs move to Other.",
	},
	"show_text": {
		"group": "Sections", "default": true,
		"label": "Text & Files section",
		"desc": "Open .txt, .md, .json, .cfg ... tabs.",
	},
	"show_shaders": {
		"group": "Sections", "default": true,
		"label": "Shaders section",
		"desc": "Open shader tabs.",
	},
	"show_other": {
		"group": "Sections", "default": true,
		"label": "Other section",
		"desc": "Tabs that fit nowhere else. If off, those tabs are not listed.",
	},
	# look
	"category_dashes": {
		"group": "Look", "default": 3, "min": 1, "max": 10,
		"label": "Dashes around category names",
		"desc": "3 gives  --- GAME ---",
	},
	"section_marks": {
		"group": "Look", "default": 3, "min": 1, "max": 10,
		"label": "Marks around section names",
		"desc": "3 gives  === SCRIPTS ===",
	},
	"space_between_sections": {
		"group": "Look", "default": true,
		"label": "Blank row between sections",
		"desc": "Exactly as tall as a script row.",
	},
	"space_between_categories": {
		"group": "Look", "default": true,
		"label": "Blank row between categories",
		"desc": "Exactly as tall as a script row.",
	},
	"dim_closed_scripts": {
		"group": "Look", "default": true,
		"label": "Dim scripts that are not open",
		"desc": "Open scripts stay bright so you can see your tabs at a glance.",
	},
	"closed_alpha": {
		"group": "Look", "default": 0.55, "min": 0.1, "max": 1.0, "step": 0.05,
		"label": "Dimming strength",
		"desc": "Lower = dimmer. 1.0 = no dimming.",
	},
	"show_unsaved_marker": {
		"group": "Look", "default": true,
		"label": "Show (*) on unsaved scripts",
		"desc": "Same marker Godot's own list uses.",
	},
	# behavior
	"sort_mode": {
		"group": "Behavior", "default": "name",
		"options": ["name", "recent"],
		"option_labels": ["Name (A-Z)", "Recently edited first"],
		"label": "Sort scripts inside categories",
		"desc": "Also available from the sort button in the panel.",
	},
	"search_class_names": {
		"group": "Behavior", "default": true,
		"label": "Search also matches class names",
		"desc": "Finds scripts by their class_name or by what they extend.",
	},
	"undo_steps": {
		"group": "Behavior", "default": 20, "min": 1, "max": 100,
		"label": "Undo steps",
		"desc": "How many category changes Ctrl+Z (or the undo button) can reverse.",
	},
	"open_all_confirm_above": {
		"group": "Behavior", "default": 15, "min": 1, "max": 200,
		"label": "Ask before opening more than this many scripts",
		"desc": "Used by \"Open all in category\".",
	},
	# advanced
	"scan_addons": {
		"group": "Advanced", "default": false,
		"label": "Include the addons folder",
		"desc": "Lists scripts from plugins too. Usually just clutter.",
	},
	"script_extensions": {
		"group": "Advanced", "default": "gd",
		"label": "Script file extensions",
		"desc": "Comma separated, for example: gd, cs",
	},
	"text_extensions": {
		"group": "Advanced", "default": "txt,md,json,cfg,csv,ini,log,xml,yml,yaml,toml",
		"label": "Extensions for Text & Files",
		"desc": "Comma separated.",
	},
	"shader_extensions": {
		"group": "Advanced", "default": "gdshader,gdshaderinc,shader",
		"label": "Extensions for Shaders",
		"desc": "Comma separated.",
	},
}

const DATA_PATH := "res://script_categories.json"
const META_SECTION := "script_categories"
const SECTION_KEYS := ["docs", "text", "shaders", "other", "scripts"]
const SECTION_TITLES := {
	"docs": "DOCUMENTATION", "text": "TEXT & FILES", "shaders": "SHADERS",
	"other": "OTHER", "scripts": "SCRIPTS",
}
const SECTION_PREFIX := "__sec_"
const POLL_SECONDS := 0.4
const DOUBLE_TOGGLE_MS := 400
const ACTIVATE_GRACE_MS := 300

var panel: VBoxContainer
var search_box: LineEdit
var tree: Tree
var menu: PopupMenu
var sort_button: MenuButton
var undo_button: Button
var name_dialog: ConfirmationDialog
var name_edit: LineEdit
var confirm_dialog: ConfirmationDialog
var info_dialog: AcceptDialog
var settings_dialog: AcceptDialog
var settings_box: VBoxContainer
var poll_timer: Timer
var builtin_list: ItemList
var builtin_filter: LineEdit

var settings: Dictionary = {}  # current values
var overrides: Dictionary = {}  # values changed from the default
var script_exts: Array[String] = []
var text_exts: Array[String] = []
var shader_exts: Array[String] = []

var categories: Array[String] = []  # full paths like "GAME/ENEMIES"
var script_cats: Dictionary = {}  # script path -> category paths
var path_uid: Dictionary = {}  # script path -> uid text
var orphans: Dictionary = {}  # saved entries not resolved yet, never dropped
var script_paths: Array[String] = []
var script_mtime: Dictionary = {}  # script path -> modified time
var script_info: Dictionary = {}  # script path -> class_name / extends
var collapsed_state: Dictionary = {}
var tab_entries: Array = []  # tabs from Godot's own list
var undo_stack: Array = []

var docked_fallback := false
var rebuilding := false
var self_toggling := false
var refresh_queued := false
var sections_built := 0
var dialog_mode := ""
var dialog_target := ""
var confirm_mode := ""
var delete_target := ""
var pending_paths: Array[String] = []
var last_struct_sig := ""
var last_state_sig := ""
var last_toggle_id := 0
var last_toggle_msec := 0
var last_toggle_state := false
var last_collapse_id := 0
var last_collapse_msec := 0


func _enter_tree() -> void:
	_load_settings()
	_load_data()
	_load_collapsed()
	_build_panel()
	_scan_scripts()
	_rebuild_tree()
	_install_panel()
	var script_editor := EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	script_editor.script_close.connect(_on_script_closed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_queue_refresh)


func _exit_tree() -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	if script_editor.script_close.is_connected(_on_script_closed):
		script_editor.script_close.disconnect(_on_script_closed)
	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_queue_refresh):
		fs.filesystem_changed.disconnect(_queue_refresh)
	if is_instance_valid(builtin_list):
		builtin_list.visible = true
	if is_instance_valid(builtin_filter):
		builtin_filter.visible = true
	if is_instance_valid(panel):
		if docked_fallback:
			remove_control_from_docks(panel)
		elif panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		panel.queue_free()


func _setting(key: String) -> Variant:
	return settings.get(key, SETTINGS[key]["default"])


func _load_settings() -> void:
	overrides.clear()
	var saved: Variant = EditorInterface.get_editor_settings().get_project_metadata(META_SECTION, "settings", {})
	if saved is Dictionary:
		for key in saved:
			if SETTINGS.has(str(key)):
				overrides[str(key)] = saved[key]
	_rebuild_settings_values()


func _rebuild_settings_values() -> void:
	settings.clear()
	for key in SETTINGS:
		var spec: Dictionary = SETTINGS[key]
		var value: Variant = spec["default"]
		if overrides.has(key):
			var raw: Variant = overrides[key]
			match typeof(spec["default"]):
				TYPE_BOOL:
					value = bool(raw)
				TYPE_INT:
					value = int(raw)
				TYPE_FLOAT:
					value = float(raw)
				_:
					value = str(raw)
			if spec.has("options") and not (spec["options"] as Array).has(value):
				value = spec["default"]
		settings[key] = value
	script_exts = _parse_ext_list(str(settings["script_extensions"]))
	text_exts = _parse_ext_list(str(settings["text_extensions"]))
	shader_exts = _parse_ext_list(str(settings["shader_extensions"]))


func _parse_ext_list(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		var ext := part.strip_edges().to_lower().trim_prefix(".")
		if ext != "":
			out.append(ext)
	return out


func _save_settings() -> void:
	EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, "settings", overrides)


func _set_setting(key: String, value: Variant) -> void:
	if settings.get(key) == value:
		return
	if value == SETTINGS[key]["default"]:
		overrides.erase(key)
	else:
		overrides[key] = value
	_save_settings()
	_rebuild_settings_values()
	_apply_setting_change(key)


func _apply_setting_change(key: String) -> void:
	match key:
		"hide_builtin_list":
			_apply_builtin_visibility()
		"script_extensions", "scan_addons", "search_class_names", "text_extensions", "shader_extensions":
			_scan_scripts()
			_rebuild_tree(true)
		"undo_steps":
			_trim_undo()
		"sort_mode":
			_sync_sort_menu()
			_rebuild_tree(true)
		_:
			_rebuild_tree(true)


func _reset_settings() -> void:
	overrides.clear()
	_save_settings()
	_rebuild_settings_values()
	_apply_builtin_visibility()
	_sync_sort_menu()
	_trim_undo()
	_scan_scripts()
	_rebuild_tree(true)
	_fill_settings_dialog()


func _apply_builtin_visibility() -> void:
	var hide := bool(_setting("hide_builtin_list"))
	if is_instance_valid(builtin_list):
		builtin_list.visible = not hide
	if is_instance_valid(builtin_filter):
		builtin_filter.visible = not hide


func _open_settings() -> void:
	_fill_settings_dialog()
	settings_dialog.popup_centered()


func _fill_settings_dialog() -> void:
	for child in settings_box.get_children():
		settings_box.remove_child(child)
		child.queue_free()
	var accent := EditorInterface.get_editor_theme().get_color("accent_color", "Editor")
	var group := ""
	for key in SETTINGS:
		var spec: Dictionary = SETTINGS[key]
		if spec["group"] != group:
			group = spec["group"]
			if settings_box.get_child_count() > 0:
				settings_box.add_child(HSeparator.new())
			var heading := Label.new()
			heading.text = String(group).to_upper()
			heading.add_theme_color_override("font_color", accent)
			settings_box.add_child(heading)
		_add_setting_row(key, spec)


func _add_setting_row(key: String, spec: Dictionary) -> void:
	var value: Variant = _setting(key)
	match typeof(spec["default"]):
		TYPE_BOOL:
			var check := CheckBox.new()
			check.text = spec["label"]
			check.button_pressed = bool(value)
			check.toggled.connect(_on_bool_setting.bind(key))
			settings_box.add_child(check)
		TYPE_INT, TYPE_FLOAT:
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = spec["label"]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var spin := SpinBox.new()
			spin.min_value = spec["min"]
			spin.max_value = spec["max"]
			spin.step = spec.get("step", 1)
			spin.value = float(value)
			spin.value_changed.connect(_on_number_setting.bind(key))
			row.add_child(spin)
			settings_box.add_child(row)
		_:
			if spec.has("options"):
				var row := HBoxContainer.new()
				var label := Label.new()
				label.text = spec["label"]
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				var picker := OptionButton.new()
				var options: Array = spec["options"]
				var labels: Array = spec["option_labels"]
				for i in options.size():
					picker.add_item(str(labels[i]))
				picker.selected = options.find(value)
				picker.item_selected.connect(_on_choice_setting.bind(key))
				row.add_child(picker)
				settings_box.add_child(row)
			else:
				var label := Label.new()
				label.text = spec["label"]
				settings_box.add_child(label)
				var edit := LineEdit.new()
				edit.text = str(value)
				edit.text_submitted.connect(_on_text_setting.bind(key))
				edit.focus_exited.connect(_on_text_focus_lost.bind(edit, key))
				settings_box.add_child(edit)
	if str(spec.get("desc", "")) != "":
		var note := Label.new()
		note.text = spec["desc"]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		settings_box.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	settings_box.add_child(gap)


func _on_bool_setting(pressed: bool, key: String) -> void:
	_set_setting(key, pressed)


func _on_number_setting(value: float, key: String) -> void:
	if typeof(SETTINGS[key]["default"]) == TYPE_INT:
		_set_setting(key, int(value))
	else:
		_set_setting(key, value)


func _on_choice_setting(index: int, key: String) -> void:
	_set_setting(key, (SETTINGS[key]["options"] as Array)[index])


func _on_text_setting(text: String, key: String) -> void:
	_set_setting(key, text.strip_edges())


func _on_text_focus_lost(edit: LineEdit, key: String) -> void:
	_set_setting(key, edit.text.strip_edges())


func _on_settings_action(action: StringName) -> void:
	if action == &"reset":
		_reset_settings()


func _make_icon_button(icon_names: Array, fallback_text: String, tip: String) -> Button:
	var button := Button.new()
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theme := EditorInterface.get_editor_theme()
	for icon_name in icon_names:
		if theme.has_icon(icon_name, "EditorIcons"):
			button.icon = theme.get_icon(icon_name, "EditorIcons")
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			return button
	button.text = fallback_text
	return button


func _build_panel() -> void:
	panel = VBoxContainer.new()
	panel.name = "Script Categories"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 3.0
	panel.custom_minimum_size = Vector2(0, 150)

	search_box = LineEdit.new()
	search_box.placeholder_text = "Search all scripts..."
	search_box.clear_button_enabled = true
	search_box.text_changed.connect(_on_search_changed)
	panel.add_child(search_box)

	var buttons := HBoxContainer.new()
	panel.add_child(buttons)

	var collapse_button := _make_icon_button(["CollapseTree"], "Fold", "Fold everything")
	collapse_button.pressed.connect(_set_all_collapsed.bind(true))
	buttons.add_child(collapse_button)

	var expand_button := _make_icon_button(["ExpandTree"], "Open", "Unfold everything")
	expand_button.pressed.connect(_set_all_collapsed.bind(false))
	buttons.add_child(expand_button)

	sort_button = MenuButton.new()
	sort_button.tooltip_text = "Sort scripts inside categories"
	sort_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theme := EditorInterface.get_editor_theme()
	if theme.has_icon("Sort", "EditorIcons"):
		sort_button.icon = theme.get_icon("Sort", "EditorIcons")
		sort_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		sort_button.text = "Sort"
	var sort_popup := sort_button.get_popup()
	var sort_labels: Array = SETTINGS["sort_mode"]["option_labels"]
	for i in sort_labels.size():
		sort_popup.add_radio_check_item(str(sort_labels[i]), i)
	sort_popup.id_pressed.connect(_on_sort_chosen)
	buttons.add_child(sort_button)
	_sync_sort_menu()

	undo_button = _make_icon_button(["UndoRedo", "Undo"], "Undo", "Undo the last category change (Ctrl+Z)")
	undo_button.pressed.connect(_undo)
	undo_button.disabled = true
	buttons.add_child(undo_button)

	var add_button := Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "New category"
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_button.pressed.connect(_ask_new_category)
	buttons.add_child(add_button)

	var settings_button := _make_icon_button(["Tools", "GuiTabMenuHl"], "Set", "Settings")
	settings_button.pressed.connect(_open_settings)
	buttons.add_child(settings_button)

	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.allow_rmb_select = true
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	tree.item_mouse_selected.connect(_on_item_mouse_selected)
	tree.item_activated.connect(_on_item_activated)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.gui_input.connect(_on_tree_input)
	tree.set_drag_forwarding(_get_drag, _can_drop, _drop)
	panel.add_child(tree)

	menu = PopupMenu.new()
	menu.id_pressed.connect(_on_menu_id_pressed)
	panel.add_child(menu)

	name_dialog = ConfirmationDialog.new()
	name_edit = LineEdit.new()
	name_dialog.add_child(name_edit)
	name_dialog.register_text_enter(name_edit)
	name_dialog.confirmed.connect(_on_name_confirmed)
	panel.add_child(name_dialog)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.confirmed.connect(_on_confirmed)
	panel.add_child(confirm_dialog)

	info_dialog = AcceptDialog.new()
	info_dialog.title = "Script Categories"
	panel.add_child(info_dialog)

	settings_dialog = AcceptDialog.new()
	settings_dialog.title = "Script Categories - Settings"
	settings_dialog.ok_button_text = "Close"
	settings_dialog.add_button("Reset to defaults", false, "reset")
	settings_dialog.custom_action.connect(_on_settings_action)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 460) * EditorInterface.get_editor_scale()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_box = VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(settings_box)
	settings_dialog.add_child(scroll)
	panel.add_child(settings_dialog)

	poll_timer = Timer.new()
	poll_timer.wait_time = POLL_SECONDS
	poll_timer.timeout.connect(_poll)
	panel.add_child(poll_timer)


func _install_panel() -> void:
	var script_editor := EditorInterface.get_script_editor()
	var filter := _find_filter(script_editor)
	if filter != null and filter.get_parent() is VBoxContainer:
		var host := filter.get_parent()
		builtin_filter = filter
		for child in host.get_children():
			if child is ItemList:
				builtin_list = child as ItemList
				break
		var insert_at := filter.get_index() + 1
		if builtin_list != null:
			insert_at = builtin_list.get_index()
		host.add_child(panel)
		host.move_child(panel, insert_at)
	else:
		push_warning("Script Categories: couldn't find the Script editor's script list, showing as a dock instead.")
		docked_fallback = true
		add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UL, panel)
	_apply_builtin_visibility()
	poll_timer.start()
	_sync_tabs(true)


func _find_filter(node: Node) -> LineEdit:
	if node is LineEdit and (node as LineEdit).placeholder_text.to_lower().contains("filter scripts"):
		return node as LineEdit
	for child in node.get_children():
		var found := _find_filter(child)
		if found != null:
			return found
	return null


func _sync_sort_menu() -> void:
	if not is_instance_valid(sort_button):
		return
	var popup := sort_button.get_popup()
	var options: Array = SETTINGS["sort_mode"]["options"]
	for i in options.size():
		popup.set_item_checked(i, options[i] == _setting("sort_mode"))


func _on_sort_chosen(id: int) -> void:
	_set_setting("sort_mode", (SETTINGS["sort_mode"]["options"] as Array)[id])


func _collect_files(dir_path: String, exts: Array, out: Array[String]) -> void:
	if FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.get_extension().to_lower() in exts:
			out.append(dir_path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(dir_path):
		if dir_name.begins_with("."):
			continue
		if dir_name == "addons" and dir_path == "res://" and not bool(_setting("scan_addons")):
			continue
		_collect_files(dir_path.path_join(dir_name), exts, out)


func _scan_scripts() -> bool:
	# true when the script list changed
	var old_paths := script_paths.duplicate()
	var old_mtime_hash := script_mtime.hash()
	script_paths.clear()
	_collect_files("res://", script_exts, script_paths)
	script_paths.sort()
	script_mtime.clear()
	for path in script_paths:
		script_mtime[path] = FileAccess.get_modified_time(path)
	_update_script_info()
	var reconciled := _reconcile()
	var mtime_changed: bool = (str(_setting("sort_mode")) == "recent") and (old_mtime_hash != script_mtime.hash())
	return reconciled or old_paths != script_paths or mtime_changed


func _update_script_info() -> void:
	if not bool(_setting("search_class_names")):
		return
	for path in script_paths:
		var info: Dictionary = script_info.get(path, {})
		if info.is_empty() or info["mtime"] != script_mtime[path]:
			script_info[path] = _parse_info(path, script_mtime[path])


func _parse_info(path: String, mtime: int) -> Dictionary:
	var info := {"mtime": mtime, "class": "", "extends": ""}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return info
	var lines := 0
	while not file.eof_reached() and lines < 80:
		var line := file.get_line().strip_edges()
		lines += 1
		if line.begins_with("class_name "):
			var rest := line.substr(11).strip_edges()
			info["class"] = rest.split(" ")[0].split(",")[0]
			var ext_at := rest.find(" extends ")
			if ext_at >= 0 and info["extends"] == "":
				info["extends"] = rest.substr(ext_at + 9).strip_edges().split(" ")[0]
		elif line.begins_with("extends ") and info["extends"] == "":
			info["extends"] = line.substr(8).strip_edges().split(" ")[0]
		if info["class"] != "" and info["extends"] != "":
			break
	file.close()
	return info


func _reconcile() -> bool:
	# follow moved scripts by uid and retry entries that could not be resolved at load
	var changed := false
	for path in script_cats.keys():
		if script_paths.has(path):
			continue
		var uid: String = path_uid.get(path, "")
		if uid == "":
			continue
		var new_path := _path_for(uid, "")
		if new_path != "" and new_path != path and script_paths.has(new_path):
			script_cats[new_path] = script_cats[path]
			script_cats.erase(path)
			path_uid.erase(path)
			path_uid[new_path] = uid
			changed = true
	for key in orphans.keys():
		var entry: Dictionary = orphans[key]
		var resolved := _path_for(str(key), str(entry.get("path", "")))
		if resolved != "" and script_paths.has(resolved):
			script_cats[resolved] = _to_array(entry.get("categories", []))
			if str(key).begins_with("uid://"):
				path_uid[resolved] = str(key)
			orphans.erase(key)
			changed = true
	if changed:
		_save_data()
	return changed


func _queue_refresh() -> void:
	if refresh_queued:
		return
	refresh_queued = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	refresh_queued = false
	if _scan_scripts():
		_rebuild_tree(true)


func _collect_tabs() -> Array:
	var out: Array = []
	if builtin_list == null:
		return out
	for index in builtin_list.item_count:
		var raw := builtin_list.get_item_text(index)
		var base := raw.trim_suffix("(*)").strip_edges()
		var tip := builtin_list.get_item_tooltip(index)
		var is_script := base.get_extension().to_lower() in script_exts
		out.append({
			"index": index,
			"text": base,
			"modified": raw.ends_with("(*)"),
			"is_script": is_script,
			"path": tip if (is_script and tip.begins_with("res://")) else "",
			"icon": builtin_list.get_item_icon(index),
			"selected": builtin_list.is_selected(index),
		})
	return out


func _entry_paths(entry: Dictionary) -> Array:
	if entry["path"] != "":
		return [entry["path"]]
	var out: Array = []
	for path in script_paths:
		if path.get_file() == entry["text"]:
			out.append(path)
	return out


func _section_key_for(entry: Dictionary) -> String:
	var base: String = entry["text"]
	var ext := base.get_extension().to_lower()
	var key := "other"
	if base.contains("::"):
		key = "other"
	elif ext == "":
		key = "docs"
	elif ext in text_exts:
		key = "text"
	elif ext in shader_exts:
		key = "shaders"
	if key != "other" and not bool(_setting("show_" + key)):
		key = "other"
	if key == "other" and not bool(_setting("show_other")):
		return ""
	return key


func _poll() -> void:
	_sync_tabs(false)


func _sync_tabs(force: bool) -> void:
	if not is_instance_valid(tree):
		return
	tab_entries = _collect_tabs()
	var struct_parts := PackedStringArray()
	var state_parts := PackedStringArray()
	for entry in tab_entries:
		if not entry["is_script"]:
			struct_parts.append("%d:%s" % [entry["index"], entry["text"]])
		state_parts.append("%d:%s:%s:%s" % [entry["index"], entry["modified"], entry["selected"], entry["path"]])
	for open_script in EditorInterface.get_script_editor().get_open_scripts():
		state_parts.append(open_script.resource_path)
	var struct_sig := "|".join(struct_parts)
	var state_sig := "|".join(state_parts)
	if force or struct_sig != last_struct_sig:
		last_struct_sig = struct_sig
		last_state_sig = state_sig
		_rebuild_tree(true)
	elif state_sig != last_state_sig:
		last_state_sig = state_sig
		_apply_tab_state()
		_sync_selection()


func _apply_tab_state() -> void:
	# dimming and the (*) marker, updated in place
	if not is_instance_valid(tree) or tree.get_root() == null:
		return
	var open_paths := {}
	var modified_paths := {}
	var modified_by_index := {}
	for open_script in EditorInterface.get_script_editor().get_open_scripts():
		open_paths[open_script.resource_path] = true
	for entry in tab_entries:
		modified_by_index[entry["index"]] = entry["modified"]
		if entry["is_script"]:
			for path in _entry_paths(entry):
				open_paths[path] = true
				if entry["modified"]:
					modified_paths[path] = true
	var normal := EditorInterface.get_editor_theme().get_color("font_color", "Tree")
	var alpha := float(_setting("closed_alpha"))
	var dimmed := normal
	dimmed.a = alpha
	var dim_on := bool(_setting("dim_closed_scripts"))
	var mark_on := bool(_setting("show_unsaved_marker"))
	for item in _all_items():
		var meta: Variant = item.get_metadata(0)
		if not (meta is Dictionary):
			continue
		match meta.get("type", ""):
			"script":
				var path: String = meta["path"]
				var is_open := open_paths.has(path) or not dim_on
				var marker := " (*)" if (mark_on and modified_paths.has(path)) else ""
				item.set_text(0, path.get_file() + marker)
				item.set_custom_color(0, normal if is_open else dimmed)
				item.set_icon_modulate(0, Color.WHITE if is_open else Color(1, 1, 1, alpha))
			"open_tab":
				var marker: String = " (*)" if (mark_on and bool(modified_by_index.get(meta["index"], false))) else ""
				item.set_text(0, str(meta["text"]) + marker)


func _sync_selection() -> void:
	# highlight the row of the current tab
	var current := {}
	for entry in tab_entries:
		if entry["selected"]:
			current = entry
			break
	if current.is_empty() or current["is_script"]:
		var script_res := EditorInterface.get_script_editor().get_current_script()
		if script_res != null:
			_select_path(script_res.resource_path)
	else:
		_select_tab_item(current["index"])


func _activate_tab(meta: Dictionary) -> void:
	var index: int = meta["index"]
	if not is_instance_valid(builtin_list) or index >= builtin_list.item_count:
		return
	if builtin_list.get_item_text(index).trim_suffix("(*)").strip_edges() != meta["text"]:
		return
	builtin_list.select(index)
	builtin_list.item_selected.emit(index)


func _section_order() -> Array:
	if bool(_setting("scripts_first")):
		return ["scripts", "docs", "text", "shaders", "other"]
	return ["docs", "text", "shaders", "other", "scripts"]


func _category_label(leaf: String) -> String:
	var marks := "".rpad(int(_setting("category_dashes")), "-")
	return "%s %s %s" % [marks, leaf.to_upper(), marks]


func _section_label(key: String) -> String:
	var marks := "".rpad(int(_setting("section_marks")), "=")
	return "%s %s %s" % [marks, SECTION_TITLES[key], marks]


func _parent_of(cat: String) -> String:
	var slash := cat.rfind("/")
	return "" if slash < 0 else cat.substr(0, slash)


func _leaf_of(cat: String) -> String:
	return cat.substr(cat.rfind("/") + 1)


func _cats_of(path: String) -> Array:
	# only categories that still exist
	var out: Array = []
	for cat in script_cats.get(path, []):
		if categories.has(cat):
			out.append(cat)
	return out


func _matches(path: String, query: String) -> bool:
	if query.is_empty() or path.to_lower().contains(query):
		return true
	if bool(_setting("search_class_names")):
		var info: Dictionary = script_info.get(path, {})
		if str(info.get("class", "")).to_lower().contains(query):
			return true
		if str(info.get("extends", "")).to_lower().contains(query):
			return true
	return false


func _cmp_name(a: String, b: String) -> bool:
	var file_a := a.get_file().to_lower()
	var file_b := b.get_file().to_lower()
	if file_a != file_b:
		return file_a < file_b
	return a < b


func _cmp_recent(a: String, b: String) -> bool:
	var time_a: int = script_mtime.get(a, 0)
	var time_b: int = script_mtime.get(b, 0)
	if time_a != time_b:
		return time_a > time_b
	return _cmp_name(a, b)


func _sort_paths(paths: Array[String]) -> void:
	if _setting("sort_mode") == "recent":
		paths.sort_custom(_cmp_recent)
	else:
		paths.sort_custom(_cmp_name)


func _scripts_directly_in(cat: String, query: String) -> Array[String]:
	var out: Array[String] = []
	for path in script_paths:
		if (script_cats.get(path, []) as Array).has(cat) and _matches(path, query):
			out.append(path)
	_sort_paths(out)
	return out


func _scripts_in_branch(cat: String) -> Array[String]:
	var out: Array[String] = []
	for path in script_paths:
		for c in script_cats.get(path, []):
			if c == cat or str(c).begins_with(cat + "/"):
				out.append(path)
				break
	_sort_paths(out)
	return out


func _branch_has_matches(cat: String, query: String) -> bool:
	for path in script_paths:
		if not _matches(path, query):
			continue
		for c in script_cats.get(path, []):
			if c == cat or str(c).begins_with(cat + "/"):
				return true
	return false


func _rebuild_tree(keep_scroll := false) -> void:
	if not is_instance_valid(tree):
		return
	var scroll_value := _get_scroll() if keep_scroll else 0.0
	rebuilding = true
	tree.clear()
	var root := tree.create_item()
	sections_built = 0
	var query := search_box.text.strip_edges().to_lower()
	var theme := EditorInterface.get_editor_theme()
	for key in _section_order():
		if key == "scripts":
			_build_scripts_section(root, query, theme)
		else:
			_build_tab_section(root, key, query, theme)
	rebuilding = false
	_apply_tab_state()
	_sync_selection()
	if keep_scroll:
		_restore_scroll.call_deferred(scroll_value)


func _begin_section(root: TreeItem, key: String, theme: Theme) -> TreeItem:
	if sections_built > 0 and bool(_setting("space_between_sections")):
		_add_spacer(root, theme)
	sections_built += 1
	var header := tree.create_item(root)
	header.set_text(0, _section_label(key))
	header.set_custom_color(0, theme.get_color("accent_color", "Editor").lightened(0.25))
	header.set_metadata(0, {"type": "section", "key": key})
	return header


func _finish_header(header: TreeItem, state_key: String, default_collapsed: bool, query: String) -> void:
	header.collapsed = false if not query.is_empty() else bool(collapsed_state.get(state_key, default_collapsed))


func _build_tab_section(root: TreeItem, key: String, query: String, theme: Theme) -> void:
	var items: Array = []
	for entry in tab_entries:
		if entry["is_script"] or _section_key_for(entry) != key:
			continue
		if not query.is_empty() and not str(entry["text"]).to_lower().contains(query):
			continue
		items.append(entry)
	if items.is_empty():
		return
	var header := _begin_section(root, key, theme)
	for entry in items:
		var item := tree.create_item(header)
		item.set_text(0, entry["text"])
		item.set_icon(0, entry["icon"])
		item.set_metadata(0, {"type": "open_tab", "index": entry["index"], "text": entry["text"]})
	_finish_header(header, SECTION_PREFIX + key, false, query)


func _build_scripts_section(root: TreeItem, query: String, theme: Theme) -> void:
	if not query.is_empty():
		var any := false
		for path in script_paths:
			if _matches(path, query):
				any = true
				break
		if not any:
			return
	elif script_paths.is_empty() and categories.is_empty():
		return
	var header := _begin_section(root, "scripts", theme)
	var shown := 0
	for cat in categories:
		if _parent_of(cat) != "":
			continue
		if not query.is_empty() and not _branch_has_matches(cat, query):
			continue
		if shown > 0 and bool(_setting("space_between_categories")):
			_add_spacer(header, theme)
		_add_category_branch(header, cat, query, theme)
		shown += 1
	var uncategorized: Array[String] = []
	for path in script_paths:
		if _cats_of(path).is_empty() and _matches(path, query):
			uncategorized.append(path)
	if not uncategorized.is_empty():
		if shown > 0 and bool(_setting("space_between_categories")):
			_add_spacer(header, theme)
		var item := _create_category_item(header, "", theme)
		_sort_paths(uncategorized)
		for path in uncategorized:
			_add_script_item(item, path, "", theme)
		_finish_header(item, "", false, query)
	_finish_header(header, SECTION_PREFIX + "scripts", bool(_setting("scripts_collapsed_by_default")), query)


func _create_category_item(parent: TreeItem, cat: String, theme: Theme) -> TreeItem:
	var item := tree.create_item(parent)
	item.set_text(0, _category_label(_leaf_of(cat) if cat != "" else "Uncategorized"))
	item.set_custom_color(0, theme.get_color("accent_color", "Editor"))
	item.set_metadata(0, {"type": "category", "name": cat})
	return item


func _add_category_branch(parent: TreeItem, cat: String, query: String, theme: Theme) -> void:
	var item := _create_category_item(parent, cat, theme)
	for path in _scripts_directly_in(cat, query):
		_add_script_item(item, path, cat, theme)
	for child_cat in categories:
		if _parent_of(child_cat) != cat:
			continue
		if not query.is_empty() and not _branch_has_matches(child_cat, query):
			continue
		_add_category_branch(item, child_cat, query, theme)
	_finish_header(item, cat, false, query)


func _add_spacer(parent: TreeItem, theme: Theme) -> void:
	# blank row; the invisible icon keeps it as tall as a script row
	var spacer := tree.create_item(parent)
	spacer.set_text(0, "")
	spacer.set_icon(0, theme.get_icon("GDScript", "EditorIcons"))
	spacer.set_icon_modulate(0, Color(1, 1, 1, 0))
	spacer.set_selectable(0, false)


func _add_script_item(parent: TreeItem, path: String, cat: String, theme: Theme) -> void:
	var item := tree.create_item(parent)
	item.set_text(0, path.get_file())
	item.set_tooltip_text(0, path)
	item.set_icon(0, theme.get_icon("GDScript", "EditorIcons"))
	item.set_metadata(0, {"type": "script", "path": path, "category": cat})


func _vscroll() -> VScrollBar:
	for child in tree.get_children(true):
		if child is VScrollBar:
			return child as VScrollBar
	return null


func _get_scroll() -> float:
	var bar := _vscroll()
	return bar.value if bar != null else 0.0


func _restore_scroll(value: float) -> void:
	await get_tree().process_frame
	var bar := _vscroll()
	if bar != null:
		bar.value = value


func _all_items() -> Array[TreeItem]:
	var out: Array[TreeItem] = []
	if tree.get_root() == null:
		return out
	var stack: Array[TreeItem] = [tree.get_root()]
	while not stack.is_empty():
		var item: TreeItem = stack.pop_back()
		for child in item.get_children():
			out.append(child)
			stack.append(child)
	return out


func _selected_items() -> Array[TreeItem]:
	var out: Array[TreeItem] = []
	var item := tree.get_next_selected(null)
	while item != null:
		out.append(item)
		item = tree.get_next_selected(item)
	return out


func _selected_scripts() -> Array:
	var out: Array = []
	for item in _selected_items():
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary and meta.get("type", "") == "script":
			out.append({"path": meta["path"], "category": meta["category"]})
	return out


func _find_visible(parent: TreeItem, kind: String, field: String, wanted: Variant) -> TreeItem:
	# first matching row that is not inside a folded section
	var child := parent.get_first_child()
	while child != null:
		var meta: Variant = child.get_metadata(0)
		if meta is Dictionary and meta.get("type", "") == kind and meta.get(field, null) == wanted:
			return child
		if not child.collapsed:
			var found := _find_visible(child, kind, field, wanted)
			if found != null:
				return found
		child = child.get_next()
	return null


func _select_path(path: String) -> void:
	if not is_instance_valid(tree) or path == "" or tree.get_root() == null:
		return
	var selected := _selected_items()
	if selected.size() > 1:
		return  # keep a multi-selection intact
	if selected.size() == 1:
		var meta: Variant = selected[0].get_metadata(0)
		if meta is Dictionary and meta.get("path", "") == path:
			return
	var item := _find_visible(tree.get_root(), "script", "path", path)
	tree.deselect_all()
	if item != null:
		# don't force a folded section open
		item.select(0)
		tree.scroll_to_item(item)


func _select_tab_item(index: int) -> void:
	if tree.get_root() == null:
		return
	var selected := _selected_items()
	if selected.size() > 1:
		return
	var item := _find_visible(tree.get_root(), "open_tab", "index", index)
	if item == null:
		return
	if selected.size() == 1 and selected[0] == item:
		return
	tree.deselect_all()
	item.select(0)
	tree.scroll_to_item(item)


func _on_search_changed(_text: String) -> void:
	_rebuild_tree()


func _on_editor_script_changed(script_res: Script) -> void:
	if script_res != null:
		_select_path(script_res.resource_path)
	_sync_tabs.call_deferred(false)


func _on_script_closed(_script_res: Script) -> void:
	_sync_tabs.call_deferred(false)


func _modifier_held() -> bool:
	return Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_META)


func _on_tree_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_Z \
			and key.is_command_or_control_pressed() and not key.shift_pressed:
		_undo()
		tree.accept_event()


func _on_item_mouse_selected(pos: Vector2, button: int) -> void:
	var item := tree.get_item_at_position(pos)
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	if button == MOUSE_BUTTON_LEFT:
		if meta["type"] == "script":
			if _modifier_held():
				return  # ctrl/shift-click only selects
			if item.is_selected(0) and _selected_items().size() > 1:
				return  # likely the start of a drag
			_open_script(meta["path"])
		elif meta["type"] == "open_tab":
			_activate_tab(meta)
	elif button == MOUSE_BUTTON_RIGHT:
		_show_menu(item, meta)


func _on_item_activated() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	match meta["type"]:
		"script":
			_open_script(meta["path"])
		"open_tab":
			_activate_tab(meta)
		"section", "category":
			_toggle_header_after_frame(item, Time.get_ticks_msec())


func _toggle_header_after_frame(item: TreeItem, started: int) -> void:
	# let the tree finish its own toggle for this click first, otherwise the
	# two toggles cancel out and the header flickers
	await get_tree().process_frame
	if not is_instance_valid(item):
		return
	if last_collapse_id == item.get_instance_id() and last_collapse_msec >= started - ACTIVATE_GRACE_MS:
		return
	_set_header_collapsed(item, not item.collapsed)


func _state_key(meta: Dictionary) -> String:
	if meta["type"] == "section":
		return SECTION_PREFIX + str(meta["key"])
	return str(meta["name"])


func _on_item_collapsed(item: TreeItem) -> void:
	if rebuilding or self_toggling:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary and meta.get("type", "") in ["section", "category"]):
		return
	var now := Time.get_ticks_msec()
	var id := item.get_instance_id()
	if id == last_toggle_id and now - last_toggle_msec < DOUBLE_TOGGLE_MS:
		# double-clicked the arrow: keep the first toggle
		last_toggle_id = 0
		self_toggling = true
		item.collapsed = last_toggle_state
		self_toggling = false
	else:
		last_toggle_id = id
		last_toggle_msec = now
		last_toggle_state = item.collapsed
	_record_collapse(item)


func _set_header_collapsed(item: TreeItem, value: bool) -> void:
	if item.collapsed == value:
		return
	self_toggling = true
	item.collapsed = value
	self_toggling = false
	_record_collapse(item)


func _record_collapse(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		collapsed_state[_state_key(meta)] = item.collapsed
	last_collapse_id = item.get_instance_id()
	last_collapse_msec = Time.get_ticks_msec()
	_save_collapsed()
	tree.queue_redraw()


func _set_all_collapsed(value: bool) -> void:
	for key in SECTION_KEYS:
		collapsed_state[SECTION_PREFIX + key] = value
	collapsed_state[""] = value
	for cat in categories:
		collapsed_state[cat] = value
	self_toggling = true
	for item in _all_items():
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary and meta.get("type", "") in ["section", "category"]:
			item.collapsed = value
	self_toggling = false
	_save_collapsed()
	tree.queue_redraw()


func _open_script(path: String) -> void:
	var script_res := ResourceLoader.load(path) as Script
	if script_res == null:
		push_warning("Script Categories: could not load %s" % path)
		return
	EditorInterface.edit_script(script_res)
	EditorInterface.set_main_screen_editor("Script")


func _open_many(paths: Array[String]) -> void:
	var last := paths.size() - 1
	for i in paths.size():
		var script_res := ResourceLoader.load(paths[i]) as Script
		if script_res != null:
			EditorInterface.edit_script(script_res, -1, 0, i == last)
	EditorInterface.set_main_screen_editor("Script")


func _add_menu_item(label: String, data: Dictionary) -> void:
	var id := menu.item_count
	menu.add_item(label, id)
	menu.set_item_metadata(menu.item_count - 1, data)


func _separator_if_needed() -> void:
	if menu.item_count > 0 and not menu.is_item_separator(menu.item_count - 1):
		menu.add_separator()


func _popup_menu_at_mouse() -> void:
	menu.position = Vector2i(tree.get_screen_position() + tree.get_local_mouse_position())
	menu.popup()


func _show_menu(item: TreeItem, meta: Dictionary) -> void:
	menu.clear()
	match meta["type"]:
		"script":
			_build_script_menu(item, meta)
		"category":
			var cat: String = meta["name"]
			if cat == "":
				return
			_add_menu_item("New subcategory...", {"action": "new_sub", "category": cat})
			_add_menu_item("Rename...", {"action": "rename", "category": cat})
			_add_menu_item("Move up", {"action": "up", "category": cat})
			_add_menu_item("Move down", {"action": "down", "category": cat})
			menu.add_separator()
			_add_menu_item("Open all in category", {"action": "open_all", "category": cat})
			menu.add_separator()
			_add_menu_item("Delete category...", {"action": "delete", "category": cat})
		"open_tab":
			_add_menu_item("Close", {"action": "close_tab", "index": meta["index"], "text": meta["text"]})
		_:
			return
	_popup_menu_at_mouse()


func _build_script_menu(item: TreeItem, meta: Dictionary) -> void:
	var entries: Array = []
	if item.is_selected(0) and _selected_items().size() > 1:
		entries = _selected_scripts()
	if entries.is_empty():
		entries = [{"path": meta["path"], "category": meta["category"]}]
	var paths: Array = []
	for entry in entries:
		if not paths.has(entry["path"]):
			paths.append(entry["path"])
	var multi := paths.size() > 1

	if not multi:
		_add_menu_item("Open", {"action": "open", "path": paths[0]})

	var addable: Array = []
	for cat in categories:
		for path in paths:
			if not (script_cats.get(path, []) as Array).has(cat):
				addable.append(cat)
				break
	if not addable.is_empty():
		_separator_if_needed()
	for cat in addable:
		_add_menu_item("Add to: %s" % cat, {"action": "add", "paths": paths, "category": cat})

	var from_cat: String = meta["category"]
	if from_cat != "":
		var remove_entries: Array = []
		for entry in entries:
			if entry["category"] == from_cat:
				remove_entries.append(entry)
		_separator_if_needed()
		_add_menu_item("Remove from: %s" % from_cat, {"action": "remove", "entries": remove_entries, "category": from_cat})

	_separator_if_needed()
	if not multi:
		_add_menu_item("Open scene using this script", {"action": "find_scene", "path": paths[0]})
		_add_menu_item("Show in FileSystem", {"action": "show_fs", "path": paths[0]})
	_add_menu_item("Copy paths" if multi else "Copy path", {"action": "copy", "paths": paths})


func _on_menu_id_pressed(id: int) -> void:
	var data: Dictionary = menu.get_item_metadata(menu.get_item_index(id))
	match data["action"]:
		"open":
			_open_script(data["path"])
		"add":
			_push_undo()
			for path in data["paths"]:
				_add_to_category(path, data["category"])
			_commit()
		"remove":
			_push_undo()
			for entry in data["entries"]:
				_remove_from_category(entry["path"], data["category"])
			_commit()
		"find_scene":
			_open_scene_for(data["path"])
		"open_scene":
			EditorInterface.open_scene_from_path(data["path"])
		"show_fs":
			EditorInterface.get_file_system_dock().navigate_to_path(data["path"])
		"copy":
			var lines := PackedStringArray()
			for path in data["paths"]:
				lines.append(path)
			DisplayServer.clipboard_set("\n".join(lines))
		"new_sub":
			_ask_new_category(data["category"])
		"rename":
			_ask_rename(data["category"])
		"up":
			_move_category(data["category"], -1)
		"down":
			_move_category(data["category"], 1)
		"open_all":
			_request_open_all(data["category"])
		"delete":
			_request_delete(data["category"])
		"close_tab":
			var index: int = data["index"]
			if is_instance_valid(builtin_list) and index < builtin_list.item_count:
				if builtin_list.get_item_text(index).trim_suffix("(*)").strip_edges() == data["text"]:
					builtin_list.item_clicked.emit(index, Vector2.ZERO, MOUSE_BUTTON_MIDDLE)


func _scenes_using(path: String) -> Array[String]:
	var found: Array[String] = []
	var scenes: Array[String] = []
	_collect_files("res://", ["tscn"], scenes)
	var uid := _key_for(path)
	for scene in scenes:
		var file := FileAccess.open(scene, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		if text.contains(path) or (uid.begins_with("uid://") and text.contains(uid)):
			found.append(scene)
	return found


func _open_scene_for(path: String) -> void:
	var scenes := _scenes_using(path)
	if scenes.is_empty():
		info_dialog.dialog_text = "No scene found that uses\n%s" % path
		info_dialog.popup_centered()
	elif scenes.size() == 1:
		EditorInterface.open_scene_from_path(scenes[0])
	else:
		_show_scene_picker.call_deferred(scenes)


func _show_scene_picker(scenes: Array[String]) -> void:
	menu.clear()
	for scene in scenes:
		var folder := scene.get_base_dir().trim_prefix("res://")
		_add_menu_item("Open scene: %s  (%s)" % [scene.get_file(), folder], {"action": "open_scene", "path": scene})
	_popup_menu_at_mouse()


func _get_drag(at_position: Vector2) -> Variant:
	var item := tree.get_item_at_position(at_position)
	if item == null:
		return null
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary and meta["type"] == "script"):
		return null
	var entries: Array = []
	if item.is_selected(0):
		entries = _selected_scripts()
	if entries.is_empty():
		entries = [{"path": meta["path"], "category": meta["category"]}]
	var preview := Label.new()
	if entries.size() > 1:
		preview.text = "%d scripts" % entries.size()
	else:
		preview.text = String(meta["path"]).get_file()
	tree.set_drag_preview(preview)
	return {"script_categories_drag": true, "items": entries}


func _can_drop(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.has("script_categories_drag")):
		return false
	var item := tree.get_item_at_position(at_position)
	if item == null:
		return false
	var meta: Variant = item.get_metadata(0)
	return meta is Dictionary and meta.get("type", "") in ["category", "script"]


func _drop(at_position: Vector2, data: Variant) -> void:
	var item := tree.get_item_at_position(at_position)
	if item == null or not (data is Dictionary):
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	var target: String = meta["name"] if meta["type"] == "category" else meta["category"]
	var copy_mode := Input.is_key_pressed(KEY_CTRL)
	_push_undo()
	for entry in data["items"]:
		var path: String = entry["path"]
		var from_cat: String = entry["category"]
		if target == from_cat:
			continue
		if target != "":
			_add_to_category(path, target)
		if from_cat != "" and not copy_mode:
			_remove_from_category(path, from_cat)
	_commit()


func _remember_uid(path: String) -> void:
	var id := ResourceLoader.get_resource_uid(path)
	if id != ResourceUID.INVALID_ID:
		path_uid[path] = ResourceUID.id_to_text(id)


func _add_to_category(path: String, cat: String) -> void:
	var cats: Array = (script_cats.get(path, []) as Array).duplicate()
	if not cats.has(cat):
		cats.append(cat)
	script_cats[path] = cats
	_remember_uid(path)


func _remove_from_category(path: String, cat: String) -> void:
	var cats: Array = (script_cats.get(path, []) as Array).duplicate()
	cats.erase(cat)
	if cats.is_empty():
		script_cats.erase(path)
	else:
		script_cats[path] = cats


func _commit() -> void:
	_save_data()
	_rebuild_tree(true)


func _rename_path(path: String, old_path: String, new_path: String) -> String:
	if path == old_path:
		return new_path
	if path.begins_with(old_path + "/"):
		return new_path + path.substr(old_path.length())
	return path


func _ask_new_category(parent := "") -> void:
	dialog_mode = "new_sub" if parent != "" else "new"
	dialog_target = parent
	name_dialog.title = "New subcategory in %s" % parent if parent != "" else "New category"
	name_edit.text = ""
	name_dialog.popup_centered(Vector2i(320, 100))
	name_edit.grab_focus()


func _ask_rename(cat: String) -> void:
	dialog_mode = "rename"
	dialog_target = cat
	name_dialog.title = "Rename category"
	name_edit.text = _leaf_of(cat)
	name_dialog.popup_centered(Vector2i(320, 100))
	name_edit.grab_focus()
	name_edit.select_all()


func _on_name_confirmed() -> void:
	var leaf := name_edit.text.strip_edges().replace("/", "-")
	if leaf.is_empty():
		return
	if dialog_mode == "rename":
		var old := dialog_target
		var parent := _parent_of(old)
		var new_full := leaf if parent == "" else parent + "/" + leaf
		if new_full == old or categories.has(new_full) or not categories.has(old):
			return
		_push_undo()
		for i in categories.size():
			categories[i] = _rename_path(categories[i], old, new_full)
		for path in script_cats.keys():
			var cats: Array = (script_cats[path] as Array).duplicate()
			for i in cats.size():
				cats[i] = _rename_path(str(cats[i]), old, new_full)
			script_cats[path] = cats
		var moved := {}
		for key in collapsed_state.keys():
			var renamed := _rename_path(str(key), old, new_full)
			if renamed != key:
				moved[renamed] = collapsed_state[key]
				collapsed_state.erase(key)
		collapsed_state.merge(moved, true)
		_save_collapsed()
	else:
		var parent := dialog_target if dialog_mode == "new_sub" else ""
		var full := leaf if parent == "" else parent + "/" + leaf
		if categories.has(full):
			return
		_push_undo()
		categories.append(full)
	_commit()


func _move_category(cat: String, delta: int) -> void:
	var siblings: Array[String] = []
	for other in categories:
		if _parent_of(other) == _parent_of(cat):
			siblings.append(other)
	var at := siblings.find(cat) + delta
	if at < 0 or at >= siblings.size():
		return
	_push_undo()
	var i := categories.find(cat)
	var j := categories.find(siblings[at])
	categories[i] = siblings[at]
	categories[j] = cat
	_commit()


func _request_delete(cat: String) -> void:
	delete_target = cat
	confirm_mode = "delete"
	var inside := 0
	for other in categories:
		if other.begins_with(cat + "/"):
			inside += 1
	confirm_dialog.title = "Delete category"
	confirm_dialog.dialog_text = "Delete \"%s\"" % cat
	if inside > 0:
		confirm_dialog.dialog_text += " and its %d subcategories" % inside
	confirm_dialog.dialog_text += "?\nThe scripts themselves are not touched."
	confirm_dialog.popup_centered()


func _request_open_all(cat: String) -> void:
	var paths := _scripts_in_branch(cat)
	if paths.is_empty():
		info_dialog.dialog_text = "There are no scripts in \"%s\"." % cat
		info_dialog.popup_centered()
	elif paths.size() > int(_setting("open_all_confirm_above")):
		confirm_mode = "open_all"
		pending_paths = paths
		confirm_dialog.title = "Open all"
		confirm_dialog.dialog_text = "Open %d scripts in \"%s\"?" % [paths.size(), cat]
		confirm_dialog.popup_centered()
	else:
		_open_many(paths)


func _on_confirmed() -> void:
	match confirm_mode:
		"delete":
			_delete_category(delete_target)
		"open_all":
			_open_many(pending_paths)


func _delete_category(cat: String) -> void:
	_push_undo()
	var gone: Array[String] = []
	for other in categories:
		if other == cat or other.begins_with(cat + "/"):
			gone.append(other)
	for other in gone:
		categories.erase(other)
		collapsed_state.erase(other)
	for path in script_cats.keys():
		var cats: Array = []
		for c in script_cats[path]:
			if not gone.has(c):
				cats.append(c)
		if cats.is_empty():
			script_cats.erase(path)
		else:
			script_cats[path] = cats
	_save_collapsed()
	_commit()


func _push_undo() -> void:
	var cats_copy := {}
	for path in script_cats:
		cats_copy[path] = (script_cats[path] as Array).duplicate()
	var list: Array = []
	list.append_array(categories)
	undo_stack.append({"categories": list, "script_cats": cats_copy})
	_trim_undo()
	_update_undo_button()


func _trim_undo() -> void:
	var limit := int(_setting("undo_steps"))
	while undo_stack.size() > limit:
		undo_stack.pop_front()
	_update_undo_button()


func _update_undo_button() -> void:
	if is_instance_valid(undo_button):
		undo_button.disabled = undo_stack.is_empty()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var snapshot: Dictionary = undo_stack.pop_back()
	categories.assign(snapshot["categories"])
	script_cats = snapshot["script_cats"]
	_update_undo_button()
	_commit()


func _to_array(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			out.append(str(entry))
	return out


func _path_for(key: String, fallback_path: String) -> String:
	if key.begins_with("uid://"):
		var id := ResourceUID.text_to_id(key)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		if fallback_path != "" and FileAccess.file_exists(fallback_path):
			return fallback_path
		return ""
	return key if FileAccess.file_exists(key) else ""


func _key_for(path: String) -> String:
	if path_uid.has(path):
		return path_uid[path]
	var id := ResourceLoader.get_resource_uid(path)
	if id != ResourceUID.INVALID_ID:
		path_uid[path] = ResourceUID.id_to_text(id)
		return path_uid[path]
	return path


func _load_collapsed() -> void:
	collapsed_state.clear()
	var saved: Variant = EditorInterface.get_editor_settings().get_project_metadata(META_SECTION, "collapsed", {})
	if saved is Dictionary:
		for key in saved:
			collapsed_state[str(key)] = bool(saved[key])


func _save_collapsed() -> void:
	EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, "collapsed", collapsed_state)


func _ensure_parents() -> void:
	# a subcategory always needs its parent
	for cat in categories.duplicate():
		var parent := _parent_of(cat)
		while parent != "":
			if not categories.has(parent):
				categories.insert(categories.find(cat), parent)
			parent = _parent_of(parent)


func _load_data() -> void:
	categories.clear()
	script_cats.clear()
	path_uid.clear()
	orphans.clear()
	if not FileAccess.file_exists(DATA_PATH):
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	for cat in parsed.get("categories", []):
		categories.append(str(cat))
	_ensure_parents()
	var saved: Variant = parsed.get("scripts", {})
	if not (saved is Dictionary):
		return
	for key in saved:
		var entry: Variant = saved[key]
		if not (entry is Dictionary):
			continue
		var cats := _to_array(entry.get("categories", []))
		if cats.is_empty():
			continue
		var resolved := _path_for(str(key), str(entry.get("path", "")))
		if resolved == "":
			orphans[str(key)] = entry
		else:
			script_cats[resolved] = cats
			if str(key).begins_with("uid://"):
				path_uid[resolved] = str(key)


func _save_data() -> void:
	var categories_out: Array = []
	for cat in categories:
		categories_out.append(cat)
	var scripts_out := {}
	for orphan_key in orphans:
		scripts_out[orphan_key] = orphans[orphan_key]
	for path in script_cats:
		scripts_out[_key_for(path)] = {"path": path, "categories": script_cats[path]}
	var file := FileAccess.open(DATA_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Script Categories: could not save %s" % DATA_PATH)
		return
	file.store_string(JSON.stringify({"categories": categories_out, "scripts": scripts_out}, "\t"))
	file.close()
