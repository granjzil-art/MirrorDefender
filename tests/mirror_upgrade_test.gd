extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

class LaserSource:
	extends Node

	func get_laser_slow_multiplier() -> float:
		return 1.0

	func get_laser_slow_duration() -> float:
		return 0.0


var _failures: int = 0
var _checks: int = 0
var _pulse_reflection_calls: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[MirrorUpgrade] running")
	_test_legacy_initial_level_migration()
	_test_configured_level_rules()
	_test_copy_chain_accumulation()
	_test_actual_projectile_reflection_state()
	_test_uniform_laser_damage()
	var fixture := await _make_fixture()
	await _test_upgrade_economy_ui_and_persistence(fixture)
	(fixture.host as Node).queue_free()
	await process_frame
	if _failures == 0:
		print("[MirrorUpgrade] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MirrorUpgrade] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_legacy_initial_level_migration() -> void:
	var legacy := MirrorPlacementData.new()
	legacy.level = 0
	_expect(legacy.validate_configuration().is_empty(), "legacy mirror without a serialized level validates as level one")
	_expect(legacy.level == 1, "legacy mirror level is migrated before saving or loading")
	legacy.level = 4
	_expect(not legacy.validate_configuration().is_empty(), "non-legacy mirror levels above the cap remain invalid")


func _test_configured_level_rules() -> void:
	var copy := TestDefinitionFactory.make_copy_mirror_definition()
	var reflect := TestDefinitionFactory.make_reflect_mirror_definition()
	_expect(copy.upgrade_costs == [50.0, 50.0], "copy mirror level-two and level-three upgrades both cost 50")
	_expect(reflect.upgrade_costs == [50.0, 50.0], "reflect mirror level-two and level-three upgrades both cost 50")
	_expect(
		is_equal_approx(copy.get_damage_multiplier(1), 1.0)
		and is_equal_approx(copy.get_damage_multiplier(2), 1.1)
		and is_equal_approx(copy.get_damage_multiplier(3), 1.2),
		"copy mirror exposes the configured 1.0/1.1/1.2 damage levels"
	)
	_expect(
		copy.get_penetration_bonus(1) == 0
		and copy.get_penetration_bonus(2) == 1
		and copy.get_penetration_bonus(3) == 2,
		"copy mirror exposes the configured 0/1/2 penetration levels"
	)
	_expect(
		copy.get_projection_alpha(1) < copy.get_projection_alpha(2)
		and copy.get_projection_alpha(2) < copy.get_projection_alpha(3)
		and copy.get_projection_alpha(3) <= 0.75,
		"copy upgrades reduce transparency while level three remains visibly virtual"
	)
	_expect(
		is_equal_approx(reflect.get_damage_multiplier(1), 1.1)
		and is_equal_approx(reflect.get_damage_multiplier(2), 1.2)
		and is_equal_approx(reflect.get_damage_multiplier(3), 1.2),
		"reflect mirror exposes the configured 1.1/1.2/1.2 damage levels"
	)
	_expect(
		reflect.get_penetration_bonus(1) == 1
		and reflect.get_penetration_bonus(2) == 2
		and reflect.get_penetration_bonus(3) == 4,
		"reflect mirror exposes the configured 1/2/4 penetration levels"
	)


func _test_copy_chain_accumulation() -> void:
	var definition := TestDefinitionFactory.make_copy_mirror_definition()
	var root_payload := MirrorCopyPayload.new()
	root_payload.stable_key = "source"
	var first := root_payload.copy_through(
		"copy-a",
		Vector3i(1, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(2),
		definition.get_penetration_bonus(2)
	)
	var second := first.copy_through(
		"copy-b",
		Vector3i(2, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(2),
		definition.get_penetration_bonus(2)
	)
	_expect(is_equal_approx(first.damage_multiplier, 1.1), "one level-two copy has 1.1 damage")
	_expect(
		is_equal_approx(second.damage_multiplier, 1.21),
		"two level-two copies multiply into 1.21 damage"
	)
	_expect(second.penetration_bonus == 2, "two level-two copies add into +2 penetration")
	var mixed := first.copy_through(
		"copy-c",
		Vector3i(3, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(3),
		definition.get_penetration_bonus(3)
	)
	_expect(
		is_equal_approx(mixed.damage_multiplier, 1.32) and mixed.penetration_bonus == 3,
		"level-two then level-three copy accumulates 1.32 damage and +3 penetration"
	)


func _test_actual_projectile_reflection_state() -> void:
	var projectile := Projectile.new()
	projectile._damage = 10.0
	projectile._penetration_limit = 2
	projectile._penetration_value = 1
	projectile._apply_reflection_modifiers({"damage_multiplier": 1.1, "penetration_bonus": 1})
	_expect(
		is_equal_approx(projectile.debug_get_damage(), 11.0)
		and projectile.debug_get_remaining_penetration() == 2,
		"level-one reflection modifies the projectile after its already-consumed penetration"
	)
	projectile._apply_reflection_modifiers({"damage_multiplier": 1.2, "penetration_bonus": 2})
	_expect(
		is_equal_approx(projectile.debug_get_damage(), 13.2)
		and projectile.debug_get_remaining_penetration() == 4,
		"a later reflection multiplies current damage and adds to current remaining penetration"
	)
	projectile.free()


func _test_uniform_laser_damage() -> void:
	var source := LaserSource.new()
	var first := CombatTarget.new()
	var second := CombatTarget.new()
	root.add_child(source)
	root.add_child(first)
	root.add_child(second)
	first.configure_debug_target(Vector3.ZERO, 100.0, 0.0, 0.0)
	second.configure_debug_target(Vector3.RIGHT, 100.0, 0.0, 0.0)
	var path := {
		"damage_multiplier": 1.32,
		"reflections": [],
		"hits": [
			{"target": first, "segment_index": 0},
			{"target": second, "segment_index": 2},
		],
	}
	LaserAttackStrategy.apply_continuous_hits(source, path, 10.0, 1.0, false)
	_expect(
		is_equal_approx(first.current_hp, 86.8) and is_equal_approx(second.current_hp, 86.8),
		"continuous laser applies one final accumulated multiplier to every segment"
	)
	first.free()
	second.free()
	source.free()
	var pulse := PulseLaserBeam.new()
	root.add_child(pulse)
	_pulse_reflection_calls = 0
	var configured := pulse.configure(
		null,
		null,
		Vector3.ZERO,
		Vector3.RIGHT,
		10.0,
		4.0,
		0.1,
		2.0,
		0.1,
		0.1,
		0.1,
		[Color.WHITE],
		2,
		Callable(self, "_trace_two_pulse_reflections")
	)
	_expect(configured and pulse.debug_get_segments().size() == 3, "two pulse-laser reflections create three segments")
	_expect(
		is_equal_approx(pulse.debug_get_damage(), 13.2),
		"all pulse-laser segments share the same twice-reflected final damage"
	)
	pulse.free()


func _trace_two_pulse_reflections(start: Vector3, end: Vector3) -> Dictionary:
	if _pulse_reflection_calls >= 2:
		return {"hit": false}
	var multipliers := [1.1, 1.2]
	var bonuses := [1, 2]
	var index := _pulse_reflection_calls
	_pulse_reflection_calls += 1
	var distance := start.distance_to(end) * 0.25
	return {
		"hit": true,
		"position": start.lerp(end, 0.25),
		"normal": Vector3.RIGHT,
		"distance": distance,
		"epsilon": 0.0001,
		"damage_multiplier": multipliers[index],
		"penetration_bonus": bonuses[index],
	}


func _test_upgrade_economy_ui_and_persistence(fixture: Dictionary) -> void:
	var manager: MirrorManager = fixture.mirror
	var resource: ResourceManager = fixture.resource
	var grid: GridManager = fixture.grid
	manager.copy_mirror_definition.inspection_display = InspectionDisplayConfigScript.new()
	manager.copy_mirror_definition.inspection_display.display_name = "测试复制镜"
	manager.copy_mirror_definition.inspection_display.function_description = "复制镜基础说明。"
	manager.copy_mirror_definition.upgrade_description = "升级说明。"
	var copy_from := Vector3i(1, 1, 0)
	var copy_edge := grid.find_edge_index(copy_from, Vector3i(2, 1, 0))
	var copy := manager.place_copy_mirror(copy_from, copy_edge, true)
	_expect(copy != null and copy.level == 1 and is_equal_approx(resource.main_resource, 260.0), "copy mirror starts at level one and spends construction cost")
	var panel := MirrorActionPanel.new()
	(fixture.host as Node).add_child(panel)
	await process_frame
	panel.configure(manager, null)
	var info_button := panel.get_node_or_null("InfoButton") as Button
	var upgrade_button := panel.find_child("UpgradeButton", true, false) as Button
	var sell_button := panel.get_node_or_null("SellButton") as Button
	var upgrade_cost_label := panel.get_node_or_null("UpgradeCostLabel") as Label
	var sell_refund_label := panel.get_node_or_null("SellRefundLabel") as Label
	_expect(
		info_button != null and upgrade_button != null and sell_button != null,
		"selected mirror exposes explanation, upgrade, and sell actions"
	)
	_expect(
		panel.get_node_or_null("FlipButton") == null and panel.get_node_or_null("DeleteButton") == null,
		"the old flip and text demolition actions are absent from the mirror panel"
	)
	_expect(
		info_button.position.x < upgrade_button.position.x
		and upgrade_button.position.y == info_button.position.y
		and sell_button.position.y < info_button.position.y
		and sell_button.position.y < upgrade_button.position.y,
		"mirror sell action is above the left-info/right-upgrade actions"
	)
	_expect(
		info_button.size == upgrade_button.size and upgrade_button.size == sell_button.size,
		"all three mirror action icons have the same size"
	)
	_expect(
		upgrade_cost_label != null and upgrade_cost_label.visible and upgrade_cost_label.text == "-50"
		and sell_refund_label != null and sell_refund_label.visible and sell_refund_label.text == "+40",
		"mirror upgrade and sell numbers occupy the building-style economy labels"
	)
	_expect(
		upgrade_cost_label.position.y < upgrade_button.position.y
		and sell_refund_label.position.y < sell_button.position.y
		and upgrade_cost_label.get_theme_color("font_color").is_equal_approx(
			sell_refund_label.get_theme_color("font_color")
		),
		"mirror economy numbers share the gold color and render above their icons"
	)
	panel._on_info_pressed()
	await process_frame
	var info_page := panel.get_node_or_null("InfoPage") as PanelContainer
	var info_title := panel.find_child("InfoTitle", true, false) as Label
	var info_description := panel.find_child("InfoDescription", true, false) as RichTextLabel
	_expect(
		info_page != null and info_page.visible
		and info_title != null and info_title.text == "测试复制镜"
		and info_description != null
		and info_description.text == manager.copy_mirror_definition.get_formatted_inspection_description_bbcode()
		and info_description.get_parsed_text()
		== manager.copy_mirror_definition.get_formatted_inspection_description(),
		"mirror explanation action uses the same compact rich text as card hover"
	)
	_expect(
		info_description.get_parsed_text().split("\n").size() == 2
		and info_description.get_parsed_text().contains("基础描述：")
		and info_description.get_parsed_text().contains("升级：")
		and not info_description.get_parsed_text().contains("1级："),
		"two-level mirror descriptions use only the semantic base and upgrade rows"
	)
	_expect(
		info_page.size.y < 300.0
		and is_equal_approx(info_page.position.y + info_page.size.y, -150.0),
		"short mirror text shrinks the page while preserving its action-side bottom edge"
	)
	_expect(manager.upgrade_mirror(copy), "mirror manager accepts the selected copy upgrade")
	_expect(
		copy.level == 2
		and is_equal_approx(resource.main_resource, 210.0)
		and is_equal_approx(copy.get_refund_amount(), 90.0),
		"first copy upgrade spends and records 50 resources"
	)
	var pair := grid.get_mirror_cell_pair(copy.from_cell, copy.edge_index, copy.active_from_side, 1)
	var source_payload := MirrorCopyPayload.new()
	source_payload.stable_key = "runtime-source"
	source_payload.projected_cell = pair.source_cell
	source_payload.root_source = RefCounted.new()
	var runtime_group: Array[MirrorCopyPayload] = manager._build_projection_group(
		copy,
		{pair.source_cell: [source_payload]}
	)
	_expect(
		runtime_group.size() == 1
		and is_equal_approx(runtime_group[0].damage_multiplier, 1.1)
		and runtime_group[0].penetration_bonus == 1,
		"runtime copy graph reads the upgraded mirror's damage and penetration"
	)
	_expect(
		runtime_group.size() == 1
		and is_equal_approx(
			runtime_group[0].projection_alpha,
			manager.copy_mirror_definition.get_projection_alpha(2)
		),
		"level-two mirror writes its configured opacity into the generated virtual image"
	)
	_expect(manager.upgrade_mirror(copy), "copy mirror upgrades from level two to level three")
	_expect(
		copy.level == 3
		and is_equal_approx(resource.main_resource, 160.0)
		and is_equal_approx(copy.get_refund_amount(), 140.0),
		"second copy upgrade also spends 50 and joins the demolition refund"
	)
	var level_three_group: Array[MirrorCopyPayload] = manager._build_projection_group(
		copy,
		{pair.source_cell: [source_payload]}
	)
	_expect(
		level_three_group.size() == 1
		and level_three_group[0].projection_alpha > runtime_group[0].projection_alpha
		and level_three_group[0].projection_alpha <= 0.75,
		"level-three virtual image is less transparent than level two but remains translucent"
	)
	_expect(
		not manager.upgrade_mirror(copy)
		and not upgrade_button.visible
		and not upgrade_cost_label.visible
		and sell_refund_label.text == "+140",
		"maximum-level mirror hides upgrade UI and keeps its full sell refund visible"
	)
	_expect(manager.remove_mirror(copy) and is_equal_approx(resource.main_resource, 300.0), "level-three copy demolition refunds construction plus both upgrades")
	var reflect_from := Vector3i(2, 2, 0)
	var reflect_edge := grid.find_edge_index(reflect_from, Vector3i(3, 2, 0))
	var reflect := manager.place_reflect_mirror(reflect_from, reflect_edge, true)
	_expect(
		reflect != null
		and is_equal_approx(reflect.get_damage_multiplier(), 1.1)
		and reflect.get_penetration_bonus() == 1,
		"new reflect mirror immediately uses its level-one reflection modifiers"
	)
	var reflect_plane := reflect.global_position + Vector3.UP
	var reflect_normal := reflect.get_active_normal()
	var level_one_hit := manager.trace_projectile_reflection(
		reflect_plane + reflect_normal,
		reflect_plane - reflect_normal
	)
	_expect(
		bool(level_one_hit.get("hit", false))
		and is_equal_approx(float(level_one_hit.get("damage_multiplier", 0.0)), 1.1)
		and int(level_one_hit.get("penetration_bonus", 0)) == 1,
		"actual level-one reflection hit carries 1.1 damage and +1 penetration"
	)
	_expect(manager.upgrade_mirror(reflect) and manager.upgrade_mirror(reflect), "reflect mirror reaches level three through two paid upgrades")
	_expect(
		reflect.level == 3
		and is_equal_approx(reflect.get_damage_multiplier(), 1.2)
		and reflect.get_penetration_bonus() == 4,
		"level-three reflect mirror exposes 1.2 damage and +4 penetration"
	)
	var level_three_hit := manager.trace_projectile_reflection(
		reflect_plane + reflect_normal,
		reflect_plane - reflect_normal
	)
	_expect(
		bool(level_three_hit.get("hit", false))
		and is_equal_approx(float(level_three_hit.get("damage_multiplier", 0.0)), 1.2)
		and int(level_three_hit.get("penetration_bonus", 0)) == 4,
		"actual level-three reflection hit carries 1.2 damage and +4 penetration"
	)
	var placements := manager.export_initial_placements()
	_expect(placements.size() == 1 and placements[0].level == 3, "initial-layout export persists mirror level")
	_expect(manager.remove_mirror(reflect) and is_equal_approx(resource.main_resource, 300.0), "reflect demolition refunds construction plus both upgrades")
	_expect(manager.load_initial_placements(placements).is_empty(), "authored level-three mirror reloads without spending resources")
	var loaded := manager.get_mirrors()[0] if not manager.get_mirrors().is_empty() else null
	var authored_refund := manager.reflect_mirror_definition.get_cumulative_cost(3)
	_expect(
		loaded != null
		and loaded.level == 3
		and is_equal_approx(loaded.get_refund_amount(), authored_refund),
		"reloaded authored mirror keeps level three and its full configured refund"
	)
	_expect(
		manager.remove_mirror(loaded)
		and is_equal_approx(resource.main_resource, 300.0 + authored_refund),
		"demolishing the reloaded authored mirror grants construction plus both upgrade costs"
	)
	panel.queue_free()


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
	level.initial_resource = 300.0
	level.building_cap = 20
	level.copy_mirror_cap = 4
	level.reflect_mirror_cap = 4
	level.base_cell = Vector3i(3, 0, 0)
	resource.apply_level_configuration(level)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile)
	_expect(loader.load_level(level, "memory://mirror-upgrade"), "mirror upgrade fixture level loads")
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
