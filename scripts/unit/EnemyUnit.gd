## M4 combat target that moves along a fixed path and attacks path blockers.
class_name EnemyUnit
extends CombatTarget

const EnemyAttackStrategyScript := preload("res://scripts/combat/EnemyAttackStrategy.gd")
const EnemyProjectileScript := preload("res://scripts/combat/EnemyProjectile.gd")
const EnemyHealthBarScript := preload("res://scripts/ui/EnemyHealthBar3D.gd")
const EnemyHitParticlesScript := preload("res://scripts/fx/EnemyHitParticles.gd")
const ATTACK_RANGE_EPSILON_RATIO := 0.001
const PATH_PROGRESS_EPSILON := 0.0001
const REFLECTION_EPSILON_RATIO := 0.002
const FRONT_BACK_REFLECTION_OUTWARD_OFFSET_RATIO := 0.1
const MAX_REFLECTIONS_PER_FRAME := 8
const SIMULATION_EPSILON := 0.000001
## Coalesces frame-by-frame damage (such as continuous lasers) while the
## previous burst is still visually fresh.
const HIT_PARTICLE_MIN_INTERVAL := 0.08

signal reached_base(unit: EnemyUnit, damage_to_base: float)
signal attack_started(unit: EnemyUnit, target: Node)
signal attack_stopped(unit: EnemyUnit, target: Node)
signal attack_performed(unit: EnemyUnit, target: Node, applied_damage: float, ranged: bool)
signal projectile_spawned(unit: EnemyUnit, projectile: EnemyProjectile)
signal rerouted(unit: EnemyUnit, from_path: PathDefinition, to_path: PathDefinition, join_cell: Vector3i)
signal route_blocked(unit: EnemyUnit, blocked_cell: Vector3i)
signal reflection_surface_health_changed(
	unit: EnemyUnit,
	surface_id: StringName,
	current_durability: float,
	maximum_durability: float
)

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
var _projectile_blocker_resolver: Callable
var _combat_manager: CombatManager
var _tile_effects_initialized: bool = false
var _waiting_blocked_cell: Vector3i = Vector3i.ZERO
var _is_waiting_for_route: bool = false
var _reroute_attack_target: Node
var _attack_target: Node
var _attack_strategy: EnemyAttackStrategy
var _attack_damage: float = 0.0
var _attacks_per_second: float = 1.0
var _attack_range_world: float = 0.65
var _enemy_health_bar: Node3D
var _movement_phase_remaining: float = 0.0
var _movement_pause_remaining: float = 0.0
var _movement_is_paused: bool = false
var _reflection_surface_states: Dictionary = {}
var _reflection_surfaces_root: Node3D
var _hit_particle_cooldown: float = 0.0
var _is_visually_moving: bool = false

func _ready() -> void:
	super._ready()
	if _health_label != null:
		_health_label.queue_free()
		_health_label = null
	_enemy_health_bar = EnemyHealthBarScript.new()
	_enemy_health_bar.name = &"EnemyHealthBar3D"
	_enemy_health_bar.configure(max_hp, current_hp, debug_height + 0.34)
	add_child(_enemy_health_bar)
	health_changed.connect(_on_enemy_health_changed)
	if _reflection_surface_states.is_empty():
		_initialize_reflection_surface_states()
	_build_special_ability_visuals()
	if _combat_manager != null and has_reflection_surfaces():
		_combat_manager.register_projectile_reflection_provider(
			self,
			Callable(self, "trace_projectile_reflection")
		)


func _exit_tree() -> void:
	if _combat_manager != null and is_instance_valid(_combat_manager):
		_combat_manager.unregister_projectile_reflection_provider(self)

