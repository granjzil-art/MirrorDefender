## Combat module entry point for target registration and spatial queries.
class_name CombatManager
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Laser Query")
@export_range(0.01, 2.0, 0.01, "or_greater") var laser_hit_radius: float = 0.18

@export_group("Debug Targets")
@export_range(1.0, 100000.0, 1.0, "or_greater") var debug_target_hp: float = 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var debug_target_speed: float = 1.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var debug_target_reward: float = 5.0

signal target_registered(target: CombatTarget)
signal target_removed(target: CombatTarget)
signal target_killed(reward_amount: float)
signal projectile_spawned(projectile: Projectile)
signal projectile_hit(target: CombatTarget, applied_damage: float)

var _targets: Array[CombatTarget] = []
var _projectiles: Array[Projectile] = []
var _next_entry_order: int = 0
var _target_exit_callbacks: Dictionary = {}

func register_target(target: CombatTarget) -> bool:
	if not feature_enabled or target == null or _targets.has(target):
		return false
	target.entry_order = _next_entry_order
	_next_entry_order += 1
	_targets.append(target)
	if not target.died.is_connected(_on_target_died):
		target.died.connect(_on_target_died)
	var exit_callback := _on_target_tree_exited.bind(target)
	if not target.tree_exited.is_connected(exit_callback):
		target.tree_exited.connect(exit_callback)
	_target_exit_callbacks[target] = exit_callback
	target_registered.emit(target)
	return true

func unregister_target(target: CombatTarget) -> void:
	if target == null or not _targets.has(target):
		return
	_targets.erase(target)
	_disconnect_target(target)
	target_removed.emit(target)

func get_targets() -> Array[CombatTarget]:
	_cleanup_targets()
	return _targets.duplicate()

func get_targets_in_range(origin: Vector3, range_world: float) -> Array[CombatTarget]:
	var out: Array[CombatTarget] = []
	var maximum_distance_squared := range_world * range_world
	for target in get_targets():
		if _xz_distance_squared(origin, target.global_position) <= maximum_distance_squared:
			out.append(target)
	return out

func get_targets_on_segment(start: Vector3, end: Vector3) -> Array[CombatTarget]:
	var out: Array[CombatTarget] = []
	var segment_start := Vector2(start.x, start.z)
	var segment_end := Vector2(end.x, end.z)
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.000001:
		return out
	for target in get_targets():
		var point := Vector2(target.global_position.x, target.global_position.z)
		var along := clampf((point - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
		var closest := segment_start + segment * along
		var allowed_radius := target.hit_radius + laser_hit_radius
		if point.distance_squared_to(closest) <= allowed_radius * allowed_radius:
			out.append(target)
	return out

func spawn_debug_target(world_position: Vector3) -> CombatTarget:
	if not feature_enabled:
		return null
	var target := CombatTarget.new()
	add_child(target)
	target.configure_debug_target(
		world_position,
		debug_target_hp,
		debug_target_speed,
		debug_target_reward
	)
	register_target(target)
	return target

func spawn_projectile(
	start: Vector3,
	target: CombatTarget,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color
) -> Projectile:
	if not feature_enabled or target == null or not target.is_alive():
		return null
	var projectile := Projectile.new()
	add_child(projectile)
	projectile.configure(
		start,
		target,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color
	)
	projectile.impacted.connect(_on_projectile_impacted)
	projectile.tree_exited.connect(_on_projectile_tree_exited.bind(projectile))
	_projectiles.append(projectile)
	projectile_spawned.emit(projectile)
	return projectile

func clear_targets() -> void:
	var targets := _targets.duplicate()
	for target in targets:
		if is_instance_valid(target):
			unregister_target(target)
			target.queue_free()
	_targets.clear()
	_target_exit_callbacks.clear()
	_next_entry_order = 0
	clear_projectiles()

func clear_projectiles() -> void:
	var projectiles := _projectiles.duplicate()
	_projectiles.clear()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()

func _cleanup_targets() -> void:
	for index in range(_targets.size() - 1, -1, -1):
		var target := _targets[index]
		if target == null or not is_instance_valid(target):
			_targets.remove_at(index)
			_target_exit_callbacks.erase(target)
		elif not target.is_alive():
			unregister_target(target)

func _xz_distance_squared(a: Vector3, b: Vector3) -> float:
	var delta := Vector2(a.x - b.x, a.z - b.z)
	return delta.length_squared()

func _on_target_died(target: CombatTarget, reward_amount: float) -> void:
	unregister_target(target)
	target_killed.emit(reward_amount)

func _on_target_tree_exited(target: CombatTarget) -> void:
	unregister_target(target)

func _on_projectile_impacted(target: CombatTarget, applied_damage: float) -> void:
	projectile_hit.emit(target, applied_damage)

func _on_projectile_tree_exited(projectile: Projectile) -> void:
	_projectiles.erase(projectile)

func _disconnect_target(target: CombatTarget) -> void:
	if target == null or not is_instance_valid(target):
		_target_exit_callbacks.erase(target)
		return
	if target.died.is_connected(_on_target_died):
		target.died.disconnect(_on_target_died)
	if _target_exit_callbacks.has(target):
		var exit_callback: Callable = _target_exit_callbacks[target]
		if target.tree_exited.is_connected(exit_callback):
			target.tree_exited.disconnect(exit_callback)
	_target_exit_callbacks.erase(target)
