## Fixed-end copy projectile until its first reflection, then a straight
## ballistic projectile. It never acquires an independent homing target.
class_name MirrorProjectionProjectile
extends Node3D

signal impacted(target: CombatTarget, applied_damage: float)
signal reflected(mirror: CopyMirror, world_position: Vector3, direction: Vector3)

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001

var _combat_manager: CombatManager
var _source_building: Building
var _end: Vector3
var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 1.0
var _damage: float = 0.0
var _maximum_distance: float = 1.0
var _distance_traveled: float = 0.0
var _reflection_resolver: Callable
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
	ballistic_from_start: bool = false
) -> void:
	_combat_manager = combat_manager
	_source_building = source_building
	global_position = start
	_end = end
	_direction = (end - start).normalized()
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, start.distance_to(end) if maximum_distance < 0.0 else maximum_distance)
	_reflection_resolver = reflection_resolver
	_ballistic_from_start = ballistic_from_start
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
		var start := global_position
		var end := start + _direction * remaining
		var mirror_hit := _query_reflection(start, end)
		var segment_distance := (
			clampf(float(mirror_hit.get("distance", remaining)), 0.0, remaining)
			if bool(mirror_hit.get("hit", false))
			else remaining
		)
		var segment_end := start + _direction * segment_distance
		if _has_reflected or _ballistic_from_start:
			var target_hit := _find_first_target_hit(start, segment_end)
			if bool(target_hit.get("hit", false)):
				var target_distance := clampf(float(target_hit.get("distance", 0.0)), 0.0, segment_distance)
				global_position = start + _direction * target_distance
				_distance_traveled += target_distance
				_impact_target(target_hit.get("target") as CombatTarget)
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


func _query_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_resolver.is_valid():
		return {"hit": false}
	var result: Variant = _reflection_resolver.call(start, end)
	return result if result is Dictionary else {"hit": false}


func _find_first_target_hit(start: Vector3, end: Vector3) -> Dictionary:
	var best: CombatTarget
	var best_distance := INF
	if (
		_combat_manager == null
		or _source_building == null
		or not is_instance_valid(_source_building)
	):
		return {"hit": false}
	for target in _combat_manager.get_targets():
		if not target.is_alive() or not _source_building.affects_target(target):
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
	return {
		"hit": best != null,
		"target": best,
		"distance": best_distance if best != null else 0.0,
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
	_impact_target(_find_target_at_endpoint())


func _impact_target(target: CombatTarget) -> void:
	_active = false
	var applied_damage := 0.0
	if target != null and is_instance_valid(target) and target.is_alive():
		applied_damage = target.take_damage(_damage)
		impacted.emit(target, applied_damage)
	queue_free()


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
