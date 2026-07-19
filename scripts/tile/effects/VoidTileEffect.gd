@tool
## Instantly defeats an enemy that enters a void tile.
class_name VoidTileEffect
extends TileEffect

@export_group("Defeat")
@export_range(0.0, 100.0, 0.05, "or_greater") var reward_multiplier: float = 1.0

func _init() -> void:
	enemy_traversal = EnemyTraversal.PASSABLE
	safe_for_reroute = false

func apply_enter(target: Node) -> void:
	if target != null and is_instance_valid(target) and target.has_method("defeat"):
		target.call("defeat", reward_multiplier)

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if not is_finite(reward_multiplier) or reward_multiplier < 0.0:
		errors.append("空洞击杀资源倍率必须为有限非负数")
	return errors
