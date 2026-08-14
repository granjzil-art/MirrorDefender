## Live, in-game tutorial timeline authoring workspace.
class_name TutorialRuntimeEditor
extends Control

const TutorialGoalDefinitionScript := preload("res://scripts/tutorial/TutorialGoalDefinition.gd")
const TutorialBubbleDefinitionScript := preload("res://scripts/tutorial/TutorialBubbleDefinition.gd")

signal active_changed(active: bool)

var _director: TutorialDirector
var _overlay: TutorialOverlay
var _building_manager: BuildingManager
var _wave_manager: WaveManager
var _pick_provider: Callable
var _active: bool = false
var _updating: bool = false
var _selected_event: TutorialEventDefinition
var _selected_bubble: TutorialBubbleDefinition
var _selected_goal: TutorialGoalDefinition

var _workspace: PanelContainer
var _event_option: OptionButton
var _event_name: LineEdit
var _trigger_kind: OptionButton
var _trigger_time_row: HBoxContainer
var _trigger_time_spin: SpinBox
var _trigger_wave_row: HBoxContainer
var _trigger_wave_spin: SpinBox
var _trigger_event_row: HBoxContainer
var _trigger_event_option: OptionButton
var _trigger_label: Label
var _gate_spin: SpinBox
var _bubble_option: OptionButton
var _bubble_text: TextEdit
var _bubble_dismiss: OptionButton
var _bubble_flow: OptionButton
var _bubble_width: SpinBox
var _bubble_x_spin: SpinBox
var _bubble_y_spin: SpinBox
var _bubble_world_anchor: CheckBox
var _goal_option: OptionButton
var _new_goal_type: OptionButton
var _goal_description: LineEdit
var _goal_visible: CheckBox
var _building_option: OptionButton
var _require_cell: CheckBox
var _cell_label: Label
var _require_facing: CheckBox
var _facing_spin: SpinBox
var _level_spin: SpinBox
var _wave_spin: SpinBox
var _status_label: Label
var _building_definitions: Array[BuildingDefinition] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	set_active(false)


func configure(
	director: TutorialDirector,
	overlay: TutorialOverlay,
	building_manager: BuildingManager,
	wave_manager: WaveManager,
	pick_provider: Callable
) -> void:
	if _director != null and _director.authoring_changed.is_connected(_refresh_all):
		_director.authoring_changed.disconnect(_refresh_all)
	_director = director
	_overlay = overlay
	_building_manager = building_manager
	_wave_manager = wave_manager
	_pick_provider = pick_provider
	if _director != null:
		_director.authoring_changed.connect(_refresh_all)
	_rebuild_building_definitions()
	_refresh_all()


func is_active() -> bool:
	return _active


func toggle() -> void:
	set_active(not _active)


func set_active(value: bool) -> void:
	_active = value
	if _workspace != null:
		_workspace.visible = value
	if _overlay != null:
		_overlay.set_authoring_enabled(value)
		_overlay.set_preview_event(_selected_event if value else null)
	active_changed.emit(value)


func capture_hovered_cell() -> bool:
	if not _active or not _pick_provider.is_valid() or _selected_goal == null:
		return false
	var pick: Variant = _pick_provider.call()
	if not pick is Dictionary or not bool((pick as Dictionary).get("hit", false)):
		_set_status("鼠标当前没有悬停在有效地图格上", true)
		return false
	_selected_goal.target_cell = (pick as Dictionary).get("cell", Vector3i.ZERO)
	_selected_goal.require_cell = true
	_selected_goal.emit_changed()
	if _director != null:
		_director.notify_authoring_changed()
	_refresh_goal_fields()
	_set_status("已采样目标格 %s" % str(_selected_goal.target_cell), false)
	return true


