extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const BuildingSelectionVisualizerScript := preload("res://scripts/building/BuildingSelectionVisualizer.gd")

var _checks: int = 0
var _failures: int = 0
var _reflection_plane_x: float = INF


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[ProjectileTrajectoryPreview] running")
	var fixture := _make_fixture()
	_test_single_direction_and_rotation(fixture)
	_test_reflection_and_shared_distance(fixture)
	_test_multi_direction_levels(fixture)
	_test_laser_placement_and_adjustment_preview(fixture)
	_test_targeting_range_placement_previews(fixture)
	_test_preview_lifecycle_and_defensive_filter(fixture)
	var host: Node = fixture.get("host")
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[ProjectileTrajectoryPreview] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error(
			"[ProjectileTrajectoryPreview] FAIL: %d/%d checks failed"
			% [_failures, _checks]
		)
		quit(1)


func _test_single_direction_and_rotation(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var building: Building = fixture.get("arrow")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	visualizer.set_projectile_reflection_resolver(Callable())
	manager.select_building(building)
	var segments := visualizer.debug_get_projectile_trajectory_segments()
	_expect(visualizer.has_projectile_trajectory_visual(), "selected projectile tower shows its trajectory")
	_expect(segments.size() == 1, "single-direction tower produces one unreflected segment")
	if segments.size() == 1:
		var segment: Dictionary = segments[0]
		var start: Vector3 = segment.get("start", Vector3.ZERO)
		var end: Vector3 = segment.get("end", Vector3.ZERO)
		_expect(
			is_equal_approx(float(segment.get("length", 0.0)), building.get_attack_range_world()),
			"trajectory reads the current level attack-range budget"
		)
		_expect(
			(end - start).normalized().is_equal_approx(building.get_facing_direction()),
			"trajectory starts along the logical building facing"
		)
	manager.rotate_selected(9)
	segments = visualizer.debug_get_projectile_trajectory_segments()
	if segments.size() == 1:
		var rotated_segment: Dictionary = segments[0]
		var rotated_start: Vector3 = rotated_segment.get("start", Vector3.ZERO)
		var rotated_end: Vector3 = rotated_segment.get("end", Vector3.ZERO)
		_expect(
			(rotated_end - rotated_start).normalized().is_equal_approx(building.get_facing_direction()),
			"facing_changed rebuilds the preview immediately"
		)
	else:
		_expect(false, "rotated tower keeps one trajectory segment")


func _test_reflection_and_shared_distance(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var building: Building = fixture.get("arrow")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	building.set_facing_index(0)
	manager.select_building(building)
	_reflection_plane_x = building.get_attack_origin().x + 2.0
	visualizer.set_projectile_reflection_resolver(Callable(self, "_trace_test_reflection"))
	var segments := visualizer.debug_get_projectile_trajectory_segments()
	_expect(segments.size() == 2, "one mirror hit splits the preview into incident and reflected segments")
	if segments.size() != 2:
		return
	var first: Dictionary = segments[0]
	var second: Dictionary = segments[1]
	var first_start: Vector3 = first.get("start", Vector3.ZERO)
	var first_end: Vector3 = first.get("end", Vector3.ZERO)
	var second_start: Vector3 = second.get("start", Vector3.ZERO)
	var second_end: Vector3 = second.get("end", Vector3.ZERO)
	_expect((first_end - first_start).normalized().is_equal_approx(Vector3.RIGHT), "incident segment reaches the reflector")
	_expect((second_end - second_start).normalized().is_equal_approx(Vector3.LEFT), "reflected segment follows r = d - 2(d dot n)n")
	var visible_distance := float(first.get("length", 0.0)) + float(second.get("length", 0.0))
	_expect(
		is_equal_approx(visible_distance + 0.01, building.get_attack_range_world()),
		"reflection and epsilon consume the same maximum-distance budget"
	)


func _test_multi_direction_levels(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var mace: Building = fixture.get("mace")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	visualizer.set_projectile_reflection_resolver(Callable())
	mace.apply_level(1)
	manager.select_building(mace)
	_expect(
		visualizer.debug_get_projectile_trajectory_segments().size() == 4,
		"level-one Mace preview uses its actual four launch directions"
	)
	mace.apply_level(2)
	_expect(
		visualizer.debug_get_projectile_trajectory_segments().size() == 8,
		"level_changed rebuilds the Mace preview with eight launch directions"
	)


func _test_laser_placement_and_adjustment_preview(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var laser: Building = fixture.get("laser")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	visualizer.set_projectile_reflection_resolver(Callable())
	laser.set_facing_index(0)
	manager.select_building(laser)
	var segments := visualizer.debug_get_projectile_trajectory_segments()
	_expect(visualizer.has_projectile_trajectory_visual(), "selected LaserTower shows its planned beam path")
	_expect(segments.size() == 1, "LaserTower preview starts as one full-range segment")
	if segments.size() == 1:
		var segment: Dictionary = segments[0]
		var start: Vector3 = segment.get("start", Vector3.ZERO)
		var end: Vector3 = segment.get("end", Vector3.ZERO)
		_expect(
			is_equal_approx(float(segment.get("length", 0.0)), laser.get_attack_range_world()),
			"LaserTower preview exposes the full planned range before runtime propagation"
		)
		_expect(
			(end - start).normalized().is_equal_approx(laser.get_facing_direction()),
			"LaserTower adjustment preview follows its logical facing"
		)
	_expect(
		is_equal_approx(laser.get_projectile_width_world(), laser.get_laser_beam_width_world()),
		"LaserTower preview reads the configurable continuous-beam width"
	)
	manager.rotate_selected(9)
	segments = visualizer.debug_get_projectile_trajectory_segments()
	if segments.size() == 1:
		var rotated_segment: Dictionary = segments[0]
		var rotated_start: Vector3 = rotated_segment.get("start", Vector3.ZERO)
		var rotated_end: Vector3 = rotated_segment.get("end", Vector3.ZERO)
		_expect(
			(rotated_end - rotated_start).normalized().is_equal_approx(laser.get_facing_direction()),
			"rotating an adjusted LaserTower rebuilds its beam preview immediately"
		)
	else:
		_expect(false, "rotated LaserTower keeps one trajectory segment")
	manager.select_building(null)
	manager.preview_updated.emit(laser)
	_expect(visualizer.has_projectile_trajectory_visual(), "LaserTower placement ghost shows its planned beam path")
	laser.set_facing_index(18)
	segments = visualizer.debug_get_projectile_trajectory_segments()
	if segments.size() == 1:
		var placement_segment: Dictionary = segments[0]
		var placement_start: Vector3 = placement_segment.get("start", Vector3.ZERO)
		var placement_end: Vector3 = placement_segment.get("end", Vector3.ZERO)
		_expect(
			(placement_end - placement_start).normalized().is_equal_approx(laser.get_facing_direction()),
			"rotating the LaserTower placement ghost rebuilds its beam preview immediately"
		)
	else:
		_expect(false, "rotated LaserTower placement keeps one trajectory segment")
	manager.preview_cleared.emit()
	_expect(not visualizer.has_projectile_trajectory_visual(), "clearing LaserTower placement removes its beam preview")


func _test_targeting_range_placement_previews(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	manager.select_building(null)
	for fixture_name in [&"arrow", &"crossbow", &"mace"]:
		var building: Building = fixture.get(fixture_name)
		manager.preview_updated.emit(building)
		_expect(
			visualizer.has_targeting_range_visual(),
			"%s placement ghost shows its blue targeting range" % fixture_name
		)
		manager.preview_cleared.emit()
		_expect(
			not visualizer.has_targeting_range_visual(),
			"clearing %s placement hides its blue targeting range" % fixture_name
		)
	manager.preview_updated.emit(fixture.get("laser"))
	_expect(
		not visualizer.has_targeting_range_visual(),
		"fixed-facing LaserTower placement stays outside targeting-range preview"
	)
	manager.preview_cleared.emit()
	manager.preview_updated.emit(fixture.get("barrier"))
	_expect(
		not visualizer.has_targeting_range_visual(),
		"defensive placement stays outside targeting-range preview"
	)
	manager.preview_cleared.emit()


func _test_preview_lifecycle_and_defensive_filter(fixture: Dictionary) -> void:
	var manager: BuildingManager = fixture.get("manager")
	var arrow: Building = fixture.get("arrow")
	var barrier: Building = fixture.get("barrier")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	manager.select_building(null)
	manager.preview_updated.emit(arrow)
	_expect(visualizer.has_projectile_trajectory_visual(), "placement preview signal shows the same trajectory")
	manager.preview_cleared.emit()
	_expect(not visualizer.has_projectile_trajectory_visual(), "clearing placement preview removes the trajectory")
	manager.select_building(barrier)
	_expect(
		not visualizer.has_projectile_trajectory_visual(),
		"defensive structures without projectiles do not show a trajectory"
	)


func _trace_test_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if (
		start.x < _reflection_plane_x - 0.0001
		and end.x >= _reflection_plane_x
		and end.x > start.x
	):
		var fraction := (_reflection_plane_x - start.x) / (end.x - start.x)
		var position := start.lerp(end, fraction)
		return {
			"hit": true,
			"position": position,
			"normal": Vector3.RIGHT,
			"distance": start.distance_to(position),
			"epsilon": 0.01,
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
	var combat := CombatManager.new()
	host.add_child(combat)
	var manager := BuildingManager.new()
	host.add_child(manager)
	manager.configure(grid, tile, resource, combat)
	var arrow := _make_building(
		host,
		TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER),
		Vector3i(2, 2, 0),
		grid,
		tile,
		combat
	)
	var mace_definition := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.MACE_TOWER)
	var level_two := mace_definition.levels[0].duplicate(true) as BuildingLevelStats
	level_two.projectile_direction_count = 8
	mace_definition.levels.append(level_two)
	var mace := _make_building(
		host,
		mace_definition,
		Vector3i(3, 2, 0),
		grid,
		tile,
		combat
	)
	var crossbow := _make_building(
		host,
		TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.CROSSBOW_TOWER),
		Vector3i(5, 2, 0),
		grid,
		tile,
		combat
	)
	var barrier := _make_building(
		host,
		TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER),
		Vector3i(1, 2, 0),
		grid,
		tile,
		combat
	)
	var laser := _make_building(
		host,
		TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER),
		Vector3i(4, 2, 0),
		grid,
		tile,
		combat
	)
	var visualizer := BuildingSelectionVisualizerScript.new()
	host.add_child(visualizer)
	visualizer.configure(grid, manager)
	return {
		"host": host,
		"grid": grid,
		"tile": tile,
		"resource": resource,
		"combat": combat,
		"manager": manager,
		"arrow": arrow,
		"mace": mace,
		"crossbow": crossbow,
		"barrier": barrier,
		"laser": laser,
		"visualizer": visualizer,
	}


func _make_building(
	host: Node,
	definition: BuildingDefinition,
	cell: Vector3i,
	grid: GridManager,
	tile: TileManager,
	combat: CombatManager
) -> Building:
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, cell, grid, tile, combat)
	building.set_process(false)
	return building


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
