extends SceneTree

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[CopyMirror] running")
	await _test_grid_geometry(GridManager.Shape.SQUARE)
	await _test_grid_geometry(GridManager.Shape.HEX)
	await _test_whole_tile_preview_stacking_and_tower_attacks()
	await _test_projected_barrier_and_shared_edge_occupancy()
	await _test_projected_rock_void_and_recursive_copy()
	if _failures == 0:
		print("[CopyMirror] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[CopyMirror] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_grid_geometry(shape: GridManager.Shape) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(shape, 1.0, Vector2i(7, 7))
	var from_cell := Vector3i(2, 3, 0) if shape == GridManager.Shape.SQUARE else Vector3i.ZERO
	var to_cell := Vector3i(3, 3, 0) if shape == GridManager.Shape.SQUARE else grid.get_neighbors(from_cell)[0]
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var pair := grid.get_mirror_cell_pair(from_cell, edge_index, true, 2)
	_expect(pair.valid, "%s mirror ray returns a valid second cell pair" % grid.get_geometry_tag())
	_expect(grid.distance(from_cell, pair.source_cell) == 1, "%s source ray advances one discrete step" % grid.get_geometry_tag())
	_expect(grid.distance(to_cell, pair.target_cell) == 1, "%s target ray advances symmetrically" % grid.get_geometry_tag())
	var endpoints := grid.get_edge_endpoints(from_cell, edge_index)
	var reflected := MirrorCopyPayload.reflect_point_across_line(
		grid.cell_to_world(pair.source_cell),
		endpoints[0],
		endpoints[1]
	)
	_expect(reflected.distance_to(grid.cell_to_world(pair.target_cell)) < 0.001, "%s cell pair is geometrically reflected across the shared edge" % grid.get_geometry_tag())
	host.queue_free()
	await process_frame

func _test_whole_tile_preview_stacking_and_tower_attacks() -> void:
	var level := _make_level(false)
	var spike := SpikeTileEffect.new()
	spike.damage_per_second = 13.0
	level.store_tile(_make_effect_tile(Vector3i(2, 2, 0), spike, true))
	var fixture := _make_fixture(level)
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var tile_manager: TileManager = fixture.tile
	var resource_manager: ResourceManager = fixture.resource
	var combat_manager: CombatManager = fixture.combat
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var source_cell := Vector3i(2, 2, 0)
	var from_cell := Vector3i(3, 2, 0)
	var to_cell := Vector3i(4, 2, 0)
	var target_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var arrow := building_manager.place_building(source_cell, building_manager.arrow_tower)
	_expect(arrow != null, "copy fixture places an arrow tower on a configured spike source tile")
	_expect(mirror_manager.update_preview(from_cell, edge_index), "valid copy-mirror edge creates a placement preview")
	var preview := mirror_manager.get_preview_info()
	_expect(preview.has_source and preview.source_cell == source_cell and preview.target_cell == target_cell, "preview reports the nearest non-empty source and reflected target")
	_expect(preview.types.size() == 2, "preview includes every copyable item on the source tile")
	var mirror := mirror_manager.place_copy_mirror(from_cell, edge_index, true)
	_expect(mirror != null, "copy mirror is placed on the previewed physical edge")
	_expect(is_equal_approx(mirror.get_mirror_height(), grid.cell_size * 1.20), "default copy mirror height is raised to 1.20 cells")
	var projections := mirror_manager.get_projections(target_cell)
	_expect(projections.size() == 2, "one mirror projects the source tile's tower and spike as one group")
	_expect(_has_projection_kind(projections, &"arrow_tower") and _has_projection_kind(projections, &"spike"), "whole-tile projection preserves both source content kinds")
	var tower_projection := _find_projection_kind(projections, &"arrow_tower")
	var tile_projection := _find_projection_kind(projections, &"spike")
	_expect(tower_projection.get_visual_snapshot() != null, "tower projection reuses a snapshot of the source Building visual")
	_expect(tile_projection.get_visual_snapshot() != null, "tile-effect projection reuses a snapshot of the source tile content")
	var source_center := grid.cell_to_world(source_cell)
	var mirrored_source_center := tile_projection.payload.transform_point(source_center)
	var rendered_source_center := tile_projection.get_visual_snapshot().global_transform * source_center
	_expect(rendered_source_center.distance_to(mirrored_source_center) < 0.001, "tile snapshot geometry receives the exact mirror transform without substitute offsets")
	_expect(tower_projection.global_position.distance_to(tile_projection.global_position) < 0.001, "overlapping projections remain on the same exact target transform")
	_expect(_snapshot_uses_immediate_mesh(tile_projection.get_visual_snapshot()), "tile projection keeps TileRenderer element geometry instead of a primitive substitute")
	_expect(not _snapshot_has_named_mesh(tile_projection.get_visual_snapshot(), "Terrain"), "tile projection excludes the source terrain base")
	_expect(_snapshot_has_named_mesh(tile_projection.get_visual_snapshot(), "Element"), "tile projection preserves the source tile element")
	_expect(_projection_materials_have_stable_order(projections), "overlapping transparent projections use deterministic render priorities without depth writes")
	var retired_projection := tile_projection
	mirror_manager.rebuild_now()
	_expect(not retired_projection.visible, "projection rebuild hides retired visuals before deferred deletion")
	projections = mirror_manager.get_projections(target_cell)
	tower_projection = _find_projection_kind(projections, &"arrow_tower")
	tile_projection = _find_projection_kind(projections, &"spike")
	_expect(tile_manager.get_occupant(target_cell) == null, "default projections do not write TileCellData occupancy")
	var reflection_camera := Camera3D.new()
	host.add_child(reflection_camera)
	reflection_camera.global_position = grid.cell_to_world(Vector3i(2, 2, 0)) + Vector3(0.0, 4.0, 3.0)
	reflection_camera.look_at(mirror.global_position + Vector3.UP * 0.35)
	reflection_camera.current = true
	mirror_manager.set_reflection_camera(reflection_camera)
	_expect(mirror.get_reflection_surface() != null and mirror.get_reflection_surface().mesh is QuadMesh, "copy mirror active face owns a dedicated reflection surface")
	_expect(mirror.get_reflection_surface().global_basis.z.normalized().dot(mirror.get_active_normal()) > 0.99, "reflection surface front normal follows the configured active side")
	var mirror_center := mirror.global_position + Vector3.UP * mirror.get_mirror_height() * 0.5
	var surface_depth_offset := (mirror.get_reflection_surface().global_position - mirror_center).dot(mirror.get_active_normal())
	_expect(surface_depth_offset > mirror.get_mirror_thickness() * 0.5, "reflection surface stays outside the mirror body at distant depth precision")
	_expect(mirror.request_reflection_refresh(), "visible active mirror face schedules one shared-world reflection refresh")
	_expect(mirror.get_reflection_camera() != null and mirror.get_reflection_camera().projection == reflection_camera.projection, "reflection camera copies the source projection without an extreme off-axis frustum")
	var source_forward: Vector3 = -reflection_camera.global_basis.z.normalized()
	var expected_reflected_forward: Vector3 = source_forward - 2.0 * source_forward.dot(mirror.get_active_normal()) * mirror.get_active_normal()
	var actual_reflected_forward: Vector3 = -mirror.get_reflection_camera().global_basis.z.normalized()
	_expect(actual_reflected_forward.dot(expected_reflected_forward.normalized()) > 0.999, "reflection camera orientation is the live source orientation mirrored across the physical plane")
	var reflection_viewport := mirror.get_reflection_viewport()
	var source_aspect := reflection_camera.get_viewport().get_visible_rect().size.aspect()
	var reflection_aspect := Vector2(reflection_viewport.size).aspect()
	_expect(is_equal_approx(reflection_aspect, source_aspect), "reflection target follows the source viewport aspect for screen-aligned sampling")
	var reflection_material := mirror.get_reflection_surface().material_override as ShaderMaterial
	_expect(reflection_material != null and reflection_material.shader.code.contains("SCREEN_UV"), "mirror surface samples the reflected world in stable screen space")
	var mirror_body := mirror.get_node("MirrorBody") as MeshInstance3D
	_expect(not mirror_body.get_layer_mask_value(1) and mirror_body.get_layer_mask_value(20), "mirror body is excluded from reflection cameras to prevent blue self-occlusion")
	var active_camera_position := reflection_camera.global_position
	var gameplay_active_normal := mirror.get_active_normal()
	reflection_camera.global_position = mirror_center - gameplay_active_normal * 24.0 + Vector3.UP * 9.0
	reflection_camera.look_at(mirror_center)
	_expect(mirror.request_reflection_refresh(), "distant camera on the opposite observation side still refreshes the mirror")
	_expect(mirror.get_reflection_surface().global_basis.z.normalized().dot(-gameplay_active_normal) > 0.99, "the single reflection surface follows the observer-facing physical side")
	_expect(mirror.get_active_normal().dot(gameplay_active_normal) > 0.99, "observer-side rendering never changes the gameplay active side")
	reflection_camera.global_position = active_camera_position
	reflection_camera.look_at(mirror_center)
	mirror.request_reflection_refresh()
	var previous_active_normal := mirror.get_active_normal()
	mirror.flip_side()
	_expect(mirror.get_reflection_surface().global_basis.z.normalized().dot(mirror.get_active_normal()) > 0.99 and mirror.get_active_normal().dot(previous_active_normal) < -0.99, "flipping the mirror moves the only reflection surface to the opposite active face")
	mirror.flip_side()
	var effect_system := TileEffectSystem.new()
	host.add_child(effect_system)
	effect_system.configure(tile_manager)
	effect_system.set_effect_overlay_resolver(Callable(mirror_manager, "get_projected_effects"))
	var spike_target := _make_target(host, grid.cell_to_world(target_cell))
	var spike_hp := spike_target.current_hp
	effect_system.apply_stay(spike_target, target_cell, 1.0)
	_expect(is_equal_approx(spike_target.current_hp, spike_hp - spike.damage_per_second), "projected spike applies the source effect parameters")

	var mirrored_target_cell := Vector3i(6, 2, 0)
	var mirrored_target := _make_target(host, grid.cell_to_world(mirrored_target_cell))
	combat_manager.register_target(mirrored_target)
	var original_endpoint := grid.cell_to_world(Vector3i(1, 2, 0)) + Vector3(0.0, mirrored_target.debug_height * 0.55, 0.0)
	arrow.notify_copy_attack(&"projectile", arrow.get_attack_origin(), original_endpoint, 17.0)
	var projection_projectile := _find_projection_projectile(combat_manager)
	_expect(projection_projectile != null, "original arrow attack spawns a fixed-end projection projectile")
	if projection_projectile != null:
		projection_projectile._process(10.0)
	_expect(is_equal_approx(mirrored_target.current_hp, mirrored_target.max_hp - 17.0), "projection projectile damages a target only at the mirrored endpoint")

	building_manager.remove_building(source_cell, 0.0)
	var laser := building_manager.place_building(source_cell, building_manager.laser_tower)
	mirror_manager.rebuild_now()
	_expect(laser != null and _has_projection_kind(mirror_manager.get_projections(target_cell), &"laser_tower"), "source replacement dynamically rebuilds a laser projection")
	var laser_before := mirrored_target.current_hp
	laser.notify_copy_attack(&"laser", laser.get_attack_origin(), original_endpoint, 9.0)
	_expect(is_equal_approx(mirrored_target.current_hp, laser_before - 9.0), "laser projection mirrors the source segment and damage tick without independent targeting")

	var overlapping := building_manager.place_building(target_cell, building_manager.arrow_tower)
	_expect(overlapping != null, "a real building can occupy a tile already containing non-occupying projections")
	mirror_manager.rebuild_now()
	_expect(not mirror_manager.get_projections(target_cell).is_empty(), "default occupancy switch keeps projections over a real building")
	mirror_manager.copy_mirror_definition.projection_ignores_occupancy = false
	mirror_manager.rebuild_now()
	_expect(mirror_manager.get_projections(target_cell).is_empty(), "strict occupancy switch suppresses the mirror's whole projection group")
	mirror_manager.copy_mirror_definition.projection_ignores_occupancy = true
	_expect(resource_manager.get_mirror_count() == 1, "only the physical mirror consumes mirror cap")
	host.queue_free()
	await process_frame

func _test_projected_barrier_and_shared_edge_occupancy() -> void:
	var level := _make_level(true)
	var fixture := _make_fixture(level)
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var source_cell := Vector3i(2, 2, 0)
	var from_cell := Vector3i(3, 2, 0)
	var to_cell := Vector3i(4, 2, 0)
	var target_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	var barrier := building_manager.place_building(source_cell, building_manager.barrier)
	var mirror := mirror_manager.place_copy_mirror(from_cell, edge_index, true)
	_expect(barrier != null and mirror != null, "path barrier and copy mirror fixture are placed")
	var projected_blocker := building_manager.resolve_path_blocker(Vector3i(4, 2, 0), target_cell)
	_expect(projected_blocker is MirrorProjection, "enemy blocker query resolves the projected barrier overlay")
	var durability_before := barrier.current_durability
	if projected_blocker != null:
		projected_blocker.call("take_structure_damage", 11.0, null)
	_expect(is_equal_approx(barrier.current_durability, durability_before - 11.0), "damage to a barrier projection is forwarded to the original durability pool")
	_expect(building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier) == null, "edge barrier cannot overlap a mirror in the shared physical-edge registry")
	var mirror_edge_id := mirror.edge_id
	_expect(mirror_manager.remove_mirror(mirror, 0.0), "selected physical mirror can be removed")
	_expect(mirror_manager.get_mirror(mirror_edge_id) == null, "mirror removal releases the mirror registry entry")
	var external_mirror := mirror_manager.place_copy_mirror(from_cell, edge_index, true)
	_expect(external_mirror != null, "released edge accepts another copy mirror")
	external_mirror.queue_free()
	await process_frame
	_expect(mirror_manager.get_mirror(mirror_edge_id) == null and fixture.resource.get_mirror_count() == 0, "external mirror deletion releases registry and mirror-cap usage")
	_expect(building_manager.place_edge_building(from_cell, edge_index, building_manager.edge_barrier) != null, "released mirror edge becomes available to another edge building")
	host.queue_free()
	await process_frame

