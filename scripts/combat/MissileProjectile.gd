## Explosive projectile with a collision-free launch loop and optional homing.
## Reflection surfaces alter its real flight direction; copy mirrors are absent
## from the reflection/blocker query chain and are therefore crossed directly.
class_name MissileProjectile
extends Projectile

signal exploded(world_position: Vector3, radius: float)

const MissileTargetMarkerScript := preload("res://scripts/combat/MissileTargetMarker.gd")
const MissileTrailScript := preload("res://scripts/combat/MissileTrail.gd")
const MissileExplosionEffectScript := preload("res://scripts/combat/MissileExplosionEffect.gd")
const MissileReflectionDamageScript := preload("res://scripts/combat/ReflectionDamage.gd")

var _orbit_anchor: Vector3
var _orbit_forward: Vector3 = Vector3.FORWARD
var _orbit_right: Vector3 = Vector3.RIGHT
var _orbit_elapsed: float = 0.0
var _orbit_duration: float = 0.72
var _orbit_radius_x: float = 0.95
var _orbit_radius_z: float = 0.62
var _orbit_vertical_amplitude: float = 0.12
var _orbit_direction_sign: float = 1.0
var _orbit_complete: bool = false
var _homing_turn_speed_radians: float = deg_to_rad(540.0)
var _speed_variation_ratio: float = 0.12
var _speed_variation_frequency: float = 2.4
var _speed_phase: float = 0.0
var _visual_wobble: float = 0.045
var _visual_roll_radians: float = deg_to_rad(12.0)
var _wobble_phase: float = 0.0
var _flight_elapsed: float = 0.0
var _explosion_radius: float = 1.0
var _explosion_duration: float = 0.48
var _trail_lifetime: float = 0.42
var _trail_width: float = 0.055
var _target_marker_size: float = 0.72
var _color: Color = Color(1.0, 0.45, 0.08, 1.0)
var _visual_wobble_root: Node3D
var _target_marker: MissileTargetMarker


func configure_targeted_missile(
	start: Vector3,
	target: CombatTarget,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition,
	source_building: Building,
	target_query: Callable,
	reflection_resolver: Callable,
	blocker_resolver: Callable,
	configuration: Dictionary
) -> void:
	var initial_direction := target.get_target_position() - start
	_configure_missile(
		start,
		target,
		initial_direction,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color,
		model_asset,
		source_building,
		target_query,
		reflection_resolver,
		blocker_resolver,
		configuration
	)


func configure_directional_missile(
	start: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition,
	source_building: Building,
	target_query: Callable,
	reflection_resolver: Callable,
	blocker_resolver: Callable,
	configuration: Dictionary
) -> void:
	_configure_missile(
		start,
		null,
		direction,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color,
		model_asset,
		source_building,
		target_query,
		reflection_resolver,
		blocker_resolver,
		configuration
	)


func _configure_missile(
	start: Vector3,
	target: CombatTarget,
	direction: Vector3,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition,
	source_building: Building,
	target_query: Callable,
	reflection_resolver: Callable,
	blocker_resolver: Callable,
	configuration: Dictionary
) -> void:
	global_position = start
	_target = target
	_source_building = source_building
	_last_target_position = (
		target.get_target_position()
		if target != null and is_instance_valid(target)
		else start + direction.normalized() * maxf(0.1, maximum_distance)
	)
	_direction = direction.normalized()
	if _direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		_direction = Vector3.FORWARD
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, maximum_distance)
	_distance_traveled = 0.0
	_penetration_limit = 0
	_penetration_value = 0
	_contact_targets.clear()
	_target_query = target_query
	_reflection_resolver = reflection_resolver
	_blocker_resolver = blocker_resolver
	_has_reflected = false
	_ballistic_mode = target == null
	_active = false
	_color = color
	_apply_configuration(configuration)
	_prepare_orbit_basis(start, _direction)
	_randomize_motion()
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color, model_asset)
	_wrap_projectile_visuals()
	_update_orientation(_direction)
	_active = true
	_spawn_trail()
	if target != null:
		_spawn_target_marker(target)


