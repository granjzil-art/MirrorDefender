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
const BasePointDefinitionScript := preload("res://scripts/path/BasePointDefinition.gd")
const WaveDefinitionScript := preload("res://scripts/wave/WaveDefinition.gd")
const SpawnGroupDefinitionScript := preload("res://scripts/wave/SpawnGroupDefinition.gd")

var _level: LevelResource
var _canvas: Control
var _save_path: LineEdit
var _status: Label
var _m4_status: Label
var _shape_select: OptionButton
var _geometry_tag_label: Label
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
var _tile_preset_options: Array = []
var _tile_height: SpinBox
var _destroy_button: Button
var _palette_button_group := ButtonGroup.new()
var _path_canvas: Variant
var _path_select: OptionButton
var _path_id: LineEdit
var _path_name: LineEdit
var _path_spawn_select: OptionButton
var _path_base_select: OptionButton
var _path_record: CheckButton
var _path_detail: Label
var _path_remove_last: Button
var _path_clear: Button
var _spawn_select: OptionButton
var _spawn_id: LineEdit
var _spawn_name: LineEdit
var _spawn_number: SpinBox
var _spawn_set_cell: Button
var _spawn_remove: Button
var _base_select: OptionButton
var _base_id: LineEdit
var _base_name: LineEdit
var _base_number: SpinBox
var _base_set_cell: Button
var _base_remove: Button
var _shared_base_hp: SpinBox
var _wave_select: OptionButton
var _wave_group_select: OptionButton
var _wave_enemy_select: OptionButton
var _wave_spawn_select: OptionButton
var _wave_path_select: OptionButton
var _wave_count: SpinBox
var _wave_interval: SpinBox
var _wave_delay: SpinBox
var _enemy_options: Array = []
var _undo_redo := UndoRedo.new()
var _undo_button: Button
var _redo_button: Button
var _dirty_indicator: Label
var _confirmation_dialog: ConfirmationDialog
var _pending_confirmation: Callable = Callable()
var _is_dirty: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_create_new_level()

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
	new_button.pressed.connect(_request_new_level)
	toolbar.add_child(new_button)
	var load_button := Button.new()
	load_button.text = "加载"
	load_button.pressed.connect(_show_load_dialog)
	toolbar.add_child(load_button)
	var save_button := Button.new()
	save_button.text = "保存"
	save_button.pressed.connect(_save_level)
	toolbar.add_child(save_button)
	_undo_button = Button.new()
	_undo_button.text = "撤销"
	_undo_button.tooltip_text = "撤销最近一次网格重建"
	_undo_button.pressed.connect(_undo_grid_rebuild)
	toolbar.add_child(_undo_button)
	_redo_button = Button.new()
	_redo_button.text = "重做"
	_redo_button.tooltip_text = "重做最近一次网格重建"
	_redo_button.pressed.connect(_redo_grid_rebuild)
	toolbar.add_child(_redo_button)
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
	_dirty_indicator = Label.new()
	_dirty_indicator.custom_minimum_size = Vector2(72.0, 0.0)
	toolbar.add_child(_dirty_indicator)
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
	_tile_preset_options = _load_tile_presets()
	for option in _tile_preset_options:
		_add_palette_item(sidebar, str(option["label"]), str(option["path"]))
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
	_confirmation_dialog = ConfirmationDialog.new()
	_confirmation_dialog.title = "确认操作"
	_confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirmation_dialog.canceled.connect(_on_confirmation_canceled)
	add_child(_confirmation_dialog)
	_update_history_buttons()
	_set_dirty(false)

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
	_geometry_tag_label = Label.new()
	_geometry_tag_label.tooltip_text = "由网格形状自动派生，运行时建筑朝向与边规则以此为准"
	sidebar.add_child(_with_label("关卡标签", _geometry_tag_label))
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

