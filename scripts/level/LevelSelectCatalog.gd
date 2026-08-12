@tool
## Ordered catalog of level-selection pages.
class_name LevelSelectCatalog
extends Resource

const LevelSelectPageDefinitionScript := preload("res://scripts/level/LevelSelectPageDefinition.gd")

@export_group("Pages")
@export var pages: Array[LevelSelectPageDefinitionScript] = []


func get_page_count() -> int:
	return pages.size()


func get_page(page_index: int) -> LevelSelectPageDefinitionScript:
	if page_index < 0 or page_index >= pages.size():
		return null
	return pages[page_index]


## Read-only validation. It reports catalog/page errors without rewriting arrays.
func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if pages.is_empty():
		errors.append("选关目录至少需要配置一页")
	var seen_pages: Dictionary = {}
	var seen_levels: Dictionary = {}
	for page_index in range(pages.size()):
		var page: LevelSelectPageDefinitionScript = pages[page_index]
		if page == null:
			errors.append("第 %d 页引用为空" % (page_index + 1))
			continue
		var page_instance_id := page.get_instance_id()
		if seen_pages.has(page_instance_id):
			errors.append("第 %d 页与第 %d 页重复引用同一页面" % [page_index + 1, int(seen_pages[page_instance_id]) + 1])
		else:
			seen_pages[page_instance_id] = page_index
		for page_error in page.validate_configuration():
			errors.append("第 %d 页：%s" % [page_index + 1, page_error])
		for slot_index in range(page.get_configured_slot_count()):
			var level_key := page.get_level_reference_key(slot_index)
			if level_key.is_empty():
				continue
			if seen_levels.has(level_key):
				var first_location: Vector2i = seen_levels[level_key]
				if first_location.x != page_index:
					errors.append(
						"第 %d 页第 %d 槽与第 %d 页第 %d 槽重复引用同一关卡" % [
							page_index + 1,
							slot_index + 1,
							first_location.x + 1,
							first_location.y + 1,
						]
					)
			else:
				seen_levels[level_key] = Vector2i(page_index, slot_index)
	return errors
