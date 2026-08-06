## MiniatureDofController -- keeps practical camera DOF focused on the rig pivot.
class_name MiniatureDofController
extends Node

signal effect_enabled_changed(enabled: bool)
signal focus_parameters_changed(focus_depth: float, near_distance: float, far_distance: float)

@export_group("Feature")
@export var feature_enabled: bool = true
@export var test_shortcut_enabled: bool = true

var _camera: Camera3D
var _camera_rig: Node3D
var _grid: GridManager
var _definition: MiniatureDofDefinition
var _attributes: CameraAttributesPractical
var _previous_attributes: CameraAttributes
var _effect_enabled: bool = true
var _focus_target: Node3D
var _focus_depth: float = 0.0
var _near_distance: float = 0.0
var _far_distance: float = 0.0
var _last_state: Dictionary = {}


func configure(
	camera: Camera3D,
	camera_rig: Node3D,
	grid: GridManager,
	definition: MiniatureDofDefinition
) -> bool:
	_restore_previous_attributes()
	_camera = camera
	_camera_rig = camera_rig
	_grid = grid
	_definition = definition
	_last_state.clear()
	if _camera == null or _camera_rig == null or _definition == null:
		set_process(false)
		return false
	if not _definition.validate_configuration().is_empty():
		set_process(false)
		return false
	_previous_attributes = _camera.attributes
	_attributes = CameraAttributesPractical.new()
	_effect_enabled = feature_enabled and _definition.feature_enabled
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_apply_enabled_state()
	return refresh_now()


func _exit_tree() -> void:
	_restore_previous_attributes()


func _process(_delta: float) -> void:
	refresh_now()


func _unhandled_input(event: InputEvent) -> void:
	if not feature_enabled or not test_shortcut_enabled:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != KEY_0:
		return
	set_effect_enabled(not _effect_enabled)
	get_viewport().set_input_as_handled()


func set_effect_enabled(enabled: bool) -> void:
	var resolved := enabled and feature_enabled and _definition != null and _definition.feature_enabled
	if resolved == _effect_enabled and (
		(_camera != null and _camera.attributes == _attributes) == resolved
	):
		return
	_effect_enabled = resolved
	_apply_enabled_state()
	if _effect_enabled:
		refresh_now(true)
	effect_enabled_changed.emit(_effect_enabled)


func is_effect_enabled() -> bool:
	return _effect_enabled


func set_focus_target(target: Node3D) -> void:
	_focus_target = target
	refresh_now(true)


func clear_focus_target() -> void:
	_focus_target = null
	refresh_now(true)


func refresh_now(force: bool = false) -> bool:
	if not _effect_enabled or _camera == null or _camera_rig == null or _grid == null or _attributes == null:
		return false
	if _camera.attributes != _attributes:
		_camera.attributes = _attributes
	var cell_size := maxf(0.01, _grid.cell_size)
	var focus_target_position := _camera_rig.global_position
	if is_instance_valid(_focus_target):
		focus_target_position = _focus_target.global_position
	focus_target_position += Vector3.UP * _definition.focus_height_offset_cells * cell_size
	var camera_forward := -_camera.global_basis.z.normalized()
	var focus_depth := maxf(
		_camera.near + 0.05,
		camera_forward.dot(focus_target_position - _camera.global_position)
	)
	var near_distance := maxf(
		_camera.near + 0.025,
		focus_depth - _definition.near_focus_margin_cells * cell_size
	)
	var far_distance := maxf(
		near_distance + 0.05,
		focus_depth + _definition.far_focus_margin_cells * cell_size
	)
	var state := {
		"camera_transform": _camera.global_transform,
		"focus_target": focus_target_position,
		"cell_size": cell_size,
		"near_distance": near_distance,
		"far_distance": far_distance,
		"near_blur_enabled": _definition.near_blur_enabled,
		"far_blur_enabled": _definition.far_blur_enabled,
		"blur_amount": _definition.blur_amount,
		"near_transition_cells": _definition.near_transition_cells,
		"far_transition_cells": _definition.far_transition_cells,
	}
	if not force and state == _last_state:
		return true
	_last_state = state
	_focus_depth = focus_depth
	_near_distance = near_distance
	_far_distance = far_distance
	_attributes.dof_blur_near_enabled = _definition.near_blur_enabled
	_attributes.dof_blur_far_enabled = _definition.far_blur_enabled
	_attributes.dof_blur_amount = _definition.blur_amount
	_attributes.dof_blur_near_distance = near_distance
	_attributes.dof_blur_far_distance = far_distance
	_attributes.dof_blur_near_transition = _definition.near_transition_cells * cell_size
	_attributes.dof_blur_far_transition = _definition.far_transition_cells * cell_size
	focus_parameters_changed.emit(focus_depth, near_distance, far_distance)
	return true


func get_camera_attributes() -> CameraAttributesPractical:
	return _attributes


func get_focus_depth() -> float:
	return _focus_depth


func get_near_distance() -> float:
	return _near_distance


func get_far_distance() -> float:
	return _far_distance


func _apply_enabled_state() -> void:
	if _camera == null:
		return
	if _effect_enabled:
		_camera.attributes = _attributes
	elif _camera.attributes == _attributes:
		_camera.attributes = _previous_attributes


func _restore_previous_attributes() -> void:
	if _camera != null and _attributes != null and _camera.attributes == _attributes:
		_camera.attributes = _previous_attributes
	_attributes = null
	_previous_attributes = null
