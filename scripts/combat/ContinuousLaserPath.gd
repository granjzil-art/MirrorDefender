## Deterministic reflected path query for the continuous laser tower.
##
## One attack-range budget is shared by every reflected segment. Live Stuff
## always wins ties, while projectile_penetration_count follows the standard
## projectile contract: N extra enemies may be crossed before the next enemy
## receives the hit and terminates the beam.
class_name ContinuousLaserPath
extends RefCounted

const MIN_SEGMENT_LENGTH := 0.0001


static func trace(
	combat_manager: CombatManager,
	source_building: Node,
	start: Vector3,
	direction_value: Vector3,
	maximum_distance: float,
	penetration_count: int,
	reflection_resolver: Callable = Callable(),
	blocker_resolver: Callable = Callable(),
	attack_effects: AttackEffectPayload = null,
	initial_damage_multiplier: float = 1.0,
	initial_reflection_index: int = 0,
	attack_kind: StringName = &"continuous_laser"
) -> Dictionary:
	var resolved_effects := attack_effects if attack_effects != null else AttackEffectPayload.new()
	var segments: Array[Dictionary] = []
	var hits: Array[Dictionary] = []
	var reflections: Array[Dictionary] = []
	var result := {
		"segments": segments,
		"hits": hits,
		"reflections": reflections,
		"endpoint": start,
		"termination": &"none",
		"damage_multiplier": maxf(0.0, initial_damage_multiplier),
		"penetration_limit": maxi(0, penetration_count),
		"main_length": 0.0,
	}
	if (
		combat_manager == null
		or direction_value.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH
		or maximum_distance <= MIN_SEGMENT_LENGTH
	):
		return result
	var current_start := start
	var direction := direction_value.normalized()
	var remaining_distance := maximum_distance
	var reflection_count := maxi(
		maxi(0, initial_reflection_index),
		resolved_effects.get_total_reflection_count()
	)
	var hit_count := 0
	var previous_reflector: CombatTarget
	var resolved_penetration_count := maxi(0, penetration_count)
	while remaining_distance > MIN_SEGMENT_LENGTH:
		var candidate_end := current_start + direction * remaining_distance
		var reflection_hit := _query(reflection_resolver, current_start, candidate_end)
		var blocker_hit := _query(blocker_resolver, current_start, candidate_end)
		var reflection_distance := _valid_hit_distance(reflection_hit, remaining_distance)
		var blocker_distance := _valid_hit_distance(blocker_hit, remaining_distance)
		var blocker_is_first := blocker_distance <= reflection_distance
		var nearest_interaction := minf(reflection_distance, blocker_distance)
		var segment_distance := (
			nearest_interaction if is_finite(nearest_interaction) else remaining_distance
		)
		var interaction_end := current_start + direction * segment_distance
		var terminal_reflector := (
			reflection_hit.get("reflector") as CombatTarget
			if not blocker_is_first and is_finite(reflection_distance)
			else null
		)
		var excluded_targets: Array[CombatTarget] = []
		if previous_reflector != null and is_instance_valid(previous_reflector):
			excluded_targets.append(previous_reflector)
		if terminal_reflector != null and not excluded_targets.has(terminal_reflector):
			excluded_targets.append(terminal_reflector)
		var target_hits := _get_sorted_target_hits(
			combat_manager,
			source_building,
			current_start,
			interaction_end,
			excluded_targets
		)
		var stopped_by_target := false
		for target_hit in target_hits:
			var entry_distance := float(target_hit.get("distance", INF))
			var center_distance := float(target_hit.get("center_distance", INF))
			if not is_finite(entry_distance):
				continue
			if is_finite(nearest_interaction):
				if entry_distance >= segment_distance - MIN_SEGMENT_LENGTH:
					continue
				if blocker_is_first and center_distance >= blocker_distance - MIN_SEGMENT_LENGTH:
					continue
			hit_count += 1
			target_hit["segment_index"] = segments.size()
			hits.append(target_hit)
			if hit_count > resolved_penetration_count:
				segment_distance = clampf(entry_distance, 0.0, segment_distance)
				interaction_end = current_start + direction * segment_distance
				stopped_by_target = true
				break
		_append_segment(
			segments,
			current_start,
			interaction_end,
			reflection_count,
			stopped_by_target or blocker_is_first and is_finite(blocker_distance),
			resolved_effects.get_laser_visual_modifiers(
				{"attack_kind": attack_kind, "source_building": source_building}
			)
		)
		result["main_length"] = float(result["main_length"]) + current_start.distance_to(interaction_end)
		result["endpoint"] = interaction_end
		remaining_distance = maxf(0.0, remaining_distance - segment_distance)
		if stopped_by_target:
			result["termination"] = &"enemy"
			break
		if blocker_is_first and is_finite(blocker_distance):
			result["termination"] = &"stuff"
			break
		if not is_finite(reflection_distance):
			result["termination"] = &"range"
			break
		var raw_normal: Variant = reflection_hit.get("normal", Vector3.ZERO)
		if not raw_normal is Vector3:
			result["termination"] = &"invalid_reflection"
			break
		var normal: Vector3 = raw_normal
		if normal.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
			result["termination"] = &"invalid_reflection"
			break
		normal = normal.normalized()
		if not resolved_effects.record_successful_reflection(reflection_hit):
			result["termination"] = &"reflection_absorbed"
			break
		var reflection_record := reflection_hit.duplicate()
		reflections.append(reflection_record)
		var reflection_damage_multiplier := float(reflection_hit.get("damage_multiplier", 1.0))
		if is_finite(reflection_damage_multiplier):
			result["damage_multiplier"] = (
				float(result["damage_multiplier"])
				* maxf(0.0, reflection_damage_multiplier)
			)
		resolved_penetration_count += maxi(0, int(reflection_hit.get("penetration_bonus", 0)))
		resolved_penetration_count += resolved_effects.get_reflection_penetration_bonus(
			reflection_hit,
			{
				"attack_kind": attack_kind,
				"source_building": source_building,
			}
		)
		result["penetration_limit"] = resolved_penetration_count
		resolved_effects.apply_reflection_effects(
			reflection_hit,
			{"attack_kind": attack_kind, "source_building": source_building}
		)
		direction = (direction - 2.0 * direction.dot(normal) * normal).normalized()
		reflection_count += 1
		previous_reflector = terminal_reflector
		var epsilon := minf(
			maxf(MIN_SEGMENT_LENGTH, float(reflection_hit.get("epsilon", MIN_SEGMENT_LENGTH))),
			remaining_distance
		)
		current_start = interaction_end + direction * epsilon
		remaining_distance = maxf(0.0, remaining_distance - epsilon)
		result["endpoint"] = current_start
		var branch_angles := resolved_effects.get_reflection_branch_angles(
			reflection_hit,
			{
				"attack_kind": attack_kind,
				"source_building": source_building,
				"direction": direction,
				"remaining_distance": remaining_distance,
			}
		)
		var granted_branches := resolved_effects.request_reflection_branch_slots(branch_angles.size())
		for branch_index in range(granted_branches):
			var branch_path := trace(
				combat_manager,
				source_building,
				current_start,
				direction.rotated(
					Vector3.UP,
					deg_to_rad(branch_angles[branch_index])
				).normalized(),
				remaining_distance,
				maxi(0, resolved_penetration_count - hit_count),
				reflection_resolver,
				blocker_resolver,
				resolved_effects.duplicate_for_reflection_branch(),
				float(result["damage_multiplier"]),
				reflection_count,
				attack_kind
			)
			_merge_branch_path(result, branch_path)
	for hit_index in range(hits.size()):
		var resolved_hit: Dictionary = hits[hit_index]
		if not resolved_hit.has("damage_multiplier"):
			resolved_hit["damage_multiplier"] = float(result["damage_multiplier"])
		hits[hit_index] = resolved_hit
	for reflection_index in range(reflections.size()):
		var resolved_reflection: Dictionary = reflections[reflection_index]
		if not resolved_reflection.has("path_damage_multiplier"):
			resolved_reflection["path_damage_multiplier"] = float(result["damage_multiplier"])
		reflections[reflection_index] = resolved_reflection
	return result