func _process(delta: float) -> void:
	_is_visually_moving = false
	var position_before_simulation := global_position
	var simulation_delta := maxf(0.0, delta)
	_hit_particle_cooldown = maxf(0.0, _hit_particle_cooldown - simulation_delta)
	var frozen_duration := minf(get_freeze_remaining(), simulation_delta)
	super._process(simulation_delta)
	if not feature_enabled or not is_alive() or _reached_base or _path_points.is_empty():
		return
	_initialize_tile_effects()
	if not is_alive():
		return
	if frozen_duration > 0.0:
		_leave_attack_state()
		_apply_current_tile_stay(frozen_duration)
		if not is_alive():
			return
		simulation_delta = maxf(0.0, simulation_delta - frozen_duration)
		if simulation_delta <= 0.0:
			return
	_simulate_unfrozen_time(simulation_delta)
	_is_visually_moving = global_position.distance_squared_to(position_before_simulation) > 0.00000001


func _simulate_unfrozen_time(duration: float) -> void:
	var remaining := maxf(0.0, duration)
	var safety := 0
	while remaining > SIMULATION_EPSILON and is_alive() and not _reached_base:
		safety += 1
		if safety > 128:
			break
		if _has_movement_cycle() and _movement_is_paused:
			var pause_step := minf(remaining, _movement_pause_remaining)
			_simulate_gameplay_step(pause_step, false)
			_movement_pause_remaining = maxf(0.0, _movement_pause_remaining - pause_step)
			remaining = maxf(0.0, remaining - pause_step)
			if _movement_pause_remaining <= SIMULATION_EPSILON:
				_movement_is_paused = false
				_movement_phase_remaining = definition.movement_active_duration
			continue
		var step := remaining
		if _has_movement_cycle():
			step = minf(step, _movement_phase_remaining)
		var movement_duration := _simulate_gameplay_step(step, true)
		remaining = maxf(0.0, remaining - step)
		if not _has_movement_cycle():
			break
		_movement_phase_remaining = maxf(0.0, _movement_phase_remaining - movement_duration)
		if _movement_phase_remaining <= SIMULATION_EPSILON:
			_movement_is_paused = true
			_movement_pause_remaining = definition.movement_pause_duration


func _simulate_gameplay_step(duration: float, movement_allowed: bool) -> float:
	if duration <= 0.0:
		return 0.0
	if _path_points.size() < 2:
		_apply_current_tile_stay(duration)
		return 0.0
	var blocker_info := _find_first_path_blocker()
	if blocker_info.is_empty():
		blocker_info = _get_reroute_attack_blocker_info()
	if not blocker_info.is_empty():
		var blocker: Node = blocker_info["node"]
		var blocker_position := _get_blocker_position(blocker)
		if _is_within_attack_range(blocker_position):
			_enter_attack_state(blocker)
			_face_target(blocker_position)
			_apply_current_tile_stay(duration)
			if is_alive():
				_attack_strategy.tick(self, duration)
			return 0.0
		_leave_attack_state()
		if not movement_allowed:
			_apply_current_tile_stay(duration)
			return 0.0
		var movement_limit := _get_path_distance_until_attack_range(blocker_info)
		var movement_duration := _move_along_path(
			minf(get_effective_move_speed() * duration, movement_limit)
		)
		var stationary_duration := maxf(0.0, duration - movement_duration)
		_apply_current_tile_stay(stationary_duration)
		if (
			is_alive()
			and is_instance_valid(blocker)
			and _is_within_attack_range(_get_blocker_position(blocker))
		):
			_enter_attack_state(blocker)
			_face_target(_get_blocker_position(blocker))
			_attack_strategy.tick(self, stationary_duration)
		return movement_duration
	_leave_attack_state()
	if not movement_allowed:
		_apply_current_tile_stay(duration)
		return 0.0
	var movement_duration := _move_along_path(get_effective_move_speed() * duration)
	_apply_current_tile_stay(maxf(0.0, duration - movement_duration))
	return movement_duration

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
	navigation_blocker_resolver: Callable = Callable(),
	projectile_blocker_resolver: Callable = Callable(),
	combat_manager: CombatManager = null
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
	_projectile_blocker_resolver = projectile_blocker_resolver
	_combat_manager = combat_manager
	_tile_effects_initialized = false
	_is_waiting_for_route = false
	_reroute_attack_target = null
	_attack_target = null
	_attack_strategy = EnemyAttackStrategyScript.new()
	_movement_is_paused = false
	_movement_pause_remaining = 0.0
	_movement_phase_remaining = (
		maxf(0.0, definition.movement_active_duration) if definition != null else 0.0
	)
	_initialize_reflection_surface_states()
	airborne = definition != null and definition.is_airborne
	_flight_height = maxf(0.0, definition.flight_height) if airborne else 0.0
	model_asset = definition.get_model_asset() if definition != null else null
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
	if _enemy_health_bar != null:
		_enemy_health_bar.configure(max_hp, current_hp, debug_height + 0.34)

