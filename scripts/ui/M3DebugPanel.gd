## Runtime M3 greybox controls; the production HUD consumes the same managers later.
class_name M3DebugPanel
extends Control

enum InteractionMode {
	SELECT,
	BUILD_ARROW,
	BUILD_LASER,
	BUILD_BARRIER,
	BUILD_EDGE_BARRIER,
	BUILD_COPY_MIRROR,
	SPAWN_TARGET,
}

@export_group("Feature")
@export var feature_enabled: bool = true

signal mode_changed(mode: InteractionMode)

var _building_manager: BuildingManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _mirror_manager: MirrorManager
var _mode: InteractionMode = InteractionMode.SELECT
var _resource_label: Label
var _mode_label: Label
var _status_label: Label
var _upgrade_button: Button
var _mode_buttons: Array[Button] = []

func _ready() -> void:
	visible = feature_enabled
	_build_interface()

func configure(
	building_manager: BuildingManager,
	resource_manager: ResourceManager,
	combat_manager: CombatManager,
	mirror_manager: MirrorManager = null
) -> void:
	_disconnect_managers()
	_building_manager = building_manager
	_resource_manager = resource_manager
	_combat_manager = combat_manager
	_mirror_manager = mirror_manager
	if _resource_manager != null:
		_resource_manager.resource_changed.connect(_on_resource_changed)
		_resource_manager.limits_changed.connect(_on_limits_changed)
		_resource_manager.income_rates_changed.connect(_on_income_rates_changed)
	if _building_manager != null:
		_building_manager.placement_failed.connect(_on_placement_failed)
		_building_manager.building_selected.connect(_on_building_selected)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		_building_manager.upgrade_failed.connect(_on_upgrade_failed)
		_building_manager.preview_updated.connect(_on_preview_updated)
		_building_manager.preview_cleared.connect(_on_preview_cleared)
	if _combat_manager != null:
		_combat_manager.target_registered.connect(_on_target_count_changed)
		_combat_manager.target_removed.connect(_on_target_count_changed)
	if _mirror_manager != null:
		_mirror_manager.placement_failed.connect(_on_mirror_placement_failed)
		_mirror_manager.mirror_selected.connect(_on_mirror_selected)
		_mirror_manager.preview_updated.connect(_on_mirror_preview_updated)
		_mirror_manager.preview_cleared.connect(_on_mirror_preview_cleared)
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
	if _mode == InteractionMode.BUILD_BARRIER:
		return _building_manager.get_definition(BuildingDefinition.Kind.BARRIER)
	if _mode == InteractionMode.BUILD_EDGE_BARRIER:
		return _building_manager.get_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	return null

func is_copy_mirror_mode() -> bool:
	return _mode == InteractionMode.BUILD_COPY_MIRROR

func select_mode(value: InteractionMode) -> void:
	_mode = value
	for index in range(_mode_buttons.size()):
		_mode_buttons[index].button_pressed = index == int(_mode)
	_mode_label.text = "模式：%s" % _get_mode_name()
	_status_label.text = ""
	if _building_manager != null and not _is_build_mode(value):
		_building_manager.clear_preview()
	if _mirror_manager != null and value != InteractionMode.BUILD_COPY_MIRROR:
		_mirror_manager.clear_preview()
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
	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	var title := Label.new()
	title.text = "M3 建筑与战斗"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_upgrade_button = Button.new()
	_upgrade_button.text = "升级"
	_upgrade_button.tooltip_text = "升级当前选中建筑"
	_upgrade_button.disabled = true
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	title_row.add_child(_upgrade_button)
	_resource_label = Label.new()
	content.add_child(_resource_label)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 0)
	content.add_child(modes)
	var group := ButtonGroup.new()
	_add_mode_button(modes, group, "选择", InteractionMode.SELECT)
	_add_mode_button(modes, group, "箭塔", InteractionMode.BUILD_ARROW)
	_add_mode_button(modes, group, "激光塔", InteractionMode.BUILD_LASER)
	_add_mode_button(modes, group, "屏障", InteractionMode.BUILD_BARRIER)
	_add_mode_button(modes, group, "边障", InteractionMode.BUILD_EDGE_BARRIER)
	_add_mode_button(modes, group, "复制镜", InteractionMode.BUILD_COPY_MIRROR)
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
	button.custom_minimum_size = Vector2(68.0, 32.0)
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
	_resource_label.text = "资源 %d | +%.1f/s | 建筑 %d/%d | 镜子 %d/%d | 靶标 %d" % [
		floori(_resource_manager.main_resource),
		_resource_manager.get_total_resource_per_second(),
		_resource_manager.get_building_count(),
		_resource_manager.building_cap,
		_resource_manager.get_mirror_count(),
		_resource_manager.mirror_cap,
		target_count,
	]

