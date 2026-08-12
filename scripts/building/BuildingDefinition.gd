## Data-only definition for one constructible M3 building type.
class_name BuildingDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

const MAX_LEVEL := 3
const DEFAULT_FUNCTION_DESCRIPTION := "暂未配置说明文本。"

enum Kind {
	ARROW_TOWER,
	LASER_TOWER,
	BARRIER,
	EDGE_BARRIER,
	CROSSBOW_TOWER,
	MACE_TOWER,
	PULSE_LASER_TOWER,
}

enum PlacementSurface {
	BUILDABLE_TILE,
	PATH_TILE,
	PATH_EDGE,
}

enum AimMode {
	FIXED_FACING,
	TRACK_TARGET,
}

@export_group("Identity")
@export var kind: Kind = Kind.ARROW_TOWER
@export var display_name: String = "箭塔"
## Optional transparent building artwork. BuildCardBar generates the mirror,
## frame, title, cost and interaction states around it.
@export var card_icon: Texture2D
## Optional finished card artwork for BuildCardBar's full-artwork mode. The
## texture may contain transparent padding; the card bar trims it at runtime.
## Keep the cost out of this texture because the HUD overlays live level-1 cost.
@export var full_card_art: Texture2D

@export_group("Runtime Inspector")
@export var inspection_display: InspectionDisplayConfigScript

@export_group("Placement")
@export var placement_surface: PlacementSurface = PlacementSurface.BUILDABLE_TILE
## Edge buildings block both traversal directions by default. Disable this only
## for future one-way variants; tile buildings ignore the setting.
@export var blocks_both_directions: bool = true

@export_group("Orientation")
## TRACK_TARGET rotates only the visual pose toward the acquired target.
## FIXED_FACING keeps attacks and visuals on the manually selected facing.
@export var aim_mode: AimMode = AimMode.FIXED_FACING
@export_range(1.0, 2160.0, 1.0, "or_greater") var visual_turn_speed_degrees: float = 720.0

@export_group("Levels")
@export var levels: Array[BuildingLevelStats] = []

@export_group("Pulse Laser")
## Legacy root-level value retained for old resources. Runtime combat tuning and
## new content use BuildingLevelStats.pulse_laser_reflect_max per level.
@export_range(0, 64, 1) var pulse_laser_reflect_max: int = 8
@export var pulse_laser_reflection_colors: Array[Color] = [
	Color(1.0, 0.08, 0.04, 1.0),
	Color(1.0, 0.36, 0.03, 1.0),
	Color(1.0, 0.88, 0.04, 1.0),
	Color(0.16, 1.0, 0.20, 1.0),
	Color(0.02, 0.92, 1.0, 1.0),
	Color(0.10, 0.34, 1.0, 1.0),
	Color(0.62, 0.12, 1.0, 1.0),
]

func get_level_stats(value: int) -> BuildingLevelStats:
	if levels.is_empty():
		return null
	var index := clampi(value, 1, get_max_level()) - 1
	return levels[index]

## Level 1 is the construction cost; every later entry is the cost paid to
## reach that level. Active demolition returns this full cumulative amount.
func get_cumulative_cost(value: int) -> float:
	var resolved_level := clampi(value, 0, get_max_level())
	var cumulative_cost: float = 0.0
	for index in range(resolved_level):
		var stats := levels[index]
		if stats != null:
			cumulative_cost += stats.cost
	return cumulative_cost

func get_max_level() -> int:
	return mini(MAX_LEVEL, levels.size())


func get_resolved_inspection_display_name() -> String:
	if inspection_display != null:
		return inspection_display.resolve_display_name(display_name)
	return display_name


func get_formatted_inspection_description() -> String:
	if inspection_display != null:
		return inspection_display.format_building_description(DEFAULT_FUNCTION_DESCRIPTION)
	return "\n".join([
		DEFAULT_FUNCTION_DESCRIPTION,
		"1级： ",
		"2级： ",
		"3级： ",
	])


func get_formatted_inspection_description_bbcode() -> String:
	if inspection_display != null:
		return inspection_display.format_building_description_bbcode(DEFAULT_FUNCTION_DESCRIPTION)
	var fallback_config := InspectionDisplayConfigScript.new()
	return fallback_config.format_building_description_bbcode(DEFAULT_FUNCTION_DESCRIPTION)

func is_configured() -> bool:
	return validate_configuration().is_empty()

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "建筑显示名", display_name)
	ConfigValidator.require_integer_range(errors, "建筑类型", kind, Kind.ARROW_TOWER, Kind.PULSE_LASER_TOWER)
	ConfigValidator.require_integer_range(
		errors,
		"放置表面",
		placement_surface,
		PlacementSurface.BUILDABLE_TILE,
		PlacementSurface.PATH_EDGE
	)
	ConfigValidator.require_integer_range(
		errors,
		"朝向模式",
		aim_mode,
		AimMode.FIXED_FACING,
		AimMode.TRACK_TARGET
	)
	ConfigValidator.require_number(
		errors,
		"视觉转向速度",
		visual_turn_speed_degrees,
		0.0,
		INF,
		false
	)
	if levels.is_empty():
		errors.append("至少需要配置 1 个建筑等级")
	if levels.size() > MAX_LEVEL:
		errors.append("建筑等级不能超过 %d 级" % MAX_LEVEL)
	for index in range(levels.size()):
		var stats := levels[index]
		if stats == null:
			errors.append("第 %d 级参数为空" % (index + 1))
			continue
		ConfigValidator.append_prefixed(
			errors,
			"第 %d 级" % (index + 1),
			stats.validate_configuration()
		)
	if kind == Kind.PULSE_LASER_TOWER:
		ConfigValidator.require_integer_range(errors, "脉冲镭射最大反射次数", pulse_laser_reflect_max, 0, 64)
		if pulse_laser_reflection_colors.is_empty():
			errors.append("脉冲镭射颜色序列不能为空")
		for index in range(pulse_laser_reflection_colors.size()):
			ConfigValidator.require_color(
				errors,
				"脉冲镭射颜色 %d" % (index + 1),
				pulse_laser_reflection_colors[index]
			)
	return errors

func is_defensive_structure() -> bool:
	return kind == Kind.BARRIER or kind == Kind.EDGE_BARRIER

func get_resolved_placement_surface() -> PlacementSurface:
	if kind == Kind.EDGE_BARRIER:
		return PlacementSurface.PATH_EDGE
	if kind == Kind.BARRIER:
		return PlacementSurface.PATH_TILE
	return placement_surface

func is_edge_building() -> bool:
	return get_resolved_placement_surface() == PlacementSurface.PATH_EDGE

func is_path_tile_building() -> bool:
	return get_resolved_placement_surface() == PlacementSurface.PATH_TILE
