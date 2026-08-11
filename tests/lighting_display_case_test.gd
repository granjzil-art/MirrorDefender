extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const FormalLevel := preload("res://resources/levels/Level2.tres")
const CaseDefinition := preload("res://resources/lighting/AcrylicDisplayCase.tres")
const WhiteSoft := preload("res://resources/lighting/WhiteSoft.tres")
const WarmYellow := preload("res://resources/lighting/WarmYellow.tres")
const CyanRed := preload("res://resources/lighting/CyanRedContrast.tres")
const NightSpotlight := preload("res://resources/lighting/NightSpotlight.tres")
const RealisticTreeShadowDefinition := preload("res://resources/lighting/RealisticTreeShadow.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[LightingDisplayCase] running")
	_test_profile_resources()
	await _test_formal_level_runtime()
	await _test_dynamic_case_bounds()
	if _failures == 0:
		print("[LightingDisplayCase] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[LightingDisplayCase] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_profile_resources() -> void:
	var profiles: Array[LightingProfile] = [WhiteSoft, WarmYellow, CyanRed, NightSpotlight]
	var expected_ids := [&"white_soft", &"warm_yellow", &"cyan_red_contrast", &"night_spotlight"]
	for index in range(profiles.size()):
		var profile := profiles[index]
		_expect(profile != null, "profile %d loads" % index)
		_expect(profile.profile_id == expected_ids[index], "profile %d keeps stable id" % index)
		_expect(profile.validate_configuration().is_empty(), "profile %d validates" % index)
	_expect(RealisticTreeShadowDefinition != null, "realistic tree shadow resource loads")
	_expect(RealisticTreeShadowDefinition.validate_configuration().is_empty(), "realistic tree shadow resource validates")
	_expect(is_equal_approx(RealisticTreeShadowDefinition.target_height_cells, 30.0), "realistic tree comparison model uses the requested 30-cell height")
	_expect(
		RealisticTreeShadowDefinition.model_asset.scene.resource_path
		== "res://assets/greattree/realistic_tree_gltf/sketchfab_scene.tscn",
		"realistic tree shadow uses the requested authored scene"
	)


func _test_formal_level_runtime() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(FormalLevel), "Level2 configures as startup level")
	root.add_child(main)
	await process_frame
	await process_frame
	var controller := main.lighting_controller
	_expect(controller != null, "Level2 creates LightingController")
	_expect(controller.get_active_profile() == WhiteSoft, "Level2 starts with white soft profile")
	_expect(controller.get_generated_light_count() == 2, "white soft profile creates two lights")
	var display_case := controller.get_display_case()
	_expect(display_case != null, "Level2 creates acrylic display case")
	_expect(display_case.get_panel_count() == 5, "display case creates four walls and a top")
	_expect(display_case.get_projectile_reflection_surface_count() == 4, "only the four side panels reflect projectiles")
	_expect(display_case.get_edge_count() == 12, "display case creates twelve acrylic edges")
	_expect(display_case.get_base_mesh() != null, "display case creates wooden base")
	var level_size := display_case.get_case_size()
	_expect(level_size.x > float(FormalLevel.grid_size.x) and level_size.z > float(FormalLevel.grid_size.y), "Level2 grid expands the case with margin")
	_expect(level_size.y >= 4.5, "case height preserves minimum diorama clearance")
	_expect(_count_collision_nodes(display_case) == 0, "display case never blocks gameplay picking")
	var realistic_tree := controller.get_realistic_tree_shadow()
	_expect(realistic_tree != null and realistic_tree.get_model_root() != null, "Level2 creates the realistic tree comparison layer")
	_expect(not controller.is_foliage_shadow_enabled(), "Level2 starts with the procedural foliage shadow disabled")
	_expect(controller.is_realistic_tree_shadow_enabled(), "Level2 starts with the realistic tree enabled")
	_expect(realistic_tree.get_mesh_count() >= 3, "realistic tree keeps its authored crown and trunk meshes")
	_expect(realistic_tree.get_collision_node_count() == 0, "realistic tree comparison layer adds no gameplay collision")
	_expect(realistic_tree.get_leaf_shadow_caster_count() >= 1, "realistic tree creates an alpha-cutout leaf shadow caster")
	_expect(_has_valid_leaf_shadow_cutout(realistic_tree), "leaf shadows use alpha scissor so the canopy keeps visible light gaps")
	var realistic_bounds := realistic_tree.get_model_world_bounds()
	_expect(
		is_equal_approx(realistic_bounds.size.y, RealisticTreeShadowDefinition.target_height_cells * main.grid.cell_size),
		"realistic tree scales to the configured cell-relative height"
	)
	var active_profile_before_tree_toggle := controller.get_active_profile()
	var environment_before_tree_toggle: Environment = main.get_node("WorldEnvironment").environment
	var light_ids_before_tree_toggle := _collect_light_instance_ids(controller)
	controller.set_realistic_tree_shadow_enabled(false)
	_expect(not controller.is_realistic_tree_shadow_enabled(), "realistic tree comparison layer has an independent off switch")
	_expect(
		controller.get_active_profile() == active_profile_before_tree_toggle
		and main.get_node("WorldEnvironment").environment == environment_before_tree_toggle
		and _collect_light_instance_ids(controller) == light_ids_before_tree_toggle,
		"disabling the realistic tree leaves the current lighting profile untouched"
	)
	controller.set_realistic_tree_shadow_enabled(true)
	_expect(controller.is_realistic_tree_shadow_enabled(), "realistic tree comparison layer can be re-enabled")
	var realistic_button := main.lighting_test_panel.get_realistic_tree_shadow_button()
	_expect(
		realistic_button != null and realistic_button.button_pressed and realistic_button.text == "实树 开",
		"lighting panel exposes the realistic tree comparison switch"
	)
	_test_projectile_reflection(main, display_case)
	_expect(controller.get_reflection_probe() != null, "display case owns one reflection probe")
	_expect(controller.apply_profile_by_index(1, 0.0), "warm profile switches immediately")
	_expect(controller.get_active_profile() == WarmYellow, "warm profile becomes active")
	_expect(controller.get_generated_light_count() == 2, "warm profile creates two lights")
	_expect(controller.apply_profile_by_index(2, 0.0), "cyan-red profile switches immediately")
	_expect(controller.get_active_profile() == CyanRed, "cyan-red profile becomes active")
	_expect(controller.get_generated_light_count() == 3, "cyan-red profile creates three lights")
	_expect(controller.apply_profile_by_index(3, 0.0), "night spotlight profile switches immediately")
	_expect(controller.get_active_profile() == NightSpotlight, "night spotlight profile becomes active")
	_expect(controller.get_generated_light_count() == 3, "night spotlight profile creates three lights")
	var night_lights := _collect_lights(controller)
	var night_spot_count := 0
	var night_shadow_spot_count := 0
	var night_shadow_light_count := 0
	for light in night_lights:
		if light.shadow_enabled:
			night_shadow_light_count += 1
		if light is SpotLight3D:
			night_spot_count += 1
			if light.shadow_enabled:
				night_shadow_spot_count += 1
			_expect(light.light_energy <= 4.0, "elevated night spotlight energy remains below the tall-tree rig guard")
			_expect((light as SpotLight3D).spot_angle <= 35.0, "night spotlight remains focused instead of flooding the level")
	_expect(night_spot_count == 1, "night profile owns one focused spotlight")
	_expect(night_shadow_spot_count == 1, "night spotlight receives the existing foliage shadow layer")
	_expect(night_shadow_light_count == 1, "night profile restricts foliage shadows to the spotlight")
	_expect(
		NightSpotlight.environment_template.background_color.get_luminance() < 0.05,
		"night profile keeps a low-luminance navy background"
	)
	var night_button := main.lighting_test_panel.get_profile_button(3)
	_expect(
		main.lighting_test_panel.get_profile_button_count() == 4
		and night_button != null
		and night_button.text == "6 夜晚聚光",
		"lighting panel exposes the fourth night preset"
	)
	main.queue_free()
	await process_frame


