extends SceneTree

const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const CardCooldownSweepScript := preload("res://scripts/ui/CardCooldownSweep.gd")
const MainControllerScript := preload("res://scripts/Main.gd")
const MainScene := preload("res://scenes/Main.tscn")
const FormalLevel := preload("res://resources/levels/Level2.tres")
const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[MirrorPlacementCooldown] running")
	_test_production_resource_contract()
	_test_wave_phase_scale_mapping()
	await _test_formal_level_initial_mirrors()
	var fixture := await _make_fixture()
	await _test_independent_cooldowns_and_card_sweep(fixture)
	var host: Node = fixture.host
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[MirrorPlacementCooldown] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MirrorPlacementCooldown] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_resource_contract() -> void:
	var copy := ResourceLoader.load(
		"res://resources/mirrors/CopyMirror.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as CopyMirrorDefinition
	var reflector := ResourceLoader.load(
		"res://resources/mirrors/ReflectMirror.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as ReflectMirrorDefinition
	_expect(copy != null and copy.validate_configuration().is_empty(), "production copy-mirror resource remains valid after cooldown schema migration")
	_expect(reflector != null and reflector.validate_configuration().is_empty(), "production reflector resource remains valid after cooldown schema migration")
	for definition in [copy, reflector]:
		_expect(is_equal_approx(definition.placement_cooldown_seconds, 15.0), "%s keeps the authored 15-second cooldown" % definition.display_name)
		_expect(is_equal_approx(definition.mirror_thickness_ratio, 0.08), "%s keeps the authored mirror thickness" % definition.display_name)
		_expect(is_equal_approx(definition.reflection_surface_offset_ratio, 0.78), "%s keeps the authored reflection-surface offset" % definition.display_name)
		_expect(definition.reflection_max_updates_per_frame == 2, "%s keeps the authored per-frame reflection budget" % definition.display_name)
		var back_color: Color = definition.mirror_back_face_color
		var darkest_channel := minf(back_color.r, minf(back_color.g, back_color.b))
		var brightest_channel := maxf(back_color.r, maxf(back_color.g, back_color.b))
		_expect(
			brightest_channel - darkest_channel <= 0.05 and is_equal_approx(back_color.a, 1.0),
			"%s keeps an opaque neutral-grey back face" % definition.display_name
		)


func _test_formal_level_initial_mirrors() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(FormalLevel), "Level2 configures for formal mirror assembly")
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(
		main.mirror_manager.get_mirrors().size() == FormalLevel.initial_mirror_placements.size(),
		"Level2 assembles all authored initial mirrors after resource repair"
	)
	main.queue_free()
	await process_frame
	await process_frame


func _test_wave_phase_scale_mapping() -> void:
	var main := MainControllerScript.new() as MainController
	var wave := WaveManager.new()
	main.wave_manager = wave
	main.mirror_preparation_cooldown_time_scale = 0.5
	wave._state = WaveManager.State.READY
	_expect(is_equal_approx(main._get_mirror_cooldown_time_scale(), 0.5), "opening preparation uses the editable half-speed factor")
	wave._state = WaveManager.State.ACTIVE
	wave._spawn_states = [{"remaining": 1}]
	_expect(is_equal_approx(main._get_mirror_cooldown_time_scale(), 1.0), "active wave action restores normal cooldown speed")
	wave._spawn_states.clear()
	_expect(is_equal_approx(main._get_mirror_cooldown_time_scale(), 0.5), "quiet interval before the next release uses preparation speed")
	wave._state = WaveManager.State.VICTORY
	_expect(is_zero_approx(main._get_mirror_cooldown_time_scale()), "terminal wave states stop mirror cooldown recovery")
	main.free()
	wave.free()


func _test_independent_cooldowns_and_card_sweep(fixture: Dictionary) -> void:
	var mirror_manager: MirrorManager = fixture.mirror
	var resource_manager: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	var copy_kind := MirrorPlacementData.MirrorKind.COPY
	var reflect_kind := MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
	var phase_clock := {"scale": 0.5}
	mirror_manager.set_cooldown_time_scale_resolver(func() -> float: return float(phase_clock.scale))

	var card_bar := BuildCardBarScript.new()
	root.add_child(card_bar)
	await process_frame
	var cards: Array[BuildingDefinition] = []
	card_bar.configure(
		resource_manager,
		mirror_manager.copy_mirror_definition,
		cards,
		1,
		mirror_manager.reflect_mirror_definition,
		mirror_manager
	)
	await process_frame
	_expect(resource_manager.main_resource == 0.0, "fixture starts with no spendable resource")
	_expect(card_bar.is_mirror_card_available() and card_bar.is_reflect_mirror_card_available(), "both mirror kinds are ready at level opening")
	_expect(mirror_manager.get_available_mirror_count(copy_kind) == 1 and mirror_manager.get_available_mirror_count(reflect_kind) == 1, "both mirror kinds open with one accumulated placement")

	var copy_from := Vector3i(1, 1, 0)
	var copy_edge := grid.find_edge_index(copy_from, Vector3i(2, 1, 0))
	var copy := mirror_manager.place_copy_mirror(copy_from, copy_edge, true)
	_expect(copy != null, "copy mirror placement succeeds with zero resource")
	_expect(resource_manager.main_resource == 0.0, "placing a mirror never changes the resource balance")
	_expect(mirror_manager.get_available_mirror_count(copy_kind) == 0 and not mirror_manager.is_mirror_kind_ready(copy_kind), "successful copy-mirror placement consumes one accumulated copy")
	_expect(mirror_manager.is_mirror_kind_ready(reflect_kind), "copy-mirror cooldown does not affect the reflector")
	_expect(not card_bar.is_mirror_card_available() and card_bar.is_reflect_mirror_card_available(), "card availability follows the independent kind cooldowns")

	var copy_sweep: Node = card_bar.get_node("Layout/Cards/MirrorCard/CooldownSweep") as Node
	_expect(copy_sweep != null and float(copy_sweep.call("get_ready_ratio")) < 0.01, "fresh cooldown fully covers the copy-mirror card")
	var first_scanline_y: float = float(copy_sweep.call("debug_get_scanline_y"))
	var remaining_before_preparation_advance := mirror_manager.get_placement_cooldown_remaining(copy_kind)
	mirror_manager.advance_placement_cooldowns(4.0)
	_expect(absf(mirror_manager.get_placement_cooldown_remaining(copy_kind) - (remaining_before_preparation_advance - 2.0)) < 0.01, "preparation factor advances ten-second cooldown at half speed")
	_expect(float(copy_sweep.call("get_ready_ratio")) > 0.0 and float(copy_sweep.call("debug_get_scanline_y")) > first_scanline_y, "scanline moves downward while the restored-color region grows")

	var remaining_before_failure := mirror_manager.get_placement_cooldown_remaining(copy_kind)
	var failed_from := Vector3i(0, 1, 0)
	var failed_edge := grid.find_edge_index(failed_from, Vector3i(0, 2, 0))
	_expect(mirror_manager.place_copy_mirror(failed_from, failed_edge, true) == null, "a cooling mirror kind rejects another placement")
	_expect(is_equal_approx(mirror_manager.get_placement_cooldown_remaining(copy_kind), remaining_before_failure), "failed placement does not restart or extend cooldown")

	phase_clock.scale = 1.0
	var remaining_before_active_advance := mirror_manager.get_placement_cooldown_remaining(copy_kind)
	mirror_manager.advance_placement_cooldowns(1.0)
	_expect(absf(mirror_manager.get_placement_cooldown_remaining(copy_kind) - (remaining_before_active_advance - 1.0)) < 0.01, "active-wave factor advances cooldown at normal speed")
	var reflect_from := Vector3i(2, 2, 0)
	var reflect_edge := grid.find_edge_index(reflect_from, Vector3i(3, 2, 0))
	var reflector := mirror_manager.place_reflect_mirror(reflect_from, reflect_edge, true)
	_expect(reflector != null and mirror_manager.get_available_mirror_count(reflect_kind) == 0 and not mirror_manager.is_mirror_kind_ready(reflect_kind), "reflector consumes only its own accumulated placement")
	_expect(resource_manager.get_mirror_count() == resource_manager.mirror_cap, "two physical mirrors fill the shared level cap")
	var reflect_sweep: Node = card_bar.get_node("Layout/Cards/ReflectMirrorCard/CooldownSweep") as Node
	_expect(bool(copy_sweep.call("is_blocked")) and bool(reflect_sweep.call("is_blocked")), "shared cap replaces cooldown progress with a fully unavailable card mask")

	_expect(mirror_manager.remove_mirror(reflector), "reflector can be removed while cooling")
	_expect(resource_manager.main_resource == 0.0, "deleting a mirror does not refund resource")
	_expect(mirror_manager.get_available_mirror_count(reflect_kind) == 1 and mirror_manager.is_mirror_kind_ready(reflect_kind), "demolishing a reflector immediately returns one reflector placement")
	_expect(not bool(copy_sweep.call("is_blocked")), "freeing shared cap restores the copy card's cooldown sweep")
	mirror_manager.advance_placement_cooldowns(20.0)
	_expect(mirror_manager.get_available_mirror_count(copy_kind) == 2, "multiple completed copy cooldowns accumulate multiple placements")
	_expect(mirror_manager.get_available_mirror_count(reflect_kind) == 4, "reflector demolition stock and later cooldown cycles accumulate together")
	var copy_footer := card_bar.get_node("Layout/Cards/MirrorCard/Content/Footer") as Label
	var reflect_footer := card_bar.get_node("Layout/Cards/ReflectMirrorCard/Content/Footer") as Label
	_expect(copy_footer != null and copy_footer.text == "×2", "copy card displays its accumulated placement count")
	_expect(reflect_footer != null and reflect_footer.text == "×4", "reflector card displays its accumulated placement count")

	var placements := mirror_manager.export_initial_placements()
	_expect(mirror_manager.load_initial_placements(placements).is_empty(), "authored initial mirrors reload without consuming placement availability")
	_expect(mirror_manager.is_mirror_kind_ready(copy_kind) and mirror_manager.is_mirror_kind_ready(reflect_kind), "level initial layout always resets both cooldowns to ready")
	_expect(mirror_manager.get_available_mirror_count(copy_kind) == 1 and mirror_manager.get_available_mirror_count(reflect_kind) == 1, "level initial layout resets both accumulated counts to one")
	_expect(resource_manager.main_resource == 0.0, "initial layout reload leaves the economy unchanged")
	card_bar.queue_free()
	await process_frame


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
	building.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	var registry := EdgeOccupancyRegistry.new()
	building.set_edge_occupancy_registry(registry)
	building.configure(grid, tile, resource, combat)
	var mirror := MirrorManager.new()
	host.add_child(mirror)
	var copy_definition := TestDefinitionFactory.make_copy_mirror_definition()
	copy_definition.placement_cooldown_seconds = 10.0
	var reflect_definition := TestDefinitionFactory.make_reflect_mirror_definition()
	reflect_definition.placement_cooldown_seconds = 6.0
	mirror.copy_mirror_definition = copy_definition
	mirror.reflect_mirror_definition = reflect_definition
	mirror.configure(grid, tile, resource, combat, building, registry)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(4, 3)
	level.grid_cell_size = 1.0
	level.initial_resource = 0.0
	level.building_cap = 20
	level.mirror_cap = 2
	level.base_cell = Vector3i(3, 0, 0)
	resource.apply_level_configuration(level)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile)
	_expect(loader.load_level(level, "memory://mirror-placement-cooldown"), "cooldown fixture level loads")
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


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		push_error("  FAIL: %s" % message)
