extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _checks: int = 0
var _failures: int = 0
var _spawned_projectiles: Array[Projectile] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[ProjectileFireMode] running")
	_test_serialized_enum_contract()
	var fixture := _make_fixture()
	_test_facing_only_fire(fixture)
	var host := fixture.get("host") as Node
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[ProjectileFireMode] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[ProjectileFireMode] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_serialized_enum_contract() -> void:
	_expect(
		BuildingLevelStats.ProjectileFireMode.TARGET_ONLY == 0
		and BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING == 1
		and BuildingLevelStats.ProjectileFireMode.FACING_ONLY == 2,
		"facing-only appends one stable serialized fire-mode value"
	)
	var stats := BuildingLevelStats.new()
	stats.projectile_fire_mode = BuildingLevelStats.ProjectileFireMode.FACING_ONLY
	_expect(stats.validate_configuration().is_empty(), "facing-only is accepted by level-data validation")


func _test_facing_only_fire(fixture: Dictionary) -> void:
	var combat := fixture.get("combat") as CombatManager
	var building := fixture.get("building") as Building
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	combat.add_child(target)
	target.configure_debug_target(building.global_position + Vector3.RIGHT, 100.0, 0.0, 0.0)
	combat.register_target(target)
	building.set_facing_index(9)
	building._process(0.01)
	_expect(_spawned_projectiles.size() == 1, "facing-only fires automatically while a target exists")
	var projectile := _spawned_projectiles[0] if not _spawned_projectiles.is_empty() else null
	_expect(
		projectile != null
		and projectile.is_ballistic()
		and projectile.get_travel_direction().is_equal_approx(building.get_facing_direction()),
		"facing-only always launches a straight projectile along logical facing"
	)
	_expect(building.get("_locked_target") == null, "facing-only does not acquire or lock the available target")
	_expect(not building.uses_targeting_range(), "facing-only does not expose a targeting-range contract")
	combat.clear_projectiles()
	_spawned_projectiles.clear()
	building._process(0.5)
	_expect(_spawned_projectiles.is_empty(), "facing-only respects the configured attack cooldown")
	building._process(0.5)
	_expect(_spawned_projectiles.size() == 1, "facing-only fires again when its cooldown expires")
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
	var combat := CombatManager.new()
	host.add_child(combat)
	combat.projectile_spawned.connect(_on_projectile_spawned)
	var definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	var stats := definition.get_level_stats(1)
	stats.projectile_fire_mode = BuildingLevelStats.ProjectileFireMode.FACING_ONLY
	stats.attacks_per_second = 1.0
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile_manager, combat)
	building.set_process(false)
	return {
		"host": host,
		"combat": combat,
		"building": building,
	}


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
