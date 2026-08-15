extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const GuardScript := preload("res://scripts/path/PathPlacementConnectivityGuard.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[PathPlacementConnectivity] running")
	await _test_last_square_route_is_rejected()
	await _test_alternate_route_then_last_route()
	await _test_hex_and_airborne_profiles()
	await _test_edge_barrier_is_rejected()
	await _test_mirror_recursive_blocker_is_rejected()
	await _test_mirror_effect_free_stuff_blocker_is_rejected()
	if _failures == 0:
		print("[PathPlacementConnectivity] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[PathPlacementConnectivity] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_last_square_route_is_rejected() -> void:
	var level := _make_single_route_level(GridManager.Shape.SQUARE)
	var fixture := _make_fixture(level)
	var building: BuildingManager = fixture.building
	var resource: ResourceManager = fixture.resource
	var blocked_cell: Vector3i = level.paths[0].cells[2]
	var resource_before := resource.main_resource
	_expect(building.update_preview(blocked_cell, building.barrier), "single-route barrier still renders a placement preview")
	_expect(not building.get_preview_building().is_preview_valid(), "single-route barrier preview is marked invalid for red rendering")
	_expect(building.place_building(blocked_cell, building.barrier) == null, "barrier cannot remove the final square route")
	_expect(is_equal_approx(resource.main_resource, resource_before), "rejected barrier does not spend resources")
	_expect(building.get_building(blocked_cell) == null, "rejected barrier creates no runtime building")
	await _dispose_fixture(fixture)


func _test_alternate_route_then_last_route() -> void:
	var level := _make_alternate_route_level()
	var fixture := _make_fixture(level)
	var building: BuildingManager = fixture.building
	var first_cell := Vector3i(2, 2, 0)
	var last_cell := Vector3i(2, 1, 0)
	var first_barrier := building.place_building(first_cell, building.barrier)
	_expect(first_barrier != null, "blocking one branch is allowed while an alternate target route remains")
	_expect(building.update_preview(last_cell, building.barrier), "last-branch blocker keeps its red preview visible")
	_expect(not building.get_preview_building().is_preview_valid(), "last alternate branch is detected before placement")
	_expect(building.place_building(last_cell, building.barrier) == null, "second barrier cannot close every route to the same target base")
	_expect(
		building.update_relocation_preview(first_barrier, last_cell)
		and building.get_preview_building().is_preview_valid(),
		"relocation preview evaluates the destination with the source blocker removed"
	)
	_expect(
		building.relocate_building_to_cell(first_barrier, last_cell),
		"moving the existing branch blocker succeeds because its old branch is reopened"
	)
	_expect(
		building.get_building(first_cell) == null
		and building.get_building(last_cell) == first_barrier,
		"connectivity-safe relocation transfers path occupancy atomically"
	)
	await _dispose_fixture(fixture)


func _test_hex_and_airborne_profiles() -> void:
	var hex_level := _make_single_route_level(GridManager.Shape.HEX)
	var hex_fixture := _make_fixture(hex_level)
	var hex_building: BuildingManager = hex_fixture.building
	var hex_cell: Vector3i = hex_level.paths[0].cells[2]
	_expect(hex_building.place_building(hex_cell, hex_building.barrier) == null, "hex adjacency also protects the final target route")
	await _dispose_fixture(hex_fixture)

	var airborne_level := _make_single_route_level(GridManager.Shape.SQUARE)
	var flying := EnemyDefinition.new()
	flying.enemy_id = &"test_flying"
	flying.display_name = "测试飞行敌人"
	flying.is_airborne = true
	var group := SpawnGroupDefinition.new()
	group.enemy = flying
	group.path = airborne_level.paths[0]
	group.spawn_point = airborne_level.spawn_points[0]
	var wave := WaveDefinition.new()
	wave.spawn_groups.append(group)
	airborne_level.waves.append(wave)
	var airborne_fixture := _make_fixture(airborne_level)
	var airborne_building: BuildingManager = airborne_fixture.building
	airborne_building.barrier.levels[0].affects_airborne = false
	var airborne_cell: Vector3i = airborne_level.paths[0].cells[2]
	_expect(airborne_building.place_building(airborne_cell, airborne_building.barrier) != null, "ground-only barrier does not falsely block an airborne-only route profile")
	await _dispose_fixture(airborne_fixture)


func _test_edge_barrier_is_rejected() -> void:
	var level := _make_single_route_level(GridManager.Shape.SQUARE)
	var obstacle_cell := Vector3i(1, 1, 0)
	level.store_tile(_make_effect_tile(obstacle_cell, RockTileEffect.new()))
	var fixture := _make_fixture(level)
	var grid: GridManager = fixture.grid
	var building: BuildingManager = fixture.building
	var mirror: MirrorManager = fixture.mirror
	var from_cell: Vector3i = level.paths[0].cells[1]
	var to_cell: Vector3i = level.paths[0].cells[2]
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	_expect(not building.update_preview(from_cell, building.arrow_tower), "ordinary building placement rejects an enemy-path tile")
	_expect(building.get_preview_building() != null and building.get_preview_building().visible, "rejected enemy-path tile keeps the physical building preview visible")
	_expect(_is_red(building.get_preview_building().get_preview_display_color()), "enemy-path building preview is red")
	_expect(not building.update_preview(obstacle_cell, building.arrow_tower), "ordinary building placement rejects an obstacle tile")
	_expect(building.get_preview_building() != null and building.get_preview_building().visible, "rejected obstacle tile keeps the physical building preview visible")
	_expect(_is_red(building.get_preview_building().get_preview_display_color()), "obstacle-tile building preview is red")
	var movable_building_cell := Vector3i(0, 0, 0)
	var movable_building := building.place_building(movable_building_cell, building.arrow_tower)
	_expect(movable_building != null, "relocation fixture places a live tile building")
	_expect(
		not building.update_relocation_preview(movable_building, obstacle_cell),
		"live tile building may be adjusted onto an invalid obstacle cell"
	)
	_expect(
		building.get_preview_building() != null
		and building.get_preview_building().visible
		and _is_red(building.get_preview_building().get_preview_display_color()),
		"invalid live-building adjustment retains a red body ghost"
	)
	_expect(
		building.get_building(movable_building_cell) == movable_building
		and building.get_building(obstacle_cell) == null
		and not building.commit_relocation_preview(movable_building),
		"red tile adjustment leaves the original live occupancy unchanged and cannot commit"
	)
	var valid_building_target := Vector3i(1, 0, 0)
	_expect(
		building.update_relocation_preview(movable_building, valid_building_target)
		and building.is_relocation_preview_valid(movable_building),
		"the same adjustment ghost turns valid on an allowed tile"
	)
	_expect(
		building.get_building(movable_building_cell) == movable_building
		and building.get_building(valid_building_target) == null,
		"green tile adjustment still leaves the original live building active before confirm"
	)
	_expect(
		building.commit_relocation_preview(movable_building)
		and building.get_building(valid_building_target) == movable_building
		and building.get_building(movable_building_cell) == null,
		"confirming the green tile adjustment atomically applies it"
	)
	_expect(not building.update_edge_preview(from_cell, edge_index, building.edge_barrier), "path-to-path edge permission rejects the edge-barrier preview")
	_expect(building.get_preview_building() != null and building.get_preview_building().visible, "rejected path edge keeps the physical edge-building preview visible")
	_expect(_is_red(building.get_preview_building().get_preview_display_color()), "path-edge building preview is red")
	_expect(building.place_edge_building(from_cell, edge_index, building.edge_barrier) == null, "edge barrier cannot be placed between two path tiles")
	_expect(not mirror.update_preview(from_cell, edge_index), "path-to-path edge permission also rejects the mirror preview")
	_expect(mirror.get_preview_mirror() != null and mirror.get_preview_mirror().visible, "rejected mirror edge keeps the physical mirror preview visible")
	_expect(_is_red(mirror.get_preview_mirror().get_preview_display_color()), "invalid-edge mirror preview is red")
	var invalid_surface_overlay := mirror.get_preview_mirror().get_reflection_surface().material_overlay as StandardMaterial3D
	_expect(invalid_surface_overlay != null and _is_red(invalid_surface_overlay.albedo_color), "red placement tint also covers the mirror face")
	_expect(mirror.get_preview_projections().is_empty(), "invalid mirror edge keeps the original copied-preview behavior")
	_expect(mirror.place_copy_mirror(from_cell, edge_index, true) == null, "a mirror cannot be placed between two path tiles")
	var movable_mirror_cell := Vector3i(5, 0, 0)
	var movable_mirror_edge := grid.find_edge_index(movable_mirror_cell, Vector3i(6, 0, 0))
	var movable_mirror := mirror.place_copy_mirror(movable_mirror_cell, movable_mirror_edge, true)
	_expect(movable_mirror != null, "relocation fixture places a live mirror on an allowed edge")
	var original_mirror_edge_id := movable_mirror.edge_id
	_expect(
		not mirror.update_relocation_preview(movable_mirror, from_cell, edge_index),
		"live mirror may be adjusted onto an invalid path-common edge"
	)
	_expect(
		mirror.get_preview_mirror() != null
		and mirror.get_preview_mirror().visible
		and _is_red(mirror.get_preview_mirror().get_preview_display_color()),
		"invalid live-mirror adjustment retains a red body ghost"
	)
	_expect(
		mirror.get_mirror(original_mirror_edge_id) == movable_mirror
		and not mirror.commit_relocation_preview(movable_mirror),
		"red mirror adjustment keeps the original live edge and cannot commit"
	)
	var boundary_cell := Vector3i.ZERO
	var boundary_edge := -1
	for candidate_edge in range(grid.edge_count()):
		if not grid.is_in_bounds(grid.neighbor_across_edge(boundary_cell, candidate_edge)):
			boundary_edge = candidate_edge
			break
	_expect(boundary_edge >= 0, "fixture exposes an outward-facing boundary edge")
	_expect(not mirror.update_preview(boundary_cell, boundary_edge), "rotating a mirror toward the map boundary remains invalid")
	_expect(mirror.get_preview_mirror() != null and mirror.get_preview_mirror().visible, "invalid boundary keeps the physical mirror preview visible")
	_expect(_is_red(mirror.get_preview_mirror().get_preview_display_color()), "invalid-boundary mirror preview is red")
	_expect(mirror.get_preview_projections().is_empty(), "invalid boundary does not create copied-object previews")
	await _dispose_fixture(fixture)


func _test_mirror_recursive_blocker_is_rejected() -> void:
	var level := _make_vertical_mirror_route_level()
	var rock := RockTileEffect.new()
	rock.enemy_traversal = TileEffect.EnemyTraversal.BLOCKED
	level.store_tile(_make_effect_tile(Vector3i(1, 2, 0), rock))
	var fixture := _make_fixture(level)
	var grid: GridManager = fixture.grid
	var mirror: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var first_from := Vector3i(2, 2, 0)
	var first_edge := grid.find_edge_index(first_from, Vector3i(3, 2, 0))
	_expect(mirror.place_copy_mirror(first_from, first_edge, true) != null, "first mirror may project the rock outside every protected route")
	_expect(not mirror.get_projections(Vector3i(4, 2, 0)).is_empty(), "first mirror creates the recursive source projection")
	var from_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, Vector3i(6, 2, 0))
	var resource_before := resource.main_resource
	_expect(mirror.update_preview(from_cell, edge_index), "mirror with a recursively copied blocker keeps its placement preview")
	var preview := mirror.get_preview_info()
	_expect(not bool(preview.get("valid", true)), "mirror preview reports final-route disconnection")
	_expect(not mirror.get_preview_mirror().is_preview_valid(), "invalid mirror frame uses the red preview state")
	var preview_projections := mirror.get_preview_projections()
	_expect(not preview_projections.is_empty() and not preview_projections[0].preview_valid, "blocking copied object uses the same red preview state")
	_expect(mirror.place_copy_mirror(from_cell, edge_index, true) == null, "mirror cannot recursively create a blocker on the final route")
	_expect(mirror.get_mirrors().size() == 1, "rejected mirror leaves only the previously valid physical mirror")
	_expect(is_equal_approx(resource.main_resource, resource_before), "rejected mirror does not spend resources")
	await _dispose_fixture(fixture)


