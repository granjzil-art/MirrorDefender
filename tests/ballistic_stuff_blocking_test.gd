extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const BuildingSelectionVisualizerScript := preload("res://scripts/building/BuildingSelectionVisualizer.gd")

class TestStructure:
	extends Node3D
	var current_hp: float = 100.0

	func is_structure_alive() -> bool:
		return current_hp > 0.0

	func get_structure_target_position() -> Vector3:
		return global_position

	func get_structure_hit_radius() -> float:
		return 0.2

	func take_structure_damage(amount: float, _attacker: Node = null) -> float:
		var applied := minf(current_hp, amount)
		current_hp -= applied
		return applied


class TestAttacker:
	extends Node3D

	func is_alive() -> bool:
		return true


var _checks: int = 0
var _failures: int = 0
var _blocker_plane_x: float = 1.0
var _blocker_token: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[BallisticStuffBlocking] running")
	var fixture := _make_fixture()
	_test_friendly_projectiles(fixture)
	_test_projection_projectile(fixture)
	_test_enemy_projectile(fixture)
	_test_continuous_laser(fixture)
	_test_trajectory_preview(fixture)
	var host: Node = fixture.get("host")
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[BallisticStuffBlocking] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[BallisticStuffBlocking] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_friendly_projectiles(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	combat.clear_targets()
	var y := 0.6
	var start := Vector3(0.0, y, 0.0)
	_blocker_plane_x = 1.0
	var target := _spawn_target(combat, Vector3(3.0, y, 0.0))
	target.position.y -= target.debug_height * 0.55
	var health_before := target.current_hp
	var targeted := combat.spawn_projectile(start, target, 10.0, 20.0, 5.0, 0.2, 0.05, Color.WHITE)
	if targeted != null:
		targeted._process(1.0)
	_expect(targeted != null and targeted.is_queued_for_deletion(), "target-tracking projectile disappears at the Stuff blocker")
	_expect(is_equal_approx(target.current_hp, health_before), "target beyond Stuff is not hit by a tracking projectile")
	var touching_target := _spawn_target(combat, Vector3(_blocker_plane_x, y, 0.0))
	touching_target.position.y -= touching_target.debug_height * 0.55
	var touching_health_before := touching_target.current_hp
	var touching_projectile := combat.spawn_projectile(
		start,
		touching_target,
		10.0,
		20.0,
		5.0,
		0.2,
		0.05,
		Color.WHITE
	)
	if touching_projectile != null:
		touching_projectile._process(1.0)
	_expect(
		touching_projectile != null
		and touching_projectile.is_queued_for_deletion()
		and is_equal_approx(touching_target.current_hp, touching_health_before),
		"Stuff wins when a target hit sphere overlaps the blocker contact surface"
	)
	var front_target := _spawn_target(combat, Vector3(_blocker_plane_x * 0.5, y, 0.0))
	front_target.position.y -= front_target.debug_height * 0.55
	var front_health_before := front_target.current_hp
	var directional := combat.spawn_directional_projectile(start, Vector3.RIGHT, 10.0, 20.0, 5.0, 0.2, 0.05, Color.WHITE, null, null, 8)
	var front_hit := (
		directional._find_first_target_hit(start, Vector3(_blocker_plane_x, y, 0.0), 1.0)
		if directional != null
		else {"hit": false}
	)
	_expect(
		front_hit.get("target") == front_target,
		"blocker-aware projectile query selects the valid target before Stuff"
	)
	if directional != null:
		directional._process(1.0)
	_expect(directional != null and directional.is_queued_for_deletion(), "directional penetrating projectile is still absorbed by Stuff")
	_expect(is_equal_approx(target.current_hp, health_before), "penetration budget never bypasses a Stuff blocker")
	_expect(
		is_equal_approx(touching_target.current_hp, touching_health_before),
		"directional projectile cannot damage an overlapping target behind Stuff"
	)
	_expect(
		is_equal_approx(front_target.current_hp, front_health_before - 20.0),
		"filtering a target behind Stuff preserves a valid target before it (hp %.1f -> %.1f)" % [
			front_health_before,
			front_target.current_hp,
		]
	)


func _test_projection_projectile(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var projectile := MirrorProjectionProjectile.new()
	combat.add_child(projectile)
	projectile.configure(
		combat,
		null,
		Vector3(0.0, 0.6, 0.0),
		Vector3(3.0, 0.6, 0.0),
		10.0,
		20.0,
		0.2,
		0.05,
		Color.WHITE,
		null,
		5.0,
		Callable(),
		true,
		8,
		Callable(self, "_trace_blocker")
	)
	projectile._process(1.0)
	_expect(projectile.is_queued_for_deletion(), "copy-mirror projectile uses the same Stuff blocker query")


func _test_enemy_projectile(fixture: Dictionary) -> void:
	var host: Node = fixture.get("host")
	var target := TestStructure.new()
	target.position = Vector3(3.0, 0.6, 0.0)
	host.add_child(target)
	var attacker := TestAttacker.new()
	host.add_child(attacker)
	var projectile := EnemyProjectile.new()
	host.add_child(projectile)
	projectile.configure(
		Vector3(0.0, 0.6, 0.0),
		target,
		attacker,
		10.0,
		20.0,
		5.0,
		0.2,
		0.05,
		Color.WHITE,
		null,
		Callable(self, "_trace_blocker")
	)
	projectile._process(1.0)
	_expect(projectile.is_queued_for_deletion(), "enemy projectile is absorbed by Stuff before its structure target")
	_expect(is_equal_approx(target.current_hp, 100.0), "absorbed enemy projectile does not damage the target behind Stuff")


func _test_continuous_laser(fixture: Dictionary) -> void:
	var host: Node = fixture.get("host")
	var grid: GridManager = fixture.get("grid")
	var tile: TileManager = fixture.get("tile")
	var combat: CombatManager = fixture.get("combat")
	combat.clear_targets()
	var definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	var laser := Building.new()
	host.add_child(laser)
	laser.configure(definition, Vector3i.ZERO, grid, tile, combat)
	laser.set_process(false)
	_blocker_plane_x = laser.get_attack_origin().x + 1.0
	var target := _spawn_target(combat, laser.get_attack_origin() + Vector3.RIGHT * 2.0)
	var health_before := target.current_hp
	laser._process(0.5)
	_expect(is_equal_approx(target.current_hp, health_before), "retained continuous laser is truncated by the same Stuff field")


func _test_trajectory_preview(fixture: Dictionary) -> void:
	var host: Node = fixture.get("host")
	var grid: GridManager = fixture.get("grid")
	var tile: TileManager = fixture.get("tile")
	var combat: CombatManager = fixture.get("combat")
	var manager: BuildingManager = fixture.get("manager")
	var definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile, combat)
	building.set_process(false)
	_blocker_plane_x = building.get_attack_origin().x + 1.0
	var visualizer := BuildingSelectionVisualizerScript.new()
	host.add_child(visualizer)
	visualizer.configure(grid, manager)
	visualizer.set_projectile_blocker_resolver(Callable(self, "_trace_blocker"))
	manager.select_building(building)
	var segments := visualizer.debug_get_projectile_trajectory_segments()
	_expect(
		segments.size() == 1
		and bool(segments[0].get("blocked", false))
		and is_equal_approx(float(segments[0].get("length", 0.0)), 1.0),
		"trajectory preview stops at the same Stuff collision point as gameplay"
	)


func _trace_blocker(start: Vector3, end: Vector3, excluded: Object = null) -> Dictionary:
	if excluded == _blocker_token or is_equal_approx(end.x, start.x):
		return {"hit": false}
	if end.x < start.x or start.x > _blocker_plane_x or end.x < _blocker_plane_x:
		return {"hit": false}
	var fraction := (_blocker_plane_x - start.x) / (end.x - start.x)
	var position := start.lerp(end, fraction)
	return {
		"hit": true,
		"position": position,
		"distance": start.distance_to(position),
		"blocker": _blocker_token,
	}


func _spawn_target(combat: CombatManager, position: Vector3) -> CombatTarget:
	var target := CombatTarget.new()
	combat.add_child(target)
	target.configure_debug_target(position, 100.0, 1.0, 0.0)
	combat.register_target(target)
	return target


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	_blocker_token = Node.new()
	host.add_child(_blocker_token)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(8, 8))
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	var resource := ResourceManager.new()
	host.add_child(resource)
	var combat := CombatManager.new()
	host.add_child(combat)
	combat.set_projectile_blocker_resolver(Callable(self, "_trace_blocker"))
	var manager := BuildingManager.new()
	host.add_child(manager)
	manager.configure(grid, tile, resource, combat)
	return {
		"host": host,
		"grid": grid,
		"tile": tile,
		"resource": resource,
		"combat": combat,
		"manager": manager,
	}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
