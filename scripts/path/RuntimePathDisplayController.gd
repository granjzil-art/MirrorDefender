## Phase controller for continuous idle routes and pulsed active-wave routes.
class_name RuntimePathDisplayController
extends Node

enum DisplayPhase {
	HIDDEN,
	CONTINUOUS,
	PULSED,
}

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Active Wave Pulse")
## Seconds between the start of two active-wave path hints.
@export_range(0.25, 30.0, 0.05, "or_greater") var pulse_period: float = 5.0
## Seconds each active-wave path hint remains visible.
@export_range(0.05, 30.0, 0.05, "or_greater") var pulse_visible_duration: float = 1.25

var _wave_manager: WaveManager
var _path_manager: PathManager
var _phase: DisplayPhase = DisplayPhase.HIDDEN
var _pulse_elapsed: float = 0.0
var _active_path_signature: String = ""


func configure(wave_manager: WaveManager, path_manager: PathManager) -> void:
	_disconnect_wave_manager()
	_wave_manager = wave_manager
	_path_manager = path_manager
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_wave_state_changed)
	_sync_phase(true)


func _process(delta: float) -> void:
	advance_display_time(delta)


## Public deterministic clock used by runtime and focused regression tests.
func advance_display_time(delta: float) -> void:
	if not feature_enabled or _phase != DisplayPhase.PULSED:
		return
	var period := maxf(0.25, pulse_period)
	_pulse_elapsed = fposmod(_pulse_elapsed + maxf(0.0, delta), period)
	_apply_display()


func get_display_phase() -> DisplayPhase:
	return _phase


func _on_wave_state_changed(
	_state: WaveManager.State,
	_current_wave: int,
	_total_waves: int,
	_active_enemy_count: int
) -> void:
	_sync_phase(false)


func _sync_phase(force: bool) -> void:
	var next_phase := DisplayPhase.HIDDEN
	var active_paths: Array[Dictionary] = []
	if feature_enabled and _wave_manager != null:
		if _wave_manager.should_show_continuous_paths():
			next_phase = DisplayPhase.CONTINUOUS
		elif _wave_manager.is_wave_action_active():
			next_phase = DisplayPhase.PULSED
			active_paths = _wave_manager.get_active_path_requests()
	var next_signature := _make_path_signature(active_paths)
	var phase_changed := next_phase != _phase
	var paths_changed := next_signature != _active_path_signature
	if not force and not phase_changed and not paths_changed:
		return
	_phase = next_phase
	_active_path_signature = next_signature
	if phase_changed or paths_changed:
		_pulse_elapsed = 0.0
	_apply_display(active_paths)


func _apply_display(active_paths: Array[Dictionary] = []) -> void:
	if _path_manager == null:
		return
	match _phase:
		DisplayPhase.CONTINUOUS:
			var all_paths: Array[Dictionary] = []
			if _wave_manager != null:
				all_paths = _wave_manager.get_all_path_requests()
			_path_manager.set_runtime_path_display(true, all_paths)
		DisplayPhase.PULSED:
			var paths := active_paths
			if paths.is_empty() and _wave_manager != null:
				paths = _wave_manager.get_active_path_requests()
			var visible_duration := minf(maxf(0.05, pulse_visible_duration), maxf(0.25, pulse_period))
			_path_manager.set_runtime_path_display(_pulse_elapsed < visible_duration, paths)
		_:
			_path_manager.set_runtime_path_display(false)


func _make_path_signature(paths: Array[Dictionary]) -> String:
	var ids := PackedStringArray()
	for request in paths:
		var path := request.get("path") as PathDefinition
		if path != null:
			ids.append("%s:%s" % [String(path.path_id), "air" if bool(request.get("airborne", false)) else "ground"])
	return "|".join(ids)


func _disconnect_wave_manager() -> void:
	if _wave_manager != null and _wave_manager.state_changed.is_connected(_on_wave_state_changed):
		_wave_manager.state_changed.disconnect(_on_wave_state_changed)