func _build_interface() -> void:
	_workspace = PanelContainer.new()
	_workspace.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_workspace.position = Vector2(-452.0, -390.0)
	_workspace.size = Vector2(430.0, 780.0)
	_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	_workspace.z_index = 200
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.055, 0.96)
	style.border_color = Color(0.28, 0.65, 0.95, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	_workspace.add_theme_stylebox_override("panel", style)
	add_child(_workspace)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_workspace.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 7)
	scroll.add_child(root)
	var title := Label.new()
	title.text = "运行时教程时间轴"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.58, 0.86, 1.0))
	root.add_child(title)
	var intro := Label.new()
	intro.text = "运行到目标时刻后创建事件；使用 X/Y 坐标调整气泡位置。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
	root.add_child(intro)
	var event_row := HBoxContainer.new()
	root.add_child(event_row)
	_event_option = OptionButton.new()
	_event_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_option.item_selected.connect(_on_event_selected)
	event_row.add_child(_event_option)
	var create_event := Button.new()
	create_event.text = "在此创建事件"
	create_event.custom_minimum_size.x = 118.0
	create_event.pressed.connect(_on_create_event)
	event_row.add_child(create_event)
	_event_name = LineEdit.new()
	_event_name.placeholder_text = "事件名称"
	_event_name.text_changed.connect(_on_event_name_changed)
	root.add_child(_event_name)
	var trigger_kind_row := HBoxContainer.new()
	root.add_child(trigger_kind_row)
	trigger_kind_row.add_child(_make_label("触发类型"))
	_trigger_kind = OptionButton.new()
	_trigger_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger_kind.add_item("开始触发", TutorialEventDefinition.TriggerKind.START)
	_trigger_kind.add_item("波次结束", TutorialEventDefinition.TriggerKind.WAVE_COMPLETED)
	_trigger_kind.add_item("时间触发", TutorialEventDefinition.TriggerKind.LEVEL_TIME)
	_trigger_kind.add_item("完成指定教程", TutorialEventDefinition.TriggerKind.EVENT_COMPLETED)
	_trigger_kind.item_selected.connect(_on_trigger_kind_changed)
	trigger_kind_row.add_child(_trigger_kind)
	_trigger_time_row = HBoxContainer.new()
	root.add_child(_trigger_time_row)
	_trigger_time_row.add_child(_make_label("关卡时间"))
	_trigger_time_spin = SpinBox.new()
	_trigger_time_spin.min_value = 0.0
	_trigger_time_spin.max_value = 7200.0
	_trigger_time_spin.step = 0.1
	_trigger_time_spin.suffix = " 秒"
	_trigger_time_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger_time_spin.value_changed.connect(_on_trigger_time_changed)
	_trigger_time_row.add_child(_trigger_time_spin)
	_trigger_wave_row = HBoxContainer.new()
	root.add_child(_trigger_wave_row)
	_trigger_wave_row.add_child(_make_label("结束波次"))
	_trigger_wave_spin = SpinBox.new()
	_trigger_wave_spin.min_value = 1
	_trigger_wave_spin.max_value = 999
	_trigger_wave_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger_wave_spin.value_changed.connect(_on_trigger_wave_changed)
	_trigger_wave_row.add_child(_trigger_wave_spin)
	_trigger_event_row = HBoxContainer.new()
	root.add_child(_trigger_event_row)
	_trigger_event_row.add_child(_make_label("指定教程"))
	_trigger_event_option = OptionButton.new()
	_trigger_event_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger_event_option.item_selected.connect(_on_trigger_event_changed)
	_trigger_event_row.add_child(_trigger_event_option)
	_trigger_label = Label.new()
	_trigger_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trigger_label.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
	root.add_child(_trigger_label)
	var gate_row := HBoxContainer.new()
	root.add_child(gate_row)
	gate_row.add_child(_make_label("完成前锁定波次"))
	_gate_spin = SpinBox.new()
	_gate_spin.min_value = 0
	_gate_spin.max_value = 999
	_gate_spin.value_changed.connect(_on_gate_changed)
	gate_row.add_child(_gate_spin)
	root.add_child(HSeparator.new())
	var bubble_header := HBoxContainer.new()
	root.add_child(bubble_header)
	bubble_header.add_child(_make_section_label("思考气泡"))
	_bubble_option = OptionButton.new()
	_bubble_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble_option.item_selected.connect(_on_bubble_selected)
	bubble_header.add_child(_bubble_option)
	var add_bubble := Button.new()
	add_bubble.text = "+"
	add_bubble.tooltip_text = "添加气泡"
	add_bubble.pressed.connect(_on_add_bubble)
	bubble_header.add_child(add_bubble)
	_bubble_text = TextEdit.new()
	_bubble_text.custom_minimum_size = Vector2(0.0, 92.0)
	_bubble_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_bubble_text.text_changed.connect(_on_bubble_text_changed)
	root.add_child(_bubble_text)
	var bubble_options := GridContainer.new()
	bubble_options.columns = 2
	root.add_child(bubble_options)
	bubble_options.add_child(_make_label("消失条件"))
	_bubble_dismiss = OptionButton.new()
	_bubble_dismiss.add_item("点击确认后", TutorialBubbleDefinitionScript.DismissCondition.ACKNOWLEDGED)
	_bubble_dismiss.add_item("关联目标完成", TutorialBubbleDefinitionScript.DismissCondition.GOAL_COMPLETED)
	_bubble_dismiss.add_item("整个事件完成", TutorialBubbleDefinitionScript.DismissCondition.EVENT_COMPLETED)
	_bubble_dismiss.add_item("持续存在", TutorialBubbleDefinitionScript.DismissCondition.PERSISTENT)
	_bubble_dismiss.item_selected.connect(_on_bubble_dismiss_changed)
	bubble_options.add_child(_bubble_dismiss)
	bubble_options.add_child(_make_label("边缘流动"))
	_bubble_flow = OptionButton.new()
	_bubble_flow.add_item("关闭", TutorialBubbleDefinitionScript.FlowStrength.OFF)
	_bubble_flow.add_item("轻微", TutorialBubbleDefinitionScript.FlowStrength.LIGHT)
	_bubble_flow.add_item("明显", TutorialBubbleDefinitionScript.FlowStrength.STRONG)
	_bubble_flow.item_selected.connect(_on_bubble_flow_changed)
	bubble_options.add_child(_bubble_flow)
	bubble_options.add_child(_make_label("最大宽度"))
	_bubble_width = SpinBox.new()
	_bubble_width.min_value = 180
	_bubble_width.max_value = 720
	_bubble_width.step = 10
	_bubble_width.value_changed.connect(_on_bubble_width_changed)
	bubble_options.add_child(_bubble_width)
	bubble_options.add_child(_make_label("X 坐标"))
	_bubble_x_spin = SpinBox.new()
	_bubble_x_spin.min_value = -4096
	_bubble_x_spin.max_value = 8192
	_bubble_x_spin.value_changed.connect(_on_bubble_x_changed)
	bubble_options.add_child(_bubble_x_spin)
	bubble_options.add_child(_make_label("Y 坐标"))
	_bubble_y_spin = SpinBox.new()
	_bubble_y_spin.min_value = -4096
	_bubble_y_spin.max_value = 8192
	_bubble_y_spin.value_changed.connect(_on_bubble_y_changed)
	bubble_options.add_child(_bubble_y_spin)
	_bubble_world_anchor = CheckBox.new()
	_bubble_world_anchor.text = "气泡跟随当前目标格"
	_bubble_world_anchor.toggled.connect(_on_bubble_world_anchor_toggled)
	root.add_child(_bubble_world_anchor)
	var coordinate_hint := Label.new()
	coordinate_hint.text = "屏幕气泡使用绝对坐标；跟随目标格时，X/Y 表示相对目标格的偏移。"
	coordinate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coordinate_hint.add_theme_color_override("font_color", Color(0.7, 0.76, 0.82))
	root.add_child(coordinate_hint)
	root.add_child(HSeparator.new())
	var goal_header := HBoxContainer.new()
	root.add_child(goal_header)
	goal_header.add_child(_make_section_label("待办目标"))
	_goal_option = OptionButton.new()
	_goal_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal_option.item_selected.connect(_on_goal_selected)
	goal_header.add_child(_goal_option)
	_new_goal_type = OptionButton.new()
	_add_goal_type_items(_new_goal_type)
	goal_header.add_child(_new_goal_type)
	var add_goal := Button.new()
	add_goal.text = "+"
	add_goal.tooltip_text = "添加目标"
	add_goal.pressed.connect(_on_add_goal)
	goal_header.add_child(add_goal)
	_goal_description = LineEdit.new()
	_goal_description.placeholder_text = "目标描述（留空自动生成）"
	_goal_description.text_changed.connect(_on_goal_description_changed)
	root.add_child(_goal_description)
	_goal_visible = CheckBox.new()
	_goal_visible.text = "显示在左上角目标列表"
	_goal_visible.toggled.connect(_on_goal_visible_changed)
	root.add_child(_goal_visible)
	var goal_grid := GridContainer.new()
	goal_grid.columns = 2
	root.add_child(goal_grid)
	goal_grid.add_child(_make_label("建筑"))
	_building_option = OptionButton.new()
	_building_option.item_selected.connect(_on_building_selected)
	goal_grid.add_child(_building_option)
	_require_cell = CheckBox.new()
	_require_cell.text = "指定位置"
	_require_cell.toggled.connect(_on_require_cell_changed)
	goal_grid.add_child(_require_cell)
	_cell_label = Label.new()
	_cell_label.text = "未设置（移到地图后按 T）"
	goal_grid.add_child(_cell_label)
	_require_facing = CheckBox.new()
	_require_facing.text = "指定朝向"
	_require_facing.toggled.connect(_on_require_facing_changed)
	goal_grid.add_child(_require_facing)
	_facing_spin = SpinBox.new()
	_facing_spin.min_value = 0
	_facing_spin.max_value = 35
	_facing_spin.value_changed.connect(_on_facing_changed)
	goal_grid.add_child(_facing_spin)
	goal_grid.add_child(_make_label("目标等级"))
	_level_spin = SpinBox.new()
	_level_spin.min_value = 1
	_level_spin.max_value = BuildingDefinition.MAX_LEVEL
	_level_spin.value_changed.connect(_on_level_changed)
	goal_grid.add_child(_level_spin)
	goal_grid.add_child(_make_label("目标波次"))
	_wave_spin = SpinBox.new()
	_wave_spin.min_value = 1
	_wave_spin.max_value = 999
	_wave_spin.value_changed.connect(_on_wave_changed)
	goal_grid.add_child(_wave_spin)
	var capture_hint := Label.new()
	capture_hint.text = "位置目标：把鼠标移到地图格后按 T 采样。朝向 0–35，每档 10°。"
	capture_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	capture_hint.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	root.add_child(capture_hint)
	root.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var save := Button.new()
	save.text = "保存教程到关卡"
	save.pressed.connect(_on_save)
	bottom.add_child(save)
	var close := Button.new()
	close.text = "关闭编辑器"
	close.pressed.connect(func() -> void: set_active(false))
	bottom.add_child(close)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _refresh_all() -> void:
	if not is_node_ready():
		return
	_updating = true
	var events := _director.get_events() if _director != null else []
	_event_option.clear()
	for index in range(events.size()):
		_event_option.add_item(events[index].display_name, index)
	if _selected_event == null or not events.has(_selected_event):
		_selected_event = events.back() if not events.is_empty() else null
	if _selected_event != null:
		_event_option.select(events.find(_selected_event))
	var event_name_text := _selected_event.display_name if _selected_event != null else ""
	if _event_name.text != event_name_text:
		_event_name.text = event_name_text
	_event_name.editable = _selected_event != null
	_gate_spin.editable = _selected_event != null
	_gate_spin.value = _selected_event.gated_wave_number if _selected_event != null else 0
	_refresh_trigger_fields(events)
	_refresh_bubble_list()
	_refresh_goal_list()
	_updating = false
	if _overlay != null and _active:
		_overlay.set_preview_event(_selected_event)


