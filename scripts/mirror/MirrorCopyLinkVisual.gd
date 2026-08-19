## Flowing ribbon that connects one direct copy source to its projected result.
class_name MirrorCopyLinkVisual
extends MeshInstance3D

static var _shared_flow_shader: Shader

const FLOW_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 line_color : source_color = vec4(0.12, 0.56, 1.0, 0.72);
uniform float flow_speed = 1.15;
uniform float flow_repeat = 3.0;
uniform float emission_energy = 2.4;

void fragment() {
	float phase = UV.x * flow_repeat - TIME * flow_speed;
	float moving_band = pow(max(0.0, sin(phase * 6.2831853)), 5.0);
	float center = 1.0 - abs(UV.y * 2.0 - 1.0);
	float edge_alpha = smoothstep(0.0, 0.34, center);
	float brightness = 0.72 + moving_band * 0.78;
	ALBEDO = line_color.rgb * brightness;
	EMISSION = line_color.rgb * emission_energy * brightness;
	ALPHA = line_color.a * edge_alpha * (0.62 + moving_band * 0.38);
}
"""

var _curve_index: int = 0
var _points: PackedVector3Array = PackedVector3Array()
var _flow_material: ShaderMaterial


func configure(
	local_start: Vector3,
	local_end: Vector3,
	curve_index: int,
	cell_size: float,
	line_color: Color,
	width_ratio: float,
	arch_height_ratio: float,
	sample_count: int,
	flow_speed: float,
	flow_repeat: float,
	emission_energy: float
) -> void:
	_curve_index = maxi(0, curve_index)
	var resolved_cell_size := maxf(0.001, cell_size)
	var resolved_samples := maxi(2, sample_count)
	var arch_height := (
		resolved_cell_size * maxf(0.0, arch_height_ratio) * float(_curve_index)
	)
	_points = _sample_arch(local_start, local_end, arch_height, resolved_samples)
	mesh = _build_ribbon_mesh(
		_points,
		resolved_cell_size * maxf(0.001, width_ratio),
		resolved_cell_size
	)
	_flow_material = ShaderMaterial.new()
	_flow_material.shader = _get_flow_shader()
	_flow_material.set_shader_parameter("line_color", line_color)
	_flow_material.set_shader_parameter("flow_speed", maxf(0.0, flow_speed))
	_flow_material.set_shader_parameter("flow_repeat", maxf(0.01, flow_repeat))
	_flow_material.set_shader_parameter("emission_energy", maxf(0.0, emission_energy))
	_flow_material.render_priority = 6
	material_override = _flow_material


func get_curve_index() -> int:
	return _curve_index


func get_curve_points() -> PackedVector3Array:
	return _points.duplicate()


func get_flow_material() -> ShaderMaterial:
	return _flow_material


static func _sample_arch(
	start: Vector3,
	end: Vector3,
	arch_height: float,
	sample_count: int
) -> PackedVector3Array:
	var result := PackedVector3Array()
	for sample_index in range(sample_count + 1):
		var t := float(sample_index) / float(sample_count)
		var point := start.lerp(end, t)
		point.y += 4.0 * t * (1.0 - t) * arch_height
		result.append(point)
	return result


static func _build_ribbon_mesh(
	points: PackedVector3Array,
	width: float,
	uv_world_scale: float
) -> ArrayMesh:
	var result := ArrayMesh.new()
	if points.size() < 2:
		return result
	var half_width := maxf(0.001, width) * 0.5
	var distances := PackedFloat32Array()
	distances.resize(points.size())
	for index in range(1, points.size()):
		distances[index] = distances[index - 1] + points[index - 1].distance_to(points[index])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment_index in range(points.size() - 1):
		var start := points[segment_index]
		var end := points[segment_index + 1]
		var tangent := (end - start).normalized()
		var side := Vector3.UP.cross(tangent).normalized()
		if side.length_squared() <= 0.000001:
			side = Vector3.RIGHT
		var start_left := start - side * half_width
		var start_right := start + side * half_width
		var end_left := end - side * half_width
		var end_right := end + side * half_width
		var start_u := distances[segment_index] / maxf(0.001, uv_world_scale)
		var end_u := distances[segment_index + 1] / maxf(0.001, uv_world_scale)
		_add_vertex(surface, start_left, Vector2(start_u, 0.0))
		_add_vertex(surface, end_left, Vector2(end_u, 0.0))
		_add_vertex(surface, end_right, Vector2(end_u, 1.0))
		_add_vertex(surface, start_left, Vector2(start_u, 0.0))
		_add_vertex(surface, end_right, Vector2(end_u, 1.0))
		_add_vertex(surface, start_right, Vector2(start_u, 1.0))
	surface.generate_normals()
	return surface.commit(result)


static func _add_vertex(surface: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(point)


static func _get_flow_shader() -> Shader:
	if _shared_flow_shader == null:
		_shared_flow_shader = Shader.new()
		_shared_flow_shader.code = FLOW_SHADER_CODE
	return _shared_flow_shader
