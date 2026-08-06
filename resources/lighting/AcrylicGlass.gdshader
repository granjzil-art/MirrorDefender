shader_type spatial;

render_mode blend_mix, depth_draw_never, cull_disabled,
		diffuse_burley, specular_schlick_ggx;

uniform vec4 glass_tint : source_color = vec4(0.72, 0.90, 0.94, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.86, 0.96, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 0.2) = 0.018;
uniform float fresnel_alpha : hint_range(0.0, 0.4) = 0.11;
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float border_alpha : hint_range(0.0, 0.4) = 0.11;
uniform float border_width : hint_range(0.001, 0.1) = 0.025;
uniform float stripe_position : hint_range(0.0, 1.5) = 0.55;
uniform float stripe_width : hint_range(0.01, 0.5) = 0.16;
uniform float stripe_strength : hint_range(0.0, 0.25) = 0.035;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(1.0 - facing, fresnel_power);
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border = 1.0 - smoothstep(0.0, border_width, edge_distance);
	float diagonal = UV.x + UV.y * 0.25;
	float stripe = 1.0 - smoothstep(
		stripe_width,
		stripe_width * 2.0,
		abs(diagonal - stripe_position)
	);

	ALBEDO = glass_tint.rgb;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = stripe_color.rgb * stripe * stripe_strength + glass_tint.rgb * border * 0.04;
	ALPHA = clamp(
		base_alpha + fresnel * fresnel_alpha + border * border_alpha + stripe * stripe_strength,
		0.0,
		0.30
	);
}
