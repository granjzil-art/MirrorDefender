extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0
var _reflection_count: int = 0
var _external_reflection_fraction: float = 0.25
var _spawned_projectiles: Array[Node] = []
var _spawned_pulse_lasers: Array[PulseLaserBeam] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[ReflectMirror] running")
	var fixture := await _make_fixture()
	_test_definition_and_preview(fixture)
	_test_placement_with_adjacent_enemies(fixture)
	_test_reflection_geometry(fixture)
	_test_pulse_laser_reflection(fixture)
	_test_level_two_reflection_forks(fixture)
	_test_external_reflector_composition(fixture)
	_test_projectile_distance_and_multiple_reflections(fixture)
	_test_projection_projectile_reflection(fixture)
	_test_initial_placement_round_trip(fixture)
	var host: Node = fixture.host
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[ReflectMirror] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[ReflectMirror] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_definition_and_preview(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var grid: GridManager = fixture.grid
	var from_cell := Vector3i(3, 2, 0)
	var to_cell := Vector3i(4, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	_expect(mirror_manager.reflect_mirror_definition.validate_configuration().is_empty(), "reflect mirror definition is valid")
	_expect(mirror_manager.update_reflect_preview(from_cell, edge_index), "reflect mirror reuses edge placement preview")
	var preview := mirror_manager.get_preview_mirror()
	_expect(preview is ReflectMirror, "reflect placement preview uses the reflector entity")
	_expect(preview != null and preview.preview_mode, "reflect placement keeps normal mirror preview presentation")
	var preview_color := preview.get_preview_display_color()
	_expect(preview_color.g > 0.8 and preview_color.r < 0.3, "valid reflect-mirror body preview is green")
	var preview_surface_overlay := preview.get_reflection_surface().material_overlay as StandardMaterial3D
	_expect(
		preview_surface_overlay != null and preview_surface_overlay.albedo_color.g > 0.8,
		"green placement tint also covers the reflect-mirror face"
	)
	var info := mirror_manager.get_preview_info()
	_expect(int(info.get("mirror_kind", -1)) == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT, "preview identifies the reflector kind")
	mirror_manager.clear_preview()


func _test_placement_with_adjacent_enemies(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var combat: CombatManager = fixture.combat
	var grid: GridManager = fixture.grid
	var from_cell := Vector3i(0, 0, 0)
	var to_cell := Vector3i(1, 0, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var from_enemy := CombatTarget.new()
	var to_enemy := CombatTarget.new()
	combat.add_child(from_enemy)
	combat.add_child(to_enemy)
	from_enemy.configure_debug_target(grid.cell_to_world(from_cell), 100.0, 0.0, 0.0)
	to_enemy.configure_debug_target(grid.cell_to_world(to_cell), 100.0, 0.0, 0.0)
	combat.register_target(from_enemy)
	combat.register_target(to_enemy)
	var copy_validation := mirror_manager.validate_placement(
		from_cell,
		edge_index,
		true,
		MirrorPlacementData.MirrorKind.COPY
	)
	_expect(copy_validation.failure.is_empty(), "adjacent enemies no longer invalidate copy-mirror placement")
	var copy := mirror_manager.place_copy_mirror(from_cell, edge_index, true)
	_expect(copy != null, "copy mirror can be placed while enemies occupy both adjacent cells")
	_expect(mirror_manager.remove_mirror(copy), "adjacent-enemy copy-mirror test releases its edge")
	var reflect_validation := mirror_manager.validate_placement(
		from_cell,
		edge_index,
		true,
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
	)
	_expect(reflect_validation.failure.is_empty(), "adjacent enemies no longer invalidate reflect-mirror placement")
	var reflector := mirror_manager.place_reflect_mirror(from_cell, edge_index, true)
	_expect(reflector != null, "reflect mirror can be placed while enemies occupy both adjacent cells")
	_expect(mirror_manager.remove_mirror(reflector), "adjacent-enemy reflector test releases its edge")
	combat.unregister_target(from_enemy)
	combat.unregister_target(to_enemy)
	from_enemy.queue_free()
	to_enemy.queue_free()


func _test_reflection_geometry(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var right: ReflectMirror = _place_right_mirror(fixture)
	_expect(right != null, "projectile reflector uses normal physical-edge placement")
	var normal := right.get_active_normal()
	var edge_direction := right.get_edge_direction().normalized()
	var plane := right.global_position + Vector3.UP
	var incoming := (-normal + edge_direction * 0.35).normalized()
	var start := plane - incoming * 1.0
	var end := plane + incoming * 1.0
	var hit := mirror_manager.trace_projectile_reflection(start, end)
	_expect(bool(hit.hit), "active mirror face intersects an incoming projectile segment")
	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var reflected_direction := (incoming - 2.0 * incoming.dot(hit_normal) * hit_normal).normalized()
	_expect(is_equal_approx(reflected_direction.dot(normal), -incoming.dot(normal)), "normal component reverses at equal angle")
	_expect(is_equal_approx(reflected_direction.dot(edge_direction), incoming.dot(edge_direction)), "tangent component is preserved at equal angle")
	var back_hit := mirror_manager.trace_projectile_reflection(end, start)
	_expect(not bool(back_hit.hit), "reflector back face passes projectiles through")


func _test_pulse_laser_reflection(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.combat
	var right: ReflectMirror = fixture.right_mirror
	var normal := right.get_active_normal()
	var plane := right.global_position + Vector3.UP
	var colors: Array[Color] = [Color.RED, Color.ORANGE]
	var beam := combat.spawn_pulse_laser(
		plane + normal,
		-normal,
		0.0,
		2.0,
		0.1,
		2.0,
		0.01,
		0.01,
		0.01,
		colors,
		1
	)
	var segments := beam.debug_get_segments() if beam != null else []
	_expect(segments.size() == 2, "pulse laser reflects from the physical mirror's active face")
	if segments.size() == 2:
		_expect(
			(segments[0].get("color") as Color).is_equal_approx(Color.RED)
			and (segments[1].get("color") as Color).is_equal_approx(Color.RED),
			"level-one physical mirror reflection preserves pulse color"
		)
		_expect(
			float(segments[0].get("length", 0.0)) + float(segments[1].get("length", 0.0)) <= 2.0001,
			"physical-mirror pulse segments share one total range budget"
		)


func _test_level_two_reflection_forks(fixture: Dictionary) -> void:
	var combat: CombatManager = fixture.combat
	var right: ReflectMirror = fixture.right_mirror
	var definition := right.definition as ReflectMirrorDefinition
	definition.level_damage_multipliers = [1.1, 1.1]
	definition.level_penetration_bonuses = [0, 0]
	_expect(right.set_level(2), "reflect mirror upgrades to level two for fork coverage")
	var source_building := (fixture.building as BuildingManager).place_building(
		Vector3i(0, 4, 0),
		(fixture.building as BuildingManager).arrow_tower
	)
	_expect(source_building != null, "fork coverage creates an arrow source for tower-specific penetration")
	if source_building != null:
		source_building.set_process(false)
	var normal := right.get_active_normal()
	var start := right.global_position + Vector3.UP + normal
	var incoming_direction := -normal
	var payload := AttackEffectPayload.new()
	var burst_effect := BurstArrowMirrorEffect.new()
	burst_effect.apply_on_copy(payload, {"copy_kind": &"arrow_tower"})
	_spawned_projectiles.clear()
	if not combat.projectile_spawned.is_connected(_on_fork_projectile_spawned):
		combat.projectile_spawned.connect(_on_fork_projectile_spawned)
	var projectile := combat.spawn_directional_projectile(
		start,
		incoming_direction,
		100.0,
		10.0,
		4.0,
		0.2,
		0.05,
		Color.WHITE,
		null,
		source_building,
		3,
		payload
	)
	projectile.set_process(false)
	projectile._process(0.02)
	_expect(_spawned_projectiles.size() == 3, "one level-two reflection keeps the original projectile and creates two branches")
	var branch_projectiles: Array[Projectile] = []
	for spawned in _spawned_projectiles:
		if spawned != projectile and spawned is Projectile:
			branch_projectiles.append(spawned as Projectile)
	var reflected_direction := (
		incoming_direction - 2.0 * incoming_direction.dot(normal) * normal
	).normalized()
	var branch_angles: Array[float] = []
	for branch in branch_projectiles:
		branch_angles.append(rad_to_deg(reflected_direction.angle_to(branch.get_travel_direction())))
	_expect(
		branch_projectiles.size() == 2
		and branch_angles.all(func(value: float) -> bool: return is_equal_approx(value, 15.0)),
		"projectile branches leave the reflected direction at exact left/right fifteen-degree angles"
	)
	var branches_preserve_snapshot := branch_projectiles.size() == 2
	for branch in branch_projectiles:
		branches_preserve_snapshot = branches_preserve_snapshot and (
			is_equal_approx(branch.debug_get_damage(), 11.0)
			and branch.debug_get_remaining_penetration() == 5
			and branch.debug_get_maximum_distance() < 4.0
			and branch.debug_get_attack_effect_ids().has(&"burst_arrow")
		)
	_expect(
		branches_preserve_snapshot,
		"projectile branches preserve reflected damage, remaining penetration/range, and special effects"
	)
	combat.clear_projectiles()
	_spawned_projectiles.clear()
	_spawned_pulse_lasers.clear()
	if not combat.pulse_laser_spawned.is_connected(_on_fork_pulse_spawned):
		combat.pulse_laser_spawned.connect(_on_fork_pulse_spawned)
	var pulse := combat.spawn_pulse_laser(
		start,
		incoming_direction,
		10.0,
		4.0,
		0.1,
		2.0,
		0.01,
		0.01,
		0.01,
		[Color.RED, Color.ORANGE],
		2
	)
	_expect(pulse != null and _spawned_pulse_lasers.size() == 3, "pulse laser reflection creates two complete beam branches")
	var continuous_path := ContinuousLaserPath.trace(
		combat,
		null,
		start,
		incoming_direction,
		4.0,
		3,
		Callable(fixture.mirror, "trace_projectile_reflection")
	)
	var continuous_branch_segments: Array = continuous_path.get("segments", []).filter(
		func(segment: Dictionary) -> bool: return bool(segment.get("branch", false))
	)
	var continuous_angles_valid := continuous_branch_segments.size() == 2
	for segment in continuous_branch_segments:
		var branch_direction: Vector3 = (
			segment.get("end", Vector3.ZERO) - segment.get("start", Vector3.ZERO)
		).normalized()
		continuous_angles_valid = continuous_angles_valid and is_equal_approx(
			rad_to_deg(reflected_direction.angle_to(branch_direction)),
			15.0
		)
	_expect(
		continuous_angles_valid,
		"continuous laser reflection creates two fifteen-degree branches with the remaining range"
	)
	combat.clear_projectiles()
	right.set_level(1)
	definition.level_damage_multipliers = [1.1, 1.1]
	definition.level_penetration_bonuses = [0, 0]


func _on_fork_projectile_spawned(projectile: Node) -> void:
	_spawned_projectiles.append(projectile)


func _on_fork_pulse_spawned(beam: PulseLaserBeam) -> void:
	_spawned_pulse_lasers.append(beam)


func _test_external_reflector_composition(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var right: ReflectMirror = fixture.right_mirror
	var normal := right.get_active_normal()
	var plane := right.global_position + Vector3.UP
	var start := plane + normal
	var end := plane - normal
	_external_reflection_fraction = 0.25
	_expect(
		mirror_manager.register_projectile_reflection_provider(self, Callable(self, "_trace_external_reflector")),
		"MirrorManager accepts a module-owned finite reflection provider"
	)
	_expect(mirror_manager.get_projectile_reflection_provider_count() == 1, "external reflector registration is queryable")
	var external_first := mirror_manager.trace_projectile_reflection(start, end)
	_expect(external_first.get("reflector") == self and external_first.get("mirror") == null, "nearest external surface wins before a physical reflect mirror")
	_external_reflection_fraction = 0.75
	var mirror_first := mirror_manager.trace_projectile_reflection(start, end)
	_expect(mirror_first.get("mirror") == right, "nearer physical reflect mirror wins before a farther external surface")
	mirror_manager.unregister_projectile_reflection_provider(self)
	_expect(mirror_manager.get_projectile_reflection_provider_count() == 0, "external reflector can unregister without changing mirrors")


func _test_projectile_distance_and_multiple_reflections(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var combat: CombatManager = fixture.combat
	var left := _place_left_mirror(fixture)
	_expect(left != null, "a second reflector can share the same mirror cap")
	var right: ReflectMirror = fixture.right_mirror
	var start := (left.global_position + right.global_position) * 0.5 + Vector3.UP
	var target := CombatTarget.new()
	combat.add_child(target)
	target.configure_debug_target(right.global_position + Vector3.RIGHT * 3.0 + Vector3.UP, 100.0, 0.0, 0.0)
	combat.register_target(target)
	var projectile := Projectile.new()
	combat.add_child(projectile)
	projectile.reflected.connect(_on_projectile_reflected)
	projectile.configure(
		start,
		target,
		100.0,
		10.0,
		5.0,
		0.2,
		0.05,
		Color.WHITE,
		null,
		null,
		Callable(combat, "get_targets"),
		Callable(mirror_manager, "trace_projectile_reflection")
	)
	projectile.set_process(false)
	_reflection_count = 0
	projectile._process(1.0)
	_expect(projectile.has_reflected(), "tower projectile enters ballistic mode after first reflection")
	_expect(_reflection_count >= 2, "one projectile can reflect from multiple mirrors")
	_expect(projectile.get_distance_traveled() <= 5.0001, "all reflected segments share the original maximum flight distance")
	_expect(projectile.is_queued_for_deletion(), "projectile disappears when the shared flight-distance budget is exhausted")


func _test_projection_projectile_reflection(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var combat: CombatManager = fixture.combat
	var building_manager: BuildingManager = fixture.building
	var source := building_manager.place_building(Vector3i(0, 0, 0), building_manager.arrow_tower)
	_expect(source != null, "copy-projectile source tower is available")
	var left: ReflectMirror = fixture.left_mirror
	var right: ReflectMirror = fixture.right_mirror
	var start := (left.global_position + right.global_position) * 0.5 + Vector3.UP
	var projectile := MirrorProjectionProjectile.new()
	combat.add_child(projectile)
	projectile.configure(
		combat,
		source,
		start,
		right.global_position + Vector3.RIGHT * 3.0 + Vector3.UP,
		100.0,
		10.0,
		0.2,
		0.05,
		Color.CYAN,
		null,
		4.0,
		Callable(mirror_manager, "trace_projectile_reflection")
	)
	projectile.set_process(false)
	projectile._process(1.0)
	_expect(projectile.has_reflected(), "copy-tower projectile uses the same reflector query")
	_expect(projectile.get_distance_traveled() <= 4.0001, "copy projectile also preserves the source range budget")


func _test_initial_placement_round_trip(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var placements := mirror_manager.export_initial_placements()
	_expect(placements.size() == 2, "initial layout export includes both physical reflectors")
	_expect(placements.all(func(item: MirrorPlacementData) -> bool:
		return item.mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
	), "initial layout persists the mirror effect kind")
	_expect(mirror_manager.load_initial_placements(placements).is_empty(), "reflector initial layout reloads without charging build cost")
	_expect(mirror_manager.get_reflect_mirrors().size() == 2, "initial layout rebuild restores reflector runtime types")


func _place_right_mirror(fixture: Dictionary) -> ReflectMirror:
	var mirror_manager: MirrorManager = fixture.mirror
	var grid: GridManager = fixture.grid
	var from_cell := Vector3i(3, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, Vector3i(4, 2, 0))
	var mirror := mirror_manager.place_reflect_mirror(from_cell, edge_index, true)
	fixture.right_mirror = mirror
	return mirror


func _place_left_mirror(fixture: Dictionary) -> ReflectMirror:
	var mirror_manager: MirrorManager = fixture.mirror
	var grid: GridManager = fixture.grid
	var from_cell := Vector3i(2, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, Vector3i(1, 2, 0))
	var mirror := mirror_manager.place_reflect_mirror(from_cell, edge_index, true)
	fixture.left_mirror = mirror
	return mirror


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	var resource := ResourceManager.new()
	host.add_child(resource)
	var combat := CombatManager.new()
	host.add_child(combat)
	var building := BuildingManager.new()
	host.add_child(building)
	building.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	building.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building.pulse_laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.PULSE_LASER_TOWER)
	building.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	var registry := EdgeOccupancyRegistry.new()
	building.set_edge_occupancy_registry(registry)
	building.configure(grid, tile, resource, combat)
	var mirror := MirrorManager.new()
	host.add_child(mirror)
	mirror.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror.reflect_mirror_definition = TestDefinitionFactory.make_reflect_mirror_definition()
	mirror.configure(grid, tile, resource, combat, building, registry)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(6, 5)
	level.grid_cell_size = 1.0
	level.initial_resource = 5000.0
	level.building_cap = 20
	level.mirror_cap = 8
	level.base_cell = Vector3i(5, 4, 0)
	resource.apply_level_configuration(level)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile)
	_expect(loader.load_level(level, "memory://reflect-mirror"), "reflect mirror fixture level loads")
	await process_frame
	return {
		"host": host,
		"grid": grid,
		"tile": tile,
		"resource": resource,
		"combat": combat,
		"building": building,
		"mirror": mirror,
	}


func _on_projectile_reflected(_mirror: CopyMirror, _position: Vector3, _direction: Vector3) -> void:
	_reflection_count += 1


func _trace_external_reflector(start: Vector3, end: Vector3) -> Dictionary:
	var segment := end - start
	return {
		"hit": true,
		"position": start.lerp(end, _external_reflection_fraction),
		"normal": Vector3.UP,
		"distance": segment.length() * _external_reflection_fraction,
		"mirror": null,
		"reflector": self,
		"surface_id": &"test_external",
		"epsilon": 0.0001,
		"max_reflections_per_frame": 8,
	}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