func _test_projected_rock_void_and_recursive_copy() -> void:
	var rock_level := _make_level(false)
	var rock := RockTileEffect.new()
	rock_level.store_tile(_make_effect_tile(Vector3i(2, 2, 0), rock, false))
	var rock_fixture := _make_fixture(rock_level)
	var rock_host: Node3D = rock_fixture.host
	var rock_grid: GridManager = rock_fixture.grid
	var rock_tile: TileManager = rock_fixture.tile
	var rock_mirrors: MirrorManager = rock_fixture.mirror
	var first_edge := rock_grid.find_edge_index(Vector3i(3, 2, 0), Vector3i(4, 2, 0))
	rock_mirrors.place_copy_mirror(Vector3i(3, 2, 0), first_edge, true)
	_expect(rock_tile.blocks_enemy_navigation(Vector3i(5, 2, 0)), "projected rock joins the dynamic-navigation obstruction query")
	var second_edge := rock_grid.find_edge_index(Vector3i(5, 2, 0), Vector3i(6, 2, 0))
	rock_mirrors.place_copy_mirror(Vector3i(5, 2, 0), second_edge, true)
	rock_mirrors.rebuild_now()
	var recursive := rock_mirrors.get_projections(Vector3i(6, 2, 0))
	_expect(not recursive.is_empty() and recursive[0].payload.chain_depth == 2, "an existing projection can be copied through a second mirror")
	_expect(recursive[0].payload.lineage.size() == 2, "recursive payload records a finite two-mirror lineage")
	_expect(recursive[0].get_visual_snapshot() != null and _snapshot_uses_immediate_mesh(recursive[0].get_visual_snapshot()), "recursive tile projection keeps the original tile-content snapshot")
	_expect(not _snapshot_has_named_mesh(recursive[0].get_visual_snapshot(), "Terrain"), "recursive tile projection never introduces terrain base geometry")
	var original_rock_center := rock_grid.cell_to_world(Vector3i(2, 2, 0))
	var recursive_rendered_center := recursive[0].get_visual_snapshot().global_transform * original_rock_center
	_expect(recursive_rendered_center.distance_to(recursive[0].payload.transform_point(original_rock_center)) < 0.001, "recursive tile snapshot applies every mirror axis to the original geometry")
	rock_host.queue_free()
	await process_frame

	var void_level := _make_level(false)
	var void_effect := VoidTileEffect.new()
	void_level.store_tile(_make_effect_tile(Vector3i(2, 2, 0), void_effect, false))
	var void_fixture := _make_fixture(void_level)
	var void_host: Node3D = void_fixture.host
	var void_grid: GridManager = void_fixture.grid
	var void_tile: TileManager = void_fixture.tile
	var void_mirrors: MirrorManager = void_fixture.mirror
	var edge_index := void_grid.find_edge_index(Vector3i(3, 2, 0), Vector3i(4, 2, 0))
	void_mirrors.place_copy_mirror(Vector3i(3, 2, 0), edge_index, true)
	var effect_system := TileEffectSystem.new()
	void_host.add_child(effect_system)
	effect_system.configure(void_tile)
	effect_system.set_effect_overlay_resolver(Callable(void_mirrors, "get_projected_effects"))
	var falling_target := _make_target(void_host, void_grid.cell_to_world(Vector3i(5, 2, 0)))
	effect_system.apply_enter(falling_target, Vector3i(5, 2, 0))
	_expect(not falling_target.is_alive(), "projected void executes the same enter-time defeat effect")
	void_host.queue_free()
	await process_frame

