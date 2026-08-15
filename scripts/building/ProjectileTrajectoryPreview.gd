## Read-only world-space preview of a Building's planned projectile or laser path.
## Reflection queries are injected so combat remains the only gameplay owner.
class_name ProjectileTrajectoryPreview
extends Node3D

const MIN_SEGMENT_LENGTH := 0.0001

var _feature_enabled: bool = true
var _color: Color = Color(1.0, 0.05, 0.05, 0.52)
var _width: float = 0.10
var _lift: float = 0.04
var _max_segments_per_direction: int = 32
var _multiplier_label_color: Color = Color(1.0, 0.05, 0.05, 1.0)
var _multiplier_label_height: float = 0.18
var _multiplier_label_stack_spacing: float = 0.22
var _reflection_resolver: Callable
var _blocker_resolver: Callable
var _segments: Array[Dictionary] = []
var _multiplier_label_data: Array[Dictionary] = []
var _multiplier_labels: Array[Label3D] = []
var _multiplier_label_unique: Dictionary = {}
var _multiplier_label_group_counts: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_ensure_visual()


func configure_style(
	feature_enabled: bool,
	color: Color,
	width: float,
	lift: float,
	max_segments_per_direction: int,
	multiplier_label_color: Color = Color(1.0, 0.05, 0.05, 1.0),
	multiplier_label_height: float = 0.18,
	multiplier_label_stack_spacing: float = 0.22
) -> void:
	_feature_enabled = feature_enabled
	_color = color
	_width = maxf(0.001, width)
	_lift = maxf(0.0, lift)
	_max_segments_per_direction = maxi(1, max_segments_per_direction)
	_multiplier_label_color = multiplier_label_color
	_multiplier_label_height = maxf(0.0, multiplier_label_height)
	_multiplier_label_stack_spacing = maxf(0.0, multiplier_label_stack_spacing)
	_ensure_visual()
	_update_material()


func set_reflection_resolver(value: Callable) -> void:
	_reflection_resolver = value


func set_blocker_resolver(value: Callable) -> void:
	_blocker_resolver = value


func rebuild(
	building: Building,
	projection_payloads: Array[MirrorCopyPayload] = [],
	show_multiplier_labels: bool = true
) -> void:
	clear()
	if (
		not _feature_enabled
		or building == null
		or not is_instance_valid(building)
		or building.get_level_stats() == null
	):
		return
	var directions := building.get_projectile_launch_directions()
	var maximum_distance := building.get_attack_range_world()
	if directions.is_empty() or maximum_distance <= MIN_SEGMENT_LENGTH:
		return
	var origin := building.get_attack_origin()
	_append_source_trajectories(
		origin,
		directions,
		maximum_distance,
		0,
		null,
		show_multiplier_labels
	)
	var source_index := 1
	for payload in projection_payloads:
		if payload == null or not payload.is_source_valid() or payload.root_source != building:
			continue
		var projected_directions: Array[Vector3] = []
		for direction in directions:
			projected_directions.append(payload.transform_direction(direction).normalized())
		if show_multiplier_labels:
			_queue_multiplier_label(
				&"copy",
				"copy-cell:%s" % str(payload.projected_cell),
				"copy:%s" % payload.stable_key,
				payload.transform_point(building.get_action_anchor()),
				payload.damage_multiplier
			)
		_append_source_trajectories(
			payload.transform_point(origin),
			projected_directions,
			maximum_distance,
			source_index,
			payload,
			show_multiplier_labels
		)
		source_index += 1
	_rebuild_mesh(_width)
	_rebuild_multiplier_labels()


func _append_source_trajectories(
	origin: Vector3,
	directions: Array[Vector3],
	maximum_distance: float,
	source_index: int,
	payload: MirrorCopyPayload,
	show_multiplier_labels: bool
) -> void:
	for direction_index in range(directions.size()):
		_trace_direction(
			origin,
			directions[direction_index],
			maximum_distance,
			direction_index,
			source_index,
			payload,
			show_multiplier_labels
		)


func clear() -> void:
	_segments.clear()
	_multiplier_label_data.clear()
	_multiplier_label_unique.clear()
	_multiplier_label_group_counts.clear()
	for label in _multiplier_labels:
		if label != null and is_instance_valid(label):
			label.free()
	_multiplier_labels.clear()
	_ensure_visual()
	_mesh_instance.mesh = null
	_mesh_instance.visible = false


func has_visual() -> bool:
	return _mesh_instance != null and _mesh_instance.visible and not _segments.is_empty()


func debug_get_segments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for segment in _segments:
		result.append(segment.duplicate(true))
	return result


func debug_get_visual_width() -> float:
	return _width


