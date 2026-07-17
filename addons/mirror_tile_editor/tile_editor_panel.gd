@tool
extends Control

const HEX_SHAPE := 0
const SQUARE_SHAPE := 1
const DEFAULT_SAVE_PATH := "res://resources/levels/CustomLevel.tres"
const PaletteItem := preload("res://addons/mirror_tile_editor/tile_palette_item.gd")
const TileEditorCanvas := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")
const PathDefinitionScript := preload("res://scripts/path/PathDefinition.gd")
const SpawnPointDefinitionScript := preload("res://scripts/path/SpawnPointDefinition.gd")
const WaveDefinitionScript := preload("res://scripts/wave/WaveDefinition.gd")
const SpawnGroupDefinitionScript := preload("res://scripts/wave/SpawnGroupDefinition.gd")

var _level: LevelResource
var _canvas: Control
var _save_path: LineEdit
var _status: Label
var _m4_status: Label
var _shape_select: OptionButton
var _size_x: SpinBox
var _size_y: SpinBox
var _height_levels: SpinBox
var _height_step: SpinBox
var _height_color_low: ColorPickerButton
var _height_color_middle: ColorPickerButton
var _height_color_high: ColorPickerButton
var _height_brush_select: OptionButton
var _inspector: VBoxContainer
var _selected_label: Label
var _tile_type_select: OptionButton
var _tile_height: SpinBox
var _destroy_button: Button
var _palette_button_group := ButtonGroup.new()
var _path_canvas: Variant
var _path_select: OptionButton
var _path_id: LineEdit
var _path_name: LineEdit
var _path_record: CheckButton
var _path_detail: Label
var _path_remove_last: Button
var _path_clear: Button
var _path_set_base: Button
var _path_add_spawn: Button
var _wave_select: OptionButton
var _wave_group_select: OptionButton
var _wave_enemy_select: OptionButton
var _wave_spawn_select: OptionButton
var _wave_path_select: OptionButton
var _wave_count: SpinBox
var _wave_interval: SpinBox
var _wave_delay: SpinBox
var _enemy_options: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_new_level()

func _build_interface() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "Mirror 关卡编辑器"
	title.add_theme_font_size_override("font_size", 20)
	title.custom_minimum_size = Vector2(180.0, 0.0)
	toolbar.add_child(title)
	var new_button := Button.new()
	new_button.text = "新建"
	new_button.pressed.connect(_new_level)
	toolbar.add_child(new_button)
	var load_button := Button.new()
	load_button.text = "加载"
	load_button.pressed.connect(_show_load_dialog)
	toolbar.add_child(load_button)
	var save_button := Button.new()
	save_button.text = "保存"
	save_button.pressed.connect(_save_level)
	toolbar.add_child(save_button)
	var reset_view_button := Button.new()
	reset_view_button.icon = get_theme_icon("Reload", "EditorIcons")
	reset_view_button.tooltip_text = "重置编辑视角"
	reset_view_button.pressed.connect(_reset_canvas_view)
	toolbar.add_child(reset_view_button)
	_save_path = LineEdit.new()
	_save_path.text = DEFAULT_SAVE_PATH
	_save_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_path.tooltip_text = "关卡资源保存路径"
	toolbar.add_child(_save_path)
	_m4_status = Label.new()
	_m4_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_m4_status.add_theme_color_override("font_color", Color(0.65, 0.77, 0.88, 1.0))
	root.add_child(_m4_status)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var splitter := HSplitContainer.new()
	splitter.name = "地块"
	splitter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(splitter)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(250.0, 0.0)
	sidebar.add_theme_constant_override("separation", 8)
	splitter.add_child(sidebar)
	_add_level_controls(sidebar)
	_add_height_brush_controls(sidebar)
	var palette_title := Label.new()
	palette_title.text = "地块调色板"
	palette_title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(palette_title)
	_add_palette_item(sidebar, "可建造", "res://resources/tiles/BuildableTile.tres")
	_add_palette_item(sidebar, "可破坏障碍", "res://resources/tiles/DestructibleTile.tres")
	_add_palette_item(sidebar, "不可建造路面", "res://resources/tiles/BlockedTile.tres")
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.65, 0.77, 0.88, 1.0))
	sidebar.add_child(_status)

	_canvas = TileEditorCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.cell_selected.connect(_on_cell_selected)
	_canvas.layout_changed.connect(_on_layout_changed)
	splitter.add_child(_canvas)

	_inspector = VBoxContainer.new()
	_inspector.custom_minimum_size = Vector2(245.0, 0.0)
	_inspector.add_theme_constant_override("separation", 8)
	splitter.add_child(_inspector)
	_add_inspector_controls()
	_add_path_tab(tabs)
	_add_wave_tab(tabs)