func _get_mode_name() -> String:
	match _mode:
		InteractionMode.BUILD_ARROW:
			return "放置箭塔"
		InteractionMode.BUILD_LASER:
			return "放置激光塔"
		InteractionMode.BUILD_BARRIER:
			return "放置屏障（仅路径格）"
		InteractionMode.BUILD_EDGE_BARRIER:
			return "放置边屏障（任意内部共享边，默认双向）"
		InteractionMode.BUILD_COPY_MIRROR:
			return "放置复制镜（R 翻转生效侧）"
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
		if _resource_manager.income_rates_changed.is_connected(_on_income_rates_changed):
			_resource_manager.income_rates_changed.disconnect(_on_income_rates_changed)
	if _building_manager != null:
		if _building_manager.placement_failed.is_connected(_on_placement_failed):
			_building_manager.placement_failed.disconnect(_on_placement_failed)
		if _building_manager.building_selected.is_connected(_on_building_selected):
			_building_manager.building_selected.disconnect(_on_building_selected)
		if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
			_building_manager.building_upgraded.disconnect(_on_building_upgraded)
		if _building_manager.upgrade_failed.is_connected(_on_upgrade_failed):
			_building_manager.upgrade_failed.disconnect(_on_upgrade_failed)
		if _building_manager.preview_updated.is_connected(_on_preview_updated):
			_building_manager.preview_updated.disconnect(_on_preview_updated)
		if _building_manager.preview_cleared.is_connected(_on_preview_cleared):
			_building_manager.preview_cleared.disconnect(_on_preview_cleared)
	if _combat_manager != null:
		if _combat_manager.target_registered.is_connected(_on_target_count_changed):
			_combat_manager.target_registered.disconnect(_on_target_count_changed)
		if _combat_manager.target_removed.is_connected(_on_target_count_changed):
			_combat_manager.target_removed.disconnect(_on_target_count_changed)
	if _mirror_manager != null:
		if _mirror_manager.placement_failed.is_connected(_on_mirror_placement_failed):
			_mirror_manager.placement_failed.disconnect(_on_mirror_placement_failed)
		if _mirror_manager.mirror_selected.is_connected(_on_mirror_selected):
			_mirror_manager.mirror_selected.disconnect(_on_mirror_selected)
		if _mirror_manager.preview_updated.is_connected(_on_mirror_preview_updated):
			_mirror_manager.preview_updated.disconnect(_on_mirror_preview_updated)
		if _mirror_manager.preview_cleared.is_connected(_on_mirror_preview_cleared):
			_mirror_manager.preview_cleared.disconnect(_on_mirror_preview_cleared)

func _is_build_mode(value: InteractionMode) -> bool:
	return value == InteractionMode.BUILD_ARROW or value == InteractionMode.BUILD_LASER or value == InteractionMode.BUILD_BARRIER or value == InteractionMode.BUILD_EDGE_BARRIER or value == InteractionMode.BUILD_COPY_MIRROR

