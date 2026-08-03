@tool
## TerrainStuffEditor -- self-contained canonical Grid/Terrain/Stuff editor page.
## It is embedded by TileEditorPanel; wave and camera pages remain untouched.
class_name TerrainStuffEditor
extends HSplitContainer

const HEX_SHAPE := 0
const SQUARE_SHAPE := 1
const Authoring := preload("res://addons/mirror_tile_editor/terrain_stuff_authoring.gd")
const CanvasScript := preload("res://addons/mirror_tile_editor/terrain_stuff_canvas.gd")
const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const TerrainModelMetricsScript := preload("res://scripts/terrain/TerrainModelMetrics.gd")

signal level_changed

var _level: LevelResource
var _shape: IGridShape
var _canvas: TerrainStuffCanvas
var _status: Label
var _shape_select: OptionButton
var _size_x: SpinBox
var _size_y: SpinBox
var _layer_height: SpinBox
var _default_terrain_select: OptionButton
var _terrain_select: OptionButton
var _layer_select: SpinBox
var _allows_tile: CheckButton
var _allows_edge: CheckButton
var _stuff_list: OptionButton
var _stuff_facing: SpinBox
var _remove_stuff_button: Button
var _ramp_label: Label
var _remove_ramp_button: Button
var _permission_tile_brush: CheckButton
var _permission_edge_brush: CheckButton
var _stuff_brush_facing: SpinBox
var _ramp_direction: OptionButton
var _ramp_length: OptionButton
var _ramp_base_layer: OptionButton
var _ramp_terrain: OptionButton
var _selected_ramp_terrain: OptionButton
var _terrain_options: Array[TerrainDefinitionScript] = []
var _stuff_options: Array[StuffDefinitionScript] = []
var _controls_blocked: bool = false
var _pending_shape_id: int = HEX_SHAPE
var _pending_grid_size := Vector2i(6, 6)
var _grid_confirmation: ConfirmationDialog
var _interface_built: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_interface()


## Returns the authoring preparation result from TerrainStuffAuthoring.
func set_level(value: LevelResource) -> Dictionary:
	_ensure_interface()
	_level = value
	if _level == null:
		_canvas.set_level(null)
		return {
			"changed": false,
			"migrated": false,
			"added_cells": 0,
			"normalized_ramps": 0,
			"skipped_ramps": 0,
		}
	_rebuild_shape()
	var preparation := Authoring.prepare_level(_level, _shape)
	_sync_level_controls()
	_canvas.set_level(_level)
	_refresh_selected_inspector()
	if bool(preparation["migrated"]):
		_set_status("旧地块已导入为 Terrain / Stuff 规范数据；保存后完成单向迁移。", true)
	elif int(preparation["normalized_ramps"]) > 0:
		_set_status(
			"已自动规约 %d 个斜坡的坡体与高低端体素层；请保存。"
			% int(preparation["normalized_ramps"]),
			true
		)
	elif int(preparation["added_cells"]) > 0:
		_set_status("已补齐 %d 个未显式配置的 Grid 格。" % int(preparation["added_cells"]), true)
	else:
		_set_status("Terrain / Stuff 编辑器已就绪。", true)
	return preparation


func reset_view() -> void:
	if _canvas != null:
		_canvas.reset_view()


func refresh() -> void:
	if _canvas != null:
		_canvas.refresh()
	_refresh_selected_inspector()


## Reconciles RampPlacementData with canonical Grid voxel layers. The parent
## editor calls this immediately before validation/save so Inspector-created or
## externally edited ramps cannot persist a visually valid but invalid Grid.
func normalize_ramp_constraints() -> Dictionary:
	if _level == null or _shape == null:
		return {
			"changed": false,
			"normalized_ramps": 0,
			"skipped_ramps": 0,
			"skipped_ramp_ids": [],
		}
	var result := Authoring.normalize_ramp_constraints(_level, _shape)
	if bool(result["changed"]):
		_canvas.refresh()
		_refresh_selected_inspector()
		level_changed.emit()
	return result


