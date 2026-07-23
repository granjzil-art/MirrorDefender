extends SceneTree

const WaveTimelineModelScript := preload("res://scripts/ui/WaveTimelineModel.gd")
const WaveTimelinePanelScript := preload("res://scripts/ui/WaveTimelinePanel.gd")
const WaveTimelinePanelScene := preload("res://scenes/ui/WaveTimelinePanel.tscn")
const PathHoverPreviewScript := preload("res://scripts/path/PathHoverPreview.gd")
const PathHoverPreviewScene := preload("res://scenes/path/PathHoverPreview.tscn")
const RuntimeHudScene := preload("res://scenes/ui/RuntimeHud.tscn")

var _failures: int = 0
var _checks: int = 0
var _previewed_paths: Array = []
var _preview_clear_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUiBatch4] running")
	var fixture := await _make_fixture()
	_test_read_only_model(fixture)
	await _test_timeline_panel(fixture)
	await _test_path_hover_preview(fixture)
	await _test_runtime_hud_layout(fixture)
	var host: Node = fixture["host"]
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[RuntimeUiBatch4] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeUiBatch4] FAIL: %d of %d checks failed" % [_failures, _checks])
	quit(1)


func _test_read_only_model(fixture: Dictionary) -> void:
	var level: LevelResource = fixture["level"]
	var wave_count_before := level.waves.size()
	var model: WaveTimelineModelScript = WaveTimelineModelScript.new()
	var entries := model.build(level)
	_expect(entries.size() == 2, "timeline model creates one entry per authored wave")
	_expect(level.waves.size() == wave_count_before, "timeline projection does not mutate level wave data")
	if entries.size() < 2:
		return
	var first: Dictionary = entries[0]
	var second: Dictionary = entries[1]
	_expect(is_zero_approx(float(first["scheduled_time"])), "first wave uses its authored zero start delay")
	_expect(is_equal_approx(float(second["scheduled_time"]), 8.0), "wave block time uses the earliest group delay")
	_expect((second["paths"] as Array).size() == 2, "hover model preserves all unique paths in one wave")
	_expect((second["enemy_totals"] as Array).size() == 2, "enemy composition aggregates by enemy type")
	var summary := String(second["summary"])
	_expect(summary.contains("测试步兵 × 3") and summary.contains("测试弓箭手 × 2"), "wave summary exposes complete enemy composition")
	_expect(summary.contains("组1：测试步兵 ×3 | 出生点1 → 据点1"), "group summary uses numbered origin and target labels")
	_expect(summary.contains("组2：测试弓箭手 ×2 | 出生点2 → 据点2"), "group summary omits path, delay and interval noise")
	_expect(not summary.contains("路径 2") and not summary.contains("1.50s"), "condensed hover details exclude path names and timing fields")
	_expect("ui_icon" in EnemyDefinition.new(), "enemy definitions expose an optional UI icon art interface")


func _test_timeline_panel(fixture: Dictionary) -> void:
	var panel := WaveTimelinePanelScene.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = Vector2(210.0, 520.0)
	await process_frame
	panel.configure(fixture["wave"])
	panel.set_level(fixture["level"])
	await process_frame
	_expect(panel.get_wave_block_count() == 2, "timeline panel creates two interactive wave blocks")
	var first_block := panel.get_node("GlassPanel/TimelineArea/BlockLayer/Wave_1") as Button
	_expect(first_block.tooltip_text.is_empty(), "wave blocks do not create a duplicate native tooltip window")
	var line_y: float = panel.get_current_line_y()
	var first_rect: Rect2 = panel.get_wave_block_rect(0)
	var second_rect: Rect2 = panel.get_wave_block_rect(1)
	_expect(is_equal_approx(first_rect.end.y, line_y), "zero-delay first wave block touches the current-time line")
	_expect(second_rect.end.y < first_rect.end.y, "future wave is positioned above the current wave")
	_expect(panel.start_button.visible and not panel.start_button.disabled, "timeline owns the one-time first-wave start button")
	_previewed_paths.clear()
	_preview_clear_count = 0
	panel.paths_preview_requested.connect(_on_paths_preview_requested)
	panel.paths_preview_cleared.connect(_on_paths_preview_cleared)
	panel.preview_wave_for_test(1)
	_expect(panel.get_hovered_wave_index() == 1, "hover selects the requested wave entry")
	_expect(panel.info_panel.visible and panel.info_details.text.contains("测试弓箭手"), "hover opens full wave details")
	_expect(_previewed_paths.size() == 2, "hover requests simultaneous preview for every unique path")
	panel.set_preview_suppressed(true)
	_expect(panel.get_hovered_wave_index() == -1 and not panel.info_panel.visible, "modal suppression closes wave details")
	_expect(_preview_clear_count > 0, "modal suppression emits a path-preview clear request")
	panel.set_preview_suppressed(false)
	panel.start_button.pressed.emit()
	await process_frame
	var wave_manager: WaveManager = fixture["wave"]
	_expect(wave_manager.get_state() == WaveManager.State.ACTIVE, "first-wave button starts the global wave timeline")
	_expect(not panel.start_button.visible, "first-wave button disappears after battle start")
	panel.queue_free()
	await process_frame


