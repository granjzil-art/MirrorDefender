@tool
## Editor-only management window for the explicit StuffCatalog registry.
## New kinds are data-authored here and immediately become available to both
## the runtime editor and Terrain/Stuff palette after a successful save.
class_name StuffCatalogManager
extends Window

const AuthoringScript := preload("res://scripts/stuff/StuffCatalogAuthoring.gd")
const StuffCatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")

const CATALOG_PATH := "res://resources/stuffs/StuffCatalog.tres"
const LEVEL_DIRECTORY := "res://resources/levels"

signal catalog_changed

var _authoring := AuthoringScript.new()
var _catalog: StuffCatalog
var _selected: StuffDefinition
var _list: ItemList
var _status: Label
var _id_edit: LineEdit
var _name_edit: LineEdit
var _description_edit: TextEdit
var _enabled: CheckButton
var _exclusive: CheckButton
var _blocks_tile: CheckButton
var _blocks_edge: CheckButton
var _blocks_ballistics: CheckButton
var _blocks_path: CheckButton
var _navigation_airborne: CheckButton
var _destructible: CheckButton
var _durability: SpinBox
var _model_picker: EditorResourcePicker
var _icon_picker: EditorResourcePicker
var _effect_picker: EditorResourcePicker
var _scale_x: SpinBox
var _scale_y: SpinBox
var _scale_z: SpinBox
var _fallback_kind: OptionButton
var _fallback_color: ColorPickerButton
var _save_button: Button
var _remove_button: Button
var _syncing := false
var _dirty := false
var _close_confirmation: ConfirmationDialog


func _ready() -> void:
	title = "关卡元素库"
	min_size = Vector2i(900, 650)
	size = Vector2i(980, 720)
	transient = true
	exclusive = false
	close_requested.connect(_on_close_requested)
	_build_interface()
	_load_catalog()


func open_manager() -> void:
	if not is_node_ready():
		await ready
	_load_catalog()
	popup_centered(size)


func get_catalog() -> StuffCatalog:
	return _catalog


