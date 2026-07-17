## Implements all M3 target priorities behind one strategy interface.
class_name PriorityTargetingStrategy
extends ITargetingStrategy

enum Priority {
	NEAREST,
	FARTHEST,
	HIGHEST_HP,
	LOWEST_HP,
	FASTEST,
	FIRST_IN,
	LOCKED,
}

var priority: Priority = Priority.NEAREST

func _init(value: int = Priority.NEAREST) -> void:
	priority = value

func select_target(
	candidates: Array[CombatTarget],
	origin: Vector3,
	locked_target: CombatTarget = null
) -> CombatTarget:
	if candidates.is_empty():
		return null
	if priority == Priority.LOCKED and _is_valid_candidate(locked_target, candidates):
		return locked_target
	var selected: CombatTarget = null
	for candidate in candidates:
		if candidate == null or not candidate.is_alive():
			continue
		if selected == null or _is_better(candidate, selected, origin):
			selected = candidate
	return selected

func _is_better(candidate: CombatTarget, selected: CombatTarget, origin: Vector3) -> bool:
	match priority:
		Priority.FARTHEST:
			return candidate.global_position.distance_squared_to(origin) > selected.global_position.distance_squared_to(origin)
		Priority.HIGHEST_HP:
			return candidate.current_hp > selected.current_hp
		Priority.LOWEST_HP:
			return candidate.current_hp < selected.current_hp
		Priority.FASTEST:
			return candidate.move_speed > selected.move_speed
		Priority.FIRST_IN:
			return candidate.entry_order < selected.entry_order
		_:
			return candidate.global_position.distance_squared_to(origin) < selected.global_position.distance_squared_to(origin)

func _is_valid_candidate(target: CombatTarget, candidates: Array[CombatTarget]) -> bool:
	return target != null and is_instance_valid(target) and target.is_alive() and candidates.has(target)
