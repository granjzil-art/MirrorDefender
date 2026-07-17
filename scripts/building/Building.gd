## Runtime tower assembled from a definition, current level stats, and strategies.
class_name Building
extends Node3D

const ArrowAttackStrategyScript := preload("res://scripts/combat/ArrowAttackStrategy.gd")
const LaserAttackStrategyScript := preload("res://scripts/combat/LaserAttackStrategy.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Visual Scale")
@export_range(0.1, 2.0, 0.05, "or_greater") var tower_height_ratio: float = 0.75
@export_range(0.05, 1.0, 0.05, "or_greater") var base_radius_ratio: float = 0.24
@export_range(0.01, 1.0, 0.01, "or_greater") var direction_marker_ratio: float = 0.32
@export_range(0.05, 1.0, 0.05) var preview_alpha: float = 0.38

signal facing_changed(building: Building, facing_index: int, facing_slots: int)
signal level_changed(building: Building, level: int, stats: BuildingLevelStats)
signal attack_performed(building: Building, target: CombatTarget, damage: float, continuous: bool)

var definition: BuildingDefinition
var cell: Vector3i = Vector3i.ZERO
var facing_index: int = 0
var level: int = 1

var _grid: GridManager
var _tile_manager: TileManager
var _combat_manager: CombatManager
var _stats: BuildingLevelStats
var _targeting_strategy: PriorityTargetingStrategy
var _attack_strategy: IAttackStrategy
var _locked_target: CombatTarget
var _preview_mode: bool = false
var _visual_root: Node3D
var _attack_line_instance: MeshInstance3D
var _attack_line_material: StandardMaterial3D

func _process(delta: float) -> void:
	if not feature_enabled or _preview_mode or _stats == null or _attack_strategy == null:
		return
	_attack_strategy.tick(self, delta)

func configure(
	building_definition: BuildingDefinition,
	building_cell: Vector3i,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	initial_level: int = 1,
	preview_mode: bool = false
) -> void:
	definition = building_definition
	cell = building_cell
	_grid = grid_manager
	_tile_manager = tile_manager
	_combat_manager = combat_manager
	_preview_mode = preview_mode
	feature_enabled = not preview_mode
	position = _grid.cell_to_world(cell) + Vector3(0.0, _tile_manager.get_world_height(cell), 0.0)
	apply_level(initial_level)
	set_facing_index(0)

func apply_level(value: int) -> bool:
	if definition == null or not definition.is_configured():
		return false
	var next_stats := definition.get_level_stats(value)
	if next_stats == null:
		return false
	if _attack_strategy != null:
		_attack_strategy.reset(self)
	level = clampi(value, 1, definition.get_max_level())
	_stats = next_stats
	_locked_target = null
	_targeting_strategy = PriorityTargetingStrategy.new(_stats.target_priority)
	_configure_attack_strategy()
	_build_visual()
	set_facing_index(facing_index)
	level_changed.emit(self, level, _stats)
	return true

func can_upgrade() -> bool:
	return definition != null and level < definition.get_max_level()

func get_level_stats() -> BuildingLevelStats:
	return _stats

func get_max_level() -> int:
	return definition.get_max_level() if definition != null else 0

func get_upgrade_cost() -> float:
	if not can_upgrade():
		return 0.0
	var next_stats := definition.get_level_stats(level + 1)
	return next_stats.cost if next_stats != null else 0.0

func get_resource_per_second() -> float:
	return _stats.resource_per_second if _stats != null else 0.0

func acquire_target() -> CombatTarget:
	if _combat_manager == null or _targeting_strategy == null:
		return null
	if not is_instance_valid(_locked_target):
		_locked_target = null
	var candidates := _combat_manager.get_targets_in_range(get_attack_origin(), get_targeting_range_world())
	_locked_target = _targeting_strategy.select_target(candidates, get_attack_origin(), _locked_target)
	return _locked_target

func is_target_in_attack_range(target: CombatTarget) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var origin := Vector2(global_position.x, global_position.z)
	var target_position := Vector2(target.global_position.x, target.global_position.z)
	return origin.distance_squared_to(target_position) <= get_attack_range_world() * get_attack_range_world()

func rotate_facing(step: int = 1) -> void:
	set_facing_index(facing_index + step)

func set_facing_index(value: int) -> void:
	var slots := get_facing_slot_count()
	facing_index = posmod(value, slots)
	var direction := get_facing_direction()
	rotation.y = atan2(-direction.x, -direction.z)
	facing_changed.emit(self, facing_index, slots)

func get_facing_slot_count() -> int:
	if _grid != null and _grid.grid_shape == GridManager.Shape.SQUARE:
		return 8
	return 6

func get_facing_direction() -> Vector3:
	if get_facing_slot_count() == 8:
		var square_angle := deg_to_rad(45.0 * float(facing_index))
		return Vector3(cos(square_angle), 0.0, sin(square_angle)).normalized()
	var hex_angle := deg_to_rad(-30.0 + 60.0 * float(facing_index))
	return Vector3(cos(hex_angle), 0.0, sin(hex_angle)).normalized()