func _add_level_controls(sidebar: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "地图参数"
	title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(title)
	_shape_select = OptionButton.new()
	_shape_select.add_item("六边形 flat-top", HEX_SHAPE)
	_shape_select.add_item("正方形", SQUARE_SHAPE)
	_shape_select.item_selected.connect(_on_shape_changed)
	sidebar.add_child(_with_label("网格形状", _shape_select))
	_size_x = _make_spin_box(1.0, 20.0, 1.0)
	_size_x.value_changed.connect(_on_grid_size_changed)
	sidebar.add_child(_with_label("半径 / 列数", _size_x))
	_size_y = _make_spin_box(1.0, 20.0, 1.0)
	_size_y.value_changed.connect(_on_grid_size_changed)
	sidebar.add_child(_with_label("行数（六边形忽略）", _size_y))
	_height_levels = _make_spin_box(1.0, 16.0, 1.0)
	_height_levels.value_changed.connect(_on_height_levels_changed)
	sidebar.add_child(_with_label("高度档数", _height_levels))
	_height_step = _make_spin_box(0.05, 5.0, 0.05)
	_height_step.value_changed.connect(_on_height_step_changed)
	sidebar.add_child(_with_label("每档世界高度", _height_step))
	_add_terrain_color_controls(sidebar)

func _add_palette_item(sidebar: VBoxContainer, label: String, path: String) -> void:
	var palette_item := PaletteItem.new()
	palette_item.configure(label, path, _palette_button_group)
	palette_item.pressed.connect(_on_brush_selected.bind(path))
	sidebar.add_child(palette_item)

func _add_terrain_color_controls(sidebar: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "高度配色"
	title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(title)
	_height_color_low = _make_color_picker()
	_height_color_low.color_changed.connect(_on_height_color_changed.bind(0))
	sidebar.add_child(_with_label("下层", _height_color_low))
	_height_color_middle = _make_color_picker()
	_height_color_middle.color_changed.connect(_on_height_color_changed.bind(1))
	sidebar.add_child(_with_label("中层", _height_color_middle))
	_height_color_high = _make_color_picker()
	_height_color_high.color_changed.connect(_on_height_color_changed.bind(2))
	sidebar.add_child(_with_label("上层", _height_color_high))

func _add_height_brush_controls(sidebar: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "高度刷"
	title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(title)
	_height_brush_select = OptionButton.new()
	_height_brush_select.item_selected.connect(_on_height_brush_changed)
	sidebar.add_child(_with_label("目标高度", _height_brush_select))
	_refresh_height_brush_options()

func _add_inspector_controls() -> void:
	var title := Label.new()
	title.text = "单格参数"
	title.add_theme_font_size_override("font_size", 16)
	_inspector.add_child(title)
	_selected_label = Label.new()
	_selected_label.text = "选择地图中的一格"
	_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(_selected_label)
	_tile_type_select = OptionButton.new()
	_tile_type_select.add_item("可建造", 0)
	_tile_type_select.add_item("可破坏障碍", 1)
	_tile_type_select.add_item("不可建造路面", 2)
	_tile_type_select.item_selected.connect(_on_tile_type_changed)
	_inspector.add_child(_with_label("地块类型", _tile_type_select))
	_tile_height = _make_spin_box(0.0, 15.0, 1.0)
	_tile_height.value_changed.connect(_on_tile_height_changed)
	_inspector.add_child(_with_label("高度档", _tile_height))
	_destroy_button = Button.new()
	_destroy_button.text = "清除障碍"
	_destroy_button.pressed.connect(_destroy_selected_obstacle)
	_inspector.add_child(_destroy_button)
	_set_inspector_enabled(false)

func _add_path_tab(tabs: TabContainer) -> void:
	var page := HSplitContainer.new()
	page.name = "路径"
	tabs.add_child(page)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(260.0, 0.0)
	sidebar.add_theme_constant_override("separation", 8)
	page.add_child(sidebar)
	var title := Label.new()
	title.text = "路径与出生点"
	title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(title)
	var add_path := Button.new()
	add_path.text = "添加路径"
	add_path.pressed.connect(_add_path)
	sidebar.add_child(add_path)
	_path_select = OptionButton.new()
	_path_select.item_selected.connect(_on_path_selected)
	sidebar.add_child(_with_label("当前路径", _path_select))
	_path_id = LineEdit.new()
	_path_id.text_changed.connect(_on_path_id_changed)
	sidebar.add_child(_with_label("路径 ID", _path_id))
	_path_name = LineEdit.new()
	_path_name.text_changed.connect(_on_path_name_changed)
	sidebar.add_child(_with_label("路径名称", _path_name))
	_path_record = CheckButton.new()
	_path_record.text = "点击地图连续记录格"
	_path_record.button_pressed = true
	sidebar.add_child(_path_record)
	_path_remove_last = Button.new()
	_path_remove_last.text = "移除最后一格"
	_path_remove_last.pressed.connect(_remove_last_path_cell)
	sidebar.add_child(_path_remove_last)
	_path_clear = Button.new()
	_path_clear.text = "清空当前路径"
	_path_clear.pressed.connect(_clear_selected_path)
	sidebar.add_child(_path_clear)
	_path_set_base = Button.new()
	_path_set_base.text = "将选中格设为据点"
	_path_set_base.pressed.connect(_set_base_from_path_selection)
	sidebar.add_child(_path_set_base)
	_path_add_spawn = Button.new()
	_path_add_spawn.text = "按路径起点添加出生点"
	_path_add_spawn.pressed.connect(_add_spawn_from_path)
	sidebar.add_child(_path_add_spawn)
	var validate_button := Button.new()
	validate_button.text = "校验 M4 关卡"
	validate_button.pressed.connect(_validate_m4_level)
	sidebar.add_child(validate_button)
	_path_detail = Label.new()
	_path_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_path_detail)
	_path_canvas = TileEditorCanvas.new()
	_path_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_path_canvas.cell_selected.connect(_on_path_canvas_selected)
	_path_canvas.path_cell_clicked.connect(_on_path_canvas_clicked)
	_path_canvas.call("set_path_edit_enabled", true)
	page.add_child(_path_canvas)

func _add_wave_tab(tabs: TabContainer) -> void:
	var page := VBoxContainer.new()
	page.name = "波次"
	page.add_theme_constant_override("separation", 8)
	tabs.add_child(page)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	page.add_child(toolbar)
	var add_wave := Button.new()
	add_wave.text = "添加波次"
	add_wave.pressed.connect(_add_wave)
	toolbar.add_child(add_wave)
	var remove_wave := Button.new()
	remove_wave.text = "删除当前波次"
	remove_wave.pressed.connect(_remove_selected_wave)
	toolbar.add_child(remove_wave)
	var add_group := Button.new()
	add_group.text = "添加出怪组"
	add_group.pressed.connect(_add_spawn_group)
	toolbar.add_child(add_group)
	var remove_group := Button.new()
	remove_group.text = "删除当前出怪组"
	remove_group.pressed.connect(_remove_selected_spawn_group)
	toolbar.add_child(remove_group)
	var validate_button := Button.new()
	validate_button.text = "校验 M4 关卡"
	validate_button.pressed.connect(_validate_m4_level)
	toolbar.add_child(validate_button)
	var form := GridContainer.new()
	form.columns = 2
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(form)
	_wave_select = OptionButton.new()
	_wave_select.item_selected.connect(_on_wave_selected)
	form.add_child(_make_form_label("波次"))
	form.add_child(_wave_select)
	_wave_group_select = OptionButton.new()
	_wave_group_select.item_selected.connect(_on_wave_group_selected)
	form.add_child(_make_form_label("出怪组"))
	form.add_child(_wave_group_select)
	_wave_enemy_select = OptionButton.new()
	_wave_enemy_select.item_selected.connect(_on_wave_enemy_selected)
	form.add_child(_make_form_label("敌人"))
	form.add_child(_wave_enemy_select)
	_wave_spawn_select = OptionButton.new()
	_wave_spawn_select.item_selected.connect(_on_wave_spawn_selected)
	form.add_child(_make_form_label("出生点"))
	form.add_child(_wave_spawn_select)
	_wave_path_select = OptionButton.new()
	_wave_path_select.item_selected.connect(_on_wave_path_selected)
	form.add_child(_make_form_label("路径"))
	form.add_child(_wave_path_select)
	_wave_count = _make_spin_box(1.0, 10000.0, 1.0)
	_wave_count.value_changed.connect(_on_wave_count_changed)
	form.add_child(_make_form_label("数量"))
	form.add_child(_wave_count)
	_wave_interval = _make_spin_box(0.01, 1000.0, 0.01)
	_wave_interval.value_changed.connect(_on_wave_interval_changed)
	form.add_child(_make_form_label("出怪间隔（秒）"))
	form.add_child(_wave_interval)
	_wave_delay = _make_spin_box(0.0, 10000.0, 0.1)
	_wave_delay.value_changed.connect(_on_wave_delay_changed)
	form.add_child(_make_form_label("组开始延迟（秒）"))
	form.add_child(_wave_delay)
	var help := Label.new()
	help.text = "路径页先绘制路线并添加出生点；波次中的每个出怪组直接选择敌人、出生点和路径。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(help)

func _make_form_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label

func _with_label(label_text: String, control: Control) -> VBoxContainer:
	var container := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	container.add_child(control)
	return container

func _make_spin_box(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = step
	spin_box.allow_greater = true
	return spin_box

func _make_color_picker() -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(0.0, 30.0)
	return picker

func _new_level() -> void:
	var level := LevelResource.new()
	level.grid_shape = HEX_SHAPE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(6, 6)
	level.height_levels = 3
	level.height_step = 0.45
	_set_level(level)
	_populate_default_tiles()
	_status.text = "新关卡已创建。拖拽左侧预制地块到地图。"

func _set_level(value: LevelResource) -> void:
	_level = value
	_set_level_controls_blocked(true)
	_shape_select.select(_level.grid_shape)
	_size_x.value = _level.grid_size.x
	_size_y.value = _level.grid_size.y
	_height_levels.value = _level.height_levels
	_height_step.value = _level.height_step
	_height_color_low.color = _level.height_color_low
	_height_color_middle.color = _level.height_color_middle
	_height_color_high.color = _level.height_color_high
	_refresh_height_brush_options()
	_set_level_controls_blocked(false)
	_canvas.call("set_level", _level)
	if _path_canvas != null:
		_path_canvas.call("set_level", _level)
	_set_inspector_enabled(false)
	_refresh_path_controls()
	_refresh_wave_controls()

func _set_level_controls_blocked(blocked: bool) -> void:
	_shape_select.set_block_signals(blocked)
	_size_x.set_block_signals(blocked)
	_size_y.set_block_signals(blocked)
	_height_levels.set_block_signals(blocked)
	_height_step.set_block_signals(blocked)

func _populate_default_tiles() -> void:
	if _level == null:
		return
	_level.clear_tiles()
	var shape: IGridShape = HexGridShape.new() if _level.grid_shape == HEX_SHAPE else SquareGridShape.new()
	shape.setup(_level.grid_cell_size)
	for cell in shape.enumerate_cells(_level.grid_size):
		var tile: Resource = TileCellDataScript.new()
		tile.call("configure", cell, 0, 0)
		_level.store_tile(tile)
	_canvas.call("refresh")

func _on_shape_changed(index: int) -> void:
	if _level == null:
		return
	_level.grid_shape = index
	_populate_default_tiles()

func _on_grid_size_changed(_value: float) -> void:
	if _level == null:
		return
	_level.grid_size = Vector2i(int(_size_x.value), int(_size_y.value))
	_populate_default_tiles()

func _on_height_levels_changed(value: float) -> void:
	if _level == null:
		return
	_level.height_levels = int(value)
	_level.clamp_tile_heights()
	_refresh_height_brush_options()
	_canvas.call("set_height_brush", -1)
	_canvas.call("refresh")

func _on_height_step_changed(value: float) -> void:
	if _level == null:
		return
	_level.height_step = value
	_level.emit_changed()
	_canvas.call("refresh")

func _on_height_color_changed(color: Color, color_stop: int) -> void:
	if _level == null:
		return
	match color_stop:
		0:
			_level.height_color_low = color
		1:
			_level.height_color_middle = color
		2:
			_level.height_color_high = color
	_level.emit_changed()
	_canvas.call("refresh")

func _on_brush_selected(preset_path: String) -> void:
	_canvas.call("set_brush_preset", preset_path)
	_height_brush_select.select(0)
	_status.text = "画笔已选择。可在地图上左键拖动涂刷。"

func _refresh_height_brush_options() -> void:
	if _height_brush_select == null:
		return
	_height_brush_select.clear()
	_height_brush_select.add_item("关闭", -1)
	if _level != null:
		for height_level in range(_level.height_levels):
			_height_brush_select.add_item("高度 %d" % height_level, height_level)
	_height_brush_select.select(0)

func _on_height_brush_changed(index: int) -> void:
	if _level == null:
		return
	var height_level := _height_brush_select.get_item_id(index)
	_canvas.call("set_height_brush", height_level)
	if height_level < 0:
		_status.text = "高度刷已关闭。"
	else:
		_status.text = "高度刷已选择。左键拖动只修改高度。"

func _reset_canvas_view() -> void:
	_canvas.call("reset_view")

func _on_cell_selected(cell: Vector3i) -> void:
	if _level == null:
		return
	var tile: Resource = _level.get_tile(cell)
	if tile == null:
		return
	_selected_label.text = "cell = %s" % str(cell)
	_tile_type_select.select(int(tile.get("tile_type")))
	_tile_height.max_value = maxi(0, _level.height_levels - 1)
	_tile_height.value = int(tile.get("height_level"))
	_destroy_button.visible = bool(tile.call("is_destructible"))
	_set_inspector_enabled(true)

func _on_tile_type_changed(index: int) -> void:
	var tile := _selected_tile()
	if tile == null:
		return
	tile.call("set_tile_type", index)
	_level.emit_changed()
	_destroy_button.visible = bool(tile.call("is_destructible"))
	_canvas.call("refresh")

func _on_tile_height_changed(value: float) -> void:
	var tile := _selected_tile()
	if tile == null:
		return
	tile.call("set_height_level", int(value), _level.height_levels)
	_level.emit_changed()
	_canvas.call("refresh")

func _destroy_selected_obstacle() -> void:
	var tile := _selected_tile()
	if tile == null or not bool(tile.call("destroy_obstacle")):
		return
	_level.emit_changed()
	_destroy_button.visible = false
	_canvas.call("refresh")

func _selected_tile() -> Resource:
	if _level == null or not _canvas.has_selected_cell:
		return null
	return _level.get_tile(_canvas.selected_cell)

func _on_layout_changed() -> void:
	if _canvas.has_selected_cell:
		_on_cell_selected(_canvas.selected_cell)
	_level.emit_changed()

func _set_inspector_enabled(enabled: bool) -> void:
	_tile_type_select.disabled = not enabled
	_tile_height.editable = enabled
	_destroy_button.disabled = not enabled
	if not enabled:
		_destroy_button.visible = false

func _get_selected_path() -> PathDefinition:
	if _level == null or _path_select == null:
		return null
	var index := _path_select.get_selected_id()
	if index < 0 or index >= _level.paths.size():
		return null
	return _level.paths[index]

func _get_selected_wave() -> WaveDefinition:
	if _level == null or _wave_select == null:
		return null
	var index := _wave_select.get_selected_id()
	if index < 0 or index >= _level.waves.size():
		return null
	return _level.waves[index]

func _get_selected_spawn_group() -> SpawnGroupDefinition:
	var wave := _get_selected_wave()
	if wave == null or _wave_group_select == null:
		return null
	var index := _wave_group_select.get_selected_id()
	if index < 0 or index >= wave.spawn_groups.size():
		return null
	return wave.spawn_groups[index]

func _mark_level_changed() -> void:
	if _level != null:
		_level.emit_changed()

func _refresh_path_controls() -> void:
	if _path_select == null:
		return
	var previous_index := _path_select.get_selected_id()
	_path_select.set_block_signals(true)
	_path_select.clear()
	if _level != null:
		for index in range(_level.paths.size()):
			var path := _level.paths[index]
			var label := path.display_name if path != null else "(空路径)"
			_path_select.add_item(label, index)
	if _path_select.item_count > 0:
		_path_select.select(clampi(previous_index, 0, _path_select.item_count - 1))
	_path_select.set_block_signals(false)
	var path := _get_selected_path()
	_path_id.set_block_signals(true)
	_path_name.set_block_signals(true)
	_path_id.text = str(path.path_id) if path != null else ""
	_path_name.text = path.display_name if path != null else ""
	_path_id.set_block_signals(false)
	_path_name.set_block_signals(false)
	var has_path := path != null
	_path_id.editable = has_path
	_path_name.editable = has_path
	_path_remove_last.disabled = not has_path or path.cells.is_empty()
	_path_clear.disabled = not has_path or path.cells.is_empty()
	_path_set_base.disabled = not (_path_canvas != null and _path_canvas.has_selected_cell)
	_path_add_spawn.disabled = not has_path or path.cells.is_empty()
	var path_cell_count: int = 0
	var path_start_text := "-"
	var path_end_text := "-"
	if path != null:
		path_cell_count = path.cells.size()
		if not path.cells.is_empty():
			path_start_text = str(path.get_start_cell())
			path_end_text = str(path.get_end_cell())
	var spawn_count: int = _level.spawn_points.size() if _level != null else 0
	_path_detail.text = "格数：%d\n起点：%s\n终点：%s\n出生点：%d" % [path_cell_count, path_start_text, path_end_text, spawn_count]
	_refresh_path_overlay()

func _refresh_path_overlay() -> void:
	if _path_canvas != null and _level != null:
		_path_canvas.call("set_m4_overlay", _level.paths, _level.spawn_points, _level.base_cell, _get_selected_path())

func _add_path() -> void:
	if _level == null:
		return
	var path: PathDefinition = PathDefinitionScript.new()
	var number := _level.paths.size() + 1
	path.path_id = StringName("path_%d" % number)
	path.display_name = "路径 %d" % number
	_level.paths.append(path)
	_mark_level_changed()
	_refresh_path_controls()
	_path_select.select(_path_select.item_count - 1)
	_refresh_path_controls()

func _on_path_selected(_index: int) -> void:
	_refresh_path_controls()

func _on_path_id_changed(value: String) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.path_id = StringName(value.strip_edges())
	_mark_level_changed()
	_refresh_path_controls()

func _on_path_name_changed(value: String) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.display_name = value.strip_edges()
	_mark_level_changed()
	_refresh_path_controls()

func _on_path_canvas_selected(_cell: Vector3i) -> void:
	_refresh_path_controls()

func _on_path_canvas_clicked(cell: Vector3i) -> void:
	if _path_record == null or not _path_record.button_pressed:
		return
	var path := _get_selected_path()
	if path == null:
		_status.text = "请先添加并选择一条路径。"
		return
	if not path.cells.is_empty() and path.cells.back() == cell:
		return
	path.cells.append(cell)
	_mark_level_changed()
	_refresh_path_controls()

func _remove_last_path_cell() -> void:
	var path := _get_selected_path()
	if path == null or path.cells.is_empty():
		return
	path.cells.pop_back()
	_mark_level_changed()
	_refresh_path_controls()

func _clear_selected_path() -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.cells.clear()
	_mark_level_changed()
	_refresh_path_controls()

func _set_base_from_path_selection() -> void:
	if _level == null or _path_canvas == null or not _path_canvas.has_selected_cell:
		return
	_level.base_cell = _path_canvas.selected_cell
	_mark_level_changed()
	_refresh_path_controls()

func _add_spawn_from_path() -> void:
	if _level == null:
		return
	var path := _get_selected_path()
	if path == null or path.cells.is_empty():
		return
	var spawn: SpawnPointDefinition = SpawnPointDefinitionScript.new()
	var number := _level.spawn_points.size() + 1
	spawn.spawn_id = StringName("spawn_%d" % number)
	spawn.display_name = "入口 %d" % number
	spawn.cell = path.get_start_cell()
	_level.spawn_points.append(spawn)
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_controls()

func _validate_m4_level() -> void:
	if _level == null:
		return
	var errors := _level.validate_m4()
	var message := "M4 校验通过。" if errors.is_empty() else "M4 校验失败：\n%s" % "\n".join(errors)
	_status.text = message
	_m4_status.text = message

func _refresh_wave_controls() -> void:
	if _wave_select == null:
		return
	_enemy_options = _load_enemy_definitions()
	var previous_wave := _wave_select.get_selected_id()
	_wave_select.set_block_signals(true)
	_wave_select.clear()
	if _level != null:
		for index in range(_level.waves.size()):
			var wave := _level.waves[index]
			_wave_select.add_item(wave.display_name if wave != null else "(空波次)", index)
	if _wave_select.item_count > 0:
		_wave_select.select(clampi(previous_wave, 0, _wave_select.item_count - 1))
	_wave_select.set_block_signals(false)
	_refresh_wave_group_controls()

func _refresh_wave_group_controls() -> void:
	var wave := _get_selected_wave()
	var previous_group := _wave_group_select.get_selected_id()
	_wave_group_select.set_block_signals(true)
	_wave_group_select.clear()
	if wave != null:
		for index in range(wave.spawn_groups.size()):
			_wave_group_select.add_item("出怪组 %d" % (index + 1), index)
	if _wave_group_select.item_count > 0:
		_wave_group_select.select(clampi(previous_group, 0, _wave_group_select.item_count - 1))
	_wave_group_select.set_block_signals(false)
	var group := _get_selected_spawn_group()
	_refresh_resource_options(_wave_enemy_select, _enemy_options, group.enemy if group != null else null, "无敌人")
	_refresh_resource_options(_wave_spawn_select, _level.spawn_points if _level != null else [], group.spawn_point if group != null else null, "无出生点")
	_refresh_resource_options(_wave_path_select, _level.paths if _level != null else [], group.path if group != null else null, "无路径")
	_wave_count.set_block_signals(true)
	_wave_interval.set_block_signals(true)
	_wave_delay.set_block_signals(true)
	_wave_count.value = group.count if group != null else 1.0
	_wave_interval.value = group.interval if group != null else 0.8
	_wave_delay.value = group.start_delay if group != null else 0.0
	_wave_count.set_block_signals(false)
	_wave_interval.set_block_signals(false)
	_wave_delay.set_block_signals(false)
	var has_group := group != null
	_wave_enemy_select.disabled = not has_group
	_wave_spawn_select.disabled = not has_group
	_wave_path_select.disabled = not has_group
	_wave_count.editable = has_group
	_wave_interval.editable = has_group
	_wave_delay.editable = has_group

func _refresh_resource_options(option: OptionButton, resources: Array, selected: Resource, empty_label: String) -> void:
	option.set_block_signals(true)
	option.clear()
	option.add_item(empty_label, -1)
	var selected_index := 0
	for index in range(resources.size()):
		var resource: Resource = resources[index]
		var label: String = resource.resource_path.get_file().get_basename() if not resource.resource_path.is_empty() else str(resource.get("display_name"))
		option.add_item(label, index)
		if resource == selected:
			selected_index = index + 1
	option.select(selected_index)
	option.set_block_signals(false)

func _load_enemy_definitions() -> Array:
	var result: Array = []
	var directory := DirAccess.open("res://resources/enemies")
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			var resource: Resource = ResourceLoader.load("res://resources/enemies/%s" % file_name)
			if resource is EnemyDefinition:
				result.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()
	return result

func _add_wave() -> void:
	if _level == null:
		return
	var wave: WaveDefinition = WaveDefinitionScript.new()
	wave.display_name = "第 %d 波" % (_level.waves.size() + 1)
	_level.waves.append(wave)
	_mark_level_changed()
	_refresh_wave_controls()
	_wave_select.select(_wave_select.item_count - 1)
	_refresh_wave_group_controls()

func _remove_selected_wave() -> void:
	var index := _wave_select.get_selected_id()
	if _level == null or index < 0 or index >= _level.waves.size():
		return
	_level.waves.remove_at(index)
	_mark_level_changed()
	_refresh_wave_controls()

func _add_spawn_group() -> void:
	var wave := _get_selected_wave()
	if wave == null:
		_status.text = "请先添加并选择一波。"
		return
	var group: SpawnGroupDefinition = SpawnGroupDefinitionScript.new()
	if not _enemy_options.is_empty():
		group.enemy = _enemy_options[0]
	if _level != null and not _level.spawn_points.is_empty():
		group.spawn_point = _level.spawn_points[0]
	if _level != null and not _level.paths.is_empty():
		group.path = _level.paths[0]
	wave.spawn_groups.append(group)
	_mark_level_changed()
	_refresh_wave_group_controls()
	_wave_group_select.select(_wave_group_select.item_count - 1)
	_refresh_wave_group_controls()

func _remove_selected_spawn_group() -> void:
	var wave := _get_selected_wave()
	var index := _wave_group_select.get_selected_id()
	if wave == null or index < 0 or index >= wave.spawn_groups.size():
		return
	wave.spawn_groups.remove_at(index)
	_mark_level_changed()
	_refresh_wave_group_controls()

func _on_wave_selected(_index: int) -> void:
	_refresh_wave_group_controls()

func _on_wave_group_selected(_index: int) -> void:
	_refresh_wave_group_controls()

func _on_wave_enemy_selected(index: int) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.enemy = _enemy_options[index - 1] if index > 0 and index - 1 < _enemy_options.size() else null
		_mark_level_changed()

func _on_wave_spawn_selected(index: int) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.spawn_point = _level.spawn_points[index - 1] if index > 0 and index - 1 < _level.spawn_points.size() else null
		_mark_level_changed()

func _on_wave_path_selected(index: int) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.path = _level.paths[index - 1] if index > 0 and index - 1 < _level.paths.size() else null
		_mark_level_changed()

func _on_wave_count_changed(value: float) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.count = int(value)
		_mark_level_changed()

func _on_wave_interval_changed(value: float) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.interval = value
		_mark_level_changed()

func _on_wave_delay_changed(value: float) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		group.start_delay = value
		_mark_level_changed()

func _show_load_dialog() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.add_filter("*.tres ; LevelResource")
	dialog.file_selected.connect(_load_level_file)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_file_dialog()

func _load_level_file(path: String) -> void:
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if resource is LevelResource:
		_set_level(resource)
		_save_path.text = path
		_status.text = "已加载 %s" % path
	else:
		_status.text = "加载失败：不是 LevelResource"

func _save_level() -> void:
	if _level == null:
		return
	var path := _save_path.text.strip_edges()
	if not path.begins_with("res://"):
		_status.text = "保存路径必须位于 res://"
		return
	if not path.ends_with(".tres"):
		path += ".tres"
		_save_path.text = path
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		_status.text = "无法创建保存目录"
		return
	var save_error := ResourceSaver.save(_level, path)
	if save_error != OK:
		_status.text = "保存失败：%s" % error_string(save_error)
		return
	EditorInterface.get_resource_filesystem().scan()
	_status.text = "已保存 %s" % path