func take_damage(amount: float) -> float:
	return super.take_damage(maxf(0.0, amount - get_effective_armor()))

func take_damage_over_time(damage_per_second: float, duration: float) -> float:
	return super.take_damage_over_time(
		maxf(0.0, damage_per_second - get_effective_armor()),
		duration
	)


func get_effective_armor() -> float:
	var aura_bonus := 0.0
	if _combat_manager != null and is_instance_valid(_combat_manager):
		for target in _combat_manager.get_targets():
			if target == self or not target is EnemyUnit:
				continue
			var caster := target as EnemyUnit
			aura_bonus = maxf(aura_bonus, caster.get_armor_aura_bonus_for(self))
	return maxf(0.0, armor + aura_bonus)


func get_armor_aura_bonus_for(target: EnemyUnit) -> float:
	if (
		target == null
		or target == self
		or not feature_enabled
		or not is_alive()
		or not target.is_alive()
		or definition == null
		or definition.armor_aura_radius <= 0.0
		or definition.armor_aura_bonus <= 0.0
	):
		return 0.0
	var radius_world := definition.armor_aura_radius * _grid_cell_size
	return (
		definition.armor_aura_bonus
		if _horizontal_distance_to(target.global_position) <= radius_world + 0.0001
		else 0.0
	)


func _has_movement_cycle() -> bool:
	return (
		definition != null
		and definition.movement_active_duration > 0.0
		and definition.movement_pause_duration > 0.0
	)


func is_in_movement_pause() -> bool:
	return _has_movement_cycle() and _movement_is_paused


## Visual-only model controllers use the distance actually travelled during the
## latest simulation frame, so pauses, combat and freeze effects select idle
## animation without duplicating gameplay rules in presentation scripts.
func is_visually_moving() -> bool:
	return _is_visually_moving


func get_movement_active_remaining() -> float:
	return maxf(0.0, _movement_phase_remaining)


## Applies the level's wave HP rule to every durability pool owned by this
## enemy. Body HP and every independent mirror face always share one multiplier.
func apply_wave_health_multiplier(multiplier: float) -> void:
	var resolved_multiplier := multiplier
	if not is_finite(resolved_multiplier) or resolved_multiplier <= 0.0:
		resolved_multiplier = 1.0
	max_hp = maxf(1.0, max_hp * resolved_multiplier)
	current_hp = max_hp
	if _enemy_health_bar != null and is_instance_valid(_enemy_health_bar):
		(_enemy_health_bar as EnemyHealthBar3D).update_health(current_hp, max_hp)
	for surface_key in _reflection_surface_states.keys():
		var surface_id := StringName(surface_key)
		var state: Dictionary = _reflection_surface_states.get(surface_id, {})
		var maximum := maxf(
			1.0,
			float(state.get("maximum_durability", 1.0)) * resolved_multiplier
		)
		state["maximum_durability"] = maximum
		state["current_durability"] = maximum
		_reflection_surface_states[surface_id] = state
		var bar_value: Variant = state.get("health_bar")
		if is_instance_valid(bar_value):
			(bar_value as EnemyHealthBar3D).update_health(maximum, maximum)


func has_reflection_surfaces() -> bool:
	return (
		feature_enabled
		and definition != null
		and definition.reflection_pattern != EnemyDefinition.ReflectionPattern.NONE
	)


func has_active_reflection_surfaces() -> bool:
	for surface_id in _reflection_surface_states:
		if is_reflection_surface_alive(StringName(surface_id)):
			return true
	return false


func get_reflection_surface_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for surface_id in _configured_reflection_surface_ids():
		result.append(surface_id)
	return result


