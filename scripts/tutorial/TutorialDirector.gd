## Runtime tutorial timeline, latched objective evaluation, and wave-release policy.
class_name TutorialDirector
extends Node

const TutorialDefinitionScript := preload("res://scripts/tutorial/TutorialDefinition.gd")
const TutorialEventDefinitionScript := preload("res://scripts/tutorial/TutorialEventDefinition.gd")
const TutorialBubbleDefinitionScript := preload("res://scripts/tutorial/TutorialBubbleDefinition.gd")
const TutorialGoalDefinitionScript := preload("res://scripts/tutorial/TutorialGoalDefinition.gd")

enum EventState {
	LOCKED,
	ACTIVE,
	COMPLETED,
}

signal presentation_changed
signal authoring_changed
signal wave_gate_changed
signal event_activated(event: TutorialEventDefinition)
signal event_completed(event: TutorialEventDefinition)
signal goal_completed(event: TutorialEventDefinition, goal_index: int)
signal automatic_tower_placed(event: TutorialEventDefinition, building: Building)
signal automatic_tower_failed(event: TutorialEventDefinition, cell: Vector3i)

var _building_manager: BuildingManager
var _wave_manager: WaveManager
var _level: LevelResource
var _definition: TutorialDefinition
var _source_path: String = ""
var _level_elapsed: float = 0.0
var _event_states: Dictionary = {}
var _goal_states: Dictionary = {}
var _bubble_revealed_counts: Dictionary = {}
var _bubble_acknowledged: Dictionary = {}
var _event_action_baselines: Dictionary = {}
var _wave_completion_times: Dictionary = {}
var _event_completion_times: Dictionary = {}
var _released_waves: Dictionary = {}
var _completed_waves: Dictionary = {}
var _automatic_tower_attempted_events: Dictionary = {}
var _building_state_ledger: Array[Dictionary] = []
var _deleted_building_ledger: Array[Dictionary] = []
var _blank_click_count: int = 0


func configure(building_manager: BuildingManager, wave_manager: WaveManager) -> void:
	_disconnect_sources()
	_building_manager = building_manager
	_wave_manager = wave_manager
	if _building_manager != null:
		_building_manager.building_constructed.connect(_on_building_state_changed)
		_building_manager.building_relocated.connect(_on_building_relocated)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		_building_manager.building_rotated_by_player.connect(_on_building_rotated)
		_building_manager.building_removed_by_player.connect(_on_building_removed_by_player)
	if _wave_manager != null:
		_wave_manager.wave_released.connect(_on_wave_released)
		_wave_manager.wave_completed.connect(_on_wave_completed)


func load_level(level: LevelResource, source_path: String = "") -> void:
	_level = level
	_source_path = source_path if not source_path.is_empty() else (level.resource_path if level != null else "")
	_definition = level.tutorial if level != null else null
	_reset_runtime_state()
	_evaluate_timeline()
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()


func get_definition() -> TutorialDefinition:
	return _definition


func get_level_resource() -> LevelResource:
	return _level


func get_level_elapsed() -> float:
	return _level_elapsed


func get_events() -> Array[TutorialEventDefinition]:
	var out: Array[TutorialEventDefinition] = []
	if _definition == null:
		return out
	for item in _definition.events:
		if item != null:
			out.append(item)
	return out


func get_event_state(event: TutorialEventDefinition) -> EventState:
	if event == null:
		return EventState.LOCKED
	return _event_states.get(event.event_id, EventState.LOCKED) as EventState


func get_active_event() -> TutorialEventDefinition:
	if _definition == null:
		return null
	for event in _definition.events:
		if event != null and get_event_state(event) == EventState.ACTIVE:
			return event
	return null


func get_goal_states(event: TutorialEventDefinition) -> Array[bool]:
	var out: Array[bool] = []
	if event == null:
		return out
	var stored: Array = _goal_states.get(event.event_id, [])
	for value in stored:
		out.append(bool(value))
	return out