func debug_get_multiplier_labels() -> Array[Dictionary]:
	return _multiplier_label_data.duplicate(true)


func _trace_direction(
	origin: Vector3,
	direction_value: Vector3,
	maximum_distance: float,
	direction_index: int,
	source_index: int,
	payload: MirrorCopyPayload,
	show_multiplier_labels: bool
) -> void:
	if direction_value.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
		return
	var current_start := origin
	var direction := direction_value.normalized()
	var remaining_distance := maximum_distance
	var reflection_index := 0
	var cumulative_multiplier := payload.damage_multiplier if payload != null else 1.0
	for _segment_index in range(_max_segments_per_direction):
		if remaining_distance <= MIN_SEGMENT_LENGTH:
			break
		var candidate_end := current_start + direction * remaining_distance
		var hit := _query_reflection(current_start, candidate_end)
		var blocker_hit := _query_blocker(current_start, candidate_end)
		var reflection_distance := _valid_hit_distance(hit, remaining_distance)
		var blocker_distance := _valid_hit_distance(blocker_hit, remaining_distance)
		if blocker_distance <= reflection_distance and is_finite(blocker_distance):
			var blocker_end := current_start + direction * blocker_distance
			_append_segment(
				current_start,
				blocker_end,
				direction_index,
				reflection_index,
				source_index,
				payload,
				true
			)
			break
		if not is_finite(reflection_distance):
			_append_segment(
				current_start,
				candidate_end,
				direction_index,
				reflection_index,
				source_index,
				payload
			)
			break
		var raw_hit_position: Variant = hit.get("position", candidate_end)
		if not raw_hit_position is Vector3:
			_append_segment(
				current_start,
				candidate_end,
				direction_index,
				reflection_index,
				source_index,
				payload
			)
			break
		var hit_position: Vector3 = raw_hit_position
		var hit_distance := current_start.distance_to(hit_position)
		if (
			not is_finite(hit_distance)
			or hit_distance <= MIN_SEGMENT_LENGTH
			or hit_distance > remaining_distance + MIN_SEGMENT_LENGTH
		):
			break
		_append_segment(
			current_start,
			hit_position,
			direction_index,
			reflection_index,
			source_index,
			payload
		)
		remaining_distance = maxf(0.0, remaining_distance - hit_distance)
		var raw_normal: Variant = hit.get("normal", Vector3.ZERO)
		if not raw_normal is Vector3:
			break
		var normal: Vector3 = raw_normal
		if normal.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
			break
		normal = normal.normalized()
		var hit_multiplier := float(hit.get("damage_multiplier", 1.0))
		if is_finite(hit_multiplier):
			cumulative_multiplier *= maxf(0.0, hit_multiplier)
		if show_multiplier_labels:
			var mirror := hit.get("mirror") as CopyMirror
			if mirror != null and is_instance_valid(mirror) and mirror.is_projectile_reflector():
				var formatted_multiplier := _format_multiplier(cumulative_multiplier)
				_queue_multiplier_label(
					&"reflection",
					"reflect:%d" % mirror.get_instance_id(),
					"reflect:%d:%s" % [mirror.get_instance_id(), formatted_multiplier],
					mirror.get_action_anchor(),
					cumulative_multiplier
				)
		direction = (direction - 2.0 * direction.dot(normal) * normal).normalized()
		reflection_index += 1
		var epsilon := minf(
			maxf(MIN_SEGMENT_LENGTH, float(hit.get("epsilon", MIN_SEGMENT_LENGTH))),
			remaining_distance
		)
		current_start = hit_position + direction * epsilon
		remaining_distance = maxf(0.0, remaining_distance - epsilon)


func _queue_multiplier_label(
	kind: StringName,
	group_key: String,
	unique_key: String,
	world_position: Vector3,
	multiplier: float
) -> void:
	if _multiplier_label_unique.has(unique_key) or not is_finite(multiplier):
		return
	_multiplier_label_unique[unique_key] = true
	var stack_index := int(_multiplier_label_group_counts.get(group_key, 0))
	_multiplier_label_group_counts[group_key] = stack_index + 1
	_multiplier_label_data.append({
		"kind": kind,
		"text": _format_multiplier(multiplier),
		"multiplier": multiplier,
		"position": world_position + Vector3.UP * (
			_multiplier_label_height + float(stack_index) * _multiplier_label_stack_spacing
		),
		"stack_index": stack_index,
	})


