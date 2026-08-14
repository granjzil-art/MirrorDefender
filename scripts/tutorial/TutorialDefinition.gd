@tool
## Level-owned tutorial timeline authored and previewed in the running game.
class_name TutorialDefinition
extends Resource

const TutorialEventDefinitionScript := preload("res://scripts/tutorial/TutorialEventDefinition.gd")

@export var enabled: bool = true
@export var events: Array[TutorialEventDefinitionScript] = []


func validate_configuration(total_waves: int) -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for index in range(events.size()):
		var event := events[index]
		if event == null:
			errors.append("教学时间轴第 %d 项为空" % (index + 1))
			continue
		if ids.has(event.event_id):
			errors.append("教学事件 ID 重复：%s" % event.event_id)
		else:
			ids[event.event_id] = true
	for event in events:
		if event == null:
			continue
		errors.append_array(event.validate_configuration(total_waves, ids))
	return errors
