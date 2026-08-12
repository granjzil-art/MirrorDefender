extends SceneTree

const RejectingTileManager := preload("res://tests/fixtures/RejectingTileManager.gd")
const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")
const TerrainRendererScript := preload("res://scripts/terrain/TerrainRenderer.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[TerrainRuntime] running")
	await _test_square_runtime_surface_and_renderer()
	await _test_terrain_model_instancing()
	await _test_flat_terrain_batching()
	await _test_hex_ramp_sampling()
	await _test_legacy_snapshot_runtime()
	await _test_loader_rolls_back_terrain()
	if _failures == 0:
		print("[TerrainRuntime] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[TerrainRuntime] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_square_runtime_surface_and_renderer() -> void:
	var fixture := _make_fixture(false)
	var level := _make_square_ramp_level()
	# This case verifies the greybox fallback, so use a deliberately model-less
	# fixture terrain instead of the production Grass.tres asset.
	var model_less_terrain := TerrainDefinition.new()
	model_less_terrain.terrain_id = &"test_model_less"
	model_less_terrain.display_name = "Model-less test terrain"
	level.default_terrain = model_less_terrain
	for grid_cell in level.grid_cells:
		grid_cell.terrain = model_less_terrain
	var loader: LevelLoader = fixture["loader"]
	var terrain: TerrainManagerScript = fixture["terrain"]
	var tile: TileManager = fixture["tile"]
	var grid: GridManager = fixture["grid"]
	var renderer: TerrainRendererScript = fixture["renderer"]
	_expect(loader.load_level(level, "memory://terrain-square"), "canonical square terrain loads transactionally")
	_expect(is_equal_approx(terrain.get_world_height(Vector3i(0, 1, 0)), 0.0), "low flat stays at world Y=0")
	_expect(is_equal_approx(terrain.get_world_height(Vector3i(1, 1, 0)), 0.25), "first 1:2 ramp center samples quarter rise")
	_expect(is_equal_approx(terrain.get_world_height(Vector3i(2, 1, 0)), 0.75), "second 1:2 ramp center samples three-quarter rise")
	_expect(is_equal_approx(terrain.get_world_height(Vector3i(3, 1, 0)), 1.0), "two-layer flat exposes one model-proportional layer")
	_expect(is_equal_approx(tile.get_world_height(Vector3i(2, 1, 0)), 0.75), "legacy TileManager height query delegates to TerrainManager")
	_expect(not tile.can_place(Vector3i(0, 0, 0)), "canonical Grid tile-building permission reaches legacy placement queries")
	_expect(not tile.allows_edge_building(Vector3i(0, 0, 0)), "canonical Grid edge-building permission reaches legacy placement queries")
	_expect(tile.can_place_path_occupant(Vector3i(0, 0, 0)), "path-only barrier occupancy keeps its existing compatibility exception")
	var low_edge := Vector3(0.5, 0.0, 1.0)
	var high_edge := Vector3(2.5, 0.0, 1.0)
	_expect(is_equal_approx(terrain.sample_surface_height(Vector3i(1, 1, 0), low_edge), 0.0), "ramp low edge is continuous with low flat")
	_expect(is_equal_approx(terrain.sample_surface_height(Vector3i(2, 1, 0), high_edge), 1.0), "ramp high edge is continuous with high flat")
	var hit := grid.pick_cell_from_ray(Vector3(1.0, 4.0, 1.0), Vector3.DOWN)
	_expect(bool(hit.get("hit", false)) and hit.get("cell") == Vector3i(1, 1, 0), "Grid picking intersects the actual ramp plane")
	_expect(is_equal_approx(Vector3(hit.get("pos", Vector3.ZERO)).y, 0.25), "ramp picking returns the sloped surface Y")
	var greybox := renderer.get_node_or_null("TerrainGreybox") as MeshInstance3D
	_expect(greybox != null and greybox.mesh != null and greybox.mesh.get_surface_count() == 1, "missing terrain models fall back to one greybox surface")
	_expect(terrain.get_terrain_color(Vector3i(0, 1, 0)).is_equal_approx(level.path_terrain_color), "path attribute overrides only the terrain presentation color")
	fixture["host"].queue_free()
	await process_frame


func _test_terrain_model_instancing() -> void:
	var fixture := _make_fixture(false)
	var level := _make_square_ramp_level()
	var terrain_definition := TerrainDefinition.new()
	terrain_definition.terrain_id = &"runtime_asset_terrain"
	terrain_definition.display_name = "运行时模型地形"
	terrain_definition.flat_model_asset = _make_model_asset(Vector3(1.2, 1.1, 1.0))
	var ramp_terrain := TerrainDefinition.new()
	ramp_terrain.terrain_id = &"runtime_ramp_override"
	ramp_terrain.display_name = "运行时斜坡覆盖地形"
	ramp_terrain.fallback_color = Color(0.34, 0.20, 0.12, 1.0)
	ramp_terrain.ramp_1_to_2_model_asset = _make_model_asset(
		Vector3(1.0, 1.0, 1.0),
		Vector3(1.0, 1.0, 2.0)
	)
	level.default_terrain = terrain_definition
	for grid_cell in level.grid_cells:
		grid_cell.terrain = terrain_definition
	level.ramp_placements[0].terrain_override = ramp_terrain
	var loader: LevelLoader = fixture["loader"]
	var terrain: TerrainManagerScript = fixture["terrain"]
	var renderer: TerrainRendererScript = fixture["renderer"]
	renderer.batch_flat_models = false
	_expect(loader.load_level(level, "memory://terrain-models"), "terrain model fixture loads")
	_expect(terrain.get_terrain(Vector3i(1, 1, 0)) == ramp_terrain, "runtime resolves an explicit terrain for every ramp footprint cell")
	_expect(terrain.get_terrain(Vector3i(0, 0, 0)) == terrain_definition, "ramp terrain override does not leak into neighboring flat Grid")
	_expect(terrain.get_ramp_for_cell(Vector3i(1, 1, 0)).terrain_override == ramp_terrain, "runtime ramp snapshot preserves the authored terrain override")
	var model_root := renderer.get_node_or_null("TerrainModels")
	var flat_count := 0
	var ramp_count := 0
	for child in model_root.get_children():
		if child.name.begins_with("Terrain_"):
			flat_count += 1
		elif child.name.begins_with("Ramp_"):
			ramp_count += 1
	_expect(flat_count == 25, "one flat model is instantiated for every non-ramp voxel layer")
	_expect(ramp_count == 1, "one full-width model is instantiated for the complete 1:2 ramp")
	var lower_voxel := model_root.get_node_or_null("Terrain_0_0_0_L1") as Node3D
	var lower_bounds := _get_visual_bounds(lower_voxel)
	var lower_aabb: AABB = lower_bounds.get("bounds", AABB())
	var lower_alignment := lower_voxel.get_node_or_null("ModelAlignment") as Node3D
	_expect(is_equal_approx(lower_aabb.end.y, 0.01), "flat model top is normalized to the logical first-layer surface")
	_expect(
		lower_alignment != null
		and is_equal_approx(lower_alignment.scale.x, lower_alignment.scale.y)
		and is_equal_approx(lower_alignment.scale.y, lower_alignment.scale.z),
		"terrain fitting preserves the authored model proportions"
	)
	_expect(is_equal_approx(lower_aabb.size.y, level.layer_height), "cube-authored terrain matches the model-proportional layer height")
	_expect(is_equal_approx(lower_aabb.size.x, level.grid_cell_size) and is_equal_approx(lower_aabb.size.z, level.grid_cell_size), "flat model footprint fits the square Grid cell")
	var upper_voxel := model_root.get_node_or_null("Terrain_3_0_0_L2") as Node3D
	_expect(upper_voxel != null and is_equal_approx(upper_voxel.position.y, 1.01), "stacked flat model roots advance by model-proportional layer_height")
	var upper_bounds := _get_visual_bounds(upper_voxel)
	var upper_aabb: AABB = upper_bounds.get("bounds", AABB())
	_expect(is_equal_approx(upper_aabb.position.y, 0.01), "adjacent normalized voxel layers share one exact boundary")
	var ramp_visual := model_root.get_node_or_null("Ramp_square_1_to_2") as Node3D
	_expect(ramp_visual != null and is_equal_approx(ramp_visual.rotation.y, PI * 0.5), "full ramp model rotates its local +Z uphill")
	var ramp_bounds := _get_visual_bounds(ramp_visual)
	var ramp_aabb: AABB = ramp_bounds.get("bounds", AABB())
	_expect(is_equal_approx(ramp_aabb.size.y, level.layer_height), "ramp model rise is normalized to one logical layer")
	_expect(is_equal_approx(ramp_aabb.size.x, 2.0) and is_equal_approx(ramp_aabb.size.z, 1.0), "1:2 ramp model fits its complete authored footprint")
	var greybox := renderer.get_node_or_null("TerrainGreybox") as MeshInstance3D
	_expect(greybox != null and greybox.mesh == null, "fully configured terrain assets suppress greybox geometry")
	fixture["host"].queue_free()
	await process_frame


func _test_flat_terrain_batching() -> void:
	var fixture := _make_fixture(false)
	var level := _make_square_ramp_level()
	var terrain_definition := TerrainDefinition.new()
	terrain_definition.terrain_id = &"batched_runtime_asset_terrain"
	terrain_definition.display_name = "批处理运行时模型地形"
	terrain_definition.flat_model_asset = _make_model_asset(Vector3(1.2, 1.1, 1.0))
	level.default_terrain = terrain_definition
	for grid_cell in level.grid_cells:
		grid_cell.terrain = terrain_definition
	var loader: LevelLoader = fixture["loader"]
	var renderer: TerrainRendererScript = fixture["renderer"]
	_expect(renderer.batch_flat_models, "flat terrain batching defaults on")
	_expect(loader.load_level(level, "memory://terrain-multimesh"), "batched terrain fixture loads")
	var model_root := renderer.get_node_or_null("TerrainModels")
	var batch_count := 0
	var instance_count := 0
	for child in model_root.get_children():
		if child is MultiMeshInstance3D:
			batch_count += 1
			instance_count += (child as MultiMeshInstance3D).multimesh.instance_count
	_expect(batch_count == 1, "identical flat terrain mesh parts collapse into one MultiMesh batch")
	_expect(instance_count == 25, "MultiMesh preserves one transform per non-ramp voxel layer")
	fixture["host"].queue_free()
	await process_frame


func _test_hex_ramp_sampling() -> void:
	var fixture := _make_fixture(false)
	var level := _make_hex_ramp_level()
	var loader: LevelLoader = fixture["loader"]
	var terrain: TerrainManagerScript = fixture["terrain"]
	_expect(loader.load_level(level, "memory://terrain-hex"), "canonical hex terrain loads")
	_expect(is_equal_approx(terrain.get_world_height(Vector3i.ZERO), 0.5), "hex 1:1 ramp center is half a layer high")
	var normal := terrain.get_surface_normal(Vector3i.ZERO)
	_expect(normal.y > 0.75 and not normal.is_equal_approx(Vector3.UP), "hex ramp exposes an uphill plane normal")
	fixture["host"].queue_free()
	await process_frame


func _test_legacy_snapshot_runtime() -> void:
	var fixture := _make_fixture(false)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(2, 2)
	level.height_levels = 4
	level.height_step = 1.0
	var source_tile := TileCellData.new()
	source_tile.configure(Vector3i(1, 0, 0), TileCellData.TileType.BUILDABLE, 2)
	level.tiles = [source_tile]
	var loader: LevelLoader = fixture["loader"]
	var terrain: TerrainManagerScript = fixture["terrain"]
	_expect(loader.load_level(level, "memory://terrain-legacy"), "legacy Tile level loads through the read-only adapter")
	_expect(is_equal_approx(terrain.get_layer_height(), 1.0), "legacy levels use the model-proportional layer height")
	_expect(terrain.get_grid_cell(Vector3i(1, 0, 0)).layer_count == 3, "legacy zero-based height becomes one-based layer count")
	_expect(level.grid_cells.is_empty() and level.terrain_content_version == 0, "runtime compatibility does not mutate legacy resources")
	fixture["host"].queue_free()
	await process_frame


func _test_loader_rolls_back_terrain() -> void:
	var fixture := _make_fixture(true)
	var loader: LevelLoader = fixture["loader"]
	var terrain: TerrainManagerScript = fixture["terrain"]
	var grid: GridManager = fixture["grid"]
	var valid := _make_square_ramp_level()
	_expect(loader.load_level(valid, "memory://terrain-before-reject"), "rollback fixture loads initial terrain")
	var previous_cell := terrain.get_grid_cell(Vector3i(1, 1, 0))
	var rejecting_tile: TileManager = fixture["tile"]
	rejecting_tile.set("reject_next_load", true)
	var replacement := _make_hex_ramp_level()
	_expect(not loader.load_level(replacement, "memory://terrain-reject"), "Tile assembly rejection fails the combined transaction")
	_expect(grid.grid_shape == GridManager.Shape.SQUARE, "combined transaction restores the previous Grid shape")
	_expect(terrain.get_level_resource() == valid, "combined transaction restores the previous Terrain level")
	_expect(terrain.get_grid_cell(Vector3i(1, 1, 0)) != previous_cell, "terrain rollback rebuilds isolated runtime cells")
	fixture["host"].queue_free()
	await process_frame


func _make_fixture(rejecting_tile: bool) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var terrain := TerrainManagerScript.new()
	host.add_child(terrain)
	terrain.set_grid(grid)
	var renderer := TerrainRendererScript.new()
	host.add_child(renderer)
	renderer.set_grid(grid)
	renderer.set_terrain_manager(terrain)
	var tile: TileManager = RejectingTileManager.new() if rejecting_tile else TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	tile.set_surface_height_resolver(Callable(terrain, "get_world_height"))
	tile.set_base_placement_resolvers(
		Callable(terrain, "allows_tile_building"),
		Callable(terrain, "allows_edge_building")
	)
	grid.set_cell_height_resolver(Callable(terrain, "get_world_height"))
	grid.set_cell_surface_height_resolver(Callable(terrain, "sample_surface_height"))
	grid.set_surface_raycast_resolver(Callable(terrain, "raycast_surface"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile, terrain)
	return {
		"host": host,
		"grid": grid,
		"terrain": terrain,
		"renderer": renderer,
		"tile": tile,
		"loader": loader,
	}


func _make_square_ramp_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(6, 3)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 1.0
	for x in range(6):
		for y in range(3):
			var grid_cell := GridCellData.new()
			var allows_tile := not (x == 0 and y == 0)
			var allows_edge := not (x == 0 and y == 0)
			grid_cell.configure(
				Vector3i(x, y, 0),
				level.default_terrain,
				2 if x >= 3 else 1,
				allows_tile,
				allows_edge
			)
			level.grid_cells.append(grid_cell)
	var ramp := RampPlacementData.new()
	ramp.ramp_id = &"square_1_to_2"
	ramp.anchor_cell = Vector3i(1, 1, 0)
	ramp.facing_index = 0
	ramp.run_length = 2
	ramp.base_layer = 1
	level.ramp_placements = [ramp]
	var path := PathDefinition.new()
	path.path_id = &"path_surface"
	path.display_name = "坡面路径"
	path.cells = [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0)]
	level.paths = [path]
	var spawn := SpawnPointDefinition.new()
	spawn.sync_with_path(path)
	level.spawn_points = [spawn]
	level.base_cell = Vector3i(3, 1, 0)
	return level


func _make_hex_ramp_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.HEX
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(2, 2)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Sand.tres")
	level.layer_height = 1.0
	var high_cell := Vector3i(1, -1, 0)
	var high := GridCellData.new()
	high.configure(high_cell, level.default_terrain, 2)
	level.grid_cells = [high]
	var ramp := RampPlacementData.new()
	ramp.ramp_id = &"hex_1_to_1"
	ramp.anchor_cell = Vector3i.ZERO
	ramp.facing_index = 0
	ramp.run_length = 1
	ramp.base_layer = 1
	level.ramp_placements = [ramp]
	level.base_cell = high_cell
	return level


func _make_model_asset(
	runtime_scale: Vector3,
	authored_size: Vector3 = Vector3(2.0, 2.0, 2.0)
) -> ModelAssetDefinition:
	var source := MeshInstance3D.new()
	source.name = "AuthoredTerrainModel"
	var mesh := BoxMesh.new()
	mesh.size = authored_size
	source.mesh = mesh
	var scene := PackedScene.new()
	if scene.pack(source) != OK:
		source.free()
		return null
	source.free()
	var asset := ModelAssetDefinition.new()
	asset.scene = scene
	asset.runtime_scale = runtime_scale
	return asset


func _get_visual_bounds(root_node: Node) -> Dictionary:
	var state := {"valid": false, "bounds": AABB()}
	if root_node != null:
		_collect_visual_bounds(root_node, Transform3D.IDENTITY, state)
	return state


func _collect_visual_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var transformed := current_transform * (node as MeshInstance3D).get_aabb()
		if bool(state.get("valid", false)):
			var existing: AABB = state.get("bounds", AABB())
			state["bounds"] = existing.merge(transformed)
		else:
			state["valid"] = true
			state["bounds"] = transformed
	for child in node.get_children():
		_collect_visual_bounds(child, current_transform, state)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