func _rebuild_multiplier_labels() -> void:
	for data in _multiplier_label_data:
		var label := Label3D.new()
		label.name = &"TrajectoryMultiplierLabel"
		label.text = String(data.get("text", ""))
		label.position = to_local(data.get("position", Vector3.ZERO))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		# Match the contextual upgrade-cost number used by building and mirror UI.
		label.font_size = 18
		label.outline_size = 3
		label.modulate = _multiplier_label_color
		label.outline_modulate = Color(0.12, 0.0, 0.0, 0.95)
		label.render_priority = 12
		add_child(label)
		_multiplier_labels.append(label)


func _format_multiplier(value: float) -> String:
	var formatted := "%.2f" % maxf(0.0, value)
	while formatted.ends_with("0"):
		formatted = formatted.left(formatted.length() - 1)
	if formatted.ends_with("."):
		formatted = formatted.left(formatted.length() - 1)
	return formatted


func _query_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_resolver.is_valid():
		return {"hit": false}
	var raw_result: Variant = _reflection_resolver.call(start, end)
	return raw_result if raw_result is Dictionary else {"hit": false}


func _query_blocker(start: Vector3, end: Vector3) -> Dictionary:
	if not _blocker_resolver.is_valid():
		return {"hit": false}
	var raw_result: Variant = _blocker_resolver.call(start, end)
	return raw_result if raw_result is Dictionary else {"hit": false}


func _valid_hit_distance(hit: Dictionary, maximum_distance: float) -> float:
	if not bool(hit.get("hit", false)):
		return INF
	var distance := float(hit.get("distance", INF))
	if not is_finite(distance) or distance < 0.0 or distance > maximum_distance + MIN_SEGMENT_LENGTH:
		return INF
	return clampf(distance, 0.0, maximum_distance)


func _append_segment(
	start: Vector3,
	end: Vector3,
	direction_index: int,
	reflection_index: int,
	source_index: int,
	payload: MirrorCopyPayload,
	blocked: bool = false
) -> void:
	var length := start.distance_to(end)
	if length <= MIN_SEGMENT_LENGTH:
		return
	_segments.append({
		"start": start,
		"end": end,
		"length": length,
		"direction_index": direction_index,
		"reflection_index": reflection_index,
		"source_index": source_index,
		"projected": payload != null,
		"projected_cell": payload.projected_cell if payload != null else Vector3i.ZERO,
		"blocked": blocked,
	})


func _rebuild_mesh(width: float) -> void:
	_ensure_visual()
	if _segments.is_empty():
		return
	var mesh := ImmediateMesh.new()
	var visual_offset := Vector3.UP * _lift
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in _segments:
		var world_start: Vector3 = segment.get("start", Vector3.ZERO)
		var world_end: Vector3 = segment.get("end", Vector3.ZERO)
		_add_prism_segment(
			mesh,
			to_local(world_start + visual_offset),
			to_local(world_end + visual_offset),
			width
		)
	mesh.surface_end()
	_mesh_instance.mesh = mesh
	_mesh_instance.visible = true


func _add_prism_segment(
	mesh: ImmediateMesh,
	start: Vector3,
	end: Vector3,
	width: float
) -> void:
	var axis := end - start
	if axis.length_squared() <= MIN_SEGMENT_LENGTH * MIN_SEGMENT_LENGTH:
		return
	var direction := axis.normalized()
	var reference := Vector3.UP
	if absf(direction.dot(reference)) > 0.98:
		reference = Vector3.RIGHT
	var side := direction.cross(reference).normalized()
	var vertical := side.cross(direction).normalized()
	var half_width := maxf(0.001, width * 0.5)
	var side_offset := side * half_width
	var vertical_offset := vertical * half_width
	var start_a := start + side_offset + vertical_offset
	var start_b := start - side_offset + vertical_offset
	var start_c := start - side_offset - vertical_offset
	var start_d := start + side_offset - vertical_offset
	var end_a := end + side_offset + vertical_offset
	var end_b := end - side_offset + vertical_offset
	var end_c := end - side_offset - vertical_offset
	var end_d := end + side_offset - vertical_offset
	_add_quad(mesh, start_a, start_b, start_c, start_d)
	_add_quad(mesh, end_d, end_c, end_b, end_a)
	_add_quad(mesh, start_a, end_a, end_b, start_b)
	_add_quad(mesh, start_b, end_b, end_c, start_c)
	_add_quad(mesh, start_c, end_c, end_d, start_d)
	_add_quad(mesh, start_d, end_d, end_a, start_a)


func _add_quad(
	mesh: ImmediateMesh,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3
) -> void:
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(c)
	mesh.surface_add_vertex(d)


func _ensure_visual() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = &"ProjectileTrajectoryMesh"
	_mesh_instance.visible = false
	add_child(_mesh_instance)
	_update_material()


func _update_material() -> void:
	if _mesh_instance == null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.render_priority = 11
	_material.albedo_color = _color
	_mesh_instance.material_override = _material