func _refresh_bubble_list() -> void:
	_bubble_option.clear()
	var bubbles: Array[TutorialBubbleDefinition] = []
	if _selected_event != null:
		bubbles = _selected_event.bubbles
	for index in range(bubbles.size()):
		_bubble_option.add_item("气泡 %d" % (index + 1), index)
	if _selected_bubble == null or not bubbles.has(_selected_bubble):
		_selected_bubble = bubbles[0] if not bubbles.is_empty() else null
	if _selected_bubble != null:
		_bubble_option.select(bubbles.find(_selected_bubble))
	_bubble_text.editable = _selected_bubble != null
	var bubble_text := _selected_bubble.text if _selected_bubble != null else ""
	if _bubble_text.text != bubble_text:
		_bubble_text.text = bubble_text
	_bubble_width.value = _selected_bubble.maximum_width if _selected_bubble != null else 420
	_bubble_x_spin.editable = _selected_bubble != null
	_bubble_y_spin.editable = _selected_bubble != null
	var bubble_coordinates := Vector2.ZERO
	if _selected_bubble != null:
		bubble_coordinates = (
			_selected_bubble.offset
			if _selected_bubble.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL
			else _selected_bubble.screen_position
		)
	_bubble_x_spin.value = bubble_coordinates.x
	_bubble_y_spin.value = bubble_coordinates.y
	_bubble_world_anchor.button_pressed = (
		_selected_bubble != null
		and _selected_bubble.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL
	)
	if _selected_bubble != null:
		_bubble_dismiss.select(_bubble_dismiss.get_item_index(_selected_bubble.dismiss_condition))
		_bubble_flow.select(_bubble_flow.get_item_index(_selected_bubble.flow_strength))


