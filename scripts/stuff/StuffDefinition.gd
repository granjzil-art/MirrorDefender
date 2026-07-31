@tool
## StuffDefinition -- reusable definition for an object placed above Grid.
##
## Stuff may own effects and placement restrictions but never changes terrain
## identity, voxel layer count, or authored path membership.
class_name StuffDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")
const ModelAssetDefinitionScript := preload("res://scripts/presentation/ModelAssetDefinition.gd")
const TileEffectScript := preload("res://scripts/tile/effects/TileEffect.gd")

enum FallbackVisualKind {
	NONE,
	GENERIC_OBSTACLE,
	SPIKES,
	HOLE,
	ROCK,
	TREE,
}

@export_group("Identity")
@export var stuff_id: StringName = &"stuff"
@export var display_name: String = "关卡元素"

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Placement")
## Coexistence is allowed only when both definitions disable exclusivity.
@export var exclusive_with_other_stuff: bool = true
@export var blocks_tile_building: bool = true
@export var blocks_edge_building: bool = false

@export_group("Gameplay")
@export var effect: TileEffectScript

@export_group("Presentation")
@export var ui_icon: Texture2D
@export_enum("无", "通用障碍", "尖刺", "空洞", "岩石", "树") var fallback_visual_kind: int = FallbackVisualKind.NONE
@export var fallback_color: Color = Color(0.2, 0.2, 0.2, 1.0)
@export var model_asset: ModelAssetDefinitionScript

## Serialized compatibility for old element resources using visual_scene.
@export_storage var visual_scene: PackedScene


func can_coexist_with(other: Resource) -> bool:
	var other_exclusive: Variant = other.get("exclusive_with_other_stuff") if other != null else null
	return (
		other_exclusive is bool
		and not exclusive_with_other_stuff
		and not bool(other_exclusive)
	)


func get_model_asset() -> ModelAssetDefinitionScript:
	if model_asset != null:
		return model_asset
	if visual_scene == null:
		return null
	var legacy_asset := ModelAssetDefinitionScript.new()
	legacy_asset.scene = visual_scene
	return legacy_asset


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if stuff_id.is_empty():
		errors.append("关卡元素 ID 不能为空")
	if display_name.strip_edges().is_empty():
		errors.append("关卡元素显示名不能为空")
	if fallback_visual_kind < FallbackVisualKind.NONE or fallback_visual_kind > FallbackVisualKind.TREE:
		errors.append("关卡元素灰盒类型无效")
	ConfigValidator.require_color(errors, "关卡元素灰盒颜色", fallback_color)
	if effect != null:
		ConfigValidator.append_prefixed(errors, "效果", effect.validate_configuration())
	var effective_model_asset := get_model_asset()
	if effective_model_asset != null:
		ConfigValidator.append_prefixed(errors, "模型", effective_model_asset.validate_configuration())
	return errors
