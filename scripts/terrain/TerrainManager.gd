## TerrainManager -- canonical runtime state and surface query boundary for Grid.
##
## It reads LevelResource's effective Grid/Ramp snapshot, so legacy levels pass
## through the migration adapter without mutating their serialized resources.
class_name TerrainManager
extends Node3D

const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const TerrainModelMetricsScript := preload("res://scripts/terrain/TerrainModelMetrics.gd")
const CANONICAL_CONTENT_VERSION: int = 2

@export_group("Feature")
@export var feature_enabled: bool = true

signal terrain_loaded(level_resource: LevelResource)
signal terrain_cleared

var _grid: GridManager
var _level: LevelResource
var _default_terrain: TerrainDefinitionScript
var _layer_height: float = TerrainModelMetricsScript.DEFAULT_LAYER_HEIGHT
var _grid_cells: Dictionary = {}
var _ramps: Array[RampPlacementDataScript] = []
var _ramp_bindings: Dictionary = {}
var _path_cells: Dictionary = {}
var _base_footprint_owners: Dictionary = {}
var _uses_legacy_snapshot: bool = false


func set_grid(value: GridManager) -> void:
	_grid = value


## Builds and commits canonical terrain runtime state. Failure leaves the
## previously loaded terrain untouched.
func load_level(level_resource: LevelResource) -> bool:
	if not feature_enabled or level_resource == null or _grid == null or _grid.get_shape() == null:
		return false
	if not level_resource.validate_runtime().is_empty():
		return false
	if (
		int(_grid.grid_shape) != level_resource.grid_shape
		or not is_equal_approx(_grid.cell_size, level_resource.grid_cell_size)
		or _grid.grid_size != level_resource.grid_size
	):
		return false
	var snapshot := level_resource.get_effective_content_snapshot()
	var next_default: TerrainDefinitionScript = snapshot.get("default_terrain") as TerrainDefinitionScript
	var next_layer_height := float(snapshot.get("layer_height", 0.0))
	if next_default == null or not is_finite(next_layer_height) or next_layer_height <= 0.0:
		return false
	var next_cells: Dictionary = {}
	for raw_cell in snapshot.get("grid_cells", []):
		if not raw_cell is GridCellDataScript:
			return false
		var source_cell: GridCellDataScript = raw_cell
		if not _grid.is_in_bounds(source_cell.cell):
			continue
		next_cells[source_cell.cell] = _clone_grid_cell(source_cell)
	for cell in _grid.enumerate_cells():
		if next_cells.has(cell):
			continue
		var default_cell := GridCellDataScript.new()
		default_cell.configure(cell, next_default, 1, true, true)
		next_cells[cell] = default_cell
	var next_ramps: Array[RampPlacementDataScript] = []
	var next_bindings: Dictionary = {}
	for raw_ramp in snapshot.get("ramp_placements", []):
		if not raw_ramp is RampPlacementDataScript:
			return false
		var ramp := _clone_ramp(raw_ramp)
		var footprint := ramp.get_footprint_cells(_grid.get_shape())
		if footprint.size() != ramp.run_length:
			return false
		for footprint_index in range(footprint.size()):
			var ramp_cell: Vector3i = footprint[footprint_index]
			if not next_cells.has(ramp_cell) or next_bindings.has(ramp_cell):
				return false
			next_bindings[ramp_cell] = {"ramp": ramp, "index": footprint_index}
		next_ramps.append(ramp)
	var next_paths: Dictionary = {}
	for path in level_resource.paths:
		if path == null:
			continue
		for path_cell in path.cells:
			next_paths[path_cell] = true
	var next_base_owners: Dictionary = {}
	for base_point in level_resource.get_effective_base_points():
		if base_point == null:
			continue
		for footprint_cell in base_point.get_footprint_cells():
			next_base_owners[footprint_cell] = base_point.base_id
	_level = level_resource
	_default_terrain = next_default
	_layer_height = next_layer_height
	_grid_cells = next_cells
	_ramps = next_ramps
	_ramp_bindings = next_bindings
	_path_cells = next_paths
	_base_footprint_owners = next_base_owners
	_uses_legacy_snapshot = bool(snapshot.get("migrated", false))
	terrain_loaded.emit(level_resource)
	return true