func _process(delta: float) -> void:
	if not _active:
		return
	var remaining_delta := maxf(0.0, delta)
	if not _orbit_complete:
		var orbit_step := minf(remaining_delta, _orbit_duration - _orbit_elapsed)
		_advance_orbit(orbit_step)
		remaining_delta = maxf(0.0, remaining_delta - orbit_step)
		if not _orbit_complete:
			_update_visual_wobble()
			return
	if remaining_delta > 0.0:
		_advance_powered_flight(remaining_delta)
	_update_visual_wobble()


func is_orbiting() -> bool:
	return not _orbit_complete


func get_orbit_direction_sign() -> int:
	return 1 if _orbit_direction_sign > 0.0 else -1


func get_orbit_progress() -> float:
	return clampf(_orbit_elapsed / _orbit_duration, 0.0, 1.0)


func get_explosion_radius() -> float:
	return _explosion_radius


func get_target_marker() -> MissileTargetMarker:
	return _target_marker if _target_marker != null and is_instance_valid(_target_marker) else null


func get_trail_position() -> Vector3:
	return (
		_visual_wobble_root.global_position
		if _visual_wobble_root != null and is_instance_valid(_visual_wobble_root)
		else global_position
	)


func _apply_configuration(configuration: Dictionary) -> void:
	_explosion_radius = maxf(0.0, float(configuration.get("explosion_radius", 1.0)))
	_orbit_duration = maxf(0.01, float(configuration.get("orbit_duration", 0.72)))
	_orbit_radius_x = maxf(0.0, float(configuration.get("orbit_radius_x", 0.95)))
	_orbit_radius_z = maxf(0.0, float(configuration.get("orbit_radius_z", 0.62)))
	_orbit_vertical_amplitude = maxf(0.0, float(configuration.get("orbit_vertical_amplitude", 0.12)))
	_homing_turn_speed_radians = deg_to_rad(maxf(1.0, float(configuration.get("homing_turn_speed_degrees", 540.0))))
	_speed_variation_ratio = clampf(float(configuration.get("speed_variation_ratio", 0.12)), 0.0, 0.95)
	_speed_variation_frequency = maxf(0.01, float(configuration.get("speed_variation_frequency", 2.4)))
	_visual_wobble = maxf(0.0, float(configuration.get("visual_wobble", 0.045)))
	_visual_roll_radians = deg_to_rad(maxf(0.0, float(configuration.get("visual_roll_degrees", 12.0))))
	_trail_lifetime = maxf(0.05, float(configuration.get("trail_lifetime", 0.42)))
	_trail_width = maxf(0.005, float(configuration.get("trail_width", 0.055)))
	_target_marker_size = maxf(0.05, float(configuration.get("target_marker_size", 0.72)))
	_explosion_duration = maxf(0.05, float(configuration.get("explosion_duration", 0.48)))


func _prepare_orbit_basis(start: Vector3, launch_direction: Vector3) -> void:
	_orbit_anchor = start
	_orbit_forward = Vector3(launch_direction.x, 0.0, launch_direction.z).normalized()
	if _orbit_forward.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		_orbit_forward = Vector3.FORWARD
	_orbit_right = _orbit_forward.cross(Vector3.UP).normalized()
	if _orbit_right.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		_orbit_right = Vector3.RIGHT
	_orbit_elapsed = 0.0
	_orbit_complete = false
	_flight_elapsed = 0.0


func _randomize_motion() -> void:
	var random := RandomNumberGenerator.new()
	random.randomize()
	_orbit_direction_sign = -1.0 if random.randi_range(0, 1) == 0 else 1.0
	_speed_phase = random.randf_range(0.0, TAU)
	_wobble_phase = random.randf_range(0.0, TAU)


func _advance_orbit(delta: float) -> void:
	if delta <= 0.0:
		return
	var previous_position := global_position
	_orbit_elapsed = minf(_orbit_duration, _orbit_elapsed + delta)
	var factor := clampf(_orbit_elapsed / _orbit_duration, 0.0, 1.0)
	var angle := _orbit_direction_sign * TAU * factor
	var radial_envelope := sin(PI * factor)
	var offset := (
		_orbit_right * (_orbit_radius_x * radial_envelope * cos(angle))
		+ _orbit_forward * (_orbit_radius_z * radial_envelope * sin(angle))
		+ Vector3.UP * (_orbit_vertical_amplitude * radial_envelope * sin(angle * 2.0))
	)
	global_position = _orbit_anchor + offset
	var tangent := global_position - previous_position
	if tangent.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
		_update_orientation(tangent.normalized())
	if _orbit_elapsed >= _orbit_duration - 0.000001:
		_finish_orbit()