static func _merge_branch_path(result: Dictionary, branch_path: Dictionary) -> void:
	var segments: Array = result.get("segments", [])
	var segment_offset := segments.size()
	for raw_segment in branch_path.get("segments", []):
		if raw_segment is Dictionary:
			var segment := (raw_segment as Dictionary).duplicate(true)
			segment["branch"] = true
			segments.append(segment)
	var hits: Array = result.get("hits", [])
	for raw_hit in branch_path.get("hits", []):
		if raw_hit is Dictionary:
			var hit := (raw_hit as Dictionary).duplicate(true)
			hit["segment_index"] = int(hit.get("segment_index", 0)) + segment_offset
			hits.append(hit)
	var reflections: Array = result.get("reflections", [])
	for raw_reflection in branch_path.get("reflections", []):
		if raw_reflection is Dictionary:
			reflections.append((raw_reflection as Dictionary).duplicate(true))


static func _get_sorted_target_hits(
	combat_manager: CombatManager,
	source_building: Node,
	start: Vector3,
	end: Vector3,
	excluded_targets: Array[CombatTarget] = []
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var segment_start := Vector2(start.x, start.z)
	var segment_end := Vector2(end.x, end.z)
	var segment := segment_end - segment_start
	var segment_length := segment.length()
	if segment_length <= MIN_SEGMENT_LENGTH:
		return result
	var direction := segment / segment_length
	for target in combat_manager.get_targets():
		if target == null or not is_instance_valid(target) or not target.is_alive():
			continue
		if excluded_targets.has(target):
			continue
		if source_building != null and is_instance_valid(source_building):
			if not bool(source_building.call("affects_target", target)):
				continue
		var center := Vector2(target.global_position.x, target.global_position.z)
		var center_distance := (center - segment_start).dot(direction)
		var allowed_radius := maxf(0.0, target.hit_radius + combat_manager.laser_hit_radius)
		var entry_distance := _ray_circle_entry_distance(
			segment_start,
			segment_end,
			center,
			allowed_radius
		)
		if entry_distance < 0.0:
			continue
		result.append({
			"target": target,
			"distance": entry_distance,
			"center_distance": center_distance,
			"entry_position": start + (end - start).normalized() * entry_distance,
		})
	result.sort_custom(_target_hit_precedes)
	return result


static func _target_hit_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_distance := float(left.get("distance", INF))
	var right_distance := float(right.get("distance", INF))
	if not is_equal_approx(left_distance, right_distance):
		return left_distance < right_distance
	var left_target := left.get("target") as CombatTarget
	var right_target := right.get("target") as CombatTarget
	var left_order := left_target.entry_order if left_target != null else 2147483647
	var right_order := right_target.entry_order if right_target != null else 2147483647
	return left_order < right_order


static func _ray_circle_entry_distance(
	start: Vector2,
	end: Vector2,
	center: Vector2,
	radius: float
) -> float:
	var segment := end - start
	var length := segment.length()
	var radius_squared := radius * radius
	if length <= MIN_SEGMENT_LENGTH:
		return 0.0 if start.distance_squared_to(center) <= radius_squared else -1.0
	var direction := segment / length
	var to_center := center - start
	var projected := to_center.dot(direction)
	var closest_squared := to_center.length_squared() - projected * projected
	if closest_squared > radius_squared:
		return -1.0
	var half_chord := sqrt(maxf(0.0, radius_squared - closest_squared))
	var entry := projected - half_chord
	if entry < 0.0:
		entry = 0.0 if start.distance_squared_to(center) <= radius_squared else projected + half_chord
	return entry if entry >= 0.0 and entry <= length else -1.0


static func _append_segment(
	segments: Array[Dictionary],
	start: Vector3,
	end: Vector3,
	reflection_index: int,
	blocked: bool,
	laser_visual_modifiers: Dictionary = {}
) -> void:
	var length := start.distance_to(end)
	if length <= MIN_SEGMENT_LENGTH:
		return
	segments.append({
		"start": start,
		"end": end,
		"length": length,
		"reflection_index": reflection_index,
		"blocked": blocked,
		"laser_visual_modifiers": laser_visual_modifiers.duplicate(true),
	})


static func _query(resolver: Callable, start: Vector3, end: Vector3) -> Dictionary:
	if not resolver.is_valid():
		return {"hit": false}
	var result: Variant = resolver.call(start, end)
	return result if result is Dictionary else {"hit": false}


static func _valid_hit_distance(hit: Dictionary, maximum_distance: float) -> float:
	if not bool(hit.get("hit", false)):
		return INF
	var distance := float(hit.get("distance", INF))
	if (
		not is_finite(distance)
		or distance <= MIN_SEGMENT_LENGTH
		or distance > maximum_distance + MIN_SEGMENT_LENGTH
	):
		return INF
	return clampf(distance, 0.0, maximum_distance)
