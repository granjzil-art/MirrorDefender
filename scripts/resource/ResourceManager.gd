## Owns current resources, independent construction caps, and passive income.
class_name ResourceManager
extends Node

const COPY_MIRROR_KIND: int = 0
const REFLECT_MIRROR_KIND: int = 1

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Economy")
@export_range(0.0, 100000.0, 1.0, "or_greater") var main_resource: float = 200.0
@export_range(0, 1000, 1, "or_greater") var building_cap: int = 20
@export_range(0, 1000, 1, "or_greater") var copy_mirror_cap: int = 5
@export_range(0, 1000, 1, "or_greater") var reflect_mirror_cap: int = 10

@export_group("Passive Income")
@export_range(0.0, 10000.0, 0.1, "or_greater") var base_resource_per_second: float = 0.5

signal resource_changed(current: float, delta: float, reason: String)
signal limits_changed(
	building_count: int,
	building_limit: int,
	copy_mirror_count: int,
	copy_mirror_limit: int,
	reflect_mirror_count: int,
	reflect_mirror_limit: int
)
signal income_rates_changed(base_per_second: float, buildings_per_second: float)

var mirror_cap: int:
	get:
		return copy_mirror_cap + reflect_mirror_cap

var _building_count: int = 0
var _copy_mirror_count: int = 0
var _reflect_mirror_count: int = 0
var _building_resource_per_second: float = 0.0
var _base_income_buffer: float = 0.0
var _building_income_buffer: float = 0.0


func _process(delta: float) -> void:
	if not feature_enabled:
		return
	if base_resource_per_second > 0.0:
		_base_income_buffer += base_resource_per_second * delta
		_base_income_buffer = _flush_income(_base_income_buffer, "base_income")
	if _building_resource_per_second > 0.0:
		_building_income_buffer += _building_resource_per_second * delta
		_building_income_buffer = _flush_income(_building_income_buffer, "building_income")


func apply_level_configuration(level_resource: LevelResource) -> void:
	if level_resource == null:
		return
	main_resource = float(level_resource.initial_resource)
	building_cap = level_resource.building_cap
	copy_mirror_cap = level_resource.get_copy_mirror_cap()
	reflect_mirror_cap = level_resource.get_reflect_mirror_cap()
	base_resource_per_second = level_resource.base_resource_per_second
	_building_count = 0
	_copy_mirror_count = 0
	_reflect_mirror_count = 0
	_building_resource_per_second = 0.0
	_reset_income_buffers()
	resource_changed.emit(main_resource, 0.0, "level_loaded")
	_emit_limits_changed()
	income_rates_changed.emit(base_resource_per_second, _building_resource_per_second)


func can_afford(cost: float) -> bool:
	return feature_enabled and is_finite(cost) and cost >= 0.0 and is_finite(main_resource) and main_resource >= cost


func spend(cost: float, reason: String = "spend") -> bool:
	if not can_afford(cost):
		return false
	main_resource -= cost
	resource_changed.emit(main_resource, -cost, reason)
	return true


func gain(amount: float, reason: String = "gain") -> void:
	if not feature_enabled or not is_finite(amount) or amount <= 0.0 or not is_finite(main_resource):
		return
	main_resource += amount
	resource_changed.emit(main_resource, amount, reason)


func set_main_resource(value: float, reason: String = "set") -> bool:
	if not feature_enabled or not is_finite(value) or value < 0.0:
		return false
	var delta := value - main_resource
	main_resource = value
	resource_changed.emit(main_resource, delta, reason)
	return true


func can_add_building() -> bool:
	return feature_enabled and _building_count < building_cap


func try_register_building(cost: float) -> bool:
	if not can_add_building() or not spend(cost, "building_cost"):
		return false
	_building_count += 1
	_emit_limits_changed()
	return true


## Registers an authored initial building without consuming initial_resource.
func try_register_initial_building() -> bool:
	if not can_add_building():
		return false
	_building_count += 1
	_emit_limits_changed()
	return true


