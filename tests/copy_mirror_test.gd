extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0
var _copy_preview_origin: Vector3 = Vector3.ZERO
var _copy_preview_direction: Vector3 = Vector3.ZERO
var _copy_preview_reflection_point: Vector3 = Vector3.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[CopyMirror] running")
	await _test_grid_geometry(GridManager.Shape.SQUARE)
	await _test_grid_geometry(GridManager.Shape.HEX)
	await _test_building_preview_and_copy_trajectory()
	await _test_mirror_placement_preview_trajectory()
	await _test_whole_tile_preview_stacking_and_tower_attacks()
	await _test_unlimited_projection_overlap_with_single_real_entity()
	await _test_projected_barrier_and_shared_edge_occupancy()
	await _test_projected_rock_after_overlapping_barrier_breaks()
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


func _test_building_preview_and_copy_trajectory() -> void:
	var level := _make_level(false)
	level.store_tile(_make_effect_tile(Vector3i(1, 2, 0), RockTileEffect.new(), false))
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
	var mirror := mirror_manager.place_copy_mirror(from_cell, edge_index, true)
	_expect(mirror != null, "building-preview fixture places its copy mirror")
	_expect(
		building_manager.update_preview(source_cell, building_manager.arrow_tower),
		"valid building placement creates the real-source preview"
	)
	var preview_building := building_manager.get_preview_building()
	var preview_projections := mirror_manager.get_building_preview_projections()
	_expect(
		preview_projections.size() == 1
		and preview_projections[0].payload.root_source == preview_building
		and preview_projections[0].payload.projected_cell == target_cell,
		"building placement previews the corresponding copy at the reflected cell"
	)
	_expect(
		preview_projections.size() == 1
		and preview_projections[0].preview_mode
		and preview_projections[0].get_visual_snapshot() != null,
		"building copy preview is a behaviorless translucent virtual image"
	)
	_expect(
		_is_green(preview_building.get_preview_display_color()),
		"valid building placement renders the physical building preview in green"
	)
	var visualizer := BuildingSelectionVisualizer.new()
	host.add_child(visualizer)
	visualizer.configure(grid, building_manager)
	visualizer.set_projectile_copy_resolver(
		Callable(mirror_manager, "get_projectile_trajectory_copy_payloads")
	)
	var payload := preview_projections[0].payload
	_copy_preview_origin = payload.transform_point(preview_building.get_attack_origin())
	_copy_preview_direction = payload.transform_direction(
		preview_building.get_projectile_launch_directions()[0]
	).normalized()
	_copy_preview_reflection_point = _copy_preview_origin + _copy_preview_direction * 0.5
	visualizer.set_projectile_reflection_resolver(
		Callable(self, "_trace_copy_preview_reflection")
	)
	visualizer.set_projectile_blocker_resolver(Callable(self, "_trace_copy_preview_blocker"))
	_assert_original_and_copy_trajectories(
		visualizer.debug_get_projectile_trajectory_segments(),
		"building placement"
	)
	building_manager.clear_preview()
	_expect(
		mirror_manager.get_building_preview_projections().is_empty(),
		"clearing building placement also clears its copy virtual images"
	)
	_expect(
		not building_manager.update_preview(Vector3i(1, 2, 0), building_manager.arrow_tower),
		"obstacle tile remains rejected"
	)
	var invalid_building_preview := building_manager.get_preview_building()
	var invalid_building_color := invalid_building_preview.get_preview_display_color()
	_expect(
		invalid_building_preview.visible
		and invalid_building_color.r > 0.8
		and invalid_building_color.g < 0.3,
		"invalid physical building preview stays visible in red"
	)
	_expect(
		mirror_manager.get_building_preview_projections().is_empty(),
		"invalid building placement keeps the original copied-preview behavior"
	)
	building_manager.clear_preview()
	var building := building_manager.place_building(source_cell, building_manager.arrow_tower)
	_expect(building != null, "copy-trajectory fixture places the previewed building")
	building_manager.select_building(building)
	var selected_building_mesh := _find_first_mesh_instance(building)
	var selected_building_overlay := (
		selected_building_mesh.material_overlay as ShaderMaterial
		if selected_building_mesh != null
		else null
	)
	var selected_building_color: Color = (
		selected_building_overlay.get_shader_parameter("highlight_color")
		if selected_building_overlay != null
		else Color.BLACK
	)
	_expect(
		selected_building_overlay != null
		and selected_building_color.g > 0.9
		and selected_building_color.r < 0.3,
		"selected live building uses the shared green body highlight"
	)
	var live_payloads := mirror_manager.get_projectile_trajectory_copy_payloads(building)
	_expect(
		live_payloads.size() == 1 and live_payloads[0].projected_cell == target_cell,
		"selected live building resolves its corresponding copy payload"
	)
	visualizer.refresh()
	_assert_original_and_copy_trajectories(
		visualizer.debug_get_projectile_trajectory_segments(),
		"selected building"
	)
	_expect(not mirror_manager.update_preview(from_cell, edge_index), "occupied mirror edge remains rejected")
	var invalid_mirror_preview := mirror_manager.get_preview_mirror()
	var invalid_mirror_color := invalid_mirror_preview.get_preview_display_color()
	_expect(
		invalid_mirror_preview.visible
		and invalid_mirror_color.r > 0.8
		and invalid_mirror_color.g < 0.3,
		"invalid physical mirror preview stays visible in red"
	)
	_expect(
		mirror_manager.get_preview_projections().is_empty(),
		"invalid mirror placement does not create copied-object previews"
	)
	host.queue_free()
	await process_frame


func _test_mirror_placement_preview_trajectory() -> void:
	var fixture := _make_fixture(_make_level(false))
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var source_cell := Vector3i(2, 2, 0)
	var from_cell := Vector3i(3, 2, 0)
	var target_cell := Vector3i(5, 2, 0)
	var edge_index := grid.find_edge_index(from_cell, Vector3i(4, 2, 0))
	var source := building_manager.place_building(source_cell, building_manager.arrow_tower)
	building_manager.select_building(null)
	_expect(source != null, "mirror-trajectory fixture places a real source tower")
	_expect(mirror_manager.update_preview(from_cell, edge_index), "copy-mirror placement creates its virtual-image preview")
	var mirror_virtual_images := mirror_manager.get_preview_projections()
	_expect(
		mirror_virtual_images.size() == 1
		and mirror_manager.get_preview_mirror() != null
		and _is_green(mirror_manager.get_preview_mirror().get_preview_display_color()),
		"valid mirror edge renders the physical mirror preview in green"
	)
	var trajectory_data := mirror_manager.get_preview_projectile_trajectory()
	var trajectory_payloads: Array = trajectory_data.get("payloads", [])
	_expect(
		trajectory_data.get("building") == source
		and trajectory_payloads.size() == 1
		and (trajectory_payloads[0] as MirrorCopyPayload).projected_cell == target_cell,
		"copy-mirror preview exposes its source tower and generated virtual-image transform"
	)
	var visualizer := BuildingSelectionVisualizer.new()
	host.add_child(visualizer)
	visualizer.configure(grid, building_manager)
	visualizer.set_mirror_preview_trajectory_resolver(
		Callable(mirror_manager, "get_preview_projectile_trajectory")
	)
	var segments := visualizer.debug_get_projectile_trajectory_segments()
	var source_segments := segments.filter(
		func(segment: Dictionary) -> bool: return not bool(segment.get("projected", false))
	)
	var virtual_segments := segments.filter(
		func(segment: Dictionary) -> bool: return bool(segment.get("projected", false))
	)
	_expect(
		source_segments.size() == source.get_projectile_launch_directions().size(),
		"copy-mirror placement displays every source-building preview trajectory"
	)
	_expect(
		virtual_segments.size() == source.get_projectile_launch_directions().size()
		and virtual_segments[0].get("projected_cell") == target_cell,
		"copy-mirror placement displays every generated virtual-image preview trajectory"
	)
	var payload := trajectory_payloads[0] as MirrorCopyPayload
	_expect(
		(source_segments[0].get("start") as Vector3).distance_to(source.get_attack_origin()) < 0.001
		and (virtual_segments[0].get("start") as Vector3).distance_to(
			payload.transform_point(source.get_attack_origin())
		) < 0.001,
		"source and virtual trajectories start from their corresponding attack origins"
	)
	mirror_manager.clear_preview()
	visualizer.refresh()
	_expect(
		not visualizer.has_projectile_trajectory_visual(),
		"clearing mirror placement removes both transient trajectories"
	)
	mirror_manager.reflect_mirror_definition = TestDefinitionFactory.make_reflect_mirror_definition()
	_expect(mirror_manager.update_reflect_preview(from_cell, edge_index), "reflect-mirror placement preview remains available")
	visualizer.refresh()
	_expect(
		not visualizer.has_projectile_trajectory_visual(),
		"reflect-mirror placement does not show copy trajectories"
	)
	host.queue_free()
	await process_frame


