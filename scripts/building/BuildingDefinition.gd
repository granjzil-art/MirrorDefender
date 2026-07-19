## Data-only definition for one constructible M3 building type.
class_name BuildingDefinition
extends Resource

const MAX_LEVEL := 3

enum Kind {
	ARROW_TOWER,
	LASER_TOWER,
	BARRIER,
	EDGE_BARRIER,
}

enum PlacementSurface {
	BUILDABLE_TILE,
	PATH_TILE,
	PATH_EDGE,
}

@export_group("Identity")
@export var kind: Kind = Kind.ARROW_TOWER
@export var display_name: String = "箭塔"

@export_group("Placement")
@export var placement_surface: PlacementSurface = PlacementSurface.BUILDABLE_TILE
## Edge buildings block both traversal directions by default. Disable this only
## for future one-way variants; tile buildings ignore the setting.
@export var blocks_both_directions: bool = true

@export_group("Levels")
@export var levels: Array[BuildingLevelStats] = []

func get_level_stats(value: int) -> BuildingLevelStats:
	if levels.is_empty():
		return null
	var index := clampi(value, 1, get_max_level()) - 1
	return levels[index]

func get_max_level() -> int:
	return mini(MAX_LEVEL, levels.size())

func is_configured() -> bool:
	return get_max_level() > 0 and get_level_stats(1) != null

func is_defensive_structure() -> bool:
	return kind == Kind.BARRIER or kind == Kind.EDGE_BARRIER

func get_resolved_placement_surface() -> PlacementSurface:
	if kind == Kind.EDGE_BARRIER:
		return PlacementSurface.PATH_EDGE
	if kind == Kind.BARRIER:
		return PlacementSurface.PATH_TILE
	return placement_surface

func is_edge_building() -> bool:
	return get_resolved_placement_surface() == PlacementSurface.PATH_EDGE

func is_path_tile_building() -> bool:
	return get_resolved_placement_surface() == PlacementSurface.PATH_TILE