func _build_interface() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var help := Label.new()
	help.text = "目录顺序即运行时与关卡编辑器的工具栏顺序。禁用只隐藏新建入口，不会破坏已有引用。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(help)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 260.0
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_list_selected)
	left.add_child(_list)
	var create_row := HBoxContainer.new()
	left.add_child(create_row)
	_add_button(create_row, "新建", _create_definition)
	_add_button(create_row, "复制", _duplicate_definition)
	_add_button(create_row, "上移", _move_selected.bind(-1))
	_add_button(create_row, "下移", _move_selected.bind(1))
	_remove_button = _add_button(left, "从目录移除（不删除资源）", _remove_definition)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 7)
	scroll.add_child(form)

	_add_heading(form, "身份与目录")
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "仅小写英文、数字、下划线"
	_id_edit.text_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("稳定 ID", _id_edit))
	_name_edit = LineEdit.new()
	_name_edit.text_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("显示名称", _name_edit))
	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size.y = 72.0
	_description_edit.text_changed.connect(_on_form_changed)
	form.add_child(_with_label("功能说明", _description_edit))
	_enabled = _make_check("允许在创作工具中使用", _on_form_changed)
	form.add_child(_enabled)

	_add_heading(form, "放置与路径")
	_exclusive = _make_check("与同格其他元素互斥", _on_form_changed)
	_blocks_tile = _make_check("阻止块建筑", _on_form_changed)
	_blocks_edge = _make_check("阻止边建筑", _on_form_changed)
	_blocks_ballistics = _make_check("阻挡激光与投射物", _on_form_changed)
	_blocks_path = _make_check("阻挡敌人路径", _on_form_changed)
	_navigation_airborne = _make_check("路径阻挡对空中敌人有效", _on_form_changed)
	form.add_child(_exclusive)
	form.add_child(_blocks_tile)
	form.add_child(_blocks_edge)
	form.add_child(_blocks_ballistics)
	form.add_child(_blocks_path)
	form.add_child(_navigation_airborne)

	_add_heading(form, "耐久")
	_destructible = _make_check("可被敌人破坏", _on_form_changed)
	form.add_child(_destructible)
	_durability = _make_spin(1.0, 1000000.0, 1.0)
	_durability.value_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("最大耐久", _durability))

	_add_heading(form, "模型与图标")
	_model_picker = EditorResourcePicker.new()
	_model_picker.base_type = "PackedScene"
	_model_picker.resource_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("模型场景", _model_picker))
	var scale_row := HBoxContainer.new()
	_scale_x = _make_scale_spin()
	_scale_y = _make_scale_spin()
	_scale_z = _make_scale_spin()
	for spin in [_scale_x, _scale_y, _scale_z]:
		spin.value_changed.connect(_on_form_changed.unbind(1))
		scale_row.add_child(spin)
	form.add_child(_with_label("运行时 Scale（X / Y / Z）", scale_row))
	_icon_picker = EditorResourcePicker.new()
	_icon_picker.base_type = "Texture2D"
	_icon_picker.resource_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("UI 图标", _icon_picker))

	_add_heading(form, "灰盒回退与高级效果")
	_fallback_kind = OptionButton.new()
	for label in ["无", "通用障碍", "尖刺", "空洞", "岩石", "树"]:
		_fallback_kind.add_item(label)
	_fallback_kind.item_selected.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("无模型时的灰盒", _fallback_kind))
	_fallback_color = ColorPickerButton.new()
	_fallback_color.color_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("灰盒颜色", _fallback_color))
	_effect_picker = EditorResourcePicker.new()
	_effect_picker.base_type = "TileEffect"
	_effect_picker.resource_changed.connect(_on_form_changed.unbind(1))
	form.add_child(_with_label("高级玩法效果（可选）", _effect_picker))

	var footer := HBoxContainer.new()
	root.add_child(footer)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status)
	_save_button = _add_button(footer, "保存元素与目录", _save_selected)

	_close_confirmation = ConfirmationDialog.new()
	_close_confirmation.title = "放弃未保存修改"
	_close_confirmation.dialog_text = "关卡元素库存在未保存修改。放弃并从磁盘重新加载吗？"
	_close_confirmation.ok_button_text = "放弃修改"
	_close_confirmation.confirmed.connect(_discard_and_hide)
	add_child(_close_confirmation)


func _load_catalog() -> void:
	var loaded := ResourceLoader.load(CATALOG_PATH) as StuffCatalog
	if loaded == null:
		_set_status("无法加载 %s" % CATALOG_PATH, false)
		return
	_catalog = loaded
	_dirty = false
	_rebuild_list()


func _rebuild_list(preferred: StuffDefinition = null) -> void:
	_list.clear()
	if _catalog == null:
		_select_definition(null)
		return
	for definition in _catalog.definitions:
		if definition == null:
			continue
		var state := "" if definition.authoring_enabled else " [已禁用]"
		_list.add_item("%s%s\n%s" % [definition.display_name, state, definition.stuff_id])
		_list.set_item_metadata(_list.item_count - 1, definition)
	var target := preferred if preferred != null else _selected
	var target_index := -1
	for index in range(_list.item_count):
		if _list.get_item_metadata(index) == target:
			target_index = index
			break
	if target_index < 0 and _list.item_count > 0:
		target_index = 0
	if target_index >= 0:
		_list.select(target_index)
		_select_definition(_list.get_item_metadata(target_index) as StuffDefinition)
	else:
		_select_definition(null)


func _on_list_selected(index: int) -> void:
	if index >= 0 and index < _list.item_count:
		_select_definition(_list.get_item_metadata(index) as StuffDefinition)