func get_checklist_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var event := get_active_event()
	if event == null:
		return out
	var states := get_goal_states(event)
	for index in range(event.goals.size()):
		var goal := event.goals[index]
		if goal == null or not goal.show_in_checklist:
			continue
		out.append({
			"description": goal.get_display_description(),
			"completed": states[index] if index < states.size() else false,
			"goal_index": index,
		})
	return out


func get_visible_bubble_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _definition == null:
		return out
	for event in _definition.events:
		if event == null or get_event_state(event) == EventState.LOCKED:
			continue
		var revealed := int(_bubble_revealed_counts.get(event.event_id, 0))
		var acknowledged: Dictionary = _bubble_acknowledged.get(event.event_id, {})
		var goals := get_goal_states(event)
		for index in range(mini(revealed, event.bubbles.size())):
			var bubble := event.bubbles[index]
			if bubble == null:
				continue
			var should_show := true
			match bubble.dismiss_condition:
				TutorialBubbleDefinitionScript.DismissCondition.ACKNOWLEDGED:
					should_show = not bool(acknowledged.get(index, false))
				TutorialBubbleDefinitionScript.DismissCondition.GOAL_COMPLETED:
					should_show = not (
						bubble.associated_goal_index >= 0
						and bubble.associated_goal_index < goals.size()
						and goals[bubble.associated_goal_index]
					)
				TutorialBubbleDefinitionScript.DismissCondition.EVENT_COMPLETED:
					should_show = get_event_state(event) != EventState.COMPLETED
				TutorialBubbleDefinitionScript.DismissCondition.PERSISTENT:
					should_show = true
			if should_show:
				out.append({"event": event, "bubble": bubble, "bubble_index": index})
	return out


func get_active_placement_target() -> Dictionary:
	var event := get_active_event()
	if event == null:
		return {}
	var states := get_goal_states(event)
	for index in range(event.goals.size()):
		var goal := event.goals[index]
		if (
			goal != null
			and goal.goal_type == TutorialGoalDefinitionScript.GoalType.PLACE_BUILDING
			and goal.require_cell
		):
			return {
				"cell": goal.target_cell,
				"facing_index": goal.target_facing_index,
				"require_facing": goal.require_facing,
				"completed": states[index] if index < states.size() else false,
				"definition": goal.building_definition,
			}
	return {}


func handle_blank_screen_click() -> void:
	_blank_click_count += 1
	var event := get_active_event()
	if event != null:
		var revealed := int(_bubble_revealed_counts.get(event.event_id, 0))
		if revealed > 0:
			var acknowledged: Dictionary = _bubble_acknowledged.get(event.event_id, {})
			var acknowledge_index := -1
			for index in range(revealed):
				if not bool(acknowledged.get(index, false)):
					acknowledge_index = index
					break
			if acknowledge_index >= 0:
				acknowledged[acknowledge_index] = true
				_bubble_acknowledged[event.event_id] = acknowledged
				if revealed < event.bubbles.size():
					_bubble_revealed_counts[event.event_id] = revealed + 1
	_evaluate_active_goals()
	presentation_changed.emit()


func get_wave_block_reason(wave_number: int) -> String:
	if _definition == null or not _definition.enabled or wave_number <= 0:
		return ""
	for event_value: Variant in _definition.events:
		if not event_value is TutorialEventDefinitionScript:
			continue
		var event := event_value as TutorialEventDefinition
		if (
			event.gated_wave_number == wave_number
			and get_event_state(event) != EventState.COMPLETED
		):
			var state := get_goal_states(event)
			for index in range(event.goals.size()):
				if index >= state.size() or state[index]:
					continue
				var goal := event.goals[index]
				if goal != null:
					return goal.get_display_description()
			return "完成教学事件：%s" % event.display_name
	return ""


