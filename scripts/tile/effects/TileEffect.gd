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

## Timed effects are dispatched by TileEffectSystem instead of firing directly
## from per-unit enter/stay callbacks.
func uses_timed_runtime() -> bool:
	return false

func get_runtime_state_key(source_cell: Vector3i) -> String:
	return "%s:%d:%d:%d" % [str(get_copy_kind()), source_cell.x, source_cell.y, source_cell.z]

func get_copy_kind() -> StringName:
	return &""

func get_copy_display_name() -> String:
	return "地块效果"

func get_copy_color() -> Color:
	return Color(0.35, 0.75, 1.0)

## Runtime obstacle hooks are opt-in so passive effects remain stateless.
func creates_runtime_obstacle() -> bool:
	return false

func get_max_durability() -> float:
	return 0.0

func allows_tile_building_after_destroyed() -> bool:
	return false

func allows_edge_building_after_destroyed() -> bool:
	return false

func validate_configuration() -> Array[String]:
	return []
