## M4 combat target that moves along a fixed path and attacks path blockers.
class_name EnemyUnit
extends CombatTarget

const EnemyAttackStrategyScript := preload("res://scripts/combat/EnemyAttackStrategy.gd")
const EnemyProjectileScript := preload("res://scripts/combat/EnemyProjectile.gd")

signal reached_base(unit: EnemyUnit, damage_to_base: float)
signal attack_started(unit: EnemyUnit, target: Node)
signal attack_stopped(unit: EnemyUnit, target: Node)
signal attack_performed(unit: EnemyUnit, target: Node, applied_damage: float, ranged: bool)
signal projectile_spawned(unit: EnemyUnit, projectile: EnemyProjectile)

var definition: EnemyDefinition
var armor: float = 0.0
var damage_to_base: float = 10.0

var _path_points := PackedVector3Array()
var _path_cells: Array[Vector3i] = []
var _path_index: int = 0
var _reached_base: bool = false
var _grid_cell_size: float = 1.0
var _blocker_resolver: Callable
var _attack_target: Node
var _attack_strategy: EnemyAttackStrategy
var _attack_damage: float = 0.0
var _attacks_per_second: float = 1.0
var _attack_range_world: float = 0.65

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if not feature_enabled or not is_alive() or _reached_base or _path_points.size() < 2:
		return
	var blocker := _find_first_path_blocker()
	if blocker != null:
		var distance_to_blocker := _horizontal_distance_to(_get_blocker_position(blocker))
		if distance_to_blocker <= _attack_range_world:
			_enter_attack_state(blocker)
			_face_target(_get_blocker_position(blocker))
			_attack_strategy.tick(self, delta)
			return
		_leave_attack_state()
		var movement_limit := maxf(0.0, distance_to_blocker - _attack_range_world)
		_move_along_path(minf(move_speed * maxf(0.0, delta), movement_limit))
		if is_alive() and is_instance_valid(blocker) and _horizontal_distance_to(_get_blocker_position(blocker)) <= _attack_range_world:
			_enter_attack_state(blocker)
			_face_target(_get_blocker_position(blocker))
			_attack_strategy.tick(self, 0.0)
		return
	_leave_attack_state()
	_move_along_path(move_speed * maxf(0.0, delta))

func configure_unit(
	enemy_definition: EnemyDefinition,
	path_points: PackedVector3Array,
	path_cells: Array[Vector3i] = [],
	grid_cell_size: float = 1.0,
	blocker_resolver: Callable = Callable()
) -> void:
	definition = enemy_definition
	_path_points = path_points
	_path_cells.clear()
	_path_cells.append_array(path_cells)
	_path_index = 0
	_reached_base = false
	_grid_cell_size = maxf(0.1, grid_cell_size)
	_blocker_resolver = blocker_resolver
	_attack_target = null
	_attack_strategy = EnemyAttackStrategyScript.new()
	if definition != null:
		max_hp = maxf(1.0, definition.max_hp)
		current_hp = max_hp
		move_speed = maxf(0.1, definition.move_speed)
		armor = maxf(0.0, definition.armor)
		damage_to_base = maxf(1.0, definition.base_damage)
		reward = maxf(0.0, definition.reward)
		hit_radius = definition.hit_radius
		debug_color = definition.body_color
		debug_height = definition.body_height
		_attack_damage = maxf(0.0, definition.attack_damage)
		_attacks_per_second = maxf(0.01, definition.attacks_per_second)
		_attack_range_world = maxf(0.1, definition.attack_range * _grid_cell_size)
	if not _path_points.is_empty():
		# Configured before add_child() so CombatTarget._ready() uses definition visuals.
		position = _path_points[0]

func take_damage(amount: float) -> float:
	return super.take_damage(maxf(0.0, amount - armor))

func is_attacking() -> bool:
	return _attack_target != null and is_instance_valid(_attack_target) and _is_blocker_alive(_attack_target) and _horizontal_distance_to(_get_blocker_position(_attack_target)) <= _attack_range_world

func get_attack_target() -> Node:
	return _attack_target if is_attacking() else null

func get_attacks_per_second() -> float:
	return _attacks_per_second

func get_attack_range_world() -> float:
	return _attack_range_world

