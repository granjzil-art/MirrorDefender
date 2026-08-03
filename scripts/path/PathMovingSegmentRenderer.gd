## Renders one short, emissive ribbon travelling along each requested route.
## Route points remain owned by PathManager; this node is presentation-only.
class_name PathMovingSegmentRenderer
extends Node3D

signal segments_finished

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Motion")
## World-space travel speed. Animation uses scaled game time supplied by the controller.
@export_range(0.1, 50.0, 0.1, "or_greater") var flow_speed: float = 3.5
## World-space length of the travelling ribbon.
@export_range(0.05, 20.0, 0.05, "or_greater") var segment_length: float = 1.25
## Pause after a ribbon leaves its destination before it restarts at the spawn point.
@export_range(0.0, 30.0, 0.05, "or_greater") var restart_delay: float = 0.75

@export_group("Visual")
@export_range(0.01, 1.0, 0.01, "or_greater") var line_lift: float = 0.14
@export_range(0.005, 1.0, 0.005, "or_greater") var line_width: float = 0.055
@export var line_color: Color = Color(0.82, 0.98, 1.0, 0.96)
@export_range(0.0, 16.0, 0.1, "or_greater") var emission_energy: float = 4.0
## Optional art override. When empty, an unshaded emissive material is generated.
@export var line_material: Material

var _path_manager: PathManager
var _mesh_instance: MeshInstance3D
var _fallback_material: StandardMaterial3D
var _requested_routes: Array[Dictionary] = []
var _route_records: Array[Dictionary] = []
var _flow_elapsed: float = 0.0
var _finish_elapsed: float = 0.0
var _is_finishing: bool = false
var _visible_segment_count: int = 0
var _segment_head_positions: Array[Vector3] = []


func _ready() -> void:
	_ensure_mesh_instance()


func configure(path_manager: PathManager) -> void:
	_disconnect_path_manager()
	_path_manager = path_manager
	if _path_manager != null:
		_path_manager.paths_loaded.connect(_on_paths_loaded)
		_path_manager.runtime_routes_changed.connect(_on_runtime_routes_changed)
	clear_routes()


## Replaces the displayed route set. Identical requests keep their current motion.
func show_routes(routes: Array, reset_motion: bool = true) -> void:
	var normalized := _normalize_requests(routes)
	var changed := _make_request_signature(normalized) != _make_request_signature(_requested_routes)
	_requested_routes = normalized
	_is_finishing = false
	_finish_elapsed = 0.0
	if reset_motion or changed:
		_flow_elapsed = 0.0
	_rebuild_route_records()


func clear_routes() -> void:
	_requested_routes.clear()
	_route_records.clear()
	_flow_elapsed = 0.0
	_finish_elapsed = 0.0
	_is_finishing = false
	_clear_mesh()


## Stops future loops but lets every currently visible segment leave its target.
## Returns false when no generated segment needs a finishing pass.
func finish_current_segments() -> bool:
	if _route_records.is_empty() or not has_visible_geometry():
		clear_routes()
		return false
	var speed := maxf(0.1, flow_speed)
	var has_segment_to_finish := false
	for record in _route_records:
		var total_length: float = float(record["total_length"])
		var travel_duration := total_length / speed
		var cycle_duration := travel_duration + maxf(0.0, restart_delay)
		var local_time := fposmod(_flow_elapsed, maxf(0.000001, cycle_duration))
		if local_time < travel_duration:
			record["finish_local_time"] = local_time
			has_segment_to_finish = true
		else:
			record["finish_local_time"] = -1.0
	if not has_segment_to_finish:
		clear_routes()
		return false
	_is_finishing = true
	_finish_elapsed = 0.0
	return true


## Public deterministic game-time clock for the controller and regressions.
func advance_visual_time(delta: float) -> void:
	if not feature_enabled or _route_records.is_empty():
		_clear_mesh()
		return
	if _is_finishing:
		_finish_elapsed += maxf(0.0, delta)
	else:
		_flow_elapsed += maxf(0.0, delta)
	_rebuild_mesh()
	if _is_finishing and _visible_segment_count == 0:
		_complete_finishing()


func get_active_path_count() -> int:
	return _route_records.size()


func is_finishing() -> bool:
	return _is_finishing


func get_active_path_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for request in _requested_routes:
		var path := request.get("path") as PathDefinition
		if path != null and not ids.has(path.path_id):
			ids.append(path.path_id)
	return ids