func get_selected_cell() -> Vector3i:
	return _canvas.selected_cell if _canvas != null and _canvas.has_selected_cell else Vector3i.ZERO


## Compatibility/testing entry for the parent editor. The returned canvas is
## still canonical and never exposes legacy Tile mutation APIs.
func get_editor_canvas() -> TerrainStuffCanvas:
	_ensure_interface()
	return _canvas


func _build_interface() -> void:
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(292.0, 0.0)
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(274.0, 0.0)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 7)
	sidebar_scroll.add_child(sidebar)
	# SplitContainer only supports two layout children. Keep the outer split for
	# the authoring toolbar, then nest the canvas/inspector split on the right.
	# This keeps Godot 4.7's native container contract valid when the editor
	# restores this main-screen plugin outside recovery mode.
	var content_split := HSplitContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content_split)

	_add_heading(sidebar, "Terrain Grid")
	var select_tool := Button.new()
	select_tool.text = "选择 / 检查"
	select_tool.pressed.connect(func() -> void:
		_canvas.set_select_tool()
		_set_status("选择模式：点击格子查看 Terrain、权限、斜坡和全部 Stuff。", true)
	)
	sidebar.add_child(select_tool)

	_shape_select = OptionButton.new()
	_shape_select.add_item("六边形 flat-top", HEX_SHAPE)
	_shape_select.add_item("正方形", SQUARE_SHAPE)
	_shape_select.item_selected.connect(_request_grid_rebuild_from_controls)
	sidebar.add_child(_with_label("网格形状", _shape_select))
	_size_x = _make_spin_box(1.0, 20.0, 1.0)
	_size_x.value_changed.connect(_request_grid_rebuild_from_value)
	sidebar.add_child(_with_label("半径 / 列数", _size_x))
	_size_y = _make_spin_box(1.0, 20.0, 1.0)
	_size_y.value_changed.connect(_request_grid_rebuild_from_value)
	sidebar.add_child(_with_label("行数（六边形忽略）", _size_y))
	_layer_height = _make_spin_box(0.05, 5.0, 0.05)
	_layer_height.editable = false
	_layer_height.tooltip_text = "由 Grid Cell Size 与地形模型 1:1 体素比例自动确定"
	_layer_height.value_changed.connect(_on_layer_height_changed)
	sidebar.add_child(_with_label("体素单层高度", _layer_height))

	_terrain_options = _load_terrain_resources()
	_default_terrain_select = OptionButton.new()
	_fill_terrain_options(_default_terrain_select)
	_default_terrain_select.item_selected.connect(_on_default_terrain_changed)
	sidebar.add_child(_with_label("新格默认地形", _default_terrain_select))

	_add_heading(sidebar, "地形刷")
	var terrain_group := ButtonGroup.new()
	for terrain in _terrain_options:
		var button := Button.new()
		button.text = terrain.display_name
		button.toggle_mode = true
		button.button_group = terrain_group
		button.tooltip_text = "%s (%s)" % [terrain.display_name, terrain.resource_path]
		button.pressed.connect(_select_terrain_brush.bind(terrain))
		sidebar.add_child(button)

	_add_heading(sidebar, "层数刷（固定 1～4 层）")
	var layer_row := HBoxContainer.new()
	for layer_count in range(1, 5):
		var button := Button.new()
		button.text = str(layer_count)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_layer_brush.bind(layer_count))
		layer_row.add_child(button)
	sidebar.add_child(layer_row)

	_add_heading(sidebar, "Grid 建造权限刷")
	_permission_tile_brush = CheckButton.new()
	_permission_tile_brush.text = "允许块建筑"
	_permission_tile_brush.button_pressed = true
	sidebar.add_child(_permission_tile_brush)
	_permission_edge_brush = CheckButton.new()
	_permission_edge_brush.text = "允许边建筑"
	_permission_edge_brush.button_pressed = true
	sidebar.add_child(_permission_edge_brush)
	var permission_brush := Button.new()
	permission_brush.text = "启用权限刷"
	permission_brush.pressed.connect(_select_permission_brush)
	sidebar.add_child(permission_brush)

	_add_heading(sidebar, "Stuff 关卡元素刷")
	_stuff_brush_facing = _make_spin_box(0.0, 7.0, 1.0)
	sidebar.add_child(_with_label("放置朝向索引", _stuff_brush_facing))
	_stuff_options = _load_stuff_resources()
	var stuff_group := ButtonGroup.new()
	for definition in _stuff_options:
		var button := Button.new()
		button.text = definition.display_name
		button.toggle_mode = true
		button.button_group = stuff_group
		button.tooltip_text = "%s\n互斥=%s，阻止块=%s，阻止边=%s" % [str(definition.resource_path), str(definition.exclusive_with_other_stuff), str(definition.blocks_tile_building), str(definition.blocks_edge_building)]
		button.pressed.connect(_select_stuff_brush.bind(definition))
		sidebar.add_child(button)

	_add_heading(sidebar, "斜坡工具（S1）")
	_ramp_direction = OptionButton.new()
	sidebar.add_child(_with_label("上坡方向", _ramp_direction))
	_ramp_length = OptionButton.new()
	for run_length in range(1, 5):
		_ramp_length.add_item("1:%d（占 %d 格）" % [run_length, run_length], run_length)
	sidebar.add_child(_with_label("坡度", _ramp_length))
	_ramp_base_layer = OptionButton.new()
	for base_layer in range(1, 4):
		_ramp_base_layer.add_item("第 %d 层 -> 第 %d 层" % [base_layer, base_layer + 1], base_layer)
	sidebar.add_child(_with_label("高低端", _ramp_base_layer))
	_ramp_terrain = OptionButton.new()
	_ramp_terrain.name = "RampTerrainBrush"
	_fill_ramp_terrain_options(_ramp_terrain)
	sidebar.add_child(_with_label("斜坡地形", _ramp_terrain))
	var ramp_brush := Button.new()
	ramp_brush.text = "启用斜坡：点击最低坡格"
	ramp_brush.tooltip_text = "自动统一坡体基底地形/基础层，并把高端连接格提高一层；斜坡地形可跟随基底或独立覆盖。"
	ramp_brush.pressed.connect(_select_ramp_brush)
	sidebar.add_child(ramp_brush)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.65, 0.77, 0.88, 1.0))
	sidebar.add_child(_status)

	_canvas = CanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.cell_selected.connect(_on_cell_selected)
	_canvas.content_changed.connect(_on_canvas_content_changed)
	_canvas.operation_reported.connect(_on_operation_reported)
	content_split.add_child(_canvas)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.custom_minimum_size = Vector2(300.0, 0.0)
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_split.add_child(inspector_scroll)
	var inspector := VBoxContainer.new()
	inspector.custom_minimum_size = Vector2(282.0, 0.0)
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 8)
	inspector_scroll.add_child(inspector)
	_build_inspector(inspector)

	_grid_confirmation = ConfirmationDialog.new()
	_grid_confirmation.title = "重建 Terrain Grid"
	_grid_confirmation.dialog_text = "切换形状或尺寸会重建 Terrain、斜坡和 Stuff。路径、波次与镜头数据保留，但可能需要重新校验。"
	_grid_confirmation.ok_button_text = "重建"
	_grid_confirmation.confirmed.connect(_confirm_grid_rebuild)
	_grid_confirmation.canceled.connect(_sync_level_controls)
	add_child(_grid_confirmation)


