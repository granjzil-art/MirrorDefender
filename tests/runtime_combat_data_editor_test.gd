extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[RuntimeCombatDataEditor] running")
	_test_formal_base_health_and_leak_defaults()
	await _test_building_working_copy_rebuild_save_and_discard()
	await _test_test_enemies_are_wave_isolated_but_keep_normal_settlement()
	if _failures == 0:
		print("[RuntimeCombatDataEditor] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[RuntimeCombatDataEditor] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_formal_base_health_and_leak_defaults() -> void:
	_expect(is_equal_approx(LevelResource.new().base_max_hp, 20.0), "new levels default to 20 base health")
	var default_wave := WaveManager.new()
	_expect(
		is_equal_approx(default_wave.enemy_leak_health_penalty, 1.0),
		"wave settlement defaults every leaked enemy to one health"
	)
	default_wave.free()
	for level_path in [
		"res://resources/levels/Level1.tres",
		"res://resources/levels/Level2.tres",
		"res://resources/levels/Level3.tres",
		"res://resources/levels/Level4.tres",
	]:
		var level := ResourceLoader.load(level_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelResource
		_expect(
			level != null and is_equal_approx(level.base_max_hp, 20.0),
			"%s authors the shared 20-health base limit" % level_path.get_file()
		)


func _test_building_working_copy_rebuild_save_and_discard() -> void:
	var save_path := "user://runtime_combat_data_editor_test_building.tres"
	var pulse_building_save_path := "user://runtime_combat_data_editor_test_pulse_building.tres"
	var copy_mirror_save_path := "user://runtime_combat_data_editor_test_copy_mirror.tres"
	var reflect_mirror_save_path := "user://runtime_combat_data_editor_test_reflect_mirror.tres"
	if ResourceLoader.exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for mirror_path in [pulse_building_save_path, copy_mirror_save_path, reflect_mirror_save_path]:
		if ResourceLoader.exists(mirror_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(mirror_path))
	var source := _make_building_definition()
	_expect(ResourceSaver.save(source, save_path) == OK, "fixture building .tres is created")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as BuildingDefinition
	var pulse_source := load("res://resources/buildings/PulseLaserTower.tres") as BuildingDefinition
	var pulse_fixture := pulse_source.duplicate(true) as BuildingDefinition
	_expect(
		ResourceSaver.save(pulse_fixture, pulse_building_save_path) == OK,
		"fixture pulse-laser building .tres is created"
	)
	var loaded_pulse := ResourceLoader.load(
		pulse_building_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as BuildingDefinition
	var host := Node3D.new()
	root.add_child(host)
	var level := _make_plain_level()
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	var resources := ResourceManager.new()
	host.add_child(resources)
	resources.apply_level_configuration(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	var manager := BuildingManager.new()
	host.add_child(manager)
	manager.arrow_tower = loaded
	manager.pulse_laser_tower = loaded_pulse
	manager.configure(grid, tile, resources, combat)
	_expect(tile.load_level(level), "building fixture level loads")
	var original := manager.place_building(Vector3i(0, 0, 0), loaded, 7)
	_expect(original != null, "fixture places the source building")
	var wave := WaveManager.new()
	host.add_child(wave)
	var loader := LevelLoader.new()
	host.add_child(loader)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	var copy_source := load("res://resources/mirrors/CopyMirror.tres") as CopyMirrorDefinition
	var reflect_source := load("res://resources/mirrors/ReflectMirror.tres") as ReflectMirrorDefinition
	var copy_fixture := copy_source.duplicate(true) as CopyMirrorDefinition
	var reflect_fixture := reflect_source.duplicate(true) as ReflectMirrorDefinition
	_expect(
		ResourceSaver.save(copy_fixture, copy_mirror_save_path) == OK
		and ResourceSaver.save(reflect_fixture, reflect_mirror_save_path) == OK,
		"fixture mirror .tres resources are created"
	)
	mirror_manager.copy_mirror_definition = ResourceLoader.load(
		copy_mirror_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as CopyMirrorDefinition
	mirror_manager.reflect_mirror_definition = ResourceLoader.load(
		reflect_mirror_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ReflectMirrorDefinition
	var session := RuntimeCombatDataEditSession.new()
	host.add_child(session)
	_expect(
		session.configure(manager, wave, loader, mirror_manager),
		"combat data session discovers building and mirror .tres resources"
	)
	var test_spawner := RuntimeTestEnemySpawner.new()
	host.add_child(test_spawner)
	test_spawner.configure(wave)
	var editor_window := RuntimeCombatDataEditorWindow.new()
	editor_window.visible = false
	host.add_child(editor_window)
	editor_window.configure(session, test_spawner)
	_expect(editor_window.force_native and not editor_window.transient, "editor uses an independent native non-transient window")
	_expect(editor_window._building_select.item_count == 2, "native editor lists both discovered building resources")
	for mirror_option_index in range(editor_window._mirror_select.item_count):
		if int(editor_window._mirror_select.get_item_metadata(mirror_option_index)) == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
			editor_window._mirror_select.select(mirror_option_index)
			editor_window._rebuild_mirror_form()
			break
	_expect(
		editor_window._mirror_select.item_count == 2
		and editor_window._mirror_form.get_child_count() > 0
		and _tree_has_label(editor_window._mirror_form, "镭射塔：初始与一级反射色盘"),
		"native editor exposes the copy/reflect mirror parameter forms"
	)
	var mirror_working := session.get_mirror_definitions()
	var working_copy := mirror_working.get(MirrorPlacementData.MirrorKind.COPY) as CopyMirrorDefinition
	var working_reflect := mirror_working.get(
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
	) as ReflectMirrorDefinition
	var burst_effect := _find_effect(working_copy, &"burst_arrow")
	var pulse_copy_effect := _find_effect(working_copy, &"pulse_laser_overdrive")
	var pulse_reflect_effect := _find_effect(working_reflect, &"pulse_laser_reflection")
	var live_copy_mirror := CopyMirror.new()
	live_copy_mirror.definition = working_copy
	live_copy_mirror.edge_id = "runtime-editor-live-copy"
	live_copy_mirror.level = 2
	live_copy_mirror.active_from_side = false
	live_copy_mirror.placement_order = 23
	mirror_manager.add_child(live_copy_mirror)
	mirror_manager._mirrors[live_copy_mirror.edge_id] = live_copy_mirror
	var mirror_edits_ok := (
		bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.COPY,
			&"root",
			&"impact_spawn_budget",
			64
		).get("success", false))
		and bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
			&"root",
			&"maximum_total_reflections",
			5
		).get("success", false))
		and bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.COPY,
			&"burst_arrow",
			&"direction_counts",
			5,
			0
		).get("success", false))
		and bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.COPY,
			&"pulse_laser_overdrive",
			&"sine_amplitude_ratio",
			0.8
		).get("success", false))
		and bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
			&"pulse_laser_reflection",
			&"reflection_colors",
			Color(0.3, 0.4, 0.5, 1.0),
			1
		).get("success", false))
	)
	_expect(mirror_edits_ok, "mirror root, tier-array, color-array and sine parameters accept runtime edits")
	_expect(
		working_copy != null
		and working_reflect != null
		and burst_effect != null
		and pulse_copy_effect != null
		and pulse_reflect_effect != null
		and working_copy.impact_spawn_budget == 64
		and working_reflect.maximum_total_reflections == 5
		and int((burst_effect.get("direction_counts") as Array)[0]) == 5
		and is_equal_approx(float(pulse_copy_effect.get("sine_amplitude_ratio")), 0.8)
		and ((pulse_reflect_effect.get("reflection_colors") as Array)[1] as Color).is_equal_approx(
			Color(0.3, 0.4, 0.5, 1.0)
		),
		"mirror working copies immediately expose every edited special value"
	)
	_expect(
		AttackEffectPayload.get_runtime_max_total_reflections() == 5
		and AttackEffectPayload.get_runtime_impact_spawn_budget() == 64,
		"mirror common safety edits immediately configure newly emitted attacks"
	)
	var initial_palette_color := Color(0.9, 0.1, 0.2, 1.0)
	var palette_edit := session.set_building_definition_array_value(
		BuildingDefinition.Kind.PULSE_LASER_TOWER,
		&"pulse_laser_reflection_colors",
		0,
		initial_palette_color
	)
	_expect(
		bool(palette_edit.get("success", false))
		and manager.get_definition(
			BuildingDefinition.Kind.PULSE_LASER_TOWER
		).pulse_laser_reflection_colors[0].is_equal_approx(initial_palette_color),
		"initial/level-one pulse color palette edits apply through the mirror page"
	)
	var rejected_mirror_array := session.set_mirror_value(
		MirrorPlacementData.MirrorKind.COPY,
		&"burst_arrow",
		&"direction_counts",
		0,
		0
	)
	_expect(
		not bool(rejected_mirror_array.get("success", false))
		and int((burst_effect.get("direction_counts") as Array)[0]) == 5,
		"invalid nested mirror-array edits roll back atomically"
	)
	var edit := session.set_building_value(
		BuildingDefinition.Kind.ARROW_TOWER,
		1,
		&"attack_range",
		12.5
	)
	_expect(bool(edit.get("success", false)), "building attack range edit is accepted")
	_expect(
		is_equal_approx(manager.get_definition(BuildingDefinition.Kind.ARROW_TOWER).get_level_stats(2).attack_range, 9.0),
		"editing level 1 leaves level 2 level_data unchanged"
	)
	var rejected_model := session.set_building_value(
		BuildingDefinition.Kind.ARROW_TOWER,
		1,
		&"projectile_model_asset",
		null
	)
	_expect(not bool(rejected_model.get("success", false)), "projectile model editing is intentionally unavailable")
	var rebuilt := manager.get_building(Vector3i(0, 0, 0))
	_expect(rebuilt != null and rebuilt != original, "existing building is recreated in place")
	_expect(rebuilt.facing_index == 7 and rebuilt.level == 1, "runtime rebuild preserves facing and level")
	_expect(is_equal_approx(rebuilt.get_level_stats().attack_range, 12.5), "rebuilt building uses explicit working level_data")
	var future := manager.place_building(Vector3i(1, 0, 0), loaded, 3)
	_expect(future != null and is_equal_approx(future.get_level_stats().attack_range, 12.5), "future placement resolves the working definition")
	var save_result := session.save()
	_expect(bool(save_result.get("success", false)), "permanent save writes the dirty building .tres")
	var persisted := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as BuildingDefinition
	_expect(persisted != null and is_equal_approx(persisted.get_level_stats(1).attack_range, 12.5), "saved level_data round-trips from the unique .tres")
	var persisted_copy := ResourceLoader.load(
		copy_mirror_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as CopyMirrorDefinition
	var persisted_reflect := ResourceLoader.load(
		reflect_mirror_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as ReflectMirrorDefinition
	var persisted_pulse := ResourceLoader.load(
		pulse_building_save_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as BuildingDefinition
	_expect(
		persisted_copy != null
		and persisted_reflect != null
		and persisted_pulse != null
		and persisted_copy.impact_spawn_budget == 64
		and persisted_reflect.maximum_total_reflections == 5
		and is_equal_approx(
			float(_find_effect(persisted_copy, &"pulse_laser_overdrive").get("sine_amplitude_ratio")),
			0.8
		)
		and persisted_pulse.pulse_laser_reflection_colors[0].is_equal_approx(
			initial_palette_color
		),
		"permanent save round-trips mirror common and nested effect resources"
	)
	_expect(
		live_copy_mirror.definition == mirror_manager.copy_mirror_definition
		and live_copy_mirror.level == 2
		and not live_copy_mirror.active_from_side
		and live_copy_mirror.placement_order == 23,
		"saving rebinds live mirrors without resetting their runtime state"
	)
	var second_edit := session.set_building_value(
		BuildingDefinition.Kind.ARROW_TOWER,
		1,
		&"attack_range",
		4.25
	)
	_expect(bool(second_edit.get("success", false)), "a second unsaved edit is accepted")
	_expect(
		bool(session.set_mirror_value(
			MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
			&"root",
			&"maximum_total_reflections",
			9
		).get("success", false)),
		"a second unsaved mirror edit is accepted"
	)
	var discard_result := session.discard()
	_expect(bool(discard_result.get("success", false)), "discard reloads the disk .tres")
	var discarded_building := manager.get_building(Vector3i(0, 0, 0))
	_expect(
		discarded_building != null and is_equal_approx(discarded_building.get_level_stats().attack_range, 12.5),
		"discard rebuilds existing buildings with the persisted level_data"
	)
	_expect(
		mirror_manager.reflect_mirror_definition.maximum_total_reflections == 5
		and AttackEffectPayload.get_runtime_max_total_reflections() == 5
		and live_copy_mirror.definition == mirror_manager.copy_mirror_definition
		and live_copy_mirror.level == 2
		and not live_copy_mirror.active_from_side
		and live_copy_mirror.placement_order == 23,
		"discard rebinds persisted mirror resources and preserves live mirror state"
	)
	host.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pulse_building_save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy_mirror_save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(reflect_mirror_save_path))


func _test_test_enemies_are_wave_isolated_but_keep_normal_settlement() -> void:
	var level := _make_wave_level()
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	var tile := TileManager.new()
	host.add_child(tile)
	tile.set_grid(grid)
	_expect(tile.load_level(level), "test-enemy fixture level loads")
	var path_manager := PathManager.new()
	host.add_child(path_manager)
	path_manager.configure(grid, tile)
	path_manager.load_level(level)
	var combat := CombatManager.new()
	host.add_child(combat)
	var resources := ResourceManager.new()
	host.add_child(resources)
	resources.apply_level_configuration(level)
	var base := BaseCore.new()
	host.add_child(base)
	base.configure(grid, tile)
	base.load_level(level)
	var wave := WaveManager.new()
	host.add_child(wave)
	wave.configure(path_manager, combat, resources, base)
	wave.load_level(level)
	var building_manager := BuildingManager.new()
	building_manager.arrow_tower = load("res://resources/buildings/ArrowTower.tres")
	host.add_child(building_manager)
	var loader := LevelLoader.new()
	host.add_child(loader)
	var session := RuntimeCombatDataEditSession.new()
	host.add_child(session)
	_expect(session.configure(building_manager, wave, loader), "enemy working-copy resolver starts")
	var working_enemy: EnemyDefinition
	for candidate in session.get_enemy_definitions():
		if candidate.enemy_id == &"grunt":
			working_enemy = candidate
			break
	if working_enemy == null and not session.get_enemy_definitions().is_empty():
		working_enemy = session.get_enemy_definitions()[0]
	var enemy_edits_ok := working_enemy != null
	if working_enemy != null:
		for edit in [
			session.set_enemy_value(working_enemy.resource_path, &"max_hp", 30.0),
			session.set_enemy_value(working_enemy.resource_path, &"reward", 17.0),
			session.set_enemy_value(working_enemy.resource_path, &"projectile_speed", 2.0),
		]:
			enemy_edits_ok = enemy_edits_ok and bool(edit.get("success", false))
	_expect(enemy_edits_ok, "enemy edits update the runtime working copy")
	var legacy_leak_edit := session.set_enemy_value(
		working_enemy.resource_path if working_enemy != null else "",
		&"base_damage",
		13.0
	)
	_expect(
		not bool(legacy_leak_edit.get("success", false)),
		"enemy-specific base damage is no longer runtime-editable"
	)
	var enemy := (
		ResourceLoader.load(working_enemy.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyDefinition
		if working_enemy != null
		else _make_enemy(&"isolated_test", "Isolated Test")
	)
	var resource_before := resources.main_resource
	var spawn := wave.spawn_test_enemy(enemy, level.paths[0])
	_expect(bool(spawn.get("success", false)), "test enemy spawns through the isolated entry")
	_expect(wave.get_active_enemy_count() == 0 and wave.get_test_enemy_count() == 1, "test enemy is excluded from authored active-unit count")
	wave._state = WaveManager.State.ACTIVE
	wave._released_wave_count = level.waves.size()
	wave._spawn_states.clear()
	wave._finish_battle_if_complete()
	_expect(wave.get_state() == WaveManager.State.VICTORY, "a living test enemy does not block authored wave completion")
	var spawned_unit := _first_enemy_unit(wave)
	_expect(spawned_unit != null, "spawned test unit remains a normal EnemyUnit")
	enemy.projectile_speed = 25.0
	_expect(
		spawned_unit != null and is_equal_approx(spawned_unit.definition.projectile_speed, 2.0),
		"an already spawned enemy owns an immutable definition snapshot"
	)
	if spawned_unit != null:
		spawned_unit.take_damage(100000.0)
	await process_frame
	_expect(is_equal_approx(resources.main_resource, resource_before + 17.0), "test enemy death grants its normal reward")
	var second_spawn := wave.spawn_test_enemy(enemy, level.paths[0])
	_expect(bool(second_spawn.get("success", false)), "test enemy spawning remains independent after wave victory")
	var second_unit := _first_enemy_unit(wave)
	var base_before := base.current_hp
	var settled_penalties: Array[float] = []
	wave.enemy_reached_base.connect(
		func(_unit: EnemyUnit, penalty: float) -> void: settled_penalties.append(penalty)
	)
	if second_unit != null:
		second_unit.reached_base.emit(second_unit, 999.0)
	_expect(
		is_equal_approx(base.current_hp, base_before - 1.0),
		"every leaked enemy removes exactly one shared base health"
	)
	_expect(
		settled_penalties == [1.0],
		"enemy_reached_base broadcasts the normalized one-health penalty"
	)
	_expect(wave.clear_test_enemies() >= 1, "test enemies can be cleared independently")
	if session.is_dirty():
		session.discard()
	host.queue_free()
	await process_frame


func _make_building_definition() -> BuildingDefinition:
	var definition := BuildingDefinition.new()
	definition.kind = BuildingDefinition.Kind.ARROW_TOWER
	definition.display_name = "Runtime Test Arrow"
	definition.aim_mode = BuildingDefinition.AimMode.TRACK_TARGET
	var stats := BuildingLevelStats.new()
	stats.cost = 10.0
	stats.base_damage = 10.0
	stats.targeting_range = 8.0
	stats.attack_range = 5.0
	stats.attacks_per_second = 1.0
	definition.levels.append(stats)
	var level_two := stats.duplicate(true) as BuildingLevelStats
	level_two.cost = 15.0
	level_two.attack_range = 9.0
	definition.levels.append(level_two)
	return definition


func _make_plain_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(3, 2)
	level.base_cell = Vector3i(2, 1, 0)
	level.initial_resource = 1000
	level.building_cap = 10
	level.base_resource_per_second = 0.0
	return level


func _make_wave_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(3, 1)
	level.base_cell = Vector3i(2, 0, 0)
	level.base_max_hp = 100.0
	level.initial_resource = 100.0
	level.base_resource_per_second = 0.0
	var path := PathDefinition.new()
	path.path_id = &"runtime_test_path"
	path.display_name = "Runtime Test Path"
	path.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)]
	var spawn := SpawnPointDefinition.new()
	spawn.spawn_id = &"runtime_test_spawn"
	spawn.display_name = "Runtime Test Spawn"
	spawn.cell = path.get_start_cell()
	path.spawn_point = spawn
	level.paths.append(path)
	level.spawn_points.append(spawn)
	var group := SpawnGroupDefinition.new()
	group.enemy = _make_enemy(&"authored", "Authored")
	group.path = path
	group.spawn_point = spawn
	group.count = 1
	group.interval = 1.0
	var authored_wave := WaveDefinition.new()
	authored_wave.display_name = "Authored Wave"
	authored_wave.spawn_groups.append(group)
	level.waves.append(authored_wave)
	return level


func _make_enemy(enemy_id: StringName, display_name: String) -> EnemyDefinition:
	var enemy := EnemyDefinition.new()
	enemy.enemy_id = enemy_id
	enemy.display_name = display_name
	enemy.max_hp = 30.0
	enemy.move_speed = 1.0
	return enemy


func _first_enemy_unit(wave: WaveManager) -> EnemyUnit:
	for child in wave.get_children():
		if child is EnemyUnit and not child.is_queued_for_deletion():
			return child as EnemyUnit
	return null


func _find_effect(definition: MirrorDefinition, effect_id: StringName) -> Resource:
	if definition == null:
		return null
	for effect in definition.attack_effects:
		if effect != null and effect.get_effect_id() == effect_id:
			return effect
	return null


func _tree_has_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _tree_has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