func _make_fixture(level: LevelResource) -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var tile_renderer := TileRenderer.new()
	host.add_child(tile_renderer)
	tile_renderer.set_grid(grid)
	tile_renderer.set_tile_manager(tile_manager)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	resource_manager.apply_level_configuration(level)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var registry := EdgeOccupancyRegistry.new()
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager.arrow_tower = _load_building("res://resources/buildings/ArrowTower.tres")
	building_manager.laser_tower = _load_building("res://resources/buildings/LaserTower.tres")
	building_manager.barrier = _load_building("res://resources/buildings/Barrier.tres")
	building_manager.edge_barrier = _load_building("res://resources/buildings/EdgeBarrier.tres")
	building_manager.set_edge_occupancy_registry(registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	var definition: Resource = ResourceLoader.load(
		"res://resources/mirrors/CopyMirror.tres",
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	)
	mirror_manager.copy_mirror_definition = definition as CopyMirrorDefinition
	mirror_manager.configure(grid, tile_manager, resource_manager, combat_manager, building_manager, registry)
	mirror_manager.set_tile_visual_snapshot_resolver(Callable(tile_renderer, "create_tile_content_visual_snapshot"))
	building_manager.set_projection_blocker_resolver(Callable(mirror_manager, "resolve_projected_blocker"))
	tile_manager.set_navigation_overlay_resolver(Callable(mirror_manager, "blocks_enemy_navigation"))
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	_expect(loader.load_level(level, "memory://copy-mirror"), "copy mirror fixture level loads")
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
		"mirror": mirror_manager,
	}

