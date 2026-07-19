## Homing enemy projectile targeting the path-blocker structure contract.
class_name EnemyProjectile
extends Node3D

signal impacted(target: Node, applied_damage: float)

var _target: Node
var _attacker: Node
var _last_target_position: Vector3
var _speed: float = 1.0
var _damage: float = 0.0
var _maximum_distance: float = 1.0
var _distance_traveled: float = 0.0
var _active: bool = false

func _process(delta: float) -> void:
	if not _active:
		return
	if not _is_attacker_alive() or not _is_target_alive():
		queue_free()
		return
	_last_target_position = _get_target_position()
	var to_target := _last_target_position - global_position
	var distance_to_target := to_target.length()
	var step_distance := _speed * maxf(0.0, delta)
	var remaining_distance := _maximum_distance - _distance_traveled
	if remaining_distance <= 0.0:
		queue_free()
		return
	var travel_distance := minf(step_distance, remaining_distance)
	var hit_radius := _get_target_hit_radius()
	if distance_to_target <= travel_distance + hit_radius:
		global_position = _last_target_position
		_impact()
		return
	var direction := to_target.normalized()
	global_position += direction * travel_distance
	_distance_traveled += travel_distance
	_update_orientation(direction)
	if _distance_traveled >= _maximum_distance:
		queue_free()

func configure(
	start: Vector3,
	target: Node,
	attacker: Node,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color
) -> void:
	global_position = start
	_target = target
	_attacker = attacker
	_last_target_position = _get_target_position()
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, maximum_distance)
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color)
	_update_orientation((_last_target_position - start).normalized())
	_active = true

func _impact() -> void:
	_active = false
	var applied_damage: float = 0.0
	if _is_target_alive() and _target.has_method("take_structure_damage"):
		applied_damage = float(_target.call("take_structure_damage", _damage, _attacker))
		impacted.emit(_target, applied_damage)
	queue_free()

func _is_attacker_alive() -> bool:
	if _attacker == null or not is_instance_valid(_attacker):
		return false
	if _attacker.has_method("is_alive"):
		return bool(_attacker.call("is_alive"))
	return not _attacker.is_queued_for_deletion()

func _is_target_alive() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _target.has_method("is_structure_alive"):
		return bool(_target.call("is_structure_alive"))
	return not _target.is_queued_for_deletion()

func _get_target_position() -> Vector3:
	if _target != null and is_instance_valid(_target) and _target.has_method("get_structure_target_position"):
		var target_position: Vector3 = _target.call("get_structure_target_position")
		return target_position
	if _target is Node3D:
		return (_target as Node3D).global_position
	return global_position

func _get_target_hit_radius() -> float:
	if _target != null and is_instance_valid(_target) and _target.has_method("get_structure_hit_radius"):
		return maxf(0.0, float(_target.call("get_structure_hit_radius")))
	return 0.0

func _build_visual(length: float, width: float, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	mesh_instance.material_override = material
	add_child(mesh_instance)

func _update_orientation(direction: Vector3) -> void:
	if direction.length_squared() <= 0.000001:
		return
	look_at(global_position + direction, Vector3.UP)
