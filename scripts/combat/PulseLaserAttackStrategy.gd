## Cooldown-based fixed-facing pulse laser that fires even without a target.
class_name PulseLaserAttackStrategy
extends IAttackStrategy

var _cooldown: float = 0.0


func tick(building: Node, delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - maxf(0.0, delta))
	if _cooldown > 0.0:
		return
	building.call("launch_pulse_laser")
	var attacks_per_second: float = building.call("get_attacks_per_second")
	_cooldown = 1.0 / maxf(0.01, attacks_per_second)


func reset(_building: Node) -> void:
	_cooldown = 0.0
