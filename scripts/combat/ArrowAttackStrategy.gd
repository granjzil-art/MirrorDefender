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
	var damage: float = building.call("get_instant_damage")
	var applied := target.take_damage(damage)
	building.call("show_attack_line", target.get_target_position(), false)
	building.call("notify_attack", target, applied, false)
	var attacks_per_second: float = building.call("get_attacks_per_second")
	_cooldown = 1.0 / maxf(0.01, attacks_per_second)

func reset(building: Node) -> void:
	_cooldown = 0.0
	building.call("clear_attack_visual")
