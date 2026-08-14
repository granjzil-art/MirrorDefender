## Native, non-pausing runtime combat-data editor for development runs.
class_name RuntimeCombatDataEditorWindow
extends Window

const DEFAULT_SIZE := Vector2i(540, 780)

signal debug_tools_toggle_requested

var _session: RuntimeCombatDataEditSession
var _test_spawner: RuntimeTestEnemySpawner
var _status_label: Label
var _save_button: Button
var _discard_button: Button
var _building_select: OptionButton
var _level_select: OptionButton
var _building_form: VBoxContainer
var _enemy_select: OptionButton
var _enemy_form: VBoxContainer
var _test_enemy_select: OptionButton
var _test_path_select: OptionButton
var _test_count: SpinBox
var _test_interval: SpinBox
var _test_status: Label
var _close_dialog: ConfirmationDialog
var _message_dialog: AcceptDialog
var _refreshing: bool = false
var _test_status_elapsed: float = 0.0
var _feature_enabled: bool = true


func _ready() -> void:
	title = "运行时战斗数据编辑器"
	size = DEFAULT_SIZE
	min_size = Vector2i(460, 620)
	force_native = true
	transient = false
	exclusive = false
	always_on_top = false
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_requested.connect(_on_close_requested)
	_build_interface()


func configure(
	session: RuntimeCombatDataEditSession,
	test_spawner: RuntimeTestEnemySpawner
) -> void:
	_session = session
	_test_spawner = test_spawner
	if _session != null:
		_session.dirty_changed.connect(_on_dirty_changed)
		_session.catalogs_changed.connect(_refresh_catalogs)
		_session.session_saved.connect(_on_session_committed)
		_session.session_discarded.connect(_on_session_discarded)
	if _test_spawner != null:
		_test_spawner.state_changed.connect(_on_test_spawner_state_changed)
	_refresh_catalogs()
	_on_dirty_changed(_session != null and _session.is_dirty())


func open_editor() -> void:
	if not _feature_enabled:
		return
	if _session == null or not _session.is_active():
		_show_message("战斗数据编辑会话未就绪")
		return
	_refresh_catalogs()
	_position_beside_game()
	popup()
	grab_focus()


func toggle_editor() -> void:
	if not _feature_enabled:
		return
	if visible:
		_on_close_requested()
	else:
		open_editor()


func _process(delta: float) -> void:
	if not visible or _test_spawner == null:
		return
	_test_status_elapsed += maxf(0.0, delta)
	if _test_status_elapsed < 0.25:
		return
	_test_status_elapsed = 0.0
	_refresh_test_counts()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if event.is_action_pressed("toggle_debug_tools"):
		debug_tools_toggle_requested.emit()
		set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		_save_changes()
		set_input_as_handled()


func set_feature_enabled(enabled: bool) -> void:
	_feature_enabled = enabled
	if not _feature_enabled:
		_close_dialog.hide()
		_message_dialog.hide()
		hide()


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = "工作副本与 .tres 一致"
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(_status_label)
	_save_button = Button.new()
	_save_button.text = "永久保存"
	_save_button.tooltip_text = "写回唯一 .tres 数据源（Ctrl+S）"
	_save_button.pressed.connect(_save_changes)
	toolbar.add_child(_save_button)
	_discard_button = Button.new()
	_discard_button.text = "放弃修改"
	_discard_button.pressed.connect(_discard_changes)
	toolbar.add_child(_discard_button)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_building_page())
	tabs.add_child(_build_enemy_page())
	tabs.add_child(_build_test_page())

	_close_dialog = ConfirmationDialog.new()
	_close_dialog.title = "存在未保存的战斗数据"
	_close_dialog.dialog_text = "永久保存修改，还是放弃并重新读取 .tres？"
	_close_dialog.ok_button_text = "永久保存"
	_close_dialog.cancel_button_text = "取消"
	_close_dialog.add_button("放弃修改", false, "discard")
	_close_dialog.confirmed.connect(_on_close_save_confirmed)
	_close_dialog.custom_action.connect(_on_close_custom_action)
	add_child(_close_dialog)
	_message_dialog = AcceptDialog.new()
	_message_dialog.title = "运行时战斗数据编辑器"
	add_child(_message_dialog)


