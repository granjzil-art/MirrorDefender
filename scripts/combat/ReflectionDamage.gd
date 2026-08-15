## Shared durability damage for reflection providers that expose destructible faces.
class_name ReflectionDamage
extends RefCounted


static func apply(reflection_hit: Dictionary, damage: float) -> float:
	if not bool(reflection_hit.get("hit", false)) or damage <= 0.0:
		return 0.0
	var reflector_value: Variant = reflection_hit.get("reflector")
	if typeof(reflector_value) != TYPE_OBJECT or not is_instance_valid(reflector_value):
		return 0.0
	var reflector := reflector_value as Object
	if not reflector.has_method("take_reflection_surface_damage"):
		return 0.0
	var surface_id := StringName(
		reflection_hit.get(
			"reflector_surface_id",
			reflection_hit.get("surface_id", StringName())
		)
	)
	if surface_id == StringName():
		return 0.0
	return float(reflector.call("take_reflection_surface_damage", surface_id, damage))