func _finish_orbit() -> void:
	_orbit_complete = true
	global_position = _orbit_anchor
	if _target != null and is_instance_valid(_target) and _target.is_alive():
		_last_target_position = _target.get_target_position()
		var to_target := _last_target_position - global_position
		if to_target.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
			_direction = to_target.normalized()
	else:
		_target = null
		_ballistic_mode = true
	_update_orientation(_direction)


func _advance_powered_flight(delta: float) -> void:
	_flight_elapsed += delta
	_update_homing_direction(delta)
	if not _active:
		return
	var remaining_distance := _maximum_distance - _distance_traveled
	if remaining_distance <= 0.000001:
		_explode()
		return
	var speed_factor := 1.0 + _speed_variation_ratio * sin(
		TAU * _speed_variation_frequency * _flight_elapsed + _speed_phase
	)
	var travel_budget := minf(_speed * maxf(0.05, speed_factor) * delta, remaining_distance)
	_advance_flight(travel_budget)
	if _active and _distance_traveled >= _maximum_distance - 0.000001:
		_explode()


func _update_homing_direction(delta: float) -> void:
	if _ballistic_mode:
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		_target = null
		_ballistic_mode = true
		return
	_last_target_position = _target.get_target_position()
	var desired := _last_target_position - global_position
	if desired.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		_explode(_target)
		return
	desired = desired.normalized()
	var angle := _direction.angle_to(desired)
	if angle <= 0.000001:
		_direction = desired
		return
	var interpolation := minf(1.0, _homing_turn_speed_radians * delta / angle)
	_direction = _direction.slerp(desired, interpolation).normalized()


func _advance_flight(travel_budget: float) -> void:
	var remaining := maxf(0.0, travel_budget)
	var reflections_this_frame := 0
	while _active and remaining > 0.000001:
		var start := global_position
		var end := start + _direction * remaining
		var reflection_hit := _query_reflection(start, end)
		var blocker_hit := _query_blocker(start, end)
		var reflection_distance := _valid_interaction_distance(reflection_hit, remaining)
		var blocker_distance := _valid_interaction_distance(blocker_hit, remaining)
		var blocker_is_first := blocker_distance <= reflection_distance
		var nearest_interaction := minf(reflection_distance, blocker_distance)
		var segment_distance := nearest_interaction if is_finite(nearest_interaction) else remaining
		var segment_end := start + _direction * segment_distance
		var reflecting_target := (
			reflection_hit.get("reflector") as CombatTarget
			if not blocker_is_first and is_finite(reflection_distance)
			else null
		)
		var target_hit := _find_first_missile_target_hit(start, segment_end, reflecting_target)
		if bool(target_hit.get("hit", false)):
			var target_distance := clampf(float(target_hit.get("distance", 0.0)), 0.0, segment_distance)
			if target_distance < segment_distance - 0.000001 or not is_finite(nearest_interaction):
				global_position = start + _direction * target_distance
				_distance_traveled += target_distance
				_explode(target_hit.get("target") as CombatTarget)
				return
		if blocker_is_first and is_finite(blocker_distance):
			global_position = blocker_hit.get("position", segment_end)
			_distance_traveled += blocker_distance
			_explode()
			return
		if not is_finite(reflection_distance):
			global_position = end
			_distance_traveled += remaining
			remaining = 0.0
			break
		global_position = reflection_hit.get("position", segment_end)
		_distance_traveled += reflection_distance
		remaining -= reflection_distance
		var normal: Vector3 = reflection_hit.get("normal", Vector3.ZERO)
		if normal.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
			remaining = 0.0
			break
		MissileReflectionDamageScript.apply(reflection_hit, _damage)
		_direction = (_direction - 2.0 * _direction.dot(normal) * normal).normalized()
		_has_reflected = true
		reflections_this_frame += 1
		reflected.emit(reflection_hit.get("mirror") as CopyMirror, global_position, _direction)
		var epsilon := minf(
			maxf(0.0001, float(reflection_hit.get("epsilon", 0.0001))),
			remaining
		)
		if epsilon > 0.0:
			global_position += _direction * epsilon
			_distance_traveled += epsilon
			remaining -= epsilon
		var frame_cap := maxi(1, int(reflection_hit.get("max_reflections_per_frame", 1)))
		if reflections_this_frame >= frame_cap:
			break
	_update_orientation(_direction)


