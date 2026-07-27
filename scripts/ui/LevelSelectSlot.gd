@tool
## One clickable level thumbnail. Empty slots keep their grid cell but render transparently.
class_name LevelSelectSlot
extends Button

const LevelThumbnailScript := preload("res://scripts/ui/LevelThumbnail.gd")
const SLOT_SIZE := Vector2(300.0, 210.0)

var _level: LevelResource
var _validation_errors: Array[String] = []
var _thumbnail: LevelThumbnailScript


func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	flat = true
	_build_content()
	_refresh()
	return


func set_level(value: LevelResource) -> void:
	_level = value
	_validation_errors.clear()
	if _level != null:
		_validation_errors.assign(_level.validate_runtime())
	_refresh()
	return


func clear() -> void:
	_level = null
	_validation_errors.clear()
	_refresh()
	return


func get_level() -> LevelResource:
	return _level


func is_empty() -> bool:
	return _level == null


func get_thumbnail() -> LevelThumbnailScript:
	return _thumbnail


func _build_content() -> void:
	if _thumbnail != null:
		return
	_thumbnail = LevelThumbnailScript.new()
	_thumbnail.name = "LevelThumbnail"
	_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_thumbnail)
	_thumbnail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return


func _refresh() -> void:
	disabled = _level == null or not _validation_errors.is_empty()
	self_modulate = Color(1.0, 1.0, 1.0, 0.0 if disabled else 1.0)
	tooltip_text = ""
	if _thumbnail == null:
		return
	if _level == null:
		_thumbnail.clear()
		return
	_thumbnail.set_level(_level)
	return
