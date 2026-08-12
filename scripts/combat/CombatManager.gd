## Combat module entry point for target registration and spatial queries.
class_name CombatManager
extends Node3D

const PulseLaserBeamScript := preload("res://scripts/combat/PulseLaserBeam.gd")
const LaserBurstEffectScript := preload("res://scripts/combat/LaserBurstEffect.gd")
const MissileProjectileScript := preload("res://scripts/combat/MissileProjectile.gd")

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
signal pulse_laser_spawned(beam: PulseLaserBeam)
signal pulse_laser_hit(target: CombatTarget, applied_damage: float, segment_index: int)

var _targets: Array[CombatTarget] = []
var _projectiles: Array[Projectile] = []
var _pulse_lasers: Array[PulseLaserBeam] = []
var _next_entry_order: int = 0
var _target_exit_callbacks: Dictionary = {}
var _projectile_reflection_resolver: Callable
var _projectile_reflection_owner: Object
var _projectile_reflection_providers: Dictionary = {}
var _projectile_blocker_resolver: Callable
var _projectile_blocker_owner: Object


func set_projectile_reflection_resolver(resolver: Callable) -> void:
	_projectile_reflection_resolver = resolver
	_projectile_reflection_owner = resolver.get_object() if resolver.is_valid() else null


func clear_projectile_reflection_resolver(expected_owner: Object = null) -> void:
	if expected_owner != null and _projectile_reflection_owner != expected_owner:
		return
	_projectile_reflection_resolver = Callable()
	_projectile_reflection_owner = null


func get_projectile_reflection_resolver() -> Callable:
	return Callable(self, "trace_projectile_reflection")


func register_projectile_reflection_provider(owner: Object, resolver: Callable) -> bool:
	if owner == null or not is_instance_valid(owner) or not resolver.is_valid():
		return false
	_projectile_reflection_providers[owner.get_instance_id()] = {
		"owner": weakref(owner),
		"resolver": resolver,
	}
	return true


func unregister_projectile_reflection_provider(owner: Object) -> void:
	if owner != null:
		_projectile_reflection_providers.erase(owner.get_instance_id())


func get_projectile_reflection_provider_count() -> int:
	_purge_projectile_reflection_providers()
	return _projectile_reflection_providers.size()


func trace_projectile_reflection(start: Vector3, end: Vector3) -> Dictionary:
	var result: Dictionary = {"hit": false}
	var best_distance := INF
	if _projectile_reflection_resolver.is_valid():
		var base_value: Variant = _projectile_reflection_resolver.call(start, end)
		if base_value is Dictionary:
			var base_candidate: Dictionary = base_value
			var base_distance := _get_reflection_candidate_distance(base_candidate, start, end)
			if bool(base_candidate.get("hit", false)) and is_finite(base_distance):
				result = base_candidate
				best_distance = base_distance
	var stale_provider_ids: Array[int] = []
	for raw_provider_id in _projectile_reflection_providers.keys():
		var provider_id := int(raw_provider_id)
		var entry: Dictionary = _projectile_reflection_providers.get(provider_id, {})
		var owner_reference := entry.get("owner") as WeakRef
		var owner: Object = owner_reference.get_ref() if owner_reference != null else null
		var resolver: Callable = entry.get("resolver", Callable())
		if owner == null or not is_instance_valid(owner) or not resolver.is_valid():
			stale_provider_ids.append(provider_id)
			continue
		var candidate_value: Variant = resolver.call(start, end)
		if not candidate_value is Dictionary:
			continue
		var candidate: Dictionary = candidate_value
		var candidate_distance := _get_reflection_candidate_distance(candidate, start, end)
		if (
			bool(candidate.get("hit", false))
			and is_finite(candidate_distance)
			and candidate_distance < best_distance - 0.000001
		):
			result = candidate
			best_distance = candidate_distance
	for provider_id in stale_provider_ids:
		_projectile_reflection_providers.erase(provider_id)
	return result


func _get_reflection_candidate_distance(
	candidate: Dictionary,
	start: Vector3,
	end: Vector3
) -> float:
	if not bool(candidate.get("hit", false)):
		return INF
	var segment_length := start.distance_to(end)
	var distance := float(candidate.get("distance", INF))
	if not is_finite(distance):
		var position_value: Variant = candidate.get("position")
		if position_value is Vector3:
			distance = start.distance_to(position_value as Vector3)
	if not is_finite(distance) or distance < 0.0 or distance > segment_length + 0.0001:
		return INF
	return distance


