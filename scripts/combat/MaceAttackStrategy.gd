## Fixed multi-direction projectile attack used by the Mace tower.
class_name MaceAttackStrategy
extends IAttackStrategy

var _cooldown: float = 0.0


func tick(building: Node, delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - maxf(0.0, delta))
	if _cooldown > 0.0:
		return
	var fires_without_target: bool = bool(building.call("fires_along_facing_without_target"))
	if not fires_without_target and not bool(building.call("has_target_in_range")):
		return
	var damage: float = float(building.call("get_instant_damage"))
	building.call("launch_multi_direction_projectiles", damage)
	_set_cooldown(building)


func _set_cooldown(building: Node) -> void:
	var attacks_per_second: float = float(building.call("get_attacks_per_second"))
	_cooldown = 1.0 / maxf(0.01, attacks_per_second)


func reset(_building: Node) -> void:
	_cooldown = 0.0
