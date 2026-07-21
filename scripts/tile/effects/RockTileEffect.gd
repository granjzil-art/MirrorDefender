@tool
## Durable terrain obstruction. Enemies reroute first and attack only when no
## authored detour is available.
class_name RockTileEffect
extends TileEffect

@export_group("Durability")
@export_range(1.0, 1000000.0, 1.0, "or_greater") var max_durability: float = 500.0

func _init() -> void:
	enemy_traversal = EnemyTraversal.BLOCKED

func get_copy_kind() -> StringName:
	return &"rock"

func get_copy_display_name() -> String:
	return "大石头"

func get_copy_color() -> Color:
	return Color(0.24, 0.27, 0.31)

func creates_runtime_obstacle() -> bool:
	return true

func get_max_durability() -> float:
	return max_durability

func allows_tile_building_after_destroyed() -> bool:
	return true

func allows_edge_building_after_destroyed() -> bool:
	return true

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(max_durability) or max_durability <= 0.0:
		errors.append("大石头最大耐久必须为有限正数")
	return errors
