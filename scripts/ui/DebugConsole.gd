## Button-opened modal console. It renders registries but contains no business commands.
class_name DebugConsole
extends Control

const DebugCommandRegistryScript := preload("res://scripts/debug/DebugCommandRegistry.gd")
const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Refresh")
@export_range(0.05, 2.0, 0.05, "or_greater") var live_refresh_interval: float = 0.2
@export_range(20, 1000, 10, "or_greater") var max_history_lines: int = 200

@export_group("Art")
@export var panel_texture: Texture2D
@export var execute_icon: Texture2D

@onready var frame_texture: TextureRect = $Shade/ConsoleFrame/FrameTexture
@onready var category_list: VBoxContainer = $Shade/ConsoleFrame/Margin/Content/Body/CategoryPanel/CategoryMargin/CategoryContent/CategoryScroll/CategoryList
@onready var live_output: RichTextLabel = $Shade/ConsoleFrame/Margin/Content/Body/MainPanel/MainMargin/MainContent/LiveOutput
@onready var log_output: RichTextLabel = $Shade/ConsoleFrame/Margin/Content/Body/MainPanel/MainMargin/MainContent/LogOutput
@onready var command_input: LineEdit = $Shade/ConsoleFrame/Margin/Content/Body/MainPanel/MainMargin/MainContent/CommandRow/CommandInput
@onready var execute_button: Button = $Shade/ConsoleFrame/Margin/Content/Body/MainPanel/MainMargin/MainContent/CommandRow/ExecuteButton
@onready var close_button: Button = $Shade/ConsoleFrame/Margin/Content/Header/CloseButton
@onready var state_label: Label = $Shade/ConsoleFrame/Margin/Content/Header/StateLabel

signal open_changed(open: bool)

var _command_registry: DebugCommandRegistryScript
var _category_registry: DebugCategoryRegistryScript
var _category_checks: Dictionary = {}
var _history_lines: Array[String] = []
var _next_live_refresh_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	execute_button.pressed.connect(_submit_input)
	command_input.text_submitted.connect(_on_text_submitted)
	close_button.pressed.connect(close_console)
	if panel_texture != null:
		frame_texture.texture = panel_texture
		frame_texture.visible = true
	if execute_icon != null:
		execute_button.icon = execute_icon


func _process(_delta: float) -> void:
	if not visible or _category_registry == null:
		return
	var now := Time.get_ticks_msec()
	if now < _next_live_refresh_msec:
		return
	_next_live_refresh_msec = now + maxi(1, roundi(live_refresh_interval * 1000.0))
	_refresh_live_output()


func _input(event: InputEvent) -> void:
	if not feature_enabled:
		return
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel_action")):
		close_console()
		get_viewport().set_input_as_handled()


func set_feature_enabled(enabled: bool) -> void:
	feature_enabled = enabled
	if not feature_enabled:
		close_console()


func configure(
	command_registry: DebugCommandRegistryScript,
	category_registry: DebugCategoryRegistryScript
) -> void:
	_disconnect_registry()
	_command_registry = command_registry
	_category_registry = category_registry
	if _category_registry != null:
		_category_registry.category_changed.connect(_on_category_changed)
		_category_registry.categories_changed.connect(_rebuild_categories)
	_rebuild_categories()
	_refresh_live_output()


func open_console() -> void:
	if not feature_enabled or visible:
		return
	visible = true
	_next_live_refresh_msec = 0
	_refresh_live_output()
	command_input.grab_focus()
	open_changed.emit(true)


func close_console() -> void:
	if not visible:
		return
	visible = false
	command_input.release_focus()
	open_changed.emit(false)


func toggle_console() -> void:
	if visible:
		close_console()
	else:
		open_console()


func is_open() -> bool:
	return visible


func submit_command(input: String) -> Dictionary:
	if _command_registry == null:
		var unavailable := {"success": false, "message": "命令注册表未连接", "clear": false}
		_append_result(input, unavailable)
		return unavailable
	var result := _command_registry.execute(input)
	if bool(result.get("clear", false)):
		_history_lines.clear()
		log_output.text = ""
		return result
	_append_result(input, result)
	return result


func get_history_text() -> String:
	return "\n".join(_history_lines)


func get_category_checkbox(category_id: StringName) -> CheckBox:
	if not _category_checks.has(category_id):
		return null
	return _category_checks[category_id] as CheckBox


func _submit_input() -> void:
	var input := command_input.text.strip_edges()
	if input.is_empty():
		return
	command_input.text = ""
	submit_command(input)
	command_input.grab_focus()


func _on_text_submitted(_text: String) -> void:
	_submit_input()


func _append_result(input: String, result: Dictionary) -> void:
	_history_lines.append("> %s" % input)
	var message := str(result.get("message", ""))
	if not message.is_empty():
		var prefix := "[OK] " if bool(result.get("success", false)) else "[ERR] "
		for line in message.split("\n"):
			_history_lines.append("%s%s" % [prefix, line])
	while _history_lines.size() > max_history_lines:
		_history_lines.remove_at(0)
	log_output.text = "\n".join(_history_lines)
	log_output.scroll_to_line(maxi(0, log_output.get_line_count() - 1))


func _rebuild_categories() -> void:
	if category_list == null:
		return
	for child in category_list.get_children():
		child.queue_free()
	_category_checks.clear()
	if _category_registry == null:
		state_label.text = "未连接"
		return
	for entry in _category_registry.list_categories():
		var category_id: StringName = entry.get("id", &"")
		var check := CheckBox.new()
		check.text = "%s  [%s]" % [str(entry.get("display_name", category_id)), category_id]
		check.button_pressed = bool(entry.get("enabled", false))
		check.toggled.connect(_on_category_toggled.bind(category_id))
		category_list.add_child(check)
		_category_checks[category_id] = check
	state_label.text = "%d 个分类" % _category_checks.size()


func _refresh_live_output() -> void:
	if live_output == null:
		return
	if _category_registry == null:
		live_output.text = "未连接调试分类注册表"
		return
	var sections: Array[String] = []
	for snapshot in _category_registry.get_enabled_snapshot():
		sections.append("[%s]\n%s" % [
			str(snapshot.get("display_name", "")),
			str(snapshot.get("text", "")),
		])
	live_output.text = "\n\n".join(sections) if not sections.is_empty() else "勾选左侧分类以显示实时调试信息"


func _on_category_toggled(enabled: bool, category_id: StringName) -> void:
	if _category_registry != null:
		_category_registry.set_enabled(category_id, enabled)
	_refresh_live_output()


func _on_category_changed(category_id: StringName, enabled: bool) -> void:
	var check := get_category_checkbox(category_id)
	if check != null:
		check.set_pressed_no_signal(enabled)
	_refresh_live_output()


func _disconnect_registry() -> void:
	if _category_registry == null:
		return
	if _category_registry.category_changed.is_connected(_on_category_changed):
		_category_registry.category_changed.disconnect(_on_category_changed)
	if _category_registry.categories_changed.is_connected(_rebuild_categories):
		_category_registry.categories_changed.disconnect(_rebuild_categories)
