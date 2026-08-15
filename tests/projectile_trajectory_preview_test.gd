extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const BuildingSelectionVisualizerScript := preload("res://scripts/building/BuildingSelectionVisualizer.gd")

var _checks: int = 0
var _failures: int = 0
var _reflection_plane_x: float = INF
var _multiplier_reflectors: Array[ReflectMirror] = []
var _test_copy_payloads: Array[MirrorCopyPayload] = []
var _mirror_preview_data: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[ProjectileTrajectoryPreview] running")
	var fixture := _make_fixture()
	_test_single_direction_and_rotation(fixture)
	_test_reflection_and_shared_distance(fixture)
	_test_multiplier_labels(fixture)
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
	var original_projectile_width := building.get_level_stats().projectile_width
	var fixed_preview_width := visualizer.projectile_preview_width
	building.get_level_stats().projectile_width = original_projectile_width * 4.0
	visualizer.refresh()
	_expect(
		is_equal_approx(visualizer.debug_get_projectile_trajectory_width(), fixed_preview_width),
		"trajectory preview keeps one fixed width independent of projectile size"
	)
	building.get_level_stats().projectile_width = original_projectile_width
	visualizer.refresh()
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


func _test_multiplier_labels(fixture: Dictionary) -> void:
	var host: Node3D = fixture.get("host")
	var manager: BuildingManager = fixture.get("manager")
	var building: Building = fixture.get("arrow")
	var visualizer: BuildingSelectionVisualizer = fixture.get("visualizer")
	building.set_facing_index(0)
	manager.select_building(building)
	var origin := building.get_attack_origin()
	var first := ReflectMirror.new()
	var second := ReflectMirror.new()
	host.add_child(first)
	host.add_child(second)
	first.global_position = Vector3(origin.x + 1.0, origin.y - 1.0, origin.z)
	second.global_position = Vector3(origin.x - 2.5, origin.y - 1.0, origin.z)
	_multiplier_reflectors = [first, second]
	visualizer.set_projectile_reflection_resolver(
		Callable(self, "_trace_multiplier_reflections")
	)
	var labels := visualizer.debug_get_projectile_multiplier_labels()
	_expect(labels.size() == 2, "two reflected preview hits create two mirror multiplier labels")
	if labels.size() == 2:
		_expect(
			String(labels[0].get("text", "")) == "1.1"
			and String(labels[1].get("text", "")) == "1.21",
			"successive level-one reflectors display 1.1 then 1.21"
		)
		_expect(
			labels[0].get("kind", &"") == &"reflection"
			and labels[1].get("kind", &"") == &"reflection",
			"reflection multipliers are classified as mirror-head labels"
		)
	var label_node := visualizer.find_child("TrajectoryMultiplierLabel", true, false) as Label3D
	_expect(
		label_node != null and label_node.modulate.is_equal_approx(Color(1.0, 0.05, 0.05, 1.0)),
		"trajectory multiplier labels render in red"
	)
	_expect(
		label_node != null and label_node.font_size == 18 and label_node.outline_size == 3,
		"trajectory multiplier labels match the upgrade-number font size and outline"
	)
	visualizer.set_projectile_reflection_resolver(Callable())
	var payload := MirrorCopyPayload.new()
	payload.stable_key = "preview-copy-chain"
	payload.copy_kind = &"arrow_tower"
	payload.root_source = building
	payload.source_cell = building.cell
	payload.root_source_cell = building.cell
	payload.projected_cell = Vector3i(4, 4, 0)
	payload.damage_multiplier = 1.21
	payload.penetration_bonus = 2
	_test_copy_payloads = [payload]
	visualizer.set_projectile_copy_resolver(Callable(self, "_resolve_test_copy_payloads"))
	labels = visualizer.debug_get_projectile_multiplier_labels()
	_expect(
		labels.size() == 1
		and labels[0].get("kind", &"") == &"copy"
		and String(labels[0].get("text", "")) == "1.21",
		"copy-chain multiplier appears above its generated virtual image"
	)
	manager.select_building(null)
	_expect(
		visualizer.debug_get_projectile_multiplier_labels().is_empty(),
		"clearing building selection removes multiplier labels"
	)
	manager.preview_updated.emit(building)
	_expect(
		not visualizer.debug_get_projectile_multiplier_labels().is_empty(),
		"building placement preview shows multiplier labels"
	)
	manager.preview_cleared.emit()
	_expect(
		visualizer.debug_get_projectile_multiplier_labels().is_empty(),
		"clearing building placement removes multiplier labels"
	)
	_mirror_preview_data = {"building": building, "payloads": [payload]}
	visualizer.set_mirror_preview_trajectory_resolver(
		Callable(self, "_resolve_test_mirror_preview")
	)
	_expect(
		visualizer.has_projectile_trajectory_visual()
		and visualizer.debug_get_projectile_multiplier_labels().is_empty(),
		"mirror placement keeps trajectory lines but never shows multiplier numbers"
	)
	_mirror_preview_data = {}
	_test_copy_payloads.clear()
	visualizer.set_mirror_preview_trajectory_resolver(Callable())
	visualizer.set_projectile_copy_resolver(Callable())
	_multiplier_reflectors.clear()
	first.queue_free()
	second.queue_free()


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
		is_equal_approx(
			visualizer.debug_get_projectile_trajectory_width(),
			visualizer.projectile_preview_width
		),
		"LaserTower trajectory uses the same fixed preview width"
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


func _trace_multiplier_reflections(start: Vector3, end: Vector3) -> Dictionary:
	if _multiplier_reflectors.size() != 2:
		return {"hit": false}
	var direction := end - start
	var mirror: ReflectMirror
	var plane_x := 0.0
	var normal := Vector3.ZERO
	if direction.x > 0.0:
		mirror = _multiplier_reflectors[0]
		plane_x = mirror.global_position.x
		normal = Vector3.RIGHT
	elif direction.x < 0.0:
		mirror = _multiplier_reflectors[1]
		plane_x = mirror.global_position.x
		normal = Vector3.LEFT
	else:
		return {"hit": false}
	var fraction := (plane_x - start.x) / direction.x
	if fraction <= 0.0001 or fraction > 1.0:
		return {"hit": false}
	var position := start.lerp(end, fraction)
	return {
		"hit": true,
		"position": position,
		"normal": normal,
		"distance": start.distance_to(position),
		"epsilon": 0.01,
		"mirror": mirror,
		"damage_multiplier": 1.1,
		"penetration_bonus": 1,
	}


func _resolve_test_copy_payloads(_building: Building) -> Array[MirrorCopyPayload]:
	return _test_copy_payloads


func _resolve_test_mirror_preview() -> Dictionary:
	return _mirror_preview_data


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
