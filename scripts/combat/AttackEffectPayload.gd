## Runtime attack state shared by projectiles and beam paths.
##
## Copy projection templates retain copy-upgrade effects. Every direct building
## emission instantiates a fresh root attack, while reflection/impact children
## inherit the exact current state and the corresponding shared spawn budgets.
class_name AttackEffectPayload
extends RefCounted

enum AttackOrigin {
	BUILDING_EMISSION,
	REFLECTION_BRANCH,
	IMPACT_CHILD,
}

const MAX_TOTAL_REFLECTIONS := 7
const DEFAULT_REFLECTION_BRANCH_BUDGET := 14
const DEFAULT_IMPACT_SPAWN_BUDGET := 128

static var _runtime_max_total_reflections: int = MAX_TOTAL_REFLECTIONS
static var _runtime_reflection_branch_budget: int = DEFAULT_REFLECTION_BRANCH_BUDGET
static var _runtime_impact_spawn_budget: int = DEFAULT_IMPACT_SPAWN_BUDGET


class SpawnBudgets:
	extends RefCounted

	var reflection_remaining: int
	var impact_remaining: int

	func _init(reflection_budget: int, impact_budget: int) -> void:
		reflection_remaining = maxi(0, reflection_budget)
		impact_remaining = maxi(0, impact_budget)


var _effects: Dictionary = {}
var _budgets: SpawnBudgets
var _origin_kind: AttackOrigin = AttackOrigin.BUILDING_EMISSION
var _copy_upgrade_count: int = 0
var _total_reflection_count: int = 0
var _reflection_upgrade_count: int = 0
var _maximum_total_reflections: int = MAX_TOTAL_REFLECTIONS


func _init() -> void:
	_maximum_total_reflections = maxi(1, _runtime_max_total_reflections)
	_budgets = SpawnBudgets.new(
		_runtime_reflection_branch_budget,
		_runtime_impact_spawn_budget
	)


static func configure_runtime_limits(
	maximum_reflections: int,
	reflection_branch_budget: int,
	impact_spawn_budget: int
) -> void:
	_runtime_max_total_reflections = maxi(1, maximum_reflections)
	_runtime_reflection_branch_budget = maxi(0, reflection_branch_budget)
	_runtime_impact_spawn_budget = maxi(0, impact_spawn_budget)


static func get_runtime_max_total_reflections() -> int:
	return _runtime_max_total_reflections


static func get_runtime_reflection_branch_budget() -> int:
	return _runtime_reflection_branch_budget


static func get_runtime_impact_spawn_budget() -> int:
	return _runtime_impact_spawn_budget


func add_effect(effect: Resource, initial_state: Dictionary = {}) -> bool:
	if effect == null or not effect.has_method("get_effect_id"):
		return false
	var effect_id := StringName(effect.call("get_effect_id"))
	if effect_id == StringName():
		return false
	if _effects.has(effect_id):
		return true
	_effects[effect_id] = {
		"effect": effect,
		"state": initial_state.duplicate(true),
	}
	return true


func has_effect(effect_id: StringName) -> bool:
	return _effects.has(effect_id)


func get_effect_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_id in _effects.keys():
		result.append(StringName(raw_id))
	result.sort()
	return result


func get_effect_state(effect_id: StringName) -> Dictionary:
	var entry: Dictionary = _effects.get(effect_id, {})
	var state: Variant = entry.get("state", {})
	return (state as Dictionary).duplicate(true) if state is Dictionary else {}


func get_effect_resource(effect_id: StringName) -> Resource:
	var entry: Dictionary = _effects.get(effect_id, {})
	return entry.get("effect") as Resource


func set_copy_upgrade_count(value: int) -> void:
	_copy_upgrade_count = clampi(value, 0, 3)


func get_copy_upgrade_count() -> int:
	return _copy_upgrade_count


func get_origin_kind() -> AttackOrigin:
	return _origin_kind


func can_spawn_reflection_branches() -> bool:
	return _origin_kind == AttackOrigin.BUILDING_EMISSION


func get_total_reflection_count() -> int:
	return _total_reflection_count


func get_reflection_upgrade_count() -> int:
	return _reflection_upgrade_count


func has_reached_reflection_limit() -> bool:
	return _total_reflection_count >= _maximum_total_reflections