func _ensure_interface() -> void:
	if _interface_built:
		return
	_interface_built = true
	_build_interface()


func _build_inspector(inspector: VBoxContainer) -> void:
	_add_heading(inspector, "单格规范数据")
	var selected_help := Label.new()
	selected_help.name = "SelectedCellHelp"
	selected_help.text = "选择地图中的一格"
	selected_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(selected_help)
	_terrain_select = OptionButton.new()
	_fill_terrain_options(_terrain_select)
	_terrain_select.item_selected.connect(_on_selected_terrain_changed)
	inspector.add_child(_with_label("Terrain 地形", _terrain_select))
	_layer_select = _make_spin_box(1.0, 4.0, 1.0)
	_layer_select.value_changed.connect(_on_selected_layer_changed)
	inspector.add_child(_with_label("体素层数", _layer_select))
	_allows_tile = CheckButton.new()
	_allows_tile.text = "Grid 允许块建筑"
	_allows_tile.toggled.connect(_on_selected_permissions_changed)
	inspector.add_child(_allows_tile)
	_allows_edge = CheckButton.new()
	_allows_edge.text = "Grid 允许边建筑"
	_allows_edge.toggled.connect(_on_selected_permissions_changed)
	inspector.add_child(_allows_edge)

	_add_heading(inspector, "同格 Stuff")
	_stuff_list = OptionButton.new()
	_stuff_list.item_selected.connect(_on_stuff_list_selected)
	inspector.add_child(_stuff_list)
	_stuff_facing = _make_spin_box(0.0, 7.0, 1.0)
	_stuff_facing.value_changed.connect(_on_selected_stuff_facing_changed)
	inspector.add_child(_with_label("选中 Stuff 朝向", _stuff_facing))
	_remove_stuff_button = Button.new()
	_remove_stuff_button.text = "移除选中 Stuff"
	_remove_stuff_button.pressed.connect(_remove_selected_stuff)
	inspector.add_child(_remove_stuff_button)

	_add_heading(inspector, "斜坡")
	_ramp_label = Label.new()
	_ramp_label.text = "当前格不属于斜坡"
	_ramp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(_ramp_label)
	_selected_ramp_terrain = OptionButton.new()
	_selected_ramp_terrain.name = "SelectedRampTerrain"
	_fill_ramp_terrain_options(_selected_ramp_terrain)
	_selected_ramp_terrain.item_selected.connect(_on_selected_ramp_terrain_changed)
	inspector.add_child(_with_label("斜坡地形", _selected_ramp_terrain))
	_remove_ramp_button = Button.new()
	_remove_ramp_button.text = "移除当前斜坡"
	_remove_ramp_button.pressed.connect(_remove_selected_ramp)
	inspector.add_child(_remove_ramp_button)
	_set_inspector_enabled(false)


