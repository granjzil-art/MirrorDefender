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

## FOLLOW_EFFECT keeps older authored Stuff resources behavior-compatible.
## Newly created definitions should explicitly choose PASSABLE or BLOCKED so
## navigation is owned by StuffDefinition rather than inferred by the effect.
enum EnemyNavigation {
	FOLLOW_EFFECT,
	PASSABLE,
	BLOCKED,
}

## FOLLOW_EFFECT preserves legacy effect-owned durability. New catalog entries
## choose an explicit value so an element does not need a custom effect merely
## to be destructible or indestructible.
enum DurabilityMode {
	FOLLOW_EFFECT,
	INDESTRUCTIBLE,
	DESTRUCTIBLE,
}

@export_group("Identity")
@export var stuff_id: StringName = &"stuff"
@export var display_name: String = "关卡元素"
@export_multiline var description: String = ""

@export_group("Catalog")
@export var authoring_enabled: bool = true

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Placement")
## Coexistence is allowed only when both definitions disable exclusivity.
@export var exclusive_with_other_stuff: bool = true
@export var blocks_tile_building: bool = true
@export var blocks_edge_building: bool = false

@export_group("Navigation")
@export_enum("兼容旧效果", "不堵路", "堵路") var enemy_navigation: int = EnemyNavigation.FOLLOW_EFFECT
## Only used when enemy_navigation is explicitly BLOCKED.
@export var navigation_affects_airborne: bool = false

@export_group("Gameplay")
@export var effect: TileEffectScript

@export_group("Durability")
@export_enum("兼容旧效果", "不可破坏", "可破坏") var durability_mode: int = DurabilityMode.FOLLOW_EFFECT
@export_range(1.0, 1000000.0, 1.0, "or_greater") var max_durability: float = 100.0

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


func blocks_enemy_navigation(target: Node = null) -> bool:
	match enemy_navigation:
		EnemyNavigation.PASSABLE:
			return false
		EnemyNavigation.BLOCKED:
			return _navigation_affects_target(target)
		_:
			return effect != null and effect.blocks_enemy_navigation(target)


func can_use_for_reroute(target: Node = null) -> bool:
	return not blocks_enemy_navigation(target)


func get_max_durability() -> float:
	match durability_mode:
		DurabilityMode.INDESTRUCTIBLE:
			return 0.0
		DurabilityMode.DESTRUCTIBLE:
			return maxf(1.0, max_durability)
		_:
			return (
				maxf(1.0, effect.get_max_durability())
				if effect != null and effect.creates_runtime_obstacle()
				else 0.0
			)


func navigation_affects_target(target: Node) -> bool:
	if enemy_navigation == EnemyNavigation.FOLLOW_EFFECT:
		return effect != null and effect.affects_target(target)
	return _navigation_affects_target(target)


func _navigation_affects_target(target: Node) -> bool:
	if navigation_affects_airborne or target == null or not is_instance_valid(target):
		return true
	if not target.has_method("is_airborne_unit"):
		return true
	return not bool(target.call("is_airborne_unit"))


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if stuff_id.is_empty():
		errors.append("关卡元素 ID 不能为空")
	elif not _has_valid_id_characters(String(stuff_id)):
		errors.append("关卡元素 ID 只能包含小写英文字母、数字和下划线")
	if display_name.strip_edges().is_empty():
		errors.append("关卡元素显示名不能为空")
	if fallback_visual_kind < FallbackVisualKind.NONE or fallback_visual_kind > FallbackVisualKind.TREE:
		errors.append("关卡元素灰盒类型无效")
	if enemy_navigation < EnemyNavigation.FOLLOW_EFFECT or enemy_navigation > EnemyNavigation.BLOCKED:
		errors.append("关卡元素敌人通行配置无效")
	if durability_mode < DurabilityMode.FOLLOW_EFFECT or durability_mode > DurabilityMode.DESTRUCTIBLE:
		errors.append("关卡元素耐久配置无效")
	if durability_mode == DurabilityMode.DESTRUCTIBLE:
		ConfigValidator.require_number(errors, "关卡元素最大耐久", max_durability, 0.0, INF, false)
	ConfigValidator.require_color(errors, "关卡元素灰盒颜色", fallback_color)
	if effect != null:
		ConfigValidator.append_prefixed(errors, "效果", effect.validate_configuration())
	var effective_model_asset := get_model_asset()
	if effective_model_asset != null:
		ConfigValidator.append_prefixed(errors, "模型", effective_model_asset.validate_configuration())
	return errors


func _has_valid_id_characters(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true
