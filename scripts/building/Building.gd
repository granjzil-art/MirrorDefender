## Runtime tower assembled from a definition, targeting strategy, and attack strategy.
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
@export_range(0.01, 1.0, 0.01, "or_greater") var attack_flash_duration: float = 0.12

signal facing_changed(building: Building, facing_index: int, facing_slots: int)
signal attack_performed(building: Building, target: CombatTarget, damage: float, continuous: bool)

var definition: BuildingDefinition
var cell: Vector3i = Vector3i.ZERO
var facing_index: int = 0
var level: int = 1

var _grid: GridManager
var _tile_manager: TileManager
var _combat_manager: CombatManager
var _targeting_strategy: PriorityTargetingStrategy
var _attack_strategy: IAttackStrategy
var _locked_target: CombatTarget
var _body_instance: MeshInstance3D
var _direction_instance: MeshInstance3D
var _attack_line_instance: MeshInstance3D
var _attack_line_material: StandardMaterial3D
var _attack_flash_remaining: float = 0.0
var _attack_line_persistent: bool = false

func _process(delta: float) -> void:
	if not feature_enabled or definition == null or _attack_strategy == null:
		return
	_attack_strategy.tick(self, delta)
	if not _attack_line_persistent and _attack_flash_remaining > 0.0:
		_attack_flash_remaining = maxf(0.0, _attack_flash_remaining - delta)
		if _attack_flash_remaining <= 0.0:
			clear_attack_visual()

func configure(
	building_definition: BuildingDefinition,
	building_cell: Vector3i,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager
) -> void:
	definition = building_definition
	cell = building_cell
	_grid = grid_manager
	_tile_manager = tile_manager
	_combat_manager = combat_manager
	_targeting_strategy = PriorityTargetingStrategy.new(definition.target_priority)
	if definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		_attack_strategy = LaserAttackStrategyScript.new()
	else:
		_attack_strategy = ArrowAttackStrategyScript.new()
	position = _grid.cell_to_world(cell) + Vector3(0.0, _tile_manager.get_world_height(cell), 0.0)
	_build_visual()
	set_facing_index(0)

func acquire_target() -> CombatTarget:
	if _combat_manager == null or _targeting_strategy == null:
		return null
	if not is_instance_valid(_locked_target):
		_locked_target = null
	var candidates := _combat_manager.get_targets_in_range(get_attack_origin(), get_attack_range_world())
	_locked_target = _targeting_strategy.select_target(candidates, get_attack_origin(), _locked_target)
	return _locked_target

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

func get_attack_range_world() -> float:
	return definition.attack_range * _grid.cell_size

func get_attacks_per_second() -> float:
	return definition.attacks_per_second

func get_instant_damage() -> float:
	return DamageCalculator.compute(definition.base_damage, definition.level_factor, definition.extra_factor)

func get_laser_damage_per_second() -> float:
	return DamageCalculator.compute(definition.laser_dps, definition.level_factor, definition.extra_factor)

func get_combat_manager() -> CombatManager:
	return _combat_manager

func show_attack_line(world_end: Vector3, persistent: bool) -> void:
	if _attack_line_instance == null:
		return
	var line_mesh := ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _attack_line_material)
	line_mesh.surface_add_vertex(_attack_line_instance.to_local(get_attack_origin()))
	line_mesh.surface_add_vertex(_attack_line_instance.to_local(world_end))
	line_mesh.surface_end()
	_attack_line_instance.mesh = line_mesh
	_attack_line_persistent = persistent
	_attack_flash_remaining = attack_flash_duration

func clear_attack_visual() -> void:
	if _attack_line_instance != null:
		_attack_line_instance.mesh = null
	_attack_line_persistent = false
	_attack_flash_remaining = 0.0

func notify_attack(target: CombatTarget, damage: float, continuous: bool) -> void:
	if damage > 0.0:
		attack_performed.emit(self, target, damage, continuous)

func shutdown() -> void:
	feature_enabled = false
	_locked_target = null
	if _attack_strategy != null:
		_attack_strategy.reset(self)

func _build_visual() -> void:
	var cell_size := _grid.cell_size
	var tower_height := _get_tower_height()
	_body_instance = MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = cell_size * base_radius_ratio * 0.72
	body_mesh.bottom_radius = cell_size * base_radius_ratio
	body_mesh.height = tower_height
	_body_instance.mesh = body_mesh
	_body_instance.position.y = tower_height * 0.5
	_body_instance.material_override = _make_material(definition.tower_color, false)
	add_child(_body_instance)
	_direction_instance = MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(
		cell_size * 0.12,
		cell_size * 0.12,
		cell_size * direction_marker_ratio
	)
	_direction_instance.mesh = marker_mesh
	_direction_instance.position = Vector3(0.0, tower_height * 0.78, -cell_size * direction_marker_ratio * 0.45)
	_direction_instance.material_override = _make_material(definition.attack_color, true)
	add_child(_direction_instance)
	_attack_line_instance = MeshInstance3D.new()
	_attack_line_material = _make_material(definition.attack_color, true)
	_attack_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_line_instance.material_override = _attack_line_material
	add_child(_attack_line_instance)

func _get_tower_height() -> float:
	return _grid.cell_size * tower_height_ratio if _grid != null else tower_height_ratio

func _make_material(color: Color, emissive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material