func _sync_level_controls() -> void:
	if _level == null or _shape_select == null:
		return
	_controls_blocked = true
	_shape_select.select(_level.grid_shape)
	_size_x.value = _level.grid_size.x
	_size_y.value = _level.grid_size.y
	_size_y.editable = _level.grid_shape == SQUARE_SHAPE
	_layer_height.value = _level.layer_height
	_default_terrain_select.select(_terrain_index(_level.default_terrain))
	_refresh_direction_options()
	_controls_blocked = false


func _request_grid_rebuild_from_controls(_index: int) -> void:
	_request_grid_rebuild()


func _request_grid_rebuild_from_value(_value: float) -> void:
	_request_grid_rebuild()


func _request_grid_rebuild() -> void:
	if _controls_blocked or _level == null:
		return
	_pending_shape_id = _shape_select.get_selected_id()
	_pending_grid_size = Vector2i(int(_size_x.value), int(_size_y.value))
	if _pending_shape_id == _level.grid_shape and _pending_grid_size == _level.grid_size:
		return
	_grid_confirmation.popup_centered()


func _confirm_grid_rebuild() -> void:
	if _level == null:
		return
	_level.grid_shape = _pending_shape_id
	_level.grid_size = _pending_grid_size
	_rebuild_shape()
	Authoring.rebuild_grid(_level, _shape, _pending_shape_id, _pending_grid_size)
	_sync_level_controls()
	_canvas.set_level(_level)
	_refresh_selected_inspector()
	_set_status("Terrain Grid 已重建；路径、波次和镜头未改动，请重新校验路径端点。", true)
	level_changed.emit()