func _test_mirror_effect_free_stuff_blocker_is_rejected() -> void:
	var level := _make_vertical_mirror_route_level()
	var fixture := _make_fixture(level, true)
	var grid: GridManager = fixture.grid
	var mirror: MirrorManager = fixture.mirror
	var stuff: StuffManager = fixture.stuff
	var blocker := StuffDefinition.new()
	blocker.stuff_id = &"effect_free_highstone"
	blocker.display_name = "Effect-free high stone"
	blocker.enemy_navigation = StuffDefinition.EnemyNavigation.BLOCKED
	blocker.durability_mode = StuffDefinition.DurabilityMode.INDESTRUCTIBLE
	blocker.fallback_visual_kind = StuffDefinition.FallbackVisualKind.ROCK
	_expect(
		stuff.add_stuff(Vector3i(1, 2, 0), blocker, 0, &"effect_free_highstone_1") != null,
		"effect-free Stuff source is available to the mirror graph"
	)
	var first_from := Vector3i(2, 2, 0)
	var first_edge := grid.find_edge_index(first_from, Vector3i(3, 2, 0))
	_expect(
		mirror.place_copy_mirror(first_from, first_edge, true) != null,
		"first mirror may project effect-free Stuff outside the protected route"
	)
	var from_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, Vector3i(6, 2, 0))
	_expect(
		mirror.update_preview(from_cell, edge_index),
		"effect-free Stuff blocker keeps a visible candidate mirror preview"
	)
	_expect(
		not bool(mirror.get_preview_info().get("valid", true)),
		"effect-free Stuff mirror preview detects final-route disconnection"
	)
	_expect(
		mirror.place_copy_mirror(from_cell, edge_index, true) == null,
		"mirror cannot close the final route with palm/high-stone-style Stuff"
	)
	await _dispose_fixture(fixture)