func _purge_projectile_reflection_providers() -> void:
	var stale_provider_ids: Array[int] = []
	for raw_provider_id in _projectile_reflection_providers.keys():
		var provider_id := int(raw_provider_id)
		var entry: Dictionary = _projectile_reflection_providers.get(provider_id, {})
		var owner_reference := entry.get("owner") as WeakRef
		var owner: Object = owner_reference.get_ref() if owner_reference != null else null
		var resolver: Callable = entry.get("resolver", Callable())
		if owner == null or not is_instance_valid(owner) or not resolver.is_valid():
			stale_provider_ids.append(provider_id)
	for provider_id in stale_provider_ids:
		_projectile_reflection_providers.erase(provider_id)


func set_projectile_blocker_resolver(resolver: Callable) -> void:
	_projectile_blocker_resolver = resolver
	_projectile_blocker_owner = resolver.get_object() if resolver.is_valid() else null


func clear_projectile_blocker_resolver(expected_owner: Object = null) -> void:
	if expected_owner != null and _projectile_blocker_owner != expected_owner:
		return
	_projectile_blocker_resolver = Callable()
	_projectile_blocker_owner = null


func get_projectile_blocker_resolver() -> Callable:
	return Callable(self, "trace_projectile_blocker")


func trace_projectile_blocker(
	start: Vector3,
	end: Vector3,
	excluded: Object = null
) -> Dictionary:
	if not _projectile_blocker_resolver.is_valid():
		return {"hit": false}
	var result: Variant = (
		_projectile_blocker_resolver.call(start, end, excluded)
		if excluded != null
		else _projectile_blocker_resolver.call(start, end)
	)
	return result if result is Dictionary else {"hit": false}

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

func get_targets_on_segment(
	start: Vector3,
	end: Vector3,
	include_end_caps: bool = true
) -> Array[CombatTarget]:
	var out: Array[CombatTarget] = []
	var segment_start := Vector2(start.x, start.z)
	var segment_end := Vector2(end.x, end.z)
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.000001:
		return out
	for target in get_targets():
		var point := Vector2(target.global_position.x, target.global_position.z)
		var raw_along := (point - segment_start).dot(segment) / segment_length_squared
		if not include_end_caps and (raw_along < 0.0 or raw_along > 1.0):
			continue
		var along := clampf(raw_along, 0.0, 1.0)
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
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	penetration_count: int = 0
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
		color,
		model_asset,
		source_building,
		Callable(self, "get_targets"),
		get_projectile_reflection_resolver(),
		penetration_count,
		_projectile_blocker_resolver
	)
	projectile.impacted.connect(_on_projectile_impacted)
	projectile.tree_exited.connect(_on_projectile_tree_exited.bind(projectile))
	_projectiles.append(projectile)
	projectile_spawned.emit(projectile)
	return projectile


## Creates and owns a targetless straight projectile using the shared query chain.
func spawn_directional_projectile(
	start: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	penetration_count: int = 0
) -> Projectile:
	if not feature_enabled or direction.length_squared() <= 0.000001:
		return null
	var projectile := Projectile.new()
	add_child(projectile)
	projectile.configure_directional(
		start,
		direction,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color,
		model_asset,
		source_building,
		Callable(self, "get_targets"),
		get_projectile_reflection_resolver(),
		penetration_count,
		_projectile_blocker_resolver
	)
	projectile.impacted.connect(_on_projectile_impacted)
	projectile.tree_exited.connect(_on_projectile_tree_exited.bind(projectile))
	_projectiles.append(projectile)
	projectile_spawned.emit(projectile)
	return projectile


func spawn_targeted_missile(
	start: Vector3,
	target: CombatTarget,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	configuration: Dictionary = {}
) -> MissileProjectile:
	if not feature_enabled or target == null or not target.is_alive():
		return null
	var missile := MissileProjectileScript.new() as MissileProjectile
	add_child(missile)
	missile.configure_targeted_missile(
		start,
		target,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color,
		model_asset,
		source_building,
		Callable(self, "get_targets"),
		get_projectile_reflection_resolver(),
		_projectile_blocker_resolver,
		configuration
	)
	missile.impacted.connect(_on_projectile_impacted)
	missile.tree_exited.connect(_on_projectile_tree_exited.bind(missile))
	_projectiles.append(missile)
	projectile_spawned.emit(missile)
	return missile


