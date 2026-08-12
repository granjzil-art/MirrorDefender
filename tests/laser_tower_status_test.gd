extends SceneTree

const ContinuousLaserPathScript := preload("res://scripts/combat/ContinuousLaserPath.gd")
const ContinuousLaserVisualScript := preload("res://scripts/combat/ContinuousLaserVisual.gd")


class TestLaserBuilding:
	extends Node

	var level: int = 2
	var combat_manager: CombatManager
	var burst_notifications: int = 0
	var last_segments: Array = []
	var last_endpoint: Vector3 = Vector3.ZERO
	var propagation_speed: float = 4.0
	var penetration_count: int = 8
	var laser_dps: float = 10.0

	func get_combat_manager() -> CombatManager:
		return combat_manager

	func get_attack_origin() -> Vector3:
		return Vector3.ZERO

	func get_laser_end() -> Vector3:
		return Vector3.RIGHT * 4.0

	func get_attack_range_world() -> float:
		return 4.0

	func get_projectile_penetration_count() -> int:
		return penetration_count

	func get_laser_damage_per_second() -> float:
		return laser_dps

	func get_laser_propagation_speed_world() -> float:
		return propagation_speed

	func get_laser_slow_multiplier() -> float:
		return 0.4

	func get_laser_slow_duration() -> float:
		return 3.0

	func get_laser_burst_interval() -> float:
		return 3.0

	func get_laser_burst_radius_world() -> float:
		return 1.0

	func get_laser_burst_damage() -> float:
		return 15.0

	func get_laser_freeze_duration() -> float:
		return 3.0

	func get_attack_color() -> Color:
		return Color(0.2, 0.9, 1.0, 1.0)

	func affects_target(_target: Node) -> bool:
		return true

	func show_attack_path(segments: Array, endpoint: Vector3) -> void:
		last_segments = segments
		last_endpoint = endpoint

	func clear_attack_visual() -> void:
		last_segments.clear()

	func notify_copy_attack(
		attack_kind: StringName,
		_world_start: Vector3,
		_world_end: Vector3,
		_damage: float
	) -> void:
		if attack_kind == &"laser_burst":
			burst_notifications += 1

	func notify_attack(
		_target: CombatTarget,
		_damage: float,
		_continuous: bool
	) -> void:
		pass


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[LaserTowerStatus] running")
	_test_production_configuration()
	_test_finite_penetration_and_cold()
	_test_cold_surface_shader_visual()
	_test_reflected_path()
	_test_propagating_logical_endpoint()
	_test_pulse_style_beam_presentation()
	_test_burst_timing_and_freeze_resume()
	await process_frame
	if _failures == 0:
		print("[LaserTowerStatus] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[LaserTowerStatus] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_configuration() -> void:
	var definition := load("res://resources/buildings/LaserTower.tres") as BuildingDefinition
	_expect(definition != null and definition.validate_configuration().is_empty(), "production LaserTower parameters validate")
	if definition == null:
		return
	var level_one := definition.get_level_stats(1)
	var level_two := definition.get_level_stats(2)
	var level_three := definition.get_level_stats(3)
	_expect(
		level_one != null
		and is_equal_approx(level_one.laser_slow_multiplier, 0.4)
		and is_equal_approx(level_one.laser_slow_duration, 3.0)
		and level_one.laser_beam_color.r > 0.8
		and level_one.laser_beam_color.b > level_one.laser_beam_color.r
		and level_one.laser_beam_width > 0.0
		and level_one.laser_beam_emission_energy > 0.0
		and level_one.laser_propagation_speed > 0.0,
		"level 1 configures cold plus adjustable milky-blue beam presentation and propagation"
	)
	_expect(
		level_two != null
		and is_equal_approx(level_two.laser_burst_interval, 3.0)
		and is_equal_approx(level_two.laser_burst_radius, 1.0)
		and level_two.base_damage > 0.0,
		"level 2 configures a damaging three-second one-cell first-hit burst"
	)
	_expect(
		level_three != null and is_equal_approx(level_three.laser_freeze_duration, 3.0),
		"level 3 configures a three-second freeze"
	)


func _test_finite_penetration_and_cold() -> void:
	var fixture := _make_combat_fixture()
	var host: Node3D = fixture.host
	var combat: CombatManager = fixture.combat
	var building := TestLaserBuilding.new()
	host.add_child(building)
	building.combat_manager = combat
	var first := _spawn_target(combat, Vector3(1.0, 0.0, 0.0))
	var second := _spawn_target(combat, Vector3(2.0, 0.0, 0.0))
	var third := _spawn_target(combat, Vector3(3.0, 0.0, 0.0))
	var path := ContinuousLaserPathScript.trace(
		combat,
		building,
		Vector3.ZERO,
		Vector3.RIGHT,
		4.0,
		1
	)
	var hits: Array = path.get("hits", [])
	_expect(hits.size() == 2, "penetration count 1 hits the first two enemies")
	_expect(path.get("termination") == &"enemy", "the second hit terminates the finite beam")
	var endpoint: Vector3 = path.get("endpoint", Vector3.ZERO)
	_expect(endpoint.x < second.global_position.x, "beam endpoint is the blocking enemy contact point")
	LaserAttackStrategy.apply_continuous_hits(building, path, 10.0, 1.0, false)
	_expect(is_equal_approx(first.current_hp, 90.0) and is_equal_approx(second.current_hp, 90.0), "every traversed enemy receives continuous damage")
	_expect(is_equal_approx(third.current_hp, 100.0), "enemies beyond the penetration stop remain unharmed")
	_expect(first.is_movement_slowed() and is_equal_approx(first.get_movement_speed_multiplier(), 0.4), "continuous contact applies the configured cold slow")
	_expect(
		first.get_node_or_null("ColdSlowVisual") == null,
		"cold slow no longer creates a blue ring under the target"
	)
	host.queue_free()


func _test_cold_surface_shader_visual() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var target := CombatTarget.new()
	target.debug_visual_enabled = true
	target.debug_color = Color(0.82, 0.18, 0.12, 1.0)
	host.add_child(target)
	target.configure_debug_target(Vector3.ZERO, 100.0, 1.0, 0.0)
	var body := target.get_node_or_null("DebugTargetBody") as MeshInstance3D
	var original_material: Material = body.material_override if body != null else null
	var original_overlay: Material = body.material_overlay if body != null else null
	_expect(target.apply_movement_slow(0.4, 3.0), "visible target accepts the cold effect")
	var cold_material := target.debug_get_cold_surface_material()
	_expect(
		body != null
		and cold_material != null
		and body.material_override == cold_material
		and target.debug_get_cold_surface_mesh_count() == 1,
		"cold applies one ShaderMaterial directly to the target model surface"
	)
	var cold_tint: Color = (
		cold_material.get_shader_parameter("cold_tint")
		if cold_material != null
		else Color.WHITE
	)
	_expect(
		cold_material != null
		and cold_tint.b > cold_tint.g
		and cold_tint.g > cold_tint.r
		and cold_material.shader.code.contains("TIME * 2.4")
		and body.material_overlay == original_overlay,
		"cold uses an animated deep-blue shader without mutating the model's overlay channel"
	)
	target._process(3.0)
	_expect(
		not target.is_movement_slowed()
		and body.material_override == original_material
		and body.material_overlay == original_overlay
		and target.debug_get_cold_surface_mesh_count() == 0,
		"cold expiry restores the model's previous material override"
	)
	var grunt_definition := load("res://resources/enemies/Grunt.tres") as EnemyDefinition
	var model_target := CombatTarget.new()
	model_target.debug_visual_enabled = false
	model_target.model_asset = grunt_definition.get_model_asset() if grunt_definition != null else null
	model_target.debug_height = grunt_definition.body_height if grunt_definition != null else 0.8
	model_target.hit_radius = grunt_definition.hit_radius if grunt_definition != null else 0.3
	host.add_child(model_target)
	model_target.apply_movement_slow(0.4, 3.0)
	_expect(
		grunt_definition != null
		and model_target.debug_get_cold_surface_mesh_count() > 0
		and model_target.get_node_or_null("ColdSlowVisual") == null,
		"production enemy model meshes receive the cold surface shader without a foot ring"
	)
	host.queue_free()


func _test_reflected_path() -> void:
	var fixture := _make_combat_fixture()
	var host: Node3D = fixture.host
	var combat: CombatManager = fixture.combat
	var building := TestLaserBuilding.new()
	host.add_child(building)
	building.combat_manager = combat
	var reflected_target := _spawn_target(combat, Vector3(2.0, 0.0, 1.0))
	var path := ContinuousLaserPathScript.trace(
		combat,
		building,
		Vector3.ZERO,
		Vector3.RIGHT,
		5.0,
		8,
		Callable(self, "_trace_test_reflector")
	)
	var segments: Array = path.get("segments", [])
	var hits: Array = path.get("hits", [])
	_expect(segments.size() == 2, "continuous laser builds a second segment after reflection")
	_expect(not hits.is_empty() and hits[0].get("target") == reflected_target, "reflected segment participates in the same enemy query")
	host.queue_free()


func _test_propagating_logical_endpoint() -> void:
	var fixture := _make_combat_fixture()
	var host: Node3D = fixture.host
	var combat: CombatManager = fixture.combat
	var building := TestLaserBuilding.new()
	host.add_child(building)
	building.combat_manager = combat
	building.level = 1
	building.propagation_speed = 1.0
	building.penetration_count = 0
	var blocker := _spawn_target(combat, Vector3(1.5, 0.0, 0.0))
	var strategy := LaserAttackStrategy.new()
	strategy.tick(building, 0.5)
	_expect(
		is_equal_approx(building.last_endpoint.x, 0.5) and is_equal_approx(blocker.current_hp, 100.0),
		"beam damage endpoint visibly propagates instead of appearing at full range"
	)
	strategy.tick(building, 0.75)
	var blocked_endpoint := building.last_endpoint.x
	_expect(
		blocked_endpoint > 0.9
		and blocked_endpoint < blocker.global_position.x
		and is_equal_approx(strategy.debug_get_propagation_distance(), blocked_endpoint),
		"finite-penetration enemy clamps the stored propagation front to its contact point"
	)
	blocker.take_damage(blocker.current_hp)
	strategy.tick(building, 0.25)
	_expect(
		building.last_endpoint.x > blocked_endpoint
		and building.last_endpoint.x < blocked_endpoint + 0.3,
		"beam resumes gradual growth from the old endpoint after its blocking enemy disappears"
	)
	host.queue_free()


func _test_pulse_style_beam_presentation() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var visual := ContinuousLaserVisualScript.new()
	host.add_child(visual)
	var expected_color := Color(0.88, 0.96, 1.0, 0.96)
	visual.configure(expected_color, 0.12, 4.5)
	visual.show_path(
		[{"start": Vector3.ZERO, "end": Vector3.RIGHT * 2.0}],
		Vector3.RIGHT * 2.0
	)
	var segment := visual.get_node_or_null("ContinuousLaserSegment0") as MeshInstance3D
	var material := visual.debug_get_beam_material()
	_expect(
		segment != null and segment.mesh is BoxMesh and is_equal_approx((segment.mesh as BoxMesh).size.x, 0.12),
		"continuous beam uses the same adjustable volumetric BoxMesh style as pulse laser"
	)
	_expect(
		material != null
		and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and material.emission_enabled
		and material.albedo_color.is_equal_approx(expected_color)
		and is_equal_approx(material.emission_energy_multiplier, 4.5),
		"continuous beam exposes the configured milky-blue color and emission strength"
	)
	var left_wave := visual.get_node_or_null("ContinuousLaserWaveLeft0") as MeshInstance3D
	var right_wave := visual.get_node_or_null("ContinuousLaserWaveRight0") as MeshInstance3D
	_expect(
		left_wave != null
		and right_wave != null
		and left_wave.visible
		and right_wave.visible
		and visual.debug_get_wave_pair_count() == 1,
		"continuous beam adds two visible wave filaments around every main-axis segment"
	)
	var left_wave_mesh := left_wave.mesh as BoxMesh if left_wave != null else null
	var left_wave_material := (
		left_wave.material_override as ShaderMaterial
		if left_wave != null
		else null
	)
	var right_wave_material := (
		right_wave.material_override as ShaderMaterial
		if right_wave != null
		else null
	)
	_expect(
		left_wave_mesh != null
		and left_wave_mesh.size.x < visual.debug_get_beam_width()
		and left_wave_mesh.subdivide_depth >= 8,
		"wave filaments stay thinner than the main axis and contain enough vertices to bend smoothly"
	)
	_expect(
		left_wave_material != null
		and right_wave_material != null
		and float(left_wave_material.get_shader_parameter("side_offset")) < 0.0
		and float(right_wave_material.get_shader_parameter("side_offset")) > 0.0
		and is_equal_approx(
			absf(float(left_wave_material.get_shader_parameter("side_offset"))),
			float(right_wave_material.get_shader_parameter("side_offset"))
		),
		"the two sine curves are symmetric translations that bracket the main axis"
	)
	_expect(
		left_wave_material != null
		and float(left_wave_material.get_shader_parameter("wave_amplitude")) > 0.0
		and float(left_wave_material.get_shader_parameter("noise_amplitude")) > 0.0
		and float(left_wave_material.get_shader_parameter("wave_angular_speed")) > 0.0
		and left_wave_material.shader.code.contains("TIME * wave_angular_speed"),
		"the filament shader combines sine movement, non-zero noise, and continuously advancing time"
	)
	visual.show_path(
		[
			{"start": Vector3.ZERO, "end": Vector3.RIGHT},
			{"start": Vector3.RIGHT, "end": Vector3.RIGHT + Vector3.FORWARD},
		],
		Vector3.RIGHT + Vector3.FORWARD
	)
	var reflected_wave := visual.get_node_or_null("ContinuousLaserWaveLeft1") as MeshInstance3D
	var reflected_wave_material := (
		reflected_wave.material_override as ShaderMaterial
		if reflected_wave != null
		else null
	)
	_expect(
		visual.debug_get_wave_pair_count() == 2
		and reflected_wave_material != null
		and is_equal_approx(
			float(reflected_wave_material.get_shader_parameter("path_distance_offset")),
			1.0
		),
		"reflected visual segments continue the travelling wave phase from accumulated path distance"
	)
	visual.clear_path()
	_expect(
		visual.debug_get_wave_pair_count() == 0
		and not left_wave.visible
		and not right_wave.visible,
		"clearing the continuous beam hides the main path's companion wave filaments"
	)
	host.queue_free()


func _test_burst_timing_and_freeze_resume() -> void:
	var fixture := _make_combat_fixture()
	var host: Node3D = fixture.host
	var combat: CombatManager = fixture.combat
	var building := TestLaserBuilding.new()
	host.add_child(building)
	building.combat_manager = combat
	building.laser_dps = 0.0
	var empty_strategy := LaserAttackStrategy.new()
	empty_strategy.tick(building, 3.0)
	_expect(_find_burst_visual(combat) == null, "burst does not fall back to the endpoint when no enemy is hit")
	building.burst_notifications = 0
	var target := _spawn_target(combat, Vector3(2.0, 0.0, 0.0))
	var endpoint_target := _spawn_target(combat, Vector3(4.0, 0.0, 0.0))
	var strategy := LaserAttackStrategy.new()
	strategy.tick(building, 2.9)
	_expect(is_equal_approx(target.current_hp, 100.0) and building.burst_notifications == 0, "level 2 waits for the complete burst interval")
	strategy.tick(building, 0.1)
	_expect(is_equal_approx(target.current_hp, 85.0) and building.burst_notifications == 1, "first-hit burst deals one-time damage and notifies copies")
	_expect(is_equal_approx(endpoint_target.current_hp, 100.0), "burst no longer uses the laser endpoint")
	_expect(target.is_movement_slowed() and not target.is_frozen(), "level 2 burst applies the normal cold effect without freezing")
	var first_hit_visual := _find_burst_visual(combat)
	_expect(
		first_hit_visual != null
		and is_equal_approx(first_hit_visual.global_position.x, target.get_target_position().x)
		and is_equal_approx(first_hit_visual.global_position.z, target.get_target_position().z),
		"burst visual is centered on the first enemy hit by the beam"
	)
	building.level = 3
	LaserAttackStrategy.apply_endpoint_burst(building, combat, target.get_target_position(), false)
	_expect(target.is_frozen(), "level 3 first-hit burst freezes enemies in its circle")
	var freeze_visual := target.get_node_or_null("FrozenShellVisual") as MeshInstance3D
	_expect(freeze_visual != null and freeze_visual.visible, "freeze enables its visible ice shell")
	target._process(3.0)
	_expect(not target.is_frozen() and target.is_movement_slowed(), "slow duration is preserved while frozen and resumes after thawing")
	_expect(_find_burst_visual(combat) != null, "first-hit burst creates the expanding visual effect")
	host.queue_free()


func _trace_test_reflector(start: Vector3, end: Vector3) -> Dictionary:
	if start.x >= 2.0 or end.x < 2.0 or end.x <= start.x:
		return {"hit": false}
	var fraction := (2.0 - start.x) / (end.x - start.x)
	var position := start.lerp(end, fraction)
	return {
		"hit": true,
		"position": position,
		"normal": Vector3(-1.0, 0.0, 1.0).normalized(),
		"distance": start.distance_to(position),
		"epsilon": 0.001,
	}


func _make_combat_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var combat := CombatManager.new()
	host.add_child(combat)
	return {"host": host, "combat": combat}


func _spawn_target(combat: CombatManager, world_position: Vector3) -> CombatTarget:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat.add_child(target)
	target.configure_debug_target(world_position, 100.0, 1.0, 0.0)
	combat.register_target(target)
	return target


func _find_burst_visual(combat: CombatManager) -> LaserBurstEffect:
	for child in combat.get_children():
		if child is LaserBurstEffect:
			return child
	return null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
