## Reflected continuous beam with finite enemy penetration and timed cold bursts.
class_name LaserAttackStrategy
extends IAttackStrategy

const ContinuousLaserPathScript := preload("res://scripts/combat/ContinuousLaserPath.gd")
const ReflectionDamageScript := preload("res://scripts/combat/ReflectionDamage.gd")

var _burst_elapsed: float = 0.0
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
	_tick_burst(building, combat_manager, path, start, maximum_end, resolved_delta)


func reset(building: Node) -> void:
	_burst_elapsed = 0.0
	_reset_propagation()
	building.call("clear_attack_visual")


func debug_get_propagation_distance() -> float:
	return _propagation_distance


func _tick_burst(
	building: Node,
	combat_manager: CombatManager,
	path: Dictionary,
	start: Vector3,
	maximum_end: Vector3,
	delta: float
) -> void:
	if int(building.get("level")) < 2:
		_burst_elapsed = 0.0
		return
	var interval: float = building.call("get_laser_burst_interval")
	if interval <= 0.0:
		_burst_elapsed = 0.0
		return
	_burst_elapsed += maxf(0.0, delta)
	var first_hit := get_first_hit_position(path)
	while _burst_elapsed >= interval:
		_burst_elapsed -= interval
		if bool(first_hit.get("hit", false)):
			apply_endpoint_burst(
				building,
				combat_manager,
				first_hit.get("position", maximum_end),
				true,
				get_path_damage_multiplier(path)
			)
		# Copies resolve their own first hit from their independently traced path,
		# so the source notification remains periodic even when this path is empty.
		building.call(
			"notify_copy_attack",
			&"laser_burst",
			start,
			maximum_end,
			float(building.call("get_laser_burst_damage"))
		)


static func trace_laser_path(
	building: Node,
	combat_manager: CombatManager,
	start: Vector3,
	direction: Vector3,
	distance_limit: float = -1.0,
	penetration_bonus: int = 0
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
		combat_manager.get_projectile_blocker_resolver()
	)


static func get_path_length(path: Dictionary) -> float:
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
	var resolved_damage_per_second := (
		maxf(0.0, damage_per_second) * get_path_damage_multiplier(path)
	)
	var mirror_damage := resolved_damage_per_second * maxf(0.0, duration)
	for raw_reflection in path.get("reflections", []):
		if raw_reflection is Dictionary:
			ReflectionDamageScript.apply(raw_reflection, mirror_damage)
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
		var applied := target.take_damage_over_time(resolved_damage_per_second, duration)
		if notify_source:
			building.call("notify_attack", target, applied, true)


static func apply_endpoint_burst(
	building: Node,
	combat_manager: CombatManager,
	endpoint: Vector3,
	notify_source: bool,
	damage_multiplier: float = 1.0
) -> void:
	var radius: float = building.call("get_laser_burst_radius_world")
	if radius <= 0.0:
		return
	var color: Color = building.call("get_attack_color")
	combat_manager.spawn_laser_burst_visual(endpoint, radius, color)
	var slow_multiplier: float = building.call("get_laser_slow_multiplier")
	var slow_duration: float = building.call("get_laser_slow_duration")
	var freeze_duration := (
		float(building.call("get_laser_freeze_duration"))
		if int(building.get("level")) >= 3
		else 0.0
	)
	var burst_damage: float = (
		float(building.call("get_laser_burst_damage"))
		* (maxf(0.0, damage_multiplier) if is_finite(damage_multiplier) else 1.0)
	)
	for target in combat_manager.get_targets_in_range(endpoint, radius):
		if not bool(building.call("affects_target", target)):
			continue
		target.apply_movement_slow(slow_multiplier, slow_duration)
		if freeze_duration > 0.0:
			target.apply_freeze(freeze_duration)
		var applied := target.take_damage(burst_damage)
		if notify_source:
			building.call("notify_attack", target, applied, false)
