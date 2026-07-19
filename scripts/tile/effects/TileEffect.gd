@tool
## Strategy resource for enemy interactions owned by a TileDefinition.
class_name TileEffect
extends Resource

enum EnemyTraversal {
	PASSABLE,
	BLOCKED,
}

@export_group("Navigation")
@export_enum("Passable", "Blocked") var enemy_traversal: int = EnemyTraversal.PASSABLE
## False excludes this tile from a voluntarily selected detour suffix.
@export var safe_for_reroute: bool = true

func blocks_enemy_navigation() -> bool:
	return enemy_traversal == EnemyTraversal.BLOCKED

func can_use_for_reroute() -> bool:
	return not blocks_enemy_navigation() and safe_for_reroute

func apply_enter(_target: Node) -> void:
	pass

func apply_stay(_target: Node, _duration: float) -> void:
	pass

func validate_configuration() -> Array[String]:
	return []