func _test_path_hover_preview(fixture: Dictionary) -> void:
	var preview := PathHoverPreviewScene.instantiate() as PathHoverPreviewScript
	_expect(preview != null, "path hover preview has an Inspector-editable reusable scene")
	if preview == null:
		return
	var host: Node3D = fixture["host"]
	host.add_child(preview)
	preview.configure(fixture["path"])
	preview.preview_paths([fixture["path_1"], fixture["path_2"]])
	_expect(preview.get_active_path_count() == 2, "3D hover preview renders all requested paths")
	var initial_positions := preview.get_marker_positions()
	_expect(initial_positions.size() == preview.markers_per_path * 2, "each path receives the configured number of flow markers")
	preview.advance_visual_time(0.25)
	var moved_positions := preview.get_marker_positions()
	var any_marker_moved := false
	for index in range(mini(initial_positions.size(), moved_positions.size())):
		var initial: Vector3 = initial_positions[index]
		var moved: Vector3 = moved_positions[index]
		if initial.distance_to(moved) > 0.001:
			any_marker_moved = true
			break
	_expect(any_marker_moved, "flow markers advance from spawn toward base")
	preview.clear_preview()
	_expect(preview.get_active_path_count() == 0 and preview.get_marker_positions().is_empty(), "explicit clear removes all hovered path state")
	preview.preview_paths([fixture["path_1"]])
	var path_manager: PathManager = fixture["path"]
	path_manager.load_level(fixture["level"])
	_expect(preview.get_active_path_count() == 0, "level reload clears stale path previews")
	preview.queue_free()
	await process_frame