func _refresh_goal_list() -> void:
	_goal_option.clear()
	var goals: Array[TutorialGoalDefinition] = []
	if _selected_event != null:
		goals = _selected_event.goals
	for index in range(goals.size()):
		_goal_option.add_item("%d. %s" % [index + 1, goals[index].get_display_description()], index)
	if _selected_goal == null or not goals.has(_selected_goal):
		_selected_goal = goals[0] if not goals.is_empty() else null
	if _selected_goal != null:
		_goal_option.select(goals.find(_selected_goal))
	_refresh_goal_fields()


func _refresh_trigger_fields(events: Array[TutorialEventDefinition]) -> void:
	var has_event := _selected_event != null
	_trigger_kind.disabled = not has_event
	if has_event:
		_trigger_kind.select(_trigger_kind.get_item_index(_selected_event.trigger_kind))
	_trigger_time_row.visible = has_event and _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.LEVEL_TIME
	_trigger_wave_row.visible = has_event and _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.WAVE_COMPLETED
	_trigger_event_row.visible = has_event and _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.EVENT_COMPLETED
	_trigger_time_spin.editable = has_event
	_trigger_time_spin.value = _selected_event.trigger_delay_seconds if has_event else 0.0
	_trigger_wave_spin.editable = has_event
	_trigger_wave_spin.value = _selected_event.trigger_wave_number if has_event else 1
	_trigger_event_option.clear()
	var selected_trigger_event := -1
	for event in events:
		if event == _selected_event:
			continue
		var item_index := _trigger_event_option.item_count
		_trigger_event_option.add_item(event.display_name)
		_trigger_event_option.set_item_metadata(item_index, event.event_id)
		if has_event and event.event_id == _selected_event.trigger_event_id:
			selected_trigger_event = item_index
	if _trigger_event_option.item_count == 0:
		_trigger_event_option.add_item("没有其他教程事件")
		_trigger_event_option.disabled = true
	else:
		_trigger_event_option.disabled = not has_event
		_trigger_event_option.select(selected_trigger_event)
	_trigger_label.text = _describe_trigger(_selected_event)