## Records one successful reflection. Callers must terminate the attack when
## this returns false; that contact is absorption and grants no reflection effect.
func record_successful_reflection(reflection_hit: Dictionary) -> bool:
	if has_reached_reflection_limit():
		return false
	_total_reflection_count += 1
	if bool(reflection_hit.get("is_upgraded_reflect_mirror", false)):
		_reflection_upgrade_count = mini(
			_total_reflection_count,
			_reflection_upgrade_count + 1
		)
	return true


## Mirror projection templates use this when an entity/copy tower fires. Copy
## state is retained, while runtime reflection state and budgets start fresh.
func instantiate_attack() -> AttackEffectPayload:
	var next := _duplicate_effects_only()
	next._copy_upgrade_count = _copy_upgrade_count
	return next


func duplicate_for_reflection_branch() -> AttackEffectPayload:
	return _duplicate_runtime_child(AttackOrigin.REFLECTION_BRANCH)


func duplicate_for_impact_child(state_overrides: Dictionary = {}) -> AttackEffectPayload:
	var next := _duplicate_runtime_child(AttackOrigin.IMPACT_CHILD)
	next._apply_state_overrides(state_overrides)
	return next


## Compatibility entry point for older callers. New code should state whether a
## child came from reflection or impact explicitly.
func duplicate_for_branch(state_overrides: Dictionary = {}) -> AttackEffectPayload:
	var next := duplicate_for_reflection_branch()
	next._apply_state_overrides(state_overrides)
	return next


func request_reflection_branch_slots(requested: int) -> int:
	if not can_spawn_reflection_branches():
		return 0
	var resolved := maxi(0, requested)
	var granted := mini(resolved, maxi(0, _budgets.reflection_remaining))
	_budgets.reflection_remaining -= granted
	return granted


func request_impact_spawn_slots(requested: int) -> int:
	var resolved := maxi(0, requested)
	var granted := mini(resolved, maxi(0, _budgets.impact_remaining))
	_budgets.impact_remaining -= granted
	return granted


func get_remaining_reflection_branch_budget() -> int:
	return maxi(0, _budgets.reflection_remaining)


func get_remaining_impact_spawn_budget() -> int:
	return maxi(0, _budgets.impact_remaining)


## Compatibility aliases retained for existing tests and extension scripts.
func request_branch_slots(requested: int) -> int:
	return request_reflection_branch_slots(requested)


func get_remaining_branch_budget() -> int:
	return get_remaining_reflection_branch_budget()


func apply_reflection_effects(reflection_hit: Dictionary, context: Dictionary = {}) -> void:
	var resolved_context := _reflection_context(context)
	for raw_effect in reflection_hit.get("attack_effects", []):
		if raw_effect is Resource and raw_effect.has_method("apply_on_reflection"):
			raw_effect.call("apply_on_reflection", self, resolved_context)


func get_reflection_penetration_bonus(
	reflection_hit: Dictionary,
	context: Dictionary = {}
) -> int:
	var result := 0
	var resolved_context := _reflection_context(context)
	for raw_effect in reflection_hit.get("attack_effects", []):
		if not raw_effect is Resource or not raw_effect.has_method("get_reflection_penetration_bonus"):
			continue
		result += maxi(0, int(raw_effect.call("get_reflection_penetration_bonus", resolved_context)))
	return result


func get_reflection_branch_angles(
	reflection_hit: Dictionary,
	context: Dictionary = {}
) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if not can_spawn_reflection_branches():
		return result
	var resolved_context := _reflection_context(context)
	for raw_effect in reflection_hit.get("attack_effects", []):
		if not raw_effect is Resource or not raw_effect.has_method("get_reflection_branch_angles"):
			continue
		var raw_angles: Variant = raw_effect.call("get_reflection_branch_angles", resolved_context)
		if raw_angles is PackedFloat32Array:
			for angle in raw_angles:
				if is_finite(angle) and not _contains_approx(result, angle):
					result.append(angle)
		elif raw_angles is Array:
			for raw_angle in raw_angles:
				var angle := float(raw_angle)
				if is_finite(angle) and not _contains_approx(result, angle):
					result.append(angle)
	return result