func _load_tile_presets() -> Array:
	var result: Array = []
	var directory := DirAccess.open("res://resources/tiles")
	if directory == null:
		return result
	var file_names := PackedStringArray()
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	file_names.sort()
	for candidate in file_names:
		var path := "res://resources/tiles/%s" % candidate
		var preset: Resource = ResourceLoader.load(path)
		if preset != null and preset.has_method("make_tile"):
			result.append({
				"label": str(preset.get("display_name")),
				"path": path,
				"preset": preset,
			})
	return result

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
	for option in _tile_preset_options:
		_tile_type_select.add_item(str(option["label"]))
		_tile_type_select.set_item_metadata(_tile_type_select.item_count - 1, option["path"])
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
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(310.0, 0.0)
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(292.0, 0.0)
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 8)
	sidebar_scroll.add_child(sidebar)
	var title := Label.new()
	title.text = "路径、出生点与据点"
	title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(title)

	var spawn_title := Label.new()
	spawn_title.text = "独立出生点"
	spawn_title.add_theme_font_size_override("font_size", 15)
	sidebar.add_child(spawn_title)
	var spawn_buttons := HBoxContainer.new()
	var add_spawn := Button.new()
	add_spawn.text = "添加"
	add_spawn.pressed.connect(_add_spawn_point)
	spawn_buttons.add_child(add_spawn)
	_spawn_remove = Button.new()
	_spawn_remove.text = "删除"
	_spawn_remove.pressed.connect(_remove_selected_spawn_point)
	spawn_buttons.add_child(_spawn_remove)
	sidebar.add_child(spawn_buttons)
	_spawn_select = OptionButton.new()
	_spawn_select.item_selected.connect(_on_spawn_selected)
	sidebar.add_child(_with_label("当前出生点", _spawn_select))
	_spawn_id = LineEdit.new()
	_spawn_id.text_changed.connect(_on_spawn_id_changed)
	sidebar.add_child(_with_label("出生点 ID", _spawn_id))
	_spawn_name = LineEdit.new()
	_spawn_name.text_changed.connect(_on_spawn_name_changed)
	sidebar.add_child(_with_label("出生点名称", _spawn_name))
	_spawn_number = _make_spin_box(1.0, 999.0, 1.0)
	_spawn_number.value_changed.connect(_on_spawn_number_changed)
	sidebar.add_child(_with_label("显示编号", _spawn_number))
	_spawn_set_cell = Button.new()
	_spawn_set_cell.text = "将画布选中格设为出生点"
	_spawn_set_cell.pressed.connect(_set_selected_spawn_cell)
	sidebar.add_child(_spawn_set_cell)

	var base_title := Label.new()
	base_title.text = "共享生命据点"
	base_title.add_theme_font_size_override("font_size", 15)
	sidebar.add_child(base_title)
	var base_buttons := HBoxContainer.new()
	var add_base := Button.new()
	add_base.text = "添加"
	add_base.pressed.connect(_add_base_point)
	base_buttons.add_child(add_base)
	_base_remove = Button.new()
	_base_remove.text = "删除"
	_base_remove.pressed.connect(_remove_selected_base_point)
	base_buttons.add_child(_base_remove)
	sidebar.add_child(base_buttons)
	_base_select = OptionButton.new()
	_base_select.item_selected.connect(_on_base_selected)
	sidebar.add_child(_with_label("当前据点", _base_select))
	_base_id = LineEdit.new()
	_base_id.text_changed.connect(_on_base_id_changed)
	sidebar.add_child(_with_label("据点 ID", _base_id))
	_base_name = LineEdit.new()
	_base_name.text_changed.connect(_on_base_name_changed)
	sidebar.add_child(_with_label("据点名称", _base_name))
	_base_number = _make_spin_box(1.0, 999.0, 1.0)
	_base_number.value_changed.connect(_on_base_number_changed)
	sidebar.add_child(_with_label("显示编号", _base_number))
	_base_set_cell = Button.new()
	_base_set_cell.text = "将画布选中格设为据点"
	_base_set_cell.pressed.connect(_set_selected_base_cell)
	sidebar.add_child(_base_set_cell)
	_shared_base_hp = _make_spin_box(1.0, 1000000.0, 1.0)
	_shared_base_hp.value_changed.connect(_on_shared_base_hp_changed)
	sidebar.add_child(_with_label("共享最大生命", _shared_base_hp))

	var path_title := Label.new()
	path_title.text = "手工路径"
	path_title.add_theme_font_size_override("font_size", 15)
	sidebar.add_child(path_title)
	var path_buttons := HBoxContainer.new()
	var add_path := Button.new()
	add_path.text = "添加路径"
	add_path.pressed.connect(_add_path)
	path_buttons.add_child(add_path)
	var remove_path := Button.new()
	remove_path.text = "删除路径"
	remove_path.pressed.connect(_remove_selected_path)
	path_buttons.add_child(remove_path)
	sidebar.add_child(path_buttons)
	_path_select = OptionButton.new()
	_path_select.item_selected.connect(_on_path_selected)
	sidebar.add_child(_with_label("当前路径", _path_select))
	_path_id = LineEdit.new()
	_path_id.text_changed.connect(_on_path_id_changed)
	sidebar.add_child(_with_label("路径 ID", _path_id))
	_path_name = LineEdit.new()
	_path_name.text_changed.connect(_on_path_name_changed)
	sidebar.add_child(_with_label("路径名称", _path_name))
	_path_spawn_select = OptionButton.new()
	_path_spawn_select.item_selected.connect(_on_path_spawn_selected)
	sidebar.add_child(_with_label("起始出生点", _path_spawn_select))
	_path_base_select = OptionButton.new()
	_path_base_select.item_selected.connect(_on_path_base_selected)
	sidebar.add_child(_with_label("目标据点", _path_base_select))
	_path_record = CheckButton.new()
	_path_record.text = "从出生点开始连续记录格"
	_path_record.button_pressed = false
	sidebar.add_child(_path_record)
	_path_remove_last = Button.new()
	_path_remove_last.text = "移除最后一格"
	_path_remove_last.pressed.connect(_remove_last_path_cell)
	sidebar.add_child(_path_remove_last)
	_path_clear = Button.new()
	_path_clear.text = "清空当前路径"
	_path_clear.pressed.connect(_clear_selected_path)
	sidebar.add_child(_path_clear)
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
	_wave_spawn_select.tooltip_text = "出生点由当前路径自动绑定。"
	form.add_child(_make_form_label("出生点（随路径）"))
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
	form.add_child(_make_form_label("距第一波开始延迟（秒）"))
	form.add_child(_wave_delay)
	var help := Label.new()
	help.text = "第一波手动开始；之后所有出怪组按相对首次点击时刻的延迟自动生成，可跨波次重叠。"
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

func _request_new_level() -> void:
	if _is_dirty:
		_request_confirmation(
			"当前关卡有未保存修改。新建关卡会丢失这些修改，是否继续？",
			_create_new_level
		)
		return
	_create_new_level()

func _create_new_level() -> void:
	var level := LevelResource.new()
	level.grid_shape = HEX_SHAPE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(6, 6)
	level.height_levels = 3
	level.height_step = 0.45
	if _save_path != null:
		_save_path.text = DEFAULT_SAVE_PATH
	_set_level(level)
	level.tiles = _make_default_tiles(level.grid_shape, level.grid_size)
	_set_level(level)
	_undo_redo.clear_history()
	_update_history_buttons()
	_set_dirty(false)
	_status.text = "新关卡已创建。拖拽左侧预制地块到地图。"

