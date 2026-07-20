@tool
## Permanent terrain obstruction. Enemies reroute instead of attacking it.
class_name RockTileEffect
extends TileEffect

func _init() -> void:
	enemy_traversal = EnemyTraversal.BLOCKED