func _on_resource_changed(_current: float, _delta: float, _reason: String) -> void:
	_refresh_summary()

func _on_limits_changed(
	_building_count: int,
	_building_limit: int,
	_mirror_count: int,
	_mirror_limit: int
) -> void:
	_refresh_summary()

func _on_income_rates_changed(_base_per_second: float, _buildings_per_second: float) -> void:
	_refresh_summary()

func _on_placement_failed(_cell: Vector3i, reason: String) -> void:
	_status_label.text = reason
	_refresh_summary()

func _on_building_selected(building: Building) -> void:
	if building == null:
		_status_label.text = "未选中建筑"
		_upgrade_button.disabled = true
	else:
		if building.is_edge_path_blocker():
			var edge_connector := "↔" if building.is_bidirectional_edge_blocker() else "→"
			_status_label.text = "已选：%s L%d/%d，%s %s %s，耐久 %d/%d" % [
				building.definition.display_name,
				building.level,
				building.get_max_level(),
				str(building.cell),
				edge_connector,
				str(building.edge_to_cell),
				ceili(building.current_durability),
				ceili(building.maximum_durability),
			]
		elif building.is_path_blocker():
			_status_label.text = "已选：%s L%d/%d，耐久 %d/%d" % [
				building.definition.display_name,
				building.level,
				building.get_max_level(),
				ceili(building.current_durability),
				ceili(building.maximum_durability),
			]
		else:
			_status_label.text = "已选：%s L%d/%d，朝向 %d/%d" % [
				building.definition.display_name,
				building.level,
				building.get_max_level(),
				building.facing_index + 1,
				building.get_facing_slot_count(),
			]
		_upgrade_button.disabled = not building.can_upgrade()
	_refresh_summary()

func _on_upgrade_pressed() -> void:
	if _building_manager != null:
		_building_manager.upgrade_selected()

func _on_building_upgraded(building: Building, _previous_level: int, _new_level: int) -> void:
	_on_building_selected(building)

func _on_upgrade_failed(_building: Building, reason: String) -> void:
	_status_label.text = reason

func _on_preview_updated(building: Building) -> void:
	if building.is_edge_placement():
		var edge_connector := "↔" if building.is_bidirectional_edge_blocker() else "→"
		_status_label.text = "预览：%s，%s %s %s（贴边固定）" % [
			building.definition.display_name,
			str(building.cell),
			edge_connector,
			str(building.edge_to_cell),
		]
		return
	_status_label.text = "预览：%s L1，朝向 %d/%d" % [
		building.definition.display_name,
		building.facing_index + 1,
		building.get_facing_slot_count(),
	]

func _on_preview_cleared() -> void:
	if _is_build_mode(_mode):
		_status_label.text = "当前格不可放置，查看左侧地块或占位信息"

func _on_target_count_changed(_target: CombatTarget) -> void:
	_refresh_summary()

func _on_mirror_placement_failed(_cell: Vector3i, reason: String) -> void:
	_status_label.text = reason
	_refresh_summary()

func _on_mirror_selected(mirror: CopyMirror) -> void:
	if mirror == null:
		return
	_status_label.text = "已选：复制镜 | 生效侧 %s | R 翻面 | Delete 删除" % str(mirror.get_active_cell())
	_upgrade_button.disabled = true
	_refresh_summary()

func _on_mirror_preview_updated(info: Dictionary) -> void:
	if bool(info.get("has_source", false)):
		_status_label.text = "镜像预览：%s → %s | %s" % [
			str(info.get("source_cell", Vector3i.ZERO)),
			str(info.get("target_cell", Vector3i.ZERO)),
			"、".join(info.get("types", [])),
		]
	else:
		_status_label.text = str(info.get("warning", "未找到复制源"))

func _on_mirror_preview_cleared() -> void:
	if _mode == InteractionMode.BUILD_COPY_MIRROR:
		_status_label.text = "选择两个有效地块之间的未占用边"
