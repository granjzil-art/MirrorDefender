@tool
## Permanent terrain obstruction. Enemies reroute instead of attacking it.
class_name RockTileEffect
extends TileEffect

func _init() -> void:
	enemy_traversal = EnemyTraversal.BLOCKED

func get_copy_kind() -> StringName:
	return &"rock"

func get_copy_display_name() -> String:
	return "大石头"

func get_copy_color() -> Color:
	return Color(0.24, 0.27, 0.31)
