## Data-only definition for one constructible M3 building type.
class_name BuildingDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

const MAX_LEVEL := 3

enum Kind {
	ARROW_TOWER,
	LASER_TOWER,
	BARRIER,
	EDGE_BARRIER,
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
## Optional production-HUD artwork. The card bar provides a stable fallback.
@export var card_icon: Texture2D

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

func get_level_stats(value: int) -> BuildingLevelStats:
	if levels.is_empty():
		return null
	var index := clampi(value, 1, get_max_level()) - 1
	return levels[index]

func get_max_level() -> int:
	return mini(MAX_LEVEL, levels.size())

func is_configured() -> bool:
	return validate_configuration().is_empty()

func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "建筑显示名", display_name)
	ConfigValidator.require_integer_range(errors, "建筑类型", kind, Kind.ARROW_TOWER, Kind.EDGE_BARRIER)
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