func clear_level() -> void:
	_level = null
	_default_terrain = null
	_grid_cells.clear()
	_ramps.clear()
	_ramp_bindings.clear()
	_path_cells.clear()
	_base_footprint_owners.clear()
	_uses_legacy_snapshot = false
	terrain_cleared.emit()


func get_level_resource() -> LevelResource:
	return _level


func get_grid_shape() -> IGridShape:
	return _grid.get_shape() if _grid != null else null


func get_grid_cell(cell: Vector3i) -> GridCellDataScript:
	return _grid_cells.get(cell) as GridCellDataScript


func get_grid_cells() -> Array[GridCellDataScript]:
	var out: Array[GridCellDataScript] = []
	if _grid == null:
		return out
	for cell in _grid.enumerate_cells():
		var grid_cell := get_grid_cell(cell)
		if grid_cell != null:
			out.append(grid_cell)
	return out


## Returns detached canonical Grid data suitable for authoring snapshots.
func export_grid_cells() -> Array[GridCellDataScript]:
	var out: Array[GridCellDataScript] = []
	for source in get_grid_cells():
		out.append(_clone_grid_cell(source))
	return out


## Returns detached canonical ramp data suitable for authoring snapshots.
func export_ramp_placements() -> Array[RampPlacementDataScript]:
	var out: Array[RampPlacementDataScript] = []
	for source in _ramps:
		out.append(_clone_ramp(source))
	return out


## Atomically replaces mutable runtime Grid/Ramp state without changing the
## loaded LevelResource identity. Used by runtime preview, undo and redo.
func replace_runtime_content(grid_cells: Array, ramp_placements: Array) -> bool:
	if _level == null or _grid == null:
		return false
	var candidate := _level.duplicate(true) as LevelResource
	if candidate == null:
		return false
	var candidate_cells: Array[GridCellDataScript] = []
	for raw_cell in grid_cells:
		if not raw_cell is GridCellDataScript:
			return false
		candidate_cells.append(_clone_grid_cell(raw_cell))
	var candidate_ramps: Array[RampPlacementDataScript] = []
	for raw_ramp in ramp_placements:
		if not raw_ramp is RampPlacementDataScript:
			return false
		candidate_ramps.append(_clone_ramp(raw_ramp))
	candidate.grid_cells.assign(candidate_cells)
	candidate.ramp_placements.assign(candidate_ramps)
	candidate.terrain_content_version = CANONICAL_CONTENT_VERSION
	candidate.tiles = []
	if not candidate.validate_runtime().is_empty():
		return false
	var next_cells: Dictionary = {}
	for source_cell in candidate_cells:
		if not _grid.is_in_bounds(source_cell.cell) or next_cells.has(source_cell.cell):
			return false
		next_cells[source_cell.cell] = _clone_grid_cell(source_cell)
	for cell in _grid.enumerate_cells():
		if not next_cells.has(cell):
			return false
	var next_ramps: Array[RampPlacementDataScript] = []
	var next_bindings: Dictionary = {}
	for source_ramp in candidate_ramps:
		var ramp := _clone_ramp(source_ramp)
		var footprint := ramp.get_footprint_cells(_grid.get_shape())
		if footprint.size() != ramp.run_length:
			return false
		for footprint_index in range(footprint.size()):
			var ramp_cell: Vector3i = footprint[footprint_index]
			if not next_cells.has(ramp_cell) or next_bindings.has(ramp_cell):
				return false
			next_bindings[ramp_cell] = {"ramp": ramp, "index": footprint_index}
		next_ramps.append(ramp)
	_grid_cells = next_cells
	_ramps = next_ramps
	_ramp_bindings = next_bindings
	_uses_legacy_snapshot = false
	terrain_loaded.emit(_level)
	return true


