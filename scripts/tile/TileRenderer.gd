## TileRenderer -- M2 greybox terrain presentation.
##
## This renderer listens to TileManager signals and never changes tile state.
## Terrain uses LevelResource path/height colors; raised cells expose needed cliff faces.
class_name TileRenderer
extends Node3D

const TOP_LIFT := 0.01

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Obstacle Colors")
@export var blocked_color: Color = Color(0.34, 0.37, 0.40, 1.0)
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
var _element_instance: MeshInstance3D
var _element_material: StandardMaterial3D
var _path_cells: Dictionary = {}
var _path_terrain_color: Color = Color("ffb93b")
var _effect_visual_state_resolver: Callable

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
		_cache_path_terrain(_tile_manager.get_level_resource())
		_rebuild()

func set_effect_visual_state_resolver(value: Callable) -> void:
	_effect_visual_state_resolver = value
	_rebuild()

func refresh_effect_visual(_source_cell: Vector3i = Vector3i.ZERO, _fill_ratio: float = 0.0) -> void:
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
	_element_instance = MeshInstance3D.new()
	_element_material = _make_terrain_material()
	_element_instance.material_override = _element_material
	add_child(_element_instance)

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

func _on_level_loaded(level_resource: LevelResource) -> void:
	_cache_path_terrain(level_resource)
	_rebuild()

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	_rebuild()

func is_path_terrain_cell(cell: Vector3i) -> bool:
	return _path_cells.has(cell)

func get_base_terrain_color(cell: Vector3i) -> Color:
	var tile := _tile_manager.get_tile(cell) if _tile_manager != null else null
	if tile == null:
		return Color.WHITE
	if is_path_terrain_cell(cell):
		return _path_terrain_color
	var fallback := blocked_color if tile.is_blocked() else _tile_manager.get_height_color(cell)
	return tile.get_terrain_color(fallback)

func create_tile_visual_snapshot(cell: Vector3i) -> Node3D:
	return _create_tile_visual_snapshot(cell, true)

func create_tile_content_visual_snapshot(cell: Vector3i) -> Node3D:
	return _create_tile_visual_snapshot(cell, false)

func _create_tile_visual_snapshot(cell: Vector3i, include_base_terrain: bool) -> Node3D:
	if not feature_enabled or _grid == null or _tile_manager == null:
		return null
	var tile := _tile_manager.get_tile(cell)
	if tile == null:
		return null
	var snapshot := Node3D.new()
	snapshot.name = "TileVisualSnapshot" if include_base_terrain else "TileContentVisualSnapshot"
	if include_base_terrain:
		var terrain_mesh := ImmediateMesh.new()
		terrain_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if _add_tile_geometry(terrain_mesh, tile, get_base_terrain_color(tile.cell)):
			terrain_mesh.surface_end()
			_add_snapshot_instance(snapshot, terrain_mesh, _terrain_material, "Terrain")
	if tile.is_destructible():
		var obstacle_mesh := ImmediateMesh.new()
		obstacle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_obstacle_geometry(obstacle_mesh, tile)
		obstacle_mesh.surface_end()
		_add_snapshot_instance(snapshot, obstacle_mesh, _obstacle_material, "Obstacle")
	if tile.get_visual_kind() != TileDefinition.VisualKind.NONE:
		var element_mesh := ImmediateMesh.new()
		element_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if _add_element_geometry(element_mesh, tile):
			element_mesh.surface_end()
			_add_snapshot_instance(snapshot, element_mesh, _element_material, "Element")
	return snapshot

