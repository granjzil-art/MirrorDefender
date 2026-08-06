@tool
## DisplayCaseLightingDefinition -- profile-owned acrylic highlight colors.
class_name DisplayCaseLightingDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

@export_group("Glass")
@export_color_no_alpha var glass_tint: Color = Color(0.72, 0.90, 0.94, 1.0)
@export_range(0.0, 0.2, 0.001) var base_alpha: float = 0.018
@export_range(0.0, 0.4, 0.001) var fresnel_alpha: float = 0.11
@export_range(1.0, 8.0, 0.1) var fresnel_power: float = 4.0
@export_range(0.0, 0.4, 0.001) var border_alpha: float = 0.11

@export_group("Reflection Stripe")
@export_color_no_alpha var stripe_color: Color = Color(0.86, 0.96, 1.0, 1.0)
@export_range(0.0, 0.25, 0.001) var stripe_strength: float = 0.035
@export_range(0.01, 0.5, 0.01) var stripe_width: float = 0.16

@export_group("Edges")
@export_color_no_alpha var edge_color: Color = Color(0.80, 0.95, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var edge_alpha: float = 0.17
@export_range(0.0, 4.0, 0.01) var edge_emission_energy: float = 0.08


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_color(errors, "玻璃色", glass_tint)
	ConfigValidator.require_color(errors, "反光条颜色", stripe_color)
	ConfigValidator.require_color(errors, "玻璃边颜色", edge_color)
	ConfigValidator.require_number(errors, "基础透明度", base_alpha, 0.0, 0.2)
	ConfigValidator.require_number(errors, "菲涅尔透明度", fresnel_alpha, 0.0, 0.4)
	ConfigValidator.require_number(errors, "反光条强度", stripe_strength, 0.0, 0.25)
	return errors
