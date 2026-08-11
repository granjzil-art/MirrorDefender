extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _spawned_projectiles: Array[Projectile] = []
var _reflection_used: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[MaceTower] running")
	_test_production_definition()
	var fixture := _make_fixture()
	await _test_card_slot(fixture)
	await _test_direction_unlocks_and_gate(fixture)
	_test_projectile_penetration(fixture)
	_test_continuous_contact_and_reflection_reentry(fixture)
	await _test_freed_contact_target_cleanup(fixture)
	fixture.host.queue_free()
	await process_frame
	if _failures == 0:
		print("[MaceTower] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MaceTower] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_definition() -> void:
	var definition := load("res://resources/buildings/MaceTower.tres") as BuildingDefinition
	_expect(definition != null, "MaceTower.tres loads")
	if definition == null:
		return
	_expect(definition.kind == BuildingDefinition.Kind.MACE_TOWER, "Mace uses the stable appended building kind")
	_expect(definition.display_name == "钉锤", "Mace keeps the confirmed display name")
	_expect(definition.validate_configuration().is_empty(), "Mace production resource validates")
	_expect(definition.get_level_stats(1).cost == 200.0, "Mace level 1 uses the confirmed 200 resource cost")
	_expect(definition.get_level_stats(1).targeting_range == 2.0, "Mace uses a two-cell horizontal targeting radius")
	_expect(definition.get_level_stats(1).projectile_direction_count == 4, "Mace level 1 fires four directions")
	_expect(definition.get_level_stats(2).projectile_direction_count == 8, "Mace level 2 unlocks eight directions")
	_expect(definition.get_level_stats(3).projectile_penetration_count == 1, "Mace level 3 unlocks one extra penetration")
	_expect(
		definition.get_level_stats(1).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_ONLY
		and definition.get_level_stats(2).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_ONLY
		and definition.get_level_stats(3).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING,
		"Mace unlocks target-or-facing only at level 3"
	)


func _test_card_slot(fixture: Dictionary) -> void:
	var definition := load("res://resources/buildings/MaceTower.tres") as BuildingDefinition
	var cards: Array[BuildingDefinition] = [
		load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition,
		load("res://resources/buildings/LaserTower.tres") as BuildingDefinition,
		load("res://resources/buildings/Barrier.tres") as BuildingDefinition,
		load("res://resources/buildings/CrossbowTower.tres") as BuildingDefinition,
		definition,
		null,
		null,
	]
	var card_bar := BuildCardBar.new()
	root.add_child(card_bar)
	await process_frame
	card_bar.configure(
		fixture.resource,
		load("res://resources/mirrors/CopyMirror.tres") as CopyMirrorDefinition,
		cards,
		6
	)
	await process_frame
	_expect(card_bar.get_building_definition_at(4) == definition, "Mace occupies the formal fifth building card slot")
	_expect(card_bar.get_filled_building_card_count() == 5, "Mace fills the fifth slot while the sixth slot remains reserved")
	card_bar.queue_free()


func _test_direction_unlocks_and_gate(fixture: Dictionary) -> void:
	var building: Building = fixture.building
	var combat: CombatManager = fixture.combat
	_spawned_projectiles.clear()
	building.apply_level(1)
	building._process(2.0)
	_expect(_spawned_projectiles.is_empty(), "level 1 waits for an enemy inside its gate")
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat.add_child(target)
	target.configure_debug_target(building.global_position + Vector3(1.0, 0.0, 0.0), 100.0, 0.0, 0.0)
	combat.register_target(target)
	building._process(2.0)
	_expect(_spawned_projectiles.size() == 4, "level 1 emits four projectiles in one attack cycle")
	combat.clear_projectiles()
	_spawned_projectiles.clear()
	building.apply_level(2)
	building._process(2.0)
	_expect(_spawned_projectiles.size() == 8, "level 2 emits eight projectiles in one attack cycle")
	combat.clear_projectiles()
	_spawned_projectiles.clear()
	combat.unregister_target(target)
	target.queue_free()
	building.apply_level(3)
	building._process(2.0)
	_expect(_spawned_projectiles.size() == 8, "level 3 keeps firing eight directions without an enemy")
	combat.clear_projectiles()


func _test_projectile_penetration(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.combat
	var first := CombatTarget.new()
	var second := CombatTarget.new()
	var targets: Array[CombatTarget] = [first, second]
	for target in targets:
		target.debug_visual_enabled = false
		combat.add_child(target)
		combat.register_target(target)
	first.configure_debug_target(Vector3(1.0, 0.0, 0.0), 100.0, 0.0, 0.0)
	second.configure_debug_target(Vector3(2.0, 0.0, 0.0), 100.0, 0.0, 0.0)
	var first_hp := first.current_hp
	var second_hp := second.current_hp
	var projectile := combat.spawn_directional_projectile(
		Vector3(0.0, 0.44, 0.0),
		Vector3.RIGHT,
		20.0,
		10.0,
		5.0,
		0.4,
		0.1,
		Color.WHITE,
		null,
		null,
		1
	)
	_expect(projectile != null, "a projectile accepts an extra penetration count")
	if projectile != null:
		projectile.set_process(false)
		projectile._process(0.3)
	_expect(first.current_hp < first_hp and second.current_hp < second_hp, "one extra penetration reaches the second enemy")
	_expect(projectile.is_queued_for_deletion(), "projectile is consumed after its configured penetration budget")
	combat.unregister_target(first)
	combat.unregister_target(second)
	first.queue_free()
	second.queue_free()


func _test_continuous_contact_and_reflection_reentry(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.combat
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat.add_child(target)
	target.configure_debug_target(Vector3(1.0, 0.0, 0.0), 100.0, 0.0, 0.0)
	combat.register_target(target)
	var projectile := Projectile.new()
	fixture.host.add_child(projectile)
	_reflection_used = false
	projectile.configure_directional(
		Vector3(0.0, 0.44, 0.0),
		Vector3.RIGHT,
		10.0,
		10.0,
		6.0,
		0.4,
		0.1,
		Color.WHITE,
		null,
		null,
		Callable(combat, "get_targets"),
		Callable(self, "_test_reflection_resolver"),
		1
	)
	projectile.set_process(false)
	var hp_before := target.current_hp
	projectile._process(0.4)
	_expect(target.current_hp == hp_before - 20.0, "continuous contact is hit once, then reflection permits one return hit")
	_expect(projectile.is_queued_for_deletion(), "projectile is consumed after the reflected re-entry uses its penetration budget")
	combat.unregister_target(target)
	target.queue_free()


func _test_freed_contact_target_cleanup(fixture: Dictionary) -> void:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	fixture.host.add_child(target)
	target.configure_debug_target(Vector3.ZERO, 10.0, 0.0, 0.0)
	var instance_id := target.get_instance_id()
	var projectile := Projectile.new()
	var projection_projectile := MirrorProjectionProjectile.new()
	fixture.host.add_child(projectile)
	fixture.host.add_child(projection_projectile)
	projectile._contact_targets[instance_id] = target
	projection_projectile._contact_targets[instance_id] = target
	target.queue_free()
	await process_frame
	_expect(not is_instance_valid(target), "contact cleanup fixture releases its target")
	projectile._refresh_contact_targets()
	projection_projectile._refresh_contact_targets()
	_expect(projectile._contact_targets.is_empty(), "projectile drops a freed contact target without a script error")
	_expect(
		projection_projectile._contact_targets.is_empty(),
		"copy-mirror projectile drops a freed contact target without a script error"
	)
	projectile.queue_free()
	projection_projectile.queue_free()


func _test_reflection_resolver(start: Vector3, end: Vector3) -> Dictionary:
	if not _reflection_used and start.x > 0.5 and start.x < 2.0 and end.x >= 2.0:
		_reflection_used = true
		return {
			"hit": true,
			"position": Vector3(2.0, 0.44, 0.0),
			"normal": Vector3.RIGHT,
			"distance": 2.0 - start.x,
			"epsilon": 0.0001,
			"max_reflections_per_frame": 8,
		}
	return {"hit": false}


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(6, 6))
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	var resource := ResourceManager.new()
	host.add_child(resource)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(6, 6)
	level.initial_resource = 10000.0
	level.building_cap = 20
	resource.apply_level_configuration(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	combat.projectile_spawned.connect(_on_projectile_spawned)
	var manager := BuildingManager.new()
	host.add_child(manager)
	manager.configure(grid, tile, resource, combat)
	var building := Building.new()
	host.add_child(building)
	var definition := load("res://resources/buildings/MaceTower.tres") as BuildingDefinition
	building.configure(definition, Vector3i(2, 2, 0), grid, tile, combat)
	building.set_process(false)
	return {"host": host, "grid": grid, "tile": tile, "resource": resource, "combat": combat, "manager": manager, "building": building}


func _on_projectile_spawned(projectile: Projectile) -> void:
	_spawned_projectiles.append(projectile)
	projectile.set_process(false)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