func _select_definition(definition: StuffDefinition) -> void:
	_selected = definition
	_syncing = true
	var has_value := definition != null
	for control in [
		_id_edit, _name_edit, _description_edit, _enabled, _exclusive,
		_blocks_tile, _blocks_edge, _blocks_ballistics, _blocks_path, _navigation_airborne,
		_destructible, _durability, _model_picker, _icon_picker, _effect_picker,
		_scale_x, _scale_y, _scale_z, _fallback_kind, _fallback_color,
	]:
		if control is LineEdit or control is TextEdit or control is SpinBox or control is EditorResourcePicker:
			control.set("editable", has_value)
		else:
			control.set("disabled", not has_value)
	_remove_button.disabled = not has_value
	_save_button.disabled = not has_value
	if not has_value:
		_id_edit.text = ""
		_name_edit.text = ""
		_description_edit.text = ""
		_syncing = false
		return
	_id_edit.text = String(definition.stuff_id)
	_id_edit.editable = definition.resource_path.is_empty()
	_name_edit.text = definition.display_name
	_description_edit.text = definition.description
	_enabled.button_pressed = definition.authoring_enabled
	_exclusive.button_pressed = definition.exclusive_with_other_stuff
	_blocks_tile.button_pressed = definition.blocks_tile_building
	_blocks_edge.button_pressed = definition.blocks_edge_building
	_blocks_ballistics.button_pressed = definition.blocks_ballistics
	_blocks_path.button_pressed = definition.enemy_navigation == StuffDefinition.EnemyNavigation.BLOCKED
	_navigation_airborne.button_pressed = definition.navigation_affects_airborne
	_destructible.button_pressed = definition.durability_mode == StuffDefinition.DurabilityMode.DESTRUCTIBLE
	_durability.value = definition.max_durability
	var asset := definition.get_model_asset()
	_model_picker.edited_resource = asset.scene if asset != null else null
	var scale := asset.runtime_scale if asset != null else Vector3.ONE
	_scale_x.value = scale.x
	_scale_y.value = scale.y
	_scale_z.value = scale.z
	_icon_picker.edited_resource = definition.ui_icon
	_effect_picker.edited_resource = definition.effect
	_fallback_kind.select(clampi(definition.fallback_visual_kind, 0, _fallback_kind.item_count - 1))
	_fallback_color.color = definition.fallback_color
	_durability.editable = _destructible.button_pressed
	_navigation_airborne.disabled = not _blocks_path.button_pressed
	_syncing = false
	_set_status("资源：%s" % (definition.resource_path if not definition.resource_path.is_empty() else "尚未保存"), true)


func _on_form_changed() -> void:
	if _syncing or _selected == null:
		return
	var requested_id := _authoring.sanitize_id(_id_edit.text)
	if _selected.resource_path.is_empty():
		_selected.stuff_id = StringName(requested_id)
	_selected.display_name = _name_edit.text.strip_edges()
	_selected.description = _description_edit.text
	_selected.authoring_enabled = _enabled.button_pressed
	_selected.exclusive_with_other_stuff = _exclusive.button_pressed
	_selected.blocks_tile_building = _blocks_tile.button_pressed
	_selected.blocks_edge_building = _blocks_edge.button_pressed
	_selected.blocks_ballistics = _blocks_ballistics.button_pressed
	_selected.enemy_navigation = (
		StuffDefinition.EnemyNavigation.BLOCKED
		if _blocks_path.button_pressed
		else StuffDefinition.EnemyNavigation.PASSABLE
	)
	_selected.navigation_affects_airborne = _navigation_airborne.button_pressed
	_selected.durability_mode = (
		StuffDefinition.DurabilityMode.DESTRUCTIBLE
		if _destructible.button_pressed
		else StuffDefinition.DurabilityMode.INDESTRUCTIBLE
	)
	_selected.max_durability = _durability.value
	_authoring.set_model_scene(
		_selected,
		_model_picker.edited_resource as PackedScene,
		Vector3(_scale_x.value, _scale_y.value, _scale_z.value)
	)
	_selected.ui_icon = _icon_picker.edited_resource as Texture2D
	_selected.effect = _effect_picker.edited_resource
	_selected.fallback_visual_kind = _fallback_kind.selected
	_selected.fallback_color = _fallback_color.color
	_selected.emit_changed()
	_durability.editable = _destructible.button_pressed
	_navigation_airborne.disabled = not _blocks_path.button_pressed
	_dirty = true
	_refresh_selected_list_label()
	_set_status("有未保存修改", true)


