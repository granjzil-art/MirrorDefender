@tool
## One latched tutorial objective. Every objective in an event must complete.
class_name TutorialGoalDefinition
extends Resource

enum GoalType {
	ACKNOWLEDGE_ALL_BUBBLES,
	BLANK_SCREEN_CLICKS,
	PLACE_BUILDING,
	UPGRADE_BUILDING,
	DELETE_BUILDING,
	RELEASE_WAVE,
	COMPLETE_WAVE,
}

@export_group("Display")
@export var goal_type: GoalType = GoalType.ACKNOWLEDGE_ALL_BUBBLES
@export_multiline var description: String = ""
@export var show_in_checklist: bool = true

@export_group("Building Target")
@export var building_definition: BuildingDefinition
@export var require_cell: bool = false
@export var target_cell: Vector3i = Vector3i.ZERO
@export var require_facing: bool = false
@export_range(0, 35, 1) var target_facing_index: int = 0
@export_range(1, BuildingDefinition.MAX_LEVEL, 1) var target_level: int = 2

@export_group("Count / Wave")
@export_range(1, 99, 1) var required_count: int = 1
@export_range(1, 999, 1) var target_wave_number: int = 1


func get_display_description() -> String:
	var authored := description.strip_edges()
	if not authored.is_empty():
		return authored
	match goal_type:
		GoalType.ACKNOWLEDGE_ALL_BUBBLES:
			return "查看全部教学气泡"
		GoalType.BLANK_SCREEN_CLICKS:
			return "点击屏幕空白处 %d 次" % required_count
		GoalType.PLACE_BUILDING:
			var name := building_definition.display_name if building_definition != null else "指定建筑"
			if require_cell and require_facing:
				return "在 %s 放置%s并调整至朝向 %d" % [str(target_cell), name, target_facing_index]
			if require_cell:
				return "在 %s 放置%s" % [str(target_cell), name]
			return "放置%s" % name
		GoalType.UPGRADE_BUILDING:
			return "将%s升级至 %d 级" % [
				building_definition.display_name if building_definition != null else "指定建筑",
				target_level,
			]
		GoalType.DELETE_BUILDING:
			return "删除%s" % (
				building_definition.display_name if building_definition != null else "一座建筑"
			)
		GoalType.RELEASE_WAVE:
			return "释放第 %d 波" % target_wave_number
		GoalType.COMPLETE_WAVE:
			return "完成第 %d 波" % target_wave_number
	return "完成教学目标"


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if required_count < 1:
		errors.append("教学目标次数必须至少为 1")
	if goal_type == GoalType.PLACE_BUILDING and building_definition == null:
		errors.append("放置目标必须选择建筑")
	if goal_type == GoalType.UPGRADE_BUILDING:
		if building_definition == null:
			errors.append("升级目标必须选择建筑")
		elif target_level < 1 or target_level > building_definition.get_max_level():
			errors.append("升级目标等级超出建筑上限")
	if (
		goal_type == GoalType.RELEASE_WAVE
		or goal_type == GoalType.COMPLETE_WAVE
	) and target_wave_number < 1:
		errors.append("波次目标必须指定正数波次")
	return errors


func matches_building(building: Building, require_level: bool = false) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if building_definition != null and (
		building.definition == null
		or building.definition.kind != building_definition.kind
	):
		return false
	if require_cell and building.cell != target_cell:
		return false
	if require_facing and building.facing_index != target_facing_index:
		return false
	if require_level and building.level < target_level:
		return false
	return true
