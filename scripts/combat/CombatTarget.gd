## Runtime damageable target contract. M4 units register instances with CombatManager.
class_name CombatTarget
extends Node3D

const COLD_SURFACE_SHADER_CODE := """
shader_type spatial;
render_mode cull_back;

uniform vec4 cold_tint : source_color = vec4(0.005, 0.03, 0.28, 1.0);
uniform float emission_energy = 0.32;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	float pulse = 0.94 + sin(TIME * 2.4) * 0.06;
	ALBEDO = cold_tint.rgb * (0.78 + rim * 0.22);
	EMISSION = cold_tint.rgb * emission_energy * (0.72 + rim * 0.48) * pulse;
	ROUGHNESS = 0.52;
}
"""

static var _shared_cold_surface_shader: Shader
static var _shared_burn_flame_texture: Texture2D

const BURN_FLAME_TEXTURE_SIZE := 64
const BURN_PARTICLE_COUNT := 8
const BURN_OUTER_COLOR := Color(1.0, 0.055, 0.018, 1.0)
const BURN_MIDDLE_COLOR := Color(1.0, 0.31, 0.035, 1.0)
const BURN_CORE_COLOR := Color(1.0, 0.83, 0.12, 1.0)

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Classification")
## Runtime target tag used by effects that can opt out of affecting airborne enemies.
@export var airborne: bool = false

@export_group("Stats")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var move_speed: float = 1.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var reward: float = 5.0
@export_range(0.05, 5.0, 0.05, "or_greater") var hit_radius: float = 0.3

@export_group("Debug Visual")
@export var debug_visual_enabled: bool = true
@export var debug_color: Color = Color(0.83, 0.20, 0.24, 1.0)
@export_range(0.1, 3.0, 0.05, "or_greater") var debug_height: float = 0.8

signal health_changed(target: CombatTarget, current_hp: float, maximum_hp: float)
signal died(target: CombatTarget, reward_amount: float)
signal movement_status_changed(
	target: CombatTarget,
	speed_multiplier: float,
	slow_remaining: float,
	freeze_remaining: float
)

var current_hp: float = 100.0
var entry_order: int = -1
var model_asset: ModelAssetDefinition
var _alive: bool = true
var _visual_root: Node3D
var _mesh_instance: MeshInstance3D
var _health_label: Label3D
var _slow_multiplier: float = 1.0
var _slow_remaining: float = 0.0
var _freeze_remaining: float = 0.0
var _burn_damage_per_second: float = 0.0
var _burn_remaining: float = 0.0
var _status_visual_elapsed: float = 0.0
var _cold_surface_material: ShaderMaterial
var _cold_surface_bindings: Array[Dictionary] = []
var _freeze_visual: MeshInstance3D
var _burn_visual: GPUParticles3D

func _ready() -> void:
	current_hp = max_hp
	if model_asset != null or debug_visual_enabled:
		_build_debug_visual()
	_build_status_visuals()
	_update_debug_status()


func _process(delta: float) -> void:
	_tick_movement_statuses(delta)
	_tick_burning(delta)

func configure_debug_target(world_position: Vector3, hp: float, speed: float, reward_amount: float) -> void:
	global_position = world_position
	max_hp = maxf(1.0, hp)
	current_hp = max_hp
	move_speed = maxf(0.0, speed)
	reward = maxf(0.0, reward_amount)
	_alive = true
	_update_debug_status()

func take_damage(amount: float) -> float:
	return _apply_damage(amount)

## Environmental damage entry that intentionally bypasses unit armor.
func take_unmitigated_damage(amount: float) -> float:
	return _apply_damage(amount)

## Continuous-damage contract. Subclasses may mitigate the rate, keeping the
## result independent from how traversal time is split across frames.
func take_damage_over_time(damage_per_second: float, duration: float) -> float:
	return _apply_damage(maxf(0.0, damage_per_second) * maxf(0.0, duration))

