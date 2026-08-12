## Copy projectile supporting a legacy fixed endpoint or a from-start straight
## ballistic path. It never acquires an independent homing target.
class_name MirrorProjectionProjectile
extends Node3D

const ReflectionDamageScript := preload("res://scripts/combat/ReflectionDamage.gd")

signal impacted(target: CombatTarget, applied_damage: float)
signal reflected(mirror: CopyMirror, world_position: Vector3, direction: Vector3)

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const CONTACT_CLEARANCE := 0.001

var _combat_manager: CombatManager
var _source_building: Building
var _end: Vector3
var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 1.0
var _damage: float = 0.0
var _maximum_distance: float = 1.0
var _distance_traveled: float = 0.0
var _penetration_limit: int = 0
var _penetration_value: int = 0
var _contact_targets: Dictionary = {}
var _reflection_resolver: Callable
var _blocker_resolver: Callable
var _has_reflected: bool = false
var _ballistic_from_start: bool = false
var _active: bool = false


func configure(
	combat_manager: CombatManager,
	source_building: Building,
	start: Vector3,
	end: Vector3,
	speed: float,
	damage: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	maximum_distance: float = -1.0,
	reflection_resolver: Callable = Callable(),
	ballistic_from_start: bool = false,
	penetration_count: int = 0,
	blocker_resolver: Callable = Callable()
) -> void:
	_combat_manager = combat_manager
	_source_building = source_building
	global_position = start
	_end = end
	_direction = (end - start).normalized()
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, start.distance_to(end) if maximum_distance < 0.0 else maximum_distance)
	_distance_traveled = 0.0
	_penetration_limit = maxi(0, penetration_count)
	_penetration_value = 0
	_contact_targets.clear()
	_reflection_resolver = reflection_resolver
	_blocker_resolver = blocker_resolver
	_has_reflected = false
	_ballistic_from_start = ballistic_from_start
	_active = false
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color, model_asset)
	_update_orientation(_direction)
	_active = true


func _process(delta: float) -> void:
	if not _active:
		return
	var remaining_lifetime_distance := _maximum_distance - _distance_traveled
	if remaining_lifetime_distance <= 0.0:
		queue_free()
		return
	var travel_budget := minf(_speed * maxf(0.0, delta), remaining_lifetime_distance)
	if not _has_reflected and not _ballistic_from_start:
		var distance_to_end := global_position.distance_to(_end)
		travel_budget = minf(travel_budget, distance_to_end)
	_advance(travel_budget)
	if not _active:
		return
	if not _has_reflected and not _ballistic_from_start and global_position.distance_squared_to(_end) <= 0.000001:
		global_position = _end
		_impact_endpoint()
		return
	if _distance_traveled >= _maximum_distance - 0.000001:
		queue_free()


func get_distance_traveled() -> float:
	return _distance_traveled


func has_reflected() -> bool:
	return _has_reflected


func get_travel_direction() -> Vector3:
	return _direction


