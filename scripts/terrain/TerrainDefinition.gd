@tool
## TerrainDefinition -- reusable visual identity for a Grid cell surface.
##
## Terrain never owns build permissions, authored paths, Stuff, or occupancy.
class_name TerrainDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

@export_group("Identity")
@export var terrain_id: StringName = &"grass"
@export var display_name: String = "草地"

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Presentation")
@export var ui_icon: Texture2D
@export var fallback_color: Color = Color(0.18, 0.60, 0.31, 1.0)
## One authored voxel block. Runtime stacking is owned by TerrainRenderer.
@export var flat_model_asset: ModelAssetDefinition
## Full-width ramp assets. A 1:N asset spans N consecutive Grid cells.
@export var ramp_1_to_1_model_asset: ModelAssetDefinition
@export var ramp_1_to_2_model_asset: ModelAssetDefinition
@export var ramp_1_to_3_model_asset: ModelAssetDefinition
@export var ramp_1_to_4_model_asset: ModelAssetDefinition


func get_ramp_model_asset(run_length: int) -> ModelAssetDefinition:
	match run_length:
		1:
			return ramp_1_to_1_model_asset
		2:
			return ramp_1_to_2_model_asset
		3:
			return ramp_1_to_3_model_asset
		4:
			return ramp_1_to_4_model_asset
	return null


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if terrain_id.is_empty():
		errors.append("地形 ID 不能为空")
	if display_name.strip_edges().is_empty():
		errors.append("地形显示名不能为空")
	ConfigValidator.require_color(errors, "地形灰盒颜色", fallback_color)
	_validate_model_asset(errors, "平地模型", flat_model_asset)
	_validate_model_asset(errors, "1:1 斜坡模型", ramp_1_to_1_model_asset)
	_validate_model_asset(errors, "1:2 斜坡模型", ramp_1_to_2_model_asset)
	_validate_model_asset(errors, "1:3 斜坡模型", ramp_1_to_3_model_asset)
	_validate_model_asset(errors, "1:4 斜坡模型", ramp_1_to_4_model_asset)
	return errors


func _validate_model_asset(
	errors: Array[String],
	label: String,
	model_asset: ModelAssetDefinition
) -> void:
	if model_asset != null:
		ConfigValidator.append_prefixed(errors, label, model_asset.validate_configuration())