func _refresh_selected_list_label() -> void:
	if _selected == null:
		return
	for index in range(_list.item_count):
		if _list.get_item_metadata(index) != _selected:
			continue
		var state := "" if _selected.authoring_enabled else " [已禁用]"
		_list.set_item_text(index, "%s%s\n%s" % [_selected.display_name, state, _selected.stuff_id])
		return


func _create_definition() -> void:
	if _catalog == null:
		return
	var result: Dictionary = _authoring.create_definition(_catalog, "new_stuff", "新关卡元素")
	if not bool(result.get("success", false)):
		_set_status(result.get("message", "新建失败"), false)
		return
	_dirty = true
	_rebuild_list(result.get("definition") as StuffDefinition)


func _duplicate_definition() -> void:
	var result: Dictionary = _authoring.duplicate_definition(_catalog, _selected)
	if not bool(result.get("success", false)):
		_set_status(result.get("message", "复制失败"), false)
		return
	_dirty = true
	_rebuild_list(result.get("definition") as StuffDefinition)


func _move_selected(offset: int) -> void:
	if _catalog == null or _selected == null:
		return
	var from_index := _catalog.definitions.find(_selected)
	if _catalog.move_definition(from_index, from_index + offset):
		_dirty = true
		_rebuild_list(_selected)


func _remove_definition() -> void:
	if _catalog == null or _selected == null:
		return
	if _dirty:
		_set_status("请先保存或放弃当前修改，再移除目录项", false)
		return
	var result: Dictionary = _authoring.remove_definition_if_unreferenced(
		_catalog,
		_selected,
		LEVEL_DIRECTORY
	)
	if not bool(result.get("success", false)):
		_set_status(result.get("message", "移除失败"), false)
		return
	_selected = null
	var save_error := ResourceSaver.save(_catalog, CATALOG_PATH)
	if save_error != OK:
		_set_status("目录已在内存移除，但保存失败：%s" % error_string(save_error), false)
		_dirty = true
	else:
		_dirty = false
		_set_status(result.get("message", "已移除"), true)
		catalog_changed.emit()
	_rebuild_list()


func _save_selected() -> void:
	if _selected == null:
		return
	_on_form_changed()
	var result: Dictionary = _authoring.save_catalog(_catalog)
	if not bool(result.get("success", false)):
		_set_status(result.get("message", "保存失败"), false)
		return
	_dirty = false
	_rebuild_list(_selected)
	_set_status(result.get("message", "保存成功"), true)
	catalog_changed.emit()


func _on_close_requested() -> void:
	if _dirty:
		_close_confirmation.popup_centered()
	else:
		hide()


func _discard_and_hide() -> void:
	ResourceLoader.load(CATALOG_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_catalog = ResourceLoader.load(CATALOG_PATH) as StuffCatalog
	_dirty = false
	catalog_changed.emit()
	hide()


func _set_status(message: String, success: bool) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.62) if success else Color(1.0, 0.42, 0.38))


func _add_button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _make_check(text_value: String, callback: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = text_value
	check.toggled.connect(callback.unbind(1))
	return check


func _make_spin(minimum: float, maximum: float, step_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.allow_greater = true
	return spin


func _make_scale_spin() -> SpinBox:
	return _make_spin(0.01, 100.0, 0.01)


func _add_heading(parent: Control, text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)


func _with_label(text_value: String, control: Control) -> VBoxContainer:
	var group := VBoxContainer.new()
	var label := Label.new()
	label.text = text_value
	group.add_child(label)
	group.add_child(control)
	return group
