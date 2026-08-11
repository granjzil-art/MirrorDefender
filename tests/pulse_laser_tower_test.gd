extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _checks: int = 0
var _failures: int = 0
var _reflection_mode: StringName = &"none"
var _reflection_plane_x: float = 0.0
var _blocker_enabled: bool = false
var _blocker_plane_x: float = 0.0
var _spawn_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[PulseLaserTower] running")
	var fixture := _make_fixture()
	_test_production_definition(fixture)
	_test_reflected_segment_damage_and_timing(fixture)
	_test_blocker_truncates_path(fixture)
	_test_fixed_facing_periodic_fire(fixture)
	_test_color_cycle(fixture)
	var host: Node = fixture.get("host")
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[PulseLaserTower] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[PulseLaserTower] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_definition(fixture: Dictionary) -> void:
	var production := load("res://resources/buildings/PulseLaserTower.tres") as BuildingDefinition
	_expect(production != null, "production pulse-laser definition loads")
	_expect(
		production != null and production.kind == BuildingDefinition.Kind.PULSE_LASER_TOWER,
		"pulse laser uses an appended independent building kind"
	)
	_expect(production != null and production.validate_configuration().is_empty(), "production pulse-laser parameters validate")
	var manager: BuildingManager = fixture.get("manager")
	_expect(manager.get_definition(BuildingDefinition.Kind.PULSE_LASER_TOWER) == manager.pulse_laser_tower, "building manager resolves the independent pulse-laser resource")


