## Short-lived, self-cleaning particle burst used for enemy damage feedback.
class_name EnemyHitParticles
extends GPUParticles3D

const BURST_LIFETIME := 0.42


func configure(
	particle_color: Color,
	emission_brightness: float,
	particle_size: float,
	particle_count: int,
	emission_radius: float
) -> void:
	name = &"EnemyHitParticles"
	amount = maxi(1, particle_count)
	lifetime = BURST_LIFETIME
	one_shot = true
	explosiveness = 1.0
	randomness = 0.72
	local_coords = true
	var visibility_radius := maxf(2.0, emission_radius + 1.5)
	visibility_aabb = AABB(
		Vector3.ONE * -visibility_radius,
		Vector3.ONE * visibility_radius * 2.0
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = maxf(0.01, emission_radius)
	particle_material.direction = Vector3.UP
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 0.85
	particle_material.initial_velocity_max = 1.75
	particle_material.gravity = Vector3(0.0, -2.4, 0.0)
	particle_material.damping_min = 0.3
	particle_material.damping_max = 0.8
	particle_material.scale_min = 0.65
	particle_material.scale_max = 1.25
	process_material = particle_material

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * maxf(0.005, particle_size)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = particle_color
	material.emission_enabled = emission_brightness > 0.0
	material.emission = particle_color
	material.emission_energy_multiplier = maxf(0.0, emission_brightness)
	quad.material = material
	draw_pass_1 = quad


func start() -> void:
	restart()
	emitting = true
	get_tree().create_timer(BURST_LIFETIME + 0.2).timeout.connect(_finish)


func _finish() -> void:
	if is_instance_valid(self):
		queue_free()
