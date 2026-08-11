shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float shadow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float breakup_scale : hint_range(1.0, 32.0) = 12.0;
uniform float gap_threshold : hint_range(0.0, 1.0) = 0.52;
uniform float pattern_seed = 7.31;


float hash_21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float bottom = mix(hash_21(cell), hash_21(cell + vec2(1.0, 0.0)), local.x);
	float top = mix(hash_21(cell + vec2(0.0, 1.0)), hash_21(cell + vec2(1.0, 1.0)), local.x);
	return mix(bottom, top, local.y);
}


void fragment() {
	float authored_alpha = texture(albedo_texture, UV).a;
	vec2 seed_offset = vec2(pattern_seed, pattern_seed * 1.731);
	float broad_gaps = value_noise(UV * max(breakup_scale * 0.28, 1.0) + seed_offset);
	float leaf_detail = value_noise(UV * breakup_scale + seed_offset.yx * 2.17);
	float breakup = mix(broad_gaps, leaf_detail, 0.38);
	float gap_mask = smoothstep(gap_threshold - 0.06, gap_threshold + 0.06, breakup);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(authored_alpha * gap_mask * shadow_strength, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