func _assert_original_and_copy_trajectories(segments: Array[Dictionary], context: String) -> void:
	var originals: Array[Dictionary] = []
	var copies: Array[Dictionary] = []
	for segment in segments:
		if bool(segment.get("projected", false)):
			copies.append(segment)
		else:
			originals.append(segment)
	_expect(originals.size() == 1, "%s keeps the source trajectory" % context)
	_expect(
		copies.size() == 2
		and int(copies[0].get("reflection_index", -1)) == 0
		and int(copies[1].get("reflection_index", -1)) == 1,
		"%s copy trajectory calculates its reflected segment" % context
	)
	_expect(
		copies.size() == 2
		and not bool(copies[0].get("blocked", true))
		and bool(copies[1].get("blocked", false)),
		"%s copy trajectory stops at the shared ballistic blocker" % context
	)


func _trace_copy_preview_reflection(start: Vector3, end: Vector3) -> Dictionary:
	var segment := end - start
	if (
		start.distance_to(_copy_preview_origin) > 0.001
		or segment.length_squared() <= 0.000001
		or segment.normalized().dot(_copy_preview_direction) < 0.999
		or segment.length() < 0.5
	):
		return {"hit": false}
	return {
		"hit": true,
		"position": _copy_preview_reflection_point,
		"normal": _copy_preview_direction,
		"distance": 0.5,
		"epsilon": 0.0001,
	}