func _make_level(with_path: bool) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(7, 5)
	level.initial_resource = 5000
	level.building_cap = 30
	level.mirror_cap = 6
	level.base_resource_per_second = 0.0
	level.base_cell = Vector3i(6, 4, 0)
	if with_path:
		var path := PathDefinition.new()
		path.path_id = &"path_1"
		path.display_name = "路径1"
		for x in range(7):
			path.cells.append(Vector3i(x, 2, 0))
		level.paths.append(path)
		level.base_cell = path.get_end_cell()
		var spawn := SpawnPointDefinition.new()
		spawn.spawn_id = &"spawn_path_1"
		spawn.display_name = "路径1出生点"
		spawn.cell = path.get_start_cell()
		level.spawn_points.append(spawn)
	return level

func _make_effect_tile(cell: Vector3i, effect: TileEffect, allows_building: bool) -> TileCellData:
	var definition := TileDefinition.new()
	definition.tile_id = StringName("copy_%s" % effect.get_copy_kind())
	definition.display_name = effect.get_copy_display_name()
	definition.surface_kind = TileDefinition.SurfaceKind.BUILDABLE if allows_building else TileDefinition.SurfaceKind.ELEMENT
	definition.allows_tile_building = allows_building
	definition.allows_edge_building = true
	definition.effect = effect
	if effect is SpikeTileEffect:
		definition.visual_kind = TileDefinition.VisualKind.SPIKES
		definition.visual_color = Color(0.95, 0.28, 0.20, 1.0)
	elif effect is VoidTileEffect:
		definition.visual_kind = TileDefinition.VisualKind.HOLE
		definition.visual_color = Color(0.01, 0.015, 0.025, 1.0)
	elif effect is RockTileEffect:
		definition.visual_kind = TileDefinition.VisualKind.ROCK
		definition.visual_color = Color(0.08, 0.085, 0.09, 1.0)
	var tile := TileCellData.new()
	tile.configure(cell, TileCellData.TileType.BUILDABLE, 0, definition)
	return tile