func _add_snapshot_instance(parent: Node3D, mesh: Mesh, source_material: Material, instance_name: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	instance.material_override = source_material.duplicate() if source_material != null else null
	parent.add_child(instance)

func _rebuild() -> void:
	if not feature_enabled or _grid == null or _tile_manager == null or _terrain_instance == null:
		return
	var terrain_mesh := ImmediateMesh.new()
	terrain_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_terrain_geometry: bool = false
	var obstacle_mesh := ImmediateMesh.new()
	obstacle_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_obstacle_geometry: bool = false
	var element_mesh := ImmediateMesh.new()
	element_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_element_geometry: bool = false
	for cell in _grid.enumerate_cells():
		var tile := _tile_manager.get_tile(cell)
		if tile == null:
			continue
		var terrain_color := get_base_terrain_color(tile.cell)
		var did_add_terrain: bool = _add_tile_geometry(terrain_mesh, tile, terrain_color)
		has_terrain_geometry = has_terrain_geometry or did_add_terrain
		if tile.is_destructible():
			_add_obstacle_geometry(obstacle_mesh, tile)
			has_obstacle_geometry = true
		if tile.get_visual_kind() != TileDefinition.VisualKind.NONE:
			has_element_geometry = _add_element_geometry(element_mesh, tile) or has_element_geometry
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
	if has_element_geometry:
		element_mesh.surface_end()
		_element_instance.mesh = element_mesh
	else:
		_element_instance.mesh = null

func _cache_path_terrain(level_resource: LevelResource) -> void:
	_path_cells.clear()
	_path_terrain_color = Color("ffb93b")
	if level_resource == null:
		return
	_path_terrain_color = level_resource.path_terrain_color
	for path in level_resource.paths:
		if path == null:
			continue
		for cell in path.cells:
			_path_cells[cell] = true

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

func _add_element_geometry(mesh: ImmediateMesh, tile: TileCellData) -> bool:
	var color := tile.get_visual_color()
	match tile.get_visual_kind():
		TileDefinition.VisualKind.SPIKES:
			_add_spikes(mesh, tile, color)
			return true
		TileDefinition.VisualKind.HOLE:
			return _add_hole(mesh, tile, color)
		TileDefinition.VisualKind.ROCK:
			_add_rock(mesh, tile, color)
			return true
	return false

func _add_spikes(mesh: ImmediateMesh, tile: TileCellData, color: Color) -> void:
	var center := _grid.cell_to_world(tile.cell)
	var base_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT * 2.0
	var spread := _grid.cell_size * 0.18
	var radius := _grid.cell_size * 0.10
	var offsets: Array[Vector3] = [
		Vector3(-spread, 0.0, -spread),
		Vector3(spread, 0.0, -spread),
		Vector3(-spread, 0.0, spread),
		Vector3(spread, 0.0, spread),
	]
	for offset in offsets:
		var spike_center := center + offset
		var top := Vector3(spike_center.x, base_y + _grid.cell_size * 0.28, spike_center.z)
		var base: Array[Vector3] = [
			Vector3(spike_center.x + radius, base_y, spike_center.z),
			Vector3(spike_center.x, base_y, spike_center.z + radius),
			Vector3(spike_center.x - radius, base_y, spike_center.z),
			Vector3(spike_center.x, base_y, spike_center.z - radius),
		]
		for index in range(base.size()):
			_add_triangle(mesh, color, top, base[index], base[(index + 1) % base.size()])

func _add_hole(mesh: ImmediateMesh, tile: TileCellData, color: Color) -> bool:
	var corners := _grid.get_corners(tile.cell)
	if corners.size() < 3:
		return false
	var effect := tile.get_effect() as VoidTileEffect
	var fill_ratio := 0.0
	if _effect_visual_state_resolver.is_valid():
		var resolved: Variant = _effect_visual_state_resolver.call(tile.cell)
		if resolved is float or resolved is int:
			fill_ratio = clampf(float(resolved), 0.0, 1.0)
	var empty_depth := effect.empty_depth_ratio if effect != null else 0.30
	var full_depth := effect.full_depth_ratio if effect != null else 0.03
	var depth := lerpf(empty_depth, full_depth, fill_ratio) * _grid.cell_size
	var base_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT * 2.0
	var rim_y := base_y + empty_depth * _grid.cell_size
	var world_center := _grid.cell_to_world(tile.cell)
	var center := Vector3(world_center.x, rim_y - depth, world_center.z)
	for index in range(corners.size()):
		var corner_a := corners[index]
		var corner_b := corners[(index + 1) % corners.size()]
		var a := Vector3(world_center.x, rim_y, world_center.z).lerp(Vector3(corner_a.x, rim_y, corner_a.z), 0.58)
		var b := Vector3(world_center.x, rim_y, world_center.z).lerp(Vector3(corner_b.x, rim_y, corner_b.z), 0.58)
		_add_triangle(mesh, color.lightened(fill_ratio * 0.16), center, a, b)
	return true

func _add_rock(mesh: ImmediateMesh, tile: TileCellData, color: Color) -> void:
	var center := _grid.cell_to_world(tile.cell)
	var base_y := _tile_manager.get_world_height(tile.cell) + TOP_LIFT
	var radius := _grid.cell_size * 0.38
	var shoulder_y := base_y + _grid.cell_size * 0.32
	var top := Vector3(center.x - radius * 0.12, base_y + _grid.cell_size * 0.72, center.z + radius * 0.08)
	var ring: Array[Vector3] = []
	var sides := maxi(4, _grid.edge_count())
	for index in range(sides):
		var angle := TAU * float(index) / float(sides)
		var scale := 0.82 if index % 2 == 0 else 1.0
		ring.append(Vector3(
			center.x + cos(angle) * radius * scale,
			shoulder_y,
			center.z + sin(angle) * radius * scale
		))
	for index in range(ring.size()):
		var next_index := (index + 1) % ring.size()
		_add_triangle(mesh, color, top, ring[index], ring[next_index])
		var base_a := Vector3(ring[index].x, base_y, ring[index].z)
		var base_b := Vector3(ring[next_index].x, base_y, ring[next_index].z)
		_add_triangle(mesh, color.darkened(0.18), ring[index], base_a, base_b)
		_add_triangle(mesh, color.darkened(0.18), ring[index], base_b, ring[next_index])
