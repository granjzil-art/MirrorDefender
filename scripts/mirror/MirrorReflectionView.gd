## One active-face planar reflection view for a CopyMirror.
## The off-axis frustum maps the shared 3D world to the physical mirror rectangle.
class_name MirrorReflectionView
extends Node3D

const REFLECTION_VISIBILITY_LAYER := 20

var _mirror: Node3D
var _definition: CopyMirrorDefinition
var _source_camera: Camera3D
var _preview_mode: bool = false
var _surface: MeshInstance3D
var _fallback_material: StandardMaterial3D
var _viewport: SubViewport
var _reflection_camera: Camera3D

func configure(
	copy_mirror: Node3D,
	definition: CopyMirrorDefinition,
	source_camera: Camera3D,
	preview_mode: bool
) -> void:
	_mirror = copy_mirror
	_definition = definition
	_source_camera = source_camera
	_preview_mode = preview_mode
	_build_surface()
	if _source_camera != null:
		_ensure_render_target()
	update_active_side()

func set_source_camera(camera: Camera3D) -> void:
	_source_camera = camera
	if _source_camera != null:
		_ensure_render_target()

func update_active_side() -> void:
	if _surface == null or _mirror == null:
		return
	var edge_direction: Vector3 = _mirror.get_edge_direction()
	var active_normal: Vector3 = _mirror.get_active_normal()
	if edge_direction.length_squared() <= 0.000001 or active_normal.length_squared() <= 0.000001:
		return
	var axis_x: Vector3 = edge_direction.normalized()
	var axis_z: Vector3 = axis_x.cross(Vector3.UP).normalized()
	if axis_z.dot(active_normal) < 0.0:
		axis_x = -axis_x
		axis_z = -axis_z
	var thickness: float = _mirror.get_mirror_thickness()
	_surface.transform = Transform3D(
		Basis(axis_x, Vector3.UP, axis_z),
		Vector3.UP * _mirror.get_mirror_height() * 0.5 + active_normal * thickness * 0.56
	)

func is_refresh_candidate() -> bool:
	if _source_camera == null or not is_instance_valid(_source_camera) or not _source_camera.current:
		return false
	if _surface == null or not is_instance_valid(_surface) or not _surface.is_visible_in_tree():
		return false
	var toward_camera := _source_camera.global_position - _surface.global_position
	if toward_camera.dot(_mirror.get_active_normal()) <= 0.001:
		return false
	return _source_camera.is_position_in_frustum(_surface.global_position)

func request_refresh() -> bool:
	if not is_refresh_candidate():
		return false
	_ensure_render_target()
	if _viewport == null or _reflection_camera == null:
		return false
	_update_reflection_camera()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func get_surface() -> MeshInstance3D:
	return _surface

func get_reflection_camera() -> Camera3D:
	return _reflection_camera

func _build_surface() -> void:
	_surface = MeshInstance3D.new()
	_surface.name = "ActiveReflectionSurface"
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Z
	quad.size = Vector2(_mirror.get_mirror_width() * 0.94, _mirror.get_mirror_height() * 0.90)
	_surface.mesh = quad
	_surface.set_layer_mask_value(1, false)
	_surface.set_layer_mask_value(REFLECTION_VISIBILITY_LAYER, true)
	_fallback_material = StandardMaterial3D.new()
	_fallback_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fallback_material.albedo_color = _definition.mirror_surface_tint.lerp(_definition.mirror_color, 0.28)
	_fallback_material.metallic = 0.85
	_fallback_material.roughness = 0.08
	_surface.material_override = _fallback_material
	add_child(_surface)

func _ensure_render_target() -> void:
	if _viewport != null or _source_camera == null or _definition == null or not _definition.reflection_enabled:
		return
	var resolution := _definition.reflection_preview_resolution if _preview_mode else _definition.reflection_resolution
	var aspect: float = _mirror.get_mirror_width() / maxf(0.01, _mirror.get_mirror_height())
	var width := maxi(64, resolution)
	var height := maxi(64, roundi(float(width) / maxf(0.1, aspect)))
	_viewport = SubViewport.new()
	_viewport.name = "ReflectionViewport"
	_viewport.size = Vector2i(width, height)
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.world_3d = _mirror.get_world_3d()
	add_child(_viewport)
	_reflection_camera = Camera3D.new()
	_reflection_camera.name = "ReflectionCamera"
	_reflection_camera.current = true
	_reflection_camera.cull_mask = _source_camera.cull_mask
	_reflection_camera.set_cull_mask_value(REFLECTION_VISIBILITY_LAYER, false)
	_viewport.add_child(_reflection_camera)
	_surface.material_override = _make_reflection_material(_viewport.get_texture())

func _update_reflection_camera() -> void:
	var axis_start: Vector3 = _mirror.get_axis_endpoints()[0]
	var axis_end: Vector3 = _mirror.get_axis_endpoints()[1]
	var virtual_eye := MirrorCopyPayload.reflect_point_across_line(
		_source_camera.global_position,
		axis_start,
		axis_end
	)
	var normal: Vector3 = _mirror.get_active_normal()
	var surface_center := _surface.global_position
	var distance := maxf(0.05, (surface_center - virtual_eye).dot(normal))
	var surface_right: Vector3 = _mirror.get_edge_direction().normalized()
	if surface_right.cross(Vector3.UP).dot(normal) < 0.0:
		surface_right = -surface_right
	var camera_right: Vector3 = -surface_right
	var camera_back: Vector3 = -normal
	_reflection_camera.global_transform = Transform3D(
		Basis(camera_right, Vector3.UP, camera_back),
		virtual_eye
	)
	var near_plane := maxf(0.02, distance * 0.985)
	var to_center := surface_center - virtual_eye
	var offset := Vector2(
		to_center.dot(camera_right) * near_plane / distance,
		to_center.dot(Vector3.UP) * near_plane / distance
	)
	var frustum_height: float = _mirror.get_mirror_height() * 0.90 * near_plane / distance
	_reflection_camera.set_frustum(
		maxf(0.01, frustum_height),
		offset,
		near_plane,
		maxf(near_plane + 1.0, _source_camera.far)
	)
	_reflection_camera.environment = _source_camera.environment
	_reflection_camera.attributes = _source_camera.attributes

func _make_reflection_material(texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D reflection_texture : source_color, filter_linear_mipmap;
uniform vec4 surface_tint : source_color = vec4(0.8, 0.94, 1.0, 1.0);
uniform float reflectivity : hint_range(0.0, 1.0) = 0.92;
void fragment() {
	vec3 reflected = texture(reflection_texture, UV).rgb;
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec3 result = mix(surface_tint.rgb, reflected * surface_tint.rgb, reflectivity);
	ALBEDO = result + surface_tint.rgb * rim * 0.12;
	EMISSION = result * 0.18;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("reflection_texture", texture)
	material.set_shader_parameter("surface_tint", _definition.mirror_surface_tint)
	material.set_shader_parameter("reflectivity", _definition.mirror_reflectivity)
	return material
