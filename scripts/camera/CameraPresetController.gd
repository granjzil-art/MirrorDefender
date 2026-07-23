## Resolves the six per-level camera slots and performs an unscaled transition.
class_name CameraPresetController
extends Node

const PRESET_ACTIONS: Array[StringName] = [
	&"camera_preset_1",
	&"camera_preset_2",
	&"camera_preset_3",
	&"camera_preset_4",
	&"camera_preset_5",
	&"camera_preset_6",
]

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Transition")
@export_range(0.0, 5.0, 0.01, "or_greater") var transition_duration: float = 0.35
## Optional normalized easing curve. Empty uses smoothstep.
@export var transition_curve: Curve

signal transition_started(slot_number: int)
signal transition_completed(slot_number: int)
signal preset_unavailable(slot_number: int)

var _camera_controller: CameraController
var _level: LevelResource
var _transition_active: bool = false
var _elapsed: float = 0.0
var _active_slot_index: int = -1
var _start_state: Dictionary = {}
var _target_state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _transition_active or _camera_controller == null:
		return
	# Pause menu and later console modal freeze an in-flight transition.
	if not _camera_controller.is_input_enabled():
		return
	var real_delta := delta
	if Engine.time_scale > 0.0001:
		real_delta /= Engine.time_scale
	advance_transition(real_delta)


func _unhandled_input(event: InputEvent) -> void:
	if not feature_enabled or _camera_controller == null or not _camera_controller.is_input_enabled():
		return
	for slot_index in range(PRESET_ACTIONS.size()):
		if not event.is_action_pressed(PRESET_ACTIONS[slot_index]):
			continue
		if request_preset(slot_index):
			get_viewport().set_input_as_handled()
		return


func configure(camera_controller: CameraController) -> void:
	if _camera_controller != null:
		_camera_controller.set_preset_transition_active(false)
	_camera_controller = camera_controller
	cancel_transition()


func load_level(level: LevelResource) -> void:
	cancel_transition()
	_level = level


## slot_index is zero-based; user-facing signals are one-based.
func request_preset(slot_index: int) -> bool:
	if not feature_enabled or _camera_controller == null or _level == null:
		return false
	var preset := _level.get_camera_preset(slot_index)
	if preset == null:
		preset_unavailable.emit(slot_index + 1)
		return false
	var configuration_errors := preset.validate_configuration()
	if not configuration_errors.is_empty():
		preset_unavailable.emit(slot_index + 1)
		return false
	_start_state = _camera_controller.get_view_state()
	_target_state = preset.to_camera_state()
	_elapsed = 0.0
	_active_slot_index = slot_index
	if transition_duration <= 0.0:
		_transition_active = false
		_camera_controller.set_preset_transition_active(false)
		_apply_state(_target_state)
		transition_started.emit(slot_index + 1)
		transition_completed.emit(slot_index + 1)
		_active_slot_index = -1
		return true
	_transition_active = true
	_camera_controller.set_preset_transition_active(true)
	transition_started.emit(slot_index + 1)
	return true


## Public deterministic step used by tests and replay-safe callers.
func advance_transition(real_delta: float) -> void:
	if not _transition_active or _camera_controller == null:
		return
	_elapsed += maxf(0.0, real_delta)
	var progress := clampf(_elapsed / maxf(transition_duration, 0.0001), 0.0, 1.0)
	var weight := _sample_transition_weight(progress)
	var start_focus: Vector3 = _start_state.get("focus_position", Vector3.ZERO)
	var target_focus: Vector3 = _target_state.get("focus_position", Vector3.ZERO)
	var start_yaw: float = float(_start_state.get("yaw_degrees", 0.0))
	var target_yaw: float = float(_target_state.get("yaw_degrees", 0.0))
	var start_pitch: float = float(_start_state.get("pitch_degrees", 50.0))
	var target_pitch: float = float(_target_state.get("pitch_degrees", 50.0))
	var start_zoom: float = float(_start_state.get("zoom_distance", 16.0))
	var target_zoom: float = float(_target_state.get("zoom_distance", 16.0))
	_camera_controller.apply_view_state(
		start_focus.lerp(target_focus, weight),
		rad_to_deg(lerp_angle(deg_to_rad(start_yaw), deg_to_rad(target_yaw), weight)),
		lerpf(start_pitch, target_pitch, weight),
		lerpf(start_zoom, target_zoom, weight)
	)
	if progress < 1.0:
		return
	var completed_slot := _active_slot_index
	_transition_active = false
	_active_slot_index = -1
	_camera_controller.set_preset_transition_active(false)
	transition_completed.emit(completed_slot + 1)


func cancel_transition() -> void:
	_transition_active = false
	_elapsed = 0.0
	_active_slot_index = -1
	_start_state.clear()
	_target_state.clear()
	if _camera_controller != null:
		_camera_controller.set_preset_transition_active(false)


func is_transition_active() -> bool:
	return _transition_active


func get_loaded_level() -> LevelResource:
	return _level


func _sample_transition_weight(progress: float) -> float:
	if transition_curve != null:
		return clampf(transition_curve.sample_baked(progress), 0.0, 1.0)
	return smoothstep(0.0, 1.0, progress)


func _apply_state(state: Dictionary) -> void:
	var focus: Vector3 = state.get("focus_position", Vector3.ZERO)
	var yaw: float = float(state.get("yaw_degrees", 0.0))
	var pitch: float = float(state.get("pitch_degrees", 50.0))
	var zoom: float = float(state.get("zoom_distance", 16.0))
	_camera_controller.apply_view_state(focus, yaw, pitch, zoom)