## Explicit environmental defeat hook. The multiplier controls only this
## target's configured reward and keeps normal combat deaths unchanged.
func defeat(reward_multiplier: float = 1.0) -> bool:
	if not feature_enabled or not _alive:
		return false
	_apply_damage(current_hp, maxf(0.0, reward_multiplier))
	return true

func _apply_damage(amount: float, reward_multiplier: float = 1.0) -> float:
	if not feature_enabled or not _alive or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_hp)
	current_hp -= applied
	health_changed.emit(self, current_hp, max_hp)
	_update_debug_status()
	if current_hp <= 0.0:
		_alive = false
		died.emit(self, reward * reward_multiplier)
		queue_free()
	return applied

func is_alive() -> bool:
	return _alive and current_hp > 0.0 and not is_queued_for_deletion()

func get_current_hp() -> float:
	return current_hp

func is_airborne_unit() -> bool:
	return airborne

func get_target_position() -> Vector3:
	return global_position + Vector3(0.0, debug_height * 0.55, 0.0)


## World point used by ground-projected target markers.
func get_target_marker_position() -> Vector3:
	return global_position + Vector3.UP * 0.025


## Applies a non-stacking movement multiplier. Reapplications keep the
## strongest slow and refresh the remaining duration.
func apply_movement_slow(speed_multiplier: float, duration: float) -> bool:
	if not feature_enabled or not is_alive() or duration <= 0.0:
		return false
	var resolved_multiplier := clampf(speed_multiplier, 0.0, 1.0)
	var was_slowed := is_movement_slowed()
	if not was_slowed:
		_slow_multiplier = resolved_multiplier
	else:
		_slow_multiplier = minf(_slow_multiplier, resolved_multiplier)
	_slow_remaining = maxf(_slow_remaining, duration)
	_update_status_visuals()
	_emit_movement_status_changed()
	return true


## Freeze suspends movement and attacks. Slow time is paused while frozen so
## the remaining cold effect resumes after thawing.
func apply_freeze(duration: float) -> bool:
	if not feature_enabled or not is_alive() or duration <= 0.0:
		return false
	_freeze_remaining = maxf(_freeze_remaining, duration)
	_update_status_visuals()
	_emit_movement_status_changed()
	return true


func get_movement_speed_multiplier() -> float:
	if is_frozen():
		return 0.0
	return _slow_multiplier if is_movement_slowed() else 1.0


func get_effective_move_speed() -> float:
	return move_speed * get_movement_speed_multiplier()


func is_movement_slowed() -> bool:
	return _slow_remaining > 0.0 and _slow_multiplier < 1.0


func is_frozen() -> bool:
	return _freeze_remaining > 0.0


func get_slow_remaining() -> float:
	return maxf(0.0, _slow_remaining)


func get_freeze_remaining() -> float:
	return maxf(0.0, _freeze_remaining)


## Burning refreshes its duration and keeps the strongest active damage rate.
## Damage is routed through take_damage_over_time so EnemyUnit armor applies.
func apply_burning(damage_per_second: float, duration: float) -> bool:
	if not feature_enabled or not is_alive() or damage_per_second <= 0.0 or duration <= 0.0:
		return false
	_burn_damage_per_second = maxf(_burn_damage_per_second, damage_per_second)
	_burn_remaining = maxf(_burn_remaining, duration)
	_ensure_burn_visual()
	_update_status_visuals()
	return true


func is_burning() -> bool:
	return _burn_remaining > 0.0 and _burn_damage_per_second > 0.0


func get_burn_remaining() -> float:
	return maxf(0.0, _burn_remaining)


func get_burn_damage_per_second() -> float:
	return maxf(0.0, _burn_damage_per_second) if is_burning() else 0.0

