## Phase controller for continuous idle routes and moving active-wave hints.
class_name RuntimePathDisplayController
extends Node

const PathHoverPreviewScene := preload("res://scenes/path/PathHoverPreview.tscn")

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
var _continuous_preview: PathHoverPreview
var _phase: DisplayPhase = DisplayPhase.HIDDEN
var _active_path_signature: String = ""
var _has_pending_transition: bool = false
var _pending_phase: DisplayPhase = DisplayPhase.HIDDEN
var _pending_paths: Array[Dictionary] = []
var _external_preview_active: bool = false


func _ready() -> void:
	_ensure_flow_renderer()
	_ensure_continuous_preview()


func configure(wave_manager: WaveManager, path_manager: PathManager) -> void:
	_disconnect_wave_manager()
	_ensure_flow_renderer()
	_ensure_continuous_preview()
	_wave_manager = wave_manager
	_path_manager = path_manager
	_flow_renderer.configure(_path_manager)
	_continuous_preview.configure(_path_manager)
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


func get_continuous_preview() -> PathHoverPreview:
	_ensure_continuous_preview()
	return _continuous_preview


## Prevents the inter-wave preview from doubling the dedicated hover overlay.
func set_external_preview_active(active: bool) -> void:
	if _external_preview_active == active:
		return
	_external_preview_active = active
	if _phase == DisplayPhase.CONTINUOUS:
		_refresh_continuous_preview()


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
	if not feature_enabled:
		_clear_pending_transition()
		_commit_phase(DisplayPhase.HIDDEN, [], true)
		return
	if _flow_renderer != null and _flow_renderer.is_finishing():
		_queue_transition(next_phase, active_paths)
		return
	var next_signature := _make_path_signature(active_paths)
	var phase_changed := next_phase != _phase
	var paths_changed := next_signature != _active_path_signature
	if not force and not phase_changed and not paths_changed:
		return
	if _phase == DisplayPhase.FLOWING and next_phase != DisplayPhase.FLOWING:
		if _flow_renderer.finish_current_segments():
			_queue_transition(next_phase, active_paths)
			return
	_commit_phase(next_phase, active_paths, phase_changed or paths_changed)


func _commit_phase(next_phase: DisplayPhase, active_paths: Array[Dictionary], reset_motion: bool) -> void:
	_clear_pending_transition()
	_phase = next_phase
	_active_path_signature = _make_path_signature(active_paths) if next_phase == DisplayPhase.FLOWING else ""
	_apply_display(active_paths, reset_motion)


func _apply_display(active_paths: Array[Dictionary] = [], reset_motion: bool = false) -> void:
	if _path_manager == null:
		return
	match _phase:
		DisplayPhase.CONTINUOUS:
			_flow_renderer.clear_routes()
			_path_manager.set_runtime_path_display(false)
			_refresh_continuous_preview()
		DisplayPhase.FLOWING:
			_continuous_preview.clear_preview()
			var paths := active_paths
			if paths.is_empty() and _wave_manager != null:
				paths = _wave_manager.get_active_path_requests()
			_path_manager.set_runtime_path_display(false)
			_flow_renderer.show_routes(paths, reset_motion)
		_:
			_path_manager.set_runtime_path_display(false)
			_flow_renderer.clear_routes()
			_continuous_preview.clear_preview()


func _refresh_continuous_preview() -> void:
	if _continuous_preview == null:
		return
	if _phase != DisplayPhase.CONTINUOUS or _external_preview_active or _wave_manager == null:
		_continuous_preview.clear_preview()
		return
	_continuous_preview.preview_paths(_wave_manager.get_next_wave_path_requests())


func _queue_transition(next_phase: DisplayPhase, active_paths: Array[Dictionary]) -> void:
	_has_pending_transition = true
	_pending_phase = next_phase
	_pending_paths = active_paths.duplicate()


func _clear_pending_transition() -> void:
	_has_pending_transition = false
	_pending_phase = DisplayPhase.HIDDEN
	_pending_paths.clear()


func _on_segments_finished() -> void:
	if not _has_pending_transition:
		return
	var next_phase := _pending_phase
	var paths := _pending_paths.duplicate()
	_commit_phase(next_phase, paths, true)


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
	if not _flow_renderer.segments_finished.is_connected(_on_segments_finished):
		_flow_renderer.segments_finished.connect(_on_segments_finished)


func _ensure_continuous_preview() -> void:
	if _continuous_preview != null and is_instance_valid(_continuous_preview):
		return
	_continuous_preview = PathHoverPreviewScene.instantiate() as PathHoverPreview
	_continuous_preview.name = "ContinuousPathPreview"
	add_child(_continuous_preview)