func _set_level(value: LevelResource) -> void:
	_level = value
	if _path_record != null:
		_path_record.button_pressed = false
	_set_level_controls_blocked(true)
	_shape_select.select(_level.grid_shape)
	_geometry_tag_label.text = str(_level.get_geometry_tag())
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

func _make_default_tiles(shape_id: int, grid_size: Vector2i) -> Array:
	var result: Array = []
	var shape: IGridShape = HexGridShape.new() if shape_id == HEX_SHAPE else SquareGridShape.new()
	shape.setup(_level.grid_cell_size if _level != null else 1.0)
	var default_preset: Resource = ResourceLoader.load("res://resources/tiles/BuildableTile.tres")
	for cell in shape.enumerate_cells(grid_size):
		var tile: Resource
		if default_preset != null and default_preset.has_method("make_tile"):
			tile = default_preset.call("make_tile", cell, _level.height_levels if _level != null else 1)
		else:
			tile = TileCellDataScript.new()
			tile.call("configure", cell, 0, 0)
		result.append(tile)
	return result

func _duplicate_tiles(source: Array) -> Array:
	var result: Array = []
	for raw_tile in source:
		if raw_tile is Resource:
			result.append((raw_tile as Resource).duplicate(true))
	return result

func _commit_grid_rebuild(shape_id: int, grid_size: Vector2i) -> void:
	if _level == null:
		return
	var before_shape := _level.grid_shape
	var before_size := _level.grid_size
	var before_tiles := _duplicate_tiles(_level.tiles)
	var after_tiles := _make_default_tiles(shape_id, grid_size)
	_undo_redo.create_action("重建关卡网格")
	_undo_redo.add_do_method(_apply_grid_snapshot.bind(shape_id, grid_size, after_tiles))
	_undo_redo.add_undo_method(_apply_grid_snapshot.bind(before_shape, before_size, before_tiles))
	_undo_redo.commit_action()
	_set_dirty(true)
	_update_history_buttons()

func _apply_grid_snapshot(shape_id: int, grid_size: Vector2i, tiles: Array) -> void:
	if _level == null:
		return
	_level.grid_shape = shape_id
	_level.grid_size = grid_size
	_level.tiles = _duplicate_tiles(tiles)
	_level.emit_changed()
	_set_level(_level)

func _restore_grid_controls() -> void:
	if _level == null:
		return
	_set_level_controls_blocked(true)
	_shape_select.select(_level.grid_shape)
	_size_x.value = _level.grid_size.x
	_size_y.value = _level.grid_size.y
	_set_level_controls_blocked(false)

func _on_shape_changed(index: int) -> void:
	if _level == null or index == _level.grid_shape:
		return
	_restore_grid_controls()
	_request_confirmation(
		"切换网格形状会重建全部地块；路径、出生点和波次会保留，但可能需要重新校验。是否继续？",
		_commit_grid_rebuild.bind(index, _level.grid_size)
	)

func _on_grid_size_changed(_value: float) -> void:
	if _level == null:
		return
	var next_size := Vector2i(int(_size_x.value), int(_size_y.value))
	if next_size == _level.grid_size:
		return
	_restore_grid_controls()
	_request_confirmation(
		"修改网格尺寸会重建全部地块；路径、出生点和波次会保留，但可能需要重新校验。是否继续？",
		_commit_grid_rebuild.bind(_level.grid_shape, next_size)
	)

func _on_height_levels_changed(value: float) -> void:
	if _level == null:
		return
	_level.height_levels = int(value)
	_level.clamp_tile_heights()
	_set_dirty(true)
	_refresh_height_brush_options()
	_canvas.call("set_height_brush", -1)
	_canvas.call("refresh")

func _on_height_step_changed(value: float) -> void:
	if _level == null:
		return
	_level.height_step = value
	_mark_level_changed()
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
	_mark_level_changed()
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
	_selected_label.text = "cell = %s" % str(cell)
	_tile_type_select.set_block_signals(true)
	_tile_height.set_block_signals(true)
	_tile_type_select.select(_find_tile_preset_index(tile))
	_tile_height.max_value = maxi(0, _level.height_levels - 1)
	_tile_height.value = int(tile.get("height_level")) if tile != null else 0
	_tile_type_select.set_block_signals(false)
	_tile_height.set_block_signals(false)
	_destroy_button.visible = tile != null and bool(tile.call("is_destructible"))
	_set_inspector_enabled(true)

func _on_tile_type_changed(index: int) -> void:
	var tile := _selected_tile(true)
	if tile == null or index < 0 or index >= _tile_type_select.item_count:
		return
	var preset_path: String = str(_tile_type_select.get_item_metadata(index))
	var preset: Resource = ResourceLoader.load(preset_path)
	if preset == null:
		return
	var definition: Resource = preset.get("definition")
	if definition != null:
		tile.call("set_definition", definition, int(preset.get("tile_type")))
	else:
		tile.call("set_tile_type", int(preset.get("tile_type")))
	_mark_level_changed()
	_destroy_button.visible = bool(tile.call("is_destructible"))
	_canvas.call("refresh")

func _find_tile_preset_index(tile: Resource) -> int:
	if tile == null or _tile_type_select.item_count == 0:
		return 0
	var tile_definition: Resource = tile.get("definition")
	var tile_definition_id: StringName = tile_definition.get("tile_id") if tile_definition != null else &""
	for index in range(_tile_type_select.item_count):
		var preset: Resource = ResourceLoader.load(str(_tile_type_select.get_item_metadata(index)))
		if preset == null:
			continue
		var preset_definition: Resource = preset.get("definition")
		if tile_definition != null and preset_definition != null and preset_definition.get("tile_id") == tile_definition_id:
			return index
		if tile_definition == null and preset_definition == null and int(preset.get("tile_type")) == int(tile.get("tile_type")):
			return index
	return 0

