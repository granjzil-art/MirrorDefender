## TileCellData -- serializable state for one map cell.
##
## This Resource owns gameplay state only. TileManager owns lookup and events,
## while TileRenderer owns all 3D presentation.
class_name TileCellData
extends Resource

enum TileType {
	BUILDABLE,
	DESTRUCTIBLE,
	BLOCKED,
}

@export_group("Identity")
@export var cell: Vector3i = Vector3i.ZERO

@export_group("Terrain")
@export var tile_type: TileType = TileType.BUILDABLE
@export_range(0, 15, 1) var height_level: int = 0
@export var obstacle_destroyed: bool = false

## Runtime-only occupancy. Buildings will set this through TileManager in M3.
var occupant: Node = null

func configure(p_cell: Vector3i, p_tile_type: int, p_height_level: int) -> void:
	cell = p_cell
	tile_type = p_tile_type
	height_level = maxi(0, p_height_level)
	obstacle_destroyed = false
	emit_changed()

func is_buildable() -> bool:
	return tile_type == TileType.BUILDABLE or (
		tile_type == TileType.DESTRUCTIBLE and obstacle_destroyed
	)

func is_destructible() -> bool:
	return tile_type == TileType.DESTRUCTIBLE and not obstacle_destroyed

func is_blocked() -> bool:
	return tile_type == TileType.BLOCKED

func can_place() -> bool:
	return is_buildable() and occupant == null

func place(new_occupant: Node) -> bool:
	if new_occupant == null or not can_place():
		return false
	occupant = new_occupant
	return true

func clear_occupant() -> void:
	occupant = null

## Converts the stone obstacle to a buildable cell while preserving terrain height.
func destroy_obstacle() -> bool:
	if not is_destructible():
		return false
	obstacle_destroyed = true
	emit_changed()
	return true

func set_height_level(value: int, height_levels: int) -> void:
	height_level = clampi(value, 0, maxi(0, height_levels - 1))
	emit_changed()

func set_tile_type(value: int) -> void:
	tile_type = value
	obstacle_destroyed = false
	emit_changed()

func get_display_name() -> String:
	match tile_type:
		TileType.BUILDABLE:
			return "可建造"
		TileType.DESTRUCTIBLE:
			return "可破坏障碍" if not obstacle_destroyed else "可建造（已清障）"
		TileType.BLOCKED:
			return "不可建造路面"
	return "未知地块"
