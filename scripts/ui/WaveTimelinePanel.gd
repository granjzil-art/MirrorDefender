## Formal M6 vertical wave timeline. Reads authored data and WaveManager state only.
class_name WaveTimelinePanel
extends Control

const WaveTimelineModelScript := preload("res://scripts/ui/WaveTimelineModel.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Timeline")
@export_range(2.0, 180.0, 0.5, "or_greater") var visible_future_seconds: float = 18.0
@export_range(44.0, 140.0, 1.0, "or_greater") var wave_block_height: float = 72.0
@export_range(0.0, 24.0, 1.0) var current_line_inset: float = 8.0

@export_group("Visual")
@export var pending_color: Color = Color(0.64, 0.80, 0.88, 1.0)
@export var active_color: Color = Color(1.0, 0.72, 0.22, 1.0)
@export var completed_color: Color = Color(0.34, 0.82, 0.56, 0.72)
@export var current_line_color: Color = Color(1.0, 0.78, 0.28, 1.0)

@export_group("Optional Art")
@export var wave_block_texture: Texture2D
@export var current_line_texture: Texture2D
@export var start_button_icon: Texture2D
@export var fallback_enemy_icon: Texture2D

signal paths_preview_requested(paths: Array)
signal paths_preview_cleared

@onready var timeline_area: Control = $GlassPanel/TimelineArea
@onready var block_layer: Control = $GlassPanel/TimelineArea/BlockLayer
@onready var current_line_fallback: ColorRect = $GlassPanel/TimelineArea/CurrentLineFallback
@onready var current_line_art: TextureRect = $GlassPanel/TimelineArea/CurrentLineArt
@onready var status_label: Label = $GlassPanel/Status
@onready var start_button: Button = $GlassPanel/StartButton
@onready var info_panel: PanelContainer = $InfoPanel
@onready var info_title: Label = $InfoPanel/Content/Title
@onready var info_icons: HBoxContainer = $InfoPanel/Content/EnemyIcons
@onready var info_details: Label = $InfoPanel/Content/Details

var _model: WaveTimelineModelScript = WaveTimelineModelScript.new()
var _wave_manager: WaveManager
var _entries: Array[Dictionary] = []
var _blocks: Dictionary = {}
var _started_wave_indices: Dictionary = {}
var _completed_wave_indices: Dictionary = {}
var _hovered_wave_index: int = -1
var _preview_suppressed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = feature_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_button.pressed.connect(_on_start_pressed)
	resized.connect(_update_timeline_layout)
	_apply_optional_art()
	_refresh_state()


func _process(_delta: float) -> void:
	if not feature_enabled or not visible:
		return
	_update_timeline_layout()
	if _wave_manager != null and _wave_manager.get_state() == WaveManager.State.ACTIVE:
		status_label.text = "当前时间  %.1fs" % _wave_manager.get_battle_elapsed()


func configure(wave_manager: WaveManager) -> void:
	_disconnect_wave_manager()
	_wave_manager = wave_manager
	_started_wave_indices.clear()
	_completed_wave_indices.clear()
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_state_changed)
		_wave_manager.wave_started.connect(_on_wave_started)
		_wave_manager.wave_completed.connect(_on_wave_completed)
	_refresh_state()


func set_level(level: LevelResource) -> void:
	clear_hover_preview()
	_entries = _model.build(level)
	_started_wave_indices.clear()
	_completed_wave_indices.clear()
	_rebuild_blocks()
	_refresh_state()
	call_deferred("_update_timeline_layout")


func set_preview_suppressed(suppressed: bool) -> void:
	_preview_suppressed = suppressed
	if suppressed:
		clear_hover_preview()


func clear_hover_preview() -> void:
	_hovered_wave_index = -1
	if info_panel != null:
		info_panel.visible = false
	paths_preview_cleared.emit()


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func get_wave_block_count() -> int:
	return _blocks.size()


func get_hovered_wave_index() -> int:
	return _hovered_wave_index


func get_current_line_y() -> float:
	return _resolve_current_line_y()


func get_wave_block_rect(wave_index: int) -> Rect2:
	var block := _blocks.get(wave_index) as Control
	return block.get_rect() if block != null else Rect2()


func preview_wave_for_test(wave_index: int) -> void:
	_on_wave_mouse_entered(wave_index)


func _rebuild_blocks() -> void:
	for child in block_layer.get_children():
		child.queue_free()
	_blocks.clear()
	for entry in _entries:
		var wave_index: int = int(entry["wave_index"])
		var block := Button.new()
		block.name = "Wave_%d" % (wave_index + 1)
		block.text = "%d\n%.1fs" % [int(entry["wave_number"]), float(entry["scheduled_time"])]
		## Native tooltips created a second hover window on top of the custom panel.
		block.tooltip_text = ""
		block.focus_mode = Control.FOCUS_NONE
		block.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		block.icon = entry["primary_icon"] if entry["primary_icon"] != null else fallback_enemy_icon
		block.expand_icon = true
		block.add_theme_stylebox_override("normal", _make_block_style())
		block.add_theme_stylebox_override("hover", _make_block_style(true))
		block.mouse_entered.connect(_on_wave_mouse_entered.bind(wave_index))
		block.mouse_exited.connect(_on_wave_mouse_exited.bind(wave_index))
		block_layer.add_child(block)
		_blocks[wave_index] = block
	_update_timeline_layout()


