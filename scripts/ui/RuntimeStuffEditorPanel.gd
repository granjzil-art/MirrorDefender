## Runtime HUD adapter for the developer-facing Stuff authoring workspace.
class_name RuntimeStuffEditorPanel
extends Control

const RuntimeStuffEditorControllerScript := preload("res://scripts/stuff/RuntimeStuffEditorController.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

var _controller: RuntimeStuffEditorControllerScript
var _toggle_button: Button
var _workspace: PanelContainer
var _content_scroll: ScrollContainer
var _palette: VBoxContainer
var _terrain_palette: GridContainer
var _selection_label: Label
var _status_label: Label
var _delete_button: Button
var _undo_button: Button
var _redo_button: Button
var _full_save_button: Button
var _allow_warning: CheckBox
var _definition_buttons: Dictionary = {}
var _terrain_buttons: Dictionary = {}
var _layer_option: OptionButton
var _ramp_run_option: OptionButton
var _ramp_base_option: OptionButton
var _ramp_terrain_option: OptionButton
var _rotate_button: Button
var _discard_confirmation: ConfirmationDialog


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()


func configure(controller: RuntimeStuffEditorControllerScript) -> void:
	_disconnect_controller()
	_controller = controller
	if _controller != null:
		_controller.active_changed.connect(_on_active_changed)
		_controller.definition_selected.connect(_on_definition_selected)
		_controller.runtime_selected.connect(_on_runtime_selected)
		_controller.tool_changed.connect(_on_tool_changed)
		_controller.ramp_selected.connect(_on_ramp_selected)
		_controller.status_changed.connect(_on_status_changed)
		var session := _controller.get_session()
		if session != null:
			session.session_changed.connect(_on_session_changed)
	_rebuild_palette()
	_on_active_changed(_controller != null and _controller.is_active())
	_update_layout()


func is_workspace_visible() -> bool:
	return _workspace != null and _workspace.visible


func get_palette_definition_count() -> int:
	return _definition_buttons.size()


func _build_interface() -> void:
	_toggle_button = Button.new()
	_toggle_button.text = "运行时关卡编辑"
	_toggle_button.position = Vector2(18.0, 206.0)
	_toggle_button.size = Vector2(142.0, 38.0)
	_toggle_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_button.pressed.connect(_on_toggle_pressed)
	add_child(_toggle_button)

	_workspace = PanelContainer.new()
	_workspace.position = Vector2(18.0, 252.0)
	_workspace.size = Vector2(300.0, 610.0)
	_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_workspace)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_workspace.add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	var title := Label.new()
	title.text = "运行时关卡编辑器"
	title.add_theme_font_size_override("font_size", 22)
	root_box.add_child(title)
	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "RuntimeEditorContentScroll"
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	root_box.add_child(_content_scroll)
	var content_box := VBoxContainer.new()
	content_box.name = "RuntimeEditorContent"
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 8)
	_content_scroll.add_child(content_box)
	var select_button := Button.new()
	select_button.text = "选择工具"
	select_button.pressed.connect(_on_select_tool_pressed)
	content_box.add_child(select_button)
	var terrain_title := Label.new()
	terrain_title.text = "地块类型（悬停即预览）"
	content_box.add_child(terrain_title)
	_terrain_palette = GridContainer.new()
	_terrain_palette.columns = 2
	_terrain_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_child(_terrain_palette)
	var layer_row := HBoxContainer.new()
	content_box.add_child(layer_row)
	var layer_label := Label.new()
	layer_label.text = "高度"
	layer_row.add_child(layer_label)
	_layer_option = OptionButton.new()
	for layer_count in range(1, 5):
		_layer_option.add_item("第 %d 层" % layer_count, layer_count)
	layer_row.add_child(_layer_option)
	var layer_button := Button.new()
	layer_button.text = "启用高度刷"
	layer_button.pressed.connect(_on_layer_tool_pressed)
	layer_row.add_child(layer_button)
	var ramp_title := Label.new()
	ramp_title.text = "斜坡（点击低端，R 调整朝向）"
	content_box.add_child(ramp_title)
	var ramp_row := HBoxContainer.new()
	content_box.add_child(ramp_row)
	_ramp_run_option = OptionButton.new()
	for run_length in range(1, 5):
		_ramp_run_option.add_item("1:%d" % run_length, run_length)
	_ramp_run_option.tooltip_text = "斜坡横跨的格数"
	ramp_row.add_child(_ramp_run_option)
	_ramp_base_option = OptionButton.new()
	for base_layer in range(1, 4):
		_ramp_base_option.add_item("底层 %d" % base_layer, base_layer)
	_ramp_base_option.tooltip_text = "斜坡低端所在体素层"
	ramp_row.add_child(_ramp_base_option)
	var ramp_button := Button.new()
	ramp_button.text = "启用斜坡"
	ramp_button.pressed.connect(_on_ramp_tool_pressed)
	ramp_row.add_child(ramp_button)
	_ramp_terrain_option = OptionButton.new()
	_ramp_terrain_option.add_item("斜坡地形：跟随基底", 0)
	_ramp_terrain_option.item_selected.connect(_on_ramp_terrain_selected)
	content_box.add_child(_ramp_terrain_option)
	var stuff_title := Label.new()
	stuff_title.text = "关卡元素"
	content_box.add_child(stuff_title)
	_palette = VBoxContainer.new()
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette.add_theme_constant_override("separation", 5)
	content_box.add_child(_palette)
	_allow_warning = CheckBox.new()
	_allow_warning.text = "允许不可达布局（作者警告）"
	_allow_warning.toggled.connect(_on_allow_warning_toggled)
	content_box.add_child(_allow_warning)
	_selection_label = Label.new()
	_selection_label.text = "未选择元素"
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_box.add_child(_selection_label)
	var selection_action_row := HBoxContainer.new()
	content_box.add_child(selection_action_row)
	_delete_button = Button.new()
	_delete_button.name = "DeleteSelectedStuffButton"
	_delete_button.text = "删除选中元素"
	_delete_button.tooltip_text = "删除当前选中的单个关卡元素（Delete）"
	_delete_button.disabled = true
	_delete_button.pressed.connect(_on_delete_pressed)
	selection_action_row.add_child(_delete_button)
	_rotate_button = Button.new()
	_rotate_button.text = "旋转选中/预览"
	_rotate_button.tooltip_text = "旋转选中的元素或斜坡，也可使用 R"
	_rotate_button.disabled = true
	_rotate_button.pressed.connect(_on_rotate_pressed)
	selection_action_row.add_child(_rotate_button)
	var history_row := HBoxContainer.new()
	content_box.add_child(history_row)
	_undo_button = Button.new()
	_undo_button.text = "撤销"
	_undo_button.pressed.connect(_on_undo_pressed)
	history_row.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "重做"
	_redo_button.pressed.connect(_on_redo_pressed)
	history_row.add_child(_redo_button)
	var save_button := Button.new()
	save_button.text = "保存元素"
	save_button.tooltip_text = "只保存关卡元素；存在地形/斜坡改动时请使用全量保存"
	save_button.pressed.connect(_on_save_pressed)
	history_row.add_child(save_button)
	_full_save_button = Button.new()
	_full_save_button.name = "FullLevelSaveButton"
	_full_save_button.text = "全量保存"
	_full_save_button.tooltip_text = "保存地块类型、层数、斜坡、关卡元素，并把当前实体建筑和全部实体镜子写为初始陈列"
	_full_save_button.pressed.connect(_on_full_save_pressed)
	history_row.add_child(_full_save_button)
	var close_row := HBoxContainer.new()
	content_box.add_child(close_row)
	var save_close := Button.new()
	save_close.text = "保存并退出"
	save_close.pressed.connect(_on_save_close_pressed)
	close_row.add_child(save_close)
	var discard := Button.new()
	discard.text = "放弃并退出"
	discard.pressed.connect(_on_discard_pressed)
	close_row.add_child(discard)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_child(_status_label)
	_discard_confirmation = ConfirmationDialog.new()
	_discard_confirmation.title = "放弃运行时关卡修改"
	_discard_confirmation.dialog_text = "当前运行时关卡存在未保存修改，确定放弃并退出吗？"
	_discard_confirmation.confirmed.connect(_confirm_discard)
	add_child(_discard_confirmation)
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _update_layout() -> void:
	if _workspace == null:
		return
	var viewport_height := size.y if size.y > 0.0 else get_viewport_rect().size.y
	_workspace.size = Vector2(300.0, maxf(120.0, viewport_height - _workspace.position.y - 18.0))


