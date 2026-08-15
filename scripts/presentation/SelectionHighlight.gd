## Shared, non-destructive green selection overlay for live buildings and mirrors.
extends RefCounted

const PREVIOUS_OVERLAY_META := &"selection_highlight_previous_overlay"
const OWNED_OVERLAY_META := &"selection_highlight_owned_overlay"
const HIGHLIGHT_COLOR := Color(0.12, 1.0, 0.24, 1.0)

static var _shared_shader: Shader


static func apply_recursive(root: Node, enabled: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is MeshInstance3D:
		_apply_to_mesh(root as MeshInstance3D, enabled)
	for child in root.get_children():
		apply_recursive(child, enabled)


static func _apply_to_mesh(mesh_instance: MeshInstance3D, enabled: bool) -> void:
	if mesh_instance.mesh == null:
		return
	if enabled:
		if not mesh_instance.has_meta(OWNED_OVERLAY_META):
			mesh_instance.set_meta(PREVIOUS_OVERLAY_META, mesh_instance.material_overlay)
			mesh_instance.set_meta(OWNED_OVERLAY_META, true)
		mesh_instance.material_overlay = _make_material()
		return
	if not mesh_instance.has_meta(OWNED_OVERLAY_META):
		return
	var previous: Variant = mesh_instance.get_meta(PREVIOUS_OVERLAY_META, null)
	mesh_instance.material_overlay = previous as Material
	mesh_instance.remove_meta(PREVIOUS_OVERLAY_META)
	mesh_instance.remove_meta(OWNED_OVERLAY_META)


static func _make_material() -> ShaderMaterial:
	if _shared_shader == null:
		_shared_shader = Shader.new()
		_shared_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled;
uniform vec4 highlight_color : source_color = vec4(0.12, 1.0, 0.24, 1.0);
uniform float body_alpha = 0.34;
uniform float rim_alpha = 0.72;
uniform float pulse_speed = 4.8;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.45);
	float pulse = 0.72 + 0.28 * sin(TIME * pulse_speed);
	ALBEDO = highlight_color.rgb;
	EMISSION = highlight_color.rgb * (2.2 + rim * 4.0) * pulse;
	ALPHA = clamp(body_alpha * pulse + rim * rim_alpha, 0.0, 0.94);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _shared_shader
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.set_shader_parameter("highlight_color", HIGHLIGHT_COLOR)
	return material
