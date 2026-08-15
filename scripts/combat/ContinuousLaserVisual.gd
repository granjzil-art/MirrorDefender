## Persistent volumetric beam renderer. Ordinary ice beams keep their central
## axis plus two translated filaments, while pulse-copy overdrive can request a
## dedicated single thick sine presentation with no axis or secondary filament.
class_name ContinuousLaserVisual
extends Node3D

const MIN_SEGMENT_LENGTH := 0.0001
const WAVE_THICKNESS_RATIO := 0.22
const WAVE_SIDE_OFFSET_RATIO := 1.35
const WAVE_AMPLITUDE_RATIO := 0.42
const WAVE_NOISE_AMPLITUDE_RATIO := 0.14
const WAVE_LENGTH_RATIO := 13.0
const WAVE_FLOW_CYCLES_PER_SECOND := 1.25
const WAVE_NOISE_FREQUENCY_MULTIPLIER := 2.17
const WAVE_SAMPLES_PER_CYCLE := 12.0
const MIN_WAVE_SUBDIVISIONS := 8
const MAX_WAVE_SUBDIVISIONS := 128
const WAVE_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 beam_color : source_color = vec4(0.88, 0.96, 1.0, 0.96);
uniform float emission_energy = 3.0;
uniform float segment_length = 1.0;
uniform float path_distance_offset = 0.0;
uniform float side_offset = 0.0;
uniform float wave_amplitude = 0.03;
uniform float wave_angular_frequency = 6.28318530718;
uniform float wave_angular_speed = 7.85398163397;
uniform float noise_amplitude = 0.01;
uniform float noise_angular_frequency = 13.634512;

float random_1d(float coordinate) {
	return fract(sin(coordinate * 127.1) * 43758.5453123);
}

float smooth_value_noise(float coordinate) {
	float cell = floor(coordinate);
	float fraction = fract(coordinate);
	float eased = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(random_1d(cell), random_1d(cell + 1.0), eased) * 2.0 - 1.0;
}

void vertex() {
	// Basis.looking_at() points local -Z along the beam, so +Z is the
	// beginning of a segment. The cumulative offset keeps reflected segments
	// on one continuous travelling phase.
	float path_distance = path_distance_offset + segment_length * 0.5 - VERTEX.z;
	float phase = path_distance * wave_angular_frequency - TIME * wave_angular_speed;
	float noise_phase = (
		path_distance * noise_angular_frequency
		+ TIME * wave_angular_speed * 0.37
	);
	float layered_noise = (
		smooth_value_noise(noise_phase)
		+ 0.5 * smooth_value_noise(noise_phase * 2.03 + 7.1)
	) / 1.5;
	VERTEX.x += (
		side_offset
		+ sin(phase) * wave_amplitude
		+ layered_noise * noise_amplitude
	);
}

