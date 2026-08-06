extends SceneTree

const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const MainScene := preload("res://scenes/Main.tscn")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")
const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[InitialLayoutPersistence] running")
	var fixture := _make_fixture()
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var arrow: Building = building_manager.place_building(
		Vector3i(1, 1, 0),
		building_manager.arrow_tower,
		3
	)
	_expect(arrow != null and arrow.apply_level(2), "runtime fixture places and upgrades one real building")
	var mirror: CopyMirror = mirror_manager.place_copy_mirror(Vector3i(2, 1, 0), 0, false)
	_expect(mirror != null, "runtime fixture places one real copy mirror")
	var resource_after_runtime_placement: float = fixture.resource.main_resource

	var validator := StuffPlacementValidatorScript.new()
	validator.configure(fixture.grid, fixture.tile, fixture.terrain, fixture.stuff)
	var session: RuntimeStuffEditSession = RuntimeStuffEditSessionScript.new()
	fixture.host.add_child(session)
	session.configure(
		fixture.stuff,
		validator,
		Callable(),
		Callable(building_manager, "export_initial_placements"),
		Callable(mirror_manager, "export_initial_placements")
	)
	_expect(session.begin(fixture.level, "memory://initial-layout"), "runtime authoring session starts")
	_expect(session.can_save_full_layout(), "session detects both full-layout snapshot providers")
	var save_path := "user://initial_layout_persistence_test.tres"
	var full_result: Dictionary = session.save(save_path, true)
	_expect(bool(full_result.success), "full save writes Stuff and the current real layout")
	_expect(is_equal_approx(fixture.resource.main_resource, resource_after_runtime_placement), "saving never changes live economy")
	var saved: LevelResource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_expect(saved != null, "full-save LevelResource reloads")
	_expect(saved.initial_building_placements.size() == 1, "full save persists one initial building")
	_expect(saved.initial_mirror_placements.size() == 1, "full save persists one initial mirror")
	if saved != null and not saved.initial_building_placements.is_empty():
		var building_data: BuildingPlacementData = saved.initial_building_placements[0]
		_expect(building_data.cell == Vector3i(1, 1, 0), "building cell round-trips")
		_expect(building_data.facing_index == 3, "building logical facing round-trips")
		_expect(building_data.level == 2, "building level round-trips")
	if saved != null and not saved.initial_mirror_placements.is_empty():
		var mirror_data: MirrorPlacementData = saved.initial_mirror_placements[0]
		_expect(mirror_data.from_cell == Vector3i(2, 1, 0) and mirror_data.edge_index == 0, "mirror edge round-trips")
		_expect(not mirror_data.active_from_side, "mirror active side round-trips")
	var duplicate_building_level := saved.duplicate(true) as LevelResource
	duplicate_building_level.initial_building_placements.append(
		duplicate_building_level.initial_building_placements[0].duplicate_placement()
	)
	_expect(_contains(duplicate_building_level.validate_runtime(), "占格重复"), "level preflight rejects duplicate initial building occupancy")
	var duplicate_mirror_level := saved.duplicate(true) as LevelResource
	duplicate_mirror_level.initial_mirror_placements.append(
		duplicate_mirror_level.initial_mirror_placements[0].duplicate_placement()
	)
	_expect(_contains(duplicate_mirror_level.validate_runtime(), "同一物理边"), "level preflight rejects duplicate initial mirror edges")
	var over_cap_level := saved.duplicate(true) as LevelResource
	over_cap_level.building_cap = 0
	_expect(_contains(over_cap_level.validate_runtime(), "超过建筑上限"), "level preflight rejects initial layouts over cap")

	_expect(
		building_manager.place_building(Vector3i(0, 2, 0), building_manager.arrow_tower, 1) != null,
		"runtime can diverge from the saved initial layout"
	)
	var stuff_only_result: Dictionary = session.save(save_path)
	_expect(bool(stuff_only_result.success), "ordinary save remains available after full save")
	saved = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	_expect(saved.initial_building_placements.size() == 1, "ordinary save does not overwrite the initial building layout")
	_expect(saved.initial_mirror_placements.size() == 1, "ordinary save does not overwrite the initial mirror layout")
	_expect(session.end_after_save(), "clean authoring session ends")

	_expect(fixture.loader.load_level(saved, "memory://saved-initial-layout"), "saved level passes runtime preflight")
	fixture.resource.apply_level_configuration(saved)
	var building_errors := building_manager.load_initial_placements(saved.initial_building_placements)
	var mirror_errors := mirror_manager.load_initial_placements(saved.initial_mirror_placements)
	_expect(building_errors.is_empty() and mirror_errors.is_empty(), "saved initial layout assembles without rejection")
	_expect(building_manager.get_buildings().size() == 1, "reload restores exactly the authored building")
	_expect(mirror_manager.get_mirrors().size() == 1, "reload restores exactly the authored mirror")
	_expect(fixture.resource.get_building_count() == 1 and fixture.resource.get_mirror_count() == 1, "initial layout counts toward both caps")
	_expect(is_equal_approx(fixture.resource.main_resource, float(saved.initial_resource)), "initial layout does not consume initial_resource")
	var restored_building := building_manager.get_building(Vector3i(1, 1, 0))
	_expect(restored_building != null and restored_building.level == 2 and restored_building.facing_index == 3, "reload restores building level and logical facing")
	var restored_mirror: CopyMirror = mirror_manager.get_mirrors()[0] if not mirror_manager.get_mirrors().is_empty() else null
	_expect(restored_mirror != null and not restored_mirror.active_from_side, "reload restores mirror active side")

	fixture.host.queue_free()
	await process_frame
	await process_frame
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(saved), "Main accepts the saved level as its startup resource")
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.building_manager.get_buildings().size() == 1, "Main level-loaded composition restores initial buildings")
	_expect(main.mirror_manager.get_mirrors().size() == 1, "Main level-loaded composition restores initial mirrors")
	_expect(is_equal_approx(main.resource_manager.main_resource, float(saved.initial_resource)), "Main initial layout preserves the configured starting resource")
	main.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if _failures == 0:
		print("[InitialLayoutPersistence] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[InitialLayoutPersistence] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var terrain := TerrainManager.new()
	host.add_child(terrain)
	terrain.set_grid(grid)
	var stuff := StuffManagerScript.new()
	host.add_child(stuff)
	stuff.configure(grid, terrain)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	tile.legacy_content_runtime_enabled = false
	tile.set_stuff_runtime_provider(stuff)
	tile.set_surface_height_resolver(Callable(terrain, "get_world_height"))
	tile.set_base_placement_resolvers(
		Callable(terrain, "allows_tile_building"),
		Callable(terrain, "allows_edge_building")
	)
	var resource := ResourceManager.new()
	host.add_child(resource)
	var combat := CombatManager.new()
	host.add_child(combat)
	var registry := EdgeOccupancyRegistry.new()
	var building := BuildingManager.new()
	host.add_child(building)
	building.arrow_tower = load("res://resources/buildings/ArrowTower.tres")
	building.set_edge_occupancy_registry(registry)
	building.configure(grid, tile, resource, combat)
	var mirror := MirrorManager.new()
	host.add_child(mirror)
	mirror.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror.configure(grid, tile, resource, combat, building, registry)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain, stuff)
	var level := _make_level()
	_expect(loader.load_level(level, "memory://initial-layout-fixture"), "initial-layout fixture loads")
	resource.apply_level_configuration(level)
	return {
		"host": host,
		"grid": grid,
		"terrain": terrain,
		"stuff": stuff,
		"tile": tile,
		"resource": resource,
		"combat": combat,
		"building": building,
		"mirror": mirror,
		"loader": loader,
		"level": level,
	}


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.display_name = "Initial Layout Persistence Test"
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 3)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 1.0
	level.height_step = 1.0
	level.initial_resource = 1000
	level.building_cap = 10
	level.mirror_cap = 4
	level.base_resource_per_second = 0.0
	level.base_cell = Vector3i(3, 2, 0)
	for x in range(level.grid_size.x):
		for y in range(level.grid_size.y):
			var cell := GridCellData.new()
			cell.configure(Vector3i(x, y, 0), level.default_terrain, 1, true, true)
			level.grid_cells.append(cell)
	return level


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)


func _contains(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if needle in error:
			return true
	return false