func get_reflection_surface_current_durability(surface_id: StringName) -> float:
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	return maxf(0.0, float(state.get("current_durability", 0.0)))


func get_reflection_surface_max_durability(surface_id: StringName) -> float:
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	return maxf(0.0, float(state.get("maximum_durability", 0.0)))


func is_reflection_surface_alive(surface_id: StringName) -> bool:
	return get_reflection_surface_current_durability(surface_id) > 0.0


func get_reflection_surface_root(surface_id: StringName) -> Node3D:
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	var root_value: Variant = state.get("root")
	return root_value as Node3D if is_instance_valid(root_value) else null


func get_reflection_surface_health_bar(surface_id: StringName) -> Node3D:
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	var bar_value: Variant = state.get("health_bar")
	return bar_value as Node3D if is_instance_valid(bar_value) else null


## Mirror durability is intentionally independent from enemy armor and body HP.
func take_reflection_surface_damage(surface_id: StringName, amount: float) -> float:
	if amount <= 0.0 or not is_reflection_surface_alive(surface_id):
		return 0.0
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	var previous := float(state.get("current_durability", 0.0))
	var applied := minf(previous, maxf(0.0, amount))
	var current := maxf(0.0, previous - applied)
	state["current_durability"] = current
	_reflection_surface_states[surface_id] = state
	var health_bar_value: Variant = state.get("health_bar")
	if is_instance_valid(health_bar_value):
		(health_bar_value as EnemyHealthBar3D).update_health(
			current,
			float(state.get("maximum_durability", 1.0))
		)
	reflection_surface_health_changed.emit(
		self,
		surface_id,
		current,
		float(state.get("maximum_durability", 1.0))
	)
	if current <= 0.0:
		_destroy_reflection_surface_visual(surface_id)
	return applied


## Finite, one-sided vertical reflection faces. A four-sided reflector forms a
## square footprint around the unit; top and bottom are intentionally absent.
func trace_projectile_reflection(start: Vector3, end: Vector3) -> Dictionary:
	var result := {
		"hit": false,
		"position": end,
		"normal": Vector3.ZERO,
		"distance": start.distance_to(end),
		"mirror": null,
		"reflector": self,
		"surface_id": StringName(),
		"reflector_surface_id": StringName(),
		"epsilon": maxf(0.0001, _grid_cell_size * REFLECTION_EPSILON_RATIO),
		"max_reflections_per_frame": MAX_REFLECTIONS_PER_FRAME,
	}
	if not has_reflection_surfaces() or not is_alive():
		return result
	var segment := end - start
	var segment_length := segment.length()
	if segment_length <= SIMULATION_EPSILON:
		return result
	var half_side := definition.reflection_side_length * _grid_cell_size * 0.5
	var height := definition.reflection_height * _grid_cell_size
	var best_fraction := INF
	for side in _get_reflection_sides():
		var side_id := StringName(side.get("id", StringName()))
		if not is_reflection_surface_alive(side_id):
			continue
		var normal: Vector3 = side.get("normal", Vector3.ZERO)
		var tangent: Vector3 = side.get("tangent", Vector3.ZERO)
		var plane_center := global_position + normal * _get_reflection_surface_distance(side_id)
		var denominator := segment.dot(normal)
		if denominator >= -SIMULATION_EPSILON:
			continue
		var signed_start := (start - plane_center).dot(normal)
		if signed_start < -SIMULATION_EPSILON:
			continue
		var fraction := -signed_start / denominator
		if fraction <= SIMULATION_EPSILON or fraction > 1.0 or fraction >= best_fraction:
			continue
		var hit_position := start + segment * fraction
		var along_side := (hit_position - plane_center).dot(tangent)
		if absf(along_side) > half_side + 0.0001:
			continue
		if (
			hit_position.y < global_position.y - 0.0001
			or hit_position.y > global_position.y + height + 0.0001
		):
			continue
		best_fraction = fraction
		result.hit = true
		result.position = hit_position
		result.normal = normal
		result.distance = segment_length * fraction
		result.surface_id = StringName("enemy_%d_%s" % [get_instance_id(), side_id])
		result.reflector_surface_id = side_id
	return result


