@tool
## Copy-effect tuning layered on the shared physical mirror contract.
class_name CopyMirrorDefinition
extends MirrorDefinition

@export_group("Copy Rules")
@export var projection_ignores_occupancy: bool = true
@export_range(1, 16, 1) var copy_chain_max: int = 4

@export_group("Projection Visual")
## Accent is reserved for overlap indicators, labels and projected attack lines.
@export var projection_tint: Color = Color(0.12, 0.85, 1.0, 1.0)
## Final opacity of the copied source model. RGB, textures and source shaders
## remain unchanged; 1.0 is fully opaque and lower values are more transparent.
@export_range(0.05, 1.0, 0.01) var projection_alpha: float = 0.76
@export_range(0.0, 8.0, 0.1) var projection_emission_energy: float = 2.8
@export_range(0.0, 1.0, 0.01) var projection_rim_alpha: float = 0.42
@export_range(0.0, 0.20, 0.005) var projection_ring_spacing_ratio: float = 0.045
@export_range(0.01, 0.10, 0.005) var projection_ring_thickness_ratio: float = 0.022


func _init() -> void:
	display_name = "复制镜"
	upgrade_costs = [50.0, 50.0]
	level_damage_multipliers = [1.0, 1.1, 1.2]
	level_penetration_bonuses = [0, 1, 2]

func validate_configuration() -> Array[String]:
	var errors: Array[String] = super.validate_configuration()
	ConfigValidator.require_integer_range(errors, "复制链上限", copy_chain_max, 1, 16)
	ConfigValidator.require_color(errors, "虚像染色", projection_tint)
	ConfigValidator.require_number(errors, "虚像透明度", projection_alpha, 0.05, 1.0)
	ConfigValidator.require_number(errors, "虚像发光强度", projection_emission_energy, 0.0, 8.0)
	ConfigValidator.require_number(errors, "虚像轮廓透明度", projection_rim_alpha, 0.0, 1.0)
	ConfigValidator.require_number(errors, "虚像环间距", projection_ring_spacing_ratio, 0.0, 0.2)
	ConfigValidator.require_number(errors, "虚像环宽度", projection_ring_thickness_ratio, 0.01, 0.1)
	return errors