func _trace_copy_preview_blocker(start: Vector3, end: Vector3) -> Dictionary:
	var segment := end - start
	var reflected_direction := -_copy_preview_direction
	if (
		start.distance_to(_copy_preview_reflection_point) > 0.001
		or segment.length_squared() <= 0.000001
		or segment.normalized().dot(reflected_direction) < 0.999
		or segment.length() < 0.75
	):
		return {"hit": false}
	var position := start + reflected_direction * 0.75
	return {
		"hit": true,
		"position": position,
		"distance": 0.75,
		"blocker": self,
	}

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
	building_manager.arrow_tower.get_level_stats(1).model_asset = _make_textured_model_asset()
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
	_expect(is_equal_approx(mirror.get_mirror_height(), grid.cell_size * 1.20), "test copy mirror uses the fixture's 1.20-cell height")
	var projections := mirror_manager.get_projections(target_cell)
	_expect(projections.size() == 2, "one mirror projects the source tile's tower and spike as one group")
	_expect(_has_projection_kind(projections, &"arrow_tower") and _has_projection_kind(projections, &"spike"), "whole-tile projection preserves both source content kinds")
	var tower_projection := _find_projection_kind(projections, &"arrow_tower")
	var tile_projection := _find_projection_kind(projections, &"spike")
	_expect(tower_projection.get_visual_snapshot() != null, "tower projection reuses a snapshot of the source Building visual")
	_expect(tile_projection.get_visual_snapshot() != null, "tile-effect projection reuses a snapshot of the source tile content")
	var source_snapshot := arrow.create_copy_visual_snapshot()
	var source_model_mesh := _find_first_mesh_instance(source_snapshot)
	var projected_model_mesh := _find_first_mesh_instance(tower_projection.get_visual_snapshot())
	var source_model_material := _get_effective_standard_material(source_model_mesh)
	var projected_model_material := _get_effective_standard_material(projected_model_mesh)
	_expect(projected_model_material.albedo_color == source_model_material.albedo_color, "projection preserves the source model material color without tinting")
	_expect(projected_model_material.albedo_texture == source_model_material.albedo_texture, "projection preserves the source model texture resource")
	_expect(
		is_equal_approx(projected_model_mesh.transparency, 1.0 - tower_projection.payload.projection_alpha),
		"the producing mirror level controls copied-model opacity"
	)
	var projection_overlay := projected_model_material.next_pass as ShaderMaterial
	var projection_accent: Color = (
		projection_overlay.get_shader_parameter("accent")
		if projection_overlay != null
		else Color.BLACK
	)
	_expect(
		projection_overlay != null
		and projection_accent.b > projection_accent.r * 2.0
		and projection_accent.b > projection_accent.g,
		"the copied model itself receives a strongly blue shader overlay"
	)
	source_snapshot.free()
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
	_expect(not retired_projection.sync_source_visual_pose() and not retired_projection.visible, "queued pose synchronization cannot reveal a retired projection")
	projections = mirror_manager.get_projections(target_cell)
	tower_projection = _find_projection_kind(projections, &"arrow_tower")
	tile_projection = _find_projection_kind(projections, &"spike")
	_expect(tile_manager.get_occupant(target_cell) == null, "default projections do not write TileCellData occupancy")
	var logical_facing_before_aim := arrow.facing_index
	var projection_snapshot_id := tower_projection.get_visual_snapshot().get_instance_id()
	var aim_target := _make_target(host, grid.cell_to_world(Vector3i(2, 0, 0)))
	combat_manager.register_target(aim_target)
	arrow.acquire_target()
	_expect(arrow.update_visual_orientation(1.0), "target-tracking building rotates its visual pose toward the acquired target")
	var expected_aim_direction := aim_target.get_target_position() - arrow.get_attack_origin()
	expected_aim_direction.y = 0.0
	_expect(arrow.get_visual_facing_direction().dot(expected_aim_direction.normalized()) > 0.999, "tracking visual faces the live target")
	_expect(arrow.facing_index == logical_facing_before_aim, "visual target tracking never changes the logical placement facing")
	var first_aim_transform := arrow.get_copy_visual_transform()
	_expect(tower_projection.sync_source_visual_pose(), "tower projection synchronizes the live source pose without rebuilding")
	_expect(
		tower_projection.get_visual_snapshot().global_transform.is_equal_approx(
			tower_projection.payload.transform_transform(first_aim_transform)
		),
		"projection applies the exact reflection matrix to the source visual pose"
	)
	aim_target.global_position = grid.cell_to_world(Vector3i(2, 4, 0))
	_expect(arrow.update_visual_orientation(1.0), "tracking visual continues following a moving target")
	_expect(tower_projection.sync_source_visual_pose(), "projection follows a later source orientation update")
	_expect(tower_projection.get_visual_snapshot().get_instance_id() == projection_snapshot_id, "live pose synchronization keeps the same projection snapshot node")
	_expect(not tower_projection.get_visual_snapshot().global_transform.is_equal_approx(tower_projection.payload.transform_transform(first_aim_transform)), "projection pose changes when its source model turns")
	_expect(
		tower_projection.get_visual_snapshot().global_transform.is_equal_approx(
			tower_projection.payload.transform_transform(arrow.get_copy_visual_transform())
		),
		"updated projection remains the source model's complete geometric mirror"
	)
	var reflection_camera := Camera3D.new()
	host.add_child(reflection_camera)
	reflection_camera.global_position = grid.cell_to_world(Vector3i(2, 2, 0)) + Vector3(0.0, 4.0, 3.0)
	reflection_camera.look_at(mirror.global_position + Vector3.UP * 0.35)
	reflection_camera.current = true
	var source_camera_attributes := CameraAttributesPractical.new()
	source_camera_attributes.dof_blur_near_enabled = true
	source_camera_attributes.dof_blur_far_enabled = true
	reflection_camera.attributes = source_camera_attributes
	mirror_manager.set_reflection_camera(reflection_camera)
	_expect(mirror.get_reflection_surface() != null and mirror.get_reflection_surface().mesh is ArrayMesh, "copy mirror active face owns a dedicated oval reflection surface")
	_expect(mirror.get_reflection_surface().global_basis.z.normalized().dot(mirror.get_active_normal()) > 0.99, "reflection surface front normal follows the configured active side")
	var mirror_center := mirror.global_position + Vector3.UP * mirror.get_mirror_height() * 0.5
	var surface_depth_offset := (mirror.get_reflection_surface().global_position - mirror_center).dot(mirror.get_active_normal())
	_expect(surface_depth_offset > mirror.get_mirror_thickness() * 0.5, "reflection surface stays outside the mirror body at distant depth precision")
	_expect(mirror.request_reflection_refresh(), "visible active mirror face schedules one shared-world reflection refresh")
	_expect(mirror.get_reflection_camera() != null and mirror.get_reflection_camera().projection == reflection_camera.projection, "reflection camera copies the source projection without an extreme off-axis frustum")
	_expect(mirror.get_reflection_camera().attributes == null, "reflection capture excludes final-view depth of field")
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
	_expect(
		reflection_material != null
		and reflection_material.shader.code.contains("1.0 - SCREEN_UV.x"),
		"mirror shader counter-corrects the reflected camera's horizontal handedness"
	)
	_expect(
		reflection_material != null
		and reflection_material.shader.code.contains("surface_tint.a")
		and reflection_material.shader.code.contains("effective_tint"),
		"transparent mirror tint controls tint strength instead of multiplying the reflection to black"
	)
	var mirror_body := mirror.get_node("MirrorBody") as MeshInstance3D
	var mirror_body_material := mirror_body.material_override as StandardMaterial3D
	var back_color := mirror_body_material.albedo_color
	_expect(absf(back_color.r - back_color.g) < 0.04 and absf(back_color.g - back_color.b) < 0.04, "copy mirror body uses a neutral grey back-face base")
	_expect(mirror.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D).size() == 1, "copy mirror has no separate top-facing marker mesh")
	_expect(not mirror_body.get_layer_mask_value(1) and mirror_body.get_layer_mask_value(20), "mirror body is excluded from reflection cameras to prevent self-occlusion")
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
	var second_mirrored_target := _make_target(
		host,
		grid.cell_to_world(mirrored_target_cell) + Vector3(grid.cell_size * 0.75, 0.0, 0.0)
	)
	combat_manager.register_target(second_mirrored_target)
	var stuff_manager := StuffManager.new()
	host.add_child(stuff_manager)
	stuff_manager.configure(grid, null)
	_expect(stuff_manager.load_level(_make_level(false)), "copy attack fixture Stuff runtime loads")
	mirror_manager.set_stuff_manager(stuff_manager)
	var original_endpoint := grid.cell_to_world(Vector3i(1, 2, 0)) + Vector3(0.0, mirrored_target.debug_height * 0.55, 0.0)
	var projected_start := tower_projection.payload.transform_point(arrow.get_attack_origin())
	var projected_end := tower_projection.payload.transform_point(original_endpoint)
	var old_endpoint_distance := projected_start.distance_to(projected_end)
	_expect(mirror.set_level(2), "copy mirror upgrades to level two for attack-effect coverage")
	mirror_manager.rebuild_now()
	tower_projection = _find_projection_kind(
		mirror_manager.get_projections(target_cell),
		&"arrow_tower"
	)
	_expect(
		tower_projection != null
		and tower_projection.payload.attack_effects.has_effect(&"burst_arrow"),
		"level-two copied arrow projection carries the burst-arrow effect"
	)
	arrow.notify_copy_attack(&"projectile", arrow.get_attack_origin(), original_endpoint, 17.0)
	var projection_projectile := _find_projection_projectile(combat_manager)
	_expect(
		projection_projectile != null
		and projection_projectile.debug_get_attack_effect_ids().has(&"burst_arrow"),
		"original arrow attack spawns a burst-enabled from-start projection projectile"
	)
	if projection_projectile != null:
		projection_projectile._process(10.0)
	_expect(
		is_equal_approx(
			mirrored_target.current_hp,
			mirrored_target.max_hp - 17.0 * mirror.get_damage_multiplier()
		)
		and is_equal_approx(
			second_mirrored_target.current_hp,
			second_mirrored_target.max_hp - 17.0 * mirror.get_damage_multiplier()
		),
		"piercing projection projectile damages both eligible targets along its mirrored ray"
	)
	_expect(
		_count_active_projection_projectiles(combat_manager) == 8,
		"each of two piercing impacts emits four non-recursive projection arrows at copy reinforcement one"
	)
	combat_manager.clear_projectiles()
	combat_manager.unregister_target(second_mirrored_target)
	second_mirrored_target.queue_free()
	await process_frame
	_expect(mirror.set_level(1), "copy mirror returns to level one after attack-effect coverage")
	mirror_manager.rebuild_now()
	tower_projection = _find_projection_kind(
		mirror_manager.get_projections(target_cell),
		&"arrow_tower"
	)
	mirrored_target.global_position = grid.cell_to_world(Vector3i(6, 0, 0))
	arrow.notify_copy_attack(&"projectile", arrow.get_attack_origin(), original_endpoint, 17.0)
	var continuing_projection_projectile := _find_projection_projectile(combat_manager)
	var continued_distance := minf(
		old_endpoint_distance + grid.cell_size * 0.25,
		arrow.get_attack_range_world() - grid.cell_size * 0.25
	)
	if continuing_projection_projectile != null:
		continuing_projection_projectile._process(
			continued_distance / arrow.get_projectile_speed_world()
		)
	_expect(
		continuing_projection_projectile != null
		and not continuing_projection_projectile.is_queued_for_deletion()
		and continuing_projection_projectile.get_distance_traveled() > old_endpoint_distance + 0.001,
		"projection arrow continues beyond the launch-time endpoint until collision or range exhaustion"
	)
	if continuing_projection_projectile != null:
		continuing_projection_projectile.queue_free()
	await process_frame
	mirrored_target.global_position = grid.cell_to_world(mirrored_target_cell)
	var ballistic_blocker := StuffDefinition.new()
	ballistic_blocker.stuff_id = &"copy_attack_blocker"
	ballistic_blocker.display_name = "Copy attack blocker"
	ballistic_blocker.blocks_ballistics = true
	var blocker_runtime := stuff_manager.add_stuff(
		mirrored_target_cell,
		ballistic_blocker,
		0,
		&"copy_attack_blocker_1"
	)
	_expect(blocker_runtime != null, "copy attack fixture places a live ballistic-blocking Stuff")
	var blocked_arrow_before := mirrored_target.current_hp
	arrow.notify_copy_attack(&"projectile", arrow.get_attack_origin(), original_endpoint, 17.0)
	var blocked_projection_projectile := _find_projection_projectile(combat_manager)
	if blocked_projection_projectile != null:
		blocked_projection_projectile._process(10.0)
	_expect(
		blocked_projection_projectile != null
		and blocked_projection_projectile.is_queued_for_deletion()
		and is_equal_approx(mirrored_target.current_hp, blocked_arrow_before),
		"copy-mirror projectile is absorbed by real blocking Stuff before its mirrored target"
	)
	_expect(stuff_manager.remove_stuff(&"copy_attack_blocker_1"), "copy attack fixture removes the projectile blocker")
	await process_frame

	building_manager.remove_building(source_cell, 0.0)
	var laser := building_manager.place_building(source_cell, building_manager.laser_tower)
	laser.set_process(false)
	mirror_manager.rebuild_now()
	_expect(laser != null and _has_projection_kind(mirror_manager.get_projections(target_cell), &"laser_tower"), "source replacement dynamically rebuilds a laser projection")
	var laser_projection := _find_projection_kind(mirror_manager.get_projections(target_cell), &"laser_tower")
	var laser_snapshot_id := laser_projection.get_visual_snapshot().get_instance_id()
	var laser_projection_before := laser_projection.get_visual_snapshot().global_transform
	var laser_facing_before := laser.facing_index
	_expect(laser.definition.aim_mode == BuildingDefinition.AimMode.FIXED_FACING, "laser tower keeps fixed-facing targeting behavior")
	_expect(laser.rotate_facing(1) and laser.facing_index != laser_facing_before, "manual laser rotation changes its logical attack facing")
	_expect(laser_projection.sync_source_visual_pose(), "fixed-facing projection synchronizes a manual source turn")
	_expect(laser_projection.get_visual_snapshot().get_instance_id() == laser_snapshot_id, "manual source rotation does not rebuild its projection snapshot")
	_expect(not laser_projection.get_visual_snapshot().global_transform.is_equal_approx(laser_projection_before), "laser projection turns when the manually rotated source turns")
	_expect(
		laser_projection.get_visual_snapshot().global_transform.is_equal_approx(
			laser_projection.payload.transform_transform(laser.get_copy_visual_transform())
		),
		"fixed-facing source rotation receives the same strict mirror transform"
	)
	var laser_before := mirrored_target.current_hp
	laser.notify_copy_attack(&"laser", laser.get_attack_origin(), original_endpoint, 9.0)
	_expect(is_equal_approx(mirrored_target.current_hp, laser_before - 9.0), "laser projection mirrors the source segment and damage tick without independent targeting")
	_expect(mirrored_target.is_movement_slowed(), "copied continuous laser mirrors the source cold status")
	_expect(
		laser_projection.get_laser_propagation_distance() > 0.0
		and laser_projection.get_laser_propagation_distance() < laser.get_attack_range_world(),
		"copied continuous laser maintains its own non-instant propagation front"
	)
	var copied_burst_target := laser_projection.get_laser_burst_target()
	_expect(
		bool(copied_burst_target.get("hit", false))
		and (copied_burst_target.get("position", Vector3.ZERO) as Vector3).is_equal_approx(
			mirrored_target.get_target_position()
		),
		"copied laser stores the first enemy from its independently traced path"
	)
	var copied_burst_before := mirrored_target.current_hp
	laser.notify_copy_attack(&"laser_burst", laser.get_attack_origin(), original_endpoint, laser.get_laser_burst_damage())
	_expect(
		is_equal_approx(mirrored_target.current_hp, copied_burst_before),
		"retired body-upgrade laser-burst events no longer affect copies"
	)
	blocker_runtime = stuff_manager.add_stuff(
		mirrored_target_cell,
		ballistic_blocker,
		0,
		&"copy_attack_blocker_2"
	)
	var projected_laser_start := laser_projection.payload.transform_point(laser.get_attack_origin())
	var projected_laser_end := laser_projection.payload.transform_point(original_endpoint)
	var retained_laser_blocker_hit := mirror_manager.trace_ballistic_blocker(
		projected_laser_start,
		projected_laser_end
	)
	_expect(
		bool(retained_laser_blocker_hit.get("hit", false)),
		"copy-mirror retained-laser path resolves the real blocking Stuff"
	)
	var blocked_laser_before := mirrored_target.current_hp
	laser.notify_copy_attack(&"laser", laser.get_attack_origin(), original_endpoint, 9.0)
	_expect(
		blocker_runtime != null and is_equal_approx(mirrored_target.current_hp, blocked_laser_before),
		"copy-mirror retained laser is truncated by real blocking Stuff"
	)
	var blocked_laser_endpoint := laser_projection.get_laser_endpoint(projected_laser_start)
	var blocked_laser_distance := laser_projection.get_laser_propagation_distance()
	var blocked_laser_key := laser_projection.payload.stable_key
	_expect(stuff_manager.remove_stuff(&"copy_attack_blocker_2"), "copy attack fixture removes the retained-laser blocker")
	await process_frame
	laser_projection = _find_projection_kind(mirror_manager.get_projections(target_cell), &"laser_tower")
	_expect(laser_projection != null, "laser projection rebuild preserves a live projection after Stuff removal")
	if laser_projection == null:
		host.queue_free()
		return
	projected_laser_start = laser_projection.payload.transform_point(laser.get_attack_origin())
	_expect(
		laser_projection.payload.stable_key == blocked_laser_key
		and is_equal_approx(
			laser_projection.get_laser_propagation_distance(),
			blocked_laser_distance
		),
		"laser projection rebuild restores the stable-key propagation distance"
	)
	laser.definition.get_level_stats(laser.level).projectile_penetration_count = 32
	laser.notify_copy_attack(&"laser", laser.get_attack_origin(), original_endpoint, 1.2)
	var resumed_laser_endpoint := laser_projection.get_laser_endpoint(projected_laser_start)
	_expect(
		resumed_laser_endpoint.distance_to(projected_laser_start)
		> blocked_laser_endpoint.distance_to(projected_laser_start),
		"copied continuous laser resumes growth after its local Stuff blocker disappears"
	)
	_expect(mirror.set_level(2), "copy mirror upgrades to level two for ice-burst coverage")
	mirror_manager.rebuild_now()
	laser_projection = _find_projection_kind(mirror_manager.get_projections(target_cell), &"laser_tower")
	_expect(
		laser_projection != null
		and laser_projection.payload.attack_effects.has_effect(&"ice_copy_burst"),
		"level-two copied ice tower receives burst and freeze together"
	)
	var ice_path_start := laser_projection.payload.transform_point(laser.get_attack_origin())
	var ice_path_end := laser_projection.payload.transform_point(original_endpoint)
	var ice_direction := (ice_path_end - ice_path_start).normalized()
	var ice_side := Vector3(-ice_direction.z, 0.0, ice_direction.x)
	var ice_burst_target := laser_projection.get_laser_burst_target()
	var ice_burst_center: Vector3 = ice_burst_target.get(
		"position",
		mirrored_target.get_target_position()
	)
	var ice_splash_target := CombatTarget.new()
	ice_splash_target.debug_visual_enabled = false
	ice_splash_target.max_hp = 1000.0
	ice_splash_target.position = ice_burst_center + ice_side * grid.cell_size
	host.add_child(ice_splash_target)
	combat_manager.register_target(ice_splash_target)
	mirrored_target.current_hp = mirrored_target.max_hp
	var ice_splash_hp_before := ice_splash_target.current_hp
	laser.notify_copy_attack(
		&"laser",
		laser.get_attack_origin(),
		original_endpoint,
		laser.get_laser_damage_per_second() * 3.0
	)
	_expect(
		is_equal_approx(
			ice_splash_target.current_hp,
			ice_splash_hp_before - laser.get_laser_burst_damage() * mirror.get_damage_multiplier()
		)
		and ice_splash_target.is_frozen()
		and is_equal_approx(ice_splash_target.get_freeze_remaining(), 1.5),
		"shared three-second source event makes the L2 copy burst at its own first hit and freeze for tier one duration"
	)
	var ice_clock_before_upgrade := laser.get_ice_copy_mirror_state()
	laser.set_facing_index(laser.facing_index + 1)
	laser.apply_level(2)
	var ice_clock_after_upgrade := laser.get_ice_copy_mirror_state()
	_expect(
		int(ice_clock_after_upgrade.get("event_sequence", -1))
			== int(ice_clock_before_upgrade.get("event_sequence", -2))
		and is_equal_approx(
			float(ice_clock_after_upgrade.get("elapsed", -1.0)),
			float(ice_clock_before_upgrade.get("elapsed", -2.0))
		),
		"ice source rotation and tower upgrade preserve the mirror event clock"
	)
	combat_manager.unregister_target(ice_splash_target)
	ice_splash_target.queue_free()
	_expect(mirror.set_level(1), "copy mirror returns to level one before base pulse-copy coverage")
	mirror_manager.rebuild_now()

	building_manager.remove_building(source_cell, 0.0)
	var pulse := building_manager.place_building(source_cell, building_manager.pulse_laser_tower)
	mirror_manager.rebuild_now()
	_expect(pulse != null and _has_projection_kind(mirror_manager.get_projections(target_cell), &"pulse_laser_tower"), "source replacement dynamically rebuilds an independent pulse-laser projection")
	var pulse_before := mirrored_target.current_hp
	pulse.notify_copy_attack(&"pulse_laser", pulse.get_attack_origin(), original_endpoint, 11.0)
	var projection_pulse := _find_pulse_laser(combat_manager)
	_expect(projection_pulse != null, "pulse-laser projection spawns a full path through the shared combat manager")
	if projection_pulse != null:
		projection_pulse._process(0.10)
	_expect(is_equal_approx(mirrored_target.current_hp, pulse_before - 11.0), "pulse-laser projection independently resolves its mirrored beam damage")
	await process_frame
	blocker_runtime = stuff_manager.add_stuff(
		mirrored_target_cell,
		ballistic_blocker,
		0,
		&"copy_attack_blocker_3"
	)
	var blocked_pulse_before := mirrored_target.current_hp
	pulse.notify_copy_attack(&"pulse_laser", pulse.get_attack_origin(), original_endpoint, 11.0)
	var blocked_projection_pulse := _find_pulse_laser(combat_manager)
	if blocked_projection_pulse != null:
		blocked_projection_pulse._process(0.10)
	_expect(
		blocker_runtime != null
		and blocked_projection_pulse != null
		and is_equal_approx(mirrored_target.current_hp, blocked_pulse_before),
		"copy-mirror pulse laser is truncated by real blocking Stuff"
	)
	_expect(stuff_manager.remove_stuff(&"copy_attack_blocker_3"), "copy attack fixture removes the pulse-laser blocker")
	await process_frame
	combat_manager.clear_projectiles()
	_expect(mirror.set_level(2), "copy mirror upgrades to level two for pulse-overdrive coverage")
	mirror_manager.rebuild_now()
	var pulse_projection := _find_projection_kind(
		mirror_manager.get_projections(target_cell),
		&"pulse_laser_tower"
	)
	_expect(
		pulse_projection != null
		and pulse_projection.payload.attack_effects.has_effect(&"pulse_laser_overdrive"),
		"level-two pulse-laser copy receives the shared overdrive effect"
	)
	for _charge_index in range(5):
		pulse.notify_copy_attack(&"pulse_laser", pulse.get_attack_origin(), original_endpoint, 11.0)
	_expect(
		_count_active_pulse_lasers(combat_manager) == 0
		and int(pulse.get_pulse_copy_mirror_state().get("charge_count", 0)) == 5
		and StringName(pulse.get_pulse_copy_mirror_state().get("phase", &"")) == &"pending",
		"five source flashes charge once per shot while the eligible copy stays completely silent"
	)
	mirror_manager._process(0.01)
	_expect(
		pulse_projection.debug_is_pulse_charge_orb_visible(),
		"charging pulse-laser copy shows the programmatic red pulsing muzzle orb"
	)
	var pulse_visual_duration := (
		pulse.get_pulse_laser_fade_in_time()
		+ pulse.get_pulse_laser_hold_time()
		+ pulse.get_pulse_laser_fade_out_time()
	)
	pulse._process(pulse_visual_duration + 0.001)
	var overdrive_state := pulse.get_pulse_copy_mirror_state()
	_expect(
		StringName(overdrive_state.get("phase", &"")) == &"overdrive"
		and float(overdrive_state.get("overdrive_remaining", 0.0)) > 9.99,
		"the shared source clock starts the ten-second overdrive after the fifth flash completes"
	)
	combat_manager.clear_projectiles()
	var overdrive_target := CombatTarget.new()
	overdrive_target.debug_visual_enabled = false
	overdrive_target.max_hp = 1000.0
	var overdrive_path_start := pulse_projection.payload.transform_point(pulse.get_attack_origin())
	var overdrive_path_end := pulse_projection.payload.transform_point(
		pulse.get_attack_origin() + pulse.get_facing_direction() * pulse.get_attack_range_world()
	)
	var overdrive_target_position := overdrive_path_start + (
		overdrive_path_end - overdrive_path_start
	).normalized() * grid.cell_size
	overdrive_target.position = Vector3(
		overdrive_target_position.x,
		grid.cell_to_world(target_cell).y,
		overdrive_target_position.z
	)
	host.add_child(overdrive_target)
	combat_manager.register_target(overdrive_target)
	var overdrive_hp_before := overdrive_target.current_hp
	mirror_manager._process(0.50)
	var expected_overdrive_damage := (
		pulse.get_instant_damage()
		* pulse.get_attacks_per_second()
		* mirror.get_damage_multiplier()
		* 0.50
	)
	_expect(
		not pulse_projection.debug_is_pulse_charge_orb_visible()
		and pulse_projection.debug_get_pulse_overdrive_single_sine_count() > 0
		and pulse_projection.debug_get_pulse_overdrive_axis_segment_count() == 0
		and pulse_projection.debug_get_pulse_overdrive_wave_pair_count() == 0,
		"overdrive renders exactly one thick sine with no axis or second filament"
	)
	var pulse_reflection_colors := pulse.get_pulse_laser_reflection_colors()
	_expect(
		not pulse_reflection_colors.is_empty()
		and pulse_projection.debug_get_pulse_overdrive_visual_color().is_equal_approx(
			pulse_reflection_colors[0]
		)
		and pulse_projection.debug_get_pulse_overdrive_rendered_color().is_equal_approx(
			pulse_reflection_colors[0]
		),
		"unreflected overdrive cache and live material both start at the fixed red color"
	)
	_expect(
		is_equal_approx(
			overdrive_target.current_hp,
			overdrive_hp_before - expected_overdrive_damage
		),
		"overdrive applies configured DPS (expected %.3f HP, got %.3f)" % [
			overdrive_hp_before - expected_overdrive_damage,
			overdrive_target.current_hp,
		]
	)
	pulse.apply_level(2)
	mirror_manager.rebuild_now()
	pulse_projection = _find_projection_kind(
		mirror_manager.get_projections(target_cell),
		&"pulse_laser_tower"
	)
	mirror_manager._process(0.01)
	_expect(
		pulse_projection != null
		and pulse_projection.debug_get_pulse_overdrive_visual_color().is_equal_approx(
			pulse_reflection_colors[0]
		),
		"source tower level never offsets an unreflected copied-overdrive color"
	)
	var old_pulse_phase := pulse_projection.debug_get_pulse_charge_orb_phase()
	var old_pulse_distance := pulse_projection.debug_get_pulse_overdrive_propagation_distance()
	var old_source_state := pulse.get_pulse_copy_mirror_state()
	mirror_manager.rebuild_now()
	pulse_projection = _find_projection_kind(
		mirror_manager.get_projections(target_cell),
		&"pulse_laser_tower"
	)
	mirror_manager._process(0.01)
	_expect(
		pulse_projection != null
		and is_equal_approx(pulse_projection.debug_get_pulse_charge_orb_phase(), old_pulse_phase)
		and is_equal_approx(
			pulse_projection.debug_get_pulse_overdrive_propagation_distance(),
			old_pulse_distance
		)
		and pulse_projection.debug_get_pulse_overdrive_rendered_color().is_equal_approx(
			pulse_reflection_colors[0]
		),
		"mirror rebuild restores pulse state and reconfigures the new renderer to red"
	)
	pulse.set_facing_index(pulse.facing_index + 1)
	pulse.apply_level(2)
	var preserved_source_state := pulse.get_pulse_copy_mirror_state()
	_expect(
		StringName(preserved_source_state.get("phase", &"")) == &"overdrive"
		and int(preserved_source_state.get("generation", -1)) == int(old_source_state.get("generation", -2))
		and is_equal_approx(
			float(preserved_source_state.get("overdrive_remaining", 0.0)),
			float(old_source_state.get("overdrive_remaining", -1.0))
		),
		"source rotation and tower upgrade preserve shared pulse charge/overdrive state"
	)
	combat_manager.unregister_target(overdrive_target)
	overdrive_target.queue_free()

	var overlapping := building_manager.place_building(target_cell, building_manager.arrow_tower)
	_expect(overlapping != null, "a real building can occupy a tile already containing non-occupying projections")
	mirror_manager.rebuild_now()
	_expect(not mirror_manager.get_projections(target_cell).is_empty(), "default occupancy switch keeps projections over a real building")
	mirror_manager.copy_mirror_definition.projection_ignores_occupancy = false
	mirror_manager.rebuild_now()
	_expect(
		not mirror_manager.get_projections(target_cell).is_empty(),
		"legacy strict-occupancy data cannot suppress projections that coexist with a real entity"
	)
	mirror_manager.copy_mirror_definition.projection_ignores_occupancy = true
	_expect(resource_manager.get_mirror_count() == 1, "only the physical mirror consumes mirror cap")
	var replacement_building_manager := BuildingManager.new()
	host.add_child(replacement_building_manager)
	replacement_building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var health_before_reconfigure_attack := mirrored_target.current_hp
	mirror_manager.configure(
		grid,
		tile_manager,
		resource_manager,
		combat_manager,
		replacement_building_manager,
		fixture.registry
	)
	pulse.notify_copy_attack(&"pulse_laser", pulse.get_attack_origin(), original_endpoint, 9.0)
	_expect(
		is_equal_approx(mirrored_target.current_hp, health_before_reconfigure_attack),
		"mirror manager reconfiguration disconnects attacks from the previous building module"
	)
	host.queue_free()
	await process_frame

