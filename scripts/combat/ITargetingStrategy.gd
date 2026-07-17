## Interface for swappable building target selection policies.
class_name ITargetingStrategy
extends RefCounted

func select_target(
	_candidates: Array[CombatTarget],
	_origin: Vector3,
	_locked_target: CombatTarget = null
) -> CombatTarget:
	push_error("ITargetingStrategy.select_target() 未实现")
	return null
