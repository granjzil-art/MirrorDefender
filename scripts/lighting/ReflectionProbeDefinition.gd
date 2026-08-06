@tool
## ReflectionProbeDefinition -- low-frequency cabinet reflection budget.
class_name ReflectionProbeDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Feature")
@export var feature_enabled: bool = true
@export var update_always: bool = false

@export_group("Capture")
@export_range(0.0, 4.0, 0.01) var intensity: float = 0.85
@export_range(0.0, 4.0, 0.05) var bounds_margin_cells: float = 0.30
@export_range(0.0, 4.0, 0.05) var blend_distance_cells: float = 0.35
@export_range(1.0, 8.0, 0.1) var max_distance_multiplier: float = 1.5
@export var box_projection: bool = true
@export var enable_shadows: bool = false


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_number(errors, "反射强度", intensity, 0.0, 4.0)
	ConfigValidator.require_number(errors, "反射边距", bounds_margin_cells, 0.0, 4.0)
	ConfigValidator.require_number(errors, "反射混合距离", blend_distance_cells, 0.0, 4.0)
	ConfigValidator.require_number(errors, "反射最大距离倍率", max_distance_multiplier, 1.0, 8.0)
	return errors
