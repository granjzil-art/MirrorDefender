## Owns the single M3 economy, construction caps, and income source switches.
class_name ResourceManager
extends Node

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Economy")
@export_range(0.0, 100000.0, 1.0, "or_greater") var main_resource: float = 200.0
@export_range(0, 1000, 1, "or_greater") var building_cap: int = 20
@export_range(0, 1000, 1, "or_greater") var mirror_cap: int = 6

@export_group("Kill Drop")
@export var kill_drop_enabled: bool = true

@export_group("Occupied Tile Income")
@export var tile_income_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var tile_income_rate: float = 1.0

@export_group("Producer Income")
@export var producer_income_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var producer_income_rate: float = 2.0

@export_group("Time Growth")
@export var time_growth_enabled: bool = true
@export_range(0.0, 1000.0, 0.1, "or_greater") var time_growth_rate: float = 0.5

@export_group("Destroyed Tile Income")
@export var destroy_tile_income_enabled: bool = true
@export_range(0, 100000, 1, "or_greater") var destroy_tile_income_amount: int = 20

signal resource_changed(current: float, delta: float, reason: String)
signal limits_changed(building_count: int, building_limit: int, mirror_count: int, mirror_limit: int)

var _tile_manager: TileManager
var _building_count: int = 0
var _mirror_count: int = 0
var _occupied_tile_count: int = 0
var _producer_count: int = 0
var _tile_income_buffer: float = 0.0
var _producer_income_buffer: float = 0.0
var _time_income_buffer: float = 0.0

func _process(delta: float) -> void:
	if not feature_enabled:
		return
	if tile_income_enabled and _occupied_tile_count > 0:
		_tile_income_buffer += tile_income_rate * float(_occupied_tile_count) * delta
		_tile_income_buffer = _flush_income(_tile_income_buffer, "tile_income")
	if producer_income_enabled and _producer_count > 0:
		_producer_income_buffer += producer_income_rate * float(_producer_count) * delta
		_producer_income_buffer = _flush_income(_producer_income_buffer, "producer_income")
	if time_growth_enabled:
		_time_income_buffer += time_growth_rate * delta
		_time_income_buffer = _flush_income(_time_income_buffer, "time_growth")

func configure(tile_manager: TileManager) -> void:
	if _tile_manager != null and _tile_manager.obstacle_destroyed.is_connected(_on_obstacle_destroyed):
		_tile_manager.obstacle_destroyed.disconnect(_on_obstacle_destroyed)
	_tile_manager = tile_manager
	if _tile_manager != null:
		_tile_manager.obstacle_destroyed.connect(_on_obstacle_destroyed)

func apply_level_configuration(level_resource: LevelResource) -> void:
	if level_resource == null:
		return
	main_resource = float(level_resource.initial_resource)
	building_cap = level_resource.building_cap
	mirror_cap = level_resource.mirror_cap
	kill_drop_enabled = level_resource.kill_drop_enabled
	tile_income_enabled = level_resource.tile_income_enabled
	tile_income_rate = level_resource.tile_income_rate
	producer_income_enabled = level_resource.producer_income_enabled
	producer_income_rate = level_resource.producer_income_rate
	time_growth_enabled = level_resource.time_growth_enabled
	time_growth_rate = level_resource.time_growth_rate
	destroy_tile_income_enabled = level_resource.destroy_tile_income_enabled
	destroy_tile_income_amount = level_resource.destroy_tile_income_amount
	_building_count = 0
	_mirror_count = 0
	_occupied_tile_count = 0
	_producer_count = 0
	_reset_income_buffers()
	resource_changed.emit(main_resource, 0.0, "level_loaded")
	_emit_limits_changed()

func can_afford(cost: float) -> bool:
	return feature_enabled and cost >= 0.0 and main_resource >= cost

func spend(cost: float, reason: String = "spend") -> bool:
	if not can_afford(cost):
		return false
	main_resource -= cost
	resource_changed.emit(main_resource, -cost, reason)
	return true

func gain(amount: float, reason: String = "gain") -> void:
	if not feature_enabled or amount <= 0.0:
		return
	main_resource += amount
	resource_changed.emit(main_resource, amount, reason)

func can_add_building() -> bool:
	return feature_enabled and _building_count < building_cap

func try_register_building(cost: float) -> bool:
	if not can_add_building() or not spend(cost, "building_cost"):
		return false
	_building_count += 1
	_occupied_tile_count = _building_count
	_emit_limits_changed()
	return true

func unregister_building(refund: float = 0.0) -> void:
	_building_count = maxi(0, _building_count - 1)
	_occupied_tile_count = _building_count
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

func set_occupied_tile_count(value: int) -> void:
	_occupied_tile_count = maxi(0, value)

func set_producer_count(value: int) -> void:
	_producer_count = maxi(0, value)

func grant_kill_drop(amount: float) -> void:
	if kill_drop_enabled:
		gain(amount, "kill_drop")

func grant_destroy_tile_income() -> void:
	if destroy_tile_income_enabled:
		gain(float(destroy_tile_income_amount), "destroy_tile")

func get_building_count() -> int:
	return _building_count

func get_mirror_count() -> int:
	return _mirror_count

func _flush_income(buffer: float, reason: String) -> float:
	var whole_amount := floorf(buffer)
	if whole_amount >= 1.0:
		gain(whole_amount, reason)
		return buffer - whole_amount
	return buffer

func _reset_income_buffers() -> void:
	_tile_income_buffer = 0.0
	_producer_income_buffer = 0.0
	_time_income_buffer = 0.0

func _emit_limits_changed() -> void:
	limits_changed.emit(_building_count, building_cap, _mirror_count, mirror_cap)

func _on_obstacle_destroyed(_cell: Vector3i) -> void:
	grant_destroy_tile_income()