func _advance(travel_budget: float) -> void:
	var remaining := maxf(0.0, travel_budget)
	var reflections_this_frame := 0
	while _active and remaining > 0.000001:
		_refresh_contact_targets()
		var start := global_position
		var end := start + _direction * remaining
		var mirror_hit := _query_reflection(start, end)
		var blocker_hit := _query_blocker(start, end)
		var mirror_distance := _valid_interaction_distance(mirror_hit, remaining)
		var blocker_distance := _valid_interaction_distance(blocker_hit, remaining)
		var blocker_is_first := blocker_distance <= mirror_distance
		var nearest_interaction := minf(mirror_distance, blocker_distance)
		var segment_distance := (
			nearest_interaction if is_finite(nearest_interaction) else remaining
		)
		var segment_end := start + _direction * segment_distance
		var reflecting_target := (
			mirror_hit.get("reflector") as CombatTarget
			if not blocker_is_first and is_finite(mirror_distance)
			else null
		)
		if _has_reflected or _ballistic_from_start:
			var target_center_limit := (
				blocker_distance
				if blocker_is_first and is_finite(blocker_distance)
				else INF
			)
			var target_hit := _find_first_target_hit(
				start,
				segment_end,
				target_center_limit,
				reflecting_target
			)
			if bool(target_hit.get("hit", false)):
				var target_distance := clampf(float(target_hit.get("distance", 0.0)), 0.0, segment_distance)
				var target_center_distance := float(target_hit.get("center_distance", INF))
				var target_precedes_blocker := (
					not blocker_is_first
					or not is_finite(blocker_distance)
					or target_center_distance < blocker_distance - 0.000001
				)
				if (
					target_precedes_blocker
					and (
						target_distance < segment_distance - 0.000001
						or not is_finite(nearest_interaction)
					)
				):
					global_position = start + _direction * target_distance
					_distance_traveled += target_distance
					if not _impact_target(target_hit.get("target") as CombatTarget):
						return
					var clearance_budget := minf(
						remaining - target_distance,
						maxf(0.0, segment_distance - target_distance)
					)
					var contact_step := minf(CONTACT_CLEARANCE, clearance_budget)
					if contact_step > 0.0:
						global_position += _direction * contact_step
						_distance_traveled += contact_step
						remaining -= target_distance + contact_step
					else:
						remaining -= target_distance
					continue
		if blocker_is_first and is_finite(blocker_distance):
			global_position = blocker_hit.get("position", segment_end)
			_distance_traveled += blocker_distance
			_active = false
			queue_free()
			return
		if not is_finite(mirror_distance):
			global_position = end
			_distance_traveled += remaining
			remaining = 0.0
			break
		global_position = mirror_hit.get("position", segment_end)
		_distance_traveled += segment_distance
		remaining -= segment_distance
		var normal: Vector3 = mirror_hit.get("normal", Vector3.ZERO)
		if normal.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
			remaining = 0.0
			break
		ReflectionDamageScript.apply(mirror_hit, _damage)
		_apply_reflection_modifiers(mirror_hit)
		_direction = (_direction - 2.0 * _direction.dot(normal) * normal).normalized()
		if reflecting_target != null and is_instance_valid(reflecting_target):
			_contact_targets[reflecting_target.get_instance_id()] = reflecting_target
		_has_reflected = true
		reflections_this_frame += 1
		reflected.emit(mirror_hit.get("mirror") as CopyMirror, global_position, _direction)
		var epsilon := minf(
			maxf(0.0001, float(mirror_hit.get("epsilon", 0.0001))),
			remaining
		)
		if epsilon > 0.0:
			global_position += _direction * epsilon
			_distance_traveled += epsilon
			remaining -= epsilon
		var frame_cap := maxi(1, int(mirror_hit.get("max_reflections_per_frame", 1)))
		if reflections_this_frame >= frame_cap:
			break
	_update_orientation(_direction)


func _apply_reflection_modifiers(reflection_hit: Dictionary) -> void:
	var damage_multiplier := float(reflection_hit.get("damage_multiplier", 1.0))
	if is_finite(damage_multiplier):
		_damage *= maxf(0.0, damage_multiplier)
	_penetration_limit += maxi(0, int(reflection_hit.get("penetration_bonus", 0)))


func debug_get_damage() -> float:
	return _damage


func debug_get_remaining_penetration() -> int:
	return maxi(0, _penetration_limit - _penetration_value)


func _query_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_resolver.is_valid():
		return {"hit": false}
	var result: Variant = _reflection_resolver.call(start, end)
	return result if result is Dictionary else {"hit": false}


func _query_blocker(start: Vector3, end: Vector3) -> Dictionary:
	if not _blocker_resolver.is_valid():
		return {"hit": false}
	var result: Variant = _blocker_resolver.call(start, end)
	return result if result is Dictionary else {"hit": false}


func _valid_interaction_distance(hit: Dictionary, maximum_distance: float) -> float:
	if not bool(hit.get("hit", false)):
		return INF
	var distance := float(hit.get("distance", INF))
	if not is_finite(distance) or distance < 0.0 or distance > maximum_distance + 0.000001:
		return INF
	return clampf(distance, 0.0, maximum_distance)