func _rebuild_palette() -> void:
	if _palette == null:
		return
	for child in _palette.get_children():
		child.free()
	_definition_buttons.clear()
	for child in _terrain_palette.get_children():
		child.free()
	_terrain_buttons.clear()
	_ramp_terrain_option.clear()
	_ramp_terrain_option.add_item("斜坡地形：跟随基底", 0)
	var terrains: Array = []
	if _controller != null:
		terrains.assign(_controller.get_terrain_definitions())
	for terrain in terrains:
		var terrain_button := Button.new()
		terrain_button.text = terrain.display_name
		terrain_button.toggle_mode = true
		terrain_button.icon = terrain.ui_icon
		terrain_button.tooltip_text = terrain.resource_path
		terrain_button.pressed.connect(_on_terrain_pressed.bind(terrain))
		_terrain_palette.add_child(terrain_button)
		_terrain_buttons[terrain] = terrain_button
		_ramp_terrain_option.add_item("斜坡地形：%s" % terrain.display_name)
		_ramp_terrain_option.set_item_metadata(_ramp_terrain_option.item_count - 1, terrain)
	var catalog := _controller.get_catalog() if _controller != null else null
	if catalog == null:
		var label := Label.new()
		label.text = "未配置 StuffCatalog"
		_palette.add_child(label)
		return
	for definition in catalog.get_enabled_definitions():
		var button := Button.new()
		button.text = definition.display_name
		button.toggle_mode = true
		button.tooltip_text = definition.description if not definition.description.is_empty() else str(definition.resource_path)
		button.icon = definition.ui_icon
		button.pressed.connect(_on_definition_pressed.bind(definition))
		_palette.add_child(button)
		_definition_buttons[definition] = button


