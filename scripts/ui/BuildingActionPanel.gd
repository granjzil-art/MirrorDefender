## Screen-projected contextual actions for the currently selected building.
class_name BuildingActionPanel
extends Control

const PANEL_SIZE := Vector2(210.0, 40.0)
const BUTTON_SIZE := Vector2(66.0, 32.0)

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Projection")
@export var screen_offset: Vector2 = Vector2(0.0, -14.0)

var _building_manager: BuildingManager
var _camera: Camera3D
var _selected_building: Building
var _delete_button: Button
var _upgrade_button: Button
var _rotate_button: Button

func _ready() -> void:
	size = PANEL_SIZE
	visible = false
	_build_interface()

func _process(_delta: float) -> void:
	_update_projection()

func configure(building_manager: BuildingManager, camera: Camera3D) -> void:
	_disconnect_manager()
	_building_manager = building_manager
	_camera = camera
	if _building_manager != null:
		_building_manager.building_selected.connect(_on_building_selected)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		_building_manager.building_removed.connect(_on_building_removed)
	_refresh_selected_building()

func _build_interface() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 4)
	panel.add_child(actions)
	_delete_button = _add_action_button(actions, "删除", "删除建筑并返还当前等级配置的资源")
	_upgrade_button = _add_action_button(actions, "升级", "消耗下一等级配置的资源")
	_rotate_button = _add_action_button(actions, "旋转", "顺时针旋转一个可用朝向")
	_delete_button.pressed.connect(_on_delete_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_rotate_button.pressed.connect(_on_rotate_pressed)

func _add_action_button(container: HBoxContainer, label_text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.tooltip_text = tooltip
	button.custom_minimum_size = BUTTON_SIZE
	container.add_child(button)
	return button

func _refresh_selected_building() -> void:
	_selected_building = _building_manager.get_selected_building() if _building_manager != null else null
	visible = feature_enabled and _selected_building != null
	if _upgrade_button != null:
		_upgrade_button.disabled = _selected_building == null or not _selected_building.can_upgrade()
	if _delete_button != null:
		_delete_button.disabled = _selected_building == null
	if _rotate_button != null:
		_rotate_button.disabled = _selected_building == null

func _update_projection() -> void:
	if not feature_enabled or _selected_building == null or not is_instance_valid(_selected_building):
		visible = false
		return
	if _camera == null or not is_instance_valid(_camera):
		visible = false
		return
	var anchor := _selected_building.get_action_anchor()
	if _camera.is_position_behind(anchor):
		visible = false
		return
	var screen_position := _camera.unproject_position(anchor)
	var viewport_size := get_viewport_rect().size
	var maximum_x := maxf(0.0, viewport_size.x - size.x)
	var maximum_y := maxf(0.0, viewport_size.y - size.y)
	position = Vector2(
		clampf(screen_position.x - size.x * 0.5 + screen_offset.x, 0.0, maximum_x),
		clampf(screen_position.y - size.y + screen_offset.y, 0.0, maximum_y)
	)
	visible = true

func _disconnect_manager() -> void:
	if _building_manager == null:
		return
	if _building_manager.building_selected.is_connected(_on_building_selected):
		_building_manager.building_selected.disconnect(_on_building_selected)
	if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
		_building_manager.building_upgraded.disconnect(_on_building_upgraded)
	if _building_manager.building_removed.is_connected(_on_building_removed):
		_building_manager.building_removed.disconnect(_on_building_removed)

func _on_delete_pressed() -> void:
	if _building_manager != null:
		_building_manager.remove_selected_building()

func _on_upgrade_pressed() -> void:
	if _building_manager != null:
		_building_manager.upgrade_selected()

func _on_rotate_pressed() -> void:
	if _building_manager != null:
		_building_manager.rotate_selected()

func _on_building_selected(_building: Building) -> void:
	_refresh_selected_building()

func _on_building_upgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	_refresh_selected_building()

func _on_building_removed(_building: Building) -> void:
	_refresh_selected_building()