func _on_tile_height_changed(value: float) -> void:
	var tile := _selected_tile(true)
	if tile == null:
		return
	tile.call("set_height_level", int(value), _level.height_levels)
	_mark_level_changed()
	_canvas.call("refresh")

func _destroy_selected_obstacle() -> void:
	var tile := _selected_tile()
	if tile == null or not bool(tile.call("destroy_obstacle")):
		return
	_mark_level_changed()
	_destroy_button.visible = false
	_canvas.call("refresh")

func _selected_tile(create_default: bool = false) -> Resource:
	if _level == null or not _canvas.has_selected_cell:
		return null
	var tile: Resource = _level.get_tile(_canvas.selected_cell)
	if tile == null and create_default:
		tile = TileCellDataScript.new()
		tile.call("configure", _canvas.selected_cell, 0, 0)
		_level.store_tile(tile)
	return tile

func _on_layout_changed() -> void:
	if _canvas.has_selected_cell:
		_on_cell_selected(_canvas.selected_cell)
	_mark_level_changed()

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


func _get_selected_spawn_point() -> SpawnPointDefinition:
	if _level == null or _spawn_select == null:
		return null
	var index := _spawn_select.get_selected_id()
	if index < 0 or index >= _level.spawn_points.size():
		return null
	return _level.spawn_points[index]


func _get_selected_base_point() -> BasePointDefinitionScript:
	if _base_select == null or _base_select.selected < 0:
		return null
	var value: Variant = _base_select.get_item_metadata(_base_select.selected)
	return value as BasePointDefinitionScript if value is BasePointDefinitionScript else null

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
		_set_dirty(true)

func _set_dirty(value: bool) -> void:
	_is_dirty = value
	if _dirty_indicator != null:
		_dirty_indicator.text = "未保存" if _is_dirty else "已保存"
		_dirty_indicator.tooltip_text = "当前关卡包含未保存修改" if _is_dirty else "当前关卡已保存或尚未修改"

func _request_confirmation(message: String, action: Callable, confirm_text: String = "继续") -> void:
	if _confirmation_dialog == null:
		return
	_pending_confirmation = action
	_confirmation_dialog.dialog_text = message
	_confirmation_dialog.get_ok_button().text = confirm_text
	_confirmation_dialog.popup_centered(Vector2i(560, 180))

func _on_confirmation_confirmed() -> void:
	var action := _pending_confirmation
	_pending_confirmation = Callable()
	if action.is_valid():
		action.call()

func _on_confirmation_canceled() -> void:
	_pending_confirmation = Callable()

func _undo_grid_rebuild() -> void:
	if not _undo_redo.has_undo():
		return
	_undo_redo.undo()
	_set_dirty(true)
	_update_history_buttons()

func _redo_grid_rebuild() -> void:
	if not _undo_redo.has_redo():
		return
	_undo_redo.redo()
	_set_dirty(true)
	_update_history_buttons()

func _update_history_buttons() -> void:
	if _undo_button != null:
		_undo_button.disabled = not _undo_redo.has_undo()
	if _redo_button != null:
		_redo_button.disabled = not _undo_redo.has_redo()

func _refresh_path_controls() -> void:
	if _path_select == null:
		return
	_refresh_spawn_controls()
	_refresh_base_controls()
	var previous_index := _path_select.get_selected_id()
	_path_select.set_block_signals(true)
	_path_select.clear()
	if _level != null:
		for index in range(_level.paths.size()):
			var path := _level.paths[index]
			var label := _get_path_option_label(path)
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
	var resolved_spawn: SpawnPointDefinition = _level.resolve_path_spawn_point(path) if _level != null else null
	var resolved_base: BasePointDefinitionScript = _level.resolve_path_target_base(path) if _level != null else null
	_refresh_resource_options(
		_path_spawn_select,
		_level.spawn_points if _level != null else [],
		resolved_spawn,
		"无出生点"
	)
	_refresh_resource_options(
		_path_base_select,
		_level.get_effective_base_points() if _level != null else [],
		resolved_base,
		"无据点"
	)
	_path_id.editable = has_path
	_path_name.editable = has_path
	_path_spawn_select.disabled = not has_path
	_path_base_select.disabled = not has_path
	_path_remove_last.disabled = not has_path or path.cells.is_empty()
	_path_clear.disabled = not has_path or path.cells.is_empty()
	var path_cell_count: int = 0
	var path_start_text := "-"
	var path_end_text := "-"
	if path != null:
		path_cell_count = path.cells.size()
		if not path.cells.is_empty():
			path_start_text = str(path.get_start_cell())
			path_end_text = str(path.get_end_cell())
	var spawn_text := _get_spawn_option_label(resolved_spawn) if resolved_spawn != null else "未建立"
	var base_text := _get_base_option_label(resolved_base) if resolved_base != null else "未建立"
	_path_detail.text = "格数：%d\n起点：%s\n终点：%s\n出生点：%s\n目标据点：%s" % [
		path_cell_count,
		path_start_text,
		path_end_text,
		spawn_text,
		base_text,
	]
	_refresh_path_overlay()