func _on_toggle_pressed() -> void:
	if _controller == null:
		return
	if not _controller.is_active():
		_controller.set_active(true)
		return
	var session := _controller.get_session()
	if session != null and session.is_dirty():
		_discard_confirmation.popup_centered()
	else:
		_controller.set_active(false)


func _on_active_changed(active: bool) -> void:
	visible = feature_enabled
	_toggle_button.visible = feature_enabled
	_toggle_button.text = "退出关卡编辑" if active else "运行时关卡编辑"
	_workspace.visible = feature_enabled and active
	_refresh_history()


func _on_definition_pressed(definition: StuffDefinition) -> void:
	if _controller != null:
		_controller.select_definition(definition)


func _on_terrain_pressed(terrain: TerrainDefinition) -> void:
	if _controller != null:
		_controller.select_terrain_brush(terrain)


func _on_layer_tool_pressed() -> void:
	if _controller != null:
		_controller.select_layer_brush(_layer_option.get_selected_id())


func _on_ramp_tool_pressed() -> void:
	if _controller != null:
		_controller.select_ramp_tool(
			_ramp_run_option.get_selected_id(),
			_ramp_base_option.get_selected_id(),
			_get_selected_ramp_terrain()
		)


func _on_ramp_terrain_selected(_index: int) -> void:
	if _controller == null:
		return
	if _controller.get_selected_ramp() != null:
		_controller.set_selected_ramp_terrain(_get_selected_ramp_terrain())
		return
	_controller.set_ramp_brush_settings(
		_ramp_run_option.get_selected_id(),
		_ramp_base_option.get_selected_id(),
		_get_selected_ramp_terrain()
	)


func _get_selected_ramp_terrain() -> TerrainDefinition:
	if _ramp_terrain_option == null or _ramp_terrain_option.selected <= 0:
		return null
	return _ramp_terrain_option.get_item_metadata(_ramp_terrain_option.selected) as TerrainDefinition


func _on_select_tool_pressed() -> void:
	if _controller != null:
		_controller.select_tool()


func _on_definition_selected(definition: StuffDefinition) -> void:
	for raw_definition in _definition_buttons.keys():
		var button: Button = _definition_buttons[raw_definition]
		button.button_pressed = raw_definition == definition
	_selection_label.text = "放置：%s" % definition.display_name if definition != null else "选择工具"
	_refresh_selection_actions()


func _on_tool_changed(tool: RuntimeStuffEditorController.Tool) -> void:
	for terrain in _terrain_buttons:
		var button: Button = _terrain_buttons[terrain]
		button.button_pressed = (
			tool == RuntimeStuffEditorController.Tool.TERRAIN
			and _controller != null
			and _controller.get_selected_terrain() == terrain
		)
	if tool == RuntimeStuffEditorController.Tool.LAYER:
		_selection_label.text = "高度刷：第 %d 层" % _layer_option.get_selected_id()
	elif tool == RuntimeStuffEditorController.Tool.RAMP and _controller.get_selected_ramp() == null:
		_selection_label.text = "放置斜坡：1:%d / 基础层 %d / R 调整方向" % [
			_ramp_run_option.get_selected_id(),
			_ramp_base_option.get_selected_id(),
		]
	_refresh_selection_actions()


