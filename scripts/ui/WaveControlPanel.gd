## Production wave controls: one-wave release, full restart, and return to level select.
class_name WaveControlPanel
extends Control

const WaveTimelineModelScript := preload("res://scripts/ui/WaveTimelineModel.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Layout")
@export_range(48.0, 96.0, 1.0) var button_size: float = 68.0

@export_group("Optional Icons")
@export var start_next_wave_icon: Texture2D
@export var restart_level_icon: Texture2D
@export var exit_level_icon: Texture2D
@export var fallback_enemy_icon: Texture2D

signal restart_level_requested
signal exit_level_requested
signal paths_preview_requested(paths: Array)
signal paths_preview_cleared

@onready var button_column: VBoxContainer = $ButtonColumn
@onready var start_button: Button = $ButtonColumn/StartNextWaveButton
@onready var restart_button: Button = $ButtonColumn/RestartLevelButton
@onready var exit_button: Button = $ButtonColumn/ExitLevelButton
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/Content/Title
@onready var info_icons: HBoxContainer = $InfoPanel/Content/EnemyIcons
@onready var info_details: Label = $InfoPanel/Content/Details

var _model: WaveTimelineModelScript = WaveTimelineModelScript.new()
var _wave_manager: WaveManager
var _entries: Array[Dictionary] = []
var _hovering_next_wave: bool = false
var _preview_suppressed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = feature_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_button.pressed.connect(_on_start_pressed)
	start_button.mouse_entered.connect(_on_start_mouse_entered)
	start_button.mouse_exited.connect(_on_start_mouse_exited)
	restart_button.pressed.connect(_on_restart_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	_apply_optional_art()
	_apply_button_size()
	_refresh_state()


func configure(wave_manager: WaveManager) -> void:
	_disconnect_wave_manager()
	_wave_manager = wave_manager
	if _wave_manager != null:
		_wave_manager.next_wave_changed.connect(_on_next_wave_changed)
		_wave_manager.wave_released.connect(_on_wave_released)
		_wave_manager.state_changed.connect(_on_wave_state_changed)
	_refresh_state()


func set_level(level: LevelResource) -> void:
	clear_hover_preview()
	_entries = _model.build(level)
	_refresh_state()


func set_preview_suppressed(suppressed: bool) -> void:
	_preview_suppressed = suppressed
	if suppressed:
		clear_hover_preview()


func clear_hover_preview() -> void:
	_hovering_next_wave = false
	if info_panel != null:
		info_panel.visible = false
	paths_preview_cleared.emit()


func preview_next_wave_for_test() -> void:
	_on_start_mouse_entered()


func get_previewed_wave_number() -> int:
	if not _hovering_next_wave or _wave_manager == null:
		return 0
	return _wave_manager.get_next_wave_number()


func _on_start_pressed() -> void:
	clear_hover_preview()
	if _wave_manager != null:
		_wave_manager.start_next_wave()


func _on_restart_pressed() -> void:
	clear_hover_preview()
	restart_level_requested.emit()


func _on_exit_pressed() -> void:
	clear_hover_preview()
	exit_level_requested.emit()


func _on_start_mouse_entered() -> void:
	if _preview_suppressed or _wave_manager == null or not _wave_manager.can_start_next_wave():
		return
	var wave_number := _wave_manager.get_next_wave_number()
	var entry := _find_entry(wave_number - 1)
	if entry.is_empty():
		return
	_hovering_next_wave = true
	info_title.text = String(entry["display_name"])
	info_details.text = String(entry["summary"])
	_rebuild_enemy_icons(entry["enemy_totals"])
	info_panel.visible = true
	var paths: Array = entry["paths"]
	paths_preview_requested.emit(paths)


func _on_start_mouse_exited() -> void:
	if _hovering_next_wave:
		clear_hover_preview()


func _find_entry(wave_index: int) -> Dictionary:
	for entry in _entries:
		if int(entry.get("wave_index", -1)) == wave_index:
			return entry
	return {}


func _rebuild_enemy_icons(enemy_totals: Array) -> void:
	for child in info_icons.get_children():
		child.queue_free()
	for total in enemy_totals:
		var icon: Texture2D = total["icon"]
		if icon == null:
			icon = fallback_enemy_icon
		if icon != null:
			var texture := TextureRect.new()
			texture.custom_minimum_size = Vector2(34.0, 34.0)
			texture.texture = icon
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			info_icons.add_child(texture)
			continue
		var fallback := Label.new()
		fallback.custom_minimum_size = Vector2(34.0, 34.0)
		var enemy_name: String = String(total["name"])
		fallback.text = enemy_name.left(1) if not enemy_name.is_empty() else "?"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info_icons.add_child(fallback)


func _refresh_state() -> void:
	if start_button == null:
		return
	var next_wave_number := _wave_manager.get_next_wave_number() if _wave_manager != null else 0
	start_button.disabled = not feature_enabled or _wave_manager == null or not _wave_manager.can_start_next_wave()
	start_button.tooltip_text = "释放第 %d 波" % next_wave_number if next_wave_number > 0 else "全部波次已释放"


func _apply_optional_art() -> void:
	start_button.icon = start_next_wave_icon
	restart_button.icon = restart_level_icon
	exit_button.icon = exit_level_icon


func _apply_button_size() -> void:
	var resolved_size := maxf(48.0, button_size)
	for button in [start_button, restart_button, exit_button]:
		button.custom_minimum_size = Vector2(resolved_size, resolved_size)


func _on_next_wave_changed(_wave_number: int, _wave: WaveDefinition) -> void:
	_refresh_state()


func _on_wave_released(_wave_number: int, _wave: WaveDefinition) -> void:
	clear_hover_preview()
	_refresh_state()


func _on_wave_state_changed(_state: WaveManager.State, _current: int, _total: int, _active: int) -> void:
	_refresh_state()


func _disconnect_wave_manager() -> void:
	if _wave_manager == null:
		return
	if _wave_manager.next_wave_changed.is_connected(_on_next_wave_changed):
		_wave_manager.next_wave_changed.disconnect(_on_next_wave_changed)
	if _wave_manager.wave_released.is_connected(_on_wave_released):
		_wave_manager.wave_released.disconnect(_on_wave_released)
	if _wave_manager.state_changed.is_connected(_on_wave_state_changed):
		_wave_manager.state_changed.disconnect(_on_wave_state_changed)
