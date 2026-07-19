## Runtime damageable target contract. M4 units register instances with CombatManager.
class_name CombatTarget
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Stats")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var move_speed: float = 1.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var reward: float = 5.0
@export_range(0.05, 5.0, 0.05, "or_greater") var hit_radius: float = 0.3

@export_group("Debug Visual")
@export var debug_visual_enabled: bool = true
@export var debug_color: Color = Color(0.83, 0.20, 0.24, 1.0)
@export_range(0.1, 3.0, 0.05, "or_greater") var debug_height: float = 0.8

signal health_changed(target: CombatTarget, current_hp: float, maximum_hp: float)
signal died(target: CombatTarget, reward_amount: float)

var current_hp: float = 100.0
var entry_order: int = -1
var _alive: bool = true
var _mesh_instance: MeshInstance3D
var _health_label: Label3D

func _ready() -> void:
	current_hp = max_hp
	if debug_visual_enabled:
		_build_debug_visual()
	_update_debug_status()

func configure_debug_target(world_position: Vector3, hp: float, speed: float, reward_amount: float) -> void:
	global_position = world_position
	max_hp = maxf(1.0, hp)
	current_hp = max_hp
	move_speed = maxf(0.0, speed)
	reward = maxf(0.0, reward_amount)
	_alive = true
	_update_debug_status()

func take_damage(amount: float) -> float:
	return _apply_damage(amount)

## Environmental damage entry that intentionally bypasses unit armor.
func take_unmitigated_damage(amount: float) -> float:
	return _apply_damage(amount)

## Continuous-damage contract. Subclasses may mitigate the rate, keeping the
## result independent from how traversal time is split across frames.
func take_damage_over_time(damage_per_second: float, duration: float) -> float:
	return _apply_damage(maxf(0.0, damage_per_second) * maxf(0.0, duration))

## Explicit environmental defeat hook. The multiplier controls only this
## target's configured reward and keeps normal combat deaths unchanged.
func defeat(reward_multiplier: float = 1.0) -> bool:
	if not feature_enabled or not _alive:
		return false
	_apply_damage(current_hp, maxf(0.0, reward_multiplier))
	return true

func _apply_damage(amount: float, reward_multiplier: float = 1.0) -> float:
	if not feature_enabled or not _alive or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_hp)
	current_hp -= applied
	health_changed.emit(self, current_hp, max_hp)
	_update_debug_status()
	if current_hp <= 0.0:
		_alive = false
		died.emit(self, reward * reward_multiplier)
		queue_free()
	return applied

func is_alive() -> bool:
	return _alive and current_hp > 0.0 and not is_queued_for_deletion()

func get_target_position() -> Vector3:
	return global_position + Vector3(0.0, debug_height * 0.55, 0.0)

func _build_debug_visual() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = hit_radius
	mesh.height = debug_height
	_mesh_instance.mesh = mesh
	_mesh_instance.position.y = debug_height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = debug_color
	material.roughness = 0.7
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	_health_label = Label3D.new()
	_health_label.position.y = debug_height + 0.35
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_label.no_depth_test = true
	_health_label.font_size = 28
	_health_label.modulate = Color.WHITE
	add_child(_health_label)

func _update_debug_status() -> void:
	if _health_label != null:
		_health_label.text = "%d/%d" % [ceili(current_hp), ceili(max_hp)]
