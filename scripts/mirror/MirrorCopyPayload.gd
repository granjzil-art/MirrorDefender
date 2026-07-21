## Stable, composable description of one tile-bound copyable item.
class_name MirrorCopyPayload
extends RefCounted

var stable_key: String = ""
var copy_kind: StringName = &""
var display_name: String = ""
var source_cell: Vector3i = Vector3i.ZERO
var root_source_cell: Vector3i = Vector3i.ZERO
var projected_cell: Vector3i = Vector3i.ZERO
var root_source: Object
var tile_effect: TileEffect
var primary_color: Color = Color.WHITE
var lineage: Array[String] = []
var axes: Array = []
var chain_depth: int = 0

func is_source_valid() -> bool:
	if root_source == null:
		return tile_effect != null
	if not is_instance_valid(root_source):
		return false
	if root_source.has_method("is_structure_alive") and copy_kind in [&"barrier", &"rock"]:
		return bool(root_source.call("is_structure_alive"))
	return not (root_source is Node and root_source.is_queued_for_deletion())

func can_pass_through(mirror_id: String, maximum_depth: int) -> bool:
	return is_source_valid() and chain_depth < maximum_depth and not lineage.has(mirror_id)

func copy_through(
	mirror_id: String,
	target_cell: Vector3i,
	axis_start: Vector3,
	axis_end: Vector3
) -> MirrorCopyPayload:
	var next := MirrorCopyPayload.new()
	next.stable_key = "%s>%s" % [stable_key, mirror_id]
	next.copy_kind = copy_kind
	next.display_name = display_name
	next.source_cell = projected_cell if chain_depth > 0 else source_cell
	next.root_source_cell = root_source_cell
	next.projected_cell = target_cell
	next.root_source = root_source
	next.tile_effect = tile_effect
	next.primary_color = primary_color
	next.lineage = lineage.duplicate()
	next.lineage.append(mirror_id)
	next.axes = axes.duplicate(true)
	next.axes.append([axis_start, axis_end])
	next.chain_depth = chain_depth + 1
	return next

func transform_point(point: Vector3) -> Vector3:
	var transformed := point
	for raw_axis in axes:
		var axis: Array = raw_axis
		if axis.size() == 2:
			transformed = reflect_point_across_line(transformed, axis[0], axis[1])
	return transformed

func get_composed_transform() -> Transform3D:
	var origin := transform_point(Vector3.ZERO)
	var axis_x := transform_point(Vector3.RIGHT) - origin
	var axis_y := transform_point(Vector3.UP) - origin
	var axis_z := transform_point(Vector3.BACK) - origin
	return Transform3D(Basis(axis_x, axis_y, axis_z), origin)

func transform_transform(source_transform: Transform3D) -> Transform3D:
	return get_composed_transform() * source_transform

func transform_direction(direction: Vector3) -> Vector3:
	return transform_point(direction) - transform_point(Vector3.ZERO)

static func reflect_point_across_line(point: Vector3, axis_start: Vector3, axis_end: Vector3) -> Vector3:
	var start := Vector2(axis_start.x, axis_start.z)
	var end := Vector2(axis_end.x, axis_end.z)
	var value := Vector2(point.x, point.z)
	var axis := end - start
	var length_squared := axis.length_squared()
	if length_squared <= 0.000001:
		return point
	var projection := start + axis * ((value - start).dot(axis) / length_squared)
	var reflected := projection * 2.0 - value
	return Vector3(reflected.x, point.y, reflected.y)