func _test_dynamic_case_bounds() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(20, 9))
	var display_case := AcrylicDisplayCase.new()
	host.add_child(display_case)
	display_case.configure(grid, null, CaseDefinition)
	_expect(display_case.rebuild_for_level(), "case builds from grid without authored mesh dependency")
	var large_size := display_case.get_case_size()
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(4, 3))
	_expect(display_case.rebuild_for_level(), "case rebuilds after grid size changes")
	var small_size := display_case.get_case_size()
	_expect(small_size.x < large_size.x and small_size.z < large_size.z, "case dimensions follow smaller level")
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.25, Vector2i(3, 3))
	_expect(display_case.rebuild_for_level(), "case rebuilds for a square grid with different cell size")
	var resized_square := display_case.get_case_size()
	_expect(resized_square.x > 0.0 and resized_square.z > 0.0, "resized square case dimensions remain valid")
	_expect(display_case.get_projectile_reflection_surface_count() == 4, "reflection surfaces rebuild with square case bounds")
	host.queue_free()
	await process_frame


func _test_projectile_reflection(main: MainController, display_case: AcrylicDisplayCase) -> void:
	var bounds := display_case.get_content_bounds()
	var size := display_case.get_case_size()
	var center_x := bounds.position.x + bounds.size.x * 0.5
	var center_z := bounds.position.z + bounds.size.z * 0.5
	var middle_y := bounds.position.y + size.y * 0.5
	var back_z := center_z - size.z * 0.5
	var front_z := center_z + size.z * 0.5
	var left_x := center_x - size.x * 0.5
	var right_x := center_x + size.x * 0.5
	var inside := Vector3(center_x, middle_y, front_z - 0.25)
	var outside := Vector3(center_x, middle_y, front_z + 0.75)
	var direct_hit := display_case.trace_projectile_reflection(inside, outside)
	_expect(bool(direct_hit.hit), "a projectile leaving the cabinet hits the front panel")
	var front_normal: Vector3 = direct_hit.get("normal", Vector3.ZERO)
	_expect(front_normal.is_equal_approx(Vector3.FORWARD), "front panel normal faces inward")
	_expect(StringName(direct_hit.get("surface_id", StringName())) == &"front", "reflection identifies the finite front panel")
	_expect(direct_hit.get("reflector") == display_case and direct_hit.get("mirror") == null, "case reflection exposes a generic reflector without pretending to be a mirror")
	var other_side_cases: Array[Dictionary] = [
		{
			"id": &"back",
			"normal": Vector3.BACK,
			"start": Vector3(center_x, middle_y, back_z + 0.25),
			"end": Vector3(center_x, middle_y, back_z - 0.75),
		},
		{
			"id": &"left",
			"normal": Vector3.RIGHT,
			"start": Vector3(left_x + 0.25, middle_y, center_z),
			"end": Vector3(left_x - 0.75, middle_y, center_z),
		},
		{
			"id": &"right",
			"normal": Vector3.LEFT,
			"start": Vector3(right_x - 0.25, middle_y, center_z),
			"end": Vector3(right_x + 0.75, middle_y, center_z),
		},
	]
	for side_case in other_side_cases:
		var side_start: Vector3 = side_case.get("start", Vector3.ZERO)
		var side_end: Vector3 = side_case.get("end", Vector3.ZERO)
		var side_hit := display_case.trace_projectile_reflection(side_start, side_end)
		var side_normal: Vector3 = side_hit.get("normal", Vector3.ZERO)
		_expect(
			bool(side_hit.hit)
			and StringName(side_hit.get("surface_id", StringName())) == side_case.get("id", StringName())
			and side_normal.is_equal_approx(side_case.get("normal", Vector3.ZERO)),
			"%s panel uses its finite inward reflection face" % String(side_case.get("id", StringName()))
		)
	var corner_hit := display_case.trace_projectile_reflection(
		Vector3(right_x - 0.25, middle_y, front_z - 0.25),
		Vector3(right_x + 0.75, middle_y, front_z + 0.75)
	)
	var corner_normal: Vector3 = corner_hit.get("normal", Vector3.ZERO)
	_expect(
		String(corner_hit.get("surface_id", "")) == "front+right"
		and corner_normal.is_equal_approx((Vector3.FORWARD + Vector3.LEFT).normalized()),
		"an exact cabinet-corner hit combines both inward normals"
	)
	var backface_hit := display_case.trace_projectile_reflection(outside, inside)
	_expect(not bool(backface_hit.hit), "a projectile entering from outside passes through the panel back face")
	var above_top := bounds.position.y + size.y + 0.25
	var above_hit := display_case.trace_projectile_reflection(
		Vector3(center_x, above_top, front_z - 0.25),
		Vector3(center_x, above_top, front_z + 0.75)
	)
	_expect(not bool(above_hit.hit), "finite side panels do not reflect above their visual height")
	var top_hit := display_case.trace_projectile_reflection(
		Vector3(center_x, bounds.position.y + size.y - 0.25, center_z),
		Vector3(center_x, bounds.position.y + size.y + 0.75, center_z)
	)
	_expect(not bool(top_hit.hit), "the acrylic top remains presentation-only")
	_expect(main.mirror_manager.get_projectile_reflection_provider_count() == 1, "Main registers the display case in the shared reflection query")
	var aggregate_hit := main.mirror_manager.trace_projectile_reflection(inside, outside)
	_expect(bool(aggregate_hit.hit) and aggregate_hit.get("reflector") == display_case, "MirrorManager returns the acrylic panel when it is the nearest reflector")
	var pulse_colors: Array[Color] = [Color.RED, Color.ORANGE]
	var pulse := main.combat_manager.spawn_pulse_laser(
		inside,
		(outside - inside).normalized(),
		0.0,
		1.0,
		0.1,
		2.0,
		0.01,
		0.01,
		0.01,
		pulse_colors,
		1
	)
	var pulse_segments := pulse.debug_get_segments() if pulse != null else []
	_expect(
		pulse_segments.size() == 2
		and (pulse_segments[1].get("color") as Color).is_equal_approx(Color.ORANGE),
		"pulse laser creates an independent orange segment after reflecting from an acrylic side panel"
	)

	var target := CombatTarget.new()
	main.combat_manager.add_child(target)
	target.configure_debug_target(outside, 100.0, 0.0, 0.0)
	var projectile := Projectile.new()
	main.combat_manager.add_child(projectile)
	var incoming_direction := (target.get_target_position() - inside).normalized()
	var expected_reflected_direction := (
		incoming_direction - 2.0 * incoming_direction.dot(Vector3.FORWARD) * Vector3.FORWARD
	).normalized()
	projectile.configure(
		inside,
		target,
		100.0,
		10.0,
		1.0,
		0.2,
		0.05,
		Color.WHITE,
		null,
		null,
		Callable(main.combat_manager, "get_targets"),
		Callable(main.mirror_manager, "trace_projectile_reflection")
	)
	projectile.set_process(false)
	projectile._process(1.0)
	_expect(projectile.has_reflected(), "a real tower projectile reflects from the acrylic panel")
	_expect(projectile.get_travel_direction().is_equal_approx(expected_reflected_direction), "the acrylic reflection preserves the mirror equal-angle rule")
	_expect(projectile.get_distance_traveled() <= 1.0001, "acrylic reflection shares the projectile's original distance budget")

	var projection_projectile := MirrorProjectionProjectile.new()
	main.combat_manager.add_child(projection_projectile)
	projection_projectile.configure(
		main.combat_manager,
		null,
		inside,
		outside,
		100.0,
		10.0,
		0.2,
		0.05,
		Color.CYAN,
		null,
		1.0,
		Callable(main.mirror_manager, "trace_projectile_reflection")
	)
	projection_projectile.set_process(false)
	projection_projectile._process(1.0)
	_expect(projection_projectile.has_reflected(), "a copy-tower projectile uses the same acrylic reflection surfaces")