func _refresh_spawn_controls() -> void:
	if _spawn_select == null:
		return
	var previous_index := _spawn_select.get_selected_id()
	_spawn_select.set_block_signals(true)
	_spawn_select.clear()
	if _level != null:
		for index in range(_level.spawn_points.size()):
			_spawn_select.add_item(_get_spawn_option_label(_level.spawn_points[index]), index)
	if _spawn_select.item_count > 0:
		_spawn_select.select(clampi(previous_index, 0, _spawn_select.item_count - 1))
	_spawn_select.set_block_signals(false)
	var spawn := _get_selected_spawn_point()
	_spawn_id.set_block_signals(true)
	_spawn_name.set_block_signals(true)
	_spawn_number.set_block_signals(true)
	_spawn_id.text = str(spawn.spawn_id) if spawn != null else ""
	_spawn_name.text = spawn.display_name if spawn != null else ""
	_spawn_number.value = _level.get_spawn_display_number(spawn) if _level != null and spawn != null else 1
	_spawn_id.set_block_signals(false)
	_spawn_name.set_block_signals(false)
	_spawn_number.set_block_signals(false)
	var enabled := spawn != null
	_spawn_id.editable = enabled
	_spawn_name.editable = enabled
	_spawn_number.editable = enabled
	_spawn_set_cell.disabled = not enabled or _path_canvas == null or not _path_canvas.has_selected_cell
	_spawn_remove.disabled = not enabled


func _refresh_base_controls() -> void:
	if _base_select == null:
		return
	var previous_id := _base_select.get_selected_id()
	_base_select.set_block_signals(true)
	_base_select.clear()
	if _level != null:
		var effective_bases := _level.get_effective_base_points()
		for index in range(effective_bases.size()):
			var base_point: BasePointDefinitionScript = effective_bases[index]
			_base_select.add_item(_get_base_option_label(base_point), index)
			_base_select.set_item_metadata(_base_select.item_count - 1, base_point)
	if _base_select.item_count > 0:
		_base_select.select(clampi(previous_id, 0, _base_select.item_count - 1))
	_base_select.set_block_signals(false)
	var base_point := _get_selected_base_point()
	_base_id.set_block_signals(true)
	_base_name.set_block_signals(true)
	_base_number.set_block_signals(true)
	_shared_base_hp.set_block_signals(true)
	_base_id.text = str(base_point.base_id) if base_point != null else ""
	_base_name.text = base_point.display_name if base_point != null else ""
	_base_number.value = _level.get_base_display_number(base_point) if _level != null and base_point != null else 1
	_shared_base_hp.value = _level.base_max_hp if _level != null else 100.0
	_base_id.set_block_signals(false)
	_base_name.set_block_signals(false)
	_base_number.set_block_signals(false)
	_shared_base_hp.set_block_signals(false)
	var enabled := base_point != null
	_base_id.editable = enabled
	_base_name.editable = enabled
	_base_number.editable = enabled
	_shared_base_hp.editable = _level != null
	_base_set_cell.disabled = not enabled or _path_canvas == null or not _path_canvas.has_selected_cell
	_base_remove.disabled = not enabled or (_level != null and _level.get_effective_base_points().size() <= 1)

func _refresh_path_overlay() -> void:
	if _path_canvas != null and _level != null:
		_path_canvas.call(
			"set_m4_overlay",
			_level.paths,
			_level.spawn_points,
			_level.get_effective_base_points(),
			_get_selected_path()
		)


func _add_spawn_point() -> void:
	if _level == null or _path_canvas == null or not _path_canvas.has_selected_cell:
		_status.text = "请先在路径画布选择出生点所在格。"
		return
	var spawn := SpawnPointDefinitionScript.new()
	var number := _next_spawn_number()
	spawn.spawn_id = StringName("spawn_%d" % number)
	spawn.display_name = "出生点 %d" % number
	spawn.display_number = number
	spawn.cell = _path_canvas.selected_cell
	_level.spawn_points.append(spawn)
	_mark_level_changed()
	_refresh_path_controls()
	_spawn_select.select(_spawn_select.item_count - 1)
	_refresh_path_controls()
	_status.text = "已添加出生点 %d；多条路径可以共用。" % number


func _remove_selected_spawn_point() -> void:
	var spawn := _get_selected_spawn_point()
	if _level == null or spawn == null:
		return
	for path in _level.paths:
		if path != null and _level.resolve_path_spawn_point(path) == spawn:
			_status.text = "无法删除：%s 正被路径 %s 引用。" % [spawn.display_name, path.display_name]
			return
	_level.spawn_points.erase(spawn)
	for wave in _level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group != null and group.spawn_point == spawn:
				group.spawn_point = null
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()


func _on_spawn_selected(_index: int) -> void:
	_refresh_path_controls()


func _on_spawn_id_changed(value: String) -> void:
	var spawn := _get_selected_spawn_point()
	if spawn == null:
		return
	spawn.spawn_id = StringName(value.strip_edges())
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()


func _on_spawn_name_changed(value: String) -> void:
	var spawn := _get_selected_spawn_point()
	if spawn == null:
		return
	spawn.display_name = value.strip_edges()
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()


func _on_spawn_number_changed(value: float) -> void:
	var spawn := _get_selected_spawn_point()
	if spawn == null:
		return
	spawn.display_number = int(value)
	_mark_level_changed()
	_refresh_path_controls()


func _set_selected_spawn_cell() -> void:
	var spawn := _get_selected_spawn_point()
	if spawn == null or _path_canvas == null or not _path_canvas.has_selected_cell:
		return
	spawn.cell = _path_canvas.selected_cell
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()


func _add_base_point() -> void:
	if _level == null or _path_canvas == null or not _path_canvas.has_selected_cell:
		_status.text = "请先在路径画布选择据点所在格。"
		return
	_ensure_authored_base_points()
	var base_point := BasePointDefinitionScript.new()
	var number := _next_base_number()
	base_point.base_id = StringName("base_%d" % number)
	base_point.display_name = "据点 %d" % number
	base_point.display_number = number
	base_point.cell = _path_canvas.selected_cell
	_level.base_points.append(base_point)
	_mark_level_changed()
	_refresh_path_controls()
	_base_select.select(_base_select.item_count - 1)
	_refresh_path_controls()
	_status.text = "已添加据点 %d；全部据点共享生命。" % number