func perform_attack(target: Node) -> void:
	if target == null or not is_instance_valid(target) or not _is_blocker_alive(target):
		return
	if definition != null and definition.projectile_speed > 0.0:
		_launch_projectile(target)
		return
	var applied_damage := float(target.call("take_structure_damage", _attack_damage, self))
	attack_performed.emit(self, target, applied_damage, false)

func _move_along_path(remaining_distance: float) -> void:
	while remaining_distance > 0.0 and _path_index < _path_points.size() - 1:
		var destination := _path_points[_path_index + 1]
		var to_destination := destination - global_position
		var distance_to_destination := to_destination.length()
		if distance_to_destination <= 0.0001:
			_path_index += 1
			continue
		if distance_to_destination <= remaining_distance:
			global_position = destination
			remaining_distance -= distance_to_destination
			_path_index += 1
		else:
			var direction := to_destination / distance_to_destination
			global_position += direction * remaining_distance
			_face_direction(direction)
			remaining_distance = 0.0
	if _path_index >= _path_points.size() - 1:
		_reach_base()

func _find_first_path_blocker() -> Node:
	if not _blocker_resolver.is_valid() or _path_cells.is_empty():
		return null
	var start_index := clampi(_path_index + 1, 0, _path_cells.size())
	for index in range(start_index, _path_cells.size()):
		var candidate: Variant = _blocker_resolver.call(_path_cells[index])
		if candidate is Node:
			var blocker: Node = candidate
			if _is_blocker_alive(blocker):
				return blocker
	return null

func _is_blocker_alive(blocker: Node) -> bool:
	if blocker == null or not is_instance_valid(blocker) or blocker.is_queued_for_deletion():
		return false
	if not blocker.has_method("take_structure_damage") or not blocker.has_method("get_structure_target_position"):
		return false
	if blocker.has_method("is_structure_alive"):
		return bool(blocker.call("is_structure_alive"))
	return true

func _get_blocker_position(blocker: Node) -> Vector3:
	if blocker != null and is_instance_valid(blocker) and blocker.has_method("get_structure_target_position"):
		var target_position: Vector3 = blocker.call("get_structure_target_position")
		return target_position
	if blocker is Node3D:
		return (blocker as Node3D).global_position
	return global_position

func _horizontal_distance_to(world_position: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(world_position.x, world_position.z))

func _enter_attack_state(target: Node) -> void:
	if _attack_target == target:
		return
	_leave_attack_state()
	_attack_target = target
	_attack_strategy.reset(self)
	attack_started.emit(self, target)

func _leave_attack_state() -> void:
	if _attack_target == null:
		return
	var previous_target := _attack_target
	_attack_target = null
	if _attack_strategy != null:
		_attack_strategy.reset(self)
	attack_stopped.emit(self, previous_target)

func _launch_projectile(target: Node) -> void:
	var host := get_parent()
	if host == null or definition == null:
		return
	var projectile: EnemyProjectile = EnemyProjectileScript.new()
	host.add_child(projectile)
	var start := get_attack_origin()
	var target_position := _get_blocker_position(target)
	var maximum_distance := maxf(_attack_range_world, start.distance_to(target_position) + _grid_cell_size * 0.5)
	projectile.configure(
		start,
		target,
		self,
		definition.projectile_speed * _grid_cell_size,
		_attack_damage,
		maximum_distance,
		definition.projectile_length * _grid_cell_size,
		definition.projectile_width * _grid_cell_size,
		definition.attack_color
	)
	projectile.impacted.connect(_on_projectile_impacted)
	projectile_spawned.emit(self, projectile)

func get_attack_origin() -> Vector3:
	return global_position + Vector3(0.0, debug_height * 0.62, 0.0)

func _face_target(world_position: Vector3) -> void:
	_face_direction(world_position - global_position)

func _face_direction(direction: Vector3) -> void:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.000001:
		return
	look_at(global_position + horizontal, Vector3.UP)

func _on_projectile_impacted(target: Node, applied_damage: float) -> void:
	attack_performed.emit(self, target, applied_damage, true)

func _reach_base() -> void:
	if _reached_base:
		return
	_reached_base = true
	_leave_attack_state()
	feature_enabled = false
	reached_base.emit(self, damage_to_base)
	queue_free()
