shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D reflection_texture : source_color, filter_linear;
uniform vec4 surface_tint : source_color = vec4(0.12, 0.24, 0.30, 1.0);
uniform float reflectivity : hint_range(0.0, 1.0) = 0.82;
uniform float reflection_brightness : hint_range(0.1, 2.0) = 0.92;
uniform float reflection_blur_pixels : hint_range(0.0, 4.0) = 0.65;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.24;
uniform bool ripple_enabled = true;
uniform float ripple_strength : hint_range(0.0, 0.02) = 0.0028;
uniform float ripple_scale : hint_range(2.0, 40.0) = 9.0;
uniform float ripple_speed : hint_range(0.0, 4.0) = 0.45;
uniform float ripple_highlight_strength : hint_range(0.0, 0.5) = 0.06;

vec3 rain_ripple(vec2 uv) {
	vec2 tiled = uv * ripple_scale;
	vec2 cell = fract(tiled) - vec2(0.5);
	vec2 cell_id = floor(tiled);
	float random_phase = fract(sin(dot(cell_id, vec2(12.9898, 78.233))) * 43758.5453);
	float radius = length(cell);
	float life = fract(TIME * ripple_speed * 0.35 + random_phase);
	float wave_radius = life * 2.25;
	float active = 1.0 - smoothstep(0.20, 0.24, life);
	float ring = exp(-abs(radius - wave_radius) * 58.0) * active;
	float envelope = 1.0 - smoothstep(0.40, 0.52, radius);
	vec2 distortion = normalize(cell + vec2(0.0001)) * ring * envelope * ripple_strength;
	return vec3(distortion, ring * envelope);
}

void fragment() {
	vec3 ripple = ripple_enabled ? rain_ripple(UV) : vec3(0.0);
	vec2 sample_uv = clamp(UV + ripple.xy, vec2(0.002), vec2(0.998));
	vec2 texel = 1.0 / vec2(textureSize(reflection_texture, 0));
	vec2 blur = texel * reflection_blur_pixels;
	vec3 reflected = texture(reflection_texture, sample_uv).rgb * 0.50;
	reflected += texture(reflection_texture, sample_uv + vec2(blur.x, 0.0)).rgb * 0.125;
	reflected += texture(reflection_texture, sample_uv - vec2(blur.x, 0.0)).rgb * 0.125;
	reflected += texture(reflection_texture, sample_uv + vec2(0.0, blur.y)).rgb * 0.125;
	reflected += texture(reflection_texture, sample_uv - vec2(0.0, blur.y)).rgb * 0.125;
	reflected *= reflection_brightness;
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float reflection_mix = clamp(reflectivity + fresnel * fresnel_strength, 0.0, 1.0);
	vec3 tinted_reflection = mix(reflected, reflected * surface_tint.rgb * 1.35, 0.30);
	vec3 ripple_highlight = vec3(0.36, 0.54, 0.62) * ripple.z * ripple_highlight_strength;
	ALBEDO = mix(surface_tint.rgb, tinted_reflection, reflection_mix) + ripple_highlight;
}
