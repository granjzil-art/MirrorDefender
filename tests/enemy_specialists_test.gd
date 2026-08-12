extends SceneTree

var _failures: int = 0
var _checks: int = 0
var _blocker: TestBlocker


class TestBlocker:
	extends Node3D
	var hp: float = 100.0

	func take_structure_damage(amount: float, _attacker: Node = null) -> float:
		var applied := minf(hp, maxf(0.0, amount))
		hp -= applied
		return applied

	func get_structure_target_position() -> Vector3:
		return global_position

	func is_structure_alive() -> bool:
		return hp > 0.0


class TestLaserBuilding:
	extends Node3D

	func get_laser_slow_multiplier() -> float:
		return 1.0

	func get_laser_slow_duration() -> float:
		return 0.0

	func affects_target(_target: CombatTarget) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[EnemySpecialists] running")
	_test_production_definitions_and_catalog()
	_test_armor_aura_uses_strongest_other_caster()
	_test_reflection_patterns_and_vertical_bounds()
	_test_projectiles_and_lasers_reflect_without_hitting_the_reflector()
	_test_final_durability_hit_still_reflects()
	_test_elite_movement_cycle()
	await process_frame
	if _failures == 0:
		print("[EnemySpecialists] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[EnemySpecialists] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_definitions_and_catalog() -> void:
	var expected := {
		"EliteMage.tres": EnemyDefinition.ReflectionPattern.NONE,
		"EliteTitan.tres": EnemyDefinition.ReflectionPattern.FOUR_SIDES,
		"SingleShieldSoldier.tres": EnemyDefinition.ReflectionPattern.FRONT,
		"DoubleShieldSoldier.tres": EnemyDefinition.ReflectionPattern.LEFT_RIGHT,
	}
	for file_name in expected:
		var definition := _load_enemy(file_name)
		_expect(definition != null, "%s loads as an enemy definition" % file_name)
		if definition == null:
			continue
		_expect(definition.validate_configuration().is_empty(), "%s passes validation" % file_name)
		_expect(definition.reflection_pattern == int(expected[file_name]), "%s owns the intended reflection pattern" % file_name)
		_expect(definition.model_asset == null, "%s can use the programmatic fallback while its model slot is empty" % file_name)
		_expect(definition.reflection_model_asset == null, "%s keeps its enemy and mirror model slots independent" % file_name)
	var editable := RuntimeCombatDataEditSession.ENEMY_PROPERTIES
	_expect(
		editable.has("armor_aura_radius")
		and editable.has("reflection_pattern")
		and editable.has("reflection_max_durability"),
		"specialist abilities and mirror durability are exposed to the combat data editor"
	)
	var bindings := RuntimeDebugBindings.new()
	var found: EnemyDefinition = bindings.call("_find_enemy", LevelResource.new(), "elite_titan")
	_expect(found != null and found.enemy_id == &"elite_titan", "debug spawn lookup discovers enemies not authored into the current waves")
	bindings.free()


func _test_armor_aura_uses_strongest_other_caster() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var combat := CombatManager.new()
	host.add_child(combat)
	var soldier := _spawn_unit(combat, _load_enemy("SingleShieldSoldier.tres"), Vector3.ZERO)
	var strong_mage := _spawn_unit(combat, _load_enemy("EliteMage.tres"), Vector3(1.0, 0.0, 0.0))
	var weak_definition := _load_enemy("EliteMage.tres").duplicate(true) as EnemyDefinition
	weak_definition.armor_aura_bonus = 3.0
	var weak_mage := _spawn_unit(combat, weak_definition, Vector3(-1.0, 0.0, 0.0))
	var base_armor := soldier.armor
	var strong_bonus := strong_mage.definition.armor_aura_bonus
	_expect(is_equal_approx(soldier.get_effective_armor(), base_armor + maxf(strong_bonus, 3.0)), "overlapping armor auras use only the strongest bonus")
	var soldier_hp := soldier.current_hp
	soldier.take_damage(10.0)
	var expected_damage := maxf(0.0, 10.0 - base_armor - maxf(strong_bonus, 3.0))
	_expect(is_equal_approx(soldier.current_hp, soldier_hp - expected_damage), "aura armor keeps the existing fixed damage-reduction algorithm")
	_expect(is_zero_approx(strong_mage.get_armor_aura_bonus_for(strong_mage)), "a mage does not receive its own aura")
	strong_mage.global_position = Vector3(20.0, 0.0, 0.0)
	_expect(is_equal_approx(soldier.get_effective_armor(), base_armor + 3.0), "leaving the strongest aura immediately reveals the weaker aura")
	weak_mage.global_position = Vector3(-20.0, 0.0, 0.0)
	_expect(is_equal_approx(soldier.get_effective_armor(), base_armor), "leaving every aura immediately restores base armor")
	host.queue_free()


func _test_reflection_patterns_and_vertical_bounds() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var titan := _spawn_unit(null, _load_enemy("EliteTitan.tres"), Vector3.ZERO)
	host.add_child(titan)
	_expect(_hits(titan, Vector3(0.0, 1.0, -2.0), Vector3(0.0, 1.0, 0.0)), "Titan reflects from its front side")
	_expect(_hits(titan, Vector3(0.0, 1.0, 2.0), Vector3(0.0, 1.0, 0.0)), "Titan reflects from its back side")
	_expect(_hits(titan, Vector3(-2.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)), "Titan reflects from its left side")
	_expect(_hits(titan, Vector3(2.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)), "Titan reflects from its right side")
	_expect(not _hits(titan, Vector3(0.0, 2.5, -2.0), Vector3(0.0, 2.5, 0.0)), "Titan has no reflective top or bottom cap")
	var reflection_root := titan.get_node_or_null("ReflectionSurfaces") as Node3D
	_expect(
		reflection_root != null and reflection_root.get_child_count() == 4,
		"empty Titan mirror-model slot builds four independent programmatic faces"
	)
	_expect(
		titan.get_node_or_null("EnemyHealthBar3D") != null,
		"Titan keeps its body health bar in the center"
	)
	for surface_id in [&"front", &"back", &"left", &"right"]:
		var surface_root := titan.get_reflection_surface_root(surface_id)
		var surface_bar := titan.get_reflection_surface_health_bar(surface_id) as EnemyHealthBar3D
		_expect(
			surface_root != null
			and surface_root.get_parent() == reflection_root
			and surface_bar != null,
			"Titan %s mirror owns a separate model root and durability bar" % surface_id
		)
		if surface_root != null and surface_bar != null:
			_expect(
				Vector2(surface_root.position.x, surface_root.position.z).length() > 0.0
				and Vector2(surface_bar.position.x, surface_bar.position.z).dot(
					Vector2(surface_root.position.x, surface_root.position.z)
				) > 0.0,
				"Titan %s durability bar is offset toward its mirror" % surface_id
			)
	var body_hp_before := titan.current_hp
	var maximum_front := titan.get_reflection_surface_max_durability(&"front")
	titan.take_reflection_surface_damage(&"front", 25.0)
	var front_bar := titan.get_reflection_surface_health_bar(&"front") as EnemyHealthBar3D
	_expect(
		front_bar != null
		and is_equal_approx(front_bar.get_current_ratio(), (maximum_front - 25.0) / maximum_front),
		"mirror durability bar updates after reflected damage"
	)
	titan.take_reflection_surface_damage(&"front", maximum_front)
	_expect(
		not titan.is_reflection_surface_alive(&"front")
		and titan.get_reflection_surface_root(&"front") == null
		and not _hits(titan, Vector3(0.0, 1.0, -2.0), Vector3(0.0, 1.0, 0.0))
		and _hits(titan, Vector3(0.0, 1.0, 2.0), Vector3(0.0, 1.0, 0.0)),
		"destroying one Titan mirror removes only that face"
	)
	_expect(
		titan.is_alive() and is_equal_approx(titan.current_hp, body_hp_before),
		"mirror damage never changes the independent enemy body HP"
	)

	var single := _spawn_unit(null, _load_enemy("SingleShieldSoldier.tres"), Vector3.ZERO)
	host.add_child(single)
	_expect(_hits(single, Vector3(0.0, 1.0, -2.0), Vector3(0.0, 1.0, 0.0)), "single-shield soldier reflects in its movement-facing direction")
	_expect(not _hits(single, Vector3(0.0, 1.0, 2.0), Vector3(0.0, 1.0, 0.0)), "single-shield soldier does not reflect from behind")
	single.call("_face_direction", Vector3.RIGHT)
	_expect(_hits(single, Vector3(2.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)), "single shield rotates with the retained movement direction")

	var dual := _spawn_unit(null, _load_enemy("DoubleShieldSoldier.tres"), Vector3.ZERO)
	host.add_child(dual)
	_expect(_hits(dual, Vector3(-2.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)) and _hits(dual, Vector3(2.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)), "double-shield soldier reflects from both lateral sides")
	_expect(not _hits(dual, Vector3(0.0, 1.0, -2.0), Vector3(0.0, 1.0, 0.0)), "double-shield soldier leaves its front side open")
	host.queue_free()


func _test_projectiles_and_lasers_reflect_without_hitting_the_reflector() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var combat := CombatManager.new()
	host.add_child(combat)
	var titan := _spawn_unit(combat, _load_enemy("EliteTitan.tres"), Vector3.ZERO)
	_expect(combat.get_projectile_reflection_provider_count() == 1, "reflective enemy registers with the shared combat reflection chain")
	var start := Vector3(0.0, titan.get_target_position().y, -2.0)
	var hp_before := titan.current_hp
	var durability_before := titan.get_reflection_surface_current_durability(&"front")
	var projectile := combat.spawn_projectile(start, titan, 20.0, 30.0, 4.0, 0.2, 0.05, Color.WHITE)
	projectile.set_process(false)
	projectile._process(1.0)
	_expect(projectile.has_reflected(), "normal tower projectile reflects from the Titan")
	_expect(is_equal_approx(titan.current_hp, hp_before), "the reflected projectile does not also damage its reflector")
	_expect(
		is_equal_approx(
			titan.get_reflection_surface_current_durability(&"front"),
			durability_before - 30.0
		),
		"normal tower projectile deducts its damage from mirror durability"
	)
	var copied_projectile := MirrorProjectionProjectile.new()
	combat.add_child(copied_projectile)
	copied_projectile.configure(
		combat,
		null,
		start,
		Vector3(0.0, titan.get_target_position().y, 2.0),
		20.0,
		30.0,
		0.2,
		0.05,
		Color.CYAN,
		null,
		4.0,
		combat.get_projectile_reflection_resolver(),
		true
	)
	copied_projectile.set_process(false)
	copied_projectile._process(1.0)
	_expect(copied_projectile.has_reflected(), "copied-building projectile uses the composite enemy reflection chain")
	_expect(
		is_equal_approx(
			titan.get_reflection_surface_current_durability(&"front"),
			durability_before - 60.0
		),
		"copied-building projectile deducts the same mirror durability as the original"
	)

	var missile := combat.spawn_directional_missile(
		start,
		Vector3.BACK,
		20.0,
		30.0,
		4.0,
		0.2,
		0.05,
		Color.ORANGE,
		null,
		null,
		{"orbit_duration": 0.01, "explosion_radius": 0.0}
	)
	missile.set_process(false)
	missile._process(1.0)
	_expect(
		missile.has_reflected()
		and is_equal_approx(
			titan.get_reflection_surface_current_durability(&"front"),
			durability_before - 90.0
		),
		"missile reflection deducts its direct damage from mirror durability"
	)

	var path := ContinuousLaserPath.trace(
		combat,
		null,
		start,
		Vector3.BACK,
		4.0,
		0,
		combat.get_projectile_reflection_resolver()
	)
	_expect(path.get("segments", []).size() == 2, "continuous laser reflects into a second segment")
	_expect(path.get("hits", []).is_empty(), "continuous laser does not damage the enemy surface that reflected it")
	var laser_building := TestLaserBuilding.new()
	host.add_child(laser_building)
	LaserAttackStrategy.apply_continuous_hits(laser_building, path, 30.0, 1.0, false)
	_expect(
		is_equal_approx(
			titan.get_reflection_surface_current_durability(&"front"),
			durability_before - 120.0
		),
		"continuous laser deducts damage-per-second times duration from mirror durability"
	)

	var beam := combat.spawn_pulse_laser(
		start,
		Vector3.BACK,
		30.0,
		4.0,
		0.1,
		2.0,
		0.0,
		0.1,
		0.1,
		[Color.CYAN, Color.BLUE],
		1
	)
	beam.set_process(false)
	beam._process(0.01)
	_expect(beam.debug_get_segments().size() == 2, "pulse laser uses the same enemy reflection provider")
	_expect(is_equal_approx(titan.current_hp, hp_before), "pulse laser excludes the reflecting Titan from both adjacent segments")
	_expect(
		is_equal_approx(
			titan.get_reflection_surface_current_durability(&"front"),
			durability_before - 150.0
		),
		"pulse laser deducts its damage once from the reflected mirror face"
	)
	titan.queue_free()
	host.queue_free()


func _test_final_durability_hit_still_reflects() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var combat := CombatManager.new()
	host.add_child(combat)
	var definition := _load_enemy("EliteTitan.tres").duplicate(true) as EnemyDefinition
	definition.reflection_max_durability = 20.0
	var titan := _spawn_unit(combat, definition, Vector3.ZERO)
	var start := Vector3(0.0, titan.get_target_position().y, -2.0)
	var projectile := combat.spawn_projectile(
		start,
		titan,
		20.0,
		30.0,
		4.0,
		0.2,
		0.05,
		Color.WHITE
	)
	projectile.set_process(false)
	projectile._process(1.0)
	_expect(
		projectile.has_reflected(),
		"the hit that exhausts mirror durability still completes its reflection"
	)
	_expect(
		not titan.is_reflection_surface_alive(&"front")
		and titan.get_reflection_surface_root(&"front") == null,
		"a projectile removes the mirror model, bar, and collision when durability reaches zero"
	)
	_expect(titan.is_alive(), "breaking the last-hit mirror leaves the enemy body alive")
	host.queue_free()


func _test_elite_movement_cycle() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var definition := _load_enemy("EliteTitan.tres").duplicate(true) as EnemyDefinition
	definition.move_speed = 1.0
	definition.movement_active_duration = 0.5
	definition.movement_pause_duration = 0.5
	var path := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -10.0)])
	var unit := _spawn_unit(null, definition, Vector3.ZERO, path)
	host.add_child(unit)
	unit.set_process(false)
	unit._process(0.5)
	_expect(is_equal_approx(unit.global_position.z, -0.5) and unit.is_in_movement_pause(), "elite enters its pause after consuming actual movement time")
	unit._process(0.5)
	_expect(is_equal_approx(unit.global_position.z, -0.5) and not unit.is_in_movement_pause(), "elite remains stationary for the complete pause duration")
	unit._process(0.25)
	_expect(is_equal_approx(unit.global_position.z, -0.75), "elite resumes from its retained facing after the pause")
	unit.apply_freeze(0.5)
	var active_before_freeze := unit.get_movement_active_remaining()
	unit._process(0.5)
	_expect(is_equal_approx(unit.get_movement_active_remaining(), active_before_freeze), "freeze does not consume the elite movement phase")

	var attacker_definition := definition.duplicate(true) as EnemyDefinition
	attacker_definition.attack_range = 1.0
	_blocker = TestBlocker.new()
	host.add_child(_blocker)
	_blocker.global_position = Vector3(0.0, 0.0, -0.2)
	var attacker := EnemyUnit.new()
	attacker.debug_visual_enabled = false
	attacker.configure_unit(
		attacker_definition,
		path,
		[Vector3i.ZERO, Vector3i(0, 1, 0)],
		1.0,
		Callable(self, "_resolve_test_blocker")
	)
	host.add_child(attacker)
	attacker.set_process(false)
	var active_before_attack := attacker.get_movement_active_remaining()
	attacker._process(0.4)
	_expect(attacker.is_attacking() and is_equal_approx(attacker.get_movement_active_remaining(), active_before_attack), "attacking during a movement phase does not consume its movement timer")
	host.queue_free()


func _resolve_test_blocker(_from: Vector3i, _to: Vector3i, _unit: EnemyUnit) -> Node:
	return _blocker


func _spawn_unit(
	combat: CombatManager,
	definition: EnemyDefinition,
	position: Vector3,
	path: PackedVector3Array = PackedVector3Array()
) -> EnemyUnit:
	var unit := EnemyUnit.new()
	unit.debug_visual_enabled = true
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = PackedVector3Array([position])
	unit.configure_unit(
		definition,
		resolved_path,
		[],
		1.0,
		Callable(),
		null,
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		Callable(),
		combat
	)
	if combat != null:
		combat.add_child(unit)
		combat.register_target(unit)
	return unit


func _hits(unit: EnemyUnit, start: Vector3, end: Vector3) -> bool:
	return bool(unit.trace_projectile_reflection(start, end).get("hit", false))


func _load_enemy(file_name: String) -> EnemyDefinition:
	return ResourceLoader.load(
		"res://resources/enemies/%s" % file_name,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as EnemyDefinition


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
