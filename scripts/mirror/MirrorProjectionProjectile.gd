## Fixed-end projectile used by a tower projection. It never homes or retargets.
class_name MirrorProjectionProjectile
extends Node3D

signal impacted(target: CombatTarget, applied_damage: float)

var _combat_manager: CombatManager
var _source_building: Building
var _end: Vector3
var _speed: float = 1.0
var _damage: float = 0.0
var _active: bool = false

func configure(
	combat_manager: CombatManager,
	source_building: Building,
	start: Vector3,
	end: Vector3,
	speed: float,
	damage: float,
	visual_length: float,
	visual_width: float,
	color: Color
) -> void:
	_combat_manager = combat_manager
	_source_building = source_building
	global_position = start
	_end = end
	_speed = maxf(0.1, speed)
	_damage = maxf(0.0, damage)
	_build_visual(maxf(0.1, visual_length), maxf(0.02, visual_width), color)
	_update_orientation((_end - start).normalized())
	_active = true

func _process(delta: float) -> void:
	if not _active:
		return
	var to_end := _end - global_position
	var distance := to_end.length()
	var travel := _speed * delta
	if distance <= travel:
		global_position = _end
		_impact()
		return
	var direction := to_end.normalized()
	global_position += direction * travel
	_update_orientation(direction)

func _impact() -> void:
	_active = false
	var target := _find_target_at_endpoint()
	var applied_damage := 0.0
	if target != null:
		applied_damage = target.take_damage(_damage)
		impacted.emit(target, applied_damage)
	queue_free()

func _find_target_at_endpoint() -> CombatTarget:
	if _combat_manager == null or _source_building == null or not is_instance_valid(_source_building):
		return null
	var best: CombatTarget
	var best_distance := INF
	for target in _combat_manager.get_targets():
		if not target.is_alive() or not _source_building.affects_target(target):
			continue
		var distance := Vector2(target.global_position.x - _end.x, target.global_position.z - _end.z).length()
		if distance <= target.hit_radius and distance < best_distance:
			best = target
			best_distance = distance
	return best

func _build_visual(length: float, width: float, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, length)
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.4
	instance.material_override = material
	add_child(instance)

func _update_orientation(direction: Vector3) -> void:
	if direction.length_squared() > 0.000001:
		look_at(global_position + direction, Vector3.UP)
