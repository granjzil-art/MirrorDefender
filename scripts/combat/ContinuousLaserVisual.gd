## Persistent volumetric beam renderer. A thick pulse-style BoxMesh remains the
## central axis while two translated, noisy sine filaments flow along it.
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

var _beam_color: Color = Color(0.88, 0.96, 1.0, 0.96)
var _beam_width: float = 0.08
var _emission_energy: float = 3.0
var _beam_material: StandardMaterial3D
var _segments: Array[MeshInstance3D] = []
var _wave_segments: Array[Dictionary] = []
var _endpoint: MeshInstance3D
var _visible_endpoint: Vector3 = Vector3.ZERO


func configure(color: Color, width: float, emission_energy: float) -> void:
	_beam_color = color
	_beam_width = maxf(MIN_SEGMENT_LENGTH, width)
	_emission_energy = maxf(0.0, emission_energy)
	_beam_material = _make_beam_material()
	if _endpoint == null:
		_build_endpoint()
	else:
		_endpoint.material_override = _beam_material
		var endpoint_mesh := _endpoint.mesh as SphereMesh
		if endpoint_mesh != null:
			endpoint_mesh.radius = _beam_width * 1.35
			endpoint_mesh.height = endpoint_mesh.radius * 2.0
	for segment in _segments:
		segment.material_override = _beam_material
	for wave_pair in _wave_segments:
		_apply_wave_style(wave_pair.get("left") as MeshInstance3D, -1.0)
		_apply_wave_style(wave_pair.get("right") as MeshInstance3D, 1.0)


func show_path(raw_segments: Array, world_endpoint: Vector3) -> void:
	if _beam_material == null:
		configure(_beam_color, _beam_width, _emission_energy)
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
		var visual := _ensure_segment(visible_count)
		var mesh := visual.mesh as BoxMesh
		mesh.size = Vector3(_beam_width, _beam_width, length)
		visual.transform = Transform3D(
			Basis.looking_at(direction / length, Vector3.UP),
			(local_start + local_end) * 0.5
		)
		visual.visible = true
		_update_wave_pair(
			visible_count,
			visual.transform,
			length,
			path_distance_offset
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
		_endpoint.visible = true


func clear_path() -> void:
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


func _ensure_segment(index: int) -> MeshInstance3D:
	while _segments.size() <= index:
		var visual := MeshInstance3D.new()
		visual.name = "ContinuousLaserSegment%d" % _segments.size()
		visual.mesh = BoxMesh.new()
		visual.material_override = _beam_material
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
	_apply_wave_style(visual, side_sign)
	return visual


func _apply_wave_style(visual: MeshInstance3D, side_sign: float) -> void:
	if visual == null:
		return
	var material := ShaderMaterial.new()
	material.shader = _get_wave_shader()
	material.set_shader_parameter("beam_color", _beam_color)
	material.set_shader_parameter("emission_energy", _emission_energy)
	material.set_shader_parameter(
		"side_offset",
		side_sign * _beam_width * WAVE_SIDE_OFFSET_RATIO
	)
	material.set_shader_parameter("wave_amplitude", _beam_width * WAVE_AMPLITUDE_RATIO)
	material.set_shader_parameter(
		"noise_amplitude",
		_beam_width * WAVE_NOISE_AMPLITUDE_RATIO
	)
	var wavelength := maxf(MIN_SEGMENT_LENGTH, _beam_width * WAVE_LENGTH_RATIO)
	var angular_frequency := TAU / wavelength
	material.set_shader_parameter("wave_angular_frequency", angular_frequency)
	material.set_shader_parameter(
		"wave_angular_speed",
		TAU * WAVE_FLOW_CYCLES_PER_SECOND
	)
	material.set_shader_parameter(
		"noise_angular_frequency",
		angular_frequency * WAVE_NOISE_FREQUENCY_MULTIPLIER
	)
	visual.material_override = material


func _update_wave_pair(
	index: int,
	segment_transform: Transform3D,
	length: float,
	path_distance_offset: float
) -> void:
	var wave_pair := _ensure_wave_pair(index)
	var wavelength := maxf(MIN_SEGMENT_LENGTH, _beam_width * WAVE_LENGTH_RATIO)
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
				_beam_width * WAVE_THICKNESS_RATIO,
				_beam_width * WAVE_THICKNESS_RATIO,
				length
			)
			mesh.subdivide_depth = subdivisions
		var material := visual.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("segment_length", length)
			material.set_shader_parameter("path_distance_offset", path_distance_offset)
		visual.transform = segment_transform
		visual.visible = true


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


func _build_endpoint() -> void:
	_endpoint = MeshInstance3D.new()
	_endpoint.name = &"LaserEndpoint"
	var mesh := SphereMesh.new()
	mesh.radius = _beam_width * 1.35
	mesh.height = mesh.radius * 2.0
	_endpoint.mesh = mesh
	_endpoint.material_override = _beam_material
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
