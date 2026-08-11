shader_type canvas_item;
render_mode unshaded;

uniform vec4 upper_color : source_color = vec4(0.91, 0.92, 0.93, 0.99);
uniform vec4 middle_color : source_color = vec4(0.67, 0.69, 0.70, 0.98);
uniform vec4 lower_color : source_color = vec4(0.42, 0.47, 0.49, 0.98);
uniform vec4 sheen_color : source_color = vec4(0.99, 0.99, 0.98, 1.0);
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.36;
uniform float shimmer_speed : hint_range(0.0, 0.25) = 0.035;
uniform float hover_strength : hint_range(0.0, 1.0) = 0.0;
uniform float selected_strength : hint_range(0.0, 1.0) = 0.0;
uniform float disabled_strength : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 0.25) = 0.085;

float rounded_mask(vec2 uv, float radius) {
	vec2 point = abs(uv * 2.0 - vec2(1.0));
	vec2 corner = point - (vec2(1.0) - vec2(radius * 2.0));
	float distance_to_edge = length(max(corner, vec2(0.0)))
		+ min(max(corner.x, corner.y), 0.0)
		- radius * 2.0;
	return 1.0 - smoothstep(-0.018, 0.018, distance_to_edge);
}

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float lower_mix = smoothstep(0.24, 1.0, UV.y);
	vec3 mirror_color = mix(middle_color.rgb, lower_color.rgb, lower_mix);
	float upper_mix = (1.0 - smoothstep(0.0, 0.52, UV.y)) * 0.78;
	mirror_color = mix(mirror_color, upper_color.rgb, upper_mix);

	// Broad, blurred silhouettes suggest a reflected environment without sampling
	// the gameplay viewport, so every card remains readable and deterministic.
	float cloud_a = sin(UV.x * 5.4 + UV.y * 2.1 + 0.7) * 0.5 + 0.5;
	float cloud_b = sin(UV.x * -3.2 + UV.y * 5.8 + 1.9) * 0.5 + 0.5;
	float reflection_shadow = smoothstep(0.72, 1.0, cloud_a * 0.62 + cloud_b * 0.38);
	mirror_color *= 1.0 - reflection_shadow * 0.10;

	float diagonal = UV.x + UV.y * 0.34;
	float fixed_sheen = exp(-pow((diagonal - 0.48) * 8.5, 2.0));
	fixed_sheen += exp(-pow((diagonal - 1.06) * 13.0, 2.0)) * 0.42;
	float sweep_center = mix(-0.35, 1.55, fract(TIME * shimmer_speed));
	float moving_sheen = exp(-pow((diagonal - sweep_center) * 15.0, 2.0));
	float resolved_sheen = fixed_sheen * sheen_strength
		+ moving_sheen * (0.08 + hover_strength * 0.28);
	mirror_color += sheen_color.rgb * resolved_sheen;

	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float edge_glow = 1.0 - smoothstep(0.0, 0.18, edge_distance);
	mirror_color += sheen_color.rgb * edge_glow * (0.06 + selected_strength * 0.10);

	float grain = hash21(floor(UV * vec2(96.0, 128.0))) - 0.5;
	mirror_color += grain * 0.012;
	float luminance = dot(mirror_color, vec3(0.299, 0.587, 0.114));
	mirror_color = mix(mirror_color, vec3(luminance) * 0.64, disabled_strength * 0.72);
	mirror_color *= 1.0 - disabled_strength * 0.28;

	float alpha = mix(middle_color.a, lower_color.a, lower_mix);
	alpha = mix(alpha, upper_color.a, upper_mix);
	COLOR = vec4(mirror_color, alpha * rounded_mask(UV, corner_radius));
}
