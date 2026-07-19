## Data-only definition for one constructible M3 building type.
class_name BuildingDefinition
extends Resource

const MAX_LEVEL := 3

enum Kind {
	ARROW_TOWER,
	LASER_TOWER,
	BARRIER,
}

@export_group("Identity")
@export var kind: Kind = Kind.ARROW_TOWER
@export var display_name: String = "箭塔"

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
