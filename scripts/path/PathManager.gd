## Runtime entry point for M4 paths, spawn positions, and path visualization.
class_name PathManager
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Debug Visual")
@export var show_paths: bool = true
@export var path_color: Color = Color(0.95, 0.91, 0.30, 1.0)
@export var spawn_color: Color = Color(0.30, 0.92, 0.56, 1.0)
@export_range(0.01, 1.0, 0.01, "or_greater") var line_lift: float = 0.08

signal paths_loaded(level_resource: LevelResource)
signal runtime_routes_changed

var _grid: GridManager
var _tile_manager: TileManager
var _level: LevelResource
var _path_index: Dictionary = {}
var _path_mesh: MeshInstance3D
var _marker_root: Node3D
var _runtime_paths_visible: bool = false
var _runtime_path_ids: Dictionary = {}
var _runtime_route_snapshot: Dictionary = {}

func _ready() -> void:
	_path_mesh = MeshInstance3D.new()
	add_child(_path_mesh)
	_marker_root = Node3D.new()
	add_child(_marker_root)

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager

func load_level(level_resource: LevelResource) -> void:
	_level = level_resource
	_path_index.clear()
	_runtime_route_snapshot.clear()
	if _level != null:
		for path in _level.paths:
			if path != null and not path.path_id.is_empty():
				_path_index[path.path_id] = path
	_rebuild_visuals()
	paths_loaded.emit(_level)


## Rebuilds height-dependent paths and spawn markers without replacing data.
func refresh_surface_positions() -> void:
	_rebuild_visuals()

func get_path_definition(path_id: StringName) -> PathDefinition:
	if not _path_index.has(path_id):
		return null
	var path: PathDefinition = _path_index[path_id]
	return path

func get_world_points(path: PathDefinition) -> PackedVector3Array:
	var points := PackedVector3Array()
	if path == null:
		return points
	for cell in path.cells:
		points.append(get_cell_world_position(cell))
	return points


## Returns the periodically refreshed route used by runtime path visuals. The
## authored get_world_points() contract remains unchanged for enemy spawning.
func get_effective_world_points(path: PathDefinition, airborne: bool = false) -> PackedVector3Array:
	var points := PackedVector3Array()
	if path == null:
		return points
	var entry: Variant = _runtime_route_snapshot.get(path.path_id, path.cells)
	var source: Array = path.cells
	if entry is Dictionary:
		var profile_key := "airborne" if airborne else "ground"
		source = entry.get(profile_key, path.cells)
	elif entry is Array:
		source = entry
	for value in source:
		if value is Vector3i:
			points.append(get_cell_world_position(value))
	return points

func get_cell_world_position(cell: Vector3i) -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	var height := _tile_manager.get_world_height(cell) if _tile_manager != null else 0.0
	return _grid.cell_to_world(cell) + Vector3(0.0, height + line_lift, 0.0)

func is_path_valid(path: PathDefinition) -> bool:
	if _grid == null or path == null or path.cells.size() < 2:
		return false
	for index in range(path.cells.size()):
		var cell := path.cells[index]
		if not _grid.is_in_bounds(cell):
			return false
		if index > 0 and not _grid.get_neighbors(path.cells[index - 1]).has(cell):
			return false
	return true


func get_spawn_marker_labels() -> Array[String]:
	var labels: Array[String] = []
	if _marker_root == null:
		return labels
	for marker_root in _marker_root.get_children():
		for child in marker_root.get_children():
			if child is Label3D:
				labels.append((child as Label3D).text)
	return labels


func set_debug_paths_visible(enabled: bool) -> void:
	if show_paths == enabled:
		return
	show_paths = enabled
	_rebuild_path_visual()


## Controls the phase-driven runtime layer independently from the debug path
## category. An empty path list means all authored paths.
func set_runtime_path_display(enabled: bool, paths: Array = []) -> void:
	var next_ids: Dictionary = {}
	for value in paths:
		var path: PathDefinition
		var airborne := false
		if value is Dictionary:
			path = value.get("path") as PathDefinition
			airborne = bool(value.get("airborne", false))
		else:
			path = value as PathDefinition
		if path != null and not path.path_id.is_empty():
			next_ids[_profile_key(path.path_id, airborne)] = true
	if _runtime_paths_visible == enabled and _runtime_path_ids == next_ids:
		return
	_runtime_paths_visible = enabled
	_runtime_path_ids = next_ids
	_rebuild_path_visual()


func is_runtime_path_display_visible() -> bool:
	return _runtime_paths_visible