func create_event_at_current_time() -> TutorialEventDefinition:
	if _level == null:
		return null
	if _definition == null:
		_definition = TutorialDefinitionScript.new()
		_level.tutorial = _definition
	var event := TutorialEventDefinitionScript.new()
	event.event_id = _make_unique_event_id()
	event.display_name = "教学事件 %d" % (_definition.events.size() + 1)
	event.trigger_kind = TutorialEventDefinitionScript.TriggerKind.LEVEL_TIME
	event.trigger_delay_seconds = _level_elapsed
	event.gated_wave_number = _wave_manager.get_next_wave_number() if _wave_manager != null else 0
	var bubble := TutorialBubbleDefinitionScript.new()
	event.bubbles.append(bubble)
	var bubble_goal := TutorialGoalDefinitionScript.new()
	bubble_goal.goal_type = TutorialGoalDefinitionScript.GoalType.ACKNOWLEDGE_ALL_BUBBLES
	bubble_goal.show_in_checklist = false
	event.goals.append(bubble_goal)
	_definition.events.append(event)
	_initialize_event(event, true)
	_level.emit_changed()
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()
	return event


func add_bubble(event: TutorialEventDefinition) -> TutorialBubbleDefinition:
	if event == null:
		return null
	var bubble := TutorialBubbleDefinitionScript.new()
	var last: TutorialBubbleDefinition = event.bubbles.back() if not event.bubbles.is_empty() else null
	if last != null:
		bubble.screen_position = last.screen_position + Vector2(28.0, 36.0)
	event.bubbles.append(bubble)
	_level.emit_changed() if _level != null else null
	authoring_changed.emit()
	presentation_changed.emit()
	return bubble


func add_goal(event: TutorialEventDefinition, goal_type: int) -> TutorialGoalDefinition:
	if event == null:
		return null
	var goal := TutorialGoalDefinitionScript.new()
	goal.goal_type = goal_type as TutorialGoalDefinitionScript.GoalType
	if goal.goal_type == TutorialGoalDefinitionScript.GoalType.ACKNOWLEDGE_ALL_BUBBLES:
		goal.show_in_checklist = false
	event.goals.append(goal)
	var states: Array = _goal_states.get(event.event_id, [])
	states.append(false)
	_goal_states[event.event_id] = states
	_level.emit_changed() if _level != null else null
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()
	return goal


func remove_last_event() -> Dictionary:
	if _definition == null or _definition.events.is_empty():
		return {"success": false, "message": "没有可删除的教学事件"}
	var removed := _definition.events.pop_back() as TutorialEventDefinition
	if removed == null:
		return {"success": false, "message": "队尾教学事件无效，无法删除"}
	var repaired_references := 0
	for event_value: Variant in _definition.events:
		if not event_value is TutorialEventDefinitionScript:
			continue
		var event := event_value as TutorialEventDefinition
		if (
			event.trigger_kind == TutorialEventDefinitionScript.TriggerKind.EVENT_COMPLETED
			and event.trigger_event_id == removed.event_id
		):
			event.trigger_kind = TutorialEventDefinitionScript.TriggerKind.START
			event.trigger_event_id = &""
			event.trigger_delay_seconds = 0.0
			repaired_references += 1
	_event_states.erase(removed.event_id)
	_goal_states.erase(removed.event_id)
	_bubble_revealed_counts.erase(removed.event_id)
	_bubble_acknowledged.erase(removed.event_id)
	_event_action_baselines.erase(removed.event_id)
	_event_completion_times.erase(removed.event_id)
	_automatic_tower_attempted_events.erase(removed.event_id)
	if _level != null:
		_level.emit_changed()
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()
	var message := "已删除队尾事件：%s" % removed.display_name
	if repaired_references > 0:
		message += "；%d 个引用已改为开始触发" % repaired_references
	return {"success": true, "message": message, "removed": removed}


