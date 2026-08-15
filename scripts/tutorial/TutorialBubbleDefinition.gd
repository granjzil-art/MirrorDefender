@tool
## One authored thought bubble shown by a tutorial event.
class_name TutorialBubbleDefinition
extends Resource

enum AnchorKind {
	SCREEN,
	WORLD_CELL,
}

enum DismissCondition {
	ACKNOWLEDGED,
	GOAL_COMPLETED,
	EVENT_COMPLETED,
	PERSISTENT,
}

enum FlowStrength {
	OFF,
	LIGHT,
	STRONG,
}

@export_group("Content")
@export_multiline var text: String = "在这里输入教学说明。"

@export_group("Placement")
@export var anchor_kind: AnchorKind = AnchorKind.SCREEN
## Top-left viewport position used by screen bubbles and by the runtime authoring preview.
@export var screen_position: Vector2 = Vector2(360.0, 220.0)
@export var world_cell: Vector3i = Vector3i.ZERO
@export_range(-10.0, 20.0, 0.05) var world_height_offset: float = 1.25
## Screen-space offset from the projected target, used by world-cell bubbles.
@export var offset: Vector2 = Vector2.ZERO
@export_range(180.0, 720.0, 1.0) var maximum_width: float = 420.0

@export_group("Behaviour")
@export var dismiss_condition: DismissCondition = DismissCondition.ACKNOWLEDGED
## Used only by GOAL_COMPLETED. Zero-based index into the owning event's goals.
@export_range(-1, 64, 1) var associated_goal_index: int = -1
@export var flow_strength: FlowStrength = FlowStrength.LIGHT


func validate_configuration(goals: Array) -> Array[String]:
	var errors: Array[String] = []
	var goal_count := goals.size()
	if text.strip_edges().is_empty():
		errors.append("气泡文本不能为空")
	if not is_finite(maximum_width) or maximum_width < 180.0:
		errors.append("气泡最大宽度必须至少为 180")
	if dismiss_condition == DismissCondition.GOAL_COMPLETED and (
		associated_goal_index < 0 or associated_goal_index >= goal_count
	):
		errors.append("按目标消失的气泡必须绑定有效目标")
	elif dismiss_condition == DismissCondition.GOAL_COMPLETED:
		var associated_goal: Resource = goals[associated_goal_index]
		if associated_goal == null or int(associated_goal.get("goal_type")) == 0:
			errors.append("按目标消失的气泡不能关联“查看全部教学气泡”目标")
	return errors
