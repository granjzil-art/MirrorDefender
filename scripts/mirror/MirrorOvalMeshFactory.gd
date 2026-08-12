## Procedural oval meshes shared by the copy mirror body and reflection face.
extends RefCounted

const DEFAULT_SEGMENTS: int = 48


static func create_prism(size: Vector3, segment_count: int = DEFAULT_SEGMENTS) -> ArrayMesh:
	var segments := maxi(12, segment_count)
	var radius_x := maxf(0.005, size.x * 0.5)
	var radius_y := maxf(0.005, size.y * 0.5)
	var half_depth := maxf(0.001, size.z * 0.5)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var current_ratio := float(index) / float(segments)
		var next_ratio := float(index + 1) / float(segments)
		var current_angle := TAU * current_ratio
		var next_angle := TAU * next_ratio
		var current_xy := Vector2(cos(current_angle) * radius_x, sin(current_angle) * radius_y)
		var next_xy := Vector2(cos(next_angle) * radius_x, sin(next_angle) * radius_y)
		var current_uv := Vector2(
			0.5 + current_xy.x / (radius_x * 2.0),
			0.5 - current_xy.y / (radius_y * 2.0)
		)
		var next_uv := Vector2(
			0.5 + next_xy.x / (radius_x * 2.0),
			0.5 - next_xy.y / (radius_y * 2.0)
		)
		# Godot treats clockwise triangles as front-facing.
		_add_vertex(surface, Vector3(0.0, 0.0, half_depth), Vector3.BACK, Vector2(0.5, 0.5))
		_add_vertex(surface, Vector3(next_xy.x, next_xy.y, half_depth), Vector3.BACK, next_uv)
		_add_vertex(surface, Vector3(current_xy.x, current_xy.y, half_depth), Vector3.BACK, current_uv)
		_add_vertex(surface, Vector3(0.0, 0.0, -half_depth), Vector3.FORWARD, Vector2(0.5, 0.5))
		_add_vertex(surface, Vector3(current_xy.x, current_xy.y, -half_depth), Vector3.FORWARD, current_uv)
		_add_vertex(surface, Vector3(next_xy.x, next_xy.y, -half_depth), Vector3.FORWARD, next_uv)
		var current_normal := Vector3(
			cos(current_angle) / radius_x,
			sin(current_angle) / radius_y,
			0.0
		).normalized()
		var next_normal := Vector3(
			cos(next_angle) / radius_x,
			sin(next_angle) / radius_y,
			0.0
		).normalized()
		var current_front := Vector3(current_xy.x, current_xy.y, half_depth)
		var next_front := Vector3(next_xy.x, next_xy.y, half_depth)
		var current_back := Vector3(current_xy.x, current_xy.y, -half_depth)
		var next_back := Vector3(next_xy.x, next_xy.y, -half_depth)
		_add_vertex(surface, current_front, current_normal, Vector2(current_ratio, 0.0))
		_add_vertex(surface, next_front, next_normal, Vector2(next_ratio, 0.0))
		_add_vertex(surface, current_back, current_normal, Vector2(current_ratio, 1.0))
		_add_vertex(surface, next_front, next_normal, Vector2(next_ratio, 0.0))
		_add_vertex(surface, next_back, next_normal, Vector2(next_ratio, 1.0))
		_add_vertex(surface, current_back, current_normal, Vector2(current_ratio, 1.0))
	return surface.commit()


static func create_face(size: Vector2, segment_count: int = DEFAULT_SEGMENTS) -> ArrayMesh:
	var segments := maxi(12, segment_count)
	var radius := Vector2(maxf(0.005, size.x * 0.5), maxf(0.005, size.y * 0.5))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var current_angle := TAU * float(index) / float(segments)
		var next_angle := TAU * float(index + 1) / float(segments)
		var current := Vector2(cos(current_angle) * radius.x, sin(current_angle) * radius.y)
		var next := Vector2(cos(next_angle) * radius.x, sin(next_angle) * radius.y)
		_add_vertex(surface, Vector3.ZERO, Vector3.BACK, Vector2(0.5, 0.5))
		_add_vertex(
			surface,
			Vector3(next.x, next.y, 0.0),
			Vector3.BACK,
			Vector2(0.5 + next.x / (radius.x * 2.0), 0.5 - next.y / (radius.y * 2.0))
		)
		_add_vertex(
			surface,
			Vector3(current.x, current.y, 0.0),
			Vector3.BACK,
			Vector2(0.5 + current.x / (radius.x * 2.0), 0.5 - current.y / (radius.y * 2.0))
		)
	return surface.commit()


static func _add_vertex(
	surface: SurfaceTool,
	position: Vector3,
	normal: Vector3,
	uv: Vector2
) -> void:
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(position)