func get_visible_segment_count() -> int:
	return _visible_segment_count


func get_segment_head_positions() -> Array[Vector3]:
	return _segment_head_positions.duplicate()


func has_visible_geometry() -> bool:
	return _mesh_instance != null and _mesh_instance.mesh != null


func _normalize_requests(routes: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value in routes:
		var path: PathDefinition
		var airborne := false
		if value is Dictionary:
			path = value.get("path") as PathDefinition
			airborne = bool(value.get("airborne", false))
		else:
			path = value as PathDefinition
		if path == null or path.path_id.is_empty():
			continue
		var key := _profile_key(path.path_id, airborne)
		if seen.has(key):
			continue
		seen[key] = true
		normalized.append({"path": path, "airborne": airborne})
	return normalized


func _rebuild_route_records() -> void:
	_route_records.clear()
	if not feature_enabled or _path_manager == null:
		_clear_mesh()
		return
	var drawn_point_sets: Dictionary = {}
	for request in _requested_routes:
		var path := request.get("path") as PathDefinition
		if path == null:
			continue
		var points := _make_lifted_points(
			_path_manager.get_effective_world_points(path, bool(request.get("airborne", false)))
		)
		if points.size() < 2:
			continue
		var point_signature := str(points)
		if drawn_point_sets.has(point_signature):
			continue
		drawn_point_sets[point_signature] = true
		var cumulative := _build_cumulative_lengths(points)
		var total_length := cumulative[cumulative.size() - 1]
		if total_length <= 0.000001:
			continue
		_route_records.append({
			"points": points,
			"cumulative": cumulative,
			"total_length": total_length,
		})
	_rebuild_mesh()


func _rebuild_mesh() -> void:
	_ensure_mesh_instance()
	_visible_segment_count = 0
	_segment_head_positions.clear()
	if _mesh_instance == null or not feature_enabled or _route_records.is_empty():
		_clear_mesh()
		return
	var mesh := ImmediateMesh.new()
	var material := line_material if line_material != null else _get_fallback_material()
	var surface_started := false
	var speed := maxf(0.1, flow_speed)
	var requested_length := maxf(0.05, segment_length)
	for record in _route_records:
		var points: PackedVector3Array = record["points"]
		var cumulative: PackedFloat32Array = record["cumulative"]
		var total_length: float = float(record["total_length"])
		var travel_duration := total_length / speed
		var cycle_duration := travel_duration + maxf(0.0, restart_delay)
		var local_time := fposmod(_flow_elapsed, maxf(0.000001, cycle_duration))
		if _is_finishing:
			local_time = float(record.get("finish_local_time", -1.0)) + _finish_elapsed
		if local_time >= travel_duration:
			continue
		if local_time < 0.0:
			continue
		var tail_distance := minf(total_length, local_time * speed)
		var head_distance := minf(total_length, tail_distance + requested_length)
		var segment_points := _extract_segment_points(points, cumulative, tail_distance, head_distance)
		if segment_points.size() < 2:
			continue
		if not surface_started:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
			surface_started = true
		_append_ribbon(mesh, segment_points)
		_visible_segment_count += 1
		_segment_head_positions.append(segment_points[segment_points.size() - 1])
	if surface_started:
		mesh.surface_end()
		_mesh_instance.mesh = mesh
	else:
		_mesh_instance.mesh = null


func _extract_segment_points(
	points: PackedVector3Array,
	cumulative: PackedFloat32Array,
	start_distance: float,
	end_distance: float
) -> PackedVector3Array:
	var result := PackedVector3Array()
	if end_distance - start_distance <= 0.000001:
		return result
	result.append(_sample_position(points, cumulative, start_distance))
	for index in range(1, cumulative.size() - 1):
		if cumulative[index] > start_distance + 0.000001 and cumulative[index] < end_distance - 0.000001:
			result.append(points[index])
	var end_position := _sample_position(points, cumulative, end_distance)
	if result[result.size() - 1].distance_squared_to(end_position) > 0.00000001:
		result.append(end_position)
	return result


func _append_ribbon(mesh: ImmediateMesh, points: PackedVector3Array) -> void:
	var half_width := maxf(0.0025, line_width * 0.5)
	var offsets: Array[Vector3] = []
	for point_index in range(points.size()):
		offsets.append(_get_ribbon_offset(points, point_index, half_width))
	for index in range(1, points.size()):
		var start := points[index - 1]
		var end := points[index]
		var start_offset := offsets[index - 1]
		var end_offset := offsets[index]
		if start.distance_squared_to(end) <= 0.00000001:
			continue
		_add_triangle(mesh, start - start_offset, start + start_offset, end + end_offset)
		_add_triangle(mesh, start - start_offset, end + end_offset, end - end_offset)


func _get_ribbon_offset(points: PackedVector3Array, index: int, half_width: float) -> Vector3:
	var previous_side := Vector3.ZERO
	var next_side := Vector3.ZERO
	if index > 0:
		previous_side = _horizontal_side(points[index] - points[index - 1])
	if index + 1 < points.size():
		next_side = _horizontal_side(points[index + 1] - points[index])
	if previous_side == Vector3.ZERO:
		return next_side * half_width
	if next_side == Vector3.ZERO:
		return previous_side * half_width
	var miter := previous_side + next_side
	if miter.length_squared() <= 0.00000001:
		return next_side * half_width
	miter = miter.normalized()
	var projection := maxf(0.5, absf(miter.dot(next_side)))
	return miter * minf(half_width / projection, half_width * 2.0)


func _horizontal_side(direction: Vector3) -> Vector3:
	if direction.length_squared() <= 0.00000001:
		return Vector3.ZERO
	var side := direction.normalized().cross(Vector3.UP)
	if side.length_squared() <= 0.00000001:
		side = direction.normalized().cross(Vector3.RIGHT)
	return side.normalized()


func _add_triangle(mesh: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh.surface_set_normal(Vector3.UP)
	mesh.surface_add_vertex(a)
	mesh.surface_set_normal(Vector3.UP)
	mesh.surface_add_vertex(b)
	mesh.surface_set_normal(Vector3.UP)
	mesh.surface_add_vertex(c)


func _make_lifted_points(source: PackedVector3Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in source:
		points.append(point + Vector3.UP * line_lift)
	return points


func _build_cumulative_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var cumulative := PackedFloat32Array([0.0])
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
		cumulative.append(total)
	return cumulative


func _sample_position(
	points: PackedVector3Array,
	cumulative: PackedFloat32Array,
	distance: float
) -> Vector3:
	for index in range(1, cumulative.size()):
		if distance > cumulative[index]:
			continue
		var segment_start := cumulative[index - 1]
		var current_length := maxf(0.000001, cumulative[index] - segment_start)
		var weight := clampf((distance - segment_start) / current_length, 0.0, 1.0)
		return points[index - 1].lerp(points[index], weight)
	return points[points.size() - 1]


func _get_fallback_material() -> StandardMaterial3D:
	if _fallback_material == null:
		_fallback_material = StandardMaterial3D.new()
	_fallback_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fallback_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fallback_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fallback_material.albedo_color = line_color
	_fallback_material.emission_enabled = true
	_fallback_material.emission = line_color
	_fallback_material.emission_energy_multiplier = emission_energy
	return _fallback_material


func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MovingPathSegments"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


func _clear_mesh() -> void:
	_visible_segment_count = 0
	_segment_head_positions.clear()
	if _mesh_instance != null:
		_mesh_instance.mesh = null


func _make_request_signature(routes: Array[Dictionary]) -> String:
	var keys := PackedStringArray()
	for request in routes:
		var path := request.get("path") as PathDefinition
		if path != null:
			keys.append(_profile_key(path.path_id, bool(request.get("airborne", false))))
	return "|".join(keys)


func _profile_key(path_id: StringName, airborne: bool) -> String:
	return "%s:%s" % [String(path_id), "air" if airborne else "ground"]


func _on_paths_loaded(_level_resource: LevelResource) -> void:
	clear_routes()


func _on_runtime_routes_changed() -> void:
	if not _is_finishing and not _requested_routes.is_empty():
		_rebuild_route_records()


func _complete_finishing() -> void:
	if not _is_finishing:
		return
	_is_finishing = false
	_finish_elapsed = 0.0
	_requested_routes.clear()
	_route_records.clear()
	_clear_mesh()
	segments_finished.emit()


func _disconnect_path_manager() -> void:
	if _path_manager == null:
		return
	if _path_manager.paths_loaded.is_connected(_on_paths_loaded):
		_path_manager.paths_loaded.disconnect(_on_paths_loaded)
	if _path_manager.runtime_routes_changed.is_connected(_on_runtime_routes_changed):
		_path_manager.runtime_routes_changed.disconnect(_on_runtime_routes_changed)
