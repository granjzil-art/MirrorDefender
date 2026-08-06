@tool
## Serialized initial placement for one real runtime Building.
class_name BuildingPlacementData
extends Resource

const BuildingDefinitionScript := preload("res://scripts/building/BuildingDefinition.gd")

@export_group("Placement")
@export var definition: BuildingDefinitionScript
@export var cell: Vector3i = Vector3i.ZERO
## Logical tile-building facing. Edge buildings derive their facing from edge_index.
@export_range(0, 35, 1) var facing_index: int = 0
## -1 for tile buildings; 0..5 for edge buildings, with square levels using 0..3.
@export_range(-1, 5, 1) var edge_index: int = -1
@export_range(1, BuildingDefinitionScript.MAX_LEVEL, 1) var level: int = 1


func configure(
	p_definition: BuildingDefinitionScript,
	p_cell: Vector3i,
	p_facing_index: int = 0,
	p_edge_index: int = -1,
	p_level: int = 1
) -> void:
	definition = p_definition
	cell = p_cell
	facing_index = maxi(0, p_facing_index)
	edge_index = p_edge_index
	level = clampi(p_level, 1, BuildingDefinitionScript.MAX_LEVEL)
	emit_changed()


func is_edge_placement() -> bool:
	return definition != null and definition.is_edge_building()


func duplicate_placement() -> BuildingPlacementData:
	var clone := BuildingPlacementData.new()
	clone.configure(definition, cell, facing_index, edge_index, level)
	return clone


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if definition == null:
		errors.append("建筑定义不能为空")
		return errors
	if level < 1 or level > definition.get_max_level():
		errors.append("建筑等级必须位于 1 到 %d 之间" % definition.get_max_level())
	if is_edge_placement() and edge_index < 0:
		errors.append("边建筑必须配置边方向")
	elif not is_edge_placement() and edge_index != -1:
		errors.append("块建筑不能配置边方向")
	if facing_index < 0 or facing_index > 35:
		errors.append("建筑朝向必须位于 0 到 35 之间")
	return errors