func unregister_building(refund: float = 0.0) -> void:
	_building_count = maxi(0, _building_count - 1)
	if refund > 0.0:
		gain(refund, "building_refund")
	_emit_limits_changed()


func can_add_mirror(mirror_kind: int = COPY_MIRROR_KIND) -> bool:
	if not feature_enabled:
		return false
	return (
		_reflect_mirror_count < reflect_mirror_cap
		if _is_reflect_kind(mirror_kind)
		else _copy_mirror_count < copy_mirror_cap
	)


func try_register_mirror(
	mirror_kind: int = COPY_MIRROR_KIND,
	cost: float = 0.0,
	reason: String = "mirror_cost"
) -> bool:
	if not can_add_mirror(mirror_kind) or not can_afford(cost):
		return false
	if cost > 0.0 and not spend(cost, reason):
		return false
	if _is_reflect_kind(mirror_kind):
		_reflect_mirror_count += 1
	else:
		_copy_mirror_count += 1
	_emit_limits_changed()
	return true


## Registers an authored initial mirror without consuming initial_resource.
func try_register_initial_mirror(mirror_kind: int = COPY_MIRROR_KIND) -> bool:
	if not can_add_mirror(mirror_kind):
		return false
	if _is_reflect_kind(mirror_kind):
		_reflect_mirror_count += 1
	else:
		_copy_mirror_count += 1
	_emit_limits_changed()
	return true


func unregister_mirror(
	mirror_kind: int = COPY_MIRROR_KIND,
	refund: float = 0.0,
	refund_reason: String = "mirror_placement_rollback"
) -> void:
	if _is_reflect_kind(mirror_kind):
		_reflect_mirror_count = maxi(0, _reflect_mirror_count - 1)
	else:
		_copy_mirror_count = maxi(0, _copy_mirror_count - 1)
	if refund > 0.0:
		gain(refund, refund_reason)
	_emit_limits_changed()


func set_building_resource_per_second(value: float) -> void:
	if not is_finite(value):
		return
	_building_resource_per_second = maxf(0.0, value)
	income_rates_changed.emit(base_resource_per_second, _building_resource_per_second)


## M4 enemy death calls this with the individual enemy reward.
func grant_enemy_drop(amount: float) -> void:
	gain(amount, "enemy_drop")


func grant_wave_completion_reward(amount: float) -> void:
	gain(amount, "wave_completion")


func get_building_count() -> int:
	return _building_count


func get_copy_mirror_count() -> int:
	return _copy_mirror_count


func get_reflect_mirror_count() -> int:
	return _reflect_mirror_count


func get_mirror_count() -> int:
	return _copy_mirror_count + _reflect_mirror_count


func get_mirror_count_for_kind(mirror_kind: int) -> int:
	return _reflect_mirror_count if _is_reflect_kind(mirror_kind) else _copy_mirror_count


func get_mirror_cap_for_kind(mirror_kind: int) -> int:
	return reflect_mirror_cap if _is_reflect_kind(mirror_kind) else copy_mirror_cap


func get_building_resource_per_second() -> float:
	return _building_resource_per_second


func get_total_resource_per_second() -> float:
	return base_resource_per_second + _building_resource_per_second


func _is_reflect_kind(mirror_kind: int) -> bool:
	return mirror_kind == REFLECT_MIRROR_KIND


func _flush_income(buffer: float, reason: String) -> float:
	var whole_amount := floorf(buffer)
	if whole_amount >= 1.0:
		gain(whole_amount, reason)
		return buffer - whole_amount
	return buffer


func _reset_income_buffers() -> void:
	_base_income_buffer = 0.0
	_building_income_buffer = 0.0


func _emit_limits_changed() -> void:
	limits_changed.emit(
		_building_count,
		building_cap,
		_copy_mirror_count,
		copy_mirror_cap,
		_reflect_mirror_count,
		reflect_mirror_cap
	)
