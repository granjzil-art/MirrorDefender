## Targeted homing or source-facing ballistic projectile. Any mirror reflection
## keeps/enters ballistic mode, and every segment consumes one distance budget.
class_name Projectile
extends Node3D

signal impacted(target: CombatTarget, applied_damage: float)
signal reflected(mirror: CopyMirror, world_position: Vector3, direction: Vector3)

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001

var _target: CombatTarget
var _source_building: Building
var _last_target_position: Vector3
var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 1.0
var _damage: float = 0.0
var _maximum_distance: float = 1.0
var _distance_traveled: float = 0.0
var _active: bool = false
var _has_reflected: bool = false
var _ballistic_mode: bool = false
var _target_query: Callable
var _reflection_resolver: Callable


func _process(delta: float) -> void:
	if not _active:
		return
	if not _ballistic_mode:
		if is_instance_valid(_target) and _target.is_alive():
			_last_target_position = _target.get_target_position()
		var to_target := _last_target_position - global_position
		if to_target.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
			if is_instance_valid(_target) and _target.is_alive():
				_impact(_target)
			else:
				queue_free()
			return
		_direction = to_target.normalized()
	var remaining_lifetime_distance := _maximum_distance - _distance_traveled
	if remaining_lifetime_distance <= 0.0:
		queue_free()
		return
	var travel_budget := minf(_speed * maxf(0.0, delta), remaining_lifetime_distance)
	_advance(travel_budget)
	if _active and _distance_traveled >= _maximum_distance - 0.000001:
		queue_free()


func configure(
	start: Vector3,
	target: CombatTarget,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	target_query: Callable = Callable(),
	reflection_resolver: Callable = Callable()
) -> void:
	global_position = start
	_target = target
	_source_building = source_building
	_last_target_position = target.get_target_position()
	_direction = (_last_target_position - start).normalized()
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, maximum_distance)
	_target_query = target_query
	_reflection_resolver = reflection_resolver
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color, model_asset)
	_update_orientation(_direction)
	_active = true


## Configures a targetless projectile that checks every travel segment from spawn.
func configure_directional(
	start: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	target_query: Callable = Callable(),
	reflection_resolver: Callable = Callable()
) -> void:
	global_position = start
	_target = null
	_source_building = source_building
	_direction = direction.normalized()
	_last_target_position = start + _direction * maxf(0.1, maximum_distance)
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, maximum_distance)
	_target_query = target_query
	_reflection_resolver = reflection_resolver
	_ballistic_mode = true
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color, model_asset)
	_update_orientation(_direction)
	_active = true


func get_distance_traveled() -> float:
	return _distance_traveled


func has_reflected() -> bool:
	return _has_reflected


func is_ballistic() -> bool:
	return _ballistic_mode


func get_travel_direction() -> Vector3:
	return _direction


func _advance(travel_budget: float) -> void:
	var remaining := maxf(0.0, travel_budget)
	var reflections_this_frame := 0
	while _active and remaining > 0.000001:
		var start := global_position
		var end := start + _direction * remaining
		var mirror_hit := _query_reflection(start, end)
		var segment_distance := (
			clampf(float(mirror_hit.get("distance", remaining)), 0.0, remaining)
			if bool(mirror_hit.get("hit", false))
			else remaining
		)
		var segment_end := start + _direction * segment_distance
		var target_hit := _find_first_target_hit(start, segment_end)
		if bool(target_hit.get("hit", false)):
			var target_distance := clampf(float(target_hit.get("distance", 0.0)), 0.0, segment_distance)
			global_position = start + _direction * target_distance
			_distance_traveled += target_distance
			_impact(target_hit.get("target") as CombatTarget)
			return
		if not bool(mirror_hit.get("hit", false)):
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
		_direction = (_direction - 2.0 * _direction.dot(normal) * normal).normalized()
		_has_reflected = true
		_ballistic_mode = true
		reflections_this_frame += 1
		var mirror := mirror_hit.get("mirror") as CopyMirror
		reflected.emit(mirror, global_position, _direction)
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


func _query_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_resolver.is_valid():
		return {"hit": false}
	var result: Variant = _reflection_resolver.call(start, end)
	return result if result is Dictionary else {"hit": false}


func _find_first_target_hit(start: Vector3, end: Vector3) -> Dictionary:
	var candidates: Array = []
	if _ballistic_mode and _target_query.is_valid():
		var queried: Variant = _target_query.call()
		if queried is Array:
			candidates = queried
	elif is_instance_valid(_target):
		candidates = [_target]
	var best_target: CombatTarget
	var best_distance := INF
	for raw_target in candidates:
		if not raw_target is CombatTarget:
			continue
		var candidate := raw_target as CombatTarget
		if not is_instance_valid(candidate) or not candidate.is_alive():
			continue
		if _source_building != null and is_instance_valid(_source_building):
			if not _source_building.affects_target(candidate):
				continue
		var hit_distance := _ray_sphere_entry_distance(
			start,
			end,
			candidate.get_target_position(),
			maxf(0.0, candidate.hit_radius)
		)
		if hit_distance >= 0.0 and hit_distance < best_distance:
			best_distance = hit_distance
			best_target = candidate
	return {
		"hit": best_target != null,
		"target": best_target,
		"distance": best_distance if best_target != null else 0.0,
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


func _impact(target: CombatTarget) -> void:
	_active = false
	var applied_damage: float = 0.0
	if is_instance_valid(target) and target.is_alive():
		applied_damage = target.take_damage(_damage)
		impacted.emit(target, applied_damage)
	queue_free()


func _build_visual(
	length: float,
	width: float,
	color: Color,
	model_asset: ModelAssetDefinition
) -> void:
	if model_asset != null:
		var custom_visual := model_asset.instantiate_fitted_model(
			&"ProjectileModel",
			AABB(
				Vector3(-width * 0.5, -width * 0.5, -length * 0.5),
				Vector3(width, width, length)
			)
		)
		if custom_visual != null:
			add_child(custom_visual)
			return
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _update_orientation(direction: Vector3) -> void:
	if direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return
	look_at(global_position + direction, Vector3.UP)
