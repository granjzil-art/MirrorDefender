## Stateful durability, out-of-combat regeneration, and reflection for barriers.
class_name BarrierDurability
extends RefCounted

signal durability_changed(current: float, maximum: float)
signal depleted(attacker: Node)

var current: float = 0.0
var maximum: float = 0.0

var _stats: BuildingLevelStats
var _time_since_damage: float = 0.0
var _depleted: bool = false

func configure(stats: BuildingLevelStats, preserve_damage: bool) -> void:
	var previous_maximum := maximum
	var previous_current := current
	_stats = stats
	maximum = maxf(1.0, _stats.max_durability) if _stats != null else 1.0
	if preserve_damage:
		var maximum_increase := maxf(0.0, maximum - previous_maximum)
		current = clampf(previous_current + maximum_increase, 0.0, maximum)
	else:
		current = maximum
	_depleted = false
	durability_changed.emit(current, maximum)

func tick(delta: float) -> void:
	if not is_alive() or current >= maximum or _stats == null:
		return
	var safe_delta := maxf(0.0, delta)
	var previous_time := _time_since_damage
	_time_since_damage += safe_delta
	if _time_since_damage < _stats.regeneration_delay or _stats.regeneration_per_second <= 0.0:
		return
	var regeneration_delta := safe_delta
	if previous_time < _stats.regeneration_delay:
		regeneration_delta = _time_since_damage - _stats.regeneration_delay
	restore(_stats.regeneration_per_second * maxf(0.0, regeneration_delta))

func take_damage(amount: float, attacker: Node = null, can_reflect_to_attacker: bool = true) -> float:
	if not is_alive() or amount <= 0.0:
		return 0.0
	var applied_damage := minf(amount, current)
	current -= applied_damage
	_time_since_damage = 0.0
	durability_changed.emit(current, maximum)
	if can_reflect_to_attacker:
		_apply_reflection(applied_damage, attacker)
	if current <= 0.0:
		_depleted = true
		depleted.emit(attacker)
	return applied_damage

func restore(amount: float) -> float:
	if not is_alive() or amount <= 0.0 or current >= maximum:
		return 0.0
	var restored := minf(amount, maximum - current)
	current += restored
	durability_changed.emit(current, maximum)
	return restored

func is_alive() -> bool:
	return not _depleted and current > 0.0

func get_ratio() -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)

func _apply_reflection(applied_damage: float, attacker: Node) -> void:
	if _stats == null or _stats.damage_reflection_ratio <= 0.0:
		return
	if attacker == null or not is_instance_valid(attacker) or not attacker.has_method("take_damage"):
		return
	var reflected_damage := applied_damage * clampf(_stats.damage_reflection_ratio, 0.0, 1.0)
	if reflected_damage > 0.0:
		attacker.call("take_damage", reflected_damage)