func _test_runtime_hud_layout(fixture: Dictionary) -> void:
	var hud := RuntimeHudScene.instantiate() as RuntimeHud
	root.add_child(hud)
	await process_frame
	hud.configure_wave_timeline(fixture["wave"])
	hud.apply_level_configuration(fixture["level"], "memory://runtime-ui-batch4")
	await process_frame
	var original_window_size := root.size
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
		var timeline: WaveTimelinePanelScript = hud.get_node("WaveTimelinePanel")
		var cards := hud.get_node("BuildCardBar") as Control
		var timeline_rect := timeline.get_global_rect()
		_expect(viewport_rect.encloses(timeline_rect), "wave timeline stays inside %dx%d" % [resolution.x, resolution.y])
		_expect(timeline_rect.size.x <= 121.0, "wave timeline keeps its compact 120-pixel width")
		_expect(not timeline_rect.intersects(cards.get_global_rect()), "wave timeline leaves the building cards clear at %dx%d" % [resolution.x, resolution.y])
		timeline.preview_wave_for_test(1)
		await process_frame
		var info_rect: Rect2 = timeline.info_panel.get_global_rect()
		_expect(viewport_rect.encloses(info_rect), "wave hover information stays inside %dx%d" % [resolution.x, resolution.y])
		timeline.clear_hover_preview()
	root.size = original_window_size
	hud.queue_free()
	await process_frame


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var base_core := BaseCore.new()
	host.add_child(base_core)
	base_core.configure(grid, tile_manager)
	var path_manager := PathManager.new()
	host.add_child(path_manager)
	path_manager.configure(grid, tile_manager)
	var wave_manager := WaveManager.new()
	host.add_child(wave_manager)
	wave_manager.configure(path_manager, combat_manager, resource_manager, base_core)

	var path_1 := _make_path(&"path_1", "路径 1", [
		Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0),
	])
	var path_2 := _make_path(&"path_2", "路径 2", [
		Vector3i(0, 2, 0), Vector3i(1, 2, 0), Vector3i(2, 2, 0), Vector3i(3, 2, 0),
	])
	var spawn_1 := _make_spawn(path_1, "入口 1")
	var spawn_2 := _make_spawn(path_2, "入口 2")
	spawn_1.display_number = 1
	spawn_2.display_number = 2
	var base_1 := _make_base(&"base_1", "据点 1", 1, path_1.get_end_cell())
	var base_2 := _make_base(&"base_2", "据点 2", 2, path_2.get_end_cell())
	path_1.spawn_point = spawn_1
	path_1.target_base = base_1
	path_2.spawn_point = spawn_2
	path_2.target_base = base_2
	var soldier := _make_enemy(&"soldier", "测试步兵")
	var archer := _make_enemy(&"archer", "测试弓箭手")
	var wave_1 := _make_wave("第一波", [
		_make_group(soldier, 2, 100.0, 0.0, spawn_1, path_1),
	])
	var wave_2 := _make_wave("第二波", [
		_make_group(soldier, 3, 1.0, 8.0, spawn_1, path_1),
		_make_group(archer, 2, 1.5, 10.0, spawn_2, path_2),
	])
	var level := LevelResource.new()
	level.display_name = "批次 4 测试关卡"
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(4, 3)
	level.base_cell = Vector3i(3, 1, 0)
	level.base_points.assign([base_1, base_2])
	level.base_resource_per_second = 0.0
	level.paths.assign([path_1, path_2])
	level.spawn_points.assign([spawn_1, spawn_2])
	level.waves.assign([wave_1, wave_2])
	grid.apply_configuration(level.grid_shape, level.grid_cell_size, level.grid_size)
	tile_manager.load_level(level)
	resource_manager.apply_level_configuration(level)
	path_manager.load_level(level)
	base_core.load_level(level)
	wave_manager.load_level(level)
	await process_frame
	_expect(level.validate_runtime().is_empty(), "batch 4 fixture is a valid runtime level")
	_expect(base_core.get_base_point_count() == 2, "runtime renders both authored base locations")
	var base_labels := base_core.get_marker_labels()
	_expect(base_labels.size() == 2 and base_labels[0].begins_with("据点 1\n") and base_labels[1].begins_with("据点 2\n"), "runtime base locations expose numeric markers")
	_expect(path_manager.get_spawn_marker_labels() == ["出生点 1", "出生点 2"], "runtime spawn locations expose numeric markers")
	_expect(tile_manager.get_occupant(base_1.cell) == base_core and tile_manager.get_occupant(base_2.cell) == base_core, "every base location points to the same health owner")
	base_core.take_damage(25.0)
	base_labels = base_core.get_marker_labels()
	_expect(is_equal_approx(base_core.current_hp, 75.0) and base_labels[0].contains("75/100") and base_labels[1].contains("75/100"), "damage at the shared base owner updates every base marker")
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"base": base_core,
		"path": path_manager,
		"wave": wave_manager,
		"level": level,
		"path_1": path_1,
		"path_2": path_2,
	}


func _make_path(path_id: StringName, display_name: String, cells: Array[Vector3i]) -> PathDefinition:
	var path := PathDefinition.new()
	path.path_id = path_id
	path.display_name = display_name
	path.cells = cells
	return path


func _make_spawn(path: PathDefinition, display_name: String) -> SpawnPointDefinition:
	var spawn := SpawnPointDefinition.new()
	spawn.spawn_id = SpawnPointDefinition.make_id_for_path(path)
	spawn.display_name = display_name
	spawn.cell = path.get_start_cell()
	return spawn


func _make_enemy(enemy_id: StringName, display_name: String) -> EnemyDefinition:
	var enemy := EnemyDefinition.new()
	enemy.enemy_id = enemy_id
	enemy.display_name = display_name
	enemy.move_speed = 0.1
	return enemy


func _make_base(base_id: StringName, display_name: String, number: int, cell: Vector3i) -> BasePointDefinition:
	var base_point := BasePointDefinition.new()
	base_point.base_id = base_id
	base_point.display_name = display_name
	base_point.display_number = number
	base_point.cell = cell
	return base_point


func _make_group(
	enemy: EnemyDefinition,
	count: int,
	interval: float,
	start_delay: float,
	spawn: SpawnPointDefinition,
	path: PathDefinition
) -> SpawnGroupDefinition:
	var group := SpawnGroupDefinition.new()
	group.enemy = enemy
	group.count = count
	group.interval = interval
	group.start_delay = start_delay
	group.spawn_point = spawn
	group.path = path
	return group


func _make_wave(display_name: String, groups: Array[SpawnGroupDefinition]) -> WaveDefinition:
	var wave := WaveDefinition.new()
	wave.display_name = display_name
	wave.spawn_groups = groups
	return wave


func _on_paths_preview_requested(paths: Array) -> void:
	_previewed_paths = paths.duplicate()


func _on_paths_preview_cleared() -> void:
	_preview_clear_count += 1


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
