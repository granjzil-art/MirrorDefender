@tool
## StuffPlacementData -- one authored Stuff instance on a Grid cell.
class_name StuffPlacementData
extends Resource

const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")

@export_group("Identity")
@export var placement_id: StringName = &"stuff_1"

@export_group("Placement")
@export var cell: Vector3i = Vector3i.ZERO
@export var definition: StuffDefinitionScript
## Hex levels accept 0..5; square levels accept 0..7.
@export_range(0, 7, 1) var facing_index: int = 0


func configure(
	p_placement_id: StringName,
	p_cell: Vector3i,
	p_definition: StuffDefinitionScript,
	p_facing_index: int = 0
) -> void:
	placement_id = p_placement_id
	cell = p_cell
	definition = p_definition
	facing_index = maxi(0, p_facing_index)
	emit_changed()


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if placement_id.is_empty():
		errors.append("关卡元素实例 ID 不能为空")
	if facing_index < 0 or facing_index > 7:
		errors.append("关卡元素朝向必须位于 0 到 7 之间")
	if definition == null:
		errors.append("关卡元素定义不能为空")
	return errors