func _make_fixture(level: LevelResource, include_stuff: bool = false) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	var terrain: TerrainManager = null
	var stuff: StuffManager = null
	if include_stuff:
		terrain = TerrainManager.new()
		host.add_child(terrain)
		terrain.set_grid(grid)
		stuff = StuffManager.new()
		host.add_child(stuff)
		stuff.configure(grid, terrain)
		tile.legacy_content_runtime_enabled = false
		tile.set_stuff_runtime_provider(stuff)
		tile.set_surface_height_resolver(Callable(terrain, "get_world_height"))
		tile.set_base_placement_resolvers(
			Callable(terrain, "allows_tile_building"),
			Callable(terrain, "allows_edge_building")
		)
	var resource := ResourceManager.new()
	host.add_child(resource)
	resource.apply_level_configuration(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	var registry := EdgeOccupancyRegistry.new()
	var building := BuildingManager.new()
	host.add_child(building)
	building.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	building.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	building.set_edge_occupancy_registry(registry)
	building.configure(grid, tile, resource, combat)
	var mirror := MirrorManager.new()
	host.add_child(mirror)
	mirror.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror.configure(grid, tile, resource, combat, building, registry)
	if stuff != null:
		mirror.set_stuff_manager(stuff)
	building.set_projection_blocker_resolver(Callable(mirror, "resolve_projected_blocker"))
	tile.set_navigation_overlay_resolver(Callable(mirror, "blocks_enemy_navigation"))
	tile.set_navigation_overlay_blocker_resolver(Callable(mirror, "resolve_projected_navigation_blocker"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain, stuff)
	_expect(loader.load_level(level, "memory://path-placement-connectivity"), "connectivity fixture level loads")
	var guard: PathPlacementConnectivityGuard = GuardScript.new()
	host.add_child(guard)
	guard.configure(
		grid,
		tile,
		Callable(building, "resolve_physical_path_blocker"),
		Callable(mirror, "get_prospective_blocked_cells")
	)
	guard.load_level(level)
	building.set_path_connectivity_validator(Callable(guard, "validate_change"))
	mirror.set_path_connectivity_validator(Callable(guard, "validate_change"))
	return {
		"host": host,
		"grid": grid,
		"tile": tile,
		"resource": resource,
		"building": building,
		"mirror": mirror,
		"terrain": terrain,
		"stuff": stuff,
	}


func _make_single_route_level(shape: GridManager.Shape) -> LevelResource:
	var cells: Array[Vector3i]
	if shape == GridManager.Shape.HEX:
		cells = [
			Vector3i(-2, 0, 2),
			Vector3i(-1, 0, 1),
			Vector3i.ZERO,
			Vector3i(1, -1, 0),
			Vector3i(2, -2, 0),
		]
	else:
		cells = [
			Vector3i(0, 2, 0),
			Vector3i(1, 2, 0),
			Vector3i(2, 2, 0),
			Vector3i(3, 2, 0),
			Vector3i(4, 2, 0),
		]
	return _make_level(shape, [cells])


func _make_alternate_route_level() -> LevelResource:
	return _make_level(GridManager.Shape.SQUARE, [
		[
			Vector3i(0, 2, 0), Vector3i(1, 2, 0), Vector3i(2, 2, 0),
			Vector3i(3, 2, 0), Vector3i(4, 2, 0),
		],
		[
			Vector3i(0, 2, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
			Vector3i(2, 1, 0), Vector3i(3, 1, 0), Vector3i(4, 1, 0),
			Vector3i(4, 2, 0),
		],
	])


func _make_vertical_mirror_route_level() -> LevelResource:
	var level := _make_level(GridManager.Shape.SQUARE, [[
		Vector3i(7, 0, 0), Vector3i(7, 1, 0), Vector3i(7, 2, 0),
		Vector3i(7, 3, 0), Vector3i(7, 4, 0),
	]])
	level.grid_size = Vector2i(9, 5)
	return level


func _make_level(shape: GridManager.Shape, path_cells: Array) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = shape
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(7, 5)
	level.initial_resource = 5000.0
	level.building_cap = 20
	level.mirror_cap = 10
	level.base_resource_per_second = 0.0
	var spawn := SpawnPointDefinition.new()
	spawn.spawn_id = &"spawn_1"
	spawn.display_name = "测试出生点"
	spawn.display_number = 1
	spawn.cell = path_cells[0][0]
	level.spawn_points.append(spawn)
	for index in range(path_cells.size()):
		var path := PathDefinition.new()
		path.path_id = StringName("path_%d" % (index + 1))
		path.display_name = "测试路径%d" % (index + 1)
		path.spawn_point = spawn
		for cell in path_cells[index]:
			path.cells.append(cell)
		level.paths.append(path)
	level.base_cell = level.paths[0].get_end_cell()
	return level


func _make_effect_tile(cell: Vector3i, effect: TileEffect) -> TileCellData:
	var definition := TileDefinition.new()
	definition.tile_id = &"test_rock"
	definition.display_name = "测试大石头"
	definition.surface_kind = TileDefinition.SurfaceKind.ELEMENT
	definition.allows_tile_building = false
	definition.allows_edge_building = true
	definition.effect = effect
	definition.visual_kind = TileDefinition.VisualKind.ROCK
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.DESTRUCTIBLE, 0, definition)
	return tile


func _dispose_fixture(fixture: Dictionary) -> void:
	var host: Node = fixture.host
	host.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)


func _is_red(color: Color) -> bool:
	return color.r > 0.8 and color.g < 0.3 and color.b < 0.3