func remove_last_bubble(event: TutorialEventDefinition) -> Dictionary:
	if event == null or event.bubbles.is_empty():
		return {"success": false, "message": "当前事件没有可删除的气泡"}
	var removed_index := event.bubbles.size() - 1
	var removed := event.bubbles.pop_back() as TutorialBubbleDefinition
	var acknowledged: Dictionary = _bubble_acknowledged.get(event.event_id, {})
	acknowledged.erase(removed_index)
	_bubble_acknowledged[event.event_id] = acknowledged
	_bubble_revealed_counts[event.event_id] = mini(
		int(_bubble_revealed_counts.get(event.event_id, 0)),
		event.bubbles.size()
	)
	reset_event_progress_for_authoring(event)
	if _level != null:
		_level.emit_changed()
	authoring_changed.emit()
	presentation_changed.emit()
	return {
		"success": true,
		"message": "已删除队尾气泡 %d" % (removed_index + 1),
		"removed": removed,
	}


func remove_last_goal(event: TutorialEventDefinition) -> Dictionary:
	if event == null or event.goals.is_empty():
		return {"success": false, "message": "当前事件没有可删除的待办目标"}
	var removed_index := event.goals.size() - 1
	var removed := event.goals.pop_back() as TutorialGoalDefinition
	for bubble in event.bubbles:
		if bubble != null and bubble.associated_goal_index == removed_index:
			bubble.associated_goal_index = -1
			if bubble.dismiss_condition == TutorialBubbleDefinitionScript.DismissCondition.GOAL_COMPLETED:
				bubble.dismiss_condition = TutorialBubbleDefinitionScript.DismissCondition.EVENT_COMPLETED
	reset_event_progress_for_authoring(event)
	if _level != null:
		_level.emit_changed()
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()
	return {
		"success": true,
		"message": "已删除队尾待办：%s" % removed.get_display_description(),
		"removed": removed,
	}


func notify_authoring_changed() -> void:
	if _level != null:
		_level.emit_changed()
	_evaluate_active_goals()
	authoring_changed.emit()
	presentation_changed.emit()
	wave_gate_changed.emit()


func reset_event_progress_for_authoring(event: TutorialEventDefinition) -> void:
	if event == null or get_event_state(event) == EventState.LOCKED:
		return
	_event_states[event.event_id] = EventState.ACTIVE
	var states: Array[bool] = []
	states.resize(event.goals.size())
	states.fill(false)
	_goal_states[event.event_id] = states
	_bubble_revealed_counts[event.event_id] = 1 if not event.bubbles.is_empty() else 0
	_bubble_acknowledged[event.event_id] = {}
	_event_action_baselines[event.event_id] = _make_action_baseline()
	_event_completion_times.erase(event.event_id)
	presentation_changed.emit()
	wave_gate_changed.emit()


func _make_action_baseline() -> Dictionary:
	return {
		"building_action_count": _building_state_ledger.size(),
		"deleted_action_count": _deleted_building_ledger.size(),
		"blank_click_count": _blank_click_count,
		"released_waves": _released_waves.duplicate(),
		"completed_waves": _completed_waves.duplicate(),
	}


