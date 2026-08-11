@tool
## FoliageShadowDefinition -- sparse, procedural, model-free foliage shadow settings.
class_name FoliageShadowDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Coverage")
@export_range(64, 1024, 1) var texture_resolution: int = 256
@export var pattern_seed: int = 104729
@export_range(1, 32, 1) var cluster_count: int = 5
@export_range(1, 12, 1) var leaves_per_cluster_min: int = 2
@export_range(1, 12, 1) var leaves_per_cluster_max: int = 3
@export_range(0.0, 0.25, 0.001) var cluster_spread_uv: float = 0.06
@export_range(0.005, 0.20, 0.001) var leaf_radius_min_uv: float = 0.045
@export_range(0.005, 0.20, 0.001) var leaf_radius_max_uv: float = 0.085
## Alpha-hash occupancy inside the sparse leaf shapes. Values above 1.0 densify the mask until it saturates.
@export_range(0.0, 2.0, 0.01) var shadow_strength: float = 0.36
@export_range(0.0, 0.45, 0.01) var edge_softness: float = 0.35

@export_group("Placement")
@export_range(0.0, 8.0, 0.05) var horizontal_margin_cells: float = 1.0
@export_range(0.05, 8.0, 0.05) var height_above_content_cells: float = 0.35
@export var pattern_tiles: Vector2 = Vector2.ONE

@export_group("Motion")
@export var motion_enabled: bool = true
@export_range(0.0, 4.0, 0.01) var motion_speed: float = 0.22
@export var sway_uv: Vector2 = Vector2(0.016, 0.011)
@export_range(-TAU, TAU, 0.01) var phase: float = 0.7


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_number(errors, "texture_resolution", float(texture_resolution), 64.0, 1024.0)
	ConfigValidator.require_number(errors, "cluster_count", float(cluster_count), 1.0, 32.0)
	ConfigValidator.require_number(errors, "leaves_per_cluster_min", float(leaves_per_cluster_min), 1.0, 12.0)
	ConfigValidator.require_number(errors, "leaves_per_cluster_max", float(leaves_per_cluster_max), 1.0, 12.0)
	if leaves_per_cluster_min > leaves_per_cluster_max:
		errors.append("leaves_per_cluster_min cannot exceed leaves_per_cluster_max")
	ConfigValidator.require_number(errors, "cluster_spread_uv", cluster_spread_uv, 0.0, 0.25)
	ConfigValidator.require_number(errors, "leaf_radius_min_uv", leaf_radius_min_uv, 0.005, 0.20)
	ConfigValidator.require_number(errors, "leaf_radius_max_uv", leaf_radius_max_uv, 0.005, 0.20)
	if leaf_radius_min_uv > leaf_radius_max_uv:
		errors.append("leaf_radius_min_uv cannot exceed leaf_radius_max_uv")
	ConfigValidator.require_number(errors, "shadow_strength", shadow_strength, 0.0, 2.0)
	ConfigValidator.require_number(errors, "edge_softness", edge_softness, 0.0, 0.45)
	ConfigValidator.require_number(errors, "horizontal_margin_cells", horizontal_margin_cells, 0.0, 8.0)
	ConfigValidator.require_number(errors, "height_above_content_cells", height_above_content_cells, 0.05, 8.0)
	ConfigValidator.require_number(errors, "pattern_tiles.x", pattern_tiles.x, 0.1, 8.0)
	ConfigValidator.require_number(errors, "pattern_tiles.y", pattern_tiles.y, 0.1, 8.0)
	ConfigValidator.require_number(errors, "motion_speed", motion_speed, 0.0, 4.0)
	ConfigValidator.require_number(errors, "sway_uv.x", sway_uv.x, 0.0, 0.25)
	ConfigValidator.require_number(errors, "sway_uv.y", sway_uv.y, 0.0, 0.25)
	return errors