func _remove_selected_base_point() -> void:
	if _level == null:
		return
	var selected := _get_selected_base_point()
	if selected == null:
		return
	_ensure_authored_base_points()
	var base_point := _find_authored_base(selected.base_id, selected.cell)
	if base_point == null or _level.base_points.size() <= 1:
		_status.text = "关卡必须至少保留一个据点。"
		return
	for path in _level.paths:
		if path != null and _level.resolve_path_target_base(path) == base_point:
			_status.text = "无法删除：%s 正被路径 %s 引用。" % [base_point.display_name, path.display_name]
			return
	_level.base_points.erase(base_point)
	_mark_level_changed()
	_refresh_path_controls()


func _on_base_selected(_index: int) -> void:
	_refresh_path_controls()


func _on_base_id_changed(value: String) -> void:
	var base_point := _materialize_selected_base()
	if base_point == null:
		return
	base_point.base_id = StringName(value.strip_edges())
	_mark_level_changed()
	_refresh_path_controls()


func _on_base_name_changed(value: String) -> void:
	var base_point := _materialize_selected_base()
	if base_point == null:
		return
	base_point.display_name = value.strip_edges()
	_mark_level_changed()
	_refresh_path_controls()


func _on_base_number_changed(value: float) -> void:
	var base_point := _materialize_selected_base()
	if base_point == null:
		return
	base_point.display_number = int(value)
	_mark_level_changed()
	_refresh_path_controls()


func _set_selected_base_cell() -> void:
	var base_point := _materialize_selected_base()
	if base_point == null or _path_canvas == null or not _path_canvas.has_selected_cell:
		return
	base_point.cell = _path_canvas.selected_cell
	if _level.base_points.size() == 1:
		_level.base_cell = base_point.cell
	_mark_level_changed()
	_refresh_path_controls()


func _on_shared_base_hp_changed(value: float) -> void:
	if _level == null:
		return
	_level.base_max_hp = value
	_mark_level_changed()


func _ensure_authored_base_points() -> void:
	if _level == null or not _level.base_points.is_empty():
		return
	var base_point := BasePointDefinitionScript.new()
	base_point.base_id = &"base_1"
	base_point.display_name = "据点 1"
	base_point.display_number = 1
	base_point.cell = _level.base_cell
	_level.base_points.append(base_point)
	for path in _level.paths:
		if path != null and path.target_base == null and not path.cells.is_empty() and path.get_end_cell() == _level.base_cell:
			path.target_base = base_point


func _materialize_selected_base() -> BasePointDefinitionScript:
	if _level == null:
		return null
	var selected := _get_selected_base_point()
	if selected == null:
		return null
	var selected_id: StringName = selected.base_id
	var selected_cell: Vector3i = selected.cell
	_ensure_authored_base_points()
	return _find_authored_base(selected_id, selected_cell)


func _find_authored_base(base_id: StringName, cell: Vector3i) -> BasePointDefinitionScript:
	if _level == null:
		return null
	for base_point in _level.base_points:
		if base_point != null and (base_point.base_id == base_id or base_point.cell == cell):
			return base_point
	return null


func _next_spawn_number() -> int:
	var used: Dictionary = {}
	if _level != null:
		for spawn in _level.spawn_points:
			if spawn != null:
				used[_level.get_spawn_display_number(spawn)] = true
	var number := 1
	while used.has(number) or (_level != null and _level.get_spawn_point(StringName("spawn_%d" % number)) != null):
		number += 1
	return number


func _next_base_number() -> int:
	var used: Dictionary = {}
	if _level != null:
		for base_point in _level.get_effective_base_points():
			if base_point != null:
				used[_level.get_base_display_number(base_point)] = true
	var number := 1
	while used.has(number) or (_level != null and _level.get_base_point(StringName("base_%d" % number)) != null):
		number += 1
	return number

func _add_path() -> void:
	if _level == null:
		return
	var path: PathDefinition = PathDefinitionScript.new()
	var number := _get_next_path_number()
	path.path_id = StringName("path_%d" % number)
	path.display_name = "路径 %d" % number
	if not _level.spawn_points.is_empty():
		path.spawn_point = _level.spawn_points[0]
	var bases := _level.get_effective_base_points()
	if not bases.is_empty() and not _level.base_points.is_empty():
		path.target_base = bases[0]
	_level.paths.append(path)
	_mark_level_changed()
	_refresh_path_controls()
	_path_select.select(_path_select.item_count - 1)
	_refresh_path_controls()


func _remove_selected_path() -> void:
	var path := _get_selected_path()
	if _level == null or path == null:
		return
	for wave in _level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group != null and group.path == path:
				_status.text = "无法删除：路径 %s 正被波次引用。" % path.display_name
				return
	_level.paths.erase(path)
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()
	_path_select.select(_path_select.item_count - 1)
	_path_record.button_pressed = true
	_refresh_path_controls()

func _on_path_selected(_index: int) -> void:
	_refresh_path_controls()


func _on_path_spawn_selected(index: int) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	var spawn := _get_selected_resource(_path_spawn_select, index) as SpawnPointDefinition
	path.spawn_point = spawn
	for wave in _level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group != null and group.path == path:
				group.spawn_point = spawn
	_mark_level_changed()
	if spawn != null and not path.cells.is_empty() and path.get_start_cell() != spawn.cell:
		_status.text = "路径首格与新出生点不一致，请清空后重新记录或修正路径。"
	_refresh_path_controls()
	_refresh_wave_group_controls()


