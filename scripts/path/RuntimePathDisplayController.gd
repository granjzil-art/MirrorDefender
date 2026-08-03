## Phase controller for continuous idle routes and moving active-wave hints.
class_name RuntimePathDisplayController
extends Node

enum DisplayPhase {
	HIDDEN,
	CONTINUOUS,
	FLOWING,
}

@export_group("Feature")
@export var feature_enabled: bool = true

var _wave_manager: WaveManager
var _path_manager: PathManager
var _flow_renderer: PathMovingSegmentRenderer
var _phase: DisplayPhase = DisplayPhase.HIDDEN
var _active_path_signature: String = ""


func _ready() -> void:
	_ensure_flow_renderer()


func configure(wave_manager: WaveManager, path_manager: PathManager) -> void:
	_disconnect_wave_manager()
	_ensure_flow_renderer()
	_wave_manager = wave_manager
	_path_manager = path_manager
	_flow_renderer.configure(_path_manager)
	if _wave_manager != null:
		_wave_manager.state_changed.connect(_on_wave_state_changed)
	_sync_phase(true)


func _process(delta: float) -> void:
	advance_display_time(delta)


## Public deterministic clock used by runtime and focused regression tests.
func advance_display_time(delta: float) -> void:
	if not feature_enabled:
		if _phase != DisplayPhase.HIDDEN:
			_sync_phase(false)
		return
	if _phase != DisplayPhase.FLOWING or _flow_renderer == null:
		return
	_flow_renderer.advance_visual_time(delta)


func get_display_phase() -> DisplayPhase:
	return _phase


func get_flow_renderer() -> PathMovingSegmentRenderer:
	_ensure_flow_renderer()
	return _flow_renderer


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
			next_phase = DisplayPhase.FLOWING
			active_paths = _wave_manager.get_active_path_requests()
	var next_signature := _make_path_signature(active_paths)
	var phase_changed := next_phase != _phase
	var paths_changed := next_signature != _active_path_signature
	if not force and not phase_changed and not paths_changed:
		return
	_phase = next_phase
	_active_path_signature = next_signature
	_apply_display(active_paths, phase_changed or paths_changed)


func _apply_display(active_paths: Array[Dictionary] = [], reset_motion: bool = false) -> void:
	if _path_manager == null:
		return
	match _phase:
		DisplayPhase.CONTINUOUS:
			_flow_renderer.clear_routes()
			var all_paths: Array[Dictionary] = []
			if _wave_manager != null:
				all_paths = _wave_manager.get_all_path_requests()
			_path_manager.set_runtime_path_display(true, all_paths)
		DisplayPhase.FLOWING:
			var paths := active_paths
			if paths.is_empty() and _wave_manager != null:
				paths = _wave_manager.get_active_path_requests()
			_path_manager.set_runtime_path_display(false)
			_flow_renderer.show_routes(paths, reset_motion)
		_:
			_path_manager.set_runtime_path_display(false)
			_flow_renderer.clear_routes()


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


func _ensure_flow_renderer() -> void:
	if _flow_renderer != null and is_instance_valid(_flow_renderer):
		return
	_flow_renderer = get_node_or_null("MovingSegments") as PathMovingSegmentRenderer
	if _flow_renderer == null:
		_flow_renderer = PathMovingSegmentRenderer.new()
		_flow_renderer.name = "MovingSegments"
		add_child(_flow_renderer)
