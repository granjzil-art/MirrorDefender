## Billboarded enemy health presentation with absolute-HP sizing and hit flashes.
class_name EnemyHealthBar3D
extends Node3D

const WIDTH_PER_HP := 0.009
const MINIMUM_WIDTH := 0.42
const MAXIMUM_WIDTH := 2.40
const BAR_HEIGHT := 0.078
const MARKER_WIDTH := 0.018
const MARKER_HEIGHT_MULTIPLIER := 1.65
const FLASH_DURATION := 0.28
const MAX_ACTIVE_FLASHES := 8
const DEPTH_STEP := 0.002

const REMAINING_COLOR := Color(1.0, 0.025, 0.045, 1.0)
const LOST_COLOR := Color(0.34, 0.35, 0.38, 0.94)
const FLASH_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var _maximum_hp: float = 1.0
var _current_hp: float = 1.0
var _bar_width: float = MINIMUM_WIDTH
var _feedback_elapsed: float = FLASH_DURATION

var _lost_mesh: MeshInstance3D
var _remaining_mesh: MeshInstance3D
var _marker_mesh: MeshInstance3D
var _lost_material: StandardMaterial3D
var _remaining_material: StandardMaterial3D
var _marker_material: StandardMaterial3D
var _active_flashes: Array[Dictionary] = []


func _ready() -> void:
	_build_visuals()
	_refresh_geometry()


func _process(delta: float) -> void:
	_face_active_camera()
	_update_feedback(maxf(0.0, delta))
	_update_damage_flashes(maxf(0.0, delta))


func configure(maximum_hp: float, current_hp: float, height_offset: float) -> void:
	_maximum_hp = maxf(1.0, maximum_hp)
	_current_hp = clampf(current_hp, 0.0, _maximum_hp)
	_bar_width = calculate_width_for_hp(_maximum_hp)
	position.y = maxf(0.0, height_offset)
	if is_node_ready():
		_refresh_geometry()


func update_health(current_hp: float, maximum_hp: float) -> void:
	var previous_hp := _current_hp
	var previous_maximum := _maximum_hp
	_maximum_hp = maxf(1.0, maximum_hp)
	_current_hp = clampf(current_hp, 0.0, _maximum_hp)
	_bar_width = calculate_width_for_hp(_maximum_hp)
	if is_node_ready():
		_refresh_geometry()
	if _current_hp < previous_hp:
		var previous_ratio := clampf(previous_hp / maxf(1.0, previous_maximum), 0.0, 1.0)
		var current_ratio := get_current_ratio()
		_add_damage_flash(current_ratio, maxf(current_ratio, previous_ratio))
		_feedback_elapsed = 0.0


static func calculate_width_for_hp(maximum_hp: float) -> float:
	return clampf(maxf(0.0, maximum_hp) * WIDTH_PER_HP, MINIMUM_WIDTH, MAXIMUM_WIDTH)


func get_bar_width() -> float:
	return _bar_width


func get_current_ratio() -> float:
	return clampf(_current_hp / maxf(1.0, _maximum_hp), 0.0, 1.0)


func get_marker_local_x() -> float:
	return -_bar_width * 0.5 + _bar_width * get_current_ratio()


func get_active_flash_count() -> int:
	return _active_flashes.size()


func _build_visuals() -> void:
	_lost_material = _make_material(LOST_COLOR, 0.42, 20)
	_remaining_material = _make_material(REMAINING_COLOR, 1.45, 21)
	_marker_material = _make_material(REMAINING_COLOR, 1.85, 23)
	_lost_mesh = _create_quad(&"LostHealth", _lost_material, 0.0)
	_remaining_mesh = _create_quad(&"RemainingHealth", _remaining_material, DEPTH_STEP)
	_marker_mesh = _create_quad(&"CurrentHealthMarker", _marker_material, DEPTH_STEP * 3.0)