func _test_unlimited_projection_overlap_with_single_real_entity() -> void:
	var fixture := _make_fixture(_make_level(false))
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var tile_manager: TileManager = fixture.tile
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var target_cell := Vector3i(5, 1, 0)
	var left_source := building_manager.place_building(
		Vector3i(2, 1, 0),
		building_manager.arrow_tower
	)
	var right_source := building_manager.place_building(
		Vector3i(6, 1, 0),
		building_manager.arrow_tower
	)
	_expect(left_source != null and right_source != null, "two independent projection sources are placed")
	var left_edge := grid.find_edge_index(Vector3i(3, 1, 0), Vector3i(4, 1, 0))
	var right_edge := grid.find_edge_index(Vector3i(6, 1, 0), target_cell)
	var left_mirror := mirror_manager.place_copy_mirror(Vector3i(3, 1, 0), left_edge, true)
	var right_mirror := mirror_manager.place_copy_mirror(Vector3i(6, 1, 0), right_edge, true)
	_expect(left_mirror != null and right_mirror != null, "two mirrors may project independent sources onto one target tile")
	mirror_manager.rebuild_now()
	_expect(
		mirror_manager.get_projections(target_cell).size() == 2,
		"one tile retains both independent virtual images"
	)
	_expect(
		tile_manager.get_occupant(target_cell) == null,
		"multiple virtual images never create a real tile occupant"
	)
	var real_building := building_manager.place_building(target_cell, building_manager.arrow_tower)
	_expect(
		real_building != null and tile_manager.get_occupant(target_cell) == real_building,
		"one real entity can be placed on a tile containing multiple virtual images"
	)
	mirror_manager.copy_mirror_definition.projection_ignores_occupancy = false
	mirror_manager.rebuild_now()
	_expect(
		mirror_manager.get_projections(target_cell).size() == 2,
		"legacy strict-occupancy data cannot remove either overlapping virtual image"
	)
	_expect(
		building_manager.place_building(target_cell, building_manager.arrow_tower) == null
		and tile_manager.get_occupant(target_cell) == real_building,
		"a second real entity is rejected while the first entity remains intact"
	)
	host.queue_free()
	await process_frame