func _test_reflected_segment_damage_and_timing(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var building: Building = fixture.get("building")
	combat.clear_targets()
	_reflection_mode = &"single"
	_blocker_enabled = false
	_reflection_plane_x = building.get_attack_origin().x + 2.0
	var target := _spawn_target(combat, building.get_attack_origin() + Vector3.RIGHT)
	var beam := building.launch_pulse_laser()
	_expect(beam != null, "fixed-facing pulse laser launches without acquiring a target")
	var segments := beam.debug_get_segments() if beam != null else []
	_expect(segments.size() == 2, "one reflection creates an independent second beam segment")
	if segments.size() == 2:
		var first: Dictionary = segments[0]
		var second: Dictionary = segments[1]
		var colors := building.get_pulse_laser_reflection_colors()
		_expect((first.get("color") as Color).is_equal_approx(colors[0]), "initial segment is red")
		_expect((second.get("color") as Color).is_equal_approx(colors[1]), "first reflected segment is orange")
		var visible_distance := float(first.get("length", 0.0)) + float(second.get("length", 0.0))
		_expect(
			is_equal_approx(visible_distance + 0.01, building.get_attack_range_world()),
			"incident, reflected, and epsilon distances share one range budget"
		)
	var health_before := target.current_hp
	if beam != null:
		beam._process(0.05)
	_expect(is_equal_approx(target.current_hp, health_before), "fade-in phase does not apply damage")
	_expect(beam != null and is_equal_approx(beam.debug_get_visual_factor(), 0.5), "fade-in changes beam width and brightness linearly")
	if beam != null:
		beam._process(0.05)
	var single_damage := building.get_instant_damage()
	_expect(
		is_equal_approx(target.current_hp, health_before - single_damage * 2.0),
		"one enemy receives independent damage from incident and reflected segments at hold entry"
	)
	if beam != null:
		beam._process(0.20)
	_expect(beam != null and is_equal_approx(beam.debug_get_visual_factor(), 0.5), "fade-out changes beam width and brightness linearly")
	_expect(
		is_equal_approx(target.current_hp, health_before - single_damage * 2.0),
		"hold and fade-out never repeat the pulse damage"
	)


func _test_blocker_truncates_path(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var building: Building = fixture.get("building")
	combat.clear_targets()
	_reflection_mode = &"none"
	_blocker_enabled = true
	_blocker_plane_x = building.get_attack_origin().x + 1.5
	var target := _spawn_target(combat, building.get_attack_origin() + Vector3.RIGHT * 3.0)
	var beam := building.launch_pulse_laser()
	var segments := beam.debug_get_segments() if beam != null else []
	_expect(segments.size() == 1 and bool(segments[0].get("blocked", false)), "nearest ballistic blocker terminates the pulse path")
	if segments.size() == 1:
		_expect(is_equal_approx(float(segments[0].get("length", 0.0)), 1.5), "blocked pulse ends at the blocker sphere entry")
	var health_before := target.current_hp
	if beam != null:
		beam._process(0.10)
	_expect(is_equal_approx(target.current_hp, health_before), "enemy beyond a Stuff blocker receives no pulse damage")


func _test_fixed_facing_periodic_fire(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var building: Building = fixture.get("building")
	combat.clear_targets()
	_reflection_mode = &"none"
	_blocker_enabled = false
	_spawn_count = 0
	if not combat.pulse_laser_spawned.is_connected(_on_pulse_laser_spawned):
		combat.pulse_laser_spawned.connect(_on_pulse_laser_spawned)
	building.apply_level(1)
	building._process(0.0)
	_expect(_spawn_count == 1, "pulse strategy fires immediately without any target")
	building._process(0.20)
	_expect(_spawn_count == 1, "pulse strategy respects its attacks-per-second cooldown")
	building._process(0.30)
	_expect(_spawn_count == 2, "pulse strategy fires again when the fixed period elapses")


func _test_color_cycle(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.get("combat")
	var building: Building = fixture.get("building")
	_reflection_mode = &"synthetic_cycle"
	_blocker_enabled = false
	var colors := building.get_pulse_laser_reflection_colors()
	var beam := combat.spawn_pulse_laser(
		building.get_attack_origin(),
		Vector3.RIGHT,
		0.0,
		10.0,
		0.1,
		2.0,
		0.1,
		0.1,
		0.1,
		colors,
		8,
		building
	)
	var segments := beam.debug_get_segments() if beam != null else []
	_expect(segments.size() >= 8, "reflection cap permits enough independent segments to exercise the palette cycle")
	if segments.size() >= 8:
		_expect((segments[6].get("color") as Color).is_equal_approx(colors[6]), "sixth reflection uses purple")
		_expect((segments[7].get("color") as Color).is_equal_approx(colors[0]), "color after purple cycles back to red")


func _trace_reflection(start: Vector3, end: Vector3) -> Dictionary:
	if _reflection_mode == &"single":
		if start.x < _reflection_plane_x - 0.0001 and end.x >= _reflection_plane_x:
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
	elif _reflection_mode == &"synthetic_cycle" and start.distance_to(end) > 0.51:
		var direction := (end - start).normalized()
		return {
			"hit": true,
			"position": start + direction * 0.5,
			"normal": Vector3.RIGHT,
			"distance": 0.5,
			"epsilon": 0.01,
			"max_reflections_per_frame": 8,
		}
	return {"hit": false}


func _trace_blocker(start: Vector3, end: Vector3, _excluded: Object = null) -> Dictionary:
	if not _blocker_enabled or end.x <= start.x:
		return {"hit": false}
	if start.x > _blocker_plane_x or end.x < _blocker_plane_x:
		return {"hit": false}
	var fraction := (_blocker_plane_x - start.x) / (end.x - start.x)
	var position := start.lerp(end, fraction)
	return {
		"hit": true,
		"position": position,
		"distance": start.distance_to(position),
		"blocker": self,
	}


func _spawn_target(combat: CombatManager, position: Vector3) -> CombatTarget:
	var target := CombatTarget.new()
	combat.add_child(target)
	target.configure_debug_target(position, 200.0, 1.0, 0.0)
	combat.register_target(target)
	return target


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
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
	combat.set_projectile_reflection_resolver(Callable(self, "_trace_reflection"))
	combat.set_projectile_blocker_resolver(Callable(self, "_trace_blocker"))
	var manager := BuildingManager.new()
	host.add_child(manager)
	var definition := TestDefinitionFactory.make_building_definition(
		BuildingDefinition.Kind.PULSE_LASER_TOWER
	)
	var stats := definition.levels[0]
	stats.base_damage = 10.0
	stats.level_factor = 1.5
	stats.extra_factor = 2.0
	stats.attack_range = 6.0
	stats.attacks_per_second = 2.0
	stats.pulse_laser_fade_in_time = 0.10
	stats.pulse_laser_hold_time = 0.10
	stats.pulse_laser_fade_out_time = 0.20
	manager.pulse_laser_tower = definition
	manager.configure(grid, tile, resource, combat)
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile, combat)
	building.set_process(false)
	_expect(is_equal_approx(building.get_instant_damage(), 30.0), "pulse damage uses base_damage times level_factor times extra_factor")
	return {
		"host": host,
		"grid": grid,
		"tile": tile,
		"resource": resource,
		"combat": combat,
		"manager": manager,
		"building": building,
	}


func _on_pulse_laser_spawned(_beam: PulseLaserBeam) -> void:
	_spawn_count += 1


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
