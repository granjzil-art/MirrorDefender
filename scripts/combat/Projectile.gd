## Homing M3 projectile with constant short-line presentation and impact damage.
class_name Projectile
extends Node3D

signal impacted(target: CombatTarget, applied_damage: float)

var _target: CombatTarget
var _last_target_position: Vector3
var _speed: float = 1.0
var _damage: float = 0.0
var _maximum_distance: float = 1.0
var _distance_traveled: float = 0.0
var _active: bool = false

func _process(delta: float) -> void:
	if not _active:
		return
	if is_instance_valid(_target) and _target.is_alive():
		_last_target_position = _target.get_target_position()
	var to_target := _last_target_position - global_position
	var distance_to_target := to_target.length()
	var hit_radius := _target.hit_radius if is_instance_valid(_target) else 0.0
	var step_distance := _speed * delta
	var remaining_distance := _maximum_distance - _distance_traveled
	if remaining_distance <= 0.0:
		queue_free()
		return
	var travel_distance := minf(step_distance, remaining_distance)
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
	target: CombatTarget,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color
) -> void:
	global_position = start
	_target = target
	_last_target_position = target.get_target_position()
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_maximum_distance = maxf(0.1, maximum_distance)
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color)
	_update_orientation((_last_target_position - start).normalized())
	_active = true

func _impact() -> void:
	_active = false
	var applied_damage: float = 0.0
	if is_instance_valid(_target) and _target.is_alive():
		applied_damage = _target.take_damage(_damage)
		impacted.emit(_target, applied_damage)
	queue_free()

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
