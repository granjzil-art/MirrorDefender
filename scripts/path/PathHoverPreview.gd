## Pure presentation overlay for fast, looping direction flow on hovered wave paths.
class_name PathHoverPreview
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Flow")
@export_range(0.1, 50.0, 0.1, "or_greater") var flow_speed: float = 5.5
@export_range(1, 16, 1) var markers_per_path: int = 5
@export_range(0.01, 1.0, 0.01, "or_greater") var line_lift: float = 0.20
@export_range(0.01, 1.0, 0.01, "or_greater") var marker_radius: float = 0.09

@export_group("Visual")
@export var line_color: Color = Color(0.24, 0.92, 1.0, 0.92)
@export var marker_color: Color = Color(0.82, 1.0, 1.0, 1.0)
@export_range(0.0, 16.0, 0.1, "or_greater") var emission_energy: float = 4.0
@export var line_material: Material
@export var marker_material: Material
@export var marker_mesh: Mesh

var _path_manager: PathManager
var _line_mesh: MeshInstance3D
var _marker_root: Node3D
var _preview_records: Array[Dictionary] = []
var _flow_elapsed: float = 0.0
var _last_ticks_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = feature_enabled
	_line_mesh = MeshInstance3D.new()
	_line_mesh.name = "FlowLines"
	add_child(_line_mesh)
	_marker_root = Node3D.new()
	_marker_root.name = "FlowMarkers"
	add_child(_marker_root)
	_last_ticks_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	var real_delta := minf(0.1, maxf(0.0, float(now_usec - _last_ticks_usec) / 1000000.0))
	_last_ticks_usec = now_usec
	advance_visual_time(real_delta)


func configure(path_manager: PathManager) -> void:
	_disconnect_path_manager()
	_path_manager = path_manager
	if _path_manager != null:
		_path_manager.paths_loaded.connect(_on_paths_loaded)
	clear_preview()


func preview_paths(paths: Array) -> void:
	clear_preview()
	if not feature_enabled or _path_manager == null:
		return
	for value in paths:
		var path := value as PathDefinition
		if path == null:
			continue
		var points := _make_lifted_points(_path_manager.get_world_points(path))
		if points.size() < 2:
			continue
		var cumulative := _build_cumulative_lengths(points)
		var total_length := cumulative[cumulative.size() - 1]
		if total_length <= 0.000001:
			continue
		_preview_records.append({
			"path": path,
			"points": points,
			"cumulative": cumulative,
			"total_length": total_length,
			"markers": _create_markers(),
		})
	_rebuild_lines()
	advance_visual_time(0.0)


func clear_preview() -> void:
	_preview_records.clear()
	_flow_elapsed = 0.0
	if _line_mesh != null:
		_line_mesh.mesh = null
	if _marker_root != null:
		for child in _marker_root.get_children():
			child.queue_free()


func advance_visual_time(real_delta: float) -> void:
	if not feature_enabled or _preview_records.is_empty():
		return
	_flow_elapsed += maxf(0.0, real_delta)
	for record in _preview_records:
		var points: PackedVector3Array = record["points"]
		var cumulative: PackedFloat32Array = record["cumulative"]
		var total_length: float = float(record["total_length"])
		var markers: Array = record["markers"]
		for marker_index in range(markers.size()):
			var marker := markers[marker_index] as MeshInstance3D
			if marker == null or not is_instance_valid(marker):
				continue
			var phase := total_length * float(marker_index) / float(maxi(1, markers.size()))
			var distance := fposmod(_flow_elapsed * flow_speed + phase, total_length)
			marker.position = _sample_position(points, cumulative, distance)


func get_active_path_count() -> int:
	return _preview_records.size()


func get_marker_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for record in _preview_records:
		var markers: Array = record["markers"]
		for value in markers:
			var marker := value as MeshInstance3D
			if marker != null and is_instance_valid(marker):
				positions.append(marker.position)
	return positions


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
		var segment_length := maxf(0.000001, cumulative[index] - segment_start)
		var weight := clampf((distance - segment_start) / segment_length, 0.0, 1.0)
		return points[index - 1].lerp(points[index], weight)
	return points[points.size() - 1]


func _rebuild_lines() -> void:
	if _line_mesh == null:
		return
	var mesh := ImmediateMesh.new()
	var material := line_material if line_material != null else _make_material(line_color)
	for record in _preview_records:
		var points: PackedVector3Array = record["points"]
		if points.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for point in points:
			mesh.surface_add_vertex(point)
		mesh.surface_end()
	_line_mesh.mesh = mesh if not _preview_records.is_empty() else null


func _create_markers() -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []
	for _index in range(markers_per_path):
		var marker := MeshInstance3D.new()
		marker.mesh = marker_mesh if marker_mesh != null else _make_marker_mesh()
		marker.material_override = marker_material if marker_material != null else _make_material(marker_color)
		_marker_root.add_child(marker)
		markers.append(marker)
	return markers


func _make_marker_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = marker_radius
	sphere.height = marker_radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return sphere


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _on_paths_loaded(_level: LevelResource) -> void:
	clear_preview()


func _disconnect_path_manager() -> void:
	if _path_manager != null and _path_manager.paths_loaded.is_connected(_on_paths_loaded):
		_path_manager.paths_loaded.disconnect(_on_paths_loaded)