func get_runtime_path_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for route_key in _runtime_path_ids.keys():
		var path_id := StringName(String(route_key).get_slice("|", 0))
		if not ids.has(path_id):
			ids.append(path_id)
	return ids


## Receives path_id -> {ground, airborne} presentation snapshots from the route
## planner. The copy prevents a renderer from mutating navigation cache state.
func set_runtime_route_snapshot(snapshot: Dictionary) -> void:
	_runtime_route_snapshot = snapshot.duplicate(true)
	_rebuild_path_visual()
	runtime_routes_changed.emit()

func _rebuild_visuals() -> void:
	if _path_mesh == null or _marker_root == null:
		return
	_rebuild_path_visual()
	for child in _marker_root.get_children():
		child.queue_free()
	if not feature_enabled or _level == null:
		return
	for spawn_point in _level.spawn_points:
		if spawn_point != null:
			_create_spawn_marker(spawn_point)


func _rebuild_path_visual() -> void:
	if _path_mesh == null:
		return
	if not feature_enabled or _level == null or (not show_paths and not _runtime_paths_visible):
		_path_mesh.mesh = null
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = path_color
	material.emission_enabled = true
	material.emission = path_color
	material.emission_energy_multiplier = 1.3
	var mesh := ImmediateMesh.new()
	var has_path_geometry: bool = false
	var drawn_route_signatures: Dictionary = {}
	for path in _level.paths:
		if path == null:
			continue
		if show_paths:
			has_path_geometry = _append_path_geometry(
				mesh,
				material,
				get_world_points(path),
				has_path_geometry,
				drawn_route_signatures
			)
		if not _runtime_paths_visible:
			continue
		for airborne in _get_runtime_profiles(path):
			has_path_geometry = _append_path_geometry(
				mesh,
				material,
				get_effective_world_points(path, airborne),
				has_path_geometry,
				drawn_route_signatures
			)
	if has_path_geometry:
		mesh.surface_end()
		_path_mesh.mesh = mesh
	else:
		_path_mesh.mesh = null


func _append_path_geometry(
	mesh: ImmediateMesh,
	material: Material,
	points: PackedVector3Array,
	has_geometry: bool,
	drawn_signatures: Dictionary
) -> bool:
	if points.size() < 2:
		return has_geometry
	var signature := str(points)
	if drawn_signatures.has(signature):
		return has_geometry
	drawn_signatures[signature] = true
	if not has_geometry:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		has_geometry = true
	for index in range(1, points.size()):
		mesh.surface_add_vertex(points[index - 1])
		mesh.surface_add_vertex(points[index])
	return has_geometry


func _get_runtime_profiles(path: PathDefinition) -> Array[bool]:
	var profiles: Array[bool] = []
	if _runtime_path_ids.is_empty():
		profiles.append(false)
		return profiles
	if _runtime_path_ids.has(_profile_key(path.path_id, false)):
		profiles.append(false)
	if _runtime_path_ids.has(_profile_key(path.path_id, true)):
		profiles.append(true)
	return profiles


func _profile_key(path_id: StringName, airborne: bool) -> String:
	return "%s|%s" % [String(path_id), "airborne" if airborne else "ground"]

func _create_spawn_marker(spawn_point: SpawnPointDefinition) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "SpawnPoint_%s" % str(spawn_point.spawn_id)
	marker_root.position = get_cell_world_position(spawn_point.cell)
	_marker_root.add_child(marker_root)
	var model_asset := (
		_level.get_spawn_point_model_asset(spawn_point)
		if _level != null
		else spawn_point.get_model_asset()
	)
	var visual_root := (
		model_asset.instantiate_grounded_model(&"SpawnPointModel")
		if model_asset != null
		else null
	)
	if visual_root != null:
		marker_root.add_child(visual_root)
	else:
		_build_spawn_fallback(marker_root)
	var label := Label3D.new()
	label.position = Vector3(0.0, 0.72, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 26
	label.text = _level.get_spawn_marker_label(spawn_point) if _level != null else spawn_point.display_name
	marker_root.add_child(label)


func _build_spawn_fallback(marker_root: Node3D) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "SpawnPointFallback"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.25
	mesh.height = 0.5
	marker.mesh = mesh
	marker.position = Vector3(0.0, 0.25, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = spawn_color
	material.emission_enabled = true
	material.emission = spawn_color
	material.emission_energy_multiplier = 1.2
	marker.material_override = material
	marker_root.add_child(marker)