func get_default_terrain() -> TerrainDefinitionScript:
	return _default_terrain


func get_layer_height() -> float:
	return _layer_height


func get_ramps() -> Array[RampPlacementDataScript]:
	return _ramps.duplicate()


func get_ramp_for_cell(cell: Vector3i) -> RampPlacementDataScript:
	var binding: Dictionary = _ramp_bindings.get(cell, {})
	return binding.get("ramp") as RampPlacementDataScript


func get_ramp_footprint_index(cell: Vector3i) -> int:
	var binding: Dictionary = _ramp_bindings.get(cell, {})
	return int(binding.get("index", -1))


func is_path_cell(cell: Vector3i) -> bool:
	return _path_cells.has(cell)


func allows_tile_building(cell: Vector3i) -> bool:
	var grid_cell := get_grid_cell(cell)
	return grid_cell != null and grid_cell.allows_tile_building


func allows_edge_building(cell: Vector3i, edge_index: int = -1) -> bool:
	var grid_cell := get_grid_cell(cell)
	if grid_cell == null:
		return false
	if edge_index < 0:
		return grid_cell.allows_edge_building
	if not grid_cell.allows_edge(edge_index):
		return false
	if _grid == null or edge_index >= _grid.edge_count():
		return false
	var neighbor := _grid.neighbor_across_edge(cell, edge_index)
	var owner: Variant = _base_footprint_owners.get(cell)
	return owner == null or _base_footprint_owners.get(neighbor) != owner


func get_terrain(cell: Vector3i) -> TerrainDefinitionScript:
	var grid_cell := get_grid_cell(cell)
	var base_terrain: TerrainDefinitionScript = (
		grid_cell.get_effective_terrain(_default_terrain)
		if grid_cell != null
		else _default_terrain
	)
	var ramp := get_ramp_for_cell(cell)
	return ramp.get_effective_terrain(base_terrain) if ramp != null else base_terrain


func get_terrain_color(cell: Vector3i) -> Color:
	if _level != null and is_path_cell(cell):
		return _level.path_terrain_color
	var grid_cell := get_grid_cell(cell)
	if _uses_legacy_snapshot and _level != null and grid_cell != null:
		return _level.get_height_color(grid_cell.layer_count - 1)
	var terrain := get_terrain(cell)
	return terrain.fallback_color if terrain != null else Color.WHITE


## Returns the cell-center surface Y. Existing building/path modules consume
## this through TileManager's compatibility resolver.
func get_world_height(cell: Vector3i) -> float:
	var grid_cell := get_grid_cell(cell)
	if grid_cell == null:
		return 0.0
	var ramp := get_ramp_for_cell(cell)
	if ramp == null:
		return grid_cell.get_surface_height(_layer_height)
	var index := get_ramp_footprint_index(cell)
	var ratio := (float(index) + 0.5) / float(ramp.run_length)
	return float(ramp.base_layer - 1) * _layer_height + ratio * _layer_height


## Samples the actual planar slope at an arbitrary XZ point in the cell.
func sample_surface_height(cell: Vector3i, world_position: Vector3) -> float:
	var ramp := get_ramp_for_cell(cell)
	if ramp == null:
		return get_world_height(cell)
	var axis := get_ramp_axis(ramp)
	var spacing := get_ramp_cell_spacing(ramp)
	if axis.is_zero_approx() or spacing <= 0.0:
		return get_world_height(cell)
	var anchor_center := _grid.cell_to_world(ramp.anchor_cell)
	var offset := Vector3(world_position.x - anchor_center.x, 0.0, world_position.z - anchor_center.z)
	var distance_from_low_edge := offset.dot(axis) + spacing * 0.5
	var ratio := clampf(distance_from_low_edge / (spacing * float(ramp.run_length)), 0.0, 1.0)
	return float(ramp.base_layer - 1) * _layer_height + ratio * _layer_height


