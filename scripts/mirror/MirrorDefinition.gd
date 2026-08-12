@tool
## Shared data contract for every physical edge mirror.
class_name MirrorDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")
const DEFAULT_FUNCTION_DESCRIPTION := "暂未配置说明文本。"

@export_group("Identity")
@export var display_name: String = "镜子"
## Optional transparent mirror artwork. BuildCardBar generates the card surface,
## frame, title and cooldown presentation around it.
@export var card_icon: Texture2D

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Placement Cooldown")
@export_range(0.0, 300.0, 0.1, "or_greater") var placement_cooldown_seconds: float = 15.0

@export_group("Placement Economy")
## Used when MirrorManager.placement_cooldown_enabled is false.
@export_range(0.0, 100000.0, 1.0, "or_greater") var placement_cost: float = 100.0

@export_group("Upgrade")
## Costs paid when advancing 1 -> 2 and 2 -> 3.
@export var upgrade_costs: Array[float] = [50.0, 50.0]
## Level-indexed combat modifiers. Concrete mirror definitions provide their
## own defaults while keeping every value editable in the resource inspector.
@export var level_damage_multipliers: Array[float] = [1.0, 1.0, 1.0]
@export var level_penetration_bonuses: Array[int] = [0, 0, 0]

@export_group("Placement")
@export var active_from_side_by_default: bool = true

@export_group("Mirror Visual")
@export var mirror_color: Color = Color(0.2, 0.78, 1.0, 0.92)
@export_range(0.02, 0.5, 0.01) var mirror_thickness_ratio: float = 0.08
@export_range(0.1, 2.0, 0.01) var mirror_height_ratio: float = 1.20
@export var reflection_enabled: bool = true
## Presentation-only two-sided observation. Gameplay always uses active_from_side.
@export var reflection_two_sided_visual: bool = true
@export_range(0.52, 1.5, 0.01) var reflection_surface_offset_ratio: float = 0.78
@export_range(64, 1024, 64) var reflection_resolution: int = 256
@export_range(64, 512, 64) var reflection_preview_resolution: int = 128
@export_range(1, 12, 1) var reflection_update_interval_frames: int = 4
@export_range(1, 6, 1) var reflection_max_updates_per_frame: int = 1
@export_range(0.0, 1.0, 0.01) var mirror_reflectivity: float = 0.92
@export var mirror_surface_tint: Color = Color(0.80, 0.94, 1.0, 1.0)
@export var mirror_back_face_color: Color = Color(0.24, 0.25, 0.27, 1.0)
@export var invalid_preview_color: Color = Color(1.0, 0.06, 0.06, 0.92)

const MAX_LEVEL: int = 3


func get_max_level() -> int:
	return MAX_LEVEL


func get_upgrade_cost(current_level: int) -> float:
	if current_level < 1 or current_level >= MAX_LEVEL:
		return 0.0
	var index := current_level - 1
	return maxf(0.0, upgrade_costs[index]) if index < upgrade_costs.size() else 0.0


func get_damage_multiplier(level: int) -> float:
	var index := clampi(level, 1, MAX_LEVEL) - 1
	return maxf(0.0, level_damage_multipliers[index]) if index < level_damage_multipliers.size() else 1.0


func get_penetration_bonus(level: int) -> int:
	var index := clampi(level, 1, MAX_LEVEL) - 1
	return maxi(0, level_penetration_bonuses[index]) if index < level_penetration_bonuses.size() else 0


func get_resolved_inspection_display_name() -> String:
	if inspection_display != null:
		return inspection_display.resolve_display_name(display_name)
	return display_name


func get_formatted_inspection_description() -> String:
	if inspection_display != null:
		return inspection_display.format_level_description(DEFAULT_FUNCTION_DESCRIPTION)
	return "\n".join([
		DEFAULT_FUNCTION_DESCRIPTION,
		"1级： ",
		"2级： ",
		"3级： ",
	])


func get_formatted_inspection_description_bbcode() -> String:
	if inspection_display != null:
		return inspection_display.format_level_description_bbcode(DEFAULT_FUNCTION_DESCRIPTION)
	var fallback_config := InspectionDisplayConfigScript.new()
	return fallback_config.format_level_description_bbcode(DEFAULT_FUNCTION_DESCRIPTION)


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if upgrade_costs.size() != MAX_LEVEL - 1:
		errors.append("镜子升级费用必须配置二级和三级两项")
	else:
		for index in range(upgrade_costs.size()):
			ConfigValidator.require_number(errors, "镜子升级费用%d" % (index + 2), upgrade_costs[index], 0.0)
	if level_damage_multipliers.size() != MAX_LEVEL:
		errors.append("镜子伤害倍率必须配置三级")
	else:
		for index in range(level_damage_multipliers.size()):
			ConfigValidator.require_number(errors, "镜子%d级伤害倍率" % (index + 1), level_damage_multipliers[index], 0.0)
	if level_penetration_bonuses.size() != MAX_LEVEL:
		errors.append("镜子穿透加成必须配置三级")
	else:
		for index in range(level_penetration_bonuses.size()):
			if level_penetration_bonuses[index] < 0:
				errors.append("镜子%d级穿透加成不能小于零" % (index + 1))
	ConfigValidator.require_text(errors, "镜子显示名", display_name)
	ConfigValidator.require_number(errors, "镜子放置冷却", placement_cooldown_seconds, 0.0)
	ConfigValidator.require_number(errors, "镜子放置费用", placement_cost, 0.0)
	ConfigValidator.require_color(errors, "镜体颜色", mirror_color)
	ConfigValidator.require_number(errors, "镜体厚度比例", mirror_thickness_ratio, 0.02, 0.5)
	ConfigValidator.require_number(errors, "镜体高度比例", mirror_height_ratio, 0.1, 2.0)
	ConfigValidator.require_number(errors, "镜面外推比例", reflection_surface_offset_ratio, 0.5, 1.5, false)
	ConfigValidator.require_integer_range(errors, "镜面分辨率", reflection_resolution, 64, 1024)
	ConfigValidator.require_integer_range(errors, "预览分辨率", reflection_preview_resolution, 64, 512)
	ConfigValidator.require_integer_range(errors, "镜面更新间隔", reflection_update_interval_frames, 1, 12)
	ConfigValidator.require_integer_range(errors, "每帧镜面更新上限", reflection_max_updates_per_frame, 1, 6)
	ConfigValidator.require_number(errors, "镜面反射率", mirror_reflectivity, 0.0, 1.0)
	ConfigValidator.require_color(errors, "镜面染色", mirror_surface_tint)
	ConfigValidator.require_color(errors, "镜面背面颜色", mirror_back_face_color)
	ConfigValidator.require_color(errors, "无效放置预览颜色", invalid_preview_color)
	return errors
