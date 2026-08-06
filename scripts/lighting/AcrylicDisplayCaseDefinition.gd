@tool
## AcrylicDisplayCaseDefinition -- reusable geometry and base material settings.
class_name AcrylicDisplayCaseDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Feature")
@export var feature_enabled: bool = true
@export var top_panel_enabled: bool = true

@export_group("Dynamic Bounds")
@export_range(0.0, 4.0, 0.05) var horizontal_margin_cells: float = 0.35
@export_range(0.5, 12.0, 0.1) var minimum_interior_height_cells: float = 4.5
@export_range(0.0, 4.0, 0.05) var top_margin_cells: float = 0.65

@export_group("Construction")
@export_range(0.005, 0.2, 0.005) var edge_thickness_cells: float = 0.025
@export_range(0.1, 2.0, 0.05) var base_thickness_cells: float = 0.65
@export_range(0.0, 0.5, 0.01) var base_overhang_cells: float = 0.12
@export_range(0.005, 0.15, 0.005) var gasket_thickness_cells: float = 0.025

@export_group("Base Material")
@export_color_no_alpha var wood_color: Color = Color(0.22, 0.105, 0.055, 1.0)
@export_range(0.0, 1.0, 0.01) var wood_roughness: float = 0.48
@export_color_no_alpha var gasket_color: Color = Color(0.025, 0.03, 0.035, 1.0)


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_number(errors, "横向边距", horizontal_margin_cells, 0.0, 4.0)
	ConfigValidator.require_number(errors, "最低内部高度", minimum_interior_height_cells, 0.0, INF, false)
	ConfigValidator.require_number(errors, "顶面余量", top_margin_cells, 0.0, 4.0)
	ConfigValidator.require_number(errors, "边缘厚度", edge_thickness_cells, 0.0, INF, false)
	ConfigValidator.require_number(errors, "底座厚度", base_thickness_cells, 0.0, INF, false)
	ConfigValidator.require_color(errors, "木底座颜色", wood_color)
	ConfigValidator.require_color(errors, "密封条颜色", gasket_color)
	return errors
