## TileRenderer -- M2 greybox terrain presentation.
##
## This renderer listens to TileManager signals and never changes tile state.
## Meshes are batched by terrain type; raised cells only expose needed cliff faces.
class_name TileRenderer
extends Node3D

const TILE_TYPE_COUNT := 3
const TOP_LIFT := 0.01

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Terrain Colors")
@export var buildable_color: Color = Color(0.18, 0.48, 0.34, 1.0)
@export var destructible_color: Color = Color(0.63, 0.36, 0.16, 1.0)
@export var blocked_color: Color = Color(0.23, 0.29, 0.36, 1.0)
@export var obstacle_color: Color = Color(0.45, 0.48, 0.48, 1.0)

@export_group("Terrain Geometry")
@export_range(0.1, 1.0, 0.05) var obstacle_radius_ratio: float = 0.28
@export_range(0.1, 2.0, 0.05) var obstacle_height_ratio: float = 0.6

var _grid: GridManager
var _tile_manager: TileManager
var _tile_instances: Array[MeshInstance3D] = []
var _tile_materials: Array[StandardMaterial3D] = []
var _obstacle_instance: MeshInstance3D
var _obstacle_material: StandardMaterial3D

func _ready() -> void:
	_setup_instances()

func set_grid(value: GridManager) -> void:
	if _grid != null and _grid.grid_changed.is_connected(_rebuild):
		_grid.grid_changed.disconnect(_rebuild)
	_grid = value
	if is_node_ready() and _grid != null:
		if not _grid.grid_changed.is_connected(_rebuild):
			_grid.grid_changed.connect(_rebuild)
		_rebuild()

func set_tile_manager(value: TileManager) -> void:
	if _tile_manager != null:
		if _tile_manager.level_loaded.is_connected(_on_level_loaded):
			_tile_manager.level_loaded.disconnect(_on_level_loaded)
		if _tile_manager.tile_changed.is_connected(_on_tile_changed):
			_tile_manager.tile_changed.disconnect(_on_tile_changed)
	_tile_manager = value
	if is_node_ready() and _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)
		_tile_manager.tile_changed.connect(_on_tile_changed)
		_rebuild()

func _setup_instances() -> void:
	var colors: Array[Color] = [buildable_color, destructible_color, blocked_color]
	for index in range(TILE_TYPE_COUNT):
		var instance := MeshInstance3D.new()
		var material := _make_material(colors[index])
		instance.material_override = material
		_tile_instances.append(instance)
		_tile_materials.append(material)
		add_child(instance)
	_obstacle_instance = MeshInstance3D.new()
	_obstacle_material = _make_material(obstacle_color)
	_obstacle_instance.material_override = _obstacle_material
	add_child(_obstacle_instance)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _on_level_loaded(_level_resource: LevelResource) -> void:
	_rebuild()

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	_rebuild()

func _rebuild() -> void:
	if not feature_enabled or _grid == null or _tile_manager == null or _tile_instances.is_empty():
		return
	var terrain_meshes: Array[ImmediateMesh] = []
	for index in range(TILE_TYPE_COUNT):
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		terrain_meshes.append(mesh)
	var obstacle_mesh := ImmediateMesh.new()
	obstacle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in _grid.enumerate_cells():
		var tile := _tile_manager.get_tile(cell)
		if tile == null:
			continue
		var type_index := int(tile.tile_type)
		if type_index < 0 or type_index >= TILE_TYPE_COUNT:
			continue
		_add_tile_geometry(terrain_meshes[type_index], tile)
		if tile.is_destructible():
			_add_obstacle_geometry(obstacle_mesh, tile)
	for index in range(TILE_TYPE_COUNT):
		terrain_meshes[index].surface_end()
		_tile_instances[index].mesh = terrain_meshes[index]
	obstacle_mesh.surface_end()
	_obstacle_instance.mesh = obstacle_mesh

func _add_tile_geometry(mesh: ImmediateMesh, tile: TileCellData) -> void:
	var corners := _grid.get_corners(tile.cell)
	if corners.size() < 3:
		return
	var top_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT
	var center := _grid.cell_to_world(tile.cell) + Vector3(0.0, top_y, 0.0)
	for index in range(corners.size()):
		var a := corners[index] + Vector3(0.0, top_y, 0.0)
		var b := corners[(index + 1) % corners.size()] + Vector3(0.0, top_y, 0.0)
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(b)
		var neighbor_cell := _grid.neighbor_across_edge(tile.cell, index)
		var neighbor_top := _tile_manager.get_world_height(neighbor_cell) + TOP_LIFT
		if top_y <= neighbor_top + 0.001:
			continue
		var lower_a := Vector3(a.x, neighbor_top, a.z)
		var lower_b := Vector3(b.x, neighbor_top, b.z)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(lower_a)
		mesh.surface_add_vertex(lower_b)
		mesh.surface_add_vertex(a)
		mesh.surface_add_vertex(lower_b)
		mesh.surface_add_vertex(b)

func _add_obstacle_geometry(mesh: ImmediateMesh, tile: TileCellData) -> void:
	var center := _grid.cell_to_world(tile.cell)
	var base_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT
	var radius := _grid.cell_size * obstacle_radius_ratio
	var top := center + Vector3(0.0, base_y + _grid.cell_size * obstacle_height_ratio, 0.0)
	var base: Array[Vector3] = [
		center + Vector3(radius, base_y, 0.0),
		center + Vector3(0.0, base_y, radius),
		center + Vector3(-radius, base_y, 0.0),
		center + Vector3(0.0, base_y, -radius),
	]
	for index in range(base.size()):
		mesh.surface_add_vertex(top)
		mesh.surface_add_vertex(base[index])
		mesh.surface_add_vertex(base[(index + 1) % base.size()])
