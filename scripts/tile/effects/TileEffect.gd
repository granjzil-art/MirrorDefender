@tool
## Strategy resource for enemy interactions owned by a TileDefinition.
class_name TileEffect
extends Resource

enum EnemyTraversal {
	PASSABLE,
	BLOCKED,
}

@export_group("Applicability")
@export var affects_airborne: bool = true

@export_group("Navigation")
@export_enum("Passable", "Blocked") var enemy_traversal: int = EnemyTraversal.PASSABLE

func blocks_enemy_navigation(target: Node = null) -> bool:
	return enemy_traversal == EnemyTraversal.BLOCKED and affects_target(target)

func can_use_for_reroute(target: Node = null) -> bool:
	return not blocks_enemy_navigation(target)

func affects_target(target: Node) -> bool:
	if affects_airborne or target == null or not is_instance_valid(target):
		return true
	if not target.has_method("is_airborne_unit"):
		return true
	return not bool(target.call("is_airborne_unit"))

func apply_enter(_target: Node) -> void:
	pass

func apply_stay(_target: Node, _duration: float) -> void:
	pass

func get_copy_kind() -> StringName:
	return &""

func get_copy_display_name() -> String:
	return "地块效果"

func get_copy_color() -> Color:
	return Color(0.35, 0.75, 1.0)

func validate_configuration() -> Array[String]:
	return []
