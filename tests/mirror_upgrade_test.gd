extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

class LaserSource:
	extends Node

	func get_laser_slow_multiplier() -> float:
		return 1.0

	func get_laser_slow_duration() -> float:
		return 0.0


class TowerKindSource:
	extends RefCounted

	var copy_kind: StringName = &""

	func _init(value: StringName) -> void:
		copy_kind = value

	func get_copy_kind() -> StringName:
		return copy_kind


class BurstCapture:
	extends RefCounted

	var captured_count: int = 0

	func spawn_radial_attack_copies(
		projectile_count: int,
		_damage_multiplier: float,
		_distance_multiplier: float,
		_penetration_count: int,
		_attack_effects: AttackEffectPayload,
		_state_overrides: Dictionary
	) -> Array[Node]:
		captured_count = projectile_count
		return []


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
	_test_arrow_mirror_effects()
	_test_reflection_path_state()
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
	_expect(legacy.validate_configuration().is_empty() and legacy.level == 2, "legacy mirror levels above the new cap migrate to level two")


func _test_configured_level_rules() -> void:
	var copy := TestDefinitionFactory.make_copy_mirror_definition()
	var reflect := TestDefinitionFactory.make_reflect_mirror_definition()
	_expect(copy.get_max_level() == 2 and copy.upgrade_costs == [50.0], "copy mirror has one level-two upgrade")
	_expect(reflect.get_max_level() == 2 and reflect.upgrade_costs == [50.0], "reflect mirror has one level-two upgrade")
	_expect(
		is_equal_approx(copy.get_damage_multiplier(1), 1.0)
		and is_equal_approx(copy.get_damage_multiplier(2), 1.1),
		"copy mirror exposes exactly two configured damage levels"
	)
	_expect(
		copy.get_penetration_bonus(1) == 0
		and copy.get_penetration_bonus(2) == 1,
		"copy mirror exposes exactly two configured penetration levels"
	)
	var copy_effect_ids: Array[StringName] = []
	for copy_effect in copy.get_attack_effects(2):
		copy_effect_ids.append(copy_effect.get_effect_id())
	_expect(
		copy.get_attack_effects(1).is_empty()
		and copy_effect_ids.size() == 4
		and copy_effect_ids.has(&"burst_arrow")
		and copy_effect_ids.has(&"burning_missile")
		and copy_effect_ids.has(&"pulse_laser_overdrive")
		and copy_effect_ids.has(&"ice_copy_burst"),
		"copy mirror exposes all four tower-specific effects only at level two"
	)
	_expect(
		copy.get_projection_alpha(1) < copy.get_projection_alpha(2)
		and copy.get_projection_alpha(2) <= 0.75,
		"copy level two reduces transparency while remaining visibly virtual"
	)
	var depth_one_alpha := copy.get_projection_alpha_for_depth(1, 1)
	var depth_two_alpha := copy.get_projection_alpha_for_depth(1, 2, depth_one_alpha)
	var depth_three_alpha := copy.get_projection_alpha_for_depth(1, 3, depth_two_alpha)
	_expect(
		depth_one_alpha > depth_two_alpha
		and depth_two_alpha > depth_three_alpha
		and depth_three_alpha >= copy.recursive_projection_min_alpha,
		"recursive copy opacity decreases monotonically with chain depth"
	)
	_expect(
		copy.get_projection_alpha_for_depth(2, 2, depth_one_alpha) < depth_one_alpha,
		"a deeper copy stays more transparent even when produced by a higher-level mirror"
	)
	_expect(
		is_equal_approx(reflect.get_damage_multiplier(1), 1.1)
		and is_equal_approx(reflect.get_damage_multiplier(2), 1.1),
		"both reflect mirror levels use a 1.1 damage multiplier"
	)
	_expect(
		reflect.get_penetration_bonus(1) == 0
		and reflect.get_penetration_bonus(2) == 0,
		"reflect mirror generic penetration is zero at both levels"
	)
	var reflect_payload := AttackEffectPayload.new()
	var reflect_angles := reflect_payload.get_reflection_branch_angles(
		{"attack_effects": reflect.get_attack_effects(2)},
		{"attack_kind": &"projectile"}
	)
	_expect(
		reflect.get_attack_effects(1).is_empty()
		and reflect_angles.size() == 2
		and is_equal_approx(reflect_angles[0], -15.0)
		and is_equal_approx(reflect_angles[1], 15.0),
		"reflect mirror exposes the level-two left/right fifteen-degree fork"
	)