void fragment() {
	ALBEDO = beam_color.rgb;
	EMISSION = beam_color.rgb * emission_energy;
	ALPHA = beam_color.a;
}
"""

static var _shared_wave_shader: Shader
static var _shared_single_sine_shader: Shader

var _beam_color: Color = Color(0.88, 0.96, 1.0, 0.96)
var _beam_width: float = 0.08
var _emission_energy: float = 3.0
var _beam_material: StandardMaterial3D
var _segments: Array[MeshInstance3D] = []
var _wave_segments: Array[Dictionary] = []
var _endpoint: MeshInstance3D
var _visible_endpoint: Vector3 = Vector3.ZERO
var _single_sine_mode: bool = false
var _single_sine_thickness_multiplier: float = 1.0
var _single_sine_amplitude_ratio: float = WAVE_AMPLITUDE_RATIO
var _single_sine_wavelength_ratio: float = WAVE_LENGTH_RATIO
var _single_sine_flow_cycles_per_second: float = WAVE_FLOW_CYCLES_PER_SECOND
var _single_sine_samples_per_cycle: float = WAVE_SAMPLES_PER_CYCLE
var _single_sine_min_subdivisions: int = MIN_WAVE_SUBDIVISIONS
var _single_sine_max_subdivisions: int = MAX_WAVE_SUBDIVISIONS


func configure(color: Color, width: float, emission_energy: float) -> void:
	_beam_color = color
	_beam_width = maxf(MIN_SEGMENT_LENGTH, width)
	_emission_energy = maxf(0.0, emission_energy)
	_beam_material = _make_beam_material()
	if _endpoint == null:
		_build_endpoint()
	else:
		_apply_box_material_style(_endpoint, _beam_color, _emission_energy)
		var endpoint_mesh := _endpoint.mesh as SphereMesh
		if endpoint_mesh != null:
			endpoint_mesh.radius = _beam_width * 1.35
			endpoint_mesh.height = endpoint_mesh.radius * 2.0
	for segment in _segments:
		_apply_box_material_style(segment, _beam_color, _emission_energy)
	for wave_pair in _wave_segments:
		_apply_wave_style(wave_pair.get("left") as MeshInstance3D, -1.0, _beam_color, _beam_width)
		_apply_wave_style(wave_pair.get("right") as MeshInstance3D, 1.0, _beam_color, _beam_width)


func configure_single_sine_tuning(tuning: Dictionary) -> void:
	_single_sine_thickness_multiplier = maxf(
		0.01,
		float(tuning.get("thickness_multiplier", 1.0))
	)
	_single_sine_amplitude_ratio = maxf(
		0.0,
		float(tuning.get("amplitude_ratio", WAVE_AMPLITUDE_RATIO))
	)
	_single_sine_wavelength_ratio = maxf(
		0.1,
		float(tuning.get("wavelength_ratio", WAVE_LENGTH_RATIO))
	)
	_single_sine_flow_cycles_per_second = maxf(
		0.0,
		float(tuning.get("flow_cycles_per_second", WAVE_FLOW_CYCLES_PER_SECOND))
	)
	_single_sine_samples_per_cycle = maxf(
		1.0,
		float(tuning.get("samples_per_cycle", WAVE_SAMPLES_PER_CYCLE))
	)
	_single_sine_min_subdivisions = maxi(
		1,
		int(tuning.get("min_subdivisions", MIN_WAVE_SUBDIVISIONS))
	)
	_single_sine_max_subdivisions = maxi(
		_single_sine_min_subdivisions,
		int(tuning.get("max_subdivisions", MAX_WAVE_SUBDIVISIONS))
	)


func show_path(raw_segments: Array, world_endpoint: Vector3) -> void:
	_show_path(raw_segments, world_endpoint, false)


func show_single_sine_path(raw_segments: Array, world_endpoint: Vector3) -> void:
	_show_path(raw_segments, world_endpoint, true)


func _show_path(raw_segments: Array, world_endpoint: Vector3, single_sine: bool) -> void:
	if _beam_material == null:
		configure(_beam_color, _beam_width, _emission_energy)
	_single_sine_mode = single_sine
	var visible_count := 0
	var path_distance_offset := 0.0
	for raw_segment in raw_segments:
		if not raw_segment is Dictionary:
			continue
		var segment: Dictionary = raw_segment
		var world_start: Vector3 = segment.get("start", world_endpoint)
		var world_end: Vector3 = segment.get("end", world_start)
		var local_start := to_local(world_start)
		var local_end := to_local(world_end)
		var direction := local_end - local_start
		var length := direction.length()
		if length <= MIN_SEGMENT_LENGTH:
			continue
		var visual_modifiers: Dictionary = segment.get("laser_visual_modifiers", {})
		var segment_color: Color = visual_modifiers.get("color", _beam_color)
		var segment_width := _beam_width * maxf(
			MIN_SEGMENT_LENGTH,
			float(visual_modifiers.get("width_multiplier", 1.0))
		)
		var visual := _ensure_segment(visible_count)
		var mesh := visual.mesh as BoxMesh
		mesh.size = Vector3(segment_width, segment_width, length)
		_apply_box_material_style(visual, segment_color, _emission_energy)
		visual.transform = Transform3D(
			Basis.looking_at(direction / length, Vector3.UP),
			(local_start + local_end) * 0.5
		)
		visual.visible = not single_sine
		if single_sine:
			_update_single_sine_segment(
				visible_count,
				visual.transform,
				length,
				path_distance_offset,
				segment_color,
				segment_width
			)
		else:
			_update_wave_pair(
				visible_count,
				visual.transform,
				length,
				path_distance_offset,
				segment_color,
				segment_width
			)
		path_distance_offset += length
		visible_count += 1
	for index in range(visible_count, _segments.size()):
		_segments[index].visible = false
	for index in range(visible_count, _wave_segments.size()):
		_set_wave_pair_visible(_wave_segments[index], false)
	_visible_endpoint = world_endpoint
	if _endpoint != null:
		_endpoint.position = to_local(world_endpoint)
		if visible_count > 0:
			var last_segment: Dictionary = raw_segments[visible_count - 1]
			var endpoint_modifiers: Dictionary = last_segment.get("laser_visual_modifiers", {})
			var endpoint_color: Color = endpoint_modifiers.get("color", _beam_color)
			var endpoint_width := _beam_width * maxf(
				MIN_SEGMENT_LENGTH,
				float(endpoint_modifiers.get("width_multiplier", 1.0))
			)
			var endpoint_mesh := _endpoint.mesh as SphereMesh
			if endpoint_mesh != null:
				endpoint_mesh.radius = endpoint_width * 1.35
				endpoint_mesh.height = endpoint_mesh.radius * 2.0
			_apply_box_material_style(_endpoint, endpoint_color, _emission_energy)
		# Pulse-copy overdrive is authored as exactly one sine curve. Its old
		# transparent endpoint sphere could still bloom into a white spot after
		# the reflected center/branch paths overlapped around it.
		_endpoint.visible = not single_sine


func clear_path() -> void:
	_single_sine_mode = false
	for segment in _segments:
		segment.visible = false
	for wave_pair in _wave_segments:
		_set_wave_pair_visible(wave_pair, false)
	if _endpoint != null:
		_endpoint.visible = false


func get_visible_endpoint() -> Vector3:
	return _visible_endpoint


func debug_get_visible_length() -> float:
	var total := 0.0
	for segment in _segments:
		if segment.visible and segment.mesh is BoxMesh:
			total += (segment.mesh as BoxMesh).size.z
	return total


func debug_get_beam_material() -> StandardMaterial3D:
	return _beam_material


func debug_get_beam_width() -> float:
	return _beam_width


func debug_get_wave_pair_count() -> int:
	var visible_count := 0
	for wave_pair in _wave_segments:
		var left := wave_pair.get("left") as MeshInstance3D
		var right := wave_pair.get("right") as MeshInstance3D
		if left != null and right != null and left.visible and right.visible:
			visible_count += 1
	return visible_count


func debug_get_visible_axis_segment_count() -> int:
	var visible_count := 0
	for segment in _segments:
		if segment != null and segment.visible:
			visible_count += 1
	return visible_count


func debug_get_single_sine_segment_count() -> int:
	if not _single_sine_mode:
		return 0
	var visible_count := 0
	for wave_pair in _wave_segments:
		var primary := wave_pair.get("left") as MeshInstance3D
		var secondary := wave_pair.get("right") as MeshInstance3D
		if primary != null and primary.visible and (secondary == null or not secondary.visible):
			visible_count += 1
	return visible_count


func debug_get_single_sine_segment_color(index: int = 0) -> Color:
	if not _single_sine_mode or index < 0 or index >= _wave_segments.size():
		return Color.TRANSPARENT
	var wave_pair: Dictionary = _wave_segments[index]
	var primary := wave_pair.get("left") as MeshInstance3D
	if primary == null or not primary.visible:
		return Color.TRANSPARENT
	var material := primary.material_override as ShaderMaterial
	if material == null:
		return Color.TRANSPARENT
	var value: Variant = material.get_shader_parameter("beam_color")
	return value as Color if value is Color else Color.TRANSPARENT


func _ensure_segment(index: int) -> MeshInstance3D:
	while _segments.size() <= index:
		var visual := MeshInstance3D.new()
		visual.name = "ContinuousLaserSegment%d" % _segments.size()
		visual.mesh = BoxMesh.new()
		visual.material_override = _make_beam_material()
		visual.visible = false
		add_child(visual)
		_segments.append(visual)
	return _segments[index]


func _ensure_wave_pair(index: int) -> Dictionary:
	while _wave_segments.size() <= index:
		var pair_index := _wave_segments.size()
		var left := _make_wave_segment("ContinuousLaserWaveLeft%d" % pair_index, -1.0)
		var right := _make_wave_segment("ContinuousLaserWaveRight%d" % pair_index, 1.0)
		_wave_segments.append({"left": left, "right": right})
	return _wave_segments[index]


func _make_wave_segment(segment_name: String, side_sign: float) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = segment_name
	visual.mesh = BoxMesh.new()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visible = false
	add_child(visual)
	_apply_wave_style(visual, side_sign, _beam_color, _beam_width)
	return visual


func _apply_wave_style(
	visual: MeshInstance3D,
	side_sign: float,
	color: Color,
	width: float,
	noise_scale: float = 1.0,
	amplitude_ratio: float = WAVE_AMPLITUDE_RATIO,
	flow_cycles_per_second: float = WAVE_FLOW_CYCLES_PER_SECOND,
	wavelength_ratio: float = WAVE_LENGTH_RATIO,
	use_opaque_single_sine_shader: bool = false
) -> void:
	if visual == null:
		return
	var resolved_shader := (
		_get_single_sine_shader()
		if use_opaque_single_sine_shader
		else _get_wave_shader()
	)
	var material := visual.material_override as ShaderMaterial
	if material == null or material.shader != resolved_shader:
		material = ShaderMaterial.new()
		material.shader = resolved_shader
		visual.material_override = material
	material.set_shader_parameter("beam_color", color)
	material.set_shader_parameter("emission_energy", _emission_energy)
	material.set_shader_parameter(
		"side_offset",
		side_sign * width * WAVE_SIDE_OFFSET_RATIO
	)
	material.set_shader_parameter("wave_amplitude", width * maxf(0.0, amplitude_ratio))
	material.set_shader_parameter(
		"noise_amplitude",
		width * WAVE_NOISE_AMPLITUDE_RATIO * maxf(0.0, noise_scale)
	)
	var wavelength := maxf(MIN_SEGMENT_LENGTH, width * maxf(0.1, wavelength_ratio))
	var angular_frequency := TAU / wavelength
	material.set_shader_parameter("wave_angular_frequency", angular_frequency)
	material.set_shader_parameter(
		"wave_angular_speed",
		TAU * maxf(0.0, flow_cycles_per_second)
	)
	material.set_shader_parameter(
		"noise_angular_frequency",
		angular_frequency * WAVE_NOISE_FREQUENCY_MULTIPLIER
	)


func _update_wave_pair(
	index: int,
	segment_transform: Transform3D,
	length: float,
	path_distance_offset: float,
	color: Color,
	width: float
) -> void:
	var wave_pair := _ensure_wave_pair(index)
	var wavelength := maxf(MIN_SEGMENT_LENGTH, width * WAVE_LENGTH_RATIO)
	var subdivisions := clampi(
		ceili(length / wavelength * WAVE_SAMPLES_PER_CYCLE),
		MIN_WAVE_SUBDIVISIONS,
		MAX_WAVE_SUBDIVISIONS
	)
	for side_name in [&"left", &"right"]:
		var visual := wave_pair.get(side_name) as MeshInstance3D
		if visual == null:
			continue
		var mesh := visual.mesh as BoxMesh
		if mesh != null:
			mesh.size = Vector3(
				width * WAVE_THICKNESS_RATIO,
				width * WAVE_THICKNESS_RATIO,
				length
			)
			mesh.subdivide_depth = subdivisions
		_apply_wave_style(visual, -1.0 if side_name == &"left" else 1.0, color, width)
		var material := visual.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("segment_length", length)
			material.set_shader_parameter("path_distance_offset", path_distance_offset)
		visual.transform = segment_transform
		visual.visible = true


func _update_single_sine_segment(
	index: int,
	segment_transform: Transform3D,
	length: float,
	path_distance_offset: float,
	color: Color,
	width: float
) -> void:
	var wave_pair := _ensure_wave_pair(index)
	var primary := wave_pair.get("left") as MeshInstance3D
	var secondary := wave_pair.get("right") as MeshInstance3D
	if primary != null:
		var wavelength := maxf(
			MIN_SEGMENT_LENGTH,
			width * _single_sine_wavelength_ratio
		)
		var subdivisions := clampi(
			ceili(length / wavelength * _single_sine_samples_per_cycle),
			_single_sine_min_subdivisions,
			_single_sine_max_subdivisions
		)
		var mesh := primary.mesh as BoxMesh
		if mesh != null:
			var thickness := width * _single_sine_thickness_multiplier
			mesh.size = Vector3(thickness, thickness, length)
			mesh.subdivide_depth = subdivisions
		_apply_wave_style(
			primary,
			0.0,
			color,
			width,
			0.0,
			_single_sine_amplitude_ratio,
			_single_sine_flow_cycles_per_second,
			_single_sine_wavelength_ratio,
			true
		)
		var material := primary.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("segment_length", length)
			material.set_shader_parameter("path_distance_offset", path_distance_offset)
		primary.transform = segment_transform
		primary.visible = true
	if secondary != null:
		secondary.visible = false


func _set_wave_pair_visible(wave_pair: Dictionary, is_visible: bool) -> void:
	var left := wave_pair.get("left") as MeshInstance3D
	var right := wave_pair.get("right") as MeshInstance3D
	if left != null:
		left.visible = is_visible
	if right != null:
		right.visible = is_visible


func _get_wave_shader() -> Shader:
	if _shared_wave_shader == null:
		_shared_wave_shader = Shader.new()
		_shared_wave_shader.code = WAVE_SHADER_CODE
	return _shared_wave_shader


## The copied pulse overdrive is intentionally opaque and single-sided. An L2
## reflection creates three beams sharing one origin; the generic transparent,
## double-sided wave shader lets all overlapping faces blend in an unstable
## order and ACES/glow can consequently wash the palette to white.
func _get_single_sine_shader() -> Shader:
	if _shared_single_sine_shader == null:
		_shared_single_sine_shader = Shader.new()
		_shared_single_sine_shader.code = WAVE_SHADER_CODE.replace(
			"render_mode unshaded, cull_disabled;",
			"render_mode unshaded, depth_draw_opaque;"
		).replace("\n\tALPHA = beam_color.a;", "")
	return _shared_single_sine_shader


func _build_endpoint() -> void:
	_endpoint = MeshInstance3D.new()
	_endpoint.name = &"LaserEndpoint"
	var mesh := SphereMesh.new()
	mesh.radius = _beam_width * 1.35
	mesh.height = mesh.radius * 2.0
	_endpoint.mesh = mesh
	_endpoint.material_override = _make_beam_material()
	_endpoint.visible = false
	add_child(_endpoint)


func _make_beam_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = _beam_color
	material.emission_enabled = true
	material.emission = _beam_color
	material.emission_energy_multiplier = _emission_energy
	return material


func _apply_box_material_style(
	visual: MeshInstance3D,
	color: Color,
	emission_energy: float
) -> void:
	if visual == null:
		return
	var material := visual.material_override as StandardMaterial3D
	if material == null:
		material = _make_beam_material()
		visual.material_override = material
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = maxf(0.0, emission_energy)
