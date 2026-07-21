## Owns current resources, construction caps, and base/building passive income.
class_name ResourceManager
extends Node

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Economy")
@export_range(0.0, 100000.0, 1.0, "or_greater") var main_resource: float = 200.0
@export_range(0, 1000, 1, "or_greater") var building_cap: int = 20
@export_range(0, 1000, 1, "or_greater") var mirror_cap: int = 6

@export_group("Passive Income")
@export_range(0.0, 10000.0, 0.1, "or_greater") var base_resource_per_second: float = 0.5

signal resource_changed(current: float, delta: float, reason: String)
signal limits_changed(building_count: int, building_limit: int, mirror_count: int, mirror_limit: int)
signal income_rates_changed(base_per_second: float, buildings_per_second: float)

var _building_count: int = 0
var _mirror_count: int = 0
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
	mirror_cap = level_resource.mirror_cap
	base_resource_per_second = level_resource.base_resource_per_second
	_building_count = 0
	_mirror_count = 0
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

func can_add_building() -> bool:
	return feature_enabled and _building_count < building_cap

func try_register_building(cost: float) -> bool:
	if not can_add_building() or not spend(cost, "building_cost"):
		return false
	_building_count += 1
	_emit_limits_changed()
	return true

func unregister_building(refund: float = 0.0) -> void:
	_building_count = maxi(0, _building_count - 1)
	if refund > 0.0:
		gain(refund, "building_refund")
	_emit_limits_changed()

func can_add_mirror() -> bool:
	return feature_enabled and _mirror_count < mirror_cap

func try_register_mirror(cost: float) -> bool:
	if not can_add_mirror() or not spend(cost, "mirror_cost"):
		return false
	_mirror_count += 1
	_emit_limits_changed()
	return true

func unregister_mirror(refund: float = 0.0) -> void:
	_mirror_count = maxi(0, _mirror_count - 1)
	if refund > 0.0:
		gain(refund, "mirror_refund")
	_emit_limits_changed()

func set_building_resource_per_second(value: float) -> void:
	if not is_finite(value):
		return
	_building_resource_per_second = maxf(0.0, value)
	income_rates_changed.emit(base_resource_per_second, _building_resource_per_second)

## M4 enemy death calls this with the individual enemy reward.
func grant_enemy_drop(amount: float) -> void:
	gain(amount, "enemy_drop")

func get_building_count() -> int:
	return _building_count

func get_mirror_count() -> int:
	return _mirror_count

func get_building_resource_per_second() -> float:
	return _building_resource_per_second

func get_total_resource_per_second() -> float:
	return base_resource_per_second + _building_resource_per_second

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
	limits_changed.emit(_building_count, building_cap, _mirror_count, mirror_cap)
