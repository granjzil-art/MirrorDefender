@tool
## One clickable level thumbnail. Empty slots keep their grid cell but render transparently.
class_name LevelSelectSlot
extends Button

const LevelThumbnailScript := preload("res://scripts/ui/LevelThumbnail.gd")

var _level: LevelResource
var _validation_errors: Array[String] = []
var _thumbnail: LevelThumbnailScript
var _interaction_locked: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
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


func set_interaction_locked(value: bool) -> void:
	_interaction_locked = value
	_refresh()
	return


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
	var is_available := _level != null and _validation_errors.is_empty()
	disabled = not is_available or _interaction_locked
	self_modulate = Color(1.0, 1.0, 1.0, 1.0 if is_available else 0.0)
	tooltip_text = ""
	if _thumbnail == null:
		return
	if _level == null:
		_thumbnail.clear()
		return
	_thumbnail.set_level(_level)
	return
