## Reflected continuous beam with finite enemy penetration and timed cold bursts.
class_name LaserAttackStrategy
extends IAttackStrategy

const ContinuousLaserPathScript := preload("res://scripts/combat/ContinuousLaserPath.gd")
const ReflectionDamageScript := preload("res://scripts/combat/ReflectionDamage.gd")

var _propagation_distance: float = 0.0
var _last_origin: Vector3 = Vector3.ZERO
var _last_direction: Vector3 = Vector3.ZERO
var _has_propagation_basis: bool = false


func tick(building: Node, delta: float) -> void:
	var combat_manager: CombatManager = building.call("get_combat_manager")
	if combat_manager == null:
		_reset_propagation()
		building.call("clear_attack_visual")
		return
	var start: Vector3 = building.call("get_attack_origin")
	var maximum_end: Vector3 = building.call("get_laser_end")
	var direction := maximum_end - start
	if direction.length_squared() <= 0.000001:
		_reset_propagation()
		building.call("clear_attack_visual")
		return
	var normalized_direction := direction.normalized()
	if _propagation_basis_changed(start, normalized_direction):
		_propagation_distance = 0.0
	_last_origin = start
	_last_direction = normalized_direction
	_has_propagation_basis = true
	var resolved_delta := maxf(0.0, delta)
	var maximum_distance: float = building.call("get_attack_range_world")
	var propagation_speed: float = building.call("get_laser_propagation_speed_world")
	_propagation_distance = minf(
		maximum_distance,
		_propagation_distance + propagation_speed * resolved_delta
	)
	var path := trace_laser_path(
		building,
		combat_manager,
		start,
		direction,
		_propagation_distance
	)
	_clamp_propagation_to_hard_stop(path)
	var segments: Array = path.get("segments", [])
	var endpoint: Vector3 = path.get("endpoint", start)
	building.call("show_attack_path", segments, endpoint)
	var damage_per_second: float = building.call("get_laser_damage_per_second")
	apply_continuous_hits(
		building,
		path,
		damage_per_second,
		resolved_delta,
		true
	)
	building.call(
		"notify_copy_attack",
		&"laser",
		start,
		maximum_end,
		damage_per_second * resolved_delta
	)


func reset(building: Node) -> void:
	_reset_propagation()
	building.call("clear_attack_visual")


func debug_get_propagation_distance() -> float:
	return _propagation_distance


static func trace_laser_path(
	building: Node,
	combat_manager: CombatManager,
	start: Vector3,
	direction: Vector3,
	distance_limit: float = -1.0,
	penetration_bonus: int = 0,
	attack_effects: AttackEffectPayload = null
) -> Dictionary:
	var maximum_distance: float = building.call("get_attack_range_world")
	if distance_limit >= 0.0:
		maximum_distance = minf(maximum_distance, distance_limit)
	return ContinuousLaserPathScript.trace(
		combat_manager,
		building,
		start,
		direction,
		maximum_distance,
		int(building.call("get_projectile_penetration_count")) + maxi(0, penetration_bonus),
		combat_manager.get_projectile_reflection_resolver(),
		combat_manager.get_projectile_blocker_resolver(),
		attack_effects
	)


static func get_path_length(path: Dictionary) -> float:
	if path.has("main_length"):
		var main_length := float(path.get("main_length", 0.0))
		return maxf(0.0, main_length) if is_finite(main_length) else 0.0
	var total := 0.0
	for raw_segment in path.get("segments", []):
		if raw_segment is Dictionary:
			total += maxf(0.0, float((raw_segment as Dictionary).get("length", 0.0)))
	return total


static func get_path_damage_multiplier(path: Dictionary) -> float:
	var value := float(path.get("damage_multiplier", 1.0))
	return maxf(0.0, value) if is_finite(value) else 1.0


## Returns the first live enemy in beam-traversal order. The target center is
## intentionally used instead of the ray entry point or the path endpoint.
static func get_first_hit_position(path: Dictionary) -> Dictionary:
	for raw_hit in path.get("hits", []):
		if not raw_hit is Dictionary:
			continue
		var target := (raw_hit as Dictionary).get("target") as CombatTarget
		if target == null or not is_instance_valid(target) or not target.is_alive():
			continue
		return {
			"hit": true,
			"position": target.get_target_position(),
			"target": target,
		}
	return {
		"hit": false,
		"position": path.get("endpoint", Vector3.ZERO),
		"target": null,
	}


func _propagation_basis_changed(start: Vector3, direction: Vector3) -> bool:
	if not _has_propagation_basis:
		return false
	return (
		start.distance_squared_to(_last_origin) > 0.000001
		or direction.dot(_last_direction) < 0.99999
	)


func _clamp_propagation_to_hard_stop(path: Dictionary) -> void:
	var termination: StringName = path.get("termination", &"none")
	if termination in [&"enemy", &"stuff"]:
		_propagation_distance = minf(_propagation_distance, get_path_length(path))


func _reset_propagation() -> void:
	_propagation_distance = 0.0
	_last_origin = Vector3.ZERO
	_last_direction = Vector3.ZERO
	_has_propagation_basis = false


static func apply_continuous_hits(
	building: Node,
	path: Dictionary,
	damage_per_second: float,
	duration: float,
	notify_source: bool
) -> void:
	for raw_reflection in path.get("reflections", []):
		if raw_reflection is Dictionary:
			var reflection: Dictionary = raw_reflection
			var reflection_multiplier := float(
				reflection.get("path_damage_multiplier", get_path_damage_multiplier(path))
			)
			ReflectionDamageScript.apply(
				reflection,
				maxf(0.0, damage_per_second)
					* maxf(0.0, reflection_multiplier)
					* maxf(0.0, duration)
			)
	var slow_multiplier: float = building.call("get_laser_slow_multiplier")
	var slow_duration: float = building.call("get_laser_slow_duration")
	var raw_hits: Array = path.get("hits", [])
	for raw_hit in raw_hits:
		if not raw_hit is Dictionary:
			continue
		var hit: Dictionary = raw_hit
		var target := hit.get("target") as CombatTarget
		if target == null or not is_instance_valid(target) or not target.is_alive():
			continue
		target.apply_movement_slow(slow_multiplier, slow_duration)
		var hit_multiplier := float(hit.get("damage_multiplier", get_path_damage_multiplier(path)))
		var hit_damage_per_second := maxf(0.0, damage_per_second) * maxf(0.0, hit_multiplier)
		var applied := target.take_damage_over_time(hit_damage_per_second, duration)
		if notify_source:
			building.call("notify_attack", target, applied, true)
