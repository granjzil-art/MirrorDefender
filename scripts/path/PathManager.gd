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

var _grid: GridManager
var _tile_manager: TileManager
var _level: LevelResource
var _path_index: Dictionary = {}
var _path_mesh: MeshInstance3D
var _marker_root: Node3D

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
	if _level != null:
		for path in _level.paths:
			if path != null and not path.path_id.is_empty():
				_path_index[path.path_id] = path
	_rebuild_visuals()
	paths_loaded.emit(_level)

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

func _rebuild_visuals() -> void:
	if _path_mesh == null or _marker_root == null:
		return
	for child in _marker_root.get_children():
		child.queue_free()
	if not feature_enabled or not show_paths or _level == null:
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
	for path in _level.paths:
		if path == null:
			continue
		var points := get_world_points(path)
		for index in range(1, points.size()):
			if not has_path_geometry:
				mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
				has_path_geometry = true
			mesh.surface_add_vertex(points[index - 1])
			mesh.surface_add_vertex(points[index])
	if has_path_geometry:
		mesh.surface_end()
		_path_mesh.mesh = mesh
	else:
		_path_mesh.mesh = null
	for spawn_point in _level.spawn_points:
		if spawn_point != null:
			_create_spawn_marker(spawn_point)

func _create_spawn_marker(spawn_point: SpawnPointDefinition) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.25
	mesh.height = 0.5
	marker.mesh = mesh
	marker.position = get_cell_world_position(spawn_point.cell) + Vector3(0.0, 0.25, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = spawn_color
	material.emission_enabled = true
	material.emission = spawn_color
	material.emission_energy_multiplier = 1.2
	marker.material_override = material
	_marker_root.add_child(marker)
