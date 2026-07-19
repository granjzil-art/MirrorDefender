## Cooldown strategy shared by melee and projectile-based enemy attacks.
class_name EnemyAttackStrategy
extends IAttackStrategy

var _cooldown: float = 0.0

func tick(attacker: Node, delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - maxf(0.0, delta))
	if _cooldown > 0.0:
		return
	var target: Node = attacker.call("get_attack_target")
	if target == null or not is_instance_valid(target):
		return
	var attack_started := bool(attacker.call("perform_attack", target))
	if not attack_started:
		return
	var attacks_per_second: float = attacker.call("get_attacks_per_second")
	_cooldown = 1.0 / maxf(0.01, attacks_per_second)

func reset(_attacker: Node) -> void:
	_cooldown = 0.0