func save_tutorial() -> Dictionary:
	if _level == null:
		return {"success": false, "message": "当前没有关卡"}
	var validation := _definition.validate_configuration(_level.waves.size()) if _definition != null else []
	if not validation.is_empty():
		return {"success": false, "message": "教程配置无效：\n%s" % "\n".join(validation)}
	var path := _source_path.strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".tres"):
		return {"success": false, "message": "当前关卡没有可写入的资源路径"}
	var disk_level := ResourceLoader.load(
		path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as LevelResource
	if disk_level == null:
		return {"success": false, "message": "无法读取待保存的关卡资源"}
	disk_level.tutorial = _definition.duplicate(true) as TutorialDefinition if _definition != null else null
	var disk_validation := disk_level.validate_runtime()
	if not disk_validation.is_empty():
		return {"success": false, "message": "保存后的关卡配置无效：\n%s" % "\n".join(disk_validation)}
	var error := ResourceSaver.save(disk_level, path)
	if error != OK:
		return {"success": false, "message": "保存教程失败：%s" % error_string(error)}
	return {"success": true, "message": "教程已保存到 %s" % path}


func _process(delta: float) -> void:
	if _definition == null or not _definition.enabled:
		return
	_level_elapsed += maxf(0.0, delta)
	_evaluate_timeline()


func _reset_runtime_state() -> void:
	_level_elapsed = 0.0
	_event_states.clear()
	_goal_states.clear()
	_bubble_revealed_counts.clear()
	_bubble_acknowledged.clear()
	_event_action_baselines.clear()
	_wave_completion_times.clear()
	_event_completion_times.clear()
	_released_waves.clear()
	_completed_waves.clear()
	_automatic_tower_attempted_events.clear()
	_building_state_ledger.clear()
	_deleted_building_ledger.clear()
	_blank_click_count = 0
	if _definition != null:
		for event in _definition.events:
			if event != null:
				_initialize_event(event, false)


func _initialize_event(event: TutorialEventDefinition, active: bool) -> void:
	_event_states[event.event_id] = EventState.ACTIVE if active else EventState.LOCKED
	var states: Array[bool] = []
	states.resize(event.goals.size())
	states.fill(false)
	_goal_states[event.event_id] = states
	_bubble_revealed_counts[event.event_id] = 1 if not event.bubbles.is_empty() and active else 0
	_bubble_acknowledged[event.event_id] = {}
	if active:
		_event_action_baselines[event.event_id] = _make_action_baseline()
		event_activated.emit(event)
		_try_place_automatic_tower(event)
		_evaluate_goals_for_event(event)


func _evaluate_timeline() -> void:
	if _definition == null or not _definition.enabled:
		return
	var changed := false
	for event in _definition.events:
		if event == null or get_event_state(event) != EventState.LOCKED:
			continue
		if _is_trigger_satisfied(event):
			_event_states[event.event_id] = EventState.ACTIVE
			_bubble_revealed_counts[event.event_id] = 1 if not event.bubbles.is_empty() else 0
			_event_action_baselines[event.event_id] = _make_action_baseline()
			event_activated.emit(event)
			_try_place_automatic_tower(event)
			_evaluate_goals_for_event(event)
			changed = true
	if changed:
		presentation_changed.emit()
		wave_gate_changed.emit()


func _try_place_automatic_tower(event: TutorialEventDefinition) -> void:
	if (
		event == null
		or not event.automatic_tower_enabled
		or event.trigger_kind != TutorialEventDefinitionScript.TriggerKind.WAVE_COMPLETED
		or _automatic_tower_attempted_events.has(event.event_id)
	):
		return
	_automatic_tower_attempted_events[event.event_id] = true
	if (
		_building_manager == null
		or event.automatic_tower_definition == null
		or not event.automatic_tower_cell_set
	):
		automatic_tower_failed.emit(event, event.automatic_tower_cell)
		return
	var building := _building_manager.place_tutorial_tower(
		event.automatic_tower_cell,
		event.automatic_tower_definition,
		event.automatic_tower_facing_index
	)
	if building == null:
		automatic_tower_failed.emit(event, event.automatic_tower_cell)
		return
	automatic_tower_placed.emit(event, building)


func _is_trigger_satisfied(event: TutorialEventDefinition) -> bool:
	match event.trigger_kind:
		TutorialEventDefinitionScript.TriggerKind.LEVEL_TIME:
			return _level_elapsed >= event.trigger_delay_seconds
		TutorialEventDefinitionScript.TriggerKind.START:
			return true
		TutorialEventDefinitionScript.TriggerKind.WAVE_COMPLETED:
			return _wave_completion_times.has(event.trigger_wave_number) and _level_elapsed >= (
				float(_wave_completion_times[event.trigger_wave_number]) + event.trigger_delay_seconds
			)
		TutorialEventDefinitionScript.TriggerKind.EVENT_COMPLETED:
			return _event_completion_times.has(event.trigger_event_id) and _level_elapsed >= (
				float(_event_completion_times[event.trigger_event_id]) + event.trigger_delay_seconds
			)
	return false


func _evaluate_active_goals() -> void:
	if _definition == null:
		return
	for event in _definition.events:
		if event != null and get_event_state(event) == EventState.ACTIVE:
			_evaluate_goals_for_event(event)


func _evaluate_goals_for_event(event: TutorialEventDefinition) -> void:
	var states: Array = _goal_states.get(event.event_id, [])
	while states.size() < event.goals.size():
		states.append(false)
	var changed := false
	for index in range(event.goals.size()):
		if bool(states[index]):
			continue
		var goal := event.goals[index]
		if goal != null and _is_goal_satisfied(event, goal):
			states[index] = true
			changed = true
			goal_completed.emit(event, index)
	_goal_states[event.event_id] = states
	if not states.is_empty() and states.all(func(value: Variant) -> bool: return bool(value)):
		_event_states[event.event_id] = EventState.COMPLETED
		_event_completion_times[event.event_id] = _level_elapsed
		event_completed.emit(event)
		changed = true
		_evaluate_timeline()
	if changed:
		presentation_changed.emit()
		wave_gate_changed.emit()


func _is_goal_satisfied(event: TutorialEventDefinition, goal: TutorialGoalDefinition) -> bool:
	var baseline: Dictionary = _event_action_baselines.get(event.event_id, {})
	match goal.goal_type:
		TutorialGoalDefinitionScript.GoalType.ACKNOWLEDGE_ALL_BUBBLES:
			var acknowledged: Dictionary = _bubble_acknowledged.get(event.event_id, {})
			return event.bubbles.is_empty() or acknowledged.size() >= event.bubbles.size()
		TutorialGoalDefinitionScript.GoalType.BLANK_SCREEN_CLICKS:
			return _blank_click_count - int(baseline.get("blank_click_count", 0)) >= goal.required_count
		TutorialGoalDefinitionScript.GoalType.PLACE_BUILDING:
			return _has_matching_building_state(goal, false, int(baseline.get("building_action_count", 0)))
		TutorialGoalDefinitionScript.GoalType.UPGRADE_BUILDING:
			return _has_matching_building_state(goal, true, int(baseline.get("building_action_count", 0)))
		TutorialGoalDefinitionScript.GoalType.DELETE_BUILDING:
			return _count_matching_deleted_buildings(
				goal,
				int(baseline.get("deleted_action_count", 0))
			) >= goal.required_count
		TutorialGoalDefinitionScript.GoalType.RELEASE_WAVE:
			var released_before: Dictionary = baseline.get("released_waves", {})
			return _released_waves.has(goal.target_wave_number) and not released_before.has(goal.target_wave_number)
		TutorialGoalDefinitionScript.GoalType.COMPLETE_WAVE:
			var completed_before: Dictionary = baseline.get("completed_waves", {})
			return _completed_waves.has(goal.target_wave_number) and not completed_before.has(goal.target_wave_number)
	return false


func _has_matching_building_state(
	goal: TutorialGoalDefinition,
	require_level: bool,
	start_index: int
) -> bool:
	var first_index := clampi(start_index, 0, _building_state_ledger.size())
	if require_level:
		for index in range(first_index, _building_state_ledger.size()):
			var upgrade_snapshot: Dictionary = _building_state_ledger[index]
			if upgrade_snapshot.get("action") == &"upgraded" and _snapshot_matches_goal(upgrade_snapshot, goal, true):
				return true
		return false
	var placed_building_ids: Dictionary = {}
	for index in range(first_index, _building_state_ledger.size()):
		var snapshot: Dictionary = _building_state_ledger[index]
		var action: StringName = snapshot.get("action", &"")
		var building_id := int(snapshot.get("building_id", 0))
		if action == &"constructed" or action == &"relocated":
			placed_building_ids[building_id] = true
		if placed_building_ids.has(building_id) and _snapshot_matches_goal(snapshot, goal, false):
			return true
	return false


func _snapshot_matches_goal(snapshot: Dictionary, goal: TutorialGoalDefinition, require_level: bool) -> bool:
	var candidate_definition := snapshot.get("definition") as BuildingDefinition
	if goal.building_definition != null and (
		candidate_definition == null
		or candidate_definition.kind != goal.building_definition.kind
	):
		return false
	if goal.require_cell and snapshot.get("cell", Vector3i.ZERO) != goal.target_cell:
		return false
	if goal.require_facing and int(snapshot.get("facing", -1)) != goal.target_facing_index:
		return false
	if require_level and int(snapshot.get("level", 0)) < goal.target_level:
		return false
	return true


func _count_matching_deleted_buildings(goal: TutorialGoalDefinition, start_index: int) -> int:
	var count := 0
	for index in range(clampi(start_index, 0, _deleted_building_ledger.size()), _deleted_building_ledger.size()):
		var snapshot: Dictionary = _deleted_building_ledger[index]
		var candidate_definition := snapshot.get("definition") as BuildingDefinition
		if goal.building_definition != null and (
			candidate_definition == null
			or candidate_definition.kind != goal.building_definition.kind
		):
			continue
		if goal.require_cell and snapshot.get("cell", Vector3i.ZERO) != goal.target_cell:
			continue
		count += 1
	return count


func _record_building_state(building: Building, action: StringName) -> void:
	if building == null or not is_instance_valid(building):
		return
	_building_state_ledger.append({
		"action": action,
		"building_id": building.get_instance_id(),
		"definition": building.definition,
		"cell": building.cell,
		"facing": building.facing_index,
		"level": building.level,
	})
	_evaluate_active_goals()


func _on_building_state_changed(building: Building) -> void:
	_record_building_state(building, &"constructed")


func _on_building_relocated(building: Building, _previous_cell: Vector3i, _previous_edge_id: String) -> void:
	_record_building_state(building, &"relocated")


func _on_building_upgraded(building: Building, _previous_level: int, _new_level: int) -> void:
	_record_building_state(building, &"upgraded")


func _on_building_rotated(building: Building, _previous_facing: int, _new_facing: int) -> void:
	_record_building_state(building, &"rotated")


func _on_building_removed_by_player(building: Building) -> void:
	if building == null:
		return
	_deleted_building_ledger.append({
		"definition": building.definition,
		"cell": building.cell,
		"facing": building.facing_index,
		"level": building.level,
	})
	_evaluate_active_goals()


func _on_wave_released(wave_number: int, _wave: WaveDefinition) -> void:
	_released_waves[wave_number] = true
	_evaluate_active_goals()


func _on_wave_completed(wave_number: int) -> void:
	_completed_waves[wave_number] = true
	_wave_completion_times[wave_number] = _level_elapsed
	_evaluate_timeline()
	_evaluate_active_goals()


func _make_unique_event_id() -> StringName:
	var index := 1
	var known: Dictionary = {}
	if _definition != null:
		for event in _definition.events:
			if event != null:
				known[event.event_id] = true
	while known.has(StringName("tutorial_event_%02d" % index)):
		index += 1
	return StringName("tutorial_event_%02d" % index)


func _disconnect_sources() -> void:
	if _building_manager != null:
		if _building_manager.building_constructed.is_connected(_on_building_state_changed):
			_building_manager.building_constructed.disconnect(_on_building_state_changed)
		if _building_manager.building_relocated.is_connected(_on_building_relocated):
			_building_manager.building_relocated.disconnect(_on_building_relocated)
		if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
			_building_manager.building_upgraded.disconnect(_on_building_upgraded)
		if _building_manager.building_rotated_by_player.is_connected(_on_building_rotated):
			_building_manager.building_rotated_by_player.disconnect(_on_building_rotated)
		if _building_manager.building_removed_by_player.is_connected(_on_building_removed_by_player):
			_building_manager.building_removed_by_player.disconnect(_on_building_removed_by_player)
	if _wave_manager != null:
		if _wave_manager.wave_released.is_connected(_on_wave_released):
			_wave_manager.wave_released.disconnect(_on_wave_released)
		if _wave_manager.wave_completed.is_connected(_on_wave_completed):
			_wave_manager.wave_completed.disconnect(_on_wave_completed)
