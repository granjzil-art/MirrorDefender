## TileManager -- Tile module's only runtime state/query entry point.
##
## Other gameplay modules query this manager rather than retaining TileCellData
## resources. TileRenderer and later Building/Path systems react through signals.
class_name TileManager
extends Node3D

const BUILDABLE_TILE_TYPE := 0

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Level")
@export var level: Resource

signal level_loaded(level_resource: LevelResource)
signal tile_changed(cell: Vector3i, tile: TileCellData)
signal obstacle_destroyed(cell: Vector3i)
signal occupant_changed(cell: Vector3i, occupant: Node)

var _grid: GridManager
var _tiles: Dictionary = {}
var _navigation_overlay_resolver: Callable

func _ready() -> void:
	var level_data := _get_level()
	if _grid != null and level_data != null:
		load_level(level_data)

## Main injects the Grid module's public entry point during scene composition.
func set_grid(value: GridManager) -> void:
	_grid = value
	var level_data := _get_level()
	if is_node_ready() and level_data != null:
		load_level(level_data)

func set_navigation_overlay_resolver(value: Callable) -> void:
	_navigation_overlay_resolver = value

func load_level(level_resource: LevelResource) -> bool:
	if not feature_enabled or level_resource == null or _grid == null:
		return false
	if not level_resource.validate_runtime().is_empty():
		return false
	if (
		int(_grid.grid_shape) != level_resource.grid_shape
		or not is_equal_approx(_grid.cell_size, level_resource.grid_cell_size)
		or _grid.grid_size != level_resource.grid_size
	):
		return false
	var next_tiles: Dictionary = {}
	for serialized_resource in level_resource.tiles:
		if not serialized_resource is TileCellData:
			return false
		var serialized_tile: TileCellData = serialized_resource
		if not _grid.is_in_bounds(serialized_tile.cell):
			continue
		var runtime_tile := _make_runtime_tile(serialized_tile, level_resource.height_levels)
		next_tiles[runtime_tile.cell] = runtime_tile
	for cell in _grid.enumerate_cells():
		if not next_tiles.has(cell):
			next_tiles[cell] = _make_default_tile(cell)
	level = level_resource
	_tiles = next_tiles
	level_loaded.emit(level_resource)
	return true

func get_tile(cell: Vector3i) -> TileCellData:
	if not _tiles.has(cell):
		return null
	var tile: TileCellData = _tiles[cell]
	return tile

func get_tiles() -> Array[TileCellData]:
	var out: Array[TileCellData] = []
	if _grid == null:
		return out
	for cell in _grid.enumerate_cells():
		var tile := get_tile(cell)
		if tile != null:
			out.append(tile)
	return out

func get_level_resource() -> LevelResource:
	return _get_level()

func get_world_height(cell: Vector3i) -> float:
	var tile := get_tile(cell)
	var level_data := _get_level()
	if tile == null or level_data == null:
		return 0.0
	return float(tile.height_level) * level_data.height_step

func get_height_color(cell: Vector3i) -> Color:
	var tile := get_tile(cell)
	var level_data := _get_level()
	if tile == null or level_data == null:
		return Color.WHITE
	return level_data.get_height_color(tile.height_level)

func can_place(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.can_place()

func can_place_path_occupant(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.can_place_path_occupant()

func allows_edge_building(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.allows_edge_building()

func blocks_enemy_navigation(cell: Vector3i, target: Node = null) -> bool:
	var tile := get_tile(cell)
	if tile != null and tile.blocks_enemy_navigation(target):
		return true
	return bool(_navigation_overlay_resolver.call(cell, target)) if _navigation_overlay_resolver.is_valid() else false

func can_use_for_reroute(cell: Vector3i, target: Node = null) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.can_use_for_reroute(target) and not blocks_enemy_navigation(cell, target)

func place_occupant(cell: Vector3i, occupant: Node) -> bool:
	var tile := get_tile(cell)
	if tile == null or not tile.place(occupant):
		return false
	occupant_changed.emit(cell, occupant)
	return true

func place_path_occupant(cell: Vector3i, occupant: Node) -> bool:
	var tile := get_tile(cell)
	if tile == null or not tile.place_path_occupant(occupant):
		return false
	occupant_changed.emit(cell, occupant)
	return true

func clear_occupant(cell: Vector3i, expected_occupant: Node = null) -> bool:
	var tile := get_tile(cell)
	if tile == null or not tile.clear_occupant(expected_occupant):
		return false
	occupant_changed.emit(cell, null)
	return true

func get_occupant(cell: Vector3i) -> Node:
	var tile := get_tile(cell)
	return tile.occupant if tile != null else null

func is_blocked(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	return tile != null and tile.is_blocked()

func apply_preset(cell: Vector3i, preset: TilePreset) -> bool:
	var level_data := _get_level()
	if not feature_enabled or _grid == null or level_data == null or preset == null:
		return false
	if not _grid.is_in_bounds(cell):
		return false
	var tile: TileCellData = preset.make_tile(cell, level_data.height_levels)
	_set_tile(tile)
	return true

func update_tile_type(cell: Vector3i, tile_type: int) -> bool:
	var tile := get_tile(cell)
	if tile == null:
		return false
	tile.set_tile_type(tile_type)
	_notify_tile_changed(tile)
	return true

func update_tile_height(cell: Vector3i, height_level: int) -> bool:
	var tile := get_tile(cell)
	var level_data := _get_level()
	if tile == null or level_data == null:
		return false
	tile.set_height_level(height_level, level_data.height_levels)
	_notify_tile_changed(tile)
	return true

func destroy_obstacle_at(cell: Vector3i) -> bool:
	var tile := get_tile(cell)
	if tile == null or not tile.destroy_obstacle():
		return false
	_notify_tile_changed(tile)
	obstacle_destroyed.emit(cell)
	return true

func _set_tile(tile: TileCellData) -> void:
	_tiles[tile.cell] = tile
	_notify_tile_changed(tile)

func _notify_tile_changed(tile: TileCellData) -> void:
	tile_changed.emit(tile.cell, tile)

func _get_level() -> LevelResource:
	var level_data: LevelResource = level
	return level_data

func _make_default_tile(cell: Vector3i) -> TileCellData:
	var tile := TileCellData.new()
	tile.configure(cell, BUILDABLE_TILE_TYPE, 0)
	return tile

func _make_runtime_tile(source: TileCellData, height_levels: int) -> TileCellData:
	var tile := TileCellData.new()
	tile.configure(
		source.cell,
		source.tile_type,
		clampi(source.height_level, 0, maxi(0, height_levels - 1)),
		source.definition
	)
	tile.obstacle_destroyed = source.obstacle_destroyed
	return tile
