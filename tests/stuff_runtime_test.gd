extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffRendererScript := preload("res://scripts/stuff/StuffRenderer.gd")
const RejectingTileManager := preload("res://tests/fixtures/RejectingTileManager.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[StuffRuntime] running")
	await _test_multiple_stuff_permissions_effects_and_durability()
	await _test_mirror_copies_every_stuff_with_shared_effect_identity()
	await _test_catalog_definition_supersedes_stale_level_copy()
	await _test_level2_spruce_uses_catalog_definition()
	await _test_legacy_level_uses_transient_stuff()
	await _test_loader_rolls_back_stuff()
	if _failures == 0:
		print("[StuffRuntime] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[StuffRuntime] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_multiple_stuff_permissions_effects_and_durability() -> void:
	var level := _make_canonical_level(true)
	var fixture := _make_fixture(level)
	var stuff: StuffManagerScript = fixture.stuff
	var tile: TileManager = fixture.tile
	var source := Vector3i(2, 2, 0)
	var items := stuff.get_stuff_at(source)
	_expect(items.size() == 2, "one Grid cell preserves two independent Stuff runtimes")
	_expect(stuff.get_effect_bindings(source).size() == 2, "each coexisting Stuff exposes its own effect binding")
	var keys: Dictionary = {}
	for binding in stuff.get_effect_bindings(source):
		keys[str(binding.state_key)] = true
	_expect(keys.size() == 2, "coexisting timed effects use placement-scoped runtime keys")
	_expect(not tile.can_place(source), "any Stuff tile-building veto composes with the Grid permission")
	_expect(tile.allows_edge_building(source), "Stuff that does not block edges preserves the Grid edge permission")
	var rock_cell := Vector3i(1, 1, 0)
	var rock: StuffRuntime = stuff.get_stuff_at(rock_cell)[0]
	_expect(tile.blocks_enemy_navigation(rock_cell), "independent rock Stuff reaches the navigation facade")
	_expect(tile.resolve_navigation_blocker(rock_cell) == rock, "navigation resolves the concrete Stuff attack target")
	var rock_center := stuff.get_ballistic_blocker_center(rock)
	var rock_ballistic_hit := stuff.trace_ballistic_blocker(
		rock_center - Vector3.RIGHT * 2.0,
		rock_center + Vector3.RIGHT * 2.0
	)
	_expect(
		bool(rock_ballistic_hit.get("hit", false)) and rock_ballistic_hit.get("blocker") == rock,
		"ballistic query resolves the live Rock Stuff sphere"
	)
	var effect_system := TileEffectSystem.new()
	fixture.host.add_child(effect_system)
	effect_system.configure(tile)
	effect_system.set_base_effect_provider(stuff)
	var inspection := TileInspectionModelBuilder.new()
	inspection.configure(fixture.grid, tile, null, null, effect_system, stuff, fixture.terrain)
	var rock_model := inspection.inspect_cell(rock_cell)
	_expect(rock_model.entries.size() == 1 and "|".join(rock_model.entries[0].lines).contains("耐久"), "runtime inspection reads Stuff durability instead of the retired Tile obstacle")
	var tree_runtime := stuff.get_stuff(&"tree_1")
	_expect(tree_runtime != null and not tree_runtime.get_copy_kind().is_empty(), "effect-free Stuff still participates in nearest-cell mirror content")
	var maximum := rock.max_durability
	rock.take_structure_damage(maximum)
	_expect(stuff.get_stuff_at(rock_cell).is_empty(), "depleted rock removes only its Stuff instance")
	_expect(
		not bool(stuff.trace_ballistic_blocker(rock_center - Vector3.RIGHT * 2.0, rock_center + Vector3.RIGHT * 2.0).get("hit", false)),
		"depleted Stuff immediately stops blocking ballistics"
	)
	_expect(tile.can_place(rock_cell) and tile.allows_edge_building(rock_cell), "rock removal restores the underlying Grid permissions")
	_expect(stuff.get_stuff_at(source).size() == 2, "destroying one Stuff never mutates another cell's collection")
	fixture.host.queue_free()
	await process_frame


func _test_mirror_copies_every_stuff_with_shared_effect_identity() -> void:
	var level := _make_canonical_level(true)
	var fixture := _make_fixture(level)
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var tile: TileManager = fixture.tile
	var stuff: StuffManagerScript = fixture.stuff
	var renderer: StuffRendererScript = fixture.renderer
	var resource := ResourceManager.new()
	host.add_child(resource)
	resource.apply_level_configuration(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	var registry := EdgeOccupancyRegistry.new()
	var buildings := BuildingManager.new()
	host.add_child(buildings)
	buildings.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	buildings.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	buildings.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	buildings.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	buildings.set_edge_occupancy_registry(registry)
	buildings.configure(grid, tile, resource, combat)
	var explicit_blocker := StuffDefinition.new()
	explicit_blocker.stuff_id = &"effect_free_blocker"
	explicit_blocker.display_name = "无效果堵路元素"
	explicit_blocker.exclusive_with_other_stuff = false
	explicit_blocker.enemy_navigation = StuffDefinition.EnemyNavigation.BLOCKED
	explicit_blocker.durability_mode = StuffDefinition.DurabilityMode.DESTRUCTIBLE
	explicit_blocker.max_durability = 40.0
	explicit_blocker.blocks_ballistics = true
	explicit_blocker.fallback_visual_kind = StuffDefinition.FallbackVisualKind.ROCK
	var explicit_blocker_runtime := stuff.add_stuff(
		Vector3i(2, 2, 0),
		explicit_blocker,
		0,
		&"effect_free_blocker_1"
	)
	_expect(explicit_blocker_runtime != null, "effect-free explicit navigation blocker joins the Stuff source cell")
	var mirrors := MirrorManager.new()
	host.add_child(mirrors)
	mirrors.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirrors.configure(grid, tile, resource, combat, buildings, registry)
	mirrors.set_stuff_manager(stuff)
	tile.set_navigation_overlay_resolver(Callable(mirrors, "blocks_enemy_navigation"))
	tile.set_navigation_overlay_blocker_resolver(Callable(mirrors, "resolve_projected_navigation_blocker"))
	var from_cell := Vector3i(3, 2, 0)
	var to_cell := Vector3i(4, 2, 0)
	var target_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var mirror := mirrors.place_copy_mirror(from_cell, edge_index, true)
	_expect(mirror != null, "canonical Stuff fixture places a copy mirror")
	var projections := mirrors.get_projections(target_cell)
	_expect(projections.size() == 3, "one mirror copies every Stuff on the nearest non-empty cell")
	var kinds: Dictionary = {}
	for projection in projections:
		kinds[projection.payload.copy_kind] = true
	_expect(
		kinds.has(&"spike") and kinds.has(&"void") and kinds.has(&"stuff_effect_free_blocker"),
		"multi-Stuff projection preserves effect-backed and effect-free kinds"
	)
	_expect(projections.all(func(projection: MirrorProjection) -> bool: return projection.get_visual_snapshot() != null), "every Stuff projection uses its real Stuff visual snapshot")
	_expect(
		tile.blocks_enemy_navigation(target_cell),
		"an effect-free Stuff projection honors its explicit navigation-blocking definition"
	)
	_expect(
		mirrors.get_prospective_blocked_cells().has(target_cell),
		"connectivity validation sees effect-free Stuff projections as prospective blockers"
	)
	var airborne_profile := PathNavigationProfile.new()
	host.add_child(airborne_profile)
	airborne_profile.configure(true)
	_expect(
		not tile.blocks_enemy_navigation(target_cell, airborne_profile),
		"an explicit Stuff projection preserves its ground-only navigation setting"
	)
	explicit_blocker.navigation_affects_airborne = true
	_expect(
		tile.blocks_enemy_navigation(target_cell, airborne_profile),
		"an explicit Stuff projection honors the airborne navigation switch"
	)
	var projected_blocker := mirrors.resolve_projected_navigation_blocker(target_cell)
	_expect(
		projected_blocker is MirrorProjection
		and projected_blocker.payload.root_source == explicit_blocker_runtime,
		"an effect-free destructible Stuff projection resolves its concrete attack target"
	)
	if projected_blocker != null:
		var projected_center: Vector3 = projected_blocker.call("get_structure_target_position")
		var projected_ballistic_hit := mirrors.trace_ballistic_blocker(
			projected_center - Vector3.RIGHT * 2.0,
			projected_center + Vector3.RIGHT * 2.0
		)
		_expect(
			bool(projected_ballistic_hit.get("hit", false))
			and projected_ballistic_hit.get("blocker") == projected_blocker,
			"copied Stuff inherits the source definition's ballistic-blocking sphere"
		)
	var blocker_durability_before := explicit_blocker_runtime.current_durability
	if projected_blocker != null:
		projected_blocker.call("take_structure_damage", 11.0, null)
	_expect(
		is_equal_approx(explicit_blocker_runtime.current_durability, blocker_durability_before - 11.0),
		"damage to an effect-free Stuff projection reaches the shared source durability"
	)
	var direct_bindings := stuff.get_effect_bindings(Vector3i(2, 2, 0))
	var projected_bindings := mirrors.get_projected_effect_bindings(target_cell)
	var direct_keys: Dictionary = {}
	for binding in direct_bindings:
		direct_keys[str(binding.state_key)] = true
	_expect(projected_bindings.all(func(binding: Dictionary) -> bool: return direct_keys.has(str(binding.state_key))), "direct and recursive projection effects share their root Stuff state identity")
	var standalone_snapshot := renderer.create_stuff_visual_snapshot(stuff.get_stuff_at(Vector3i(2, 2, 0))[0].placement_id)
	_expect(standalone_snapshot != null, "StuffRenderer exposes a model-preserving mirror snapshot interface")
	if standalone_snapshot != null:
		standalone_snapshot.free()
	fixture.host.queue_free()
	await process_frame


func _test_catalog_definition_supersedes_stale_level_copy() -> void:
	var catalog: StuffCatalog = load("res://resources/stuffs/StuffCatalog.tres")
	var canonical := catalog.get_definition(&"stuff", true)
	_expect(canonical != null, "Stuff catalog exposes the canonical spruce definition")
	if canonical == null:
		return
	var stale: StuffDefinition = canonical.duplicate(true)
	stale.durability_mode = StuffDefinition.DurabilityMode.DESTRUCTIBLE
	stale.max_durability = 100.0
	var level := _make_canonical_level(false)
	level.stuff_placements.append(
		_make_placement(&"stale_spruce_1", Vector3i(3, 3, 0), stale)
	)
	var fixture := _make_fixture(level, false, catalog)
	var runtime: StuffRuntime = fixture.stuff.get_stuff(&"stale_spruce_1")
	_expect(
		runtime != null and runtime.definition == canonical,
		"runtime relinks a stale embedded Stuff copy to its catalog definition"
	)
	_expect(
		runtime != null and not runtime.is_destructible(),
		"catalog-authoritative spruce cannot be destroyed through its navigation blocker"
	)
	fixture.host.queue_free()
	await process_frame


func _test_level2_spruce_uses_catalog_definition() -> void:
	var level: LevelResource = load("res://resources/levels/Level2.tres")
	var catalog: StuffCatalog = load("res://resources/stuffs/StuffCatalog.tres")
	var canonical := catalog.get_definition(&"stuff", true)
	var authored_indestructible := true
	for placement: StuffPlacementData in level.stuff_placements:
		if placement.definition != null and placement.definition.stuff_id == &"stuff":
			authored_indestructible = authored_indestructible and (
				placement.definition.durability_mode == StuffDefinition.DurabilityMode.INDESTRUCTIBLE
			)
	_expect(authored_indestructible, "Level2 serializes spruce as indestructible")
	var fixture := _make_fixture(level, false, catalog)
	var spruce_count := 0
	var all_canonical := true
	var all_indestructible := true
	for runtime: StuffRuntime in fixture.stuff.get_all_stuff():
		if runtime.definition == null or runtime.definition.stuff_id != &"stuff":
			continue
		spruce_count += 1
		all_canonical = all_canonical and runtime.definition == canonical
		all_indestructible = all_indestructible and not runtime.is_destructible()
	_expect(spruce_count > 0, "Level2 loads its authored spruce placements")
	_expect(all_canonical, "every Level2 spruce resolves to the catalog definition")
	_expect(all_indestructible, "every Level2 spruce navigation blocker is indestructible")
	fixture.host.queue_free()
	await process_frame


func _test_legacy_level_uses_transient_stuff() -> void:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(3, 3)
	level.height_levels = 4
	level.height_step = 1.0
	var effect := RockTileEffect.new()
	effect.max_durability = 77.0
	var definition := TileDefinition.new()
	definition.tile_id = &"legacy_rock"
	definition.display_name = "旧关卡石头"
	definition.surface_kind = TileDefinition.SurfaceKind.DESTRUCTIBLE
	definition.allows_tile_building = false
	definition.allows_edge_building = true
	definition.effect = effect
	definition.visual_kind = TileDefinition.VisualKind.ROCK
	var tile_data := TileCellData.new()
	tile_data.configure(Vector3i(1, 1, 0), TileCellData.TileType.DESTRUCTIBLE, 1, definition)
	level.tiles = [tile_data]
	var fixture := _make_fixture(level)
	var stuff: StuffManagerScript = fixture.stuff
	var runtime_items := stuff.get_stuff_at(Vector3i(1, 1, 0))
	_expect(runtime_items.size() == 1 and runtime_items[0] is StuffRuntime, "legacy mixed Tile content migrates to one transient Stuff runtime")
	_expect(is_equal_approx(runtime_items[0].max_durability, 77.0), "legacy effect parameters survive the read-only Stuff adapter")
	_expect(level.stuff_placements.is_empty() and level.terrain_content_version == 0, "runtime Stuff migration never mutates the serialized legacy level")
	_expect(not tile_data.obstacle_destroyed, "runtime destruction state remains isolated from the authored legacy Tile")
	fixture.host.queue_free()
	await process_frame


func _test_loader_rolls_back_stuff() -> void:
	var original := _make_canonical_level(true)
	var fixture := _make_fixture(original, true)
	var stuff: StuffManagerScript = fixture.stuff
	var tile: TileManager = fixture.tile
	var original_rock := stuff.get_stuff(&"rock_1")
	tile.set("reject_next_load", true)
	var replacement := _make_canonical_level(false)
	replacement.stuff_placements[0].placement_id = &"replacement_spike"
	_expect(not fixture.loader.load_level(replacement, "memory://stuff-reject"), "Tile rejection fails the combined Stuff transaction")
	_expect(stuff.get_level_resource() == original, "combined transaction restores the previous Stuff level")
	_expect(stuff.get_stuff(&"rock_1") != null, "Stuff rollback reconstructs the removed previous rock")
	_expect(stuff.get_stuff(&"rock_1") != original_rock, "Stuff rollback isolates mutable runtime instances")
	_expect(stuff.get_stuff(&"replacement_spike") == null, "failed replacement Stuff never leaks into active state")
	fixture.host.queue_free()
	await process_frame


func _make_fixture(
	level: LevelResource,
	rejecting_tile: bool = false,
	catalog: StuffCatalog = null
) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var terrain := TerrainManager.new()
	host.add_child(terrain)
	terrain.set_grid(grid)
	var stuff := StuffManagerScript.new()
	host.add_child(stuff)
	stuff.stuff_catalog = catalog
	stuff.configure(grid, terrain)
	var renderer := StuffRendererScript.new()
	host.add_child(renderer)
	renderer.configure(grid, stuff)
	var tile: TileManager = RejectingTileManager.new() if rejecting_tile else TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	tile.legacy_content_runtime_enabled = false
	tile.set_stuff_runtime_provider(stuff)
	tile.set_surface_height_resolver(Callable(terrain, "get_world_height"))
	tile.set_base_placement_resolvers(Callable(terrain, "allows_tile_building"), Callable(terrain, "allows_edge_building"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain, stuff)
	_expect(loader.load_level(level, "memory://stuff-runtime"), "Stuff fixture loads through the combined transaction")
	return {"host": host, "grid": grid, "terrain": terrain, "stuff": stuff, "renderer": renderer, "tile": tile, "loader": loader}


func _make_canonical_level(include_rock: bool) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(7, 5)
	level.base_cell = Vector3i(6, 4, 0)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 1.0
	level.initial_resource = 5000
	level.building_cap = 30
	level.mirror_cap = 6
	for x in range(level.grid_size.x):
		for y in range(level.grid_size.y):
			var grid_cell := GridCellData.new()
			grid_cell.configure(Vector3i(x, y, 0), level.default_terrain, 1, true, true)
			level.grid_cells.append(grid_cell)
	var spike := StuffDefinition.new()
	spike.stuff_id = &"spike_a"
	spike.display_name = "尖刺"
	spike.exclusive_with_other_stuff = false
	spike.blocks_tile_building = true
	spike.blocks_edge_building = false
	spike.effect = SpikeTileEffect.new()
	spike.fallback_visual_kind = StuffDefinition.FallbackVisualKind.SPIKES
	spike.fallback_color = Color("ef564b")
	var void_stuff := StuffDefinition.new()
	void_stuff.stuff_id = &"void_a"
	void_stuff.display_name = "空洞"
	void_stuff.exclusive_with_other_stuff = false
	void_stuff.blocks_tile_building = true
	void_stuff.blocks_edge_building = false
	void_stuff.effect = VoidTileEffect.new()
	void_stuff.fallback_visual_kind = StuffDefinition.FallbackVisualKind.HOLE
	void_stuff.fallback_color = Color("10131c")
	level.stuff_placements.append(_make_placement(&"spike_1", Vector3i(2, 2, 0), spike))
	level.stuff_placements.append(_make_placement(&"void_1", Vector3i(2, 2, 0), void_stuff))
	if include_rock:
		var rock := StuffDefinition.new()
		rock.stuff_id = &"rock_a"
		rock.display_name = "大石头"
		rock.blocks_tile_building = true
		rock.blocks_edge_building = false
		rock.blocks_ballistics = true
		rock.effect = RockTileEffect.new()
		rock.fallback_visual_kind = StuffDefinition.FallbackVisualKind.ROCK
		rock.fallback_color = Color("34363c")
		level.stuff_placements.append(_make_placement(&"rock_1", Vector3i(1, 1, 0), rock))
	var tree := StuffDefinition.new()
	tree.stuff_id = &"tree_a"
	tree.display_name = "树"
	tree.blocks_tile_building = false
	tree.blocks_edge_building = false
	tree.fallback_visual_kind = StuffDefinition.FallbackVisualKind.TREE
	tree.fallback_color = Color("4d8b4a")
	level.stuff_placements.append(_make_placement(&"tree_1", Vector3i(0, 0, 0), tree))
	return level


func _make_placement(id: StringName, cell: Vector3i, definition: StuffDefinition) -> StuffPlacementData:
	var placement := StuffPlacementData.new()
	placement.configure(id, cell, definition, 0)
	return placement


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
