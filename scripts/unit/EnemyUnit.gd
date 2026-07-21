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
signal rerouted(unit: EnemyUnit, from_path: PathDefinition, to_path: PathDefinition, join_cell: Vector3i)
signal route_blocked(unit: EnemyUnit, blocked_cell: Vector3i)

var definition: EnemyDefinition
var armor: float = 0.0
var damage_to_base: float = 10.0

var _path_points := PackedVector3Array()
var _path_cells: Array[Vector3i] = []
var _path_index: int = 0
var _active_path: PathDefinition
var _reached_base: bool = false
var _grid_cell_size: float = 1.0
var _flight_height: float = 0.0
var _blocker_resolver: Callable
var _route_resolver: Callable
var _cell_world_resolver: Callable
var _tile_enter_resolver: Callable
var _tile_stay_resolver: Callable
var _navigation_blocker_resolver: Callable
var _tile_effects_initialized: bool = false
var _waiting_blocked_cell: Vector3i = Vector3i.ZERO
var _is_waiting_for_route: bool = false
var _reroute_attack_target: Node
var _attack_target: Node
var _attack_strategy: EnemyAttackStrategy
var _attack_damage: float = 0.0
var _attacks_per_second: float = 1.0
var _attack_range_world: float = 0.65

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if not feature_enabled or not is_alive() or _reached_base or _path_points.is_empty():
		return
	_initialize_tile_effects()
	if not is_alive():
		return
	if _path_points.size() < 2:
		_apply_current_tile_stay(delta)
		return
	var blocker_info := _find_first_path_blocker()
	if blocker_info.is_empty():
		blocker_info = _get_reroute_attack_blocker_info()
	if not blocker_info.is_empty():
		var blocker: Node = blocker_info["node"]
		var blocker_position := _get_blocker_position(blocker)
		if _is_within_attack_range(blocker_position):
			_enter_attack_state(blocker)
			_face_target(blocker_position)
			_apply_current_tile_stay(delta)
			if not is_alive():
				return
			_attack_strategy.tick(self, delta)
			return
		_leave_attack_state()
		var movement_limit := _get_path_distance_until_attack_range(blocker_info)
		var movement_duration := _move_along_path(minf(move_speed * maxf(0.0, delta), movement_limit))
		_apply_current_tile_stay(maxf(0.0, delta - movement_duration))
		if is_alive() and is_instance_valid(blocker) and _is_within_attack_range(_get_blocker_position(blocker)):
			_enter_attack_state(blocker)
			_face_target(_get_blocker_position(blocker))
			_attack_strategy.tick(self, 0.0)
		return
	_leave_attack_state()
	var movement_duration := _move_along_path(move_speed * maxf(0.0, delta))
	_apply_current_tile_stay(maxf(0.0, delta - movement_duration))

func configure_unit(
	enemy_definition: EnemyDefinition,
	path_points: PackedVector3Array,
	path_cells: Array[Vector3i] = [],
	grid_cell_size: float = 1.0,
	blocker_resolver: Callable = Callable(),
	path_definition: PathDefinition = null,
	route_resolver: Callable = Callable(),
	cell_world_resolver: Callable = Callable(),
	tile_enter_resolver: Callable = Callable(),
	tile_stay_resolver: Callable = Callable(),
	navigation_blocker_resolver: Callable = Callable()
) -> void:
	definition = enemy_definition
	_path_points.clear()
	_path_cells.clear()
	_path_cells.append_array(path_cells)
	_path_index = 0
	_active_path = path_definition
	_reached_base = false
	_grid_cell_size = maxf(0.1, grid_cell_size)
	_blocker_resolver = blocker_resolver
	_route_resolver = route_resolver
	_cell_world_resolver = cell_world_resolver
	_tile_enter_resolver = tile_enter_resolver
	_tile_stay_resolver = tile_stay_resolver
	_navigation_blocker_resolver = navigation_blocker_resolver
	_tile_effects_initialized = false
	_is_waiting_for_route = false
	_reroute_attack_target = null
	_attack_target = null
	_attack_strategy = EnemyAttackStrategyScript.new()
	airborne = definition != null and definition.is_airborne
	_flight_height = maxf(0.0, definition.flight_height) if airborne else 0.0
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
	for point in path_points:
		_path_points.append(_with_flight_height(point))
	if not _path_points.is_empty():
		# Configured before add_child() so CombatTarget._ready() uses definition visuals.
		position = _path_points[0]

func take_damage(amount: float) -> float:
	return super.take_damage(maxf(0.0, amount - armor))

func take_damage_over_time(damage_per_second: float, duration: float) -> float:
	return super.take_damage_over_time(maxf(0.0, damage_per_second - armor), duration)

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

func _move_along_path(remaining_distance: float) -> float:
	var movement_duration := 0.0
	while remaining_distance > 0.0 and _path_index < _path_points.size() - 1:
		var navigation_state := _resolve_next_terrain_blocker()
		if navigation_state < 0:
			break
		if navigation_state > 0:
			continue
		var destination := _path_points[_path_index + 1]
		var to_destination := destination - global_position
		var distance_to_destination := to_destination.length()
		if distance_to_destination <= 0.0001:
			_path_index += 1
			_apply_tile_enter(_path_cells[_path_index] if _path_index < _path_cells.size() else Vector3i.ZERO)
			if not is_alive():
				break
			continue
		var traveled_distance := minf(distance_to_destination, remaining_distance)
		var traveled_duration := traveled_distance / maxf(0.0001, move_speed)
		_apply_current_tile_stay(traveled_duration)
		movement_duration += traveled_duration
		if not is_alive():
			break
		if distance_to_destination <= remaining_distance:
			global_position = destination
			remaining_distance -= distance_to_destination
			_path_index += 1
			_apply_tile_enter(_path_cells[_path_index] if _path_index < _path_cells.size() else Vector3i.ZERO)
			if not is_alive():
				break
		else:
			var direction := to_destination / distance_to_destination
			global_position += direction * remaining_distance
			_face_direction(direction)
			remaining_distance = 0.0
	if is_alive() and _path_index >= _path_points.size() - 1:
		_reach_base()
	return movement_duration

