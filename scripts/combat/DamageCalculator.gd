## Stateless M3 damage formula shared by instant and continuous attacks.
class_name DamageCalculator
extends RefCounted

static func compute(base_damage: float, level_factor: float, extra_factor: float) -> float:
	return maxf(0.0, base_damage) * maxf(0.0, level_factor) * maxf(0.0, extra_factor)
