@tool
## Ordered definition for one fixed six-slot level-selection page.
class_name LevelSelectPageDefinition
extends Resource

const SLOT_COUNT: int = 6

@export_group("Identity")
@export var display_name: String = ""

@export_group("Levels")
## Null entries are intentional empty slots and preserve authored ordering.
@export var levels: Array[LevelResource] = []


func get_level(slot_index: int) -> LevelResource:
	if slot_index < 0 or slot_index >= SLOT_COUNT or slot_index >= levels.size():
		return null
	return levels[slot_index]


func get_levels_for_slots() -> Array[LevelResource]:
	var result: Array[LevelResource] = []
	result.resize(SLOT_COUNT)
	for slot_index in range(mini(levels.size(), SLOT_COUNT)):
		result[slot_index] = levels[slot_index]
	return result


## Read-only validation. Empty slots are valid and are never compacted or filled.
func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if levels.size() > SLOT_COUNT:
		errors.append("每页最多只能配置 %d 个关卡槽位，当前为 %d 个" % [SLOT_COUNT, levels.size()])
	var seen_levels: Dictionary = {}
	for slot_index in range(levels.size()):
		var level: LevelResource = levels[slot_index]
		if level == null:
			continue
		var instance_id := level.get_instance_id()
		if seen_levels.has(instance_id):
			errors.append("第 %d 槽与第 %d 槽重复引用同一关卡" % [slot_index + 1, int(seen_levels[instance_id]) + 1])
		else:
			seen_levels[instance_id] = slot_index
		for level_error in level.validate_runtime():
			errors.append("第 %d 槽关卡无效：%s" % [slot_index + 1, level_error])
	return errors
