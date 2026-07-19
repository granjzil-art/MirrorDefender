@tool
## TilePreset -- palette asset used by the level editor.
class_name TilePreset
extends Resource

const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")

@export var display_name: String = "可建造"
@export_enum("可建造", "可破坏障碍", "不可建造路面") var tile_type: int = 0
@export var definition: TileDefinition
@export_range(0, 15, 1) var height_level: int = 0

func make_tile(cell: Vector3i, height_levels: int) -> Variant:
	var tile: Resource = TileCellDataScript.new()
	tile.call(
		"configure",
		cell,
		tile_type,
		clampi(height_level, 0, maxi(0, height_levels - 1)),
		definition
	)
	return tile