func _build_building_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "建筑参数"
	page.add_theme_constant_override("separation", 8)
	var selectors := HBoxContainer.new()
	page.add_child(selectors)
	var type_label := Label.new()
	type_label.text = "建筑"
	selectors.add_child(type_label)
	_building_select = OptionButton.new()
	_building_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_select.item_selected.connect(_on_building_selected)
	selectors.add_child(_building_select)
	var level_label := Label.new()
	level_label.text = "等级"
	selectors.add_child(level_label)
	_level_select = OptionButton.new()
	_level_select.custom_minimum_size.x = 90
	_level_select.item_selected.connect(_on_building_level_selected)
	selectors.add_child(_level_select)
	var hint := Label.new()
	hint.text = "修改后会在相同位置和朝向重建该类型、该等级的现有建筑。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.72, 0.82, 0.9)
	page.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_building_form = VBoxContainer.new()
	_building_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_form.add_theme_constant_override("separation", 5)
	scroll.add_child(_building_form)
	return page


func _build_enemy_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "敌人参数"
	page.add_theme_constant_override("separation", 8)
	var selectors := HBoxContainer.new()
	page.add_child(selectors)
	var label := Label.new()
	label.text = "敌人类型"
	selectors.add_child(label)
	_enemy_select = OptionButton.new()
	_enemy_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_select.item_selected.connect(_on_enemy_selected)
	selectors.add_child(_enemy_select)
	var hint := Label.new()
	hint.text = "已生成敌人保持出生数据；后续波次和测试敌人使用当前工作副本。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.72, 0.82, 0.9)
	page.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_enemy_form = VBoxContainer.new()
	_enemy_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_form.add_theme_constant_override("separation", 5)
	scroll.add_child(_enemy_form)
	return page


func _build_test_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "测试敌人"
	page.add_theme_constant_override("separation", 10)
	_test_enemy_select = _add_labeled_option(page, "敌人类型")
	_test_path_select = _add_labeled_option(page, "路径")
	_test_count = _add_labeled_spin(page, "数量", 1.0, 200.0, 1.0, 1.0)
	_test_interval = _add_labeled_spin(page, "生成间隔（秒）", 0.01, 60.0, 0.05, 1.0)
	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	var start_button := Button.new()
	start_button.text = "开始生成"
	start_button.pressed.connect(_start_test_batch)
	buttons.add_child(start_button)
	var stop_button := Button.new()
	stop_button.text = "停止后续生成"
	stop_button.pressed.connect(_stop_test_batch)
	buttons.add_child(stop_button)
	var clear_button := Button.new()
	clear_button.text = "清理测试敌人"
	clear_button.pressed.connect(_clear_test_enemies)
	buttons.add_child(clear_button)
	_test_status = Label.new()
	_test_status.text = "测试敌人不参与波次调度，但正常结算奖励和基地伤害。"
	_test_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_test_status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(spacer)
	return page