func _build_debug_visual() -> void:
	if model_asset != null:
		_visual_root = model_asset.instantiate_grounded_model(&"EnemyModel")
		if _visual_root != null:
			add_child(_visual_root)
	if _visual_root == null and debug_visual_enabled:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = &"DebugTargetBody"
		var mesh := CapsuleMesh.new()
		mesh.radius = hit_radius
		mesh.height = debug_height
		_mesh_instance.mesh = mesh
		_mesh_instance.position.y = debug_height * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = debug_color
		material.roughness = 0.7
		_mesh_instance.material_override = material
		add_child(_mesh_instance)
	if debug_visual_enabled:
		_health_label = Label3D.new()
		_health_label.position.y = debug_height + 0.35
		_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_health_label.no_depth_test = true
		_health_label.font_size = 28
		_health_label.modulate = Color.WHITE
		add_child(_health_label)


func _build_status_visuals() -> void:
	_cold_surface_material = ShaderMaterial.new()
	_cold_surface_material.shader = _get_cold_surface_shader()
	_cold_surface_material.set_shader_parameter(
		"cold_tint",
		Color(0.005, 0.03, 0.28, 1.0)
	)
	_cold_surface_material.set_shader_parameter("emission_energy", 0.32)
	_cold_surface_material.render_priority = 1

	_freeze_visual = MeshInstance3D.new()
	_freeze_visual.name = &"FrozenShellVisual"
	var freeze_mesh := CapsuleMesh.new()
	freeze_mesh.radius = maxf(0.06, hit_radius * 1.16)
	freeze_mesh.height = maxf(debug_height * 1.08, freeze_mesh.radius * 2.0)
	_freeze_visual.mesh = freeze_mesh
	_freeze_visual.position.y = debug_height * 0.5
	_freeze_visual.material_override = _make_status_material(
		Color(0.42, 0.9, 1.0, 0.34),
		3.8
	)
	_freeze_visual.visible = false
	add_child(_freeze_visual)



func _ensure_burn_visual() -> void:
	if _burn_visual != null and is_instance_valid(_burn_visual):
		return
	_burn_visual = create_burn_particles(hit_radius, debug_height)
	_burn_visual.name = &"BurningStatusVisual"
	add_child(_burn_visual)


## Shared factory used by burning enemies and copied burning missiles so both
## presentations retain the same cached flame texture and particle behaviour.
static func create_burn_particles(
	visual_radius: float,
	visual_height: float,
	active: bool = false
) -> GPUParticles3D:
	var radius := maxf(0.01, visual_radius)
	var height := maxf(0.01, visual_height)
	var particles := GPUParticles3D.new()
	particles.amount = BURN_PARTICLE_COUNT
	particles.lifetime = 0.72
	particles.randomness = 0.42
	particles.preprocess = 0.35
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.local_coords = true
	particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	particles.position.y = maxf(0.08, height * 0.18)
	var visual_extent := maxf(height, radius * 3.0)
	particles.visibility_aabb = AABB(
		Vector3(-visual_extent, -visual_extent * 0.4, -visual_extent),
		Vector3(visual_extent * 2.0, visual_extent * 2.2, visual_extent * 2.0)
	)
	particles.process_material = _make_burn_particle_process_material(radius, height)
	particles.draw_pass_1 = _make_burn_particle_mesh(radius, height)
	particles.emitting = active
	particles.visible = active
	return particles


func _make_status_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _tick_movement_statuses(delta: float) -> void:
	var remaining_delta := maxf(0.0, delta)
	var status_changed := false
	if _freeze_remaining > 0.0:
		var freeze_step := minf(_freeze_remaining, remaining_delta)
		_freeze_remaining = maxf(0.0, _freeze_remaining - freeze_step)
		remaining_delta = maxf(0.0, remaining_delta - freeze_step)
		status_changed = freeze_step > 0.0
	if _freeze_remaining <= 0.0 and _slow_remaining > 0.0 and remaining_delta > 0.0:
		_slow_remaining = maxf(0.0, _slow_remaining - remaining_delta)
		status_changed = true
		if _slow_remaining <= 0.0:
			_slow_multiplier = 1.0
	_status_visual_elapsed += maxf(0.0, delta)
	_update_status_visuals()
	if status_changed:
		_emit_movement_status_changed()