func _load_building(path: String) -> BuildingDefinition:
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	return resource as BuildingDefinition

func _make_target(host: Node, world_position: Vector3) -> CombatTarget:
	var target := CombatTarget.new()
	target.debug_visual_enabled = false
	target.max_hp = 100.0
	target.position = world_position
	host.add_child(target)
	return target

func _has_projection_kind(projections: Array[MirrorProjection], kind: StringName) -> bool:
	for projection in projections:
		if projection.payload.copy_kind == kind:
			return true
	return false

func _find_projection_kind(projections: Array[MirrorProjection], kind: StringName) -> MirrorProjection:
	for projection in projections:
		if projection.payload.copy_kind == kind:
			return projection
	return null

func _snapshot_uses_immediate_mesh(snapshot: Node3D) -> bool:
	if snapshot == null:
		return false
	for child in snapshot.get_children():
		if child is MeshInstance3D and child.mesh is ImmediateMesh:
			return true
		if child is Node3D and _snapshot_uses_immediate_mesh(child):
			return true
	return false

func _snapshot_has_named_mesh(snapshot: Node3D, mesh_name: String) -> bool:
	if snapshot == null:
		return false
	var child := snapshot.get_node_or_null(NodePath(mesh_name))
	return child is MeshInstance3D and child.mesh is ImmediateMesh

func _projection_materials_have_stable_order(projections: Array[MirrorProjection]) -> bool:
	var priorities: Dictionary = {}
	for projection in projections:
		var mesh := _find_first_mesh_instance(projection.get_visual_snapshot())
		if mesh == null or not mesh.material_override is StandardMaterial3D:
			return false
		var material := mesh.material_override as StandardMaterial3D
		if material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED or priorities.has(material.render_priority):
			return false
		priorities[material.render_priority] = true
	return priorities.size() == projections.size()

func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null

func _find_projection_projectile(combat_manager: CombatManager) -> MirrorProjectionProjectile:
	for child in combat_manager.get_children():
		if child is MirrorProjectionProjectile:
			return child
	return null

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
