## Fixed-direction piercing beam with frame-rate-independent continuous damage.
class_name LaserAttackStrategy
extends IAttackStrategy

func tick(building: Node, delta: float) -> void:
	var combat_manager: CombatManager = building.call("get_combat_manager")
	if combat_manager == null:
		building.call("clear_attack_visual")
		return
	var start: Vector3 = building.call("get_attack_origin")
	var end: Vector3 = building.call("get_laser_end")
	building.call("show_attack_line", end, true)
	var damage_per_second: float = building.call("get_laser_damage_per_second")
	var damage_this_tick := damage_per_second * delta
	building.call("notify_copy_attack", &"laser", start, end, damage_this_tick)
	for target in combat_manager.get_targets_on_segment(start, end):
		if not bool(building.call("affects_target", target)):
			continue
		var applied := target.take_damage(damage_this_tick)
		building.call("notify_attack", target, applied, true)

func reset(building: Node) -> void:
	building.call("clear_attack_visual")
