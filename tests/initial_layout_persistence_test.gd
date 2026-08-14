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
	var selected_building_mesh := _find_first_mesh(arrow)
	var building_selection_overlay := (
		selected_building_mesh.material_overlay as ShaderMaterial
		if selected_building_mesh != null
		else null
	)
	var building_selection_color: Color = (
		building_selection_overlay.get_shader_parameter("highlight_color")
		if building_selection_overlay != null
		else Color.BLACK
	)
	_expect(
		building_selection_overlay != null
		and building_selection_color.r > 0.9
		and building_selection_color.g < 0.1,
		"selected live building receives the conspicuous red shader overlay"
	)
	building_manager.select_building(null)
	_expect(
		selected_building_mesh.material_overlay == null,
		"clearing building selection removes the red shader overlay"
	)
	building_manager.select_building(arrow)
	var resource_before_relocation: float = fixture.resource.main_resource
	var building_count_before_relocation: int = fixture.resource.get_building_count()
	_expect(
		building_manager.update_relocation_preview(arrow, Vector3i(1, 2, 0)),
		"upgraded building exposes a legal drag-relocation preview"
	)
	var relocation_preview := building_manager.get_preview_building()
	_expect(
		relocation_preview != null
		and relocation_preview.level == arrow.level
		and relocation_preview.facing_index == arrow.facing_index,
		"drag preview preserves the source level and facing"
	)
	_expect(
		building_manager.relocate_building_to_cell(arrow, Vector3i(1, 2, 0)),
		"live tile building relocates without reconstruction"
	)
	_expect(
		building_manager.get_building(Vector3i(1, 1, 0)) == null
		and building_manager.get_building(Vector3i(1, 2, 0)) == arrow,
		"tile relocation atomically transfers occupancy to the destination"
	)
	_expect(
		arrow.level == 2
		and arrow.facing_index == 3
		and is_equal_approx(fixture.resource.main_resource, resource_before_relocation)
		and fixture.resource.get_building_count() == building_count_before_relocation,
		"tile relocation preserves upgrades, facing, resources, and building cap usage"
	)
	_expect(
		building_manager.relocate_building_to_cell(arrow, Vector3i(1, 1, 0)),
		"tile building can be dragged back to its original cell"
	)
	building_manager.clear_preview()
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
	var resource_before_initial_demolition: float = fixture.resource.main_resource
	var expected_building_refund := restored_building.get_refund_amount()
	var expected_mirror_refund := restored_mirror.get_refund_amount()
	_expect(
		expected_building_refund > 0.0 and expected_mirror_refund > 0.0,
		"authored initial building and mirror expose full configured refunds"
	)
	building_manager.select_building(restored_building)
	_expect(building_manager.remove_selected_building(), "authored initial building can be demolished through the player action")
	_expect(mirror_manager.remove_mirror(restored_mirror), "authored initial mirror can be demolished through the player action")
	_expect(
		is_equal_approx(
			fixture.resource.main_resource,
			resource_before_initial_demolition + expected_building_refund + expected_mirror_refund
		),
		"initial building and mirror demolition returns construction plus every authored upgrade cost"
	)

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
	var live_building := main.building_manager.get_building(Vector3i(1, 1, 0))
	main.building_manager.select_building(live_building)
	var live_camera := main.cam_rig.get_camera()
	var drag_start_world := main.grid.cell_to_world(Vector3i(1, 1, 0)) + Vector3(
		0.0,
		main.tile_manager.get_world_height(Vector3i(1, 1, 0)),
		0.0
	)
	var drag_end_world := main.grid.cell_to_world(Vector3i(1, 2, 0)) + Vector3(
		0.0,
		main.tile_manager.get_world_height(Vector3i(1, 2, 0)),
		0.0
	)
	var drag_start_screen := live_camera.unproject_position(drag_start_world)
	var drag_end_screen := live_camera.unproject_position(drag_end_world)
	main._begin_building_drag_candidate(drag_start_screen)
	main._update_building_drag_gesture(drag_end_screen)
	main._finish_building_drag(drag_end_screen)
	_expect(
		main.building_manager.get_building(Vector3i(1, 2, 0)) == live_building
		and main.building_manager.get_building(Vector3i(1, 1, 0)) == null,
		"Main hold-and-drag gesture relocates the selected live building"
	)
	_expect(
		main.runtime_interaction.get_world_selection_cell() == Vector3i(1, 2, 0),
		"drag relocation keeps world selection attached to the moved building"
	)
	var live_mirror := main.mirror_manager.get_mirrors()[0] as CopyMirror
	var live_mirror_instance_id := live_mirror.get_instance_id()
	var live_mirror_level := live_mirror.level
	var live_mirror_refund := live_mirror.get_refund_amount()
	var mirror_body := live_mirror.get_node("MirrorBody") as MeshInstance3D
	var mirror_start_screen := live_camera.unproject_position(
		mirror_body.global_position
	)
	var mirror_target_cell := Vector3i(2, 1, 0)
	var mirror_end_world := main.grid.cell_to_world(mirror_target_cell) + Vector3(
		0.0,
		main.tile_manager.get_world_height(mirror_target_cell),
		0.0
	)
	var mirror_end_screen := live_camera.unproject_position(mirror_end_world)
	var mirror_pick := main.mirror_manager.pick_mirror(live_camera, mirror_start_screen)
	main.runtime_interaction.handle_primary({"hit": false}, {"hit": false}, mirror_pick)
	main._begin_building_drag_candidate(mirror_start_screen)
	main._update_building_drag_gesture(mirror_end_screen)
	main._finish_building_drag(mirror_end_screen)
	_expect(
		live_mirror.get_instance_id() == live_mirror_instance_id
		and live_mirror.get_active_cell() == mirror_target_cell,
		"Main hold-and-drag gesture relocates the same selected live mirror"
	)
	_expect(
		live_mirror.level == live_mirror_level
		and is_equal_approx(live_mirror.get_refund_amount(), live_mirror_refund),
		"mirror drag preserves its level and cumulative refund"
	)
	_expect(
		main.runtime_interaction.get_world_selection_cell() == mirror_target_cell
		and main.runtime_interaction.get_world_selection_edge_id() == live_mirror.edge_id,
		"mirror drag keeps world selection attached to its new edge"
	)
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
	var copy_mirror_definition := TestDefinitionFactory.make_copy_mirror_definition()
	copy_mirror_definition.placement_cost = 40.0
	mirror.copy_mirror_definition = copy_mirror_definition
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


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null
