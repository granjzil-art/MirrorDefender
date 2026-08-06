@tool
## Explicit authoring/runtime registry for every available StuffDefinition.
## Array order is the palette order; disabled definitions stay reference-safe
## for existing levels but are hidden from creation palettes.
class_name StuffCatalog
extends Resource

const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")

@export_group("Definitions")
@export var definitions: Array[StuffDefinitionScript] = []


func get_enabled_definitions() -> Array[StuffDefinitionScript]:
	var result: Array[StuffDefinitionScript] = []
	for definition in definitions:
		if definition != null and definition.authoring_enabled:
			result.append(definition)
	return result


func get_definition(stuff_id: StringName, include_disabled: bool = false) -> StuffDefinitionScript:
	for definition in definitions:
		if definition == null or definition.stuff_id != stuff_id:
			continue
		if include_disabled or definition.authoring_enabled:
			return definition
	return null


func contains_definition(definition: StuffDefinitionScript) -> bool:
	return definition != null and definition in definitions


func add_definition(definition: StuffDefinitionScript) -> bool:
	if definition == null or contains_definition(definition):
		return false
	if get_definition(definition.stuff_id, true) != null:
		return false
	definitions.append(definition)
	emit_changed()
	return true


func remove_definition(definition: StuffDefinitionScript) -> bool:
	var index := definitions.find(definition)
	if index < 0:
		return false
	definitions.remove_at(index)
	emit_changed()
	return true


func move_definition(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= definitions.size():
		return false
	var resolved_to := clampi(to_index, 0, definitions.size() - 1)
	if from_index == resolved_to:
		return false
	var definition := definitions[from_index]
	definitions.remove_at(from_index)
	definitions.insert(resolved_to, definition)
	emit_changed()
	return true


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for index in range(definitions.size()):
		var definition := definitions[index]
		if definition == null:
			errors.append("关卡元素目录第 %d 项为空" % (index + 1))
			continue
		if ids.has(definition.stuff_id):
			errors.append("关卡元素目录 ID 重复：%s" % definition.stuff_id)
		else:
			ids[definition.stuff_id] = true
		for error in definition.validate_configuration():
			errors.append("%s：%s" % [definition.display_name, error])
	return errors