func _refresh_goal_fields() -> void:
	var goal := _selected_goal
	_goal_description.editable = goal != null
	var goal_description_text := goal.description if goal != null else ""
	if _goal_description.text != goal_description_text:
		_goal_description.text = goal_description_text
	_goal_visible.disabled = goal == null
	_goal_visible.button_pressed = goal.show_in_checklist if goal != null else false
	_require_cell.disabled = goal == null
	_require_cell.button_pressed = goal.require_cell if goal != null else false
	_cell_label.text = str(goal.target_cell) if goal != null and goal.require_cell else "未设置（移到地图后按 T）"
	_require_facing.disabled = goal == null
	_require_facing.button_pressed = goal.require_facing if goal != null else false
	_facing_spin.editable = goal != null
	_facing_spin.value = goal.target_facing_index if goal != null else 0
	_level_spin.editable = goal != null
	_level_spin.value = goal.target_level if goal != null else 1
	_wave_spin.editable = goal != null
	_wave_spin.value = goal.target_wave_number if goal != null else 1
	_rebuild_building_option()


func _rebuild_building_definitions() -> void:
	_building_definitions.clear()
	if _building_manager == null:
		return
	for definition in [
		_building_manager.arrow_tower,
		_building_manager.laser_tower,
		_building_manager.pulse_laser_tower,
		_building_manager.crossbow_tower,
		_building_manager.mace_tower,
		_building_manager.barrier,
		_building_manager.edge_barrier,
	]:
		if definition != null and not _building_definitions.has(definition):
			_building_definitions.append(definition)


func _rebuild_building_option() -> void:
	_building_option.clear()
	_building_option.add_item("不限制", -1)
	for index in range(_building_definitions.size()):
		_building_option.add_item(_building_definitions[index].display_name, index)
	var selected := -1
	if _selected_goal != null and _selected_goal.building_definition != null:
		selected = _building_definitions.find(_selected_goal.building_definition)
	_building_option.select(_building_option.get_item_index(selected))