func _on_layer_height_changed(_value: float) -> void:
	if _controls_blocked or _level == null:
		return
	var model_layer_height := TerrainModelMetricsScript.get_layer_height(_level.grid_cell_size)
	_level.layer_height = model_layer_height
	_level.height_step = model_layer_height
	_level.emit_changed()
	_canvas.refresh()
	level_changed.emit()


func _on_default_terrain_changed(index: int) -> void:
	if _controls_blocked or _level == null or index < 0 or index >= _terrain_options.size():
		return
	_level.default_terrain = _terrain_options[index]
	_level.emit_changed()
	_canvas.refresh()
	level_changed.emit()


func _select_terrain_brush(terrain: TerrainDefinitionScript) -> void:
	_canvas.set_terrain_brush(terrain)
	_set_status("地形刷：%s。左键可连续涂刷，不改变层数、权限或 Stuff。" % terrain.display_name, true)


func _select_layer_brush(layer_count: int) -> void:
	_canvas.set_layer_brush(layer_count)
	_set_status("层数刷：第 %d 层。左键可连续涂刷，不改变 Terrain 或 Stuff。" % layer_count, true)


func _select_permission_brush() -> void:
	_canvas.set_permission_brush(
		_permission_tile_brush.button_pressed,
		_permission_edge_brush.button_pressed
	)
	_set_status("权限刷已启用；只修改 Grid 的两类基础建造权限。", true)


func _select_stuff_brush(definition: StuffDefinitionScript) -> void:
	_canvas.set_stuff_brush(definition, int(_stuff_brush_facing.value))
	_set_status("Stuff 刷：%s。每次点击尝试新增一个实例，互斥规则由定义决定。" % definition.display_name, true)


func _select_ramp_brush() -> void:
	_ensure_ramp_terrain_controls()
	var terrain_override := _ramp_terrain_from_selection(_ramp_terrain)
	_canvas.set_ramp_brush(
		_ramp_direction.get_selected_id(),
		_ramp_length.get_selected_id(),
		_ramp_base_layer.get_selected_id(),
		terrain_override
	)
	var terrain_label := (
		"跟随坡底基底"
		if terrain_override == null
		else terrain_override.display_name
	)
	_set_status("斜坡工具：%s；点击最低坡格，青色轮廓为占格预览。" % terrain_label, true)


func _on_cell_selected(_cell: Vector3i) -> void:
	_refresh_selected_inspector()


func _on_canvas_content_changed() -> void:
	_refresh_selected_inspector()
	level_changed.emit()


func _on_operation_reported(message: String, success: bool) -> void:
	_set_status(message, success)


