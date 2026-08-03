## ModelFitTransform -- pure transform math for authored visual bounds.
class_name ModelFitTransform
extends RefCounted

enum VerticalAlignment {
	MINIMUM,
	CENTER,
	MAXIMUM,
}


static func exact(source: AABB, target: AABB) -> Transform3D:
	var fit_scale := Vector3(
		target.size.x / source.size.x,
		target.size.y / source.size.y,
		target.size.z / source.size.z
	)
	var fit_position := target.position - source.position * fit_scale
	return Transform3D(Basis.from_scale(fit_scale), fit_position)


## Fits the authored X/Z footprint with one uniform scale. Y uses the same
## scale and is only aligned, never independently compressed or stretched.
static func proportional(
	source: AABB,
	target: AABB,
	vertical_alignment: int
) -> Transform3D:
	var fit_scale_value := minf(
		target.size.x / source.size.x,
		target.size.z / source.size.z
	)
	var fit_scale := Vector3.ONE * fit_scale_value
	var source_center := source.get_center()
	var target_center := target.get_center()
	var fit_position := Vector3(
		target_center.x - source_center.x * fit_scale_value,
		0.0,
		target_center.z - source_center.z * fit_scale_value
	)
	match vertical_alignment:
		VerticalAlignment.MINIMUM:
			fit_position.y = target.position.y - source.position.y * fit_scale_value
		VerticalAlignment.MAXIMUM:
			fit_position.y = target.end.y - source.end.y * fit_scale_value
		_:
			fit_position.y = target_center.y - source_center.y * fit_scale_value
	return Transform3D(Basis.from_scale(fit_scale), fit_position)