func _add_goal_type_items(option: OptionButton) -> void:
	option.add_item("说明气泡", TutorialGoalDefinitionScript.GoalType.ACKNOWLEDGE_ALL_BUBBLES)
	option.add_item("空白点击", TutorialGoalDefinitionScript.GoalType.BLANK_SCREEN_CLICKS)
	option.add_item("放置建筑", TutorialGoalDefinitionScript.GoalType.PLACE_BUILDING)
	option.add_item("升级建筑", TutorialGoalDefinitionScript.GoalType.UPGRADE_BUILDING)
	option.add_item("删除建筑", TutorialGoalDefinitionScript.GoalType.DELETE_BUILDING)
	option.add_item("释放波次", TutorialGoalDefinitionScript.GoalType.RELEASE_WAVE)
	option.add_item("完成波次", TutorialGoalDefinitionScript.GoalType.COMPLETE_WAVE)


func _describe_trigger(event: TutorialEventDefinition) -> String:
	if event == null:
		return "运行到目标时刻后点击“在此创建事件”。"
	match event.trigger_kind:
		TutorialEventDefinition.TriggerKind.START:
			return "触发点：关卡开始后立即触发"
		TutorialEventDefinition.TriggerKind.LEVEL_TIME:
			return "触发点：进入关卡 %.1f 秒后" % event.trigger_delay_seconds
		TutorialEventDefinition.TriggerKind.WAVE_COMPLETED:
			return "触发点：第 %d 波结束后" % event.trigger_wave_number
		TutorialEventDefinition.TriggerKind.EVENT_COMPLETED:
			return "触发点：教程 %s 完成后" % event.trigger_event_id
	return "触发点未配置"


func _on_create_event() -> void:
	if _director == null:
		return
	_selected_event = _director.create_event_at_current_time()
	_selected_bubble = null
	_selected_goal = null
	_refresh_all()
	_set_status("已在当前运行时刻创建事件", false)


func _on_event_selected(index: int) -> void:
	if _updating or _director == null:
		return
	var events := _director.get_events()
	_selected_event = events[index] if index >= 0 and index < events.size() else null
	_selected_bubble = null
	_selected_goal = null
	_refresh_all()


func _on_event_name_changed(value: String) -> void:
	if _updating or _selected_event == null:
		return
	_selected_event.display_name = value
	_notify_changed()


func _on_trigger_kind_changed(index: int) -> void:
	if _updating or _selected_event == null:
		return
	_selected_event.trigger_kind = _trigger_kind.get_item_id(index)
	if _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.LEVEL_TIME:
		_selected_event.trigger_delay_seconds = _director.get_level_elapsed() if _director != null else 0.0
	else:
		_selected_event.trigger_delay_seconds = 0.0
	if _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.WAVE_COMPLETED:
		var current_wave := _wave_manager.get_current_wave_number() if _wave_manager != null else 0
		_selected_event.trigger_wave_number = maxi(1, current_wave)
	elif _selected_event.trigger_kind == TutorialEventDefinition.TriggerKind.EVENT_COMPLETED:
		var events := _director.get_events() if _director != null else []
		for event in events:
			if event != _selected_event:
				_selected_event.trigger_event_id = event.event_id
				break
	_notify_changed()


func _on_trigger_time_changed(value: float) -> void:
	if _updating or _selected_event == null:
		return
	_selected_event.trigger_delay_seconds = value
	_notify_changed()


func _on_trigger_wave_changed(value: float) -> void:
	if _updating or _selected_event == null:
		return
	_selected_event.trigger_wave_number = roundi(value)
	_notify_changed()


func _on_trigger_event_changed(index: int) -> void:
	if _updating or _selected_event == null or _trigger_event_option.disabled:
		return
	_selected_event.trigger_event_id = _trigger_event_option.get_item_metadata(index)
	_notify_changed()


func _on_gate_changed(value: float) -> void:
	if _updating or _selected_event == null:
		return
	_selected_event.gated_wave_number = roundi(value)
	_notify_changed()


func _on_add_bubble() -> void:
	if _director == null or _selected_event == null:
		return
	_selected_bubble = _director.add_bubble(_selected_event)
	_refresh_all()


func _on_bubble_selected(index: int) -> void:
	if _updating or _selected_event == null:
		return
	_selected_bubble = _selected_event.bubbles[index] if index >= 0 and index < _selected_event.bubbles.size() else null
	_updating = true
	_refresh_bubble_list()
	_updating = false


func _on_bubble_text_changed() -> void:
	if _updating or _selected_bubble == null:
		return
	_selected_bubble.text = _bubble_text.text
	_notify_changed()