func _on_ramp_selected(ramp: RampPlacementData) -> void:
	if ramp == null:
		_refresh_selection_actions()
		return
	_selection_label.text = "已选斜坡：%s\n低端：%s\n坡度：1:%d\n基础层：%d\n方向：%d" % [
		ramp.ramp_id,
		str(ramp.anchor_cell),
		ramp.run_length,
		ramp.base_layer,
		ramp.facing_index,
	]
	_select_ramp_terrain(ramp.terrain_override)
	_refresh_selection_actions()


func _on_runtime_selected(runtime: StuffRuntime) -> void:
	if runtime == null:
		if _controller == null or _controller.get_selected_definition() == null:
			_selection_label.text = "未选择已有元素"
		_refresh_selection_actions()
		return
	_selection_label.text = "已选：%s\nID：%s\n格：%s\n朝向：%d" % [
		runtime.definition.display_name if runtime.definition != null else "关卡元素",
		runtime.placement_id,
		str(runtime.cell),
		runtime.facing_index,
	]
	_refresh_selection_actions()


func _on_status_changed(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.modulate = Color(1.0, 0.45, 0.38) if is_error else Color(0.78, 0.94, 1.0)
	_refresh_history()


func _on_session_changed(_dirty: bool) -> void:
	_refresh_history()


func _refresh_history() -> void:
	var session := _controller.get_session() if _controller != null else null
	_undo_button.disabled = session == null or not session.can_undo()
	_redo_button.disabled = session == null or not session.can_redo()
	_full_save_button.disabled = _controller == null or not _controller.can_save_full_layout()
	_refresh_selection_actions()


func _refresh_selection_actions() -> void:
	if _delete_button == null:
		return
	var has_selection := (
		_controller != null
		and (_controller.get_selected_runtime() != null or _controller.get_selected_ramp() != null)
	)
	_delete_button.disabled = (
		_controller == null
		or not _controller.is_active()
		or not has_selection
	)
	_delete_button.text = "删除选中斜坡" if _controller != null and _controller.get_selected_ramp() != null else "删除选中元素"
	_rotate_button.disabled = (
		_controller == null
		or not _controller.is_active()
		or (
			not has_selection
			and _controller.get_tool() != RuntimeStuffEditorController.Tool.STUFF
			and _controller.get_tool() != RuntimeStuffEditorController.Tool.RAMP
		)
	)


func _select_ramp_terrain(terrain: TerrainDefinition) -> void:
	if _ramp_terrain_option == null:
		return
	_ramp_terrain_option.select(0)
	if terrain == null:
		return
	for index in range(1, _ramp_terrain_option.item_count):
		if _ramp_terrain_option.get_item_metadata(index) == terrain:
			_ramp_terrain_option.select(index)
			return


func _on_allow_warning_toggled(value: bool) -> void:
	if _controller != null:
		_controller.set_allow_path_warning(value)


func _on_undo_pressed() -> void:
	if _controller != null:
		_controller.undo()


func _on_redo_pressed() -> void:
	if _controller != null:
		_controller.redo()


func _on_delete_pressed() -> void:
	if _controller != null:
		_controller.remove_selected()


func _on_rotate_pressed() -> void:
	if _controller != null:
		_controller.rotate_current()


func _on_save_pressed() -> void:
	if _controller != null:
		_controller.save()


func _on_full_save_pressed() -> void:
	if _controller != null:
		_controller.save_full_layout()


func _on_save_close_pressed() -> void:
	if _controller != null:
		_controller.save_and_close()


func _on_discard_pressed() -> void:
	if _controller == null:
		return
	var session := _controller.get_session()
	if session != null and session.is_dirty():
		_discard_confirmation.popup_centered()
	else:
		_controller.set_active(false)


func _confirm_discard() -> void:
	if _controller != null:
		_controller.discard_and_close()


func _disconnect_controller() -> void:
	if _controller == null:
		return
	if _controller.active_changed.is_connected(_on_active_changed):
		_controller.active_changed.disconnect(_on_active_changed)
	if _controller.definition_selected.is_connected(_on_definition_selected):
		_controller.definition_selected.disconnect(_on_definition_selected)
	if _controller.runtime_selected.is_connected(_on_runtime_selected):
		_controller.runtime_selected.disconnect(_on_runtime_selected)
	if _controller.tool_changed.is_connected(_on_tool_changed):
		_controller.tool_changed.disconnect(_on_tool_changed)
	if _controller.ramp_selected.is_connected(_on_ramp_selected):
		_controller.ramp_selected.disconnect(_on_ramp_selected)
	if _controller.status_changed.is_connected(_on_status_changed):
		_controller.status_changed.disconnect(_on_status_changed)
	var session := _controller.get_session()
	if session != null and session.session_changed.is_connected(_on_session_changed):
		session.session_changed.disconnect(_on_session_changed)