func _get_reflection_sides() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if definition == null:
		return result
	for layout in _get_local_reflection_side_layout():
		var local_normal: Vector3 = layout.get("normal", Vector3.ZERO)
		var local_tangent: Vector3 = layout.get("tangent", Vector3.ZERO)
		var world_normal := global_basis * local_normal
		world_normal.y = 0.0
		world_normal = world_normal.normalized()
		var world_tangent := global_basis * local_tangent
		world_tangent.y = 0.0
		world_tangent = world_tangent.normalized()
		result.append({
			"id": layout.get("id", StringName()),
			"normal": world_normal,
			"tangent": world_tangent,
		})
	return result


func _get_local_reflection_side_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if definition == null:
		return result
	match definition.reflection_pattern:
		EnemyDefinition.ReflectionPattern.FRONT:
			result.append({"id": &"front", "normal": Vector3.FORWARD, "tangent": Vector3.RIGHT})
		EnemyDefinition.ReflectionPattern.LEFT_RIGHT:
			result.append({"id": &"left", "normal": Vector3.LEFT, "tangent": Vector3.FORWARD})
			result.append({"id": &"right", "normal": Vector3.RIGHT, "tangent": Vector3.FORWARD})
		EnemyDefinition.ReflectionPattern.FOUR_SIDES:
			result.append({"id": &"front", "normal": Vector3.FORWARD, "tangent": Vector3.RIGHT})
			result.append({"id": &"back", "normal": Vector3.BACK, "tangent": Vector3.RIGHT})
			result.append({"id": &"left", "normal": Vector3.LEFT, "tangent": Vector3.FORWARD})
			result.append({"id": &"right", "normal": Vector3.RIGHT, "tangent": Vector3.FORWARD})
	return result


func _configured_reflection_surface_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for layout in _get_local_reflection_side_layout():
		result.append(StringName(layout.get("id", StringName())))
	return result


func _get_reflection_surface_distance(surface_id: StringName) -> float:
	var distance := definition.reflection_side_length * _grid_cell_size * 0.5
	if surface_id == &"front" or surface_id == &"back":
		distance += _grid_cell_size * FRONT_BACK_REFLECTION_OUTWARD_OFFSET_RATIO
	return distance


func _initialize_reflection_surface_states() -> void:
	_reflection_surface_states.clear()
	if definition == null:
		return
	var maximum := maxf(1.0, definition.reflection_max_durability)
	for surface_id in _configured_reflection_surface_ids():
		_reflection_surface_states[surface_id] = {
			"current_durability": maximum,
			"maximum_durability": maximum,
			"root": null,
			"health_bar": null,
		}


func _build_special_ability_visuals() -> void:
	if definition == null:
		return
	if debug_visual_enabled and definition.armor_aura_radius > 0.0 and definition.armor_aura_bonus > 0.0:
		var aura := MeshInstance3D.new()
		aura.name = &"ArmorAuraVisual"
		var aura_mesh := TorusMesh.new()
		var aura_radius := definition.armor_aura_radius * _grid_cell_size
		aura_mesh.inner_radius = maxf(0.04, aura_radius - 0.035)
		aura_mesh.outer_radius = aura_radius + 0.035
		aura.mesh = aura_mesh
		aura.position.y = 0.055
		aura.material_override = _make_ability_material(Color(0.68, 0.28, 1.0, 0.72), 2.2)
		add_child(aura)
	if not has_reflection_surfaces():
		return
	_reflection_surfaces_root = Node3D.new()
	_reflection_surfaces_root.name = &"ReflectionSurfaces"
	add_child(_reflection_surfaces_root)
	var side_length := definition.reflection_side_length * _grid_cell_size
	var height := definition.reflection_height * _grid_cell_size
	var thickness := maxf(0.025, _grid_cell_size * 0.035)
	var material := _make_ability_material(Color(0.32, 0.88, 1.0, 0.48), 2.8)
	for layout in _get_local_reflection_side_layout():
		var side_id := StringName(layout.get("id", StringName()))
		var local_normal: Vector3 = layout.get("normal", Vector3.ZERO)
		var size := (
			Vector3(side_length, height, thickness)
			if absf(local_normal.z) > 0.5
			else Vector3(thickness, height, side_length)
		)
		_add_reflection_surface(side_id, local_normal, size, material)


