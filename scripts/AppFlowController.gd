## Persistent application flow root. Owns either level selection or one battle scene.
class_name AppFlowController
extends Node

@export_group("Flow Resources")
@export var level_select_catalog: LevelSelectCatalog
@export var level_select_scene: PackedScene
@export var main_scene: PackedScene

@onready var content: Node = $Content

var _active_level_select: Control
var _active_main: Node
var _pending_main: Node
var _pending_start_success: bool = false
var _transition_pending: bool = false
var _catalog_validation_errors: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	_catalog_validation_errors = _validate_catalog()
	_show_level_select()


func get_active_level_select() -> Control:
	return _active_level_select


func get_active_main() -> Node:
	return _active_main


func get_active_content_count() -> int:
	return content.get_child_count() if content != null else 0


func return_to_level_select() -> void:
	if _transition_pending:
		return
	_transition_pending = true
	call_deferred("_complete_return_to_level_select")


func _show_level_select() -> void:
	_release_active_main()
	_release_active_level_select()
	Engine.time_scale = 1.0
	if not _catalog_validation_errors.is_empty():
		_active_level_select = _create_fallback_level_select(
			"选关配置不可用\n%s" % "\n".join(_catalog_validation_errors)
		)
	else:
		_active_level_select = _instantiate_level_select()
	content.add_child(_active_level_select)
	if _active_level_select is LevelSelectView:
		var view := _active_level_select as LevelSelectView
		view.configure(level_select_catalog)
		view.level_selected.connect(_on_level_selected)


func _instantiate_level_select() -> Control:
	if level_select_scene != null:
		var instance := level_select_scene.instantiate()
		if instance is Control:
			return instance as Control
		instance.free()
	return _create_fallback_level_select("选关场景不可用")


func _create_fallback_level_select(message: String) -> Control:
	var fallback := Control.new()
	fallback.name = "LevelSelectFallback"
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.012, 0.022, 0.031, 1.0)
	fallback.add_child(background)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.add_child(label)
	return fallback


func _validate_catalog() -> Array[String]:
	if level_select_catalog == null:
		return ["未配置 LevelSelectCatalog"]
	return level_select_catalog.validate_configuration()


func _on_level_selected(level: LevelResource) -> void:
	if _transition_pending or level == null:
		return
	var validation_errors := level.validate_runtime()
	if not validation_errors.is_empty():
		return
	_transition_pending = true
	call_deferred("_start_level", level)


func _start_level(level: LevelResource) -> void:
	if main_scene == null:
		_transition_pending = false
		return
	var candidate := main_scene.instantiate()
	if candidate == null or not candidate.has_method("configure_startup_level"):
		if candidate != null:
			candidate.free()
		_transition_pending = false
		return
	if not bool(candidate.call("configure_startup_level", level)):
		candidate.free()
		_transition_pending = false
		return
	if (
		not candidate.has_signal("return_to_level_select_requested")
		or not candidate.has_signal("startup_level_load_resolved")
	):
		candidate.free()
		_transition_pending = false
		return
	candidate.connect(&"return_to_level_select_requested", _on_return_to_level_select_requested)
	candidate.connect(&"startup_level_load_resolved", _on_startup_level_load_resolved)
	_pending_main = candidate
	_pending_start_success = false
	if candidate is Node3D:
		(candidate as Node3D).visible = false
	candidate.process_mode = Node.PROCESS_MODE_DISABLED
	content.add_child(candidate)


func _on_startup_level_load_resolved(success: bool, _reason: String) -> void:
	_pending_start_success = success
	call_deferred("_commit_start_level")


func _commit_start_level() -> void:
	var candidate := _pending_main
	_pending_main = null
	if candidate == null or not is_instance_valid(candidate):
		_transition_pending = false
		return
	if not _pending_start_success:
		if candidate.get_parent() != null:
			candidate.get_parent().remove_child(candidate)
		candidate.free()
		_transition_pending = false
		return
	_release_active_level_select()
	_active_main = candidate
	_active_main.process_mode = Node.PROCESS_MODE_INHERIT
	if _active_main is Node3D:
		(_active_main as Node3D).visible = true
	_transition_pending = false


func _on_return_to_level_select_requested() -> void:
	return_to_level_select()


func _complete_return_to_level_select() -> void:
	if _active_main != null and _active_main.has_method("prepare_for_level_transition"):
		_active_main.call("prepare_for_level_transition")
	_release_active_main()
	Engine.time_scale = 1.0
	_show_level_select()
	_transition_pending = false


func _release_active_level_select() -> void:
	if _active_level_select == null:
		return
	if is_instance_valid(_active_level_select):
		if _active_level_select.get_parent() != null:
			_active_level_select.get_parent().remove_child(_active_level_select)
		_active_level_select.free()
	_active_level_select = null


func _release_active_main() -> void:
	if _active_main == null:
		return
	if is_instance_valid(_active_main):
		if _active_main.get_parent() != null:
			_active_main.get_parent().remove_child(_active_main)
		_active_main.free()
	_active_main = null
