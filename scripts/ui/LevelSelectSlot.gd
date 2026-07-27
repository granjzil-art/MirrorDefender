@tool
## One clickable level slot. Empty slots stay visible but cannot be activated.
class_name LevelSelectSlot
extends Button

const LevelThumbnailScript := preload("res://scripts/ui/LevelThumbnail.gd")
const SLOT_SIZE := Vector2(300.0, 210.0)

var _level: LevelResource
var _validation_errors: Array[String] = []
var _thumbnail: LevelThumbnailScript
var _title_label: Label


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_build_content()
	_apply_styles()
	_refresh()


func set_level(value: LevelResource) -> void:
	_level = value
	_validation_errors.clear()
	if _level != null:
		_validation_errors.assign(_level.validate_runtime())
	_refresh()


func clear() -> void:
	_level = null
	_validation_errors.clear()
	_refresh()


func get_level() -> LevelResource:
	return _level


func is_empty() -> bool:
	return _level == null


func get_thumbnail() -> LevelThumbnailScript:
	return _thumbnail


func _build_content() -> void:
	if _thumbnail != null:
		return
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 7)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(content)
	_thumbnail = LevelThumbnailScript.new()
	_thumbnail.name = "Thumbnail"
	_thumbnail.custom_minimum_size = Vector2(0.0, 158.0)
	_thumbnail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_thumbnail)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_title_label)


func _refresh() -> void:
	disabled = _level == null or not _validation_errors.is_empty()
	if _level == null:
		tooltip_text = ""
	elif not _validation_errors.is_empty():
		tooltip_text = "关卡配置无效：\n%s" % "\n".join(_validation_errors)
	else:
		tooltip_text = _get_level_name(_level)
	if _thumbnail == null or _title_label == null:
		return
	if _level == null:
		_thumbnail.clear()
		_title_label.text = "空槽"
		_title_label.modulate = Color(0.58, 0.62, 0.65, 0.82)
		return
	_thumbnail.set_level(_level)
	_title_label.text = _get_level_name(_level)
	_title_label.modulate = Color(0.88, 0.94, 0.98, 1.0)


func _get_level_name(level: LevelResource) -> String:
	var authored_name := level.display_name.strip_edges()
	if not authored_name.is_empty():
		return authored_name
	if not level.resource_path.is_empty():
		return level.resource_path.get_file().get_basename()
	return "未命名关卡"


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make_style(Color(0.075, 0.11, 0.14, 0.98), Color(0.28, 0.48, 0.58, 1.0), 2))
	add_theme_stylebox_override("hover", _make_style(Color(0.09, 0.145, 0.18, 1.0), Color(0.48, 0.78, 0.88, 1.0), 3))
	add_theme_stylebox_override("pressed", _make_style(Color(0.045, 0.09, 0.12, 1.0), Color(1.0, 0.73, 0.18, 1.0), 3))
	add_theme_stylebox_override("disabled", _make_style(Color(0.065, 0.075, 0.085, 0.94), Color(0.20, 0.23, 0.25, 1.0), 2))


func _make_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style
