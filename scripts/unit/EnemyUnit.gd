## M4 combat target that moves along a fixed path and attacks path blockers.
class_name EnemyUnit
extends CombatTarget

const EnemyAttackStrategyScript := preload("res://scripts/combat/EnemyAttackStrategy.gd")
const EnemyProjectileScript := preload("res://scripts/combat/EnemyProjectile.gd")
const ATTACK_RANGE_EPSILON_RATIO := 0.001
const PATH_PROGRESS_EPSILON := 0.0001

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
	var blocker_info := _find_first_path_blocker()
	if not blocker_info.is_empty():
		var blocker: Node = blocker_info["node"]
		var blocker_position := _get_blocker_position(blocker)
		if _is_within_attack_range(blocker_position):
			_enter_attack_state(blocker)
			_face_target(blocker_position)
			_attack_strategy.tick(self, delta)
			return
		_leave_attack_state()
		var movement_limit := _get_path_distance_until_attack_range(blocker_info)
		_move_along_path(minf(move_speed * maxf(0.0, delta), movement_limit))
		if is_alive() and is_instance_valid(blocker) and _is_within_attack_range(_get_blocker_position(blocker)):
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
	return _attack_target != null and is_instance_valid(_attack_target) and _is_blocker_alive(_attack_target) and _is_within_attack_range(_get_blocker_position(_attack_target))

func get_attack_target() -> Node:
	return _attack_target if is_attacking() else null

func get_attacks_per_second() -> float:
	return _attacks_per_second

func get_attack_range_world() -> float:
	return _attack_range_world

func perform_attack(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not _is_blocker_alive(target):
		return false
	if definition != null and definition.projectile_speed > 0.0:
		return _launch_projectile(target) != null
	var applied_damage := float(target.call("take_structure_damage", _attack_damage, self))
	attack_performed.emit(self, target, applied_damage, false)
	return true

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

func _find_first_path_blocker() -> Dictionary:
	if not _blocker_resolver.is_valid() or _path_cells.size() < 2:
		return {}
	var last_segment := mini(_path_cells.size(), _path_points.size()) - 1
	for segment_index in range(clampi(_path_index, 0, last_segment), last_segment):
		var from_cell := _path_cells[segment_index]
		var to_cell := _path_cells[segment_index + 1]
		var candidate: Variant = _blocker_resolver.call(from_cell, to_cell)
		if not candidate is Node:
			continue
		var blocker: Node = candidate
		if not _is_blocker_alive(blocker):
			continue
		var blocker_position := _get_blocker_position(blocker)
		var segment_ratio := _get_horizontal_segment_ratio(
			_path_points[segment_index],
			_path_points[segment_index + 1],
			blocker_position
		)
		if segment_index == _path_index:
			var current_ratio := _get_horizontal_segment_ratio(
				_path_points[segment_index],
				_path_points[segment_index + 1],
				global_position
			)
			if segment_ratio + PATH_PROGRESS_EPSILON < current_ratio:
				continue
		return {
			"node": blocker,
			"segment_index": segment_index,
			"segment_ratio": segment_ratio,
			"position": blocker_position,
		}
	return {}

## Returns travel distance along the authored polyline until the unit first
## enters the horizontal attack circle. This avoids chord-distance stalls at
## bends and works for both tile-center and edge-midpoint blockers.
func _get_path_distance_until_attack_range(blocker_info: Dictionary) -> float:
	var blocker_position: Vector3 = blocker_info["position"]
	if _is_within_attack_range(blocker_position):
		return 0.0
	var target_segment: int = int(blocker_info["segment_index"])
	var target_ratio: float = float(blocker_info["segment_ratio"])
	var segment_start := global_position
	var accumulated_distance := 0.0
	for segment_index in range(_path_index, target_segment + 1):
		var segment_end := _path_points[segment_index + 1]
		if segment_index == target_segment:
			segment_end = _path_points[segment_index].lerp(
				_path_points[segment_index + 1],
				target_ratio
			)
		var entry_ratio := _get_attack_circle_entry_ratio(
			segment_start,
			segment_end,
			blocker_position,
			_attack_range_world
		)
		var segment_length := segment_start.distance_to(segment_end)
		if entry_ratio >= 0.0:
			return accumulated_distance + segment_length * entry_ratio
		accumulated_distance += segment_length
		segment_start = segment_end
	return accumulated_distance

func _get_attack_circle_entry_ratio(
	segment_start: Vector3,
	segment_end: Vector3,
	center: Vector3,
	radius: float
) -> float:
	var start_2d := Vector2(segment_start.x, segment_start.z)
	var end_2d := Vector2(segment_end.x, segment_end.z)
	var center_2d := Vector2(center.x, center.z)
	if start_2d.distance_squared_to(center_2d) <= radius * radius:
		return 0.0
	var direction := end_2d - start_2d
	var a := direction.length_squared()
	if a <= 0.0000001:
		return -1.0
	var offset := start_2d - center_2d
	var b := 2.0 * offset.dot(direction)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * a)
	var second := (-b + root) / (2.0 * a)
	if first >= 0.0 and first <= 1.0:
		return first
	if second >= 0.0 and second <= 1.0:
		return second
	return -1.0

func _get_horizontal_segment_ratio(start: Vector3, end: Vector3, point: Vector3) -> float:
	var start_2d := Vector2(start.x, start.z)
	var direction := Vector2(end.x, end.z) - start_2d
	var length_squared := direction.length_squared()
	if length_squared <= 0.0000001:
		return 0.0
	var point_2d := Vector2(point.x, point.z)
	return clampf((point_2d - start_2d).dot(direction) / length_squared, 0.0, 1.0)

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

func _get_attack_range_epsilon() -> float:
	return maxf(0.0005, _grid_cell_size * ATTACK_RANGE_EPSILON_RATIO)

func _is_within_attack_range(world_position: Vector3) -> bool:
	return _horizontal_distance_to(world_position) <= _attack_range_world + _get_attack_range_epsilon()

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

func _launch_projectile(target: Node) -> EnemyProjectile:
	var host := get_parent()
	if host == null or definition == null:
		return null
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
	return projectile

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
