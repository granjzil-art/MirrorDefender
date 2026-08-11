@tool
## RealisticTreeShadowDefinition -- data for a real model used as a natural shadow caster.
class_name RealisticTreeShadowDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Feature")
@export var feature_enabled: bool = true
@export var model_asset: ModelAssetDefinition

@export_group("Placement")
## X/Z position relative to the current content bounds; values outside 0..1 place an off-level caster.
@export var position_normalized: Vector2 = Vector2(0.18, 0.18)
@export_range(0.5, 80.0, 0.05, "or_greater") var target_height_cells: float = 4.0
@export_range(-180.0, 180.0, 0.5) var yaw_degrees: float = 18.0
@export_range(-1.0, 2.0, 0.01) var ground_offset_cells: float = 0.0

@export_group("Rendering")
@export var model_visible: bool = true
@export var cast_shadow: bool = true

@export_group("Leaf Shadow Cutout")
## Replace alpha-blended leaf shadows with a shadow-only alpha-scissor copy.
@export var leaf_alpha_cutout_enabled: bool = true
## Leaf-shadow coverage multiplier. Zero removes leaf shadows; values above 1.0 densify them.
@export_range(0.0, 2.0, 0.01) var leaf_shadow_strength: float = 1.0
@export_range(0.0, 1.0, 0.01) var leaf_alpha_scissor_threshold: float = 0.5
@export_range(1.0, 32.0, 0.1) var leaf_shadow_breakup_scale: float = 12.0
## Higher values remove more leaf-shadow coverage and open larger light gaps.
@export_range(0.0, 1.0, 0.01) var leaf_shadow_gap_threshold: float = 0.52
@export var leaf_shadow_pattern_seed: float = 7.31


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if model_asset == null:
		errors.append("model_asset is required")
	else:
		ConfigValidator.append_prefixed(errors, "model_asset", model_asset.validate_configuration())
	ConfigValidator.require_number(errors, "position_normalized.x", position_normalized.x, -2.0, 3.0)
	ConfigValidator.require_number(errors, "position_normalized.y", position_normalized.y, -2.0, 3.0)
	ConfigValidator.require_number(errors, "target_height_cells", target_height_cells, 0.5, 80.0)
	ConfigValidator.require_number(errors, "yaw_degrees", yaw_degrees, -180.0, 180.0)
	ConfigValidator.require_number(errors, "ground_offset_cells", ground_offset_cells, -1.0, 2.0)
	ConfigValidator.require_number(errors, "leaf_shadow_strength", leaf_shadow_strength, 0.0, 2.0)
	ConfigValidator.require_number(errors, "leaf_alpha_scissor_threshold", leaf_alpha_scissor_threshold, 0.0, 1.0)
	ConfigValidator.require_number(errors, "leaf_shadow_breakup_scale", leaf_shadow_breakup_scale, 1.0, 32.0)
	ConfigValidator.require_number(errors, "leaf_shadow_gap_threshold", leaf_shadow_gap_threshold, 0.0, 1.0)
	ConfigValidator.require_number(errors, "leaf_shadow_pattern_seed", leaf_shadow_pattern_seed, -1000000.0, 1000000.0)
	return errors