func _update_timeline_layout() -> void:
	if timeline_area == null:
		return
	var area_size := timeline_area.size
	if area_size.x <= 1.0 or area_size.y <= 1.0:
		return
	var line_y := _resolve_current_line_y()
	current_line_fallback.position = Vector2(0.0, line_y)
	current_line_fallback.size = Vector2(area_size.x, 3.0)
	current_line_art.position = current_line_fallback.position
	current_line_art.size = current_line_fallback.size
	var elapsed := _wave_manager.get_battle_elapsed() if _wave_manager != null else 0.0
	var pixels_per_second := maxf(1.0, line_y / maxf(0.5, visible_future_seconds))
	for entry in _entries:
		var wave_index: int = int(entry["wave_index"])
		var block := _blocks.get(wave_index) as Button
		if block == null:
			continue
		var scheduled_time: float = float(entry["scheduled_time"])
		var bottom := line_y - (scheduled_time - elapsed) * pixels_per_second
		var top := bottom - wave_block_height
		block.position = Vector2(10.0, top)
		block.size = Vector2(maxf(40.0, area_size.x - 20.0), wave_block_height)
		block.visible = bottom >= 0.0 and top <= area_size.y
		_refresh_block_visual(wave_index, block)


func _resolve_current_line_y() -> float:
	return maxf(0.0, timeline_area.size.y - current_line_inset)


func _refresh_state() -> void:
	if start_button == null:
		return
	var state := _wave_manager.get_state() if _wave_manager != null else WaveManager.State.NO_WAVES
	start_button.visible = state == WaveManager.State.READY and not _entries.is_empty()
	start_button.disabled = state != WaveManager.State.READY
	match state:
		WaveManager.State.READY:
			status_label.text = "等待开始第一波"
		WaveManager.State.ACTIVE:
			status_label.text = "当前时间  %.1fs" % _wave_manager.get_battle_elapsed()
		WaveManager.State.VICTORY:
			status_label.text = "全部波次完成"
		WaveManager.State.DEFEAT:
			status_label.text = "防守失败"
		WaveManager.State.CONFIG_ERROR:
			status_label.text = "波次配置错误"
		_:
			status_label.text = "未配置波次"
	_update_timeline_layout()


func _refresh_block_visual(wave_index: int, block: Button) -> void:
	if _completed_wave_indices.has(wave_index):
		block.modulate = completed_color
	elif _started_wave_indices.has(wave_index):
		block.modulate = active_color
	else:
		block.modulate = pending_color


func _on_start_pressed() -> void:
	if _wave_manager != null and not _wave_manager.start_battle():
		status_label.text = "无法开始第一波"


func _on_wave_mouse_entered(wave_index: int) -> void:
	if _preview_suppressed or wave_index < 0:
		return
	var entry := _find_entry(wave_index)
	if entry.is_empty():
		return
	_hovered_wave_index = wave_index
	info_title.text = String(entry["display_name"])
	info_details.text = String(entry["summary"])
	_rebuild_enemy_icons(entry["enemy_totals"])
	info_panel.visible = true
	var paths: Array = entry["paths"]
	paths_preview_requested.emit(paths)


func _find_entry(wave_index: int) -> Dictionary:
	for entry in _entries:
		if int(entry.get("wave_index", -1)) == wave_index:
			return entry
	return {}


func _on_wave_mouse_exited(wave_index: int) -> void:
	if _hovered_wave_index == wave_index:
		clear_hover_preview()


func _rebuild_enemy_icons(enemy_totals: Array) -> void:
	for child in info_icons.get_children():
		child.queue_free()
	for total in enemy_totals:
		var icon: Texture2D = total["icon"]
		if icon != null:
			var texture := TextureRect.new()
			texture.custom_minimum_size = Vector2(34.0, 34.0)
			texture.texture = icon
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			info_icons.add_child(texture)
		else:
			var fallback := Label.new()
			fallback.custom_minimum_size = Vector2(34.0, 34.0)
			var name: String = String(total["name"])
			fallback.text = name.left(1) if not name.is_empty() else "?"
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			info_icons.add_child(fallback)


func _make_block_style(hovered: bool = false) -> StyleBox:
	if wave_block_texture != null:
		var textured := StyleBoxTexture.new()
		textured.texture = wave_block_texture
		return textured
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.18, 0.98) if not hovered else Color(0.12, 0.24, 0.30, 1.0)
	style.border_color = Color(0.46, 0.76, 0.86, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	return style


func _apply_optional_art() -> void:
	start_button.icon = start_button_icon
	current_line_art.texture = current_line_texture
	current_line_art.visible = current_line_texture != null
	current_line_fallback.visible = current_line_texture == null
	current_line_fallback.color = current_line_color


func _on_state_changed(_state: WaveManager.State, _current: int, _total: int, _active: int) -> void:
	_refresh_state()


func _on_wave_started(wave_number: int, _wave: WaveDefinition) -> void:
	_started_wave_indices[wave_number - 1] = true
	_update_timeline_layout()


func _on_wave_completed(wave_number: int) -> void:
	_completed_wave_indices[wave_number - 1] = true
	_update_timeline_layout()


func _disconnect_wave_manager() -> void:
	if _wave_manager == null:
		return
	if _wave_manager.state_changed.is_connected(_on_state_changed):
		_wave_manager.state_changed.disconnect(_on_state_changed)
	if _wave_manager.wave_started.is_connected(_on_wave_started):
		_wave_manager.wave_started.disconnect(_on_wave_started)
	if _wave_manager.wave_completed.is_connected(_on_wave_completed):
		_wave_manager.wave_completed.disconnect(_on_wave_completed)
