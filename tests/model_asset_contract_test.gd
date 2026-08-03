extends SceneTree

var _checks: int = 0
var _failures: int = 0


class TestStructure:
	extends Node3D

	var durability: float = 100.0

	func is_structure_alive() -> bool:
		return durability > 0.0

	func get_structure_target_position() -> Vector3:
		return global_position + Vector3.UP * 0.5

	func get_structure_hit_radius() -> float:
		return 0.2

	func take_structure_damage(amount: float, _attacker: Node = null) -> float:
		var applied := minf(maxf(0.0, amount), durability)
		durability -= applied
		return applied


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[ModelAssetContract] running")
	_test_contract_preserves_authored_transform()
	_test_programmatic_alignment()
	_test_production_terrain_prefab()
	_test_production_building_assets()
	await _test_tile_and_element_models()
	await _test_building_and_projectile_models()
	await _test_enemy_and_enemy_projectile_models()
	_test_projection_projectile_model()
	if _failures == 0:
		print("[ModelAssetContract] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[ModelAssetContract] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_production_terrain_prefab() -> void:
	var packed := ResourceLoader.load(
		"res://assets/blocks/tscn/bricks_b_2.tscn",
		"PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as PackedScene
	_expect(packed != null, "production bricks terrain prefab loads")
	var asset := ModelAssetDefinition.new()
	asset.scene = packed
	var errors := asset.validate_configuration() if packed != null else ["resource failed to load"]
	_expect(errors.is_empty(), "production bricks terrain prefab has an unambiguous node tree: %s" % str(errors))


func _test_contract_preserves_authored_transform() -> void:
	var scene := _make_model_scene(Vector3(2.0, 3.0, 4.0))
	var asset := _make_model_asset(scene, Vector3(0.5, 0.75, 1.25))
	var instance := asset.instantiate_model(&"ContractModel")
	_expect(instance != null, "configured model asset instantiates")
	_expect(instance.scale.is_equal_approx(Vector3(0.5, 0.75, 1.25)), "runtime scale is applied to the wrapper")
	var authored := instance.find_child("AuthoredModel", true, false) as Node3D
	_expect(authored != null, "authored scene remains a child of the wrapper")
	_expect(authored != null and authored.scale.is_equal_approx(Vector3(2.0, 3.0, 4.0)), "authored scene scale is not overwritten")
	instance.free()
	asset.runtime_scale = Vector3.ZERO
	_expect(not asset.validate_configuration().is_empty(), "non-positive runtime scale is rejected")
	var invalid_root := Control.new()
	var invalid_scene := PackedScene.new()
	_expect(invalid_scene.pack(invalid_root) == OK, "non-3D test scene packs")
	invalid_root.free()
	var invalid_asset := _make_model_asset(invalid_scene, Vector3.ONE)
	_expect(invalid_asset.instantiate_model() == null, "non-Node3D model roots fail safely")
	_expect(not invalid_asset.validate_configuration().is_empty(), "non-Node3D model roots are rejected by validation")


func _test_programmatic_alignment() -> void:
	var scene := _make_offset_model_scene()
	var asset := _make_model_asset(scene, Vector3(1.7, 0.8, 0.6))
	var grounded := asset.instantiate_grounded_model(&"GroundedModel")
	_expect(grounded != null, "offset authored model instantiates through ground alignment")
	var grounded_result := _get_visual_bounds(grounded)
	var grounded_bounds: AABB = grounded_result.get("bounds", AABB())
	_expect(bool(grounded_result.get("valid", false)), "ground alignment exposes render bounds")
	_expect(is_zero_approx(grounded_bounds.position.y), "ground alignment maps the visual bottom to logical Y=0")
	_expect(is_zero_approx(grounded_bounds.get_center().x), "ground alignment centers the visual footprint on X")
	_expect(is_zero_approx(grounded_bounds.get_center().z), "ground alignment centers the visual footprint on Z")
	grounded.free()
	var target := AABB(Vector3(-0.5, -0.45, -0.75), Vector3(1.0, 0.45, 1.5))
	var fitted := asset.instantiate_fitted_model(&"FittedModel", target)
	_expect(fitted != null, "offset authored model instantiates through exact bounds fitting")
	_expect(fitted.scale.is_equal_approx(Vector3.ONE), "fitted contexts normalize legacy runtime scale")
	var fitted_result := _get_visual_bounds(fitted)
	var fitted_bounds: AABB = fitted_result.get("bounds", AABB())
	_expect(fitted_bounds.position.is_equal_approx(target.position), "fit absorbs authored offsets and legacy runtime scale")
	_expect(fitted_bounds.size.is_equal_approx(target.size), "fit maps every visual axis to the logical target bounds")
	fitted.free()


func _test_production_building_assets() -> void:
	var arrow := ResourceLoader.load(
		"res://resources/buildings/ArrowTower.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as BuildingDefinition
	_expect(arrow != null, "production arrow tower loads after model contract migration")
	var errors := arrow.validate_configuration() if arrow != null else ["resource failed to load"]
	_expect(errors.is_empty(), "production arrow tower model assets validate: %s" % str(errors))


func _test_tile_and_element_models() -> void:
	var base_scene := _make_model_scene(Vector3(1.2, 1.2, 1.2))
	var element_scene := _make_model_scene(Vector3(0.8, 0.8, 0.8))
	var base_asset := _make_model_asset(base_scene, Vector3(1.5, 1.5, 1.5))
	var element_asset := _make_model_asset(element_scene, Vector3(0.75, 0.75, 0.75))
	var level := _make_level()
	level.tile_model_asset = base_asset
	var definition := TileDefinition.new()
	definition.tile_id = &"asset_element"
	definition.display_name = "资产元素"
	definition.surface_kind = TileDefinition.SurfaceKind.ELEMENT
	definition.visual_kind = TileDefinition.VisualKind.SPIKES
	definition.element_model_asset = element_asset
	var element_cell := Vector3i(1, 1, 0)
	var tile := TileCellData.new()
	tile.configure(element_cell, TileCellData.TileType.BLOCKED, 1, definition)
	level.store_tile(tile)
	var fixture := _make_tile_fixture(level)
	var host: Node3D = fixture["host"]
	var renderer: TileRenderer = fixture["renderer"]
	_expect(bool(fixture["loaded"]), "tile model fixture loads")
	var live_base := renderer.find_child("TileBase_0_0_0", true, false) as Node3D
	var live_element := renderer.find_child("TileElement_1_1_0", true, false) as Node3D
	_expect(live_base != null and live_base.scale.is_equal_approx(Vector3.ONE), "level tile model normalizes its fitted runtime scale")
	_expect(live_element != null and live_element.scale.is_equal_approx(element_asset.runtime_scale), "tile element model replaces only the content layer")
	var full_snapshot := renderer.create_tile_visual_snapshot(element_cell)
	var content_snapshot := renderer.create_tile_content_visual_snapshot(element_cell)
	_expect(full_snapshot.find_child("TerrainModel", true, false) != null, "full tile snapshot includes the configured base model")
	_expect(full_snapshot.find_child("ElementModel", true, false) != null, "full tile snapshot includes the configured element model")
	_expect(content_snapshot.find_child("TerrainModel", true, false) == null, "content snapshot keeps the tile base separated")
	_expect(content_snapshot.find_child("ElementModel", true, false) != null, "content snapshot exposes the configured model to mirror projections")
	full_snapshot.free()
	content_snapshot.free()
	host.queue_free()
	await process_frame


func _test_building_and_projectile_models() -> void:
	var scene := _make_model_scene(Vector3(1.4, 1.4, 1.4))
	var level_one_asset := _make_model_asset(scene, Vector3.ONE)
	var level_two_asset := _make_model_asset(scene, Vector3(1.35, 1.35, 1.35))
	var projectile_asset := _make_model_asset(scene, Vector3(0.2, 0.2, 0.6))
	var level := _make_level()
	var fixture := _make_tile_fixture(level)
	var host: Node3D = fixture["host"]
	var grid: GridManager = fixture["grid"]
	var tile_manager: TileManager = fixture["tile"]
	var combat := CombatManager.new()
	host.add_child(combat)
	var stats_one := BuildingLevelStats.new()
	stats_one.model_asset = level_one_asset
	stats_one.projectile_model_asset = projectile_asset
	stats_one.targeting_range = 10.0
	stats_one.attack_range = 10.0
	var stats_two := BuildingLevelStats.new()
	stats_two.model_asset = level_two_asset
	stats_two.projectile_model_asset = projectile_asset
	var definition := BuildingDefinition.new()
	definition.levels = [stats_one, stats_two]
	var building := Building.new()
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, tile_manager, combat)
	var first_wrapper := _get_building_model_wrapper(building)
	_expect(first_wrapper != null and first_wrapper.scale.is_equal_approx(Vector3.ONE), "building level 1 consumes its model asset")
	_expect(building.apply_level(2), "building applies a second configured level")
	var second_wrapper := _get_building_model_wrapper(building)
	_expect(second_wrapper != null and second_wrapper.scale.is_equal_approx(level_two_asset.runtime_scale), "levels can share one scene with independent runtime scales")
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.position = Vector3(0.0, 0.0, -2.0)
	host.add_child(target)
	combat.register_target(target)
	var projectile := building.launch_projectile(target, 1.0)
	var projectile_wrapper := projectile.get_node_or_null("ProjectileModel") as Node3D if projectile != null else null
	_expect(projectile_wrapper != null and projectile_wrapper.scale.is_equal_approx(Vector3.ONE), "building projectile normalizes its fitted model asset")
	host.queue_free()
	await process_frame


func _test_enemy_and_enemy_projectile_models() -> void:
	var scene := _make_model_scene(Vector3(0.9, 0.9, 0.9))
	var enemy_asset := _make_model_asset(scene, Vector3(1.6, 1.6, 1.6))
	var projectile_asset := _make_model_asset(scene, Vector3(0.25, 0.25, 0.7))
	var definition := EnemyDefinition.new()
	definition.model_asset = enemy_asset
	definition.projectile_model_asset = projectile_asset
	definition.projectile_speed = 4.0
	var host := Node3D.new()
	root.add_child(host)
	var enemy := EnemyUnit.new()
	enemy.debug_visual_enabled = false
	enemy.configure_unit(
		definition,
		PackedVector3Array([Vector3.ZERO, Vector3(2.0, 0.0, 0.0)]),
		[Vector3i.ZERO, Vector3i(1, 0, 0)]
	)
	host.add_child(enemy)
	var enemy_wrapper := enemy.get_node_or_null("EnemyModel") as Node3D
	_expect(enemy_wrapper != null and enemy_wrapper.scale.is_equal_approx(enemy_asset.runtime_scale), "enemy model remains visible when greybox debug visuals are disabled")
	var target := TestStructure.new()
	target.position = Vector3(1.0, 0.0, 0.0)
	host.add_child(target)
	var projectile := enemy.call("_launch_projectile", target) as EnemyProjectile
	var projectile_wrapper := projectile.get_node_or_null("EnemyProjectileModel") as Node3D if projectile != null else null
	_expect(projectile_wrapper != null and projectile_wrapper.scale.is_equal_approx(Vector3.ONE), "enemy projectile normalizes its fitted model asset")
	host.queue_free()
	await process_frame


func _test_projection_projectile_model() -> void:
	var scene := _make_model_scene(Vector3(1.1, 1.1, 1.1))
	var asset := _make_model_asset(scene, Vector3(0.3, 0.3, 0.8))
	var projectile := MirrorProjectionProjectile.new()
	var combat := CombatManager.new()
	var building := Building.new()
	root.add_child(combat)
	root.add_child(building)
	root.add_child(projectile)
	projectile.configure(
		combat,
		building,
		Vector3.ZERO,
		Vector3(2.0, 0.0, 0.0),
		4.0,
		1.0,
		0.3,
		0.1,
		Color.CYAN,
		asset
	)
	var wrapper := projectile.get_node_or_null("MirrorProjectileModel") as Node3D
	_expect(wrapper != null and wrapper.scale.is_equal_approx(Vector3.ONE), "mirror projectile normalizes the source fitted model asset")
	projectile.free()
	building.free()
	combat.free()


func _make_model_scene(authored_scale: Vector3) -> PackedScene:
	var authored := MeshInstance3D.new()
	authored.name = "AuthoredModel"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	authored.mesh = mesh
	authored.scale = authored_scale
	var scene := PackedScene.new()
	var result := scene.pack(authored)
	authored.free()
	_expect(result == OK, "test model scene packs")
	return scene


func _make_offset_model_scene() -> PackedScene:
	var authored := Node3D.new()
	authored.name = "OffsetAuthoredModel"
	authored.position = Vector3(1.8, 2.4, -0.7)
	authored.rotation.y = 0.37
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "OffsetMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 3.0, 1.0)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(-0.4, 0.6, 1.1)
	authored.add_child(mesh_instance)
	mesh_instance.owner = authored
	var scene := PackedScene.new()
	var result := scene.pack(authored)
	authored.free()
	_expect(result == OK, "offset model scene packs")
	return scene


func _get_visual_bounds(root_node: Node) -> Dictionary:
	var state := {"valid": false, "bounds": AABB()}
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


func _make_model_asset(scene: PackedScene, runtime_scale: Vector3) -> ModelAssetDefinition:
	var asset := ModelAssetDefinition.new()
	asset.scene = scene
	asset.runtime_scale = runtime_scale
	return asset


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(2, 2)
	level.height_levels = 3
	level.height_step = 0.4
	level.base_cell = Vector3i(1, 0, 0)
	return level


func _make_tile_fixture(level: LevelResource) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var renderer := TileRenderer.new()
	host.add_child(renderer)
	renderer.set_grid(grid)
	renderer.set_tile_manager(tile_manager)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	var loaded := loader.load_level(level, "memory://model-assets")
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"renderer": renderer,
		"loaded": loaded,
	}


func _get_building_model_wrapper(building: Building) -> Node3D:
	var visual_root := building.get("_visual_root") as Node3D
	return visual_root.get_node_or_null("BuildingModel") as Node3D if visual_root != null else null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
