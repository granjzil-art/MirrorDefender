## Stable in-memory definitions used by behavior tests.
##
## Tests must not depend on designer-owned production .tres tuning. Production
## resources are covered separately by load/validation smoke checks.
extends RefCounted


static func make_copy_mirror_definition() -> CopyMirrorDefinition:
	var definition := CopyMirrorDefinition.new()
	definition.display_name = "测试复制镜"
	definition.cost = 120.0
	definition.refund = 60.0
	definition.projection_ignores_occupancy = true
	definition.copy_chain_max = 4
	definition.active_from_side_by_default = true
	definition.mirror_thickness_ratio = 0.08
	definition.mirror_height_ratio = 1.20
	definition.reflection_enabled = true
	definition.reflection_two_sided_visual = true
	definition.reflection_surface_offset_ratio = 0.78
	definition.reflection_resolution = 128
	definition.reflection_preview_resolution = 64
	definition.reflection_update_interval_frames = 1
	definition.reflection_max_updates_per_frame = 6
	return definition


static func make_building_definition(kind: BuildingDefinition.Kind) -> BuildingDefinition:
	var definition := BuildingDefinition.new()
	definition.kind = kind
	definition.display_name = _building_display_name(kind)
	definition.placement_surface = _building_placement_surface(kind)
	definition.blocks_both_directions = true
	definition.aim_mode = (
		BuildingDefinition.AimMode.TRACK_TARGET
		if kind == BuildingDefinition.Kind.ARROW_TOWER
		else BuildingDefinition.AimMode.FIXED_FACING
	)
	definition.visual_turn_speed_degrees = 2160.0
	definition.levels.append(_make_building_stats(kind))
	return definition


static func _make_building_stats(kind: BuildingDefinition.Kind) -> BuildingLevelStats:
	var stats := BuildingLevelStats.new()
	stats.cost = 25.0
	stats.refund_amount = 10.0
	stats.base_damage = 20.0
	stats.targeting_range = 8.0
	stats.attack_range = 7.0
	stats.attacks_per_second = 1.0
	stats.laser_dps = 12.0 if kind == BuildingDefinition.Kind.LASER_TOWER else 0.0
	stats.max_durability = 150.0
	stats.projectile_speed = 8.0
	return stats


static func _building_display_name(kind: BuildingDefinition.Kind) -> String:
	match kind:
		BuildingDefinition.Kind.LASER_TOWER:
			return "测试激光塔"
		BuildingDefinition.Kind.BARRIER:
			return "测试屏障"
		BuildingDefinition.Kind.EDGE_BARRIER:
			return "测试边障"
		_:
			return "测试箭塔"


static func _building_placement_surface(
	kind: BuildingDefinition.Kind
) -> BuildingDefinition.PlacementSurface:
	match kind:
		BuildingDefinition.Kind.BARRIER:
			return BuildingDefinition.PlacementSurface.PATH_TILE
		BuildingDefinition.Kind.EDGE_BARRIER:
			return BuildingDefinition.PlacementSurface.PATH_EDGE
		_:
			return BuildingDefinition.PlacementSurface.BUILDABLE_TILE