func _find_first_missile_target_hit(
	start: Vector3,
	end: Vector3,
	excluded_target: CombatTarget = null
) -> Dictionary:
	if not _target_query.is_valid() or start.distance_squared_to(end) <= 0.000001:
		return {"hit": false}
	var queried: Variant = _target_query.call()
	if not queried is Array:
		return {"hit": false}
	var best_target: CombatTarget
	var best_distance := INF
	for raw_target in queried:
		if not raw_target is CombatTarget:
			continue
		var candidate := raw_target as CombatTarget
		if candidate == null or not is_instance_valid(candidate) or not candidate.is_alive():
			continue
		if candidate == excluded_target:
			continue
		var hit_distance := _ray_sphere_entry_distance(
			start,
			end,
			candidate.get_target_position(),
			maxf(0.0, candidate.hit_radius)
		)
		if hit_distance >= 0.0 and hit_distance < best_distance:
			best_target = candidate
			best_distance = hit_distance
	return {
		"hit": best_target != null,
		"target": best_target,
		"distance": best_distance if best_target != null else 0.0,
	}


func _explode(contact_target: CombatTarget = null) -> void:
	if not _active:
		return
	_active = false
	var explosion_position := global_position
	_spawn_explosion_visual(explosion_position)
	var damaged_ids: Dictionary = {}
	if _target_query.is_valid():
		var queried: Variant = _target_query.call()
		if queried is Array:
			for raw_target in queried:
				if not raw_target is CombatTarget:
					continue
				var candidate := raw_target as CombatTarget
				if candidate == null or not is_instance_valid(candidate) or not candidate.is_alive():
					continue
				var offset := Vector2(
					candidate.global_position.x - explosion_position.x,
					candidate.global_position.z - explosion_position.z
				)
				if offset.length_squared() <= _explosion_radius * _explosion_radius + 0.000001:
					_damage_explosion_target(candidate, damaged_ids)
	if contact_target != null and is_instance_valid(contact_target) and contact_target.is_alive():
		_damage_explosion_target(contact_target, damaged_ids)
	exploded.emit(explosion_position, _explosion_radius)
	queue_free()


func _damage_explosion_target(target: CombatTarget, damaged_ids: Dictionary) -> void:
	var instance_id := target.get_instance_id()
	if damaged_ids.has(instance_id):
		return
	damaged_ids[instance_id] = true
	var applied_damage := target.take_damage(_damage)
	impacted.emit(target, applied_damage)


func _spawn_explosion_visual(world_position: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var effect := MissileExplosionEffectScript.new() as MissileExplosionEffect
	parent.add_child(effect)
	effect.configure(world_position, _explosion_radius, _color, _explosion_duration)


func _wrap_projectile_visuals() -> void:
	var existing_children := get_children()
	_visual_wobble_root = Node3D.new()
	_visual_wobble_root.name = &"MissileVisualWobbleRoot"
	add_child(_visual_wobble_root)
	for child in existing_children:
		remove_child(child)
		_visual_wobble_root.add_child(child)


func _update_visual_wobble() -> void:
	if _visual_wobble_root == null:
		return
	var elapsed := _orbit_elapsed + _flight_elapsed
	_visual_wobble_root.position = Vector3(
		sin(elapsed * 8.0 + _wobble_phase) * _visual_wobble,
		cos(elapsed * 6.5 + _wobble_phase) * _visual_wobble * 0.55,
		0.0
	)
	_visual_wobble_root.rotation.z = sin(elapsed * 7.2 + _wobble_phase) * _visual_roll_radians


func _spawn_trail() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var trail := MissileTrailScript.new() as MissileTrail
	parent.add_child(trail)
	trail.configure(self, _trail_width, _trail_lifetime, _color.lightened(0.18))


func _spawn_target_marker(target: CombatTarget) -> void:
	var parent := get_parent()
	if parent == null:
		return
	_target_marker = MissileTargetMarkerScript.new() as MissileTargetMarker
	parent.add_child(_target_marker)
	_target_marker.configure(target, self, _target_marker_size)