func get_laser_visual_modifiers(context: Dictionary = {}) -> Dictionary:
	var result := {"width_multiplier": 1.0}
	var resolved_context := _reflection_context(context)
	for effect_id in get_effect_ids():
		var entry: Dictionary = _effects.get(effect_id, {})
		var effect := entry.get("effect") as Resource
		if effect == null or not effect.has_method("get_laser_visual_modifiers"):
			continue
		var raw_modifiers: Variant = effect.call("get_laser_visual_modifiers", resolved_context)
		if not raw_modifiers is Dictionary:
			continue
		var modifiers := raw_modifiers as Dictionary
		var width_multiplier := float(modifiers.get("width_multiplier", 1.0))
		if is_finite(width_multiplier):
			result["width_multiplier"] = (
				float(result.get("width_multiplier", 1.0)) * maxf(0.0, width_multiplier)
			)
		if modifiers.has("color") and modifiers.get("color") is Color:
			result["color"] = modifiers.get("color") as Color
	return result


func notify_projectile_impact(projectile: Object, target: CombatTarget) -> void:
	for effect_id in get_effect_ids():
		var entry: Dictionary = _effects.get(effect_id, {})
		var effect := entry.get("effect") as Resource
		var state_value: Variant = entry.get("state", {})
		var state: Dictionary = state_value if state_value is Dictionary else {}
		if effect != null and effect.has_method("on_projectile_impact"):
			effect.call("on_projectile_impact", self, state, projectile, target)
		entry["state"] = state
		_effects[effect_id] = entry


func notify_missile_explosion(
	missile: Object,
	world_position: Vector3,
	explosion_damage: float
) -> void:
	for effect_id in get_effect_ids():
		var entry: Dictionary = _effects.get(effect_id, {})
		var effect := entry.get("effect") as Resource
		var state_value: Variant = entry.get("state", {})
		var state: Dictionary = state_value if state_value is Dictionary else {}
		if effect != null and effect.has_method("on_missile_explosion"):
			effect.call(
				"on_missile_explosion",
				self,
				state,
				missile,
				world_position,
				maxf(0.0, explosion_damage)
			)
		entry["state"] = state
		_effects[effect_id] = entry


func _reflection_context(context: Dictionary) -> Dictionary:
	var resolved := context.duplicate()
	resolved["copy_upgrade_count"] = _copy_upgrade_count
	resolved["total_reflection_count"] = _total_reflection_count
	resolved["reflection_upgrade_count"] = _reflection_upgrade_count
	resolved["attack_origin"] = _origin_kind
	return resolved


func _duplicate_effects_only() -> AttackEffectPayload:
	var next := AttackEffectPayload.new()
	next._effects.clear()
	for raw_id in _effects.keys():
		var effect_id := StringName(raw_id)
		var entry: Dictionary = _effects[raw_id]
		var state_value: Variant = entry.get("state", {})
		next._effects[effect_id] = {
			"effect": entry.get("effect") as Resource,
			"state": (state_value as Dictionary).duplicate(true) if state_value is Dictionary else {},
		}
	return next


func _duplicate_runtime_child(origin: AttackOrigin) -> AttackEffectPayload:
	var next := _duplicate_effects_only()
	next._budgets = _budgets
	next._origin_kind = origin
	next._copy_upgrade_count = _copy_upgrade_count
	next._total_reflection_count = _total_reflection_count
	next._reflection_upgrade_count = _reflection_upgrade_count
	next._maximum_total_reflections = _maximum_total_reflections
	return next


func _apply_state_overrides(state_overrides: Dictionary) -> void:
	for raw_id in state_overrides.keys():
		var effect_id := StringName(raw_id)
		if not _effects.has(effect_id):
			continue
		var override_value: Variant = state_overrides[raw_id]
		if not override_value is Dictionary:
			continue
		var entry: Dictionary = _effects[effect_id]
		var state_value: Variant = entry.get("state", {})
		var state: Dictionary = state_value if state_value is Dictionary else {}
		state.merge((override_value as Dictionary).duplicate(true), true)
		entry["state"] = state
		_effects[effect_id] = entry


func _contains_approx(values: PackedFloat32Array, candidate: float) -> bool:
	for value in values:
		if is_equal_approx(value, candidate):
			return true
	return false