func _refresh_geometry() -> void:
	if _lost_mesh == null or _remaining_mesh == null or _marker_mesh == null:
		return
	_set_quad_size(_lost_mesh, Vector2(_bar_width, BAR_HEIGHT))
	_lost_mesh.position.x = 0.0
	var remaining_width := _bar_width * get_current_ratio()
	_set_quad_size(_remaining_mesh, Vector2(maxf(remaining_width, 0.0001), BAR_HEIGHT))
	_remaining_mesh.position.x = -_bar_width * 0.5 + remaining_width * 0.5
	_remaining_mesh.visible = remaining_width > 0.0001
	_set_quad_size(
		_marker_mesh,
		Vector2(MARKER_WIDTH, BAR_HEIGHT * MARKER_HEIGHT_MULTIPLIER)
	)
	_marker_mesh.position.x = get_marker_local_x()


func _add_damage_flash(from_ratio: float, to_ratio: float) -> void:
	var resolved_from := clampf(from_ratio, 0.0, 1.0)
	var resolved_to := clampf(to_ratio, resolved_from, 1.0)
	if resolved_to - resolved_from <= 0.00001:
		return
	while _active_flashes.size() >= MAX_ACTIVE_FLASHES:
		_remove_flash_at(0)
	var material := _make_material(FLASH_COLOR, 4.8, 22)
	var mesh := _create_quad(&"DamageFlash", material, DEPTH_STEP * 2.0)
	var flash_width := _bar_width * (resolved_to - resolved_from)
	_set_quad_size(mesh, Vector2(maxf(flash_width, 0.0001), BAR_HEIGHT))
	mesh.position.x = -_bar_width * 0.5 + _bar_width * resolved_from + flash_width * 0.5
	_active_flashes.append({
		"mesh": mesh,
		"material": material,
		"elapsed": 0.0,
	})


func _update_feedback(delta: float) -> void:
	if _remaining_material == null or _marker_material == null or _lost_material == null:
		return
	_feedback_elapsed = minf(FLASH_DURATION, _feedback_elapsed + delta)
	var strength := 0.0
	if _feedback_elapsed < FLASH_DURATION:
		var progress := _feedback_elapsed / FLASH_DURATION
		var flicker := 0.64 + 0.36 * absf(cos(progress * TAU * 2.5))
		strength = (1.0 - progress) * flicker
	_remaining_material.emission_energy_multiplier = 1.45 + strength * 2.1
	_marker_material.emission_energy_multiplier = 1.85 + strength * 2.8
	_lost_material.emission_energy_multiplier = 0.42 + strength * 0.48


func _update_damage_flashes(delta: float) -> void:
	for index in range(_active_flashes.size() - 1, -1, -1):
		var flash := _active_flashes[index]
		var elapsed: float = float(flash.get("elapsed", 0.0)) + delta
		if elapsed >= FLASH_DURATION:
			_remove_flash_at(index)
			continue
		flash["elapsed"] = elapsed
		var progress := elapsed / FLASH_DURATION
		var flicker := 0.58 + 0.42 * absf(cos(progress * TAU * 3.0))
		var strength := (1.0 - progress) * flicker
		var material: StandardMaterial3D = flash.get("material") as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(1.0, 1.0, 1.0, clampf(strength * 1.35, 0.0, 1.0))
			material.emission_energy_multiplier = 1.0 + strength * 5.2


func _remove_flash_at(index: int) -> void:
	if index < 0 or index >= _active_flashes.size():
		return
	var flash := _active_flashes[index]
	var mesh: MeshInstance3D = flash.get("mesh") as MeshInstance3D
	if mesh != null and is_instance_valid(mesh):
		mesh.queue_free()
	_active_flashes.remove_at(index)


func _face_active_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera != null:
		global_basis = camera.global_basis.orthonormalized()


func _create_quad(
	node_name: StringName,
	material: StandardMaterial3D,
	depth_offset: float
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = QuadMesh.new()
	instance.material_override = material
	instance.position.z = depth_offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _set_quad_size(instance: MeshInstance3D, size: Vector2) -> void:
	if instance != null and instance.mesh is QuadMesh:
		(instance.mesh as QuadMesh).size = size


func _make_material(
	color: Color,
	emission_energy: float,
	render_priority: int
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = render_priority
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = emission_energy
	return material