func _on_path_base_selected(index: int) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	var selected := _get_selected_resource(_path_base_select, index) as BasePointDefinitionScript
	if selected != null and not _level.base_points.has(selected):
		var selected_id: StringName = selected.base_id
		var selected_cell: Vector3i = selected.cell
		_ensure_authored_base_points()
		selected = _find_authored_base(selected_id, selected_cell)
	path.target_base = selected
	_mark_level_changed()
	if selected != null and not path.cells.is_empty() and path.get_end_cell() != selected.cell:
		_status.text = "路径末格与新目标据点不一致，请继续记录到据点或修正路径。"
	_refresh_path_controls()

func _on_path_id_changed(value: String) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.path_id = StringName(value.strip_edges())
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()

func _on_path_name_changed(value: String) -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.display_name = value.strip_edges()
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()

func _on_path_canvas_selected(_cell: Vector3i) -> void:
	_refresh_path_controls()

func _on_path_canvas_clicked(cell: Vector3i) -> void:
	if _path_record == null or not _path_record.button_pressed:
		return
	var path := _get_selected_path()
	if path == null:
		_status.text = "请先添加并选择一条路径。"
		return
	var path_spawn := _level.resolve_path_spawn_point(path)
	var path_base := _level.resolve_path_target_base(path)
	if path_spawn == null or path_base == null:
		_status.text = "请先为路径选择起始出生点和目标据点。"
		return
	if path.cells.is_empty():
		path.cells.append(path_spawn.cell)
	if not path.cells.is_empty() and path.cells.back() == cell:
		_mark_level_changed()
		_refresh_path_controls()
		return
	var cells_to_append: Array[Vector3i] = [cell]
	if not path.cells.is_empty():
		var shape: IGridShape = HexGridShape.new() if _level.grid_shape == HEX_SHAPE else SquareGridShape.new()
		shape.setup(_level.grid_cell_size)
		var previous_cell: Vector3i = path.cells.back()
		cells_to_append = _get_path_cells_to_append(shape, previous_cell, cell)
		if cells_to_append.is_empty():
			_status.text = "未添加：%s 与路径末格 %s 不相邻。" % [str(cell), str(previous_cell)]
			return
	path.cells.append_array(cells_to_append)
	if path.cells.back() == path_base.cell:
		_path_record.button_pressed = false
		_status.text = "路径已到达 %s，停止记录。" % _level.get_base_marker_label(path_base)
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()

func _get_path_cells_to_append(
	shape: IGridShape,
	previous_cell: Vector3i,
	target_cell: Vector3i
) -> Array[Vector3i]:
	if shape.get_neighbors(previous_cell).has(target_cell):
		return [target_cell]
	if not shape is SquareGridShape or previous_cell.z != 0 or target_cell.z != 0:
		return []
	var step := Vector3i.ZERO
	if previous_cell.x == target_cell.x:
		step.y = signi(target_cell.y - previous_cell.y)
	elif previous_cell.y == target_cell.y:
		step.x = signi(target_cell.x - previous_cell.x)
	else:
		return []
	if step == Vector3i.ZERO:
		return []
	var result: Array[Vector3i] = []
	var current := previous_cell + step
	while current != target_cell:
		result.append(current)
		current += step
	result.append(target_cell)
	return result

func _normalize_square_path_gaps(level: LevelResource) -> int:
	if level == null or level.grid_shape != GridManager.Shape.SQUARE:
		return 0
	var shape := SquareGridShape.new()
	shape.setup(level.grid_cell_size)
	var inserted_cells := 0
	for path in level.paths:
		if path == null or path.cells.size() < 2:
			continue
		var normalized: Array[Vector3i] = [path.cells[0]]
		for index in range(1, path.cells.size()):
			var previous_cell: Vector3i = normalized.back()
			var target_cell: Vector3i = path.cells[index]
			var segment := _get_path_cells_to_append(shape, previous_cell, target_cell)
			if segment.is_empty():
				normalized.append(target_cell)
				continue
			inserted_cells += maxi(0, segment.size() - 1)
			normalized.append_array(segment)
		path.cells = normalized
	if inserted_cells > 0:
		level.emit_changed()
	return inserted_cells

func _remove_last_path_cell() -> void:
	var path := _get_selected_path()
	if path == null or path.cells.is_empty():
		return
	path.cells.pop_back()
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()

func _clear_selected_path() -> void:
	var path := _get_selected_path()
	if path == null:
		return
	path.cells.clear()
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_group_controls()

func _set_base_from_path_selection() -> void:
	_set_selected_base_cell()

func _add_spawn_from_path() -> void:
	if _level == null:
		return
	var path := _get_selected_path()
	if path == null or path.cells.is_empty():
		return
	var spawn := _sync_spawn_for_path(path)
	if spawn == null:
		return
	_mark_level_changed()
	_refresh_path_controls()
	_refresh_wave_controls()
	_status.text = "已为 %s 关联独立出生点。" % path.display_name

func _get_next_path_number() -> int:
	if _level == null:
		return 1
	var number := _level.paths.size() + 1
	while true:
		var path_id := StringName("path_%d" % number)
		if _level.get_path_by_id(path_id) == null:
			return number
		number += 1
	return number

func _sync_spawn_for_path(path: PathDefinition, known_spawn: SpawnPointDefinition = null) -> SpawnPointDefinition:
	if _level == null or path == null:
		return null
	var spawn := known_spawn
	if spawn == null:
		var candidates := _level.get_spawn_point_candidates_for_path(path)
		if candidates.size() > 1:
			_status.text = "未同步：%s 对应多个出生点，请先清理旧关卡的重复引用。" % path.display_name
			return null
		if candidates.size() == 1:
			spawn = candidates[0]
	if spawn == null:
		spawn = SpawnPointDefinitionScript.new()
		var number := _next_spawn_number()
		spawn.spawn_id = StringName("spawn_%d" % number)
		spawn.display_name = "出生点 %d" % number
		spawn.display_number = number
		spawn.cell = path.get_start_cell() if not path.cells.is_empty() else Vector3i.ZERO
		_level.spawn_points.append(spawn)
	path.spawn_point = spawn
	return spawn

