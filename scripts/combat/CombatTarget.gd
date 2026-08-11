## Runtime damageable target contract. M4 units register instances with CombatManager.
class_name CombatTarget
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Classification")
## Runtime target tag used by effects that can opt out of affecting airborne enemies.
@export var airborne: bool = false

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
signal movement_status_changed(
	target: CombatTarget,
	speed_multiplier: float,
	slow_remaining: float,
	freeze_remaining: float
)

var current_hp: float = 100.0
var entry_order: int = -1
var model_asset: ModelAssetDefinition
var _alive: bool = true
var _visual_root: Node3D
var _mesh_instance: MeshInstance3D
var _health_label: Label3D
var _slow_multiplier: float = 1.0
var _slow_remaining: float = 0.0
var _freeze_remaining: float = 0.0
var _status_visual_elapsed: float = 0.0
var _slow_visual: MeshInstance3D
var _freeze_visual: MeshInstance3D

func _ready() -> void:
	current_hp = max_hp
	if model_asset != null or debug_visual_enabled:
		_build_debug_visual()
	_build_status_visuals()
	_update_debug_status()


func _process(delta: float) -> void:
	_tick_movement_statuses(delta)

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

func get_current_hp() -> float:
	return current_hp

func is_airborne_unit() -> bool:
	return airborne

func get_target_position() -> Vector3:
	return global_position + Vector3(0.0, debug_height * 0.55, 0.0)


## World point used by ground-projected target markers.
func get_target_marker_position() -> Vector3:
	return global_position + Vector3.UP * 0.025


## Applies a non-stacking movement multiplier. Reapplications keep the
## strongest slow and refresh the remaining duration.
func apply_movement_slow(speed_multiplier: float, duration: float) -> bool:
	if not feature_enabled or not is_alive() or duration <= 0.0:
		return false
	var resolved_multiplier := clampf(speed_multiplier, 0.0, 1.0)
	var was_slowed := is_movement_slowed()
	if not was_slowed:
		_slow_multiplier = resolved_multiplier
	else:
		_slow_multiplier = minf(_slow_multiplier, resolved_multiplier)
	_slow_remaining = maxf(_slow_remaining, duration)
	_update_status_visuals()
	_emit_movement_status_changed()
	return true


## Freeze suspends movement and attacks. Slow time is paused while frozen so
## the remaining cold effect resumes after thawing.
func apply_freeze(duration: float) -> bool:
	if not feature_enabled or not is_alive() or duration <= 0.0:
		return false
	_freeze_remaining = maxf(_freeze_remaining, duration)
	_update_status_visuals()
	_emit_movement_status_changed()
	return true


func get_movement_speed_multiplier() -> float:
	if is_frozen():
		return 0.0
	return _slow_multiplier if is_movement_slowed() else 1.0


func get_effective_move_speed() -> float:
	return move_speed * get_movement_speed_multiplier()


func is_movement_slowed() -> bool:
	return _slow_remaining > 0.0 and _slow_multiplier < 1.0


func is_frozen() -> bool:
	return _freeze_remaining > 0.0


func get_slow_remaining() -> float:
	return maxf(0.0, _slow_remaining)


func get_freeze_remaining() -> float:
	return maxf(0.0, _freeze_remaining)

func _build_debug_visual() -> void:
	if model_asset != null:
		_visual_root = model_asset.instantiate_grounded_model(&"EnemyModel")
		if _visual_root != null:
			add_child(_visual_root)
	if _visual_root == null and debug_visual_enabled:
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
	if debug_visual_enabled:
		_health_label = Label3D.new()
		_health_label.position.y = debug_height + 0.35
		_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_health_label.no_depth_test = true
		_health_label.font_size = 28
		_health_label.modulate = Color.WHITE
		add_child(_health_label)


func _build_status_visuals() -> void:
	_slow_visual = MeshInstance3D.new()
	_slow_visual.name = &"ColdSlowVisual"
	var slow_mesh := TorusMesh.new()
	slow_mesh.inner_radius = maxf(0.04, hit_radius * 1.05)
	slow_mesh.outer_radius = maxf(slow_mesh.inner_radius + 0.03, hit_radius * 1.38)
	_slow_visual.mesh = slow_mesh
	_slow_visual.position.y = 0.045
	_slow_visual.material_override = _make_status_material(
		Color(0.18, 0.82, 1.0, 0.72),
		2.8
	)
	_slow_visual.visible = false
	add_child(_slow_visual)

	_freeze_visual = MeshInstance3D.new()
	_freeze_visual.name = &"FrozenShellVisual"
	var freeze_mesh := CapsuleMesh.new()
	freeze_mesh.radius = maxf(0.06, hit_radius * 1.16)
	freeze_mesh.height = maxf(debug_height * 1.08, freeze_mesh.radius * 2.0)
	_freeze_visual.mesh = freeze_mesh
	_freeze_visual.position.y = debug_height * 0.5
	_freeze_visual.material_override = _make_status_material(
		Color(0.42, 0.9, 1.0, 0.34),
		3.8
	)
	_freeze_visual.visible = false
	add_child(_freeze_visual)


func _make_status_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func _tick_movement_statuses(delta: float) -> void:
	var remaining_delta := maxf(0.0, delta)
	var status_changed := false
	if _freeze_remaining > 0.0:
		var freeze_step := minf(_freeze_remaining, remaining_delta)
		_freeze_remaining = maxf(0.0, _freeze_remaining - freeze_step)
		remaining_delta = maxf(0.0, remaining_delta - freeze_step)
		status_changed = freeze_step > 0.0
	if _freeze_remaining <= 0.0 and _slow_remaining > 0.0 and remaining_delta > 0.0:
		_slow_remaining = maxf(0.0, _slow_remaining - remaining_delta)
		status_changed = true
		if _slow_remaining <= 0.0:
			_slow_multiplier = 1.0
	_status_visual_elapsed += maxf(0.0, delta)
	_update_status_visuals()
	if status_changed:
		_emit_movement_status_changed()


func _update_status_visuals() -> void:
	if _slow_visual != null:
		_slow_visual.visible = is_movement_slowed()
		if _slow_visual.visible:
			var pulse := 1.0 + sin(_status_visual_elapsed * 5.0) * 0.06
			_slow_visual.scale = Vector3(pulse, 1.0, pulse)
			_slow_visual.rotation.y = _status_visual_elapsed * 0.8
	if _freeze_visual != null:
		_freeze_visual.visible = is_frozen()
		if _freeze_visual.visible:
			var shimmer := 1.0 + sin(_status_visual_elapsed * 7.0) * 0.025
			_freeze_visual.scale = Vector3.ONE * shimmer


func _emit_movement_status_changed() -> void:
	movement_status_changed.emit(
		self,
		get_movement_speed_multiplier(),
		get_slow_remaining(),
		get_freeze_remaining()
	)

func _update_debug_status() -> void:
	if _health_label != null:
		_health_label.text = "%d/%d" % [ceili(current_hp), ceili(max_hp)]