func get_surface_normal(cell: Vector3i) -> Vector3:
	var ramp := get_ramp_for_cell(cell)
	if ramp == null:
		return Vector3.UP
	var axis := get_ramp_axis(ramp)
	var run_distance := get_ramp_cell_spacing(ramp) * float(ramp.run_length)
	if axis.is_zero_approx() or run_distance <= 0.0:
		return Vector3.UP
	var grade := _layer_height / run_distance
	return Vector3(-axis.x * grade, 1.0, -axis.z * grade).normalized()


func get_ramp_axis(ramp: RampPlacementDataScript) -> Vector3:
	if ramp == null or _grid == null:
		return Vector3.ZERO
	var next_cell := _grid.neighbor_across_edge(ramp.anchor_cell, ramp.facing_index)
	var direction := _grid.cell_to_world(next_cell) - _grid.cell_to_world(ramp.anchor_cell)
	direction.y = 0.0
	return direction.normalized()


func get_ramp_cell_spacing(ramp: RampPlacementDataScript) -> float:
	if ramp == null or _grid == null:
		return 0.0
	var next_cell := _grid.neighbor_across_edge(ramp.anchor_cell, ramp.facing_index)
	var delta := _grid.cell_to_world(next_cell) - _grid.cell_to_world(ramp.anchor_cell)
	delta.y = 0.0
	return delta.length()


## Exact sloped-surface picking entry injected into GridManager.
func raycast_surface(origin: Vector3, direction: Vector3) -> Dictionary:
	if _grid == null or direction.is_zero_approx():
		return {"hit": false, "pos": Vector3.ZERO, "cell": Vector3i.ZERO}
	var nearest_distance := INF
	var nearest_cell := Vector3i.ZERO
	var nearest_position := Vector3.ZERO
	for cell in _grid.enumerate_cells():
		var normal := get_surface_normal(cell)
		var center := _grid.cell_to_world(cell)
		center.y = get_world_height(cell)
		var denominator := normal.dot(direction)
		if absf(denominator) < 1e-6:
			continue
		var distance := normal.dot(center - origin) / denominator
		if distance < 0.0 or distance >= nearest_distance:
			continue
		var position := origin + direction * distance
		if not _is_point_inside_cell(position, cell):
			continue
		nearest_distance = distance
		nearest_cell = cell
		nearest_position = position
	if not is_finite(nearest_distance):
		return {"hit": false, "pos": Vector3.ZERO, "cell": Vector3i.ZERO}
	return {"hit": true, "pos": nearest_position, "cell": nearest_cell}


func _clone_grid_cell(source: GridCellDataScript) -> GridCellDataScript:
	var runtime_cell := GridCellDataScript.new()
	runtime_cell.configure(
		source.cell,
		source.terrain,
		source.layer_count,
		source.allows_tile_building,
		source.allows_edge_building,
		source.edge_building_mask
	)
	return runtime_cell


func _clone_ramp(source: RampPlacementDataScript) -> RampPlacementDataScript:
	var runtime_ramp := RampPlacementDataScript.new()
	runtime_ramp.ramp_id = source.ramp_id
	runtime_ramp.anchor_cell = source.anchor_cell
	runtime_ramp.facing_index = source.facing_index
	runtime_ramp.run_length = source.run_length
	runtime_ramp.base_layer = source.base_layer
	runtime_ramp.terrain_override = source.terrain_override
	return runtime_ramp


func _is_point_inside_cell(world_position: Vector3, cell: Vector3i) -> bool:
	var polygon := PackedVector2Array()
	for corner in _grid.get_corners(cell):
		polygon.append(Vector2(corner.x, corner.z))
	return Geometry2D.is_point_in_polygon(Vector2(world_position.x, world_position.z), polygon)