func _refresh_selected_inspector() -> void:
	_ensure_ramp_terrain_controls()
	if _level == null or _canvas == null or not _canvas.has_selected_cell:
		_set_inspector_enabled(false)
		return
	var cell := _canvas.selected_cell
	var data := Authoring.get_grid_cell(_level, cell)
	var ramp := Authoring.get_ramp_at(_level, _shape, cell)
	var layer_constraint := Authoring.get_ramp_layer_constraint(_level, _shape, cell)
	var related_ramp: RampPlacementData = (
		layer_constraint["ramp"] as RampPlacementData
		if not layer_constraint.is_empty()
		else null
	)
	_controls_blocked = true
	var selected_help := find_child("SelectedCellHelp", true, false) as Label
	if selected_help != null:
		selected_help.text = "cell = %s" % str(cell)
	_terrain_select.select(_terrain_index(data.get_effective_terrain(_level.default_terrain) if data != null else _level.default_terrain))
	_layer_select.value = data.layer_count if data != null else 1
	_allows_tile.button_pressed = data.allows_tile_building if data != null else true
	_allows_edge.button_pressed = data.allows_edge_building if data != null else true
	_stuff_facing.max_value = 5 if _level.grid_shape == HEX_SHAPE else 7
	_stuff_list.clear()
	for placement in Authoring.get_stuff_at(_level, cell):
		var label := "%s | %s" % [
			placement.definition.display_name if placement.definition != null else "无效定义",
			placement.placement_id,
		]
		_stuff_list.add_item(label)
		_stuff_list.set_item_metadata(_stuff_list.item_count - 1, placement.placement_id)
	if _stuff_list.item_count > 0:
		_stuff_list.select(0)
		_sync_selected_stuff_facing()
	if bool(layer_constraint.get("conflict", false)):
		_ramp_label.text = "当前平地同时受到多个互相冲突的斜坡连接约束"
	elif related_ramp == null:
		_ramp_label.text = "当前格不属于斜坡"
	else:
		var ramp_terrain_label := (
			"跟随基底"
			if related_ramp.terrain_override == null
			else related_ramp.terrain_override.display_name
		)
		_ramp_label.text = "%s | %s | 1:%d | 基础层 %d | 上坡方向 %d | 地形 %s" % [
			related_ramp.ramp_id,
			str(layer_constraint["role"]),
			related_ramp.run_length,
			related_ramp.base_layer,
			related_ramp.facing_index,
			ramp_terrain_label,
		]
	if _selected_ramp_terrain != null:
		_selected_ramp_terrain.select(
			_ramp_terrain_selection_index(ramp.terrain_override if ramp != null else null)
		)
	_controls_blocked = false
	_set_inspector_enabled(true)
	_terrain_select.disabled = ramp != null
	_layer_select.editable = layer_constraint.is_empty()
	_remove_ramp_button.disabled = related_ramp == null or bool(layer_constraint.get("conflict", false))
	if _selected_ramp_terrain != null:
		_selected_ramp_terrain.disabled = ramp == null
	_remove_stuff_button.disabled = _stuff_list.item_count == 0
	_stuff_facing.editable = _stuff_list.item_count > 0


func _on_selected_terrain_changed(index: int) -> void:
	if _controls_blocked or not _has_selection() or index < 0 or index >= _terrain_options.size():
		return
	if Authoring.get_ramp_at(_level, _shape, _canvas.selected_cell) != null:
		return
	if Authoring.paint_terrain(_level, _canvas.selected_cell, _terrain_options[index]):
		_canvas.refresh()
		level_changed.emit()


func _on_selected_layer_changed(value: float) -> void:
	if _controls_blocked or not _has_selection():
		return
	if not Authoring.get_ramp_layer_constraint(_level, _shape, _canvas.selected_cell).is_empty():
		return
	if Authoring.paint_layer(_level, _canvas.selected_cell, int(value)):
		_canvas.refresh()
		level_changed.emit()


func _on_selected_ramp_terrain_changed(_index: int) -> void:
	if _controls_blocked or not _has_selection() or _selected_ramp_terrain == null:
		return
	var ramp := Authoring.get_ramp_at(_level, _shape, _canvas.selected_cell)
	if ramp == null:
		return
	var terrain_override := _ramp_terrain_from_selection(_selected_ramp_terrain)
	if Authoring.set_ramp_terrain_override(_level, ramp.ramp_id, terrain_override):
		_canvas.refresh()
		_refresh_selected_inspector()
		_set_status(
			"斜坡 %s 已%s。底层 Grid 地形未改变。" % [
				ramp.ramp_id,
				"恢复跟随基底" if terrain_override == null else "覆盖为 %s" % terrain_override.display_name,
			],
			true
		)
		level_changed.emit()


func _on_selected_permissions_changed(_value: bool) -> void:
	if _controls_blocked or not _has_selection():
		return
	if Authoring.paint_permissions(
		_level,
		_canvas.selected_cell,
		_allows_tile.button_pressed,
		_allows_edge.button_pressed
	):
		_canvas.refresh()
		level_changed.emit()


func _on_stuff_list_selected(_index: int) -> void:
	if _controls_blocked:
		return
	_controls_blocked = true
	_sync_selected_stuff_facing()
	_controls_blocked = false


func _sync_selected_stuff_facing() -> void:
	var placement := _selected_stuff()
	_stuff_facing.value = placement.facing_index if placement != null else 0


