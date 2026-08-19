@tool
## Authored tutorial event captured on the live level timeline.
class_name TutorialEventDefinition
extends Resource

const TutorialBubbleDefinitionScript := preload("res://scripts/tutorial/TutorialBubbleDefinition.gd")
const TutorialGoalDefinitionScript := preload("res://scripts/tutorial/TutorialGoalDefinition.gd")

enum TriggerKind {
	LEVEL_TIME,
	START,
	WAVE_COMPLETED,
	EVENT_COMPLETED,
}

@export_group("Identity")
@export var event_id: StringName = &"tutorial_event"
@export var display_name: String = "教学事件"

@export_group("Timeline Trigger")
@export var trigger_kind: TriggerKind = TriggerKind.LEVEL_TIME
@export_range(0.0, 7200.0, 0.1, "or_greater") var trigger_delay_seconds: float = 0.0
@export_range(0, 999, 1) var trigger_wave_number: int = 0
@export var trigger_event_id: StringName = &""

@export_group("Content")
@export var bubbles: Array[TutorialBubbleDefinitionScript] = []
@export var goals: Array[TutorialGoalDefinitionScript] = []

@export_group("Wave Gate")
## Zero leaves waves unrestricted. Positive values block that authored wave until all goals latch.
@export_range(0, 999, 1) var gated_wave_number: int = 0

@export_group("Wave Completion Tower")
## Adds one free level-one tower when this wave-completed event activates.
@export var automatic_tower_enabled: bool = false
@export var automatic_tower_definition: BuildingDefinition
@export var automatic_tower_cell_set: bool = false
@export var automatic_tower_cell: Vector3i = Vector3i.ZERO
@export_range(0, 35, 1) var automatic_tower_facing_index: int = 0


func validate_configuration(total_waves: int, known_event_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if String(event_id).strip_edges().is_empty():
		errors.append("教学事件 ID 不能为空")
	if trigger_kind == TriggerKind.WAVE_COMPLETED:
		if trigger_wave_number < 1 or trigger_wave_number > total_waves:
			errors.append("教学事件 %s 的触发波次无效" % event_id)
	if trigger_kind == TriggerKind.EVENT_COMPLETED and (
		String(trigger_event_id).is_empty() or not known_event_ids.has(trigger_event_id)
	):
		errors.append("教学事件 %s 引用了不存在的前置事件" % event_id)
	if gated_wave_number < 0 or gated_wave_number > total_waves:
		errors.append("教学事件 %s 的门禁波次无效" % event_id)
	if automatic_tower_enabled:
		if trigger_kind != TriggerKind.WAVE_COMPLETED:
			errors.append("教学事件 %s 的自动建塔只能使用波次结束触发" % event_id)
		if automatic_tower_definition == null:
			errors.append("教学事件 %s 的自动建塔未选择塔" % event_id)
		elif automatic_tower_definition.is_defensive_structure() or automatic_tower_definition.is_edge_building():
			errors.append("教学事件 %s 的自动建塔只能选择普通塔" % event_id)
		if not automatic_tower_cell_set:
			errors.append("教学事件 %s 的自动建塔未选择地图格" % event_id)
	if goals.is_empty():
		errors.append("教学事件 %s 至少需要一个目标" % event_id)
	for bubble_index in range(bubbles.size()):
		var bubble := bubbles[bubble_index]
		if bubble == null:
			errors.append("教学事件 %s 的第 %d 个气泡为空" % [event_id, bubble_index + 1])
		else:
			for message in bubble.validate_configuration(goals):
				errors.append("教学事件 %s / 气泡 %d：%s" % [event_id, bubble_index + 1, message])
	for goal_index in range(goals.size()):
		var goal := goals[goal_index]
		if goal == null:
			errors.append("教学事件 %s 的第 %d 个目标为空" % [event_id, goal_index + 1])
			continue
		for message in goal.validate_configuration():
			errors.append("教学事件 %s / 目标 %d：%s" % [event_id, goal_index + 1, message])
		if (
			goal.goal_type == TutorialGoalDefinitionScript.GoalType.RELEASE_WAVE
			and goal.target_wave_number == gated_wave_number
		):
			errors.append("教学事件 %s 不能用释放第 %d 波的目标锁住同一波" % [event_id, gated_wave_number])
	return errors
