@tool
## TileCellData -- serializable state for one map cell.
##
## Serialized instances are level configuration snapshots. TileManager clones
## them before play and owns runtime mutation, lookup, occupancy, and events;
## TileRenderer owns all 3D presentation.
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
## New cells use a reusable definition. Null keeps legacy enum-only levels valid.
@export var definition: TileDefinition
@export_range(0, 15, 1) var height_level: int = 0
@export var obstacle_destroyed: bool = false

## Runtime-only occupancy. Buildings will set this through TileManager in M3.
var occupant: Node = null

func configure(
	p_cell: Vector3i,
	p_tile_type: int,
	p_height_level: int,
	p_definition: TileDefinition = null
) -> void:
	cell = p_cell
	tile_type = p_tile_type
	definition = p_definition
	height_level = maxi(0, p_height_level)
	obstacle_destroyed = false
	emit_changed()

func is_buildable() -> bool:
	if definition != null:
		return definition.is_buildable(obstacle_destroyed)
	return tile_type == TileType.BUILDABLE or (
		tile_type == TileType.DESTRUCTIBLE and obstacle_destroyed
	)

func is_destructible() -> bool:
	if definition != null:
		return definition.is_destructible(obstacle_destroyed)
	return tile_type == TileType.DESTRUCTIBLE and not obstacle_destroyed

func is_blocked() -> bool:
	if definition != null:
		return definition.is_blocked_surface()
	return tile_type == TileType.BLOCKED

func allows_tile_building() -> bool:
	if definition != null:
		return definition.allows_tile_building
	return tile_type != TileType.DESTRUCTIBLE or obstacle_destroyed

func allows_edge_building() -> bool:
	return definition == null or definition.allows_edge_building

func blocks_enemy_navigation() -> bool:
	return definition != null and definition.blocks_enemy_navigation()

func can_use_for_reroute() -> bool:
	return definition == null or definition.can_use_for_reroute()

func get_effect() -> TileEffect:
	return definition.effect if definition != null else null

func get_visual_kind() -> int:
	return int(definition.visual_kind) if definition != null else TileDefinition.VisualKind.NONE

func get_visual_tag() -> StringName:
	return definition.get_visual_tag() if definition != null else &"none"

func get_visual_color() -> Color:
	return definition.visual_color if definition != null else Color.WHITE

func get_terrain_color(fallback: Color) -> Color:
	if definition != null and definition.override_terrain_color:
		return definition.terrain_color
	return fallback

func can_place() -> bool:
	return is_buildable() and allows_tile_building() and occupant == null

## Path blockers may occupy a road cell, but never an uncleared obstacle.
func can_place_path_occupant() -> bool:
	return occupant == null and allows_tile_building() and not is_destructible()

func place(new_occupant: Node) -> bool:
	if new_occupant == null or not can_place():
		return false
	occupant = new_occupant
	return true

func place_path_occupant(new_occupant: Node) -> bool:
	if new_occupant == null or not can_place_path_occupant():
		return false
	occupant = new_occupant
	return true

func clear_occupant(expected_occupant: Node = null) -> bool:
	if expected_occupant != null and occupant != expected_occupant:
		return false
	occupant = null
	return true

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
	definition = null
	obstacle_destroyed = false
	emit_changed()

func set_definition(value: TileDefinition, fallback_tile_type: int = TileType.BUILDABLE) -> void:
	definition = value
	tile_type = fallback_tile_type
	obstacle_destroyed = false
	emit_changed()

func get_display_name() -> String:
	if definition != null:
		return definition.display_name
	match tile_type:
		TileType.BUILDABLE:
			return "可建造"
		TileType.DESTRUCTIBLE:
			return "可破坏障碍" if not obstacle_destroyed else "可建造（已清障）"
		TileType.BLOCKED:
			return "不可建造路面"
	return "未知地块"

func get_configuration_errors() -> Array[String]:
	return definition.validate_configuration() if definition != null else []