func _add_labeled_option(parent: VBoxContainer, text: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _add_labeled_spin(
	parent: VBoxContainer,
	text: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float
) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _refresh_catalogs() -> void:
	if _session == null or _building_select == null:
		return
	_refreshing = true
	var selected_kind := _selected_metadata_int(_building_select, -1)
	var selected_enemy_path := _selected_metadata_string(_enemy_select)
	var selected_test_enemy_path := _selected_metadata_string(_test_enemy_select)
	var selected_path_name := _selected_metadata_path_name(_test_path_select)
	_building_select.clear()
	for definition in _session.get_building_definitions():
		_building_select.add_item(definition.display_name)
		_building_select.set_item_metadata(_building_select.item_count - 1, definition.kind)
	_select_metadata(_building_select, selected_kind)
	_refresh_level_selector()
	_enemy_select.clear()
	_test_enemy_select.clear()
	for enemy in _session.get_enemy_definitions():
		var path := enemy.resource_path
		_enemy_select.add_item(enemy.display_name)
		_enemy_select.set_item_metadata(_enemy_select.item_count - 1, path)
		_test_enemy_select.add_item(enemy.display_name)
		_test_enemy_select.set_item_metadata(_test_enemy_select.item_count - 1, path)
	_select_metadata(_enemy_select, selected_enemy_path)
	_select_metadata(_test_enemy_select, selected_test_enemy_path)
	_test_path_select.clear()
	for path in _session.get_current_paths():
		_test_path_select.add_item(path.display_name)
		_test_path_select.set_item_metadata(_test_path_select.item_count - 1, path)
	_select_path_name(_test_path_select, selected_path_name)
	_refreshing = false
	_rebuild_building_form()
	_rebuild_enemy_form()


func _refresh_level_selector() -> void:
	var previous := _selected_metadata_int(_level_select, 1)
	_level_select.clear()
	var definition := _get_selected_building_definition()
	if definition == null:
		return
	for building_level in range(1, definition.get_max_level() + 1):
		_level_select.add_item("%d 级" % building_level)
		_level_select.set_item_metadata(_level_select.item_count - 1, building_level)
	_select_metadata(_level_select, previous)


func _rebuild_building_form() -> void:
	_clear_children(_building_form)
	var definition := _get_selected_building_definition()
	var building_level := _selected_metadata_int(_level_select, 1)
	if definition == null:
		return
	var level_data := definition.get_level_stats(building_level)
	if level_data == null:
		return
	for field in _building_fields(definition.kind):
		_add_property_row(_building_form, level_data, field, true)


func _rebuild_enemy_form() -> void:
	_clear_children(_enemy_form)
	var definition := _get_selected_enemy_definition(_enemy_select)
	if definition == null:
		return
	for field in _enemy_fields():
		_add_property_row(_enemy_form, definition, field, false)


func _add_property_row(
	parent: VBoxContainer,
	resource: Resource,
	field: Dictionary,
	is_building: bool
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = String(field.get("label", field.get("property", "")))
	label.custom_minimum_size.x = 190
	label.tooltip_text = String(field.get("tooltip", ""))
	row.add_child(label)
	var property := StringName(field.get("property", ""))
	var type := String(field.get("type", "float"))
	if type == "bool":
		var check := CheckBox.new()
		check.button_pressed = bool(resource.get(property))
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_building:
			check.toggled.connect(_on_building_bool_changed.bind(property))
		else:
			check.toggled.connect(_on_enemy_bool_changed.bind(property))
		row.add_child(check)
	elif type == "enum":
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item in field.get("options", []):
			option.add_item(String(item))
		option.select(clampi(int(resource.get(property)), 0, maxi(0, option.item_count - 1)))
		if is_building:
			option.item_selected.connect(_on_building_enum_changed.bind(property))
		else:
			option.item_selected.connect(_on_enemy_enum_changed.bind(property))
		row.add_child(option)
	elif type == "color":
		var picker := ColorPickerButton.new()
		picker.color = Color(resource.get(property))
		picker.edit_alpha = true
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_building:
			picker.color_changed.connect(_on_building_color_changed.bind(property))
		else:
			picker.color_changed.connect(_on_enemy_color_changed.bind(property))
		row.add_child(picker)
	else:
		var spin := SpinBox.new()
		spin.min_value = float(field.get("min", 0.0))
		spin.max_value = float(field.get("max", 100000.0))
		spin.step = float(field.get("step", 0.1))
		spin.allow_greater = bool(field.get("allow_greater", false))
		spin.value = float(resource.get(property))
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var integer := type == "int"
		if is_building:
			spin.value_changed.connect(_on_building_number_changed.bind(property, integer))
		else:
			spin.value_changed.connect(_on_enemy_number_changed.bind(property, integer))
		row.add_child(spin)


func _building_fields(kind: int) -> Array[Dictionary]:
	var airborne := _bool_field("affects_airborne", "可攻击空中敌人")
	if kind in [BuildingDefinition.Kind.BARRIER, BuildingDefinition.Kind.EDGE_BARRIER]:
		return [
			airborne,
			_float_field("max_durability", "最大耐久", 1.0, 1000000.0, 1.0),
			_float_field("regeneration_delay", "脱战恢复延迟（秒）", 0.0, 1000.0, 0.1),
			_float_field("regeneration_per_second", "每秒恢复耐久", 0.0, 100000.0, 0.1),
			_float_field("damage_reflection_ratio", "伤害反射比例", 0.0, 1.0, 0.01),
		]
	if kind == BuildingDefinition.Kind.LASER_TOWER:
		return [
			airborne,
			_float_field("laser_dps", "持续伤害/秒", 0.0, 100000.0, 0.1),
			_float_field("base_damage", "端点爆发伤害", 0.0, 100000.0, 0.1),
			_float_field("attack_range", "光束距离（格）", 0.1, 100.0, 0.1),
			_int_field("projectile_penetration_count", "穿透敌人数", 0, 32),
			_float_field("laser_propagation_speed", "光束传播速度（格/秒）", 0.01, 100.0, 0.1),
			_float_field("laser_slow_multiplier", "寒冷移速倍率", 0.0, 1.0, 0.05),
			_float_field("laser_slow_duration", "寒冷持续时间（秒）", 0.0, 60.0, 0.1),
			_float_field("laser_burst_interval", "端点爆发间隔（秒）", 0.0, 60.0, 0.1),
			_float_field("laser_burst_radius", "端点爆发半径（格）", 0.0, 20.0, 0.1),
			_float_field("laser_freeze_duration", "冻结时间（秒）", 0.0, 60.0, 0.1),
			_float_field("laser_beam_width", "光束宽度", 0.01, 2.0, 0.01),
		]
	if kind == BuildingDefinition.Kind.PULSE_LASER_TOWER:
		return [
			airborne,
			_float_field("base_damage", "单次伤害", 0.0, 100000.0, 0.1),
			_float_field("attack_range", "脉冲距离（格）", 0.1, 100.0, 0.1),
			_float_field("attacks_per_second", "每秒攻击次数", 0.01, 100.0, 0.01),
			_int_field("pulse_laser_reflect_max", "最大反射次数", 0, 64),
			_float_field("pulse_laser_width", "脉冲宽度", 0.01, 2.0, 0.01),
			_float_field("pulse_laser_emission_energy", "发光强度", 0.0, 32.0, 0.1),
			_float_field("pulse_laser_fade_in_time", "淡入时间（秒）", 0.0, 10.0, 0.01),
			_float_field("pulse_laser_hold_time", "保持时间（秒）", 0.0, 10.0, 0.01),
			_float_field("pulse_laser_fade_out_time", "淡出时间（秒）", 0.0, 10.0, 0.01),
		]
	var fields: Array[Dictionary] = [
		airborne,
		_float_field("base_damage", "单次伤害", 0.0, 100000.0, 0.1),
		_float_field("targeting_range", "索敌距离（格）", 0.1, 100.0, 0.1),
		_float_field("attack_range", "攻击/飞行距离（格）", 0.1, 100.0, 0.1),
		_float_field("attacks_per_second", "每秒攻击次数", 0.01, 100.0, 0.01),
		_float_field("projectile_speed", "投射物速度（格/秒）", 0.1, 100.0, 0.1),
		_int_field("projectile_penetration_count", "额外穿透目标数", 0, 32),
		_enum_field("projectile_fire_mode", "投射物开火模式", ["仅索敌", "索敌或朝向", "仅固定朝向"]),
	]
	if kind == BuildingDefinition.Kind.MACE_TOWER:
		fields.append(_int_field("projectile_direction_count", "齐射方向数", 1, 8))
	else:
		fields.insert(1, _bool_field("prioritizes_airborne", "优先空中敌人"))
		fields.insert(6, _enum_field("target_priority", "目标优先级", ["最近", "最远", "最高血", "最低血", "最快", "首个进入", "锁定"]))
	if kind == BuildingDefinition.Kind.CROSSBOW_TOWER:
		fields.append(_bool_field("projectile_is_missile", "使用导弹"))
		fields.append(_float_field("missile_explosion_radius", "爆炸半径（格）", 0.0, 20.0, 0.05))
		fields.append(_float_field("missile_orbit_duration", "起飞环绕时间（秒）", 0.01, 10.0, 0.01))
		fields.append(_float_field("missile_orbit_radius_x", "环绕横向半径", 0.0, 10.0, 0.05))
		fields.append(_float_field("missile_orbit_radius_z", "环绕纵向半径", 0.0, 10.0, 0.05))
		fields.append(_float_field("missile_orbit_vertical_amplitude", "环绕高度起伏", 0.0, 5.0, 0.01))
		fields.append(_float_field("missile_homing_turn_speed_degrees", "追踪转向速度（度/秒）", 1.0, 2160.0, 1.0))
		fields.append(_float_field("missile_speed_variation_ratio", "速度波动比例", 0.0, 0.95, 0.01))
		fields.append(_float_field("missile_speed_variation_frequency", "速度波动频率", 0.01, 30.0, 0.01))
	return fields


func _enemy_fields() -> Array[Dictionary]:
	return [
		_float_field("max_hp", "最大生命", 1.0, 100000.0, 1.0),
		_float_field("move_speed", "移动速度（格/秒）", 0.1, 100.0, 0.1),
		_float_field("armor", "护甲", 0.0, 100000.0, 0.1),
		_float_field("reward", "死亡奖励", 0.0, 100000.0, 1.0),
		_float_field("hit_radius", "受击半径", 0.05, 5.0, 0.05),
		_bool_field("is_airborne", "空中单位"),
		_float_field("flight_height", "飞行高度", 0.0, 10.0, 0.05),
		_bool_field("is_elite", "精英敌人"),
		_float_field("movement_active_duration", "连续移动时长（秒）", 0.0, 60.0, 0.05),
		_float_field("movement_pause_duration", "移动停顿时长（秒）", 0.0, 60.0, 0.05),
		_float_field("armor_aura_radius", "护甲光环范围（格）", 0.0, 20.0, 0.05),
		_float_field("armor_aura_bonus", "护甲光环加成", 0.0, 100000.0, 0.1),
		_enum_field("reflection_pattern", "反射面", ["无", "移动方向前方", "左右两侧", "前后左右四面"]),
		_float_field("reflection_side_length", "反射体边长（格）", 0.1, 5.0, 0.05),
		_float_field("reflection_height", "反射体高度（格）", 0.1, 5.0, 0.05),
		_float_field("reflection_max_durability", "单面镜最大耐久", 1.0, 100000.0, 1.0),
		_float_field("attack_damage", "攻击建筑伤害", 0.0, 100000.0, 0.1),
		_float_field("attacks_per_second", "每秒攻击次数", 0.01, 100.0, 0.01),
		_float_field("attack_range", "攻击距离（格）", 0.1, 100.0, 0.1),
		_float_field("projectile_speed", "投射物速度（0 为近战）", 0.0, 100.0, 0.1),
		_color_field("hit_particle_color", "受击粒子颜色"),
		_float_field("hit_particle_brightness", "受击粒子亮度", 0.0, 32.0, 0.1),
		_float_field("hit_particle_size", "受击粒子大小", 0.005, 1.0, 0.005),
		_int_field("hit_particle_count", "受击粒子数量", 0, 128),
	]


func _float_field(property: String, label: String, minimum: float, maximum: float, step: float) -> Dictionary:
	return {"property": StringName(property), "label": label, "type": "float", "min": minimum, "max": maximum, "step": step}


func _int_field(property: String, label: String, minimum: int, maximum: int) -> Dictionary:
	return {"property": StringName(property), "label": label, "type": "int", "min": minimum, "max": maximum, "step": 1}


func _bool_field(property: String, label: String) -> Dictionary:
	return {"property": StringName(property), "label": label, "type": "bool"}


func _color_field(property: String, label: String) -> Dictionary:
	return {"property": StringName(property), "label": label, "type": "color"}


func _enum_field(property: String, label: String, options: Array) -> Dictionary:
	return {"property": StringName(property), "label": label, "type": "enum", "options": options}


func _on_building_selected(_index: int) -> void:
	if _refreshing:
		return
	_refreshing = true
	_refresh_level_selector()
	_refreshing = false
	_rebuild_building_form()


func _on_building_level_selected(_index: int) -> void:
	if not _refreshing:
		_rebuild_building_form()


func _on_enemy_selected(_index: int) -> void:
	if not _refreshing:
		_rebuild_enemy_form()


func _on_building_number_changed(value: float, property: StringName, integer: bool) -> void:
	_apply_building_value(property, int(round(value)) if integer else value)


func _on_building_bool_changed(value: bool, property: StringName) -> void:
	_apply_building_value(property, value)


func _on_building_enum_changed(value: int, property: StringName) -> void:
	_apply_building_value(property, value)


func _on_building_color_changed(value: Color, property: StringName) -> void:
	_apply_building_value(property, value)


func _apply_building_value(property: StringName, value: Variant) -> void:
	if _refreshing or _session == null:
		return
	var definition := _get_selected_building_definition()
	if definition == null:
		return
	var building_level := _selected_metadata_int(_level_select, 1)
	var result := _session.set_building_value(definition.kind, building_level, property, value)
	_show_result(result)
	if not bool(result.get("success", false)):
		_rebuild_building_form()


func _on_enemy_number_changed(value: float, property: StringName, integer: bool) -> void:
	_apply_enemy_value(property, int(round(value)) if integer else value)


func _on_enemy_bool_changed(value: bool, property: StringName) -> void:
	_apply_enemy_value(property, value)


func _on_enemy_enum_changed(value: int, property: StringName) -> void:
	_apply_enemy_value(property, value)


func _on_enemy_color_changed(value: Color, property: StringName) -> void:
	_apply_enemy_value(property, value)


func _apply_enemy_value(property: StringName, value: Variant) -> void:
	if _refreshing or _session == null:
		return
	var definition := _get_selected_enemy_definition(_enemy_select)
	if definition == null:
		return
	var result := _session.set_enemy_value(definition.resource_path, property, value)
	_show_result(result)
	if not bool(result.get("success", false)):
		_rebuild_enemy_form()


func _save_changes() -> bool:
	if _session == null:
		return false
	var result := _session.save()
	_show_result(result)
	if not bool(result.get("success", false)):
		_show_message(String(result.get("message", "保存失败")))
	return bool(result.get("success", false))


func _discard_changes() -> bool:
	if _session == null:
		return false
	var result := _session.discard()
	_show_result(result)
	if not bool(result.get("success", false)):
		_show_message(String(result.get("message", "放弃修改失败")))
	return bool(result.get("success", false))


func _start_test_batch() -> void:
	if _test_spawner == null:
		return
	var enemy := _get_selected_enemy_definition(_test_enemy_select)
	var path := _selected_metadata_path(_test_path_select)
	var result := _test_spawner.start_batch(
		enemy,
		path,
		int(round(_test_count.value)),
		_test_interval.value
	)
	_show_result(result)
	if not bool(result.get("success", false)):
		_show_message(String(result.get("message", "生成测试敌人失败")))


func _stop_test_batch() -> void:
	if _test_spawner != null:
		_test_spawner.stop()


func _clear_test_enemies() -> void:
	if _test_spawner != null:
		_test_spawner.clear_test_enemies()


func _on_test_spawner_state_changed(running: bool, remaining: int, living: int, message: String) -> void:
	if _test_status != null:
		_test_status.text = "%s\n状态：%s · 待生成 %d · 存活 %d" % [message, "生成中" if running else "空闲", remaining, living]


func _refresh_test_counts() -> void:
	if _test_spawner == null or _test_status == null:
		return
	var state := "生成中" if _test_spawner.is_running() else "空闲"
	_test_status.text = "测试敌人不参与波次调度，但正常结算奖励和基地伤害。\n状态：%s · 待生成 %d · 存活 %d" % [state, _test_spawner.get_remaining_count(), _test_spawner.get_living_count()]


func _on_dirty_changed(dirty: bool) -> void:
	title = "运行时战斗数据编辑器%s" % (" *" if dirty else "")
	if _save_button != null:
		_save_button.disabled = not dirty or (_session != null and not _session.can_save_permanently())
	if _discard_button != null:
		_discard_button.disabled = not dirty
	if _status_label != null and not dirty:
		_status_label.text = "工作副本与 .tres 一致"


func _on_session_committed(_paths: PackedStringArray) -> void:
	if _test_spawner != null and _test_spawner.is_running():
		_test_spawner.stop()


func _on_session_discarded() -> void:
	if _test_spawner != null and _test_spawner.is_running():
		_test_spawner.stop()


func _on_close_requested() -> void:
	if _session != null and _session.is_dirty():
		_close_dialog.popup_centered()
		return
	hide()


func _on_close_save_confirmed() -> void:
	if _save_changes():
		hide()


func _on_close_custom_action(action: StringName) -> void:
	if action != &"discard":
		return
	_close_dialog.hide()
	if _discard_changes():
		hide()


func _show_result(result: Dictionary) -> void:
	if _status_label == null:
		return
	_status_label.text = String(result.get("message", ""))
	_status_label.modulate = Color.WHITE if bool(result.get("success", false)) else Color(1.0, 0.48, 0.4)


func _show_message(message: String) -> void:
	if _message_dialog == null:
		push_error(message)
		return
	_message_dialog.dialog_text = message
	_message_dialog.popup_centered(Vector2i(430, 180))


func _get_selected_building_definition() -> BuildingDefinition:
	if _session == null:
		return null
	var kind := _selected_metadata_int(_building_select, -1)
	for definition in _session.get_building_definitions():
		if definition.kind == kind:
			return definition
	return null


func _get_selected_enemy_definition(option: OptionButton) -> EnemyDefinition:
	if _session == null:
		return null
	var path := _selected_metadata_string(option)
	for definition in _session.get_enemy_definitions():
		if definition.resource_path == path:
			return definition
	return null


func _selected_metadata_int(option: OptionButton, fallback: int) -> int:
	if option == null or option.selected < 0:
		return fallback
	return int(option.get_item_metadata(option.selected))


func _selected_metadata_string(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _selected_metadata_path(option: OptionButton) -> PathDefinition:
	if option == null or option.selected < 0:
		return null
	return option.get_item_metadata(option.selected) as PathDefinition


func _selected_metadata_path_name(option: OptionButton) -> String:
	var path := _selected_metadata_path(option)
	return path.display_name if path != null else ""


func _select_metadata(option: OptionButton, value: Variant) -> void:
	if option == null or option.item_count == 0:
		return
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return
	option.select(0)


func _select_path_name(option: OptionButton, value: String) -> void:
	if option == null or option.item_count == 0:
		return
	for index in range(option.item_count):
		var path := option.get_item_metadata(index) as PathDefinition
		if path != null and path.display_name == value:
			option.select(index)
			return
	option.select(0)


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _position_beside_game() -> void:
	var root_window := get_tree().root
	var screen := DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var gap := 12
	var right_position := root_window.position + Vector2i(root_window.size.x + gap, 0)
	var left_position := root_window.position - Vector2i(size.x + gap, 0)
	if right_position.x + size.x <= usable.end.x:
		position = Vector2i(right_position.x, clampi(right_position.y, usable.position.y, usable.end.y - size.y))
	elif left_position.x >= usable.position.x:
		position = Vector2i(left_position.x, clampi(left_position.y, usable.position.y, usable.end.y - size.y))
	else:
		for other_screen in range(DisplayServer.get_screen_count()):
			if other_screen == screen:
				continue
			var other_usable := DisplayServer.screen_get_usable_rect(other_screen)
			if other_usable.size.x >= size.x and other_usable.size.y >= size.y:
				position = other_usable.position
				return
		# A single screen physically narrower than both windows cannot guarantee
		# non-overlap. Keep the editor independently movable at the screen edge.
		position = usable.position + Vector2i(maxi(0, usable.size.x - size.x), 0)
