extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const BuildingSelectionVisualizerScript := preload("res://scripts/building/BuildingSelectionVisualizer.gd")

var _failures: int = 0
var _checks: int = 0
var _last_projectile: Projectile


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[CrossbowTower] running")
	_test_production_definitions()
	var fixture := await _make_fixture()
	_test_free_facing_contract(fixture)
	await _test_card_order(fixture)
	_test_selection_visuals(fixture)
	_test_directional_and_targeted_fire(fixture)
	var host: Node = fixture.get("host")
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[CrossbowTower] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[CrossbowTower] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_definitions() -> void:
	var crossbow := load("res://resources/buildings/CrossbowTower.tres") as BuildingDefinition
	var arrow := load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition
	_expect(crossbow != null and crossbow.validate_configuration().is_empty(), "crossbow definition loads and validates")
	if crossbow != null:
		_expect(crossbow.kind == BuildingDefinition.Kind.CROSSBOW_TOWER, "crossbow has an appended stable building kind")
		_expect(crossbow.display_name == "导弹塔", "the stable crossbow kind is now presented as the missile tower")
		for level_index in range(1, crossbow.get_max_level() + 1):
			_expect(
				crossbow.get_level_stats(level_index).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING
				and crossbow.get_level_stats(level_index).projectile_is_missile
				and crossbow.get_level_stats(level_index).prioritizes_airborne,
				"missile level %d keeps facing fire, missile behavior, and airborne priority" % level_index
			)
	_expect(
		arrow != null
		and arrow.get_level_stats(1).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_ONLY
		and arrow.get_level_stats(3).projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING,
		"arrow tower unlocks configurable facing fire at level three"
	)
	_expect(
		arrow != null
		and arrow.get_level_stats(1).prioritizes_airborne
		and arrow.get_level_stats(2).prioritizes_airborne
		and arrow.get_level_stats(3).prioritizes_airborne,
		"all arrow tower levels share airborne-first targeting"
	)


func _test_free_facing_contract(fixture: Dictionary) -> void:
	var grid: GridManager = fixture.get("grid")
	var building: Building = fixture.get("building")
	_expect(grid.get_tile_building_facing_count() == 36, "tile buildings expose 36 ten-degree facings")
	_expect(grid.get_tile_content_facing_count() == 8, "square grid-bound Stuff keeps eight topology facings")
	building.set_facing_index(9)
	_expect(building.get_facing_slot_count() == 36, "runtime building uses the free-facing contract")
	_expect(building.get_facing_direction().is_equal_approx(Vector3.BACK), "facing slot 9 resolves to positive Z at 90 degrees")


func _test_card_order(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var bar := BuildCardBar.new()
	root.add_child(bar)
	await process_frame
	var cards: Array[BuildingDefinition] = [
		manager.arrow_tower,
		manager.laser_tower,
		manager.barrier,
		manager.crossbow_tower,
	]
	bar.configure(fixture.get("resource"), null, cards, 6)
	_expect(bar.get_building_definition_at(3) == manager.crossbow_tower, "crossbow occupies formal building card slot four")
	bar.queue_free()
	await process_frame


func _test_selection_visuals(fixture: Dictionary) -> void:
	var host: Node = fixture.get("host")
	var manager: BuildingManager = fixture.get("manager")
	var visualizer := BuildingSelectionVisualizerScript.new()
	host.add_child(visualizer)
	visualizer.configure(fixture.get("grid"), manager)
	manager.select_building(fixture.get("building"))
	_expect(visualizer.has_targeting_range_visual(), "selected targeting tower shows a blue range surface")
	_expect(
		visualizer.get_visualized_occupied_cells() == [Vector3i.ZERO],
		"selected tile building shows its occupied-cell footprint"
	)
	manager.select_building(null)
	_expect(not visualizer.has_targeting_range_visual(), "clearing selection removes targeting presentation")
	visualizer.queue_free()


func _test_directional_and_targeted_fire(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var building: Building = fixture.get("building")
	_last_projectile = null
	building.set_facing_index(9)
	building._process(0.01)
	_expect(_last_projectile != null and _last_projectile.is_ballistic(), "crossbow fires a ballistic projectile without a target")
	if _last_projectile != null:
		_expect(
			_last_projectile.get_travel_direction().is_equal_approx(building.get_facing_direction()),
			"no-target projectile follows the logical building facing"
		)
		var crossing_target := CombatTarget.new()
		crossing_target.debug_visual_enabled = false
		combat.add_child(crossing_target)
		crossing_target.configure_debug_target(Vector3(0.0, 0.0, 1.0), 100.0, 0.0, 0.0)
		combat.register_target(crossing_target)
		var crossing_hp := crossing_target.current_hp
		_last_projectile._process(0.2)
		_expect(crossing_target.current_hp < crossing_hp, "directional projectile damages the first enemy crossing its straight path")
		combat.unregister_target(crossing_target)
		crossing_target.queue_free()
	combat.clear_projectiles()
	_last_projectile = null
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat.add_child(target)
	target.configure_debug_target(Vector3(-1.0, 0.0, 0.0), 100.0, 0.0, 0.0)
	combat.register_target(target)
	building._process(1.0)
	_expect(_last_projectile != null and not _last_projectile.is_ballistic(), "crossbow retains normal homing fire while a target exists")
	combat.clear_projectiles()
	combat.unregister_target(target)
	target.queue_free()


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	grid.grid_shape = GridManager.Shape.SQUARE
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(4, 4)
	level.initial_resource = 1000.0
	level.building_cap = 20
	resource_manager.apply_level_configuration(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	combat.projectile_spawned.connect(_on_projectile_spawned)
	var manager := BuildingManager.new()
	host.add_child(manager)
	manager.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	manager.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	manager.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	manager.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	manager.crossbow_tower = load("res://resources/buildings/CrossbowTower.tres") as BuildingDefinition
	manager.configure(grid, tile_manager, resource_manager, combat)
	var definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.CROSSBOW_TOWER)
	definition.levels[0].projectile_fire_mode = BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile_manager, combat)
	building.set_process(false)
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat,
		"manager": manager,
		"building": building,
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
