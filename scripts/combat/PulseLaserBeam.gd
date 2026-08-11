## One instantaneous pulse-laser path with independent reflected segments.
## The path is frozen at launch. Damage is applied exactly once when fade-in
## enters the hold phase, while each reflected segment owns its own hit pass.
class_name PulseLaserBeam
extends Node3D

signal impacted(target: CombatTarget, applied_damage: float, segment_index: int)

const MIN_SEGMENT_LENGTH := 0.0001
const MIN_VISUAL_FACTOR := 0.0001

var _combat_manager: CombatManager
var _source_building: Building
var _damage: float = 0.0
var _maximum_width: float = 0.1
var _emission_energy: float = 2.0
var _fade_in_time: float = 0.0
var _hold_time: float = 0.0
var _fade_out_time: float = 0.0
var _elapsed: float = 0.0
var _damage_applied: bool = false
var _visual_factor: float = 0.0
var _reflection_resolver: Callable
var _blocker_resolver: Callable
var _segments: Array[Dictionary] = []


func configure(
	combat_manager: CombatManager,
	source_building: Building,
	start: Vector3,
	direction: Vector3,
	damage: float,
	maximum_distance: float,
	maximum_width: float,
	emission_energy: float,
	fade_in_time: float,
	hold_time: float,
	fade_out_time: float,
	colors: Array[Color],
	maximum_reflections: int,
	reflection_resolver: Callable = Callable(),
	blocker_resolver: Callable = Callable()
) -> bool:
	if direction.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
		return false
	if maximum_distance <= MIN_SEGMENT_LENGTH or colors.is_empty():
		return false
	_combat_manager = combat_manager
	_source_building = source_building
	_damage = maxf(0.0, damage)
	_maximum_width = maxf(MIN_VISUAL_FACTOR, maximum_width)
	_emission_energy = maxf(0.0, emission_energy)
	_fade_in_time = maxf(0.0, fade_in_time)
	_hold_time = maxf(0.0, hold_time)
	_fade_out_time = maxf(0.0, fade_out_time)
	_reflection_resolver = reflection_resolver
	_blocker_resolver = blocker_resolver
	global_transform = Transform3D.IDENTITY
	_trace_path(start, direction.normalized(), maximum_distance, colors, maxi(0, maximum_reflections))
	if _segments.is_empty():
		return false
	_build_visuals()
	_apply_visual_factor(0.0 if _fade_in_time > 0.0 else 1.0)
	set_process(true)
	return true


func _process(delta: float) -> void:
	var previous_elapsed := _elapsed
	_elapsed += maxf(0.0, delta)
	if not _damage_applied and previous_elapsed < _fade_in_time and _elapsed >= _fade_in_time:
		_apply_damage_once()
	elif not _damage_applied and _fade_in_time <= 0.0:
		_apply_damage_once()
	var hold_end := _fade_in_time + _hold_time
	var total_duration := hold_end + _fade_out_time
	var visual_factor := 1.0
	if _elapsed < _fade_in_time:
		visual_factor = _elapsed / _fade_in_time if _fade_in_time > 0.0 else 1.0
	elif _elapsed > hold_end:
		visual_factor = (
			1.0 - (_elapsed - hold_end) / _fade_out_time
			if _fade_out_time > 0.0
			else 0.0
		)
	_apply_visual_factor(clampf(visual_factor, 0.0, 1.0))
	if _elapsed >= total_duration:
		queue_free()


func debug_get_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for segment in _segments:
		var copy := segment.duplicate()
		copy.erase("visual")
		copy.erase("material")
		result.append(copy)
	return result


func has_applied_damage() -> bool:
	return _damage_applied


func debug_get_visual_factor() -> float:
	return _visual_factor


