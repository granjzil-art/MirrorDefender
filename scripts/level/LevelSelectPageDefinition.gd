@tool
## Ordered definition for the four portal faces of one level-selection cube.
class_name LevelSelectPageDefinition
extends Resource

const SLOT_COUNT: int = 4

@export_group("Identity")
@export var display_name: String = ""

@export_group("Levels")
## Persist only lightweight resource paths. Keeping LevelResource references here
## pins every level dependency for the entire lifetime of AppRoot.
## Empty strings are intentional empty slots and preserve authored ordering.
@export var level_paths: PackedStringArray = PackedStringArray()

## Transient compatibility input for tests and runtime-created catalogs. This is
## deliberately not exported, so authored catalog resources cannot retain whole
## level graphs.
var levels: Array[LevelResource] = []


func get_level(slot_index: int) -> LevelResource:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return null
	if not levels.is_empty():
		return levels[slot_index] if slot_index < levels.size() else null
	var path := get_level_path(slot_index)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as LevelResource


func get_level_path(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return ""
	if not levels.is_empty():
		if slot_index >= levels.size() or levels[slot_index] == null:
			return ""
		return levels[slot_index].resource_path
	if slot_index >= level_paths.size():
		return ""
	return String(level_paths[slot_index]).strip_edges()


func get_configured_slot_count() -> int:
	return levels.size() if not levels.is_empty() else level_paths.size()


func get_level_reference_key(slot_index: int) -> String:
	if not levels.is_empty():
		if slot_index < 0 or slot_index >= levels.size() or levels[slot_index] == null:
			return ""
		var level := levels[slot_index]
		if not level.resource_path.is_empty():
			return "path:%s" % level.resource_path.simplify_path()
		return "instance:%d" % level.get_instance_id()
	var path := get_level_path(slot_index)
	return "" if path.is_empty() else "path:%s" % path.simplify_path()


func get_levels_for_slots() -> Array[LevelResource]:
	var result: Array[LevelResource] = []
	result.resize(SLOT_COUNT)
	for slot_index in range(mini(get_configured_slot_count(), SLOT_COUNT)):
		result[slot_index] = get_level(slot_index)
	return result


## Read-only validation. Empty slots are valid and are never compacted or filled.
func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	var slot_count := get_configured_slot_count()
	if slot_count > SLOT_COUNT:
		errors.append("每页最多只能配置 %d 个关卡槽位，当前为 %d 个" % [SLOT_COUNT, slot_count])
	var seen_levels: Dictionary = {}
	for slot_index in range(slot_count):
		var reference_key := get_level_reference_key(slot_index)
		if reference_key.is_empty():
			continue
		if seen_levels.has(reference_key):
			errors.append("第 %d 槽与第 %d 槽重复引用同一关卡" % [slot_index + 1, int(seen_levels[reference_key]) + 1])
		else:
			seen_levels[reference_key] = slot_index
		if not levels.is_empty():
			var level: LevelResource = levels[slot_index]
			for level_error in level.validate_runtime():
				errors.append("第 %d 槽关卡无效：%s" % [slot_index + 1, level_error])
			continue
		var path := get_level_path(slot_index)
		if not path.begins_with("res://") or not path.ends_with(".tres"):
			errors.append("第 %d 槽关卡路径必须是 res:// 下的 .tres 文件" % (slot_index + 1))
		elif not ResourceLoader.exists(path):
			errors.append("第 %d 槽关卡路径不存在：%s" % [slot_index + 1, path])
	return errors