func _find_first_target_hit(
	start: Vector3,
	end: Vector3,
	maximum_center_distance: float = INF,
	excluded_target: CombatTarget = null
) -> Dictionary:
	var best: CombatTarget
	var best_distance := INF
	var best_center_distance := INF
	var segment_direction := (end - start).normalized()
	if (
		_combat_manager == null
		or _source_building == null
		or not is_instance_valid(_source_building)
	):
		return {"hit": false}
	for target in _combat_manager.get_targets():
		if not target.is_alive() or not _source_building.affects_target(target):
			continue
		if target == excluded_target:
			continue
		if _contact_targets.has(target.get_instance_id()):
			continue
		var center_distance := maxf(
			0.0,
			(target.get_target_position() - start).dot(segment_direction)
		)
		if center_distance >= maximum_center_distance - 0.000001:
			continue
		var distance := _ray_sphere_entry_distance(
			start,
			end,
			target.get_target_position(),
			maxf(0.0, target.hit_radius)
		)
		if distance >= 0.0 and distance < best_distance:
			best = target
			best_distance = distance
			best_center_distance = center_distance
	return {
		"hit": best != null,
		"target": best,
		"distance": best_distance if best != null else 0.0,
		"center_distance": best_center_distance if best != null else 0.0,
	}


func _ray_sphere_entry_distance(
	start: Vector3,
	end: Vector3,
	center: Vector3,
	radius: float
) -> float:
	var segment := end - start
	var length := segment.length()
	if length <= 0.000001:
		return 0.0 if start.distance_squared_to(center) <= radius * radius else -1.0
	var direction := segment / length
	var to_center := center - start
	var projected := to_center.dot(direction)
	var closest_squared := to_center.length_squared() - projected * projected
	var radius_squared := radius * radius
	if closest_squared > radius_squared:
		return -1.0
	var half_chord := sqrt(maxf(0.0, radius_squared - closest_squared))
	var entry := projected - half_chord
	if entry < 0.0:
		entry = 0.0 if start.distance_squared_to(center) <= radius_squared else projected + half_chord
	return entry if entry >= 0.0 and entry <= length else -1.0


func _impact_endpoint() -> void:
	var target := _find_target_at_endpoint()
	if target == null:
		_active = false
		queue_free()
		return
	_impact_target(target)


func _impact_target(target: CombatTarget) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return _active
	_contact_targets[target.get_instance_id()] = target
	var applied_damage := 0.0
	applied_damage = target.take_damage(_damage)
	impacted.emit(target, applied_damage)
	_penetration_value += 1
	if _penetration_value > _penetration_limit:
		_active = false
		queue_free()
		return false
	_ballistic_from_start = true
	return true


func _refresh_contact_targets() -> void:
	for instance_id in _contact_targets.keys():
		var target_value: Variant = _contact_targets[instance_id]
		if not is_instance_valid(target_value):
			_contact_targets.erase(instance_id)
			continue
		var target := target_value as CombatTarget
		if (
			target == null
			or not target.is_alive()
			or global_position.distance_to(target.get_target_position()) > target.hit_radius + CONTACT_CLEARANCE
		):
			_contact_targets.erase(instance_id)


func _find_target_at_endpoint() -> CombatTarget:
	if _combat_manager == null or _source_building == null or not is_instance_valid(_source_building):
		return null
	var best: CombatTarget
	var best_distance := INF
	for target in _combat_manager.get_targets():
		if not target.is_alive() or not _source_building.affects_target(target):
			continue
		var distance := Vector2(target.global_position.x - _end.x, target.global_position.z - _end.z).length()
		if distance <= target.hit_radius and distance < best_distance:
			best = target
			best_distance = distance
	return best


func _build_visual(
	length: float,
	width: float,
	color: Color,
	model_asset: ModelAssetDefinition
) -> void:
	if model_asset != null:
		var custom_visual := model_asset.instantiate_fitted_model(
			&"MirrorProjectileModel",
			AABB(
				Vector3(-width * 0.5, -width * 0.5, -length * 0.5),
				Vector3(width, width, length)
			)
		)
		if custom_visual != null:
			add_child(custom_visual)
			_apply_projection_overlay(custom_visual, color)
			return
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.4
	instance.material_override = material
	add_child(instance)


func _apply_projection_overlay(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var overlay := StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.albedo_color = Color(color.r, color.g, color.b, 0.28)
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.emission_enabled = true
		overlay.emission = color
		overlay.emission_energy_multiplier = 1.4
		mesh_instance.material_overlay = overlay
	for child in node.get_children():
		_apply_projection_overlay(child, color)


func _update_orientation(direction: Vector3) -> void:
	if direction.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
		look_at(global_position + direction, Vector3.UP)