func _trace_path(
	start: Vector3,
	direction_value: Vector3,
	maximum_distance: float,
	colors: Array[Color],
	maximum_reflections: int
) -> void:
	var current_start := start
	var direction := direction_value
	var remaining_distance := maximum_distance
	var reflection_count := 0
	while remaining_distance > MIN_SEGMENT_LENGTH:
		var candidate_end := current_start + direction * remaining_distance
		var reflection_hit := _query_reflection(current_start, candidate_end)
		var blocker_hit := _query_blocker(current_start, candidate_end)
		var reflection_distance := _valid_hit_distance(reflection_hit, remaining_distance)
		var blocker_distance := _valid_hit_distance(blocker_hit, remaining_distance)
		var blocker_is_first := blocker_distance <= reflection_distance
		var nearest_hit_distance := minf(reflection_distance, blocker_distance)
		var segment_distance := (
			nearest_hit_distance if is_finite(nearest_hit_distance) else remaining_distance
		)
		var segment_end := current_start + direction * segment_distance
		_append_segment(
			current_start,
			segment_end,
			colors[reflection_count % colors.size()],
			reflection_count,
			blocker_is_first and is_finite(blocker_distance)
		)
		remaining_distance = maxf(0.0, remaining_distance - segment_distance)
		if blocker_is_first and is_finite(blocker_distance):
			break
		if not is_finite(reflection_distance) or reflection_count >= maximum_reflections:
			break
		var raw_normal: Variant = reflection_hit.get("normal", Vector3.ZERO)
		if not raw_normal is Vector3:
			break
		var normal: Vector3 = raw_normal
		if normal.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
			break
		normal = normal.normalized()
		direction = (direction - 2.0 * direction.dot(normal) * normal).normalized()
		reflection_count += 1
		var epsilon := minf(
			maxf(MIN_SEGMENT_LENGTH, float(reflection_hit.get("epsilon", MIN_SEGMENT_LENGTH))),
			remaining_distance
		)
		current_start = segment_end + direction * epsilon
		remaining_distance = maxf(0.0, remaining_distance - epsilon)


func _append_segment(
	start: Vector3,
	end: Vector3,
	color: Color,
	reflection_index: int,
	blocked: bool
) -> void:
	var length := start.distance_to(end)
	if length <= MIN_SEGMENT_LENGTH:
		return
	_segments.append({
		"start": start,
		"end": end,
		"length": length,
		"color": color,
		"reflection_index": reflection_index,
		"blocked": blocked,
	})


func _build_visuals() -> void:
	for index in range(_segments.size()):
		var segment: Dictionary = _segments[index]
		var start: Vector3 = segment.get("start", Vector3.ZERO)
		var end: Vector3 = segment.get("end", Vector3.ZERO)
		var color: Color = segment.get("color", Color.WHITE)
		var visual := MeshInstance3D.new()
		visual.name = "PulseLaserSegment%d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(_maximum_width, _maximum_width, start.distance_to(end))
		visual.mesh = mesh
		add_child(visual)
		visual.position = (start + end) * 0.5
		visual.look_at(end, Vector3.UP)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = _emission_energy
		visual.material_override = material
		segment["visual"] = visual
		segment["material"] = material
		_segments[index] = segment


func _apply_visual_factor(factor: float) -> void:
	var resolved := clampf(factor, 0.0, 1.0)
	_visual_factor = resolved
	for segment in _segments:
		var visual: MeshInstance3D = segment.get("visual") as MeshInstance3D
		var material: StandardMaterial3D = segment.get("material") as StandardMaterial3D
		if visual != null:
			visual.visible = resolved > 0.0
			var width_factor := maxf(MIN_VISUAL_FACTOR, resolved)
			visual.scale = Vector3(width_factor, width_factor, 1.0)
		if material != null:
			var color: Color = segment.get("color", Color.WHITE)
			color.a *= resolved
			material.albedo_color = color
			material.emission = color
			material.emission_energy_multiplier = _emission_energy * resolved


func _apply_damage_once() -> void:
	if _damage_applied:
		return
	_damage_applied = true
	if _combat_manager == null or _damage <= 0.0:
		return
	for segment_index in range(_segments.size()):
		var segment: Dictionary = _segments[segment_index]
		var start: Vector3 = segment.get("start", Vector3.ZERO)
		var end: Vector3 = segment.get("end", Vector3.ZERO)
		var include_end_caps := not bool(segment.get("blocked", false))
		for target in _combat_manager.get_targets_on_segment(start, end, include_end_caps):
			if _source_building != null and is_instance_valid(_source_building):
				if not _source_building.affects_target(target):
					continue
			var applied := target.take_damage(_damage)
			impacted.emit(target, applied, segment_index)


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


func _valid_hit_distance(hit: Dictionary, maximum_distance: float) -> float:
	if not bool(hit.get("hit", false)):
		return INF
	var distance := float(hit.get("distance", INF))
	if not is_finite(distance) or distance <= MIN_SEGMENT_LENGTH or distance > maximum_distance + MIN_SEGMENT_LENGTH:
		return INF
	return clampf(distance, 0.0, maximum_distance)
