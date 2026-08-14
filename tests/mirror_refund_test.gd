extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[MirrorRefund] running")
	var fixture := await _make_fixture()
	await _test_full_runtime_refund(fixture)
	await _test_live_relocation_preserves_state(fixture)
	await _test_authored_and_external_removal_boundaries(fixture)
	(fixture.host as Node).queue_free()
	await process_frame
	if _failures == 0:
		print("[MirrorRefund] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MirrorRefund] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_full_runtime_refund(fixture: Dictionary) -> void:
	var manager: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	var copy_from := Vector3i(1, 1, 0)
	var copy_edge := grid.find_edge_index(copy_from, Vector3i(2, 1, 0))
	var copy := manager.place_copy_mirror(copy_from, copy_edge, true)
	_expect(copy != null and is_equal_approx(resource.main_resource, 160.0), "runtime copy mirror spends its 40-resource construction cost")
	_expect(copy != null and is_equal_approx(copy.get_refund_amount(), 40.0), "copy mirror records its construction investment")
	_expect(
		manager.invest_in_mirror(copy, 25.0, "mirror_test_upgrade")
		and is_equal_approx(copy.get_refund_amount(), 65.0),
		"later paid investment accumulates on the same mirror ledger"
	)
	var refund_events: Array[Dictionary] = []
	resource.resource_changed.connect(
		func(current: float, delta: float, reason: String) -> void:
			if reason == "mirror_refund":
				refund_events.append({"current": current, "delta": delta})
	)
	_expect(manager.remove_mirror(copy), "runtime copy mirror demolition succeeds")
	_expect(is_equal_approx(resource.main_resource, 200.0), "copy mirror demolition returns every invested resource")
	_expect(
		refund_events.size() == 1 and is_equal_approx(float(refund_events[0].delta), 65.0),
		"demolition emits one full mirror-refund economy event"
	)
	var reflect_from := Vector3i(2, 2, 0)
	var reflect_edge := grid.find_edge_index(reflect_from, Vector3i(3, 2, 0))
	var reflector := manager.place_reflect_mirror(reflect_from, reflect_edge, true)
	_expect(reflector != null and is_equal_approx(resource.main_resource, 140.0), "runtime reflector records and spends its independent 60-resource cost")
	_expect(manager.remove_mirror(reflector) and is_equal_approx(resource.main_resource, 200.0), "reflector demolition also returns its full investment")


func _test_live_relocation_preserves_state(fixture: Dictionary) -> void:
	var manager: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	var source_cell := Vector3i(1, 1, 0)
	var source_edge := grid.find_edge_index(source_cell, Vector3i(2, 1, 0))
	var mirror := manager.place_copy_mirror(source_cell, source_edge, true)
	_expect(mirror != null and manager.upgrade_mirror(mirror), "relocation fixture creates one upgraded selected mirror")
	var resource_before := resource.main_resource
	var refund_before := mirror.get_refund_amount()
	var count_before := resource.get_copy_mirror_count()
	var target_edge := grid.find_edge_index(source_cell, Vector3i(1, 2, 0))
	_expect(
		manager.update_relocation_preview(mirror, source_cell, target_edge),
		"live mirror drag exposes a legal tile-edge relocation preview"
	)
	var preview := manager.get_preview_mirror()
	_expect(
		preview != null
		and preview.level == mirror.level
		and preview.get_active_cell() == source_cell,
		"relocation preview preserves level and faces the dragged target tile"
	)
	var original_instance_id := mirror.get_instance_id()
	var previous_edge_id := mirror.edge_id
	_expect(manager.relocate_mirror(mirror, source_cell, target_edge), "live mirror relocates to the previewed edge")
	_expect(
		mirror.get_instance_id() == original_instance_id
		and mirror.level == 2
		and is_equal_approx(mirror.get_refund_amount(), refund_before),
		"mirror relocation retains the same upgraded instance and investment ledger"
	)
	_expect(
		is_equal_approx(resource.main_resource, resource_before)
		and resource.get_copy_mirror_count() == count_before,
		"mirror relocation spends no resource and changes no mirror capacity"
	)
	_expect(
		manager.get_mirror(previous_edge_id) == null
		and manager.get_mirror(mirror.edge_id) == mirror
		and manager.get_selected_mirror() == mirror,
		"mirror relocation atomically transfers edge occupancy and selection"
	)
	var edge_before_wheel := mirror.edge_index
	_expect(
		manager.rotate_selected_mirror(1)
		and mirror.edge_index == wrapi(edge_before_wheel + 1, 0, grid.edge_count()),
		"selected placed mirror wheel rotation advances it around the active tile"
	)
	_expect(manager.remove_mirror(mirror), "relocated mirror remains normally removable")
	_expect(is_equal_approx(resource.main_resource, 200.0), "relocated mirror still refunds its complete lifetime investment")
	var reflect_source_cell := Vector3i(2, 1, 0)
	var reflect_source_edge := grid.find_edge_index(reflect_source_cell, Vector3i(3, 1, 0))
	var reflector := manager.place_reflect_mirror(reflect_source_cell, reflect_source_edge, true)
	var reflect_target_edge := grid.find_edge_index(reflect_source_cell, Vector3i(2, 2, 0))
	_expect(
		reflector != null
		and manager.update_relocation_preview(reflector, reflect_source_cell, reflect_target_edge)
		and manager.get_preview_mirror() is ReflectMirror,
		"reflect mirror drag uses the matching reflector relocation preview"
	)
	var reflector_instance_id := reflector.get_instance_id()
	_expect(
		manager.relocate_mirror(reflector, reflect_source_cell, reflect_target_edge)
		and reflector.get_instance_id() == reflector_instance_id
		and reflector.get_active_cell() == reflect_source_cell,
		"reflect mirror relocation keeps the same instance and faces the target tile"
	)
	_expect(manager.remove_mirror(reflector), "relocated reflector remains normally removable")
	_expect(is_equal_approx(resource.main_resource, 200.0), "relocated reflector retains its complete refund")


func _test_authored_and_external_removal_boundaries(fixture: Dictionary) -> void:
	var manager: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	var copy_placement := MirrorPlacementData.new()
	var copy_initial_from := Vector3i(0, 1, 0)
	var copy_initial_edge := grid.find_edge_index(copy_initial_from, Vector3i(0, 2, 0))
	copy_placement.configure(
		copy_initial_from,
		copy_initial_edge,
		true,
		MirrorPlacementData.MirrorKind.COPY,
		3
	)
	var reflect_placement := MirrorPlacementData.new()
	var reflect_initial_from := Vector3i(2, 1, 0)
	var reflect_initial_edge := grid.find_edge_index(reflect_initial_from, Vector3i(3, 1, 0))
	reflect_placement.configure(
		reflect_initial_from,
		reflect_initial_edge,
		true,
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
		2
	)
	_expect(
		manager.load_initial_placements([copy_placement, reflect_placement]).is_empty(),
		"authored initial mirrors load without spending resource"
	)
	_expect(is_equal_approx(resource.main_resource, 200.0), "initial mirror assembly leaves starting resource unchanged")
	var initial_copy := manager.get_mirror(grid.canonical_edge_id(copy_initial_from, copy_initial_edge))
	var initial_reflector := manager.get_mirror(grid.canonical_edge_id(reflect_initial_from, reflect_initial_edge))
	var expected_copy_refund := manager.copy_mirror_definition.get_cumulative_cost(3)
	var expected_reflect_refund := manager.reflect_mirror_definition.get_cumulative_cost(2)
	_expect(
		initial_copy != null and is_equal_approx(initial_copy.get_refund_amount(), expected_copy_refund),
		"level-three initial copy mirror refunds placement plus both upgrades"
	)
	_expect(
		initial_reflector != null and is_equal_approx(initial_reflector.get_refund_amount(), expected_reflect_refund),
		"level-two initial reflector refunds placement plus its first upgrade"
	)
	_expect(manager.remove_mirror(initial_copy), "authored initial copy mirror can be demolished")
	_expect(manager.remove_mirror(initial_reflector), "authored initial reflector can be demolished")
	_expect(
		is_equal_approx(resource.main_resource, 200.0 + expected_copy_refund + expected_reflect_refund),
		"demolishing authored initial mirrors grants their full configured cumulative value"
	)
	resource.set_main_resource(200.0, "mirror_refund_test_reset")
	var external_from := Vector3i(1, 1, 0)
	var external_edge := grid.find_edge_index(external_from, Vector3i(2, 1, 0))
	var external := manager.place_copy_mirror(external_from, external_edge, true)
	_expect(external != null and is_equal_approx(resource.main_resource, 160.0), "external-removal boundary places one paid mirror")
	external.queue_free()
	await process_frame
	_expect(is_equal_approx(resource.main_resource, 160.0), "external deletion is not treated as player demolition and grants no refund")


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
	var registry := EdgeOccupancyRegistry.new()
	building.set_edge_occupancy_registry(registry)
	building.configure(grid, tile, resource, combat)
	var mirror := MirrorManager.new()
	host.add_child(mirror)
	var copy_definition := TestDefinitionFactory.make_copy_mirror_definition()
	copy_definition.placement_cost = 40.0
	var reflect_definition := TestDefinitionFactory.make_reflect_mirror_definition()
	reflect_definition.placement_cost = 60.0
	mirror.copy_mirror_definition = copy_definition
	mirror.reflect_mirror_definition = reflect_definition
	mirror.configure(grid, tile, resource, combat, building, registry)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(4, 3)
	level.grid_cell_size = 1.0
	level.initial_resource = 200
	level.building_cap = 20
	level.copy_mirror_cap = 4
	level.reflect_mirror_cap = 4
	level.base_cell = Vector3i(3, 0, 0)
	resource.apply_level_configuration(level)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile)
	_expect(loader.load_level(level, "memory://mirror-refund"), "mirror refund fixture level loads")
	await process_frame
	return {
		"host": host,
		"grid": grid,
		"resource": resource,
		"mirror": mirror,
	}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
