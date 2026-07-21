## Per-cell runtime durability and attack target for a destructible tile effect.
class_name TileObstacleRuntime
extends Node3D

const PathBlockerPolicyScript := preload("res://scripts/path/PathBlockerPolicy.gd")

signal durability_changed(obstacle: TileObstacleRuntime, current: float, maximum: float)
signal depleted(obstacle: TileObstacleRuntime, attacker: Node)

var cell: Vector3i = Vector3i.ZERO
var effect: TileEffect
var current_durability: float = 0.0
var max_durability: float = 0.0

var _grid: GridManager
var _tile_manager: Node
var _depleted: bool = false

func configure(
	p_cell: Vector3i,
	p_effect: TileEffect,
	grid_manager: GridManager,
	tile_manager: Node
) -> void:
	cell = p_cell
	effect = p_effect
	_grid = grid_manager
	_tile_manager = tile_manager
	max_durability = maxf(1.0, effect.get_max_durability()) if effect != null else 1.0
	current_durability = max_durability
	_depleted = false
	refresh_world_position()

func refresh_world_position() -> void:
	if _grid == null or _tile_manager == null:
		return
	global_position = _grid.cell_to_world(cell) + Vector3.UP * _tile_manager.get_world_height(cell)

func is_structure_alive() -> bool:
	return not _depleted and current_durability > 0.0

func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not is_structure_alive() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var applied_damage := minf(amount, current_durability)
	current_durability -= applied_damage
	durability_changed.emit(self, current_durability, max_durability)
	if current_durability <= 0.0:
		_depleted = true
		depleted.emit(self, attacker)
	return applied_damage

func get_structure_target_position() -> Vector3:
	var cell_size := _grid.cell_size if _grid != null else 1.0
	return global_position + Vector3.UP * cell_size * 0.42

func get_structure_hit_radius() -> float:
	return (_grid.cell_size if _grid != null else 1.0) * 0.32

func get_path_blocker_response() -> int:
	return PathBlockerPolicyScript.Response.REROUTE_THEN_ATTACK

func affects_target(target: Node) -> bool:
	return effect != null and effect.affects_target(target)
