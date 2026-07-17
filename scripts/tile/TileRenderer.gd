## TileRenderer -- M2 greybox terrain presentation.
##
## This renderer listens to TileManager signals and never changes tile state.
## Terrain uses LevelResource height colors; raised cells expose needed cliff faces.
class_name TileRenderer
extends Node3D

const TOP_LIFT := 0.01

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Obstacle Colors")
@export var obstacle_color: Color = Color(0.45, 0.48, 0.48, 1.0)

@export_group("Terrain Geometry")
@export_range(0.1, 1.0, 0.05) var obstacle_radius_ratio: float = 0.28
@export_range(0.1, 2.0, 0.05) var obstacle_height_ratio: float = 0.6

var _grid: GridManager
var _tile_manager: TileManager
var _terrain_instance: MeshInstance3D
var _terrain_material: StandardMaterial3D
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
	_terrain_instance = MeshInstance3D.new()
	_terrain_material = _make_terrain_material()
	_terrain_instance.material_override = _terrain_material
	add_child(_terrain_instance)
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

func _make_terrain_material() -> StandardMaterial3D:
	var material := _make_material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	return material

func _on_level_loaded(_level_resource: LevelResource) -> void:
	_rebuild()

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	_rebuild()

func _rebuild() -> void:
	if not feature_enabled or _grid == null or _tile_manager == null or _terrain_instance == null:
		return
	var terrain_mesh := ImmediateMesh.new()
	terrain_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_terrain_geometry: bool = false
	var obstacle_mesh := ImmediateMesh.new()
	obstacle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_obstacle_geometry: bool = false
	for cell in _grid.enumerate_cells():
		var tile := _tile_manager.get_tile(cell)
		if tile == null:
			continue
		var terrain_color := _tile_manager.get_height_color(cell)
		var did_add_terrain: bool = _add_tile_geometry(terrain_mesh, tile, terrain_color)
		has_terrain_geometry = has_terrain_geometry or did_add_terrain
		if tile.is_destructible():
			_add_obstacle_geometry(obstacle_mesh, tile)
			has_obstacle_geometry = true
	if has_terrain_geometry:
		terrain_mesh.surface_end()
		_terrain_instance.mesh = terrain_mesh
	else:
		_terrain_instance.mesh = null
	if has_obstacle_geometry:
		obstacle_mesh.surface_end()
		_obstacle_instance.mesh = obstacle_mesh
	else:
		_obstacle_instance.mesh = null

func _add_tile_geometry(mesh: ImmediateMesh, tile: TileCellData, terrain_color: Color) -> bool:
	var corners := _grid.get_corners(tile.cell)
	if corners.size() < 3:
		return false
	var top_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT
	var center := _grid.cell_to_world(tile.cell) + Vector3(0.0, top_y, 0.0)
	for index in range(corners.size()):
		var a := corners[index] + Vector3(0.0, top_y, 0.0)
		var b := corners[(index + 1) % corners.size()] + Vector3(0.0, top_y, 0.0)
		_add_triangle(mesh, terrain_color, center, a, b)
		var neighbor_cell := _grid.neighbor_across_edge(tile.cell, index)
		var neighbor_top := _tile_manager.get_world_height(neighbor_cell) + TOP_LIFT
		if top_y <= neighbor_top + 0.001:
			continue
		var lower_a := Vector3(a.x, neighbor_top, a.z)
		var lower_b := Vector3(b.x, neighbor_top, b.z)
		_add_triangle(mesh, terrain_color, a, lower_a, lower_b)
		_add_triangle(mesh, terrain_color, a, lower_b, b)
	return true

func _add_triangle(mesh: ImmediateMesh, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(c)

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
