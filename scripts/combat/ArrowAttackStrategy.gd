## Cooldown-based single-target instant attack.
class_name ArrowAttackStrategy
extends IAttackStrategy

var _cooldown: float = 0.0

func tick(building: Node, delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		return
	var target: CombatTarget = building.call("acquire_target")
	if target == null:
		return
	var target_in_range: bool = building.call("is_target_in_attack_range", target)
	if not target_in_range:
		return
	var damage: float = building.call("get_instant_damage")
	building.call("launch_projectile", target, damage)
	var attacks_per_second: float = building.call("get_attacks_per_second")
	_cooldown = 1.0 / maxf(0.01, attacks_per_second)

func reset(building: Node) -> void:
	_cooldown = 0.0
	building.call("clear_attack_visual")
