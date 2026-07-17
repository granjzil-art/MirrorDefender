@tool
extends Control

const HEX_SHAPE := 0
const SQUARE_SHAPE := 1
const DEFAULT_SAVE_PATH := "res://resources/levels/CustomLevel.tres"
const PALETTE_ITEMS := [
	{"label": "可建造", "path": "res://resources/tiles/BuildableTile.tres"},
	{"label": "可破坏障碍", "path": "res://resources/tiles/DestructibleTile.tres"},
	{"label": "不可建造路面", "path": "res://resources/tiles/BlockedTile.tres"},
]
const PaletteItem := preload("res://addons/mirror_tile_editor/tile_palette_item.gd")
const TileEditorCanvas := preload("res://addons/mirror_tile_editor/tile_editor_canvas.gd")
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")

var _level: LevelResource
var _canvas: Control
var _save_path: LineEdit
var _status: Label
var _shape_select: OptionButton
var _size_x: SpinBox
var _size_y: SpinBox
var _height_levels: SpinBox
var _height_step: SpinBox
var _height_color_low: ColorPickerButton
var _height_color_middle: ColorPickerButton
var _height_color_high: ColorPickerButton
var _inspector: VBoxContainer
var _selected_label: Label
var _tile_type_select: OptionButton
var _tile_height: SpinBox
var _destroy_button: Button
var _palette_button_group := ButtonGroup.new()

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
	title.text = "Mirror 地块编辑器"
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

	var splitter := HSplitContainer.new()
	splitter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(splitter)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(250.0, 0.0)
	sidebar.add_theme_constant_override("separation", 8)
	splitter.add_child(sidebar)
	_add_level_controls(sidebar)
	var palette_title := Label.new()
	palette_title.text = "地块调色板"
	palette_title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(palette_title)
	for item in PALETTE_ITEMS:
		var palette_item := PaletteItem.new()
		var label: String = item.label
		var path: String = item.path
		palette_item.configure(label, path, _palette_button_group)
		palette_item.pressed.connect(_on_brush_selected.bind(path))
		sidebar.add_child(palette_item)
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
	_set_level_controls_blocked(false)
	_canvas.call("set_level", _level)
	_set_inspector_enabled(false)

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
	_status.text = "画笔已选择。可在地图上左键拖动涂刷。"

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
	var resource: Resource = ResourceLoader.load(path)
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