func _on_selected_stuff_facing_changed(value: float) -> void:
	if _controls_blocked:
		return
	var placement := _selected_stuff()
	if placement != null and Authoring.set_stuff_facing(_level, placement.placement_id, int(value)):
		_canvas.refresh()
		level_changed.emit()


func _remove_selected_stuff() -> void:
	var placement := _selected_stuff()
	if placement == null:
		return
	if Authoring.remove_stuff(_level, placement.placement_id):
		_canvas.refresh()
		_refresh_selected_inspector()
		_set_status("已移除 Stuff %s。Grid 地形和基础权限不变。" % placement.placement_id, true)
		level_changed.emit()


func _remove_selected_ramp() -> void:
	if not _has_selection():
		return
	var constraint := Authoring.get_ramp_layer_constraint(_level, _shape, _canvas.selected_cell)
	var ramp: RampPlacementData = (
		constraint["ramp"] as RampPlacementData
		if not constraint.is_empty()
		else null
	)
	if ramp != null and Authoring.remove_ramp(_level, ramp.ramp_id):
		_canvas.refresh()
		_refresh_selected_inspector()
		_set_status("已移除斜坡 %s；自动整理过的层数保留，可继续手工调整。" % ramp.ramp_id, true)
		level_changed.emit()


func _selected_stuff() -> StuffPlacementDataScript:
	if not _has_selection() or _stuff_list.selected < 0:
		return null
	var placement_id: StringName = _stuff_list.get_item_metadata(_stuff_list.selected)
	for placement in Authoring.get_stuff_at(_level, _canvas.selected_cell):
		if placement.placement_id == placement_id:
			return placement
	return null


func _set_inspector_enabled(enabled: bool) -> void:
	_ensure_ramp_terrain_controls()
	if _terrain_select == null:
		return
	_terrain_select.disabled = not enabled
	_layer_select.editable = enabled
	_allows_tile.disabled = not enabled
	_allows_edge.disabled = not enabled
	_stuff_list.disabled = not enabled
	_stuff_facing.editable = enabled
	_remove_stuff_button.disabled = not enabled
	_remove_ramp_button.disabled = not enabled
	if _selected_ramp_terrain != null:
		_selected_ramp_terrain.disabled = not enabled


## Godot keeps an existing main-screen plugin instance alive when a @tool
## script is hot-reloaded. Newly added member references are then null even
## though the older UI tree remains valid. Rebind named controls when present,
## or insert only the missing controls into that live tree so the whole
## Inspector cannot be disabled by one optional extension control.
func _ensure_ramp_terrain_controls() -> void:
	if _ramp_terrain == null or not is_instance_valid(_ramp_terrain):
		_ramp_terrain = find_child("RampTerrainBrush", true, false) as OptionButton
	if _ramp_terrain == null and _ramp_base_layer != null and is_instance_valid(_ramp_base_layer):
		var base_group := _ramp_base_layer.get_parent() as Control
		var sidebar := base_group.get_parent() as Container if base_group != null else null
		if sidebar != null:
			_ramp_terrain = OptionButton.new()
			_ramp_terrain.name = "RampTerrainBrush"
			_fill_ramp_terrain_options(_ramp_terrain)
			var terrain_group := _with_label("斜坡地形", _ramp_terrain)
			sidebar.add_child(terrain_group)
			sidebar.move_child(terrain_group, base_group.get_index() + 1)

	if _selected_ramp_terrain == null or not is_instance_valid(_selected_ramp_terrain):
		_selected_ramp_terrain = find_child("SelectedRampTerrain", true, false) as OptionButton
	if _selected_ramp_terrain == null and _ramp_label != null and is_instance_valid(_ramp_label):
		var inspector := _ramp_label.get_parent() as Container
		if inspector != null:
			_selected_ramp_terrain = OptionButton.new()
			_selected_ramp_terrain.name = "SelectedRampTerrain"
			_fill_ramp_terrain_options(_selected_ramp_terrain)
			var terrain_group := _with_label("斜坡地形", _selected_ramp_terrain)
			inspector.add_child(terrain_group)
			inspector.move_child(terrain_group, _ramp_label.get_index() + 1)
	if _selected_ramp_terrain != null:
		var callback := Callable(self, "_on_selected_ramp_terrain_changed")
		if not _selected_ramp_terrain.item_selected.is_connected(callback):
			_selected_ramp_terrain.item_selected.connect(callback)


