extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[PerformanceOptimization] running")
	_test_project_settings()
	_test_profile_resources()
	_test_world_texture_limits()
	await _test_production_terrain_batching()
	if _failures == 0:
		print("[PerformanceOptimization] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[PerformanceOptimization] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_project_settings() -> void:
	_expect(int(ProjectSettings.get_setting("rendering/scaling_3d/mode", 0)) == 2, "project uses FSR2 scaling")
	_expect(is_equal_approx(float(ProjectSettings.get_setting("rendering/scaling_3d/scale", 0.0)), 1.0), "project keeps native scale until runtime settings apply")
	_expect(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", -1)) == 0, "FSR2 replaces 3D MSAA")
	_expect(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", -1)) == 3, "directional soft shadows use medium filtering")
	var runtime_settings := RuntimeSettings.new()
	_expect(runtime_settings.depth_of_field_enabled, "depth of field remains enabled by default")
	_expect(runtime_settings.render_quality_preset == RuntimeSettings.RENDER_QUALITY_BALANCED, "balanced 2K render cap is the default quality")


func _test_profile_resources() -> void:
	for profile_path in [
		"res://resources/lighting/WhiteSoft.tres",
		"res://resources/lighting/WarmYellow.tres",
		"res://resources/lighting/CyanRedContrast.tres",
		"res://resources/lighting/NightSpotlight.tres",
	]:
		var profile := load(profile_path) as LightingProfile
		var environment := profile.environment_template if profile != null else null
		_expect(environment != null, "%s keeps its environment" % profile_path.get_file())
		_expect(environment != null and environment.ssao_enabled, "%s keeps SSAO" % profile_path.get_file())
		_expect(environment != null and environment.glow_enabled, "%s keeps Glow" % profile_path.get_file())
		_expect(environment != null and not environment.ssil_enabled, "%s disables SSIL" % profile_path.get_file())
	for mirror_path in [
		"res://resources/mirrors/CopyMirror.tres",
		"res://resources/mirrors/ReflectMirror.tres",
	]:
		var definition := load(mirror_path) as MirrorDefinition
		_expect(definition != null and definition.reflection_resolution == 256, "%s uses a 256px reflection" % mirror_path.get_file())
		_expect(definition != null and definition.reflection_preview_resolution == 128, "%s uses a 128px preview" % mirror_path.get_file())
		_expect(definition != null and definition.reflection_update_interval_frames == 4, "%s refreshes every four frames" % mirror_path.get_file())
		_expect(definition != null and definition.reflection_max_updates_per_frame == 1, "%s updates at most one mirror per frame" % mirror_path.get_file())


func _test_world_texture_limits() -> void:
	const SCRIPT_PATH := "res://tools/performance/apply_world_texture_limits.ps1"
	const MANIFEST_PATH := "res://tools/performance/world_texture_limit_manifest.json"
	_expect(FileAccess.file_exists(SCRIPT_PATH), "world texture limit batch script is retained")
	_expect(FileAccess.file_exists(MANIFEST_PATH), "world texture rollback manifest is retained")
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(typeof(parsed_manifest) == TYPE_DICTIONARY, "world texture rollback manifest is valid JSON")
	if typeof(parsed_manifest) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed_manifest
	var entries: Array = manifest.get("entries", [])
	_expect(int(manifest.get("target_limit", 0)) == 2048, "world textures use a 2048px import cap")
	_expect(int(manifest.get("minimum_source_dimension", 0)) == 4096, "batch scan starts at 4K source textures")
	_expect(entries.size() == 176, "rollback manifest records all 176 affected textures")
	var unlimited_before := 0
	var terrain_limited_before := 0
	var all_sources_exist := true
	var all_imports_limited := true
	var all_exclusions_respected := true
	for entry_value: Variant in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			all_sources_exist = false
			all_imports_limited = false
			continue
		var entry: Dictionary = entry_value
		var source_path := "res://%s" % str(entry.get("source_path", ""))
		var import_path := "res://%s" % str(entry.get("import_path", ""))
		var normalized_source := source_path.to_lower()
		all_sources_exist = all_sources_exist and FileAccess.file_exists(source_path)
		all_exclusions_respected = all_exclusions_respected and not normalized_source.begins_with("res://assets/ui/") and not normalized_source.begins_with("res://assets/png/")
		all_imports_limited = all_imports_limited and FileAccess.file_exists(import_path) and FileAccess.get_file_as_string(import_path).contains("process/size_limit=2048")
		if int(entry.get("previous_limit", -1)) == 0:
			unlimited_before += 1
		elif int(entry.get("previous_limit", -1)) == 2048:
			terrain_limited_before += 1
	_expect(unlimited_before == 156 and terrain_limited_before == 20, "manifest preserves the exact 156 unlimited and 20 pre-limited rollback baseline")
	_expect(all_sources_exist, "all limited source textures still exist")
	_expect(all_exclusions_respected, "UI and assets/png exclusions are respected")
	_expect(all_imports_limited, "all 176 texture import sidecars remain capped at 2048px")


func _test_production_terrain_batching() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(Level1), "Level1 configures for production batching verification")
	if main == null:
		return
	root.add_child(main)
	await process_frame
	await process_frame
	var terrain_root := main.terrain_renderer.get_node_or_null("TerrainModels")
	var batch_nodes := 0
	var legacy_flat_nodes := 0
	var coverage_by_asset: Dictionary = {}
	if terrain_root != null:
		for child in terrain_root.get_children():
			if child is MultiMeshInstance3D:
				batch_nodes += 1
				var asset_path := str(child.get_meta("terrain_asset_path", ""))
				var count := int(child.get_meta("terrain_batch_instance_count", 0))
				coverage_by_asset[asset_path] = maxi(int(coverage_by_asset.get(asset_path, 0)), count)
			elif child.name.begins_with("Terrain_"):
				legacy_flat_nodes += 1
	var covered_voxels := 0
	for count_value in coverage_by_asset.values():
		covered_voxels += int(count_value)
	var expected_voxels := Level1.grid_size.x * Level1.grid_size.y
	_expect(batch_nodes > 0, "production Level1 creates MultiMesh terrain batches")
	_expect(legacy_flat_nodes == 0, "production Level1 does not fall back to per-voxel flat nodes")
	_expect(covered_voxels == expected_voxels, "production batches cover all %d Level1 terrain voxels" % expected_voxels)
	_expect(terrain_root != null and terrain_root.get_child_count() < expected_voxels / 2, "production terrain node count is materially lower than one node per voxel")
	print("[PerformanceOptimization] Level1 terrain: %d batch nodes, %d covered voxels, %d legacy nodes" % [batch_nodes, covered_voxels, legacy_flat_nodes])
	_test_placement_preview_reuse(main)
	main.queue_free()
	await process_frame


func _test_placement_preview_reuse(main: MainController) -> void:
	_expect(main.building_manager.reuse_placement_preview_instances, "tower preview instance reuse is enabled by default")
	_expect(main.mirror_manager.reuse_placement_preview_instances, "mirror and projection preview reuse is enabled by default")
	var building_preview_id := 0
	var building_first_cell := Vector3i.ZERO
	var building_moved := false
	for cell in main.grid.enumerate_cells():
		if not main.building_manager.update_preview(cell, main.building_manager.arrow_tower):
			continue
		var preview := main.building_manager.get_preview_building()
		if preview == null:
			continue
		if building_preview_id == 0:
			building_preview_id = preview.get_instance_id()
			building_first_cell = cell
		elif cell != building_first_cell:
			building_moved = true
			_expect(preview.get_instance_id() == building_preview_id, "tower placement movement reuses one Building preview instance")
			_expect(preview.cell == cell, "reused tower preview updates its logical cell")
			break
	_expect(building_moved, "production Level1 exposes two valid tower preview cells")
	main.building_manager.clear_preview()

	var mirror_preview_id := 0
	var reflection_viewport_id := 0
	var first_edge_id := ""
	var mirror_moved := false
	for cell in main.grid.enumerate_cells():
		for edge_index in range(main.grid.edge_count()):
			if not main.mirror_manager.update_reflect_preview(cell, edge_index):
				continue
			var mirror_preview := main.mirror_manager.get_preview_mirror()
			if mirror_preview == null:
				continue
			var reflection_viewport := mirror_preview.get_reflection_viewport()
			if mirror_preview_id == 0:
				mirror_preview_id = mirror_preview.get_instance_id()
				reflection_viewport_id = reflection_viewport.get_instance_id() if reflection_viewport != null else 0
				first_edge_id = mirror_preview.edge_id
			elif mirror_preview.edge_id != first_edge_id:
				mirror_moved = true
				_expect(mirror_preview.get_instance_id() == mirror_preview_id, "mirror placement movement reuses one CopyMirror preview instance")
				_expect(
					reflection_viewport != null
					and reflection_viewport.get_instance_id() == reflection_viewport_id,
					"mirror placement movement retains its reflection SubViewport"
				)
				break
		if mirror_moved:
			break
	_expect(mirror_moved, "production Level1 exposes two valid mirror preview edges")
	main.mirror_manager.clear_preview()


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % description)
		return
	_failures += 1
	push_error("  FAIL: %s" % description)
