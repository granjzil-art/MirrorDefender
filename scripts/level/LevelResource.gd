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
@export var height_color_low: Color = Color(0.18, 0.60, 0.31, 1.0)
@export var height_color_middle: Color = Color(0.95, 0.76, 0.18, 1.0)
@export var height_color_high: Color = Color(0.84, 0.24, 0.20, 1.0)

@export_group("M3 Economy")
@export_range(0, 100000, 1, "or_greater") var initial_resource: int = 200
@export_range(0, 1000, 1, "or_greater") var building_cap: int = 20
@export_range(0, 1000, 1, "or_greater") var mirror_cap: int = 6

@export_group("M3 Income Sources")
@export var kill_drop_enabled: bool = true
@export var tile_income_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var tile_income_rate: float = 1.0
@export var producer_income_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var producer_income_rate: float = 2.0
@export var time_growth_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var time_growth_rate: float = 0.5
@export var destroy_tile_income_enabled: bool = true
@export_range(0, 100000, 1, "or_greater") var destroy_tile_income_amount: int = 20

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

func get_height_color(height_level: int) -> Color:
	var maximum_level := maxi(1, height_levels - 1)
	var normalized_height := clampf(float(height_level) / float(maximum_level), 0.0, 1.0)
	if normalized_height <= 0.5:
		return height_color_low.lerp(height_color_middle, normalized_height * 2.0)
	return height_color_middle.lerp(height_color_high, (normalized_height - 0.5) * 2.0)