func _test_projected_barrier_and_shared_edge_occupancy() -> void:
	var level := _make_level(true)
	var path: PathDefinition = level.paths[0]
	path.cells.assign([
		Vector3i(1, 2, 0),
		Vector3i(2, 2, 0),
		Vector3i(2, 3, 0),
		Vector3i(3, 3, 0),
		Vector3i(4, 3, 0),
		Vector3i(4, 2, 0),
		Vector3i(5, 2, 0),
		Vector3i(6, 2, 0),
	])
	level.spawn_points[0].cell = path.get_start_cell()
	level.base_cell = path.get_end_cell()
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
	_expect(mirror_manager.remove_mirror(mirror), "selected physical mirror can be removed")
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
	var source_rock := rock_tile.get_runtime_obstacle(Vector3i(2, 2, 0))
	var projected_rock := rock_mirrors.resolve_projected_navigation_blocker(Vector3i(5, 2, 0))
	_expect(source_rock != null and projected_rock is MirrorProjection, "projected rock exposes the mirrored attack target")
	var direct_projection_alpha: float = (projected_rock as MirrorProjection).payload.projection_alpha
	var source_durability_before := float(source_rock.get("current_durability"))
	projected_rock.call("take_structure_damage", 11.0, null)
	_expect(
		is_equal_approx(float(source_rock.get("current_durability")), source_durability_before - 11.0),
		"projected rock damage is forwarded to the real source durability"
	)
	var second_edge := rock_grid.find_edge_index(Vector3i(5, 2, 0), Vector3i(6, 2, 0))
	rock_mirrors.place_copy_mirror(Vector3i(5, 2, 0), second_edge, true)
	rock_mirrors.rebuild_now()
	var recursive := rock_mirrors.get_projections(Vector3i(6, 2, 0))
	_expect(not recursive.is_empty() and recursive[0].payload.chain_depth == 2, "an existing projection can be copied through a second mirror")
	_expect(
		not recursive.is_empty()
		and recursive[0].payload.projection_alpha < direct_projection_alpha,
		"recursive projection becomes more transparent than its parent projection"
	)
	var direct_projection_mesh := _find_first_mesh_instance(
		(projected_rock as MirrorProjection).get_visual_snapshot()
	)
	var recursive_projection_mesh := _find_first_mesh_instance(
		recursive[0].get_visual_snapshot()
	)
	_expect(
		direct_projection_mesh != null
		and recursive_projection_mesh != null
		and recursive_projection_mesh.transparency > direct_projection_mesh.transparency
		and is_equal_approx(
			recursive_projection_mesh.transparency,
			1.0 - recursive[0].payload.projection_alpha
		),
		"recursive depth opacity reaches the rendered blue projection mesh"
	)
	_expect(recursive[0].payload.lineage.size() == 2, "recursive payload records a finite two-mirror lineage")
	_expect(recursive[0].get_visual_snapshot() != null and _snapshot_uses_immediate_mesh(recursive[0].get_visual_snapshot()), "recursive tile projection keeps the original tile-content snapshot")
	_expect(not _snapshot_has_named_mesh(recursive[0].get_visual_snapshot(), "Terrain"), "recursive tile projection never introduces terrain base geometry")
	var original_rock_center := rock_grid.cell_to_world(Vector3i(2, 2, 0))
	var recursive_rendered_center := recursive[0].get_visual_snapshot().global_transform * original_rock_center
	_expect(recursive_rendered_center.distance_to(recursive[0].payload.transform_point(original_rock_center)) < 0.001, "recursive tile snapshot applies every mirror axis to the original geometry")
	var durability_before_recursive_hit := float(source_rock.get("current_durability"))
	recursive[0].take_structure_damage(13.0, null)
	_expect(
		is_equal_approx(float(source_rock.get("current_durability")), durability_before_recursive_hit - 13.0),
		"recursive rock projection forwards damage to the same real source"
	)
	recursive[0].take_structure_damage(100000.0, null)
	_expect(rock_tile.get_runtime_obstacle(Vector3i(2, 2, 0)) == null, "destroying any rock projection depletes the real source")
	_expect(rock_tile.can_place(Vector3i(2, 2, 0)) and rock_tile.allows_edge_building(Vector3i(2, 2, 0)), "destroyed source rock restores both building permissions")
	_expect(rock_mirrors.get_projections(Vector3i(5, 2, 0)).is_empty() and rock_mirrors.get_projections(Vector3i(6, 2, 0)).is_empty(), "source rock destruction removes all direct and recursive projections")
	_expect(rock_mirrors.get_mirrors().size() == 2, "shared rock destruction leaves every physical mirror intact")
	rock_host.queue_free()
	await process_frame

	var void_level := _make_level(false)
	var void_effect := VoidTileEffect.new()
	void_effect.max_capacity = 1
	void_effect.recovery_seconds_per_point = 100.0
	void_effect.swallow_interval = 0.25
	void_level.store_tile(_make_effect_tile(Vector3i(2, 2, 0), void_effect, false))
	var void_fixture := _make_fixture(void_level)
	var void_host: Node3D = void_fixture.host
	var void_grid: GridManager = void_fixture.grid
	var void_tile: TileManager = void_fixture.tile
	var void_mirrors: MirrorManager = void_fixture.mirror
	var void_renderer: TileRenderer = void_fixture.renderer
	var edge_index := void_grid.find_edge_index(Vector3i(3, 2, 0), Vector3i(4, 2, 0))
	void_mirrors.place_copy_mirror(Vector3i(3, 2, 0), edge_index, true)
	var effect_system := TileEffectSystem.new()
	void_host.add_child(effect_system)
	effect_system.configure(void_tile)
	effect_system.set_effect_overlay_binding_resolver(Callable(void_mirrors, "get_projected_effect_bindings"))
	void_renderer.set_effect_visual_state_resolver(Callable(effect_system, "get_void_fill_ratio"))
	effect_system.effect_visual_state_changed.connect(func(source_cell: Vector3i, fill_ratio: float) -> void:
		void_renderer.refresh_effect_visual(source_cell, fill_ratio)
		void_mirrors.rebuild_now()
	)
	var empty_projection := void_mirrors.get_projections(Vector3i(5, 2, 0))[0]
	var empty_depth := _snapshot_element_min_y(empty_projection.get_visual_snapshot())
	var falling_target := _make_target(void_host, void_grid.cell_to_world(Vector3i(5, 2, 0)))
	effect_system.apply_enter(falling_target, Vector3i(5, 2, 0))
	effect_system._process(0.25)
	_expect(not falling_target.is_alive(), "projected void executes the same periodic swallow effect")
	_expect(effect_system.get_void_current_fill(Vector3i(2, 2, 0)) == 1, "projected void consumes the real source tile's shared capacity")
	var filled_projection := void_mirrors.get_projections(Vector3i(5, 2, 0))[0]
	_expect(_snapshot_element_min_y(filled_projection.get_visual_snapshot()) > empty_depth + 0.1, "projected void rebuilds with the source's shallower filled geometry")
	var source_target := _make_target(void_host, void_grid.cell_to_world(Vector3i(2, 2, 0)))
	effect_system.apply_enter(source_target, Vector3i(2, 2, 0))
	effect_system._process(0.25)
	_expect(source_target.is_alive(), "a full projected/source void pair cannot consume a second enemy")
	void_host.queue_free()
	await process_frame