func _get_path_option_label(path: PathDefinition) -> String:
	if path == null:
		return "(空路径)"
	var display_name := path.display_name.strip_edges()
	if display_name.is_empty():
		display_name = "未命名路径"
	return "%s [%s]" % [display_name, str(path.path_id)]

func _get_spawn_option_label(spawn: SpawnPointDefinition) -> String:
	if spawn == null:
		return "(空出生点)"
	var display_name := spawn.display_name.strip_edges()
	if display_name.is_empty():
		display_name = "未关联出生点"
	var number := _level.get_spawn_display_number(spawn) if _level != null else spawn.display_number
	return "%s · 出生点%d [%s]" % [display_name, number, str(spawn.spawn_id)]


func _get_base_option_label(base_point: BasePointDefinitionScript) -> String:
	if base_point == null:
		return "(空据点)"
	var display_name := base_point.display_name.strip_edges()
	if display_name.is_empty():
		display_name = "未命名据点"
	var number := _level.get_base_display_number(base_point) if _level != null else base_point.display_number
	return "%s · 据点%d [%s]" % [display_name, number, str(base_point.base_id)]

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
	var resolved_spawn := _level.resolve_group_spawn_point(group) if _level != null and group != null else null
	_refresh_resource_options(_wave_spawn_select, _level.spawn_points if _level != null else [], resolved_spawn, "无出生点")
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
	_wave_spawn_select.disabled = true
	_wave_path_select.disabled = not has_group
	_wave_count.editable = has_group
	_wave_interval.editable = has_group
	_wave_delay.editable = has_group

func _refresh_resource_options(option: OptionButton, resources: Array, selected: Resource, empty_label: String) -> void:
	option.set_block_signals(true)
	option.clear()
	option.add_item(empty_label, -1)
	var selected_index := 0
	for raw_resource in resources:
		if not raw_resource is Resource:
			continue
		var resource: Resource = raw_resource
		var label := _get_resource_option_label(resource)
		option.add_item(label)
		var item_index := option.item_count - 1
		option.set_item_metadata(item_index, resource)
		if resource == selected:
			selected_index = item_index
	option.select(selected_index)
	option.set_block_signals(false)

func _get_resource_option_label(resource: Resource) -> String:
	if resource is PathDefinition:
		return _get_path_option_label(resource as PathDefinition)
	if resource is SpawnPointDefinition:
		return _get_spawn_option_label(resource as SpawnPointDefinition)
	if resource is BasePointDefinitionScript:
		return _get_base_option_label(resource as BasePointDefinitionScript)
	if not resource.resource_path.is_empty():
		return resource.resource_path.get_file().get_basename()
	var display_name: Variant = resource.get("display_name")
	return str(display_name) if display_name != null else "未命名资源"

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
	result.sort_custom(_sort_resources_by_path)
	return result

func _sort_resources_by_path(a: Resource, b: Resource) -> bool:
	if a == null:
		return false
	if b == null:
		return true
	return a.resource_path.naturalnocasecmp_to(b.resource_path) < 0

func _get_selected_resource(option: OptionButton, index: int) -> Resource:
	if option == null or index <= 0 or index >= option.item_count:
		return null
	var value: Variant = option.get_item_metadata(index)
	return value if value is Resource else null

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
	if _level != null and not _level.paths.is_empty():
		group.path = _level.paths[0]
		group.spawn_point = _level.resolve_path_spawn_point(group.path)
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
		group.enemy = _get_selected_resource(_wave_enemy_select, index) as EnemyDefinition
		_mark_level_changed()

func _on_wave_path_selected(index: int) -> void:
	var group := _get_selected_spawn_group()
	if group != null:
		var selected_path := _get_selected_resource(_wave_path_select, index) as PathDefinition
		var paired_spawn := _level.resolve_path_spawn_point(selected_path) if selected_path != null else null
		group.path = selected_path
		group.spawn_point = paired_spawn
		_mark_level_changed()
		_refresh_wave_group_controls()
		if group.path != null and group.spawn_point == null:
			_status.text = "当前路径没有唯一出生点，请到路径页同步。"

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
	dialog.file_selected.connect(_on_load_dialog_file_selected.bind(dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_file_dialog()

func _on_load_dialog_file_selected(path: String, dialog: EditorFileDialog) -> void:
	dialog.queue_free()
	if _is_dirty:
		_request_confirmation(
			"当前关卡有未保存修改。加载其他关卡会丢失这些修改，是否继续？",
			_load_level_file.bind(path),
			"加载"
		)
		return
	_load_level_file(path)

func _load_level_file(path: String) -> void:
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	if resource is LevelResource:
		var inserted_path_cells := _normalize_square_path_gaps(resource)
		_set_level(resource)
		_save_path.text = path
		_undo_redo.clear_history()
		_update_history_buttons()
		_set_dirty(inserted_path_cells > 0)
		if inserted_path_cells > 0:
			_status.text = "已加载 %s，并补齐 %d 个四边形路径中间格；请保存关卡。" % [path, inserted_path_cells]
		else:
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
	var validation_errors := _level.validate_runtime()
	if not validation_errors.is_empty():
		_request_confirmation(
			"当前关卡校验失败：\n%s\n\n仍要作为未完成关卡保存吗？" % "\n".join(validation_errors),
			_save_level_to_path.bind(path),
			"仍然保存"
		)
		return
	_save_level_to_path(path)

func _save_level_to_path(path: String) -> void:
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
	_set_dirty(false)
	_status.text = "已保存 %s" % path
