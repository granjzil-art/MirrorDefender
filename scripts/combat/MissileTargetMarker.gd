## Ground-projected aim marker owned by one targeted missile.
class_name MissileTargetMarker
extends Node3D

const AIM_TEXTURE := preload("res://assets/png/aim.png")

var _target: CombatTarget
var _missile: Node
var _base_size: float = 0.7
var _elapsed: float = 0.0
var _marker: MeshInstance3D


func configure(target: CombatTarget, missile: Node, size_world: float) -> void:
	_target = target
	_missile = missile
	_base_size = maxf(0.05, size_world)
	_build_visual()
	_update_position()


func _process(delta: float) -> void:
	if _missile == null or not is_instance_valid(_missile) or _missile.is_queued_for_deletion():
		queue_free()
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		queue_free()
		return
	_elapsed += maxf(0.0, delta)
	_update_position()
	var pulse := 1.0 + sin(_elapsed * 7.0) * 0.08
	_marker.scale = Vector3(pulse, pulse, pulse)
	_marker.rotation.y = _elapsed * 0.45


func get_marked_target() -> CombatTarget:
	return _target if _target != null and is_instance_valid(_target) else null


func _update_position() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	global_position = _target.get_target_marker_position()


func _build_visual() -> void:
	_marker = MeshInstance3D.new()
	_marker.name = &"AimTexture"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * _base_size
	_marker.mesh = quad
	_marker.rotation_degrees.x = -90.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.albedo_texture = AIM_TEXTURE
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission_texture = AIM_TEXTURE
	material.emission = Color(1.0, 0.12, 0.08, 1.0)
	material.emission_energy_multiplier = 1.8
	material.render_priority = 4
	_marker.material_override = material
	add_child(_marker)