## -1 remains blocked/prepares the fallback attack, 0 continues on the current
## route, 1 installed a new route.
func _resolve_next_terrain_blocker() -> int:
	if _is_blocker_alive(_reroute_attack_target):
		# A failed detour has promoted this terrain blocker to a normal attack
		# target. Limited approach movement may now enter its attack circle.
		return 0
	if not _route_resolver.is_valid() or _path_index >= _path_cells.size() - 1:
		_reroute_attack_target = null
		_is_waiting_for_route = false
		return 0
	# The unit can already be partway through this logical segment after attacking
	# a higher-priority blocker. Re-check the destination cell here so a rebuilt
	# terrain projection cannot be bypassed merely because the unit left the
	# preceding cell center.
	var current_cell := _path_cells[_path_index]
	var blocked_cell := _path_cells[_path_index + 1]
	var resolution: Variant = _route_resolver.call(_active_path, current_cell, blocked_cell, self)
	if not resolution is Dictionary or not bool(resolution.get("triggered", false)):
		_reroute_attack_target = null
		_is_waiting_for_route = false
		return 0
	if not bool(resolution.get("found", false)):
		if not _is_waiting_for_route or _waiting_blocked_cell != blocked_cell:
			route_blocked.emit(self, blocked_cell)
		_waiting_blocked_cell = blocked_cell
		_is_waiting_for_route = true
		var blocker_value: Variant = resolution.get("blocker")
		_reroute_attack_target = blocker_value as Node if blocker_value is Node else null
		return -1
	var route_value: Variant = resolution.get("cells", [])
	if not route_value is Array or route_value.size() < 2:
		return -1
	var route_cells: Array[Vector3i] = []
	for raw_cell in route_value:
		if raw_cell is Vector3i:
			route_cells.append(raw_cell)
	if route_cells.size() < 2:
		return -1
	var route_points := PackedVector3Array()
	for cell in route_cells:
		if _cell_world_resolver.is_valid():
			var point: Variant = _cell_world_resolver.call(cell)
			if not point is Vector3:
				return -1
			route_points.append(_with_flight_height(point))
		else:
			route_points.append(global_position if cell == current_cell else Vector3.ZERO)
	if not _cell_world_resolver.is_valid():
		return -1
	var previous_path := _active_path
	_path_cells = route_cells
	_path_points = route_points
	_path_index = 0
	_active_path = resolution.get("path") as PathDefinition
	_reroute_attack_target = null
	_is_waiting_for_route = false
	rerouted.emit(self, previous_path, _active_path, resolution.get("join_cell", current_cell))
	return 1

func _initialize_tile_effects() -> void:
	if _tile_effects_initialized:
		return
	_tile_effects_initialized = true
	if not _path_cells.is_empty():
		_apply_tile_enter(_path_cells[clampi(_path_index, 0, _path_cells.size() - 1)])

func _apply_tile_enter(cell: Vector3i) -> void:
	if _tile_enter_resolver.is_valid():
		_tile_enter_resolver.call(self, cell)

func _apply_current_tile_stay(duration: float) -> void:
	if duration <= 0.0 or not _tile_stay_resolver.is_valid() or _path_cells.is_empty():
		return
	var cell := _path_cells[clampi(_path_index, 0, _path_cells.size() - 1)]
	_tile_stay_resolver.call(self, cell, duration)

func _find_first_path_blocker() -> Dictionary:
	if not _blocker_resolver.is_valid() or _path_cells.size() < 2:
		return {}
	var last_segment := mini(_path_cells.size(), _path_points.size()) - 1
	for segment_index in range(clampi(_path_index, 0, last_segment), last_segment):
		var from_cell := _path_cells[segment_index]
		var to_cell := _path_cells[segment_index + 1]
		var candidate: Variant = _blocker_resolver.call(from_cell, to_cell, self)
		if candidate is Node:
			var blocker: Node = candidate
			if _is_blocker_alive(blocker):
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
		if _navigation_blocker_resolver.is_valid() and bool(_navigation_blocker_resolver.call(to_cell, self)):
			break
	return {}

func _get_reroute_attack_blocker_info() -> Dictionary:
	if not _is_blocker_alive(_reroute_attack_target):
		_reroute_attack_target = null
		return {}
	if _path_points.size() < 2 or _path_index >= _path_points.size() - 1:
		return {}
	var blocker_position := _get_blocker_position(_reroute_attack_target)
	var segment_index := clampi(_path_index, 0, _path_points.size() - 2)
	return {
		"node": _reroute_attack_target,
		"segment_index": segment_index,
		"segment_ratio": _get_horizontal_segment_ratio(
			_path_points[segment_index],
			_path_points[segment_index + 1],
			blocker_position
		),
		"position": blocker_position,
	}

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

## Accepts Variant deliberately: Godot rejects a previously freed Object before
## entering a function whose parameter is typed as Node, so the validity guard
## must run before narrowing the blocker contract.
func _is_blocker_alive(blocker: Variant) -> bool:
	if typeof(blocker) != TYPE_OBJECT or blocker == null or not is_instance_valid(blocker):
		return false
	if blocker.is_queued_for_deletion():
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

func _with_flight_height(world_position: Vector3) -> Vector3:
	return world_position + Vector3.UP * _flight_height

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
