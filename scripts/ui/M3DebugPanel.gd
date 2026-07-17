## Runtime M3 greybox controls; the production HUD consumes the same managers later.
class_name M3DebugPanel
extends Control

enum InteractionMode {
	SELECT,
	BUILD_ARROW,
	BUILD_LASER,
	SPAWN_TARGET,
}

@export_group("Feature")
@export var feature_enabled: bool = true

signal mode_changed(mode: InteractionMode)

var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _mode: InteractionMode = InteractionMode.SELECT
var _resource_label: Label
var _mode_label: Label
var _status_label: Label
var _mode_buttons: Array[Button] = []

func _ready() -> void:
	visible = feature_enabled
	_build_interface()

func configure(
	building_manager: BuildingManager,
	resource_manager: ResourceManager,
	combat_manager: CombatManager
) -> void:
	_disconnect_managers()
	_building_manager = building_manager
	_resource_manager = resource_manager
	_combat_manager = combat_manager
	if _resource_manager != null:
		_resource_manager.resource_changed.connect(_on_resource_changed)
		_resource_manager.limits_changed.connect(_on_limits_changed)
	if _building_manager != null:
		_building_manager.placement_failed.connect(_on_placement_failed)
		_building_manager.building_selected.connect(_on_building_selected)
	if _combat_manager != null:
		_combat_manager.target_registered.connect(_on_target_count_changed)
		_combat_manager.target_removed.connect(_on_target_count_changed)
	_refresh_summary()
	select_mode(InteractionMode.SELECT)

func get_mode() -> InteractionMode:
	return _mode

func get_selected_definition() -> BuildingDefinition:
	if _building_manager == null:
		return null
	if _mode == InteractionMode.BUILD_LASER:
		return _building_manager.get_definition(BuildingDefinition.Kind.LASER_TOWER)
	if _mode == InteractionMode.BUILD_ARROW:
		return _building_manager.get_definition(BuildingDefinition.Kind.ARROW_TOWER)
	return null

func select_mode(value: InteractionMode) -> void:
	_mode = value
	for index in range(_mode_buttons.size()):
		_mode_buttons[index].button_pressed = index == int(_mode)
	_mode_label.text = "模式：%s" % _get_mode_name()
	_status_label.text = ""
	mode_changed.emit(_mode)

func cancel_to_select() -> void:
	select_mode(InteractionMode.SELECT)

func report_target_spawned() -> void:
	_status_label.text = "已放置战斗靶标"
	_refresh_summary()

func report_no_cell() -> void:
	_status_label.text = "未命中地图格"

func _build_interface() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	panel.add_child(content)
	var title := Label.new()
	title.text = "M3 建筑与战斗"
	title.add_theme_font_size_override("font_size", 16)
	content.add_child(title)
	_resource_label = Label.new()
	content.add_child(_resource_label)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 0)
	content.add_child(modes)
	var group := ButtonGroup.new()
	_add_mode_button(modes, group, "选择", InteractionMode.SELECT)
	_add_mode_button(modes, group, "箭塔", InteractionMode.BUILD_ARROW)
	_add_mode_button(modes, group, "激光塔", InteractionMode.BUILD_LASER)
	_add_mode_button(modes, group, "靶标", InteractionMode.SPAWN_TARGET)
	_mode_label = Label.new()
	content.add_child(_mode_label)
	_status_label = Label.new()
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size.y = 24.0
	content.add_child(_status_label)

func _add_mode_button(
	container: HBoxContainer,
	group: ButtonGroup,
	label_text: String,
	mode: InteractionMode
) -> void:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(88.0, 32.0)
	button.pressed.connect(select_mode.bind(mode))
	container.add_child(button)
	_mode_buttons.append(button)

func _refresh_summary() -> void:
	if _resource_label == null:
		return
	if _resource_manager == null:
		_resource_label.text = "经济未连接"
		return
	var target_count := _combat_manager.get_targets().size() if _combat_manager != null else 0
	_resource_label.text = "资源 %d  |  建筑 %d/%d  |  靶标 %d" % [
		floori(_resource_manager.main_resource),
		_resource_manager.get_building_count(),
		_resource_manager.building_cap,
		target_count,
	]

func _get_mode_name() -> String:
	match _mode:
		InteractionMode.BUILD_ARROW:
			return "放置箭塔"
		InteractionMode.BUILD_LASER:
			return "放置激光塔"
		InteractionMode.SPAWN_TARGET:
			return "放置靶标"
		_:
			return "选择建筑"

func _disconnect_managers() -> void:
	if _resource_manager != null:
		if _resource_manager.resource_changed.is_connected(_on_resource_changed):
			_resource_manager.resource_changed.disconnect(_on_resource_changed)
		if _resource_manager.limits_changed.is_connected(_on_limits_changed):
			_resource_manager.limits_changed.disconnect(_on_limits_changed)
	if _building_manager != null:
		if _building_manager.placement_failed.is_connected(_on_placement_failed):
			_building_manager.placement_failed.disconnect(_on_placement_failed)
		if _building_manager.building_selected.is_connected(_on_building_selected):
			_building_manager.building_selected.disconnect(_on_building_selected)
	if _combat_manager != null:
		if _combat_manager.target_registered.is_connected(_on_target_count_changed):
			_combat_manager.target_registered.disconnect(_on_target_count_changed)
		if _combat_manager.target_removed.is_connected(_on_target_count_changed):
			_combat_manager.target_removed.disconnect(_on_target_count_changed)

func _on_resource_changed(_current: float, _delta: float, _reason: String) -> void:
	_refresh_summary()

func _on_limits_changed(
	_building_count: int,
	_building_limit: int,
	_mirror_count: int,
	_mirror_limit: int
) -> void:
	_refresh_summary()

func _on_placement_failed(_cell: Vector3i, reason: String) -> void:
	_status_label.text = reason
	_refresh_summary()

func _on_building_selected(building: Building) -> void:
	if building == null:
		_status_label.text = "未选中建筑"
	else:
		_status_label.text = "已选：%s，朝向 %d/%d" % [
			building.definition.display_name,
			building.facing_index + 1,
			building.get_facing_slot_count(),
		]
	_refresh_summary()

func _on_target_count_changed(_target: CombatTarget) -> void:
	_refresh_summary()
