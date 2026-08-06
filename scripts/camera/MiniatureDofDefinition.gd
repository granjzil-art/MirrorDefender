@tool
## MiniatureDofDefinition -- data-only settings for depth-driven miniature DOF.
class_name MiniatureDofDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Focus Plane")
## Raises the focus target above the CameraRig pivot in grid-cell units.
@export_range(-2.0, 4.0, 0.05) var focus_height_offset_cells: float = 0.35
## Clear depth range in front of and behind the focus target.
@export_range(0.05, 12.0, 0.05) var near_focus_margin_cells: float = 2.00
@export_range(0.05, 12.0, 0.05) var far_focus_margin_cells: float = 2.00

@export_group("Blur")
@export var near_blur_enabled: bool = true
@export var far_blur_enabled: bool = true
@export_range(0.0, 1.0, 0.005) var blur_amount: float = 0.10
## Distance over which blur reaches full strength, expressed in grid cells.
@export_range(0.05, 16.0, 0.05) var near_transition_cells: float = 3.00
@export_range(0.05, 16.0, 0.05) var far_transition_cells: float = 3.00


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_number(errors, "focus_height_offset_cells", focus_height_offset_cells, -2.0, 4.0)
	ConfigValidator.require_number(errors, "near_focus_margin_cells", near_focus_margin_cells, 0.05, 12.0)
	ConfigValidator.require_number(errors, "far_focus_margin_cells", far_focus_margin_cells, 0.05, 12.0)
	ConfigValidator.require_number(errors, "blur_amount", blur_amount, 0.0, 1.0)
	ConfigValidator.require_number(errors, "near_transition_cells", near_transition_cells, 0.05, 16.0)
	ConfigValidator.require_number(errors, "far_transition_cells", far_transition_cells, 0.05, 16.0)
	if not near_blur_enabled and not far_blur_enabled:
		errors.append("Near and far blur cannot both be disabled")
	return errors