func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_nodes(child)
	return count


func _collect_lights(node: Node) -> Array[Light3D]:
	var lights: Array[Light3D] = []
	if node is Light3D:
		lights.append(node as Light3D)
	for child in node.get_children():
		lights.append_array(_collect_lights(child))
	return lights


func _collect_light_instance_ids(node: Node) -> Array[int]:
	var ids: Array[int] = []
	if node is Light3D:
		ids.append(node.get_instance_id())
	for child in node.get_children():
		ids.append_array(_collect_light_instance_ids(child))
	ids.sort()
	return ids


func _has_valid_leaf_shadow_cutout(node: Node) -> bool:
	if node is MeshInstance3D and node.has_meta(&"realistic_tree_leaf_shadow_caster"):
		var caster := node as MeshInstance3D
		var material := caster.material_override as ShaderMaterial
		return (
			caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			and material != null
			and material.shader != null
			and is_equal_approx(float(material.get_shader_parameter("shadow_strength")), RealisticTreeShadowDefinition.leaf_shadow_strength)
			and is_equal_approx(float(material.get_shader_parameter("alpha_scissor_threshold")), RealisticTreeShadowDefinition.leaf_alpha_scissor_threshold)
			and is_equal_approx(float(material.get_shader_parameter("gap_threshold")), RealisticTreeShadowDefinition.leaf_shadow_gap_threshold)
		)
	for child in node.get_children():
		if _has_valid_leaf_shadow_cutout(child):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
