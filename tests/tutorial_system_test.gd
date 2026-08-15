extends SceneTree

const TutorialThoughtBubbleScript := preload("res://scripts/ui/TutorialThoughtBubble.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[TutorialSystem] running")
	_test_configuration_validation()
	_test_latched_all_goal_runtime()
	_test_trigger_types()
	_test_wave_gate()
	_test_tail_deletion()
	_test_level_resource_reload_isolation()
	await _test_runtime_editor_controls()
	await _test_world_bound_bubble_tracks_camera()
	await _test_content_sized_bubble()
	if _failures == 0:
		print("[TutorialSystem] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[TutorialSystem] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_configuration_validation() -> void:
	var tutorial := TutorialDefinition.new()
	var event := TutorialEventDefinition.new()
	event.event_id = &"placement"
	event.gated_wave_number = 1
	var bubble := TutorialBubbleDefinition.new()
	bubble.text = "把箭塔放在红色格子。"
	event.bubbles.append(bubble)
	var goal := TutorialGoalDefinition.new()
	goal.goal_type = TutorialGoalDefinition.GoalType.RELEASE_WAVE
	goal.target_wave_number = 1
	event.goals.append(goal)
	tutorial.events.append(event)
	_expect(
		tutorial.validate_configuration(2).any(func(message: String) -> bool: return message.contains("同一波")),
		"validation rejects a release goal gated by the same wave"
	)
	goal.goal_type = TutorialGoalDefinition.GoalType.ACKNOWLEDGE_ALL_BUBBLES
	_expect(tutorial.validate_configuration(2).is_empty(), "valid all-goal tutorial data passes validation")


func _test_latched_all_goal_runtime() -> void:
	var host := Node.new()
	root.add_child(host)
	var buildings := BuildingManager.new()
	var waves := WaveManager.new()
	var director := TutorialDirector.new()
	host.add_child(buildings)
	host.add_child(waves)
	host.add_child(director)
	director.configure(buildings, waves)
	var definition := _make_building_definition()
	var level := _make_level(2)
	var tutorial := TutorialDefinition.new()
	var event := TutorialEventDefinition.new()
	event.event_id = &"all_goals"
	event.display_name = "全部目标"
	var placement := TutorialGoalDefinition.new()
	placement.goal_type = TutorialGoalDefinition.GoalType.PLACE_BUILDING
	placement.building_definition = definition
	placement.require_cell = true
	placement.target_cell = Vector3i(1, 0, 0)
	placement.require_facing = true
	placement.target_facing_index = 9
	event.goals.append(placement)
	var hidden_click := TutorialGoalDefinition.new()
	hidden_click.goal_type = TutorialGoalDefinition.GoalType.BLANK_SCREEN_CLICKS
	hidden_click.show_in_checklist = false
	event.goals.append(hidden_click)
	tutorial.events.append(event)
	level.tutorial = tutorial
	director.load_level(level)
	_expect(director.get_event_state(event) == TutorialDirector.EventState.ACTIVE, "zero-time event activates immediately")
	var building := Building.new()
	building.definition = definition
	building.cell = Vector3i(1, 0, 0)
	building.facing_index = 8
	building.level = 1
	buildings.building_constructed.emit(building)
	_expect(director.get_event_state(event) == TutorialDirector.EventState.ACTIVE, "wrong facing does not complete placement")
	building.facing_index = 9
	buildings.building_rotated_by_player.emit(building, 8, 9)
	_expect(director.get_event_state(event) == TutorialDirector.EventState.ACTIVE, "all-goal rule waits for hidden objective")
	_expect(director.get_checklist_entries().size() == 1, "hidden objectives do not appear in checklist")
	director.handle_blank_screen_click()
	_expect(director.get_event_state(event) == TutorialDirector.EventState.COMPLETED, "all goals complete and latch once")
	building.facing_index = 3
	buildings.building_rotated_by_player.emit(building, 9, 3)
	_expect(director.get_event_state(event) == TutorialDirector.EventState.COMPLETED, "completed goal never regresses")
	building.free()
	host.free()


func _test_wave_gate() -> void:
	var manager := WaveManager.new()
	root.add_child(manager)
	manager._level = _make_level(1)
	manager._state = WaveManager.State.READY
	manager.set_wave_release_guard(func(_wave_number: int) -> String: return "完成放置目标")
	_expect(not manager.can_start_next_wave(), "wave manager enforces tutorial gate at the release boundary")
	_expect(manager.get_next_wave_release_block_reason() == "完成放置目标", "wave gate exposes player-facing reason")
	manager.set_wave_release_guard(func(_wave_number: int) -> String: return "")
	_expect(manager.can_start_next_wave(), "empty tutorial reason restores normal wave availability")
	manager.free()


func _test_tail_deletion() -> void:
	var host := Node.new()
	root.add_child(host)
	var director := TutorialDirector.new()
	host.add_child(director)
	var level := _make_level(2)
	var tutorial := TutorialDefinition.new()
	var event := _make_click_event(&"delete_01", 99)
	event.bubbles.append(TutorialBubbleDefinition.new())
	tutorial.events.append(event)
	level.tutorial = tutorial
	director.load_level(level)
	var first_bubble := event.bubbles[0]
	var second_bubble := director.add_bubble(event)
	var third_bubble := director.add_bubble(event)
	var bubble_result := director.remove_last_bubble(event)
	_expect(bool(bubble_result.get("success", false)), "bubble tail deletion succeeds")
	_expect(event.bubbles == [first_bubble, second_bubble] and not event.bubbles.has(third_bubble), "bubble deletion removes only the queue tail")
	var linked_goal := director.add_goal(event, TutorialGoalDefinition.GoalType.PLACE_BUILDING)
	first_bubble.dismiss_condition = TutorialBubbleDefinition.DismissCondition.GOAL_COMPLETED
	first_bubble.associated_goal_index = event.goals.size() - 1
	var goal_result := director.remove_last_goal(event)
	_expect(bool(goal_result.get("success", false)) and not event.goals.has(linked_goal), "goal deletion removes only the queue tail")
	_expect(
		first_bubble.dismiss_condition == TutorialBubbleDefinition.DismissCondition.EVENT_COMPLETED
		and first_bubble.associated_goal_index == -1,
		"deleting a linked tail goal repairs its bubble reference"
	)
	var second_event := director.create_event_at_current_time()
	second_event.event_id = &"delete_02"
	var third_event := director.create_event_at_current_time()
	third_event.event_id = &"delete_03"
	event.trigger_kind = TutorialEventDefinition.TriggerKind.EVENT_COMPLETED
	event.trigger_event_id = third_event.event_id
	var event_result := director.remove_last_event()
	_expect(bool(event_result.get("success", false)) and not director.get_events().has(third_event), "event deletion removes only the queue tail")
	_expect(director.get_events().back() == second_event, "event deletion preserves the preceding queue order")
	_expect(event.trigger_kind == TutorialEventDefinition.TriggerKind.START, "deleting a referenced tail event repairs dependent triggers")
	host.free()


func _test_level_resource_reload_isolation() -> void:
	const LEVEL_PATH := "res://resources/levels/Level1.tres"
	var active_level := ResourceLoader.load(
		LEVEL_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP
	) as LevelResource
	var director := TutorialDirector.new()
	root.add_child(director)
	director.load_level(active_level, LEVEL_PATH)
	var active_event_count := director.get_events().size()
	var replacement_level := ResourceLoader.load(
		LEVEL_PATH,
		"",
		ResourceLoader.CACHE_MODE_IGNORE_DEEP
	) as LevelResource
	_expect(active_level != null and replacement_level != null, "restart loads a complete isolated level graph")
	_expect(active_level != replacement_level, "restart does not replace the active cached level in place")
	_expect(
		director.get_events().size() == active_event_count,
		"isolated reload leaves the active tutorial event graph intact until the swap"
	)
	director.load_level(replacement_level, LEVEL_PATH)
	_expect(
		director.get_events().all(func(event: TutorialEventDefinition) -> bool: return event != null),
		"reloaded tutorial timeline contains only event definitions"
	)
	director.free()


func _test_trigger_types() -> void:
	var host := Node.new()
	root.add_child(host)
	var buildings := BuildingManager.new()
	var waves := WaveManager.new()
	var director := TutorialDirector.new()
	host.add_child(buildings)
	host.add_child(waves)
	host.add_child(director)
	director.configure(buildings, waves)
	var level := _make_level(2)
	var tutorial := TutorialDefinition.new()
	var start_event := _make_click_event(&"start", 1)
	start_event.trigger_kind = TutorialEventDefinition.TriggerKind.START
	var timed_event := _make_click_event(&"timed", 99)
	timed_event.trigger_kind = TutorialEventDefinition.TriggerKind.LEVEL_TIME
	timed_event.trigger_delay_seconds = 5.0
	var wave_event := _make_click_event(&"wave_end", 99)
	wave_event.trigger_kind = TutorialEventDefinition.TriggerKind.WAVE_COMPLETED
	wave_event.trigger_wave_number = 1
	var dependent_event := _make_click_event(&"dependent", 99)
	dependent_event.trigger_kind = TutorialEventDefinition.TriggerKind.EVENT_COMPLETED
	dependent_event.trigger_event_id = start_event.event_id
	tutorial.events.assign([start_event, timed_event, wave_event, dependent_event])
	level.tutorial = tutorial
	director.load_level(level)
	_expect(director.get_event_state(start_event) == TutorialDirector.EventState.ACTIVE, "start trigger activates immediately")
	_expect(director.get_event_state(timed_event) == TutorialDirector.EventState.LOCKED, "time trigger waits for its authored time")
	director._process(4.9)
	_expect(director.get_event_state(timed_event) == TutorialDirector.EventState.LOCKED, "time trigger stays locked before its authored time")
	director._process(0.1)
	_expect(director.get_event_state(timed_event) == TutorialDirector.EventState.ACTIVE, "time trigger activates at its authored time")
	_expect(director.get_event_state(wave_event) == TutorialDirector.EventState.LOCKED, "wave-end trigger waits for its selected wave")
	waves.wave_completed.emit(1)
	_expect(director.get_event_state(wave_event) == TutorialDirector.EventState.ACTIVE, "wave-end trigger activates when its selected wave completes")
	_expect(director.get_event_state(dependent_event) == TutorialDirector.EventState.LOCKED, "tutorial-complete trigger waits for its selected tutorial")
	director.handle_blank_screen_click()
	_expect(director.get_event_state(start_event) == TutorialDirector.EventState.COMPLETED, "start tutorial can complete normally")
	_expect(director.get_event_state(dependent_event) == TutorialDirector.EventState.ACTIVE, "tutorial-complete trigger activates from the selected tutorial")
	var authored := director.create_event_at_current_time()
	_expect(authored.trigger_kind == TutorialEventDefinition.TriggerKind.LEVEL_TIME, "creating at runtime records a time trigger")
	_expect(is_equal_approx(authored.trigger_delay_seconds, 5.0), "creating at runtime records the current level time")
	host.free()


func _test_content_sized_bubble() -> void:
	var short_definition := TutorialBubbleDefinition.new()
	short_definition.text = "短句"
	var short_bubble := TutorialThoughtBubbleScript.new()
	root.add_child(short_bubble)
	short_bubble.configure(short_definition, true)
	await process_frame
	var short_size := short_bubble.size
	_expect(short_bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE, "authoring preview bubbles do not capture dragging")
	var long_definition := TutorialBubbleDefinition.new()
	long_definition.text = "这是一段明显更长的教学说明文字，它应当根据最大宽度自动换行，并让白色思考气泡向下增长。"
	long_definition.maximum_width = 300.0
	var long_bubble := TutorialThoughtBubbleScript.new()
	root.add_child(long_bubble)
	long_bubble.configure(long_definition)
	await process_frame
	_expect(long_bubble.size.y > short_size.y, "bubble height grows with wrapped text")
	_expect(long_bubble.size.x <= long_definition.maximum_width + 0.01, "bubble width respects authored maximum")
	short_bubble.free()
	long_bubble.free()


func _test_runtime_editor_controls() -> void:
	var host := Node.new()
	root.add_child(host)
	var buildings := BuildingManager.new()
	var arrow_definition := _make_building_definition()
	buildings.arrow_tower = arrow_definition
	var waves := WaveManager.new()
	var director := TutorialDirector.new()
	var editor := TutorialRuntimeEditor.new()
	host.add_child(buildings)
	host.add_child(waves)
	host.add_child(director)
	host.add_child(editor)
	await process_frame
	director.configure(buildings, waves)
	var level := _make_level(2)
	var tutorial := TutorialDefinition.new()
	var event := _make_click_event(&"editor", 99)
	var bubble := TutorialBubbleDefinition.new()
	bubble.text = "abc"
	event.bubbles.append(bubble)
	var initial_arrow := Building.new()
	initial_arrow.definition = arrow_definition
	initial_arrow.cell = Vector3i(1, 0, 0)
	initial_arrow.level = 1
	buildings._buildings[initial_arrow.cell] = initial_arrow
	tutorial.events.append(event)
	level.tutorial = tutorial
	director.load_level(level)
	editor.configure(director, null, buildings, waves, Callable())
	_expect(editor._trigger_kind.item_count == 4, "runtime editor offers the four authored trigger types")
	var goal := event.goals[0]
	var placement_type_item := editor._goal_type.get_item_index(TutorialGoalDefinition.GoalType.PLACE_BUILDING)
	editor._on_goal_type_changed(placement_type_item)
	_expect(goal.goal_type == TutorialGoalDefinition.GoalType.PLACE_BUILDING, "goal type selector edits the current goal")
	_expect(director.get_event_state(event) == TutorialDirector.EventState.ACTIVE, "an existing arrow tower does not satisfy a new placement goal")
	_expect(not editor._building_option.disabled and editor._building_option.item_count > 1, "placement goal enables the building catalog")
	var arrow_item := editor._building_option.get_item_index(1)
	editor._on_building_selected(arrow_item)
	_expect(goal.building_definition == arrow_definition, "arrow tower can be selected for a placement goal")
	_expect(editor._building_option.get_selected_id() == 1, "arrow tower remains visibly selected after editor refresh")
	var linked_dismiss_item := editor._bubble_dismiss.get_item_index(TutorialBubbleDefinition.DismissCondition.GOAL_COMPLETED)
	editor._on_bubble_dismiss_changed(linked_dismiss_item)
	_expect(bubble.associated_goal_index == 0, "linked bubble explicitly targets the placement goal")
	director.handle_blank_screen_click()
	_expect(director.get_event_state(event) == TutorialDirector.EventState.ACTIVE, "clicking a linked bubble does not complete an unfinished placement goal")
	_expect(director.get_visible_bubble_entries().size() == 1, "linked bubble remains until its placement goal completes")
	var placed := Building.new()
	placed.definition = arrow_definition
	placed.cell = Vector3i.ZERO
	placed.level = 1
	buildings.building_constructed.emit(placed)
	_expect(director.get_event_state(event) == TutorialDirector.EventState.COMPLETED, "placement action completes the linked goal and event")
	_expect(director.get_visible_bubble_entries().is_empty(), "linked bubble disappears after the placement goal completes")
	placed.free()
	initial_arrow.free()
	editor._bubble_text.set_caret_line(0)
	editor._bubble_text.set_caret_column(3)
	editor._bubble_text.insert_text_at_caret("d")
	_expect(editor._bubble_text.get_caret_column() == 4, "bubble text refresh preserves the typing caret")
	event.trigger_kind = TutorialEventDefinition.TriggerKind.LEVEL_TIME
	editor._refresh_all()
	_expect(editor._trigger_time_row.visible and not editor._trigger_wave_row.visible, "time trigger shows only its time parameter")
	event.trigger_kind = TutorialEventDefinition.TriggerKind.WAVE_COMPLETED
	editor._refresh_all()
	_expect(editor._trigger_wave_row.visible and not editor._trigger_time_row.visible, "wave-end trigger shows only its wave parameter")
	bubble.anchor_kind = TutorialBubbleDefinition.AnchorKind.SCREEN
	editor._refresh_all()
	editor._on_bubble_x_changed(640.0)
	editor._on_bubble_y_changed(360.0)
	_expect(bubble.screen_position == Vector2(640.0, 360.0), "screen bubble position is authored through X/Y coordinates")
	bubble.anchor_kind = TutorialBubbleDefinition.AnchorKind.WORLD_CELL
	editor._refresh_all()
	editor._on_bubble_cell_x_changed(3.0)
	editor._on_bubble_cell_y_changed(4.0)
	editor._on_bubble_cell_z_changed(2.0)
	_expect(bubble.world_cell == Vector3i(3, 4, 2), "world bubble can bind to an explicitly authored grid cell")
	editor._on_bubble_x_changed(-24.0)
	editor._on_bubble_y_changed(18.0)
	_expect(bubble.offset == Vector2(-24.0, 18.0), "world bubble X/Y coordinates author its target-relative offset")
	host.free()


func _test_world_bound_bubble_tracks_camera() -> void:
	var host := Node.new()
	root.add_child(host)
	var grid := GridManager.new()
	var camera := Camera3D.new()
	var overlay := TutorialOverlay.new()
	var bubble_node := TutorialThoughtBubbleScript.new()
	host.add_child(grid)
	host.add_child(camera)
	host.add_child(overlay)
	overlay.add_child(bubble_node)
	await process_frame
	var definition := TutorialBubbleDefinition.new()
	definition.anchor_kind = TutorialBubbleDefinition.AnchorKind.WORLD_CELL
	definition.world_cell = Vector3i(2, 1, 0)
	definition.offset = Vector2(18.0, -12.0)
	bubble_node.configure(definition)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(0.0, 8.0, 9.0)
	camera.look_at(Vector3.ZERO)
	overlay._camera = camera
	overlay._grid = grid
	overlay._position_bubble(bubble_node, definition)
	var first_position := bubble_node.position
	camera.position = Vector3(6.0, 8.0, 9.0)
	camera.look_at(Vector3.ZERO)
	overlay._position_bubble(bubble_node, definition)
	_expect(bubble_node.position.distance_to(first_position) > 1.0, "world-bound bubble follows its grid cell when the camera moves")
	host.free()


func _make_level(wave_count: int) -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.HEX
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(2, 2)
	level.height_levels = 3
	level.height_step = 1.0
	level.base_cell = Vector3i.ZERO
	var tile := TileCellData.new()
	tile.configure(Vector3i.ZERO, TileCellData.TileType.BUILDABLE, 1)
	level.tiles.append(tile)
	for index in range(wave_count):
		var wave := WaveDefinition.new()
		wave.display_name = "Wave %d" % (index + 1)
		level.waves.append(wave)
	return level


func _make_building_definition() -> BuildingDefinition:
	var definition := BuildingDefinition.new()
	definition.display_name = "教学箭塔"
	definition.levels = [BuildingLevelStats.new(), BuildingLevelStats.new()]
	return definition


func _make_click_event(event_id: StringName, required_count: int) -> TutorialEventDefinition:
	var event := TutorialEventDefinition.new()
	event.event_id = event_id
	var goal := TutorialGoalDefinition.new()
	goal.goal_type = TutorialGoalDefinition.GoalType.BLANK_SCREEN_CLICKS
	goal.required_count = required_count
	event.goals.append(goal)
	return event


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