func _on_bubble_dismiss_changed(index: int) -> void:
	if _updating or _selected_bubble == null:
		return
	_selected_bubble.dismiss_condition = _bubble_dismiss.get_item_id(index)
	if (
		_selected_bubble.dismiss_condition == TutorialBubbleDefinitionScript.DismissCondition.GOAL_COMPLETED
		and _selected_event != null
		and _selected_goal != null
	):
		_selected_bubble.associated_goal_index = _selected_event.goals.find(_selected_goal)
	_notify_changed()


func _on_bubble_flow_changed(index: int) -> void:
	if _updating or _selected_bubble == null:
		return
	_selected_bubble.flow_strength = _bubble_flow.get_item_id(index)
	_notify_changed()


func _on_bubble_width_changed(value: float) -> void:
	if _updating or _selected_bubble == null:
		return
	_selected_bubble.maximum_width = value
	_notify_changed()


func _on_bubble_x_changed(value: float) -> void:
	if _updating or _selected_bubble == null:
		return
	if _selected_bubble.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL:
		_selected_bubble.offset.x = value
	else:
		_selected_bubble.screen_position.x = value
	_notify_changed()


func _on_bubble_y_changed(value: float) -> void:
	if _updating or _selected_bubble == null:
		return
	if _selected_bubble.anchor_kind == TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL:
		_selected_bubble.offset.y = value
	else:
		_selected_bubble.screen_position.y = value
	_notify_changed()


func _on_bubble_world_anchor_toggled(enabled: bool) -> void:
	if _updating or _selected_bubble == null:
		return
	_selected_bubble.anchor_kind = (
		TutorialBubbleDefinitionScript.AnchorKind.WORLD_CELL
		if enabled
		else TutorialBubbleDefinitionScript.AnchorKind.SCREEN
	)
	if enabled and _selected_goal != null and _selected_goal.require_cell:
		_selected_bubble.world_cell = _selected_goal.target_cell
	_notify_changed()


func _on_add_goal() -> void:
	if _director == null or _selected_event == null:
		return
	_selected_goal = _director.add_goal(_selected_event, _new_goal_type.get_selected_id())
	if _selected_goal.goal_type in [
		TutorialGoalDefinitionScript.GoalType.PLACE_BUILDING,
		TutorialGoalDefinitionScript.GoalType.UPGRADE_BUILDING,
		TutorialGoalDefinitionScript.GoalType.DELETE_BUILDING,
	] and not _building_definitions.is_empty():
		_selected_goal.building_definition = _building_definitions[0]
	_refresh_all()


func _on_goal_selected(index: int) -> void:
	if _updating or _selected_event == null:
		return
	_selected_goal = _selected_event.goals[index] if index >= 0 and index < _selected_event.goals.size() else null
	_updating = true
	_refresh_goal_fields()
	_updating = false


func _on_goal_description_changed(value: String) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.description = value
	_notify_changed()


func _on_goal_visible_changed(value: bool) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.show_in_checklist = value
	_notify_changed()


func _on_building_selected(index: int) -> void:
	if _updating or _selected_goal == null:
		return
	var id := _building_option.get_item_id(index)
	_selected_goal.building_definition = _building_definitions[id] if id >= 0 and id < _building_definitions.size() else null
	_notify_changed()


func _on_require_cell_changed(value: bool) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.require_cell = value
	_notify_changed()


func _on_require_facing_changed(value: bool) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.require_facing = value
	_notify_changed()


func _on_facing_changed(value: float) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.target_facing_index = roundi(value)
	_notify_changed()


func _on_level_changed(value: float) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.target_level = roundi(value)
	_notify_changed()


func _on_wave_changed(value: float) -> void:
	if _updating or _selected_goal == null:
		return
	_selected_goal.target_wave_number = roundi(value)
	_notify_changed()


func _on_save() -> void:
	if _director == null:
		return
	var result := _director.save_tutorial()
	_set_status(String(result.get("message", "")), not bool(result.get("success", false)))


func _notify_changed() -> void:
	if _selected_event != null:
		_selected_event.emit_changed()
	if _selected_bubble != null:
		_selected_bubble.emit_changed()
	if _selected_goal != null:
		_selected_goal.emit_changed()
	if _director != null:
		_director.notify_authoring_changed()


func _set_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38) if is_error else Color(0.45, 1.0, 0.62))


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_section_label(text: String) -> Label:
	var label := _make_label(text)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.43))
	return label