func spawn_directional_missile(
	start: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	maximum_distance: float,
	visual_length: float,
	visual_width: float,
	color: Color,
	model_asset: ModelAssetDefinition = null,
	source_building: Building = null,
	configuration: Dictionary = {}
) -> MissileProjectile:
	if not feature_enabled or direction.length_squared() <= 0.000001:
		return null
	var missile := MissileProjectileScript.new() as MissileProjectile
	add_child(missile)
	missile.configure_directional_missile(
		start,
		direction,
		speed,
		damage,
		maximum_distance,
		visual_length,
		visual_width,
		color,
		model_asset,
		source_building,
		Callable(self, "get_targets"),
		get_projectile_reflection_resolver(),
		_projectile_blocker_resolver,
		configuration
	)
	missile.impacted.connect(_on_projectile_impacted)
	missile.tree_exited.connect(_on_projectile_tree_exited.bind(missile))
	_projectiles.append(missile)
	projectile_spawned.emit(missile)
	return missile


func spawn_pulse_laser(
	start: Vector3,
	direction: Vector3,
	damage: float,
	maximum_distance: float,
	maximum_width: float,
	emission_energy: float,
	fade_in_time: float,
	hold_time: float,
	fade_out_time: float,
	colors: Array[Color],
	maximum_reflections: int,
	source_building: Building = null
) -> PulseLaserBeam:
	if not feature_enabled:
		return null
	var beam := PulseLaserBeamScript.new() as PulseLaserBeam
	add_child(beam)
	if not beam.configure(
		self,
		source_building,
		start,
		direction,
		damage,
		maximum_distance,
		maximum_width,
		emission_energy,
		fade_in_time,
		hold_time,
		fade_out_time,
		colors,
		maximum_reflections,
		get_projectile_reflection_resolver(),
		_projectile_blocker_resolver
	):
		beam.free()
		return null
	beam.impacted.connect(_on_pulse_laser_impacted)
	beam.tree_exited.connect(_on_pulse_laser_tree_exited.bind(beam))
	_pulse_lasers.append(beam)
	pulse_laser_spawned.emit(beam)
	return beam


func spawn_laser_burst_visual(
	world_position: Vector3,
	radius: float,
	color: Color
) -> LaserBurstEffect:
	if not feature_enabled or radius <= 0.0:
		return null
	var effect := LaserBurstEffectScript.new() as LaserBurstEffect
	add_child(effect)
	effect.configure(world_position, radius, color)
	return effect

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
	var pulse_lasers := _pulse_lasers.duplicate()
	_pulse_lasers.clear()
	for beam in pulse_lasers:
		if is_instance_valid(beam):
			beam.queue_free()


## Cancels attacks owned by one runtime building without disturbing attacks
## from other towers. Used when combat-data editing rebuilds that building.
func clear_attacks_from_building(source_building: Building) -> void:
	if source_building == null:
		return
	for projectile in _projectiles.duplicate():
		if (
			is_instance_valid(projectile)
			and projectile.get_source_building() == source_building
		):
			_projectiles.erase(projectile)
			projectile.queue_free()
	for beam in _pulse_lasers.duplicate():
		if is_instance_valid(beam) and beam.get_source_building() == source_building:
			_pulse_lasers.erase(beam)
			beam.queue_free()

func _cleanup_targets() -> void:
	# unregister_target emits synchronously. Listeners such as M3DebugPanel may
	# query targets again from that signal, so never iterate the live array here.
	var snapshot := _targets.duplicate()
	for target in snapshot:
		if target == null or not is_instance_valid(target):
			_targets.erase(target)
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


func _on_pulse_laser_impacted(
	target: CombatTarget,
	applied_damage: float,
	segment_index: int
) -> void:
	pulse_laser_hit.emit(target, applied_damage, segment_index)


func _on_pulse_laser_tree_exited(beam: PulseLaserBeam) -> void:
	_pulse_lasers.erase(beam)

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