func _test_copy_chain_accumulation() -> void:
	var definition := TestDefinitionFactory.make_copy_mirror_definition()
	var root_payload := MirrorCopyPayload.new()
	root_payload.stable_key = "source"
	root_payload.copy_kind = &"arrow_tower"
	var first := root_payload.copy_through(
		"copy-a",
		Vector3i(1, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(2),
		definition.get_penetration_bonus(2),
		-1.0,
		2
	)
	definition.apply_copy_attack_effects(
		first.attack_effects,
		2,
		{"copy_kind": first.copy_kind, "chain_depth": first.chain_depth}
	)
	var second := first.copy_through(
		"copy-b",
		Vector3i(2, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(2),
		definition.get_penetration_bonus(2),
		-1.0,
		2
	)
	_expect(is_equal_approx(first.damage_multiplier, 1.1), "one level-two copy has 1.1 damage")
	_expect(
		is_equal_approx(second.damage_multiplier, 1.21),
		"two level-two copies multiply into 1.21 damage"
	)
	_expect(second.penetration_bonus == 2, "two level-two copies add into +2 penetration")
	_expect(
		first.attack_effects.has_effect(&"burst_arrow")
		and second.attack_effects.has_effect(&"burst_arrow"),
		"recursive copies retain attack effects granted by an earlier mirror"
	)
	var burst_child_effects := first.attack_effects.duplicate_for_impact_child(
		{&"burst_arrow": {"is_burst_child": true}}
	)
	_expect(
		not bool(first.attack_effects.get_effect_state(&"burst_arrow").get("is_burst_child", true))
		and bool(
			burst_child_effects.get_effect_state(&"burst_arrow").get("is_burst_child", false)
		),
		"burst children receive a child-only non-recursive state without consuming the piercing parent"
	)
	var mixed := first.copy_through(
		"copy-c",
		Vector3i(3, 0, 0),
		Vector3.ZERO,
		Vector3.FORWARD,
		definition.get_damage_multiplier(2),
		definition.get_penetration_bonus(2),
		-1.0,
		2
	)
	_expect(
		is_equal_approx(mixed.damage_multiplier, 1.21)
		and mixed.penetration_bonus == 2
		and mixed.copy_upgrade_count == 2,
		"a second level-two copy keeps accumulating independently of mirror max level"
	)


func _test_arrow_mirror_effects() -> void:
	var copy := TestDefinitionFactory.make_copy_mirror_definition()
	var burst_effect := copy.get_attack_effects(2)[0]
	for copy_count in range(1, 4):
		var payload := AttackEffectPayload.new()
		payload.set_copy_upgrade_count(copy_count)
		burst_effect.apply_on_copy(payload, {"copy_kind": &"arrow_tower"})
		var capture := BurstCapture.new()
		payload.notify_projectile_impact(capture, null)
		_expect(
			capture.captured_count == [4, 6, 8][copy_count - 1],
			"arrow burst direction count follows copy reinforcement %d" % copy_count
		)
	var reflect := TestDefinitionFactory.make_reflect_mirror_definition()
	var reflection_hit := {"attack_effects": reflect.get_attack_effects(2)}
	var arrow_payload := AttackEffectPayload.new()
	_expect(
		arrow_payload.get_reflection_penetration_bonus(
			reflection_hit,
			{"source_building": TowerKindSource.new(&"arrow_tower")}
		) == 2,
		"level-two reflection grants arrow projectiles two penetration"
	)
	_expect(
		arrow_payload.get_reflection_penetration_bonus(
			reflection_hit,
			{"source_building": TowerKindSource.new(&"crossbow_tower")}
		) == 0,
		"level-two reflection grants non-arrow projectiles no penetration"
	)


func _test_reflection_path_state() -> void:
	var payload := AttackEffectPayload.new()
	var upgraded_hit := {"is_upgraded_reflect_mirror": true}
	for index in range(AttackEffectPayload.MAX_TOTAL_REFLECTIONS):
		_expect(payload.record_successful_reflection(upgraded_hit), "reflection %d succeeds before the cap" % (index + 1))
	_expect(
		not payload.record_successful_reflection(upgraded_hit)
		and payload.get_total_reflection_count() == 7
		and payload.get_reflection_upgrade_count() == 7,
		"the eighth reflector absorbs without increasing either reflection count"
	)
	var branch := payload.duplicate_for_reflection_branch()
	_expect(
		branch.get_total_reflection_count() == 7
		and branch.get_reflection_upgrade_count() == 7
		and not branch.can_spawn_reflection_branches(),
		"reflection branches inherit synchronized counts and cannot fork again"
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
	var downgrade_button := panel.get_node_or_null("DowngradeButton") as Button
	var upgrade_button := panel.find_child("UpgradeButton", true, false) as Button
	var sell_button := panel.get_node_or_null("SellButton") as Button
	var downgrade_refund_label := panel.get_node_or_null("DowngradeRefundLabel") as Label
	var upgrade_cost_label := panel.get_node_or_null("UpgradeCostLabel") as Label
	var sell_refund_label := panel.get_node_or_null("SellRefundLabel") as Label
	_expect(
		downgrade_button != null and upgrade_button != null and sell_button != null,
		"selected mirror exposes downgrade, upgrade, and sell actions"
	)
	_expect(
		panel.get_node_or_null("InfoButton") == null
		and panel.get_node_or_null("InfoPage") == null
		and panel.get_node_or_null("FlipButton") == null
		and panel.get_node_or_null("DeleteButton") == null,
		"the mirror explanation, old flip, and text demolition controls are absent"
	)
	_expect(
		downgrade_button.position.x < upgrade_button.position.x
		and upgrade_button.position.y == downgrade_button.position.y
		and sell_button.position.y < downgrade_button.position.y
		and sell_button.position.y < upgrade_button.position.y,
		"mirror sell action is above the left-downgrade/right-upgrade actions"
	)
	_expect(
		downgrade_button.size == upgrade_button.size and upgrade_button.size == sell_button.size,
		"all three mirror action icons have the same size"
	)
	var downgrade_icon := downgrade_button.get_node_or_null("Icon") as TextureRect
	_expect(
		downgrade_icon != null and downgrade_icon.texture != null,
		"mirror downgrade uses the supplied down-arrow icon"
	)
	_expect(
		upgrade_cost_label != null and upgrade_cost_label.visible and upgrade_cost_label.text == "-50"
		and downgrade_refund_label != null and not downgrade_refund_label.visible
		and sell_refund_label != null and sell_refund_label.visible and sell_refund_label.text == "+40",
		"level-one mirror shows upgrade and sell economy while hiding downgrade"
	)
	_expect(
		upgrade_cost_label.position.y < upgrade_button.position.y
		and sell_refund_label.position.y < sell_button.position.y
		and upgrade_cost_label.get_theme_color("font_color").is_equal_approx(
			sell_refund_label.get_theme_color("font_color")
		),
		"mirror economy numbers share the gold color and render above their icons"
	)
	_expect(manager.upgrade_mirror(copy), "mirror manager accepts the selected copy upgrade")
	_expect(
		copy.level == 2
		and is_equal_approx(resource.main_resource, 210.0)
		and is_equal_approx(copy.get_refund_amount(), 90.0)
		and downgrade_button.visible
		and downgrade_refund_label.visible
		and downgrade_refund_label.text == "+50"
		and not upgrade_button.visible,
		"first copy upgrade spends 50 and replaces upgrade with downgrade"
	)
	panel._on_downgrade_pressed()
	_expect(
		copy.level == 1
		and is_equal_approx(resource.main_resource, 260.0)
		and is_equal_approx(copy.get_refund_amount(), 40.0)
		and not downgrade_button.visible
		and upgrade_button.visible
		and sell_refund_label.text == "+40"
		and not manager.downgrade_mirror(copy),
		"mirror downgrade returns its upgrade payment without duplicating later sell refund"
	)
	_expect(manager.upgrade_mirror(copy), "copy mirror can upgrade again after a downgrade")
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
	_expect(
		not manager.upgrade_mirror(copy)
		and downgrade_button.visible
		and downgrade_refund_label.visible
		and downgrade_refund_label.text == "+50"
		and not upgrade_button.visible
		and not upgrade_cost_label.visible
		and sell_refund_label.text == "+90",
		"level-two maximum mirror shows downgrade, hides upgrade, and keeps its full sell refund visible"
	)
	_expect(manager.remove_mirror(copy) and is_equal_approx(resource.main_resource, 300.0), "level-two copy demolition refunds construction plus its upgrade")
	var reflect_from := Vector3i(2, 2, 0)
	var reflect_edge := grid.find_edge_index(reflect_from, Vector3i(3, 2, 0))
	var reflect := manager.place_reflect_mirror(reflect_from, reflect_edge, true)
	_expect(
		reflect != null
		and is_equal_approx(reflect.get_damage_multiplier(), 1.1)
		and reflect.get_penetration_bonus() == 0,
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
		and int(level_one_hit.get("penetration_bonus", -1)) == 0,
		"actual level-one reflection hit carries 1.1 damage and no generic penetration"
	)
	_expect(manager.upgrade_mirror(reflect), "reflect mirror reaches its level-two maximum through one paid upgrade")
	_expect(
		reflect.level == 2
		and is_equal_approx(reflect.get_damage_multiplier(), 1.1)
		and reflect.get_penetration_bonus() == 0,
		"level-two reflect mirror keeps 1.1 damage and zero generic penetration"
	)
	var reflect_upgrade_refund := reflect.get_downgrade_refund()
	var resource_before_reflect_downgrade := resource.main_resource
	_expect(
		manager.downgrade_mirror(reflect)
		and reflect.level == 1
		and is_equal_approx(resource.main_resource, resource_before_reflect_downgrade + reflect_upgrade_refund)
		and is_equal_approx(reflect.get_refund_amount(), manager.reflect_mirror_definition.placement_cost),
		"reflect mirror downgrade returns its upgrade payment and removes it from later sell value"
	)
	_expect(manager.upgrade_mirror(reflect), "reflect mirror can upgrade again after a downgrade")
	var level_two_hit := manager.trace_projectile_reflection(
		reflect_plane + reflect_normal,
		reflect_plane - reflect_normal
	)
	_expect(
		bool(level_two_hit.get("hit", false))
		and is_equal_approx(float(level_two_hit.get("damage_multiplier", 0.0)), 1.1)
		and int(level_two_hit.get("penetration_bonus", -1)) == 0
		and bool(level_two_hit.get("is_upgraded_reflect_mirror", false)),
		"actual level-two reflection hit exposes its upgraded marker and common modifiers"
	)
	var placements := manager.export_initial_placements()
	_expect(placements.size() == 1 and placements[0].level == 2, "initial-layout export persists level two")
	_expect(manager.remove_mirror(reflect) and is_equal_approx(resource.main_resource, 300.0), "reflect demolition refunds construction plus its upgrade")
	_expect(manager.load_initial_placements(placements).is_empty(), "authored level-two mirror reloads without spending resources")
	var loaded := manager.get_mirrors()[0] if not manager.get_mirrors().is_empty() else null
	var authored_refund := manager.reflect_mirror_definition.get_cumulative_cost(2)
	_expect(
		loaded != null
		and loaded.level == 2
		and is_equal_approx(loaded.get_refund_amount(), authored_refund),
		"reloaded authored mirror keeps level two and its full configured refund"
	)
	_expect(
		manager.remove_mirror(loaded)
		and is_equal_approx(resource.main_resource, 300.0 + authored_refund),
		"demolishing the reloaded authored mirror grants construction plus its upgrade cost"
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
