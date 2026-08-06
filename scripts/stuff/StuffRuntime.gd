## StuffRuntime -- one independent runtime instance above a Grid cell.
##
## It owns mutable durability only. Terrain, occupancy and rendering remain in
## their respective modules. Mirror projections share this runtime as source.
class_name StuffRuntime
extends Node3D

const PathBlockerPolicyScript := preload("res://scripts/path/PathBlockerPolicy.gd")

signal durability_changed(stuff: StuffRuntime, current: float, maximum: float)
signal depleted(stuff: StuffRuntime, attacker: Node)

var placement_id: StringName = &""
var cell: Vector3i = Vector3i.ZERO
var definition: StuffDefinition
var facing_index: int = 0
var current_durability: float = 0.0
var max_durability: float = 0.0

var _grid: GridManager
var _surface_height_resolver: Callable
var _visual_snapshot_resolver: Callable
var _depleted: bool = false


func configure(
	p_placement: StuffPlacementData,
	grid_manager: GridManager,
	surface_height_resolver: Callable
) -> bool:
	if p_placement == null or p_placement.definition == null or grid_manager == null:
		return false
	placement_id = p_placement.placement_id
	cell = p_placement.cell
	definition = p_placement.definition
	facing_index = p_placement.facing_index
	_grid = grid_manager
	_surface_height_resolver = surface_height_resolver
	var effect := get_effect()
	max_durability = definition.get_max_durability()
	current_durability = max_durability
	_depleted = false
	refresh_world_transform()
	return true


func set_visual_snapshot_resolver(value: Callable) -> void:
	_visual_snapshot_resolver = value


func refresh_world_transform() -> void:
	if _grid == null:
		return
	var height := 0.0
	if _surface_height_resolver.is_valid():
		var resolved: Variant = _surface_height_resolver.call(cell)
		if resolved is float or resolved is int:
			height = float(resolved)
	position = _grid.cell_to_world(cell) + Vector3.UP * height
	var direction := get_facing_direction()
	rotation.y = atan2(-direction.x, -direction.z)


func get_effect() -> TileEffect:
	return definition.effect if definition != null else null


func get_effect_state_key() -> String:
	return "stuff:%s" % String(placement_id)


func get_stuff_definition() -> StuffDefinition:
	return definition


func get_copy_kind() -> StringName:
	var effect := get_effect()
	if effect != null and not effect.get_copy_kind().is_empty():
		return effect.get_copy_kind()
	return StringName("stuff_%s" % String(definition.stuff_id)) if definition != null else &""


func get_copy_display_name() -> String:
	var effect := get_effect()
	return effect.get_copy_display_name() if effect != null else (definition.display_name if definition != null else "")


func get_copy_color() -> Color:
	var effect := get_effect()
	return effect.get_copy_color() if effect != null else (definition.fallback_color if definition != null else Color.WHITE)


func get_facing_direction() -> Vector3:
	if _grid == null:
		return Vector3.FORWARD
	var count := _grid.get_tile_content_facing_count()
	if count == 8:
		var square_angle := deg_to_rad(45.0 * float(posmod(facing_index, count)))
		return Vector3(cos(square_angle), 0.0, sin(square_angle)).normalized()
	var hex_angle := deg_to_rad(-30.0 + 60.0 * float(posmod(facing_index, maxi(1, count))))
	return Vector3(cos(hex_angle), 0.0, sin(hex_angle)).normalized()


func is_structure_alive() -> bool:
	return not _depleted and (max_durability <= 0.0 or current_durability > 0.0)


func is_destructible() -> bool:
	return max_durability > 0.0


func blocks_enemy_navigation(target: Node = null) -> bool:
	return (
		is_structure_alive()
		and definition != null
		and definition.blocks_enemy_navigation(target)
	)


func can_use_for_reroute(target: Node = null) -> bool:
	return (
		not is_structure_alive()
		or definition == null
		or definition.can_use_for_reroute(target)
	)


func affects_target(target: Node) -> bool:
	if definition != null and definition.enemy_navigation != StuffDefinition.EnemyNavigation.PASSABLE:
		return definition.navigation_affects_target(target)
	var effect := get_effect()
	return effect == null or effect.affects_target(target)


func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not is_destructible() or not is_structure_alive() or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_durability)
	current_durability -= applied
	durability_changed.emit(self, current_durability, max_durability)
	if current_durability <= 0.0:
		_depleted = true
		depleted.emit(self, attacker)
	return applied


func get_structure_target_position() -> Vector3:
	var size := _grid.cell_size if _grid != null else 1.0
	return global_position + Vector3.UP * size * 0.42


func get_structure_hit_radius() -> float:
	return (_grid.cell_size if _grid != null else 1.0) * 0.32


func get_path_blocker_response() -> int:
	return PathBlockerPolicyScript.Response.REROUTE_THEN_ATTACK


func create_copy_visual_snapshot() -> Node3D:
	if not _visual_snapshot_resolver.is_valid():
		return null
	return _visual_snapshot_resolver.call(placement_id) as Node3D


func get_copy_visual_transform() -> Transform3D:
	return global_transform


func sync_copy_visual_snapshot(_snapshot: Node3D) -> void:
	pass