func _test_projected_rock_after_overlapping_barrier_breaks() -> void:
	var level := _make_level(true)
	var path: PathDefinition = level.paths[0]
	path.cells.clear()
	for x in range(4, 7):
		path.cells.append(Vector3i(x, 2, 0))
	level.spawn_points[0].cell = path.get_start_cell()
	level.base_cell = path.get_end_cell()
	var rock := RockTileEffect.new()
	rock.max_durability = 500.0
	level.store_tile(_make_effect_tile(Vector3i(2, 2, 0), rock, false))
	var fixture := _make_fixture(level)
	var host: Node3D = fixture.host
	var grid: GridManager = fixture.grid
	var tile_manager: TileManager = fixture.tile
	var building_manager: BuildingManager = fixture.building
	var mirror_manager: MirrorManager = fixture.mirror
	var mirror_edge := grid.find_edge_index(Vector3i(3, 2, 0), Vector3i(4, 2, 0))
	var mirror := mirror_manager.place_copy_mirror(Vector3i(3, 2, 0), mirror_edge, true)
	var barrier := building_manager.place_building(Vector3i(5, 2, 0), building_manager.barrier)
	_expect(mirror != null and barrier != null, "barrier can overlap a projected rock on the same path tile")
	_expect(
		building_manager.resolve_path_blocker(Vector3i(4, 2, 0), Vector3i(5, 2, 0)) == barrier,
		"ordinary barrier keeps attack priority over the overlapping projected rock"
	)
	var planner := PathRoutePlanner.new()
	host.add_child(planner)
	planner.configure(grid, tile_manager)
	planner.load_level(level)
	var points := PackedVector3Array()
	for cell in path.cells:
		points.append(grid.cell_to_world(cell))
	var enemy_definition := EnemyDefinition.new()
	enemy_definition.move_speed = 10.0
	enemy_definition.attack_damage = 200.0
	enemy_definition.attack_range = 0.65
	var enemy := EnemyUnit.new()
	enemy.debug_visual_enabled = false
	enemy.configure_unit(
		enemy_definition,
		points,
		path.cells,
		1.0,
		Callable(building_manager, "resolve_path_blocker"),
		path,
		Callable(planner, "find_detour"),
		func(cell: Vector3i) -> Vector3: return grid.cell_to_world(cell),
		Callable(),
		Callable(),
		Callable(tile_manager, "blocks_enemy_navigation")
	)
	enemy.set_process(false)
	host.add_child(enemy)
	var source_rock := tile_manager.get_runtime_obstacle(Vector3i(2, 2, 0))
	var first_projected_rock := mirror_manager.resolve_projected_navigation_blocker(Vector3i(5, 2, 0))
	var source_durability_before := float(source_rock.get("current_durability"))
	enemy._process(5.0)
	enemy._process(0.1)
	_expect(building_manager.get_building(Vector3i(5, 2, 0)) == null, "enemy destroys the higher-priority overlapping barrier first")
	var position_after_barrier := enemy.global_position
	await process_frame
	var rebuilt_projected_rock := mirror_manager.resolve_projected_navigation_blocker(Vector3i(5, 2, 0))
	_expect(
		rebuilt_projected_rock != null and rebuilt_projected_rock != first_projected_rock,
		"barrier removal rebuilds the overlapping projected rock at the frame boundary"
	)
	enemy._process(0.1)
	_expect(enemy.global_position == position_after_barrier, "projected rock still blocks the enemy after the barrier disappears mid-segment")
	enemy._process(0.1)
	_expect(
		float(source_rock.get("current_durability")) < source_durability_before,
		"enemy attacks the projected rock when every authored route remains blocked"
	)
	host.queue_free()
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
	building_manager.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	building_manager.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building_manager.pulse_laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.PULSE_LASER_TOWER)
	building_manager.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building_manager.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	building_manager.set_edge_occupancy_registry(registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror_manager.configure(grid, tile_manager, resource_manager, combat_manager, building_manager, registry)
	mirror_manager.set_tile_visual_snapshot_resolver(Callable(tile_renderer, "create_tile_content_visual_snapshot"))
	building_manager.set_projection_blocker_resolver(Callable(mirror_manager, "resolve_projected_blocker"))
	tile_manager.set_navigation_overlay_resolver(Callable(mirror_manager, "blocks_enemy_navigation"))
	tile_manager.set_navigation_overlay_blocker_resolver(Callable(mirror_manager, "resolve_projected_navigation_blocker"))
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
		"renderer": tile_renderer,
		"registry": registry,
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


func _is_green(color: Color) -> bool:
	return color.g > 0.8 and color.r < 0.3 and color.b < 0.4

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


func _make_textured_model_asset() -> ModelAssetDefinition:
	var root_node := Node3D.new()
	root_node.name = "TexturedTower"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TexturedBody"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.72, 0.42)
	mesh_instance.mesh = mesh
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.95, 0.20, 0.12, 1.0))
	image.set_pixel(1, 0, Color(0.10, 0.35, 0.95, 1.0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.71, 0.26, 1.0)
	material.albedo_texture = ImageTexture.create_from_image(image)
	mesh.material = material
	root_node.add_child(mesh_instance)
	mesh_instance.owner = root_node
	var packed_scene := PackedScene.new()
	packed_scene.pack(root_node)
	root_node.free()
	var asset := ModelAssetDefinition.new()
	asset.scene = packed_scene
	return asset


func _get_effective_standard_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	if mesh_instance.material_override is StandardMaterial3D:
		return mesh_instance.material_override as StandardMaterial3D
	if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
		return null
	var surface_override := mesh_instance.get_surface_override_material(0)
	if surface_override is StandardMaterial3D:
		return surface_override as StandardMaterial3D
	return mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D

func _snapshot_has_named_mesh(snapshot: Node3D, mesh_name: String) -> bool:
	if snapshot == null:
		return false
	var child := snapshot.get_node_or_null(NodePath(mesh_name))
	return child is MeshInstance3D and child.mesh is ImmediateMesh

func _snapshot_element_min_y(snapshot: Node3D) -> float:
	if snapshot == null:
		return INF
	var element := snapshot.get_node_or_null(NodePath("Element")) as MeshInstance3D
	if element == null or element.mesh == null or element.mesh.get_surface_count() == 0:
		return INF
	var arrays := element.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var minimum := INF
	for vertex in vertices:
		minimum = minf(minimum, vertex.y)
	return minimum

func _projection_materials_have_stable_order(projections: Array[MirrorProjection]) -> bool:
	var priorities: Dictionary = {}
	for projection in projections:
		var mesh := _find_first_mesh_instance(projection.get_visual_snapshot())
		if mesh == null:
			return false
		var material := _get_effective_standard_material(mesh)
		if material == null:
			return false
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
		if child is MirrorProjectionProjectile and not child.is_queued_for_deletion():
			return child
	return null


func _count_active_projection_projectiles(combat_manager: CombatManager) -> int:
	var count := 0
	for child in combat_manager.get_children():
		if child is MirrorProjectionProjectile and not child.is_queued_for_deletion():
			count += 1
	return count


func _find_pulse_laser(combat_manager: CombatManager) -> PulseLaserBeam:
	for child in combat_manager.get_children():
		if child is PulseLaserBeam:
			return child
	return null


func _count_active_pulse_lasers(combat_manager: CombatManager) -> int:
	var count := 0
	for child in combat_manager.get_children():
		if child is PulseLaserBeam and not child.is_queued_for_deletion():
			count += 1
	return count

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
