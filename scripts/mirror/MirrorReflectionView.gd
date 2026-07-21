## One screen-aligned planar reflection view for a CopyMirror.
## It mirrors the source camera while one observer-facing Quad clips the result.
class_name MirrorReflectionView
extends Node3D

const REFLECTION_VISIBILITY_LAYER := 20
const DEFAULT_VIEWPORT_ASPECT := Vector2(16.0, 9.0)

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
	var active_normal: Vector3 = _mirror.get_active_normal()
	_update_surface_side(active_normal)

func _update_surface_side(surface_normal: Vector3) -> void:
	var edge_direction: Vector3 = _mirror.get_edge_direction()
	if edge_direction.length_squared() <= 0.000001 or surface_normal.length_squared() <= 0.000001:
		return
	var axis_x: Vector3 = edge_direction.normalized()
	var axis_z: Vector3 = axis_x.cross(Vector3.UP).normalized()
	if axis_z.dot(surface_normal) < 0.0:
		axis_x = -axis_x
		axis_z = -axis_z
	var thickness: float = _mirror.get_mirror_thickness()
	_surface.transform = Transform3D(
		Basis(axis_x, Vector3.UP, axis_z),
		Vector3.UP * _mirror.get_mirror_height() * 0.5
			+ surface_normal * thickness * _definition.reflection_surface_offset_ratio
	)

func is_refresh_candidate() -> bool:
	if _source_camera == null or not is_instance_valid(_source_camera) or not _source_camera.current:
		return false
	if _surface == null or not is_instance_valid(_surface) or not _surface.is_visible_in_tree():
		return false
	var active_normal: Vector3 = _mirror.get_active_normal()
	var toward_camera := _source_camera.global_position - _get_mirror_center()
	if not _definition.reflection_two_sided_visual and toward_camera.dot(active_normal) <= 0.001:
		return false
	_update_surface_side(_resolve_observer_normal())
	return _is_surface_in_source_frustum()

func request_refresh() -> bool:
	if not is_refresh_candidate():
		return false
	_ensure_render_target()
	if _viewport == null or _reflection_camera == null:
		return false
	_sync_render_target_size()
	_update_reflection_camera()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func get_surface() -> MeshInstance3D:
	return _surface

func get_reflection_camera() -> Camera3D:
	return _reflection_camera

func get_reflection_viewport() -> SubViewport:
	return _viewport

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
	var width := maxi(64, resolution)
	_viewport = SubViewport.new()
	_viewport.name = "ReflectionViewport"
	_viewport.size = Vector2i(
		width,
		maxi(64, roundi(float(width) * DEFAULT_VIEWPORT_ASPECT.y / DEFAULT_VIEWPORT_ASPECT.x))
	)
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
	_sync_render_target_size()
	_surface.material_override = _make_reflection_material(_viewport.get_texture())

func _update_reflection_camera() -> void:
	var axis_start: Vector3 = _mirror.get_axis_endpoints()[0]
	var axis_end: Vector3 = _mirror.get_axis_endpoints()[1]
	var virtual_eye := MirrorCopyPayload.reflect_point_across_line(
		_source_camera.global_position,
		axis_start,
		axis_end
	)
	var observer_normal := _resolve_observer_normal()
	_update_surface_side(observer_normal)
	var plane_normal: Vector3 = _mirror.get_active_normal()
	var source_forward: Vector3 = -_source_camera.global_basis.z.normalized()
	var source_up: Vector3 = _source_camera.global_basis.y.normalized()
	var reflected_forward := source_forward - 2.0 * source_forward.dot(plane_normal) * plane_normal
	var reflected_up := source_up - 2.0 * source_up.dot(plane_normal) * plane_normal
	_reflection_camera.global_position = virtual_eye
	_reflection_camera.look_at(virtual_eye + reflected_forward, reflected_up)
	_copy_source_projection()
	_reflection_camera.environment = _source_camera.environment
	_reflection_camera.attributes = _source_camera.attributes

func _sync_render_target_size() -> void:
	if _viewport == null or _source_camera == null or _definition == null:
		return
	var resolution := _definition.reflection_preview_resolution if _preview_mode else _definition.reflection_resolution
	var width := maxi(64, resolution)
	var source_viewport := _source_camera.get_viewport()
	var source_size := source_viewport.get_visible_rect().size if source_viewport != null else DEFAULT_VIEWPORT_ASPECT
	var aspect_height := source_size.y / maxf(1.0, source_size.x)
	_viewport.size = Vector2i(width, maxi(64, roundi(float(width) * aspect_height)))

func _copy_source_projection() -> void:
	_reflection_camera.keep_aspect = _source_camera.keep_aspect
	match _source_camera.projection:
		Camera3D.PROJECTION_ORTHOGONAL:
			_reflection_camera.set_orthogonal(_source_camera.size, _source_camera.near, _source_camera.far)
		Camera3D.PROJECTION_FRUSTUM:
			_reflection_camera.set_frustum(
				_source_camera.size,
				_source_camera.frustum_offset,
				_source_camera.near,
				_source_camera.far
			)
		_:
			_reflection_camera.set_perspective(_source_camera.fov, _source_camera.near, _source_camera.far)

func _resolve_observer_normal() -> Vector3:
	var active_normal: Vector3 = _mirror.get_active_normal()
	if not _definition.reflection_two_sided_visual or _source_camera == null:
		return active_normal
	var toward_camera := _source_camera.global_position - _get_mirror_center()
	return -active_normal if toward_camera.dot(active_normal) < 0.0 else active_normal

func _get_mirror_center() -> Vector3:
	return _mirror.global_position + Vector3.UP * _mirror.get_mirror_height() * 0.5

func _is_surface_in_source_frustum() -> bool:
	var center := _surface.global_position
	if _source_camera.is_position_in_frustum(center):
		return true
	var half_right: Vector3 = _surface.global_basis.x.normalized() * _mirror.get_mirror_width() * 0.47
	var half_up: Vector3 = Vector3.UP * _mirror.get_mirror_height() * 0.45
	var corners := PackedVector3Array([
		center - half_right - half_up,
		center + half_right - half_up,
		center + half_right + half_up,
		center - half_right + half_up,
	])
	for corner in corners:
		if _source_camera.is_position_in_frustum(corner):
			return true
	return false

func _make_reflection_material(texture: Texture2D) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D reflection_texture : source_color, filter_linear_mipmap;
uniform vec4 surface_tint : source_color = vec4(0.8, 0.94, 1.0, 1.0);
uniform float reflectivity : hint_range(0.0, 1.0) = 0.92;
void fragment() {
	vec3 reflected = texture(reflection_texture, SCREEN_UV).rgb;
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