func _tick_burning(delta: float) -> void:
	if not is_burning():
		return
	var step := minf(_burn_remaining, maxf(0.0, delta))
	if step > 0.0:
		take_damage_over_time(_burn_damage_per_second, step)
	_burn_remaining = maxf(0.0, _burn_remaining - step)
	if _burn_remaining <= 0.0:
		_burn_damage_per_second = 0.0
	_update_status_visuals()


func _update_status_visuals() -> void:
	_update_cold_surface_material(is_movement_slowed())
	if _freeze_visual != null:
		_freeze_visual.visible = is_frozen()
		if _freeze_visual.visible:
			var shimmer := 1.0 + sin(_status_visual_elapsed * 7.0) * 0.025
			_freeze_visual.scale = Vector3.ONE * shimmer
	if _burn_visual != null:
		var burn_active := is_burning()
		if _burn_visual.visible != burn_active:
			_burn_visual.visible = burn_active
			_burn_visual.emitting = burn_active
			if burn_active:
				_burn_visual.restart()


static func _make_burn_particle_mesh(visual_radius: float, visual_height: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(
		maxf(0.12, visual_radius * 0.95),
		maxf(0.22, visual_height * 0.58)
	)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.albedo_texture = _get_burn_flame_texture()
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_texture = _get_burn_flame_texture()
	material.emission_energy_multiplier = 1.65
	material.render_priority = 2
	mesh.material = material
	return mesh


static func _make_burn_particle_process_material(
	visual_radius: float,
	visual_height: float
) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(
		maxf(0.04, visual_radius * 0.62),
		maxf(0.02, visual_height * 0.08),
		maxf(0.04, visual_radius * 0.62)
	)
	material.direction = Vector3.UP
	material.spread = 22.0
	material.initial_velocity_min = maxf(0.12, visual_height * 0.32)
	material.initial_velocity_max = maxf(0.22, visual_height * 0.58)
	material.gravity = Vector3(0.0, maxf(0.05, visual_height * 0.16), 0.0)
	material.scale_min = 0.48
	material.scale_max = 0.92
	material.angle_min = -14.0
	material.angle_max = 14.0
	material.angular_velocity_min = -28.0
	material.angular_velocity_max = 28.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.72, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color.WHITE,
		Color(1.0, 1.0, 1.0, 0.92),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	material.color_ramp = fade_texture
	return material


static func _get_burn_flame_texture() -> Texture2D:
	if _shared_burn_flame_texture != null:
		return _shared_burn_flame_texture
	var image := Image.create_empty(
		BURN_FLAME_TEXTURE_SIZE,
		BURN_FLAME_TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	var antialias_width := 2.0 / float(BURN_FLAME_TEXTURE_SIZE)
	for pixel_y in range(BURN_FLAME_TEXTURE_SIZE):
		var vertical := 1.0 - float(pixel_y) / float(BURN_FLAME_TEXTURE_SIZE - 1)
		for pixel_x in range(BURN_FLAME_TEXTURE_SIZE):
			var horizontal := (
				float(pixel_x) / float(BURN_FLAME_TEXTURE_SIZE - 1) * 2.0 - 1.0
			)
			var outer := _sample_flame_layer(
				horizontal,
				vertical,
				0.82,
				1.0,
				0.17,
				0.0,
				antialias_width
			)
			if outer <= 0.0:
				image.set_pixel(pixel_x, pixel_y, Color.TRANSPARENT)
				continue
			var middle := _sample_flame_layer(
				horizontal,
				vertical,
				0.54,
				0.73,
				-0.09,
				1.7,
				antialias_width
			) * outer
			var core := _sample_flame_layer(
				horizontal,
				vertical,
				0.30,
				0.43,
				0.055,
				3.1,
				antialias_width
			) * outer
			var color := BURN_OUTER_COLOR
			color = color.lerp(BURN_MIDDLE_COLOR, middle)
			color = color.lerp(BURN_CORE_COLOR, core)
			color.a = outer
			image.set_pixel(pixel_x, pixel_y, color)
	_shared_burn_flame_texture = ImageTexture.create_from_image(image)
	return _shared_burn_flame_texture


static func _sample_flame_layer(
	horizontal: float,
	vertical: float,
	base_width: float,
	top: float,
	bend: float,
	phase: float,
	antialias_width: float
) -> float:
	if vertical < 0.0 or vertical > top:
		return 0.0
	var progress := clampf(vertical / maxf(0.001, top), 0.0, 1.0)
	var bottom_rounding := smoothstep(0.0, 0.08, progress)
	var taper := pow(maxf(0.0, 1.0 - progress), 0.62)
	var edge_wobble := 0.88 + sin(progress * 8.4 + phase) * 0.12
	var half_width := base_width * taper * edge_wobble * bottom_rounding
	var center := bend * sin(progress * PI * 1.2) * pow(progress, 1.45)
	var edge_distance := half_width - absf(horizontal - center)
	return smoothstep(-antialias_width, antialias_width, edge_distance)


func debug_get_burn_particles() -> GPUParticles3D:
	return _burn_visual


func debug_get_burn_flame_texture() -> Texture2D:
	return _get_burn_flame_texture()


func debug_get_cold_surface_material() -> ShaderMaterial:
	return _cold_surface_material


func debug_get_cold_surface_mesh_count() -> int:
	var count := 0
	for binding in _cold_surface_bindings:
		var mesh := binding.get("mesh") as MeshInstance3D
		if (
			mesh != null
			and is_instance_valid(mesh)
			and mesh.material_override == _cold_surface_material
		):
			count += 1
	return count


func _update_cold_surface_material(is_active: bool) -> void:
	if is_active:
		if _cold_surface_bindings.is_empty():
			_bind_cold_surface_material()
		return
	_restore_cold_surface_materials()


func _bind_cold_surface_material() -> void:
	if _cold_surface_material == null:
		return
	var meshes: Array[MeshInstance3D] = []
	if _visual_root != null and is_instance_valid(_visual_root):
		_collect_model_meshes(_visual_root, meshes)
	elif _mesh_instance != null and is_instance_valid(_mesh_instance):
		meshes.append(_mesh_instance)
	for mesh in meshes:
		_cold_surface_bindings.append({
			"mesh": mesh,
			"previous_material_override": mesh.material_override,
		})
		mesh.material_override = _cold_surface_material


func _restore_cold_surface_materials() -> void:
	for binding in _cold_surface_bindings:
		var mesh := binding.get("mesh") as MeshInstance3D
		if (
			mesh == null
			or not is_instance_valid(mesh)
			or mesh.material_override != _cold_surface_material
		):
			continue
		mesh.material_override = binding.get("previous_material_override") as Material
	_cold_surface_bindings.clear()


func _collect_model_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_model_meshes(child, meshes)


func _get_cold_surface_shader() -> Shader:
	if _shared_cold_surface_shader == null:
		_shared_cold_surface_shader = Shader.new()
		_shared_cold_surface_shader.code = COLD_SURFACE_SHADER_CODE
	return _shared_cold_surface_shader


func _emit_movement_status_changed() -> void:
	movement_status_changed.emit(
		self,
		get_movement_speed_multiplier(),
		get_slow_remaining(),
		get_freeze_remaining()
	)

func _update_debug_status() -> void:
	if _health_label != null:
		_health_label.text = "%d/%d" % [ceili(current_hp), ceili(max_hp)]
