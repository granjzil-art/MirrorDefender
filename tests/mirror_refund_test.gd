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


func _test_authored_and_external_removal_boundaries(fixture: Dictionary) -> void:
	var manager: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	var placement := MirrorPlacementData.new()
	var initial_from := Vector3i(0, 1, 0)
	var initial_edge := grid.find_edge_index(initial_from, Vector3i(0, 2, 0))
	placement.configure(initial_from, initial_edge, true, MirrorPlacementData.MirrorKind.COPY)
	_expect(manager.load_initial_placements([placement]).is_empty(), "authored initial mirror loads without spending resource")
	var initial_mirror := manager.get_mirrors()[0] if not manager.get_mirrors().is_empty() else null
	_expect(initial_mirror != null and is_zero_approx(initial_mirror.get_refund_amount()), "authored initial mirror owns no refundable investment")
	_expect(manager.remove_mirror(initial_mirror) and is_equal_approx(resource.main_resource, 200.0), "demolishing an authored free mirror creates no resource")
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
