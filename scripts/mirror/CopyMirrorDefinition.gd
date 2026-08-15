@tool
## Copy-effect tuning layered on the shared physical mirror contract.
class_name CopyMirrorDefinition
extends MirrorDefinition

@export_group("Copy Rules")
## Legacy serialized compatibility field. Runtime projections always ignore
## entity/projection occupancy: one real entity plus unlimited virtual images.
@export var projection_ignores_occupancy: bool = true
@export_range(1, 3, 1) var copy_chain_max: int = 3
@export_range(1, 4096, 1) var impact_spawn_budget: int = 128

@export_group("Projection Visual")
## Accent is reserved for overlap indicators, labels and projected attack lines.
@export var projection_tint: Color = Color(0.03, 0.28, 1.0, 1.0)
## Legacy/fallback opacity for resources authored before per-level visuals.
@export_range(0.05, 1.0, 0.01) var projection_alpha: float = 0.38
## Final source-model opacity at mirror levels 1/2.
@export var level_projection_alphas: Array[float] = [0.38, 0.50]
## Every recursive step multiplies opacity by this value. Values below one make
## deeper copies more transparent even when a later mirror has a higher level.
@export_range(0.05, 0.99, 0.01) var recursive_projection_alpha_multiplier: float = 0.72
@export_range(0.01, 0.50, 0.01) var recursive_projection_min_alpha: float = 0.08
@export_range(0.0, 8.0, 0.1) var projection_emission_energy: float = 2.8
@export_range(0.0, 1.0, 0.01) var projection_rim_alpha: float = 0.42
@export_range(0.0, 0.20, 0.005) var projection_ring_spacing_ratio: float = 0.045
@export_range(0.01, 0.10, 0.005) var projection_ring_thickness_ratio: float = 0.022


func _init() -> void:
	display_name = "复制镜"
	upgrade_costs = [50.0]
	level_damage_multipliers = [1.0, 1.1]
	level_penetration_bonuses = [0, 1]


func get_projection_alpha(level: int) -> float:
	var index := clampi(level, 1, MAX_LEVEL) - 1
	if index < level_projection_alphas.size():
		return clampf(level_projection_alphas[index], 0.05, 0.75)
	return clampf(projection_alpha, 0.05, 0.75)


func get_projection_alpha_for_depth(
	level: int,
	chain_depth: int,
	parent_projection_alpha: float = -1.0
) -> float:
	var resolved_depth := maxi(1, chain_depth)
	var resolved_alpha := get_projection_alpha(level) * pow(
		recursive_projection_alpha_multiplier,
		resolved_depth - 1
	)
	if resolved_depth > 1 and parent_projection_alpha >= 0.0:
		resolved_alpha = minf(
			resolved_alpha,
			parent_projection_alpha * recursive_projection_alpha_multiplier
		)
	return clampf(resolved_alpha, recursive_projection_min_alpha, 0.75)

func validate_configuration() -> Array[String]:
	var errors: Array[String] = super.validate_configuration()
	if level_projection_alphas.size() != MAX_LEVEL:
		errors.append("Projection opacity must define exactly two levels")
	else:
		for index in range(level_projection_alphas.size()):
			ConfigValidator.require_number(
				errors,
				"Projection opacity level %d" % (index + 1),
				level_projection_alphas[index],
				0.05,
				0.75
			)
	ConfigValidator.require_integer_range(errors, "复制链上限", copy_chain_max, 1, 3)
	ConfigValidator.require_integer_range(errors, "命中子攻击预算", impact_spawn_budget, 1, 4096)
	ConfigValidator.require_color(errors, "虚像染色", projection_tint)
	ConfigValidator.require_number(errors, "虚像透明度", projection_alpha, 0.05, 1.0)
	ConfigValidator.require_number(
		errors,
		"递归虚像透明度倍率",
		recursive_projection_alpha_multiplier,
		0.05,
		0.99
	)
	ConfigValidator.require_number(
		errors,
		"递归虚像最低可见度",
		recursive_projection_min_alpha,
		0.01,
		0.50
	)
	ConfigValidator.require_number(errors, "虚像发光强度", projection_emission_energy, 0.0, 8.0)
	ConfigValidator.require_number(errors, "虚像轮廓透明度", projection_rim_alpha, 0.0, 1.0)
	ConfigValidator.require_number(errors, "虚像环间距", projection_ring_spacing_ratio, 0.0, 0.2)
	ConfigValidator.require_number(errors, "虚像环宽度", projection_ring_thickness_ratio, 0.01, 0.1)
	return errors
