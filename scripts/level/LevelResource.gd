@tool
## LevelResource -- data-only level definition.
##
## M2 owns grid and tile layout. Later milestones extend this same Resource with
## paths, waves, resources, and caps instead of creating parallel level formats.
class_name LevelResource
extends Resource

@export_group("Grid")
@export_enum("六边形", "正方形") var grid_shape: int = 0
@export_range(0.1, 10.0, 0.05, "or_greater") var grid_cell_size: float = 1.0
## HEX uses x as radius. SQUARE uses (columns, rows).
@export var grid_size: Vector2i = Vector2i(6, 6)

@export_group("Tiles")
@export_range(1, 16, 1) var height_levels: int = 3
@export_range(0.05, 5.0, 0.05, "or_greater") var height_step: float = 0.45
@export var tiles: Array = []

@export_group("Editor Terrain Colors")
@export var height_color_low: Color = Color(0.16, 0.34, 0.24, 1.0)
@export var height_color_middle: Color = Color(0.38, 0.58, 0.25, 1.0)
@export var height_color_high: Color = Color(0.77, 0.68, 0.31, 1.0)

func get_tile(cell: Vector3i) -> Variant:
	for raw_tile in tiles:
		var tile: Resource = raw_tile
		if tile == null:
			continue
		var tile_cell: Vector3i = tile.get("cell")
		if tile_cell == cell:
			return tile
	return null

func store_tile(tile: Resource) -> void:
	if tile == null:
		return
	var tile_cell: Vector3i = tile.get("cell")
	for index in range(tiles.size()):
		var current: Resource = tiles[index]
		if current == null:
			continue
		var current_cell: Vector3i = current.get("cell")
		if current_cell == tile_cell:
			tiles[index] = tile
			emit_changed()
			return
	tiles.append(tile)
	emit_changed()

func clear_tiles() -> void:
	tiles.clear()
	emit_changed()

func clamp_tile_heights() -> void:
	for raw_tile in tiles:
		var tile: Resource = raw_tile
		if tile != null:
			var current_height: int = tile.get("height_level")
			tile.set("height_level", clampi(current_height, 0, maxi(0, height_levels - 1)))
	emit_changed()
