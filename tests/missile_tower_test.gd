extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0
var _last_projectile: Projectile
var _reflection_enabled: bool = false
var _blocker_enabled: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[MissileTower] running")
	_test_production_configuration()
	var fixture := _make_fixture()
	_test_airborne_priority(fixture)
	await _test_targeted_missile(fixture)
	await _test_directional_airborne_direct_hit(fixture)
	await _test_range_explosion(fixture)
	await _test_reflection_and_stuff(fixture)
	await _test_mirror_special_effects(fixture)
	await _test_source_removal(fixture)
	var host := fixture.get("host") as Node
	if host != null and is_instance_valid(host):
		host.queue_free()
	await process_frame
	if _failures == 0:
		print("[MissileTower] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MissileTower] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_configuration() -> void:
	var missile_tower := load("res://resources/buildings/CrossbowTower.tres") as BuildingDefinition
	var arrow_tower := load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition
	_expect(missile_tower != null and missile_tower.display_name == "导弹塔", "the former crossbow slot is presented as the missile tower")
	if missile_tower != null:
		var expected_explosion_radii := [1.3, 1.7, 2.0]
		for level_index in range(1, missile_tower.get_max_level() + 1):
			var stats := missile_tower.get_level_stats(level_index)
			_expect(stats.projectile_is_missile, "missile level %d uses explosive missile projectiles" % level_index)
			_expect(stats.prioritizes_airborne, "missile level %d prioritizes airborne targets" % level_index)
			_expect(
				is_equal_approx(
					stats.missile_explosion_radius,
					expected_explosion_radii[level_index - 1]
				),
				"missile level %d keeps its configured numeric explosion-radius upgrade" % level_index
			)
	_expect(arrow_tower != null, "arrow tower production definition loads")
	if arrow_tower != null:
		for level_index in range(1, arrow_tower.get_max_level() + 1):
			_expect(arrow_tower.get_level_stats(level_index).prioritizes_airborne, "arrow level %d shares airborne-first targeting" % level_index)


func _test_airborne_priority(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var ground := _make_target(combat, Vector3(0.5, 0.0, 0.0), false)
	_expect(building.acquire_target() == ground, "locked targeting initially accepts a ground enemy when no flyer exists")
	var flyer := _make_target(combat, Vector3(2.5, 3.0, 0.0), true)
	_expect(building.acquire_target() == flyer, "an airborne enemy immediately preempts the locked ground target")
	_remove_target(combat, ground)
	_remove_target(combat, flyer)


func _test_targeted_missile(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var target := _make_target(combat, Vector3(2.0, 0.0, 0.0), false)
	_last_projectile = null
	building._process(1.0)
	var airborne_splash := _make_target(combat, Vector3(2.7, 5.0, 1.0), true)
	var missile := _last_projectile as MissileProjectile
	_expect(missile != null and missile.is_orbiting(), "a targeted tower shot starts as a missile in its collision-free launch loop")
	if missile == null:
		_remove_target(combat, target)
		_remove_target(combat, airborne_splash)
		return
	_expect(
		missile.debug_get_burning_particles() == null,
		"ordinary missiles do not allocate the copied burning particle presentation"
	)
	_expect(not missile.is_ballistic(), "the targeted missile retains its marked homing target")
	_expect(absi(missile.get_orbit_direction_sign()) == 1, "each missile chooses a valid clockwise or counter-clockwise loop")
	var marker := missile.get_target_marker()
	_expect(marker != null and marker.get_node_or_null("AimTexture") != null, "the supplied aim texture is shown beneath the marked target")
	var initial_marker_position := marker.global_position if marker != null else Vector3.ZERO
	target.global_position.z = 1.0
	if marker != null:
		marker._process(0.02)
	_expect(marker != null and marker.global_position.z > initial_marker_position.z + 0.5, "the aim marker follows target movement during the launch loop")
	var target_hp := target.current_hp
	missile._process(0.1)
	_expect(is_equal_approx(target.current_hp, target_hp), "the launch loop performs no collision or damage checks")
	missile._process(0.1)
	_expect(not missile.is_orbiting(), "the missile enters powered flight after exactly one loop")
	for _step in range(200):
		if missile.is_queued_for_deletion() or target.current_hp < target_hp:
			break
		missile._process(0.02)
	_expect(is_equal_approx(target.current_hp, target_hp - 20.0), "the contacted enemy receives one explosion damage instance without direct-hit duplication")
	_expect(is_equal_approx(airborne_splash.current_hp, 80.0), "the same horizontal explosion damages an airborne enemy despite its height")
	var has_explosion_visual := false
	var has_trail := false
	var explosion_visual: MissileExplosionEffect
	for child in combat.get_children():
		has_explosion_visual = has_explosion_visual or child is MissileExplosionEffect
		if child is MissileExplosionEffect:
			explosion_visual = child as MissileExplosionEffect
		has_trail = has_trail or child is MissileTrail
	_expect(has_explosion_visual, "impact spawns the programmatic explosion presentation")
	_expect(
		explosion_visual != null
		and explosion_visual.get_node_or_null("MissileExplosionOuterRed") != null
		and explosion_visual.get_node_or_null("MissileExplosionMiddleOrange") != null
		and explosion_visual.get_node_or_null("MissileExplosionInnerYellow") != null
		and explosion_visual.debug_get_fire_wave_colors() == [
			MissileExplosionEffect.FIRE_RED,
			MissileExplosionEffect.FIRE_ORANGE,
			MissileExplosionEffect.FIRE_YELLOW,
		],
		"explosion pressure wave uses concentric red, orange, and yellow fire layers"
	)
	_expect(has_trail, "missile movement owns a fading programmatic trail")
	_remove_target(combat, target)
	_remove_target(combat, airborne_splash)
	await process_frame


func _test_range_explosion(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var endpoint_target := _make_target(combat, Vector3(0.7, 4.0, 4.0), true)
	_last_projectile = building.launch_directional_projectile(20.0, Vector3.BACK)
	var missile := _last_projectile as MissileProjectile
	_expect(missile != null and missile.is_ballistic(), "an untracked facing shot stays ballistic after its launch loop")
	if missile != null:
		missile._process(1.0)
	_expect(is_equal_approx(endpoint_target.current_hp, 80.0), "reaching maximum flight distance triggers a one-cell explosion")
	_remove_target(combat, endpoint_target)
	await process_frame


func _test_directional_airborne_direct_hit(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var origin := building.get_attack_origin()
	var airborne_target := _make_target(
		combat,
		Vector3(origin.x, origin.y + 4.0, origin.z + 2.0),
		true
	)
	_last_projectile = building.launch_directional_projectile(20.0, Vector3.BACK)
	var missile := _last_projectile as MissileProjectile
	if missile != null:
		missile._process(0.5)
	_expect(
		is_equal_approx(airborne_target.current_hp, 80.0),
		"no-target directional missile directly contacts an airborne enemy on its combat-plane path"
	)
	_remove_target(combat, airborne_target)
	await process_frame


func _test_reflection_and_stuff(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	combat.set_projectile_reflection_resolver(Callable(self, "_trace_reflection"))
	combat.set_projectile_blocker_resolver(Callable(self, "_trace_blocker"))
	_reflection_enabled = true
	_blocker_enabled = false
	var reflected := building.launch_directional_projectile(20.0, Vector3.BACK) as MissileProjectile
	if reflected != null:
		reflected._process(0.34)
	_expect(reflected != null and reflected.has_reflected(), "reflect-mirror/acrylic query hits reflect the missile without exploding it")
	_expect(reflected != null and not reflected.is_queued_for_deletion(), "reflection leaves the missile active")
	if reflected != null:
		reflected.queue_free()
	await process_frame


func _test_mirror_special_effects(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var copy_definition := load("res://resources/mirrors/CopyMirror.tres") as CopyMirrorDefinition
	var reflect_definition := load("res://resources/mirrors/ReflectMirror.tres") as ReflectMirrorDefinition
	_expect(copy_definition != null and reflect_definition != null, "missile mirror-effect resources load")
	if copy_definition == null or reflect_definition == null:
		return

	var origin := Vector3(10.0, 1.0, 10.0)
	var burning_target := _make_target(combat, origin + Vector3(1.4, -1.0, 0.0), false)
	_expect(
		burning_target.debug_get_burn_particles() == null,
		"non-burning enemies do not allocate a GPU particle system"
	)
	var burn_payload := AttackEffectPayload.new()
	burn_payload.set_copy_upgrade_count(1)
	copy_definition.apply_copy_attack_effects(
		burn_payload,
		2,
		{"copy_kind": &"crossbow_tower", "copy_upgrade_count": 1}
	)
	var burning_effect := burn_payload.get_effect_resource(&"burning_missile")
	var configured_burn_ratio := float(burning_effect.get("damage_per_second_ratio"))
	var configured_burn_duration := float(burning_effect.get("burn_duration"))
	var burning_missile := combat.spawn_directional_missile(
		origin,
		Vector3.RIGHT,
		10.0,
		20.0,
		4.0,
		0.2,
		0.05,
		Color.ORANGE_RED,
		null,
		building,
		building.get_missile_configuration(),
		burn_payload
	)
	var missile_burn_particles := (
		burning_missile.debug_get_burning_particles()
		if burning_missile != null
		else null
	)
	var missile_flame_texture: Texture2D
	if missile_burn_particles != null and missile_burn_particles.draw_pass_1 is QuadMesh:
		var flame_mesh := missile_burn_particles.draw_pass_1 as QuadMesh
		var flame_material := flame_mesh.material as StandardMaterial3D
		if flame_material != null:
			missile_flame_texture = flame_material.albedo_texture
	_expect(
		missile_burn_particles != null
		and missile_burn_particles.visible
		and missile_burn_particles.emitting
		and missile_burn_particles.amount == CombatTarget.BURN_PARTICLE_COUNT
		and missile_flame_texture == burning_target.debug_get_burn_flame_texture(),
		"copied burning missiles reuse the enemy burn particle presentation and cached flame texture"
	)
	if burning_missile != null:
		burning_missile._explode()
	var burn_particles := burning_target.debug_get_burn_particles()
	_expect(
		is_equal_approx(burning_target.current_hp, 100.0)
		and burning_target.is_burning()
		and is_equal_approx(
			burning_target.get_burn_damage_per_second(),
			20.0 * configured_burn_ratio
		)
		and burn_particles != null
		and burn_particles.visible
		and burn_particles.emitting
		and burn_particles.amount == CombatTarget.BURN_PARTICLE_COUNT
		and burn_particles.draw_pass_1 is QuadMesh
		and burning_target.debug_get_burn_flame_texture() != null,
		"one L2 copy ignites the independent area using the configured explosion-damage ratio"
	)
	burning_target._process(1.0)
	_expect(
		is_equal_approx(
			burning_target.current_hp,
			100.0 - 20.0 * configured_burn_ratio
		)
		and is_equal_approx(
			burning_target.get_burn_remaining(),
			maxf(0.0, configured_burn_duration - 1.0)
		),
		"burning deals continuous damage and consumes its configured duration"
	)
	var stronger_missile := combat.spawn_directional_missile(
		origin,
		Vector3.RIGHT,
		10.0,
		40.0,
		4.0,
		0.2,
		0.05,
		Color.ORANGE_RED,
		null,
		building,
		building.get_missile_configuration(),
		burn_payload.instantiate_attack()
	)
	if stronger_missile != null:
		stronger_missile._explode()
	_expect(
		is_equal_approx(
			burning_target.get_burn_damage_per_second(),
			40.0 * configured_burn_ratio
		)
		and is_equal_approx(burning_target.get_burn_remaining(), configured_burn_duration),
		"repeat ignition refreshes duration and keeps the stronger damage rate"
	)

	var expanded_target := _make_target(combat, origin + Vector3(2.1, -1.0, 0.0), false)
	var expanded_payload := burn_payload.instantiate_attack()
	expanded_payload.set_copy_upgrade_count(3)
	var expanded_missile := combat.spawn_directional_missile(
		origin,
		Vector3.RIGHT,
		10.0,
		20.0,
		4.0,
		0.2,
		0.05,
		Color.ORANGE_RED,
		null,
		building,
		building.get_missile_configuration(),
		expanded_payload
	)
	if expanded_missile != null:
		expanded_missile._explode()
	_expect(
		expanded_target.is_burning()
		and is_equal_approx(expanded_target.current_hp, 100.0)
		and expanded_target.debug_get_burn_flame_texture()
			== burning_target.debug_get_burn_flame_texture(),
		"three L2 copies expand only the burn radius to 2.25 cells, independent of explosion radius"
	)
	var short_burn_target := _make_target(combat, origin + Vector3(0.0, -1.0, 3.0), false)
	short_burn_target.apply_burning(1.0, 0.05)
	short_burn_target._process(0.06)
	var expired_particles := short_burn_target.debug_get_burn_particles()
	_expect(
		not short_burn_target.is_burning()
		and expired_particles != null
		and not expired_particles.visible
		and not expired_particles.emitting,
		"fire particles stop immediately when the burn duration ends"
	)

	var growth_payload := AttackEffectPayload.new()
	var upgraded_hit := {
		"is_upgraded_reflect_mirror": true,
		"attack_effects": reflect_definition.get_attack_effects(2),
	}
	var growth_missile := combat.spawn_directional_missile(
		origin,
		Vector3.RIGHT,
		10.0,
		20.0,
		4.0,
		0.2,
		0.05,
		Color.ORANGE_RED,
		null,
		building,
		building.get_missile_configuration(),
		growth_payload
	)
	if growth_missile != null:
		growth_payload.record_successful_reflection(upgraded_hit)
		growth_payload.apply_reflection_effects(
			upgraded_hit,
			{"attack_kind": &"missile", "projectile": growth_missile}
		)
	_expect(
		growth_missile != null
		and is_equal_approx(growth_missile.get_mirror_visual_scale(), 1.15)
		and is_equal_approx(growth_missile.get_explosion_radius(), 1.1),
		"one L2 reflection enlarges missile visuals by 15% and explosion radius by 10%"
	)
	if growth_missile != null:
		growth_payload.record_successful_reflection(upgraded_hit)
		growth_payload.apply_reflection_effects(
			upgraded_hit,
			{"attack_kind": &"missile", "projectile": growth_missile}
		)
	_expect(
		growth_missile != null
		and is_equal_approx(growth_missile.get_mirror_visual_scale(), 1.30)
		and is_equal_approx(growth_missile.get_explosion_radius(), 1.20),
		"multiple L2 reflections recalculate missile growth linearly from its original values"
	)
	var growth_branch := (
		growth_missile._spawn_directional_attack_copy(
			growth_missile.global_position,
			Vector3.BACK,
			20.0,
			1.0,
			0,
			growth_payload.duplicate_for_reflection_branch()
		) as MissileProjectile
		if growth_missile != null
		else null
	)
	_expect(
		growth_branch != null
		and is_equal_approx(growth_branch.get_mirror_visual_scale(), 1.30)
		and is_equal_approx(growth_branch.get_explosion_radius(), 1.20),
		"reflected missile branches inherit the complete current size and explosion snapshot"
	)
	if growth_missile != null:
		growth_missile.queue_free()
	if growth_branch != null:
		growth_branch.queue_free()
	_remove_target(combat, burning_target)
	_remove_target(combat, expanded_target)
	_remove_target(combat, short_burn_target)
	await process_frame

	_reflection_enabled = false
	_blocker_enabled = true
	var splash_target := _make_target(combat, Vector3(0.7, 4.0, 1.0), true)
	var blocked := building.launch_directional_projectile(20.0, Vector3.BACK) as MissileProjectile
	if blocked != null:
		blocked._process(0.5)
	_expect(is_equal_approx(splash_target.current_hp, 80.0), "a Stuff blocker contact explodes and applies horizontal airborne splash")
	_remove_target(combat, splash_target)
	combat.clear_projectile_reflection_resolver(self)
	combat.clear_projectile_blocker_resolver(self)
	_reflection_enabled = false
	_blocker_enabled = false
	await process_frame


func _test_source_removal(fixture: Dictionary) -> void:
	var building := fixture.get("building") as Building
	var missile := building.launch_directional_projectile(20.0, Vector3.BACK) as MissileProjectile
	building.queue_free()
	await process_frame
	if missile != null:
		missile._process(0.25)
	_expect(missile != null and is_instance_valid(missile), "a launched missile survives removal of its source building")
	var branch := missile._spawn_directional_attack_copy(
		missile.global_position,
		Vector3.RIGHT,
		20.0,
		1.0,
		0,
		AttackEffectPayload.new()
	) as MissileProjectile if missile != null else null
	_expect(
		branch != null and branch.get_source_building() == null,
		"a missile can create a reflected branch after its source building is freed"
	)


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var combat := CombatManager.new()
	host.add_child(combat)
	combat.projectile_spawned.connect(_on_projectile_spawned)
	var definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.CROSSBOW_TOWER)
	var stats := definition.levels[0]
	stats.projectile_fire_mode = BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING
	stats.projectile_is_missile = true
	stats.prioritizes_airborne = true
	stats.target_priority = PriorityTargetingStrategy.Priority.LOCKED
	stats.targeting_range = 3.0
	stats.attack_range = 4.0
	stats.base_damage = 20.0
	stats.projectile_speed = 10.0
	stats.missile_explosion_radius = 1.0
	stats.missile_orbit_duration = 0.2
	stats.missile_orbit_radius_x = 0.7
	stats.missile_orbit_radius_z = 0.45
	stats.missile_speed_variation_ratio = 0.0
	stats.missile_visual_wobble = 0.0
	stats.missile_homing_turn_speed_degrees = 2160.0
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile_manager, combat)
	building.set_process(false)
	return {"host": host, "grid": grid, "tile": tile_manager, "combat": combat, "building": building}


func _make_target(combat: CombatManager, position: Vector3, airborne: bool) -> CombatTarget:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.airborne = airborne
	combat.add_child(target)
	target.configure_debug_target(position, 100.0, 0.0, 0.0)
	combat.register_target(target)
	return target


func _remove_target(combat: CombatManager, target: CombatTarget) -> void:
	if target == null or not is_instance_valid(target):
		return
	combat.unregister_target(target)
	target.queue_free()


func _trace_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_enabled or start.z >= 1.0 or end.z < 1.0:
		return {"hit": false}
	var distance := (1.0 - start.z) / maxf(0.000001, end.z - start.z) * start.distance_to(end)
	return {
		"hit": true,
		"position": Vector3(start.x, lerpf(start.y, end.y, distance / start.distance_to(end)), 1.0),
		"normal": Vector3.FORWARD,
		"distance": distance,
		"mirror": null,
		"epsilon": 0.001,
		"max_reflections_per_frame": 4,
	}


func _trace_blocker(start: Vector3, end: Vector3, _excluded: Object = null) -> Dictionary:
	if not _blocker_enabled or start.z >= 1.0 or end.z < 1.0:
		return {"hit": false}
	var fraction := (1.0 - start.z) / maxf(0.000001, end.z - start.z)
	return {
		"hit": true,
		"position": start.lerp(end, fraction),
		"distance": start.distance_to(end) * fraction,
	}


func _on_projectile_spawned(projectile: Projectile) -> void:
	_last_projectile = projectile
	projectile.set_process(false)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
