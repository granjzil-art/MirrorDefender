extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const FormalLevel := preload("res://resources/levels/Level2.tres")
const DefaultDefinition := preload("res://resources/lighting/FoliageShadowDefault.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[FoliageShadow] running")
	_test_definition()
	await _test_standalone_controller()
	await _test_formal_level_integration()
	if _failures == 0:
		print("[FoliageShadow] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[FoliageShadow] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_definition() -> void:
	_expect(DefaultDefinition != null, "default foliage shadow resource loads")
	_expect(DefaultDefinition.validate_configuration().is_empty(), "default foliage shadow resource validates")
	var in_memory_default := FoliageShadowDefinition.new()
	_expect(in_memory_default.validate_configuration().is_empty(), "script defaults remain independently valid")
	_expect(DefaultDefinition.cluster_count >= 1 and DefaultDefinition.cluster_count <= 32, "editable cluster budget stays inside the supported contract")
	_expect(DefaultDefinition.shadow_strength >= 0.0 and DefaultDefinition.shadow_strength <= 2.0, "editable shadow strength stays inside the expanded supported contract")
	var high_strength_definition := FoliageShadowDefinition.new()
	high_strength_definition.shadow_strength = 2.0
	_expect(high_strength_definition.validate_configuration().is_empty(), "procedural foliage accepts the expanded 2.0 shadow strength")


func _test_standalone_controller() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var definition := DefaultDefinition.duplicate(true) as FoliageShadowDefinition
	var controller := FoliageShadowController.new()
	host.add_child(controller)
	_expect(controller.configure(definition), "standalone foliage shadow controller configures")
	var first_bounds := AABB(Vector3(-5.0, -1.0, -3.0), Vector3(10.0, 4.0, 6.0))
	_expect(controller.rebuild(first_bounds, 1.0), "procedural foliage shadow rebuilds from level bounds")
	var caster := controller.get_caster()
	_expect(caster != null and caster.mesh is PlaneMesh, "shadow system creates one procedural plane")
	_expect(
		caster.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"procedural plane is invisible outside the shadow pass"
	)
	_expect(caster.visible, "foliage shadow starts enabled")
	_expect(_count_collision_nodes(controller) == 0, "foliage shadow creates no picking or gameplay collision")
	var material := caster.material_override as StandardMaterial3D
	_expect(
		material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
		"foliage mask uses fractional alpha-hash shadow coverage"
	)
	var texture := controller.get_pattern_texture()
	_expect(
		texture != null
		and texture.get_width() == definition.texture_resolution
		and texture.get_height() == definition.texture_resolution,
		"program-generated shadow texture uses the configured resolution"
	)
	var statistics := controller.get_pattern_statistics()
	var coverage_ratio: float = float(statistics.get("coverage_ratio", 1.0))
	var mean_opacity: float = float(statistics.get("mean_opacity", 1.0))
	_expect(coverage_ratio > 0.0 and coverage_ratio <= 1.0, "leaf silhouettes produce valid non-empty normalized coverage")
	_expect(mean_opacity > 0.0 and mean_opacity <= definition.shadow_strength, "mean procedural opacity respects the editable strength ceiling")
	var offset_before := material.uv1_offset
	_expect(controller.advance_motion(2.0), "enabled foliage shadow advances wind motion")
	_expect(not material.uv1_offset.is_equal_approx(offset_before), "wind motion changes the shadow mask position")
	controller.set_effect_enabled(false)
	var disabled_offset := material.uv1_offset
	_expect(not controller.is_effect_enabled() and not caster.visible, "independent switch fully hides the shadow caster")
	_expect(not controller.advance_motion(2.0), "disabled foliage shadow stops motion work")
	_expect(material.uv1_offset.is_equal_approx(disabled_offset), "disabled shadow leaves its material state unchanged")
	controller.set_effect_enabled(true)
	_expect(controller.is_effect_enabled() and caster.visible, "foliage shadow can be re-enabled independently")
	controller.set_effect_enabled(false)
	controller.feature_enabled = true
	controller.set_effect_enabled(true)
	_expect(controller.is_effect_enabled(), "an initially disabled runtime state does not permanently lock the feature")
	var first_size := (caster.mesh as PlaneMesh).size
	_expect(
		controller.rebuild(AABB(Vector3.ZERO, Vector3(4.0, 2.0, 3.0)), 1.5),
		"shadow plane rebuilds for a differently sized level"
	)
	var second_size := (caster.mesh as PlaneMesh).size
	_expect(second_size.x < first_size.x and second_size.y < first_size.y, "shadow plane follows dynamic level bounds")
	host.queue_free()
	await process_frame


func _test_formal_level_integration() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(FormalLevel), "Level2 configures for foliage shadow testing")
	root.add_child(main)
	await process_frame
	await process_frame
	var lighting := main.lighting_controller
	var foliage := lighting.get_foliage_shadow()
	_expect(foliage != null and foliage.get_caster() != null, "Main creates the independent foliage shadow layer")
	_expect(not lighting.is_foliage_shadow_enabled(), "Level2 starts with procedural foliage shadow disabled for real-tree comparison")
	_expect(lighting.is_realistic_tree_shadow_enabled(), "Level2 starts with the realistic tree comparison layer enabled")
	var profile_before := lighting.get_active_profile()
	var light_count_before := lighting.get_generated_light_count()
	var light_instance_ids_before := _collect_light_instance_ids(lighting)
	var environment_before: Environment = main.get_node("WorldEnvironment").environment
	lighting.set_foliage_shadow_enabled(false)
	_expect(not lighting.is_foliage_shadow_enabled(), "runtime switch disables only the foliage shadow")
	_expect(lighting.get_active_profile() == profile_before, "disabling foliage shadow preserves the active lighting profile")
	_expect(lighting.get_generated_light_count() == light_count_before, "disabling foliage shadow preserves every generated light")
	_expect(main.get_node("WorldEnvironment").environment == environment_before, "disabling foliage shadow preserves the Environment resource")
	_expect(
		_collect_light_instance_ids(lighting) == light_instance_ids_before,
		"disabling foliage shadow leaves the active light nodes untouched"
	)
	for profile_index in range(lighting.get_profiles().size()):
		_expect(
			lighting.apply_profile_by_index(profile_index, 0.0),
			"lighting profile %d switches while foliage shadow is disabled" % profile_index
		)
		_expect(
			_count_shadow_lights(lighting) > 0,
			"lighting profile %d retains a shadow-enabled light for the optional layer" % profile_index
		)
		_expect(
			not lighting.is_foliage_shadow_enabled(),
			"lighting profile %d does not override the independent shadow switch" % profile_index
		)
	lighting.set_foliage_shadow_enabled(true)
	_expect(lighting.is_foliage_shadow_enabled(), "foliage shadow re-enables after an independent profile switch")
	var button := main.lighting_test_panel.get_foliage_shadow_button()
	_expect(button != null and button.button_pressed and button.text == "树影 开", "lighting panel exposes the dedicated shadow toggle")
	main.queue_free()
	await process_frame
	var disabled_main := MainScene.instantiate() as MainController
	disabled_main.foliage_shadow_enabled = false
	_expect(
		disabled_main.configure_startup_level(FormalLevel),
		"Level2 accepts an initially disabled foliage-shadow state"
	)
	root.add_child(disabled_main)
	await process_frame
	await process_frame
	_expect(
		not disabled_main.lighting_controller.is_foliage_shadow_enabled(),
		"initially disabled foliage shadows stay off after level load"
	)
	disabled_main.lighting_controller.set_foliage_shadow_enabled(true)
	_expect(
		disabled_main.lighting_controller.is_foliage_shadow_enabled(),
		"the runtime switch can enable a shadow layer that started disabled"
	)
	disabled_main.queue_free()
	await process_frame


func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_nodes(child)
	return count


func _collect_light_instance_ids(node: Node) -> Array[int]:
	var ids: Array[int] = []
	if node is Light3D:
		ids.append(node.get_instance_id())
	for child in node.get_children():
		ids.append_array(_collect_light_instance_ids(child))
	ids.sort()
	return ids


func _count_shadow_lights(node: Node) -> int:
	var count := 1 if node is Light3D and (node as Light3D).shadow_enabled else 0
	for child in node.get_children():
		count += _count_shadow_lights(child)
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