func _add_reflection_surface(
	surface_id: StringName,
	local_normal: Vector3,
	size: Vector3,
	material: StandardMaterial3D
) -> void:
	var surface_root := Node3D.new()
	surface_root.name = StringName("%sReflectionSurface" % String(surface_id).capitalize())
	surface_root.position = local_normal * _get_reflection_surface_distance(surface_id)
	_reflection_surfaces_root.add_child(surface_root)
	var visual: Node3D
	if definition.reflection_model_asset != null:
		visual = definition.reflection_model_asset.instantiate_fitted_model(
			&"MirrorModel",
			AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
		)
	if visual == null:
		var fallback := MeshInstance3D.new()
		fallback.name = &"MirrorModel"
		var mesh := BoxMesh.new()
		mesh.size = size
		fallback.mesh = mesh
		fallback.position.y = size.y * 0.5
		fallback.material_override = material
		visual = fallback
	surface_root.add_child(visual)
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	var health_bar := EnemyHealthBarScript.new()
	health_bar.name = &"MirrorHealthBar3D"
	health_bar.configure(
		float(state.get("maximum_durability", 1.0)),
		float(state.get("current_durability", 0.0)),
		debug_height + 0.34
	)
	health_bar.position += local_normal * maxf(0.08, _grid_cell_size * 0.14)
	surface_root.add_child(health_bar)
	state["root"] = surface_root
	state["health_bar"] = health_bar
	_reflection_surface_states[surface_id] = state


func _destroy_reflection_surface_visual(surface_id: StringName) -> void:
	var state: Dictionary = _reflection_surface_states.get(surface_id, {})
	var surface_root_value: Variant = state.get("root")
	if is_instance_valid(surface_root_value):
		var surface_root := surface_root_value as Node3D
		surface_root.visible = false
		surface_root.queue_free()
	state["root"] = null
	state["health_bar"] = null
	_reflection_surface_states[surface_id] = state


func _make_ability_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.metallic = 0.72
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material


func get_target_marker_position() -> Vector3:
	return global_position - Vector3.UP * _flight_height + Vector3.UP * 0.025


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
		var traveled_duration := traveled_distance / maxf(0.0001, get_effective_move_speed())
		_apply_current_tile_stay(traveled_duration)
		movement_duration += traveled_duration
		if not is_alive():
			break
		_face_direction(to_destination)
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
		definition.attack_color,
		definition.projectile_model_asset,
		_projectile_blocker_resolver
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

func _on_enemy_health_changed(
	_target: CombatTarget,
	new_current_hp: float,
	new_maximum_hp: float
) -> void:
	if _enemy_health_bar != null:
		_enemy_health_bar.update_health(new_current_hp, new_maximum_hp)
	_spawn_hit_particles(new_current_hp <= 0.0)


func _spawn_hit_particles(force: bool = false) -> void:
	if (
		definition == null
		or definition.hit_particle_count <= 0
		or not is_inside_tree()
		or _hit_particle_cooldown > 0.0 and not force
	):
		return
	var host := get_parent()
	if host == null:
		return
	var burst := EnemyHitParticlesScript.new()
	burst.configure(
		definition.hit_particle_color,
		definition.hit_particle_brightness,
		definition.hit_particle_size,
		definition.hit_particle_count,
		maxf(definition.hit_particle_size, hit_radius * 0.55)
	)
	host.add_child(burst)
	burst.global_position = get_target_position()
	burst.start()
	_hit_particle_cooldown = HIT_PARTICLE_MIN_INTERVAL

func _reach_base() -> void:
	if _reached_base:
		return
	_reached_base = true
	_leave_attack_state()
	feature_enabled = false
	reached_base.emit(self, damage_to_base)
	queue_free()
