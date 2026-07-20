## Screen-projected actions for the selected copy mirror.
class_name MirrorActionPanel
extends Control

const PANEL_SIZE := Vector2(148.0, 40.0)
const BUTTON_SIZE := Vector2(68.0, 32.0)

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Projection")
@export var screen_offset: Vector2 = Vector2(0.0, -14.0)

var _mirror_manager: MirrorManager
var _camera: Camera3D
var _selected_mirror: CopyMirror

func _ready() -> void:
	size = PANEL_SIZE
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 4)
	panel.add_child(actions)
	var delete_button := _add_button(actions, "删除", "删除复制镜并返还配置资源")
	var flip_button := _add_button(actions, "翻面", "切换复制镜生效侧")
	delete_button.pressed.connect(_on_delete_pressed)
	flip_button.pressed.connect(_on_flip_pressed)

func configure(mirror_manager: MirrorManager, camera: Camera3D) -> void:
	_disconnect_manager()
	_mirror_manager = mirror_manager
	_camera = camera
	if _mirror_manager != null:
		_mirror_manager.mirror_selected.connect(_on_mirror_selected)
		_mirror_manager.mirror_removed.connect(_on_mirror_removed)
		_mirror_manager.mirror_changed.connect(_on_mirror_changed)
	_refresh_selection()

func _process(_delta: float) -> void:
	if not feature_enabled or _selected_mirror == null or not is_instance_valid(_selected_mirror):
		visible = false
		return
	if _camera == null or not is_instance_valid(_camera):
		visible = false
		return
	var anchor := _selected_mirror.get_action_anchor()
	if _camera.is_position_behind(anchor):
		visible = false
		return
	var screen_position := _camera.unproject_position(anchor)
	var viewport_size := get_viewport_rect().size
	position = Vector2(
		clampf(screen_position.x - size.x * 0.5 + screen_offset.x, 0.0, maxf(0.0, viewport_size.x - size.x)),
		clampf(screen_position.y - size.y + screen_offset.y, 0.0, maxf(0.0, viewport_size.y - size.y))
	)
	visible = true

func _add_button(container: HBoxContainer, label_text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = tooltip
	button.custom_minimum_size = BUTTON_SIZE
	container.add_child(button)
	return button

func _refresh_selection() -> void:
	_selected_mirror = _mirror_manager.get_selected_mirror() if _mirror_manager != null else null
	visible = feature_enabled and _selected_mirror != null

func _disconnect_manager() -> void:
	if _mirror_manager == null:
		return
	if _mirror_manager.mirror_selected.is_connected(_on_mirror_selected):
		_mirror_manager.mirror_selected.disconnect(_on_mirror_selected)
	if _mirror_manager.mirror_removed.is_connected(_on_mirror_removed):
		_mirror_manager.mirror_removed.disconnect(_on_mirror_removed)
	if _mirror_manager.mirror_changed.is_connected(_on_mirror_changed):
		_mirror_manager.mirror_changed.disconnect(_on_mirror_changed)

func _on_delete_pressed() -> void:
	if _mirror_manager != null:
		_mirror_manager.remove_selected_mirror()

func _on_flip_pressed() -> void:
	if _mirror_manager != null:
		_mirror_manager.flip_selected()

func _on_mirror_selected(_mirror: CopyMirror) -> void:
	_refresh_selection()

func _on_mirror_removed(_mirror: CopyMirror) -> void:
	_refresh_selection()

func _on_mirror_changed(_mirror: CopyMirror) -> void:
	_refresh_selection()
