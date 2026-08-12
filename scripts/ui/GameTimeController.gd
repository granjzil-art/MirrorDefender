## Resolves player-selected 1x/2x/4x, tactical-slow, and pause requests.
class_name GameTimeController
extends Node

const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")

@export_group("Tactical Slow")
@export var tactical_slow_enabled: bool = true
@export_range(0.01, 1.0, 0.01) var tactical_slow_scale: float = 0.1

@export_group("Fast Forward")
@export_range(1.0, 8.0, 0.1, "or_greater") var fast_scale: float = 2.0
@export_range(1.0, 8.0, 0.1, "or_greater") var very_fast_scale: float = 4.0

signal time_scale_changed(scale: float)
signal tactical_slow_enabled_changed(enabled: bool)
signal playback_scale_changed(scale: float)
## Compatibility signal for callers that only distinguish normal from >1x.
signal fast_enabled_changed(enabled: bool)
signal paused_changed(paused: bool)
signal authoring_pause_changed(paused: bool)

var _interaction: RuntimeInteractionControllerScript
var _building_manager: BuildingManager
var _mirror_manager: MirrorManager
var _playback_scale: float = 1.0
var _paused: bool = false
var _authoring_paused: bool = false
var _applied_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_scale()


func _exit_tree() -> void:
	if is_equal_approx(Engine.time_scale, _applied_scale):
		Engine.time_scale = 1.0


func configure(
	interaction: RuntimeInteractionControllerScript,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager
) -> void:
	_disconnect_sources()
	_interaction = interaction
	_building_manager = building_manager
	_mirror_manager = mirror_manager
	if _interaction != null:
		_interaction.mode_changed.connect(_on_context_changed)
	if _building_manager != null:
		_building_manager.building_selected.connect(_on_building_selected)
	if _mirror_manager != null:
		_mirror_manager.mirror_selected.connect(_on_mirror_selected)
	_refresh_scale()


func set_tactical_slow_enabled(enabled: bool) -> void:
	if tactical_slow_enabled == enabled:
		return
	tactical_slow_enabled = enabled
	tactical_slow_enabled_changed.emit(enabled)
	_refresh_scale()


func toggle_tactical_slow_enabled() -> void:
	set_tactical_slow_enabled(not tactical_slow_enabled)


func set_fast_enabled(enabled: bool) -> void:
	set_playback_scale(_get_fast_scale() if enabled else 1.0)


func is_fast_enabled() -> bool:
	return _playback_scale > 1.0 and not is_equal_approx(_playback_scale, 1.0)


func set_playback_scale(value: float) -> void:
	var resolved := _resolve_playback_scale(value)
	if is_equal_approx(_playback_scale, resolved):
		return
	var was_fast := is_fast_enabled()
	_playback_scale = resolved
	playback_scale_changed.emit(_playback_scale)
	if was_fast != is_fast_enabled():
		fast_enabled_changed.emit(is_fast_enabled())
	_refresh_scale()


func cycle_playback_scale() -> void:
	var fast := _get_fast_scale()
	var very_fast := _get_very_fast_scale()
	if is_equal_approx(_playback_scale, 1.0):
		set_playback_scale(fast)
	elif is_equal_approx(_playback_scale, fast) and very_fast > fast:
		set_playback_scale(very_fast)
	else:
		set_playback_scale(1.0)


func get_playback_scale() -> float:
	return _playback_scale


func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	paused_changed.emit(paused)
	_refresh_scale()


func is_paused() -> bool:
	return _paused


func set_authoring_paused(paused: bool) -> void:
	if _authoring_paused == paused:
		return
	_authoring_paused = paused
	authoring_pause_changed.emit(paused)
	_refresh_scale()


func is_authoring_paused() -> bool:
	return _authoring_paused


func get_effective_scale() -> float:
	return _applied_scale


func reset_runtime_state() -> void:
	var playback_changed := not is_equal_approx(_playback_scale, 1.0)
	var fast_changed := is_fast_enabled()
	var pause_changed := _paused
	var authoring_pause_changed_value := _authoring_paused
	_playback_scale = 1.0
	_paused = false
	_authoring_paused = false
	_applied_scale = 1.0
	Engine.time_scale = 1.0
	if fast_changed:
		fast_enabled_changed.emit(false)
	if playback_changed:
		playback_scale_changed.emit(1.0)
	if pause_changed:
		paused_changed.emit(false)
	if authoring_pause_changed_value:
		authoring_pause_changed.emit(false)
	time_scale_changed.emit(1.0)


func has_tactical_context() -> bool:
	if _interaction != null and not _interaction.is_select_mode():
		return true
	if _building_manager != null and _building_manager.get_selected_building() != null:
		return true
	return _mirror_manager != null and _mirror_manager.get_selected_mirror() != null


func _refresh_scale() -> void:
	var resolved := 1.0
	if _paused or _authoring_paused:
		resolved = 0.0
	elif tactical_slow_enabled and has_tactical_context():
		resolved = clampf(tactical_slow_scale, 0.01, 1.0)
	else:
		resolved = _playback_scale
	if is_equal_approx(_applied_scale, resolved) and is_equal_approx(Engine.time_scale, resolved):
		return
	_applied_scale = resolved
	Engine.time_scale = resolved
	time_scale_changed.emit(resolved)


func _resolve_playback_scale(value: float) -> float:
	var fast := _get_fast_scale()
	var very_fast := _get_very_fast_scale()
	if is_equal_approx(value, very_fast):
		return very_fast
	if is_equal_approx(value, fast):
		return fast
	return 1.0


func _get_fast_scale() -> float:
	return maxf(1.0, fast_scale)


func _get_very_fast_scale() -> float:
	return maxf(_get_fast_scale(), very_fast_scale)


func _on_context_changed(_value: Variant = null) -> void:
	_refresh_scale()


func _on_building_selected(_building: Building) -> void:
	_refresh_scale()


func _on_mirror_selected(_mirror: CopyMirror) -> void:
	_refresh_scale()


func _disconnect_sources() -> void:
	if _interaction != null and _interaction.mode_changed.is_connected(_on_context_changed):
		_interaction.mode_changed.disconnect(_on_context_changed)
	if _building_manager != null and _building_manager.building_selected.is_connected(_on_building_selected):
		_building_manager.building_selected.disconnect(_on_building_selected)
	if _mirror_manager != null and _mirror_manager.mirror_selected.is_connected(_on_mirror_selected):
		_mirror_manager.mirror_selected.disconnect(_on_mirror_selected)