func get_attack_origin() -> Vector3:
	return global_position + Vector3(0.0, _get_tower_height() * 0.82, 0.0)

func get_laser_end() -> Vector3:
	return get_attack_origin() + get_facing_direction() * get_attack_range_world()

func get_targeting_range_world() -> float:
	return _stats.targeting_range * _grid.cell_size

func get_attack_range_world() -> float:
	return _stats.attack_range * _grid.cell_size

func get_attacks_per_second() -> float:
	return _stats.attacks_per_second

func get_instant_damage() -> float:
	return DamageCalculator.compute(_stats.base_damage, _stats.level_factor, _stats.extra_factor)

func get_laser_damage_per_second() -> float:
	return DamageCalculator.compute(_stats.laser_dps, _stats.level_factor, _stats.extra_factor)

func get_combat_manager() -> CombatManager:
	return _combat_manager

func launch_projectile(target: CombatTarget, damage: float) -> Projectile:
	if _combat_manager == null or _stats == null:
		return null
	var projectile := _combat_manager.spawn_projectile(
		get_attack_origin(),
		target,
		_stats.projectile_speed * _grid.cell_size,
		damage,
		get_attack_range_world(),
		_stats.projectile_length * _grid.cell_size,
		_stats.projectile_width * _grid.cell_size,
		_stats.attack_color
	)
	if projectile != null:
		projectile.impacted.connect(_on_projectile_impacted)
	return projectile

func show_attack_line(world_end: Vector3, _persistent: bool) -> void:
	if _attack_line_instance == null:
		return
	var line_mesh := ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _attack_line_material)
	line_mesh.surface_add_vertex(_attack_line_instance.to_local(get_attack_origin()))
	line_mesh.surface_add_vertex(_attack_line_instance.to_local(world_end))
	line_mesh.surface_end()
	_attack_line_instance.mesh = line_mesh

func clear_attack_visual() -> void:
	if _attack_line_instance != null:
		_attack_line_instance.mesh = null

func notify_attack(target: CombatTarget, damage: float, continuous: bool) -> void:
	if damage > 0.0:
		attack_performed.emit(self, target, damage, continuous)

func shutdown() -> void:
	feature_enabled = false
	_locked_target = null
	if _attack_strategy != null:
		_attack_strategy.reset(self)

func _configure_attack_strategy() -> void:
	if _preview_mode:
		_attack_strategy = null
	elif definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		_attack_strategy = LaserAttackStrategyScript.new()
	else:
		_attack_strategy = ArrowAttackStrategyScript.new()

func _build_visual() -> void:
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
	_visual_root = Node3D.new()
	add_child(_visual_root)
	if _stats.visual_scene != null:
		var custom_visual := _stats.visual_scene.instantiate()
		if custom_visual is Node3D:
			_visual_root.add_child(custom_visual)
			if _preview_mode:
				_apply_preview_materials(custom_visual)
		else:
			custom_visual.queue_free()
	else:
		_build_default_body()
	_build_direction_marker()
	_build_attack_line()

func _build_default_body() -> void:
	var cell_size := _grid.cell_size
	var tower_height := _get_tower_height()
	var body_instance := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = cell_size * base_radius_ratio * 0.72
	body_mesh.bottom_radius = cell_size * base_radius_ratio
	body_mesh.height = tower_height
	body_instance.mesh = body_mesh
	body_instance.position.y = tower_height * 0.5
	body_instance.material_override = _make_material(_stats.tower_color, false)
	_visual_root.add_child(body_instance)

func _build_direction_marker() -> void:
	var cell_size := _grid.cell_size
	var tower_height := _get_tower_height()
	var direction_instance := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(cell_size * 0.12, cell_size * 0.12, cell_size * direction_marker_ratio)
	direction_instance.mesh = marker_mesh
	direction_instance.position = Vector3(0.0, tower_height * 0.78, -cell_size * direction_marker_ratio * 0.45)
	direction_instance.material_override = _make_material(_stats.attack_color, true)
	_visual_root.add_child(direction_instance)

func _build_attack_line() -> void:
	_attack_line_instance = MeshInstance3D.new()
	_attack_line_material = _make_material(_stats.attack_color, true)
	_attack_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_line_instance.material_override = _attack_line_material
	_visual_root.add_child(_attack_line_instance)

func _apply_preview_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		mesh_instance.material_override = _make_material(_stats.tower_color, false)
	for child in node.get_children():
		_apply_preview_materials(child)

func _get_tower_height() -> float:
	return _grid.cell_size * tower_height_ratio if _grid != null else tower_height_ratio

func _make_material(color: Color, emissive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var resolved_color := color
	if _preview_mode:
		resolved_color.a = preview_alpha
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = resolved_color
	material.roughness = 0.65
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material

func _on_projectile_impacted(target: CombatTarget, applied_damage: float) -> void:
	notify_attack(target, applied_damage, false)