func _has_selection() -> bool:
	return _level != null and _canvas != null and _canvas.has_selected_cell


func _rebuild_shape() -> void:
	if _level == null:
		_shape = null
		return
	_shape = HexGridShape.new() if _level.grid_shape == HEX_SHAPE else SquareGridShape.new()
	_shape.setup(_level.grid_cell_size)


func _refresh_direction_options() -> void:
	if _ramp_direction == null or _level == null:
		return
	_ramp_direction.clear()
	var count := 6 if _level.grid_shape == HEX_SHAPE else 4
	for direction in range(count):
		_ramp_direction.add_item("方向 %d" % direction, direction)
	_stuff_brush_facing.max_value = 5 if _level.grid_shape == HEX_SHAPE else 7


func _load_terrain_resources() -> Array[TerrainDefinitionScript]:
	var result: Array[TerrainDefinitionScript] = []
	for resource in _load_resources("res://resources/terrains"):
		if resource is TerrainDefinitionScript:
			result.append(resource)
	result.sort_custom(func(a: TerrainDefinitionScript, b: TerrainDefinitionScript) -> bool:
		return a.display_name < b.display_name
	)
	return result


func _load_stuff_resources() -> Array[StuffDefinitionScript]:
	var result: Array[StuffDefinitionScript] = []
	for resource in _load_resources("res://resources/stuffs"):
		if resource is StuffDefinitionScript:
			result.append(resource)
	result.sort_custom(func(a: StuffDefinitionScript, b: StuffDefinitionScript) -> bool:
		return a.display_name < b.display_name
	)
	return result


func _load_resources(directory_path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	var names := PackedStringArray()
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	names.sort()
	for candidate in names:
		var resource := ResourceLoader.load("%s/%s" % [directory_path, candidate])
		if resource != null:
			result.append(resource)
	return result


func _fill_terrain_options(option_button: OptionButton) -> void:
	option_button.clear()
	for terrain in _terrain_options:
		option_button.add_item(terrain.display_name)
		option_button.set_item_tooltip(option_button.item_count - 1, terrain.resource_path)


func _fill_ramp_terrain_options(option_button: OptionButton) -> void:
	option_button.clear()
	option_button.add_item("跟随坡底基底")
	option_button.set_item_tooltip(0, "默认：斜坡整体使用最低坡格的 Grid 地形")
	for terrain in _terrain_options:
		option_button.add_item(terrain.display_name)
		option_button.set_item_tooltip(
			option_button.item_count - 1,
			"覆盖斜坡整体表现：%s（不修改底层 Grid）" % terrain.resource_path
		)


func _ramp_terrain_from_selection(option_button: OptionButton) -> TerrainDefinitionScript:
	if option_button == null or option_button.selected <= 0:
		return null
	var terrain_index := option_button.selected - 1
	return _terrain_options[terrain_index] if terrain_index < _terrain_options.size() else null


func _ramp_terrain_selection_index(terrain: TerrainDefinitionScript) -> int:
	return _terrain_index(terrain) + 1 if terrain != null else 0


func _terrain_index(terrain: TerrainDefinitionScript) -> int:
	if terrain == null:
		return 0
	for index in range(_terrain_options.size()):
		if _terrain_options[index] == terrain or _terrain_options[index].terrain_id == terrain.terrain_id:
			return index
	return 0


func _set_status(message: String, success: bool) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override(
		"font_color",
		Color(0.65, 0.90, 0.72, 1.0) if success else Color(1.0, 0.48, 0.42, 1.0)
	)


func _add_heading(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)


func _with_label(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box


func _make_spin_box(minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin
