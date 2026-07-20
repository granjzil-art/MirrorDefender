## Runtime tower assembled from a definition, current level stats, and strategies.
class_name Building
extends Node3D

const ArrowAttackStrategyScript := preload("res://scripts/combat/ArrowAttackStrategy.gd")
const LaserAttackStrategyScript := preload("res://scripts/combat/LaserAttackStrategy.gd")
const BarrierDurabilityScript := preload("res://scripts/building/BarrierDurability.gd")
const ACTION_ANCHOR_HEIGHT_RATIO := 1.15

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
signal copy_attack_triggered(building: Building, attack_kind: StringName, world_start: Vector3, world_end: Vector3, damage: float)
signal durability_changed(building: Building, current: float, maximum: float)
signal structure_destroyed(building: Building, attacker: Node)

var definition: BuildingDefinition
var cell: Vector3i = Vector3i.ZERO
var edge_to_cell: Vector3i = Vector3i.ZERO
var edge_index: int = -1
var edge_id: String = ""
var facing_index: int = 0
var level: int = 1
var current_durability: float:
	get:
		return _durability.current if _durability != null else 0.0
var maximum_durability: float:
	get:
		return _durability.maximum if _durability != null else 0.0

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
var _durability_label: Label3D
var _durability: BarrierDurability

func _process(delta: float) -> void:
	if not feature_enabled or _preview_mode or _stats == null:
		return
	if is_path_blocker():
		_durability.tick(delta)
	elif _attack_strategy != null:
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
	edge_to_cell = Vector3i.ZERO
	edge_index = -1
	edge_id = ""
	_configure_common(
		building_definition,
		building_cell,
		grid_manager,
		tile_manager,
		combat_manager,
		initial_level,
		preview_mode
	)

func configure_edge(
	building_definition: BuildingDefinition,
	from_cell: Vector3i,
	to_cell: Vector3i,
	placement_edge_index: int,
	placement_edge_id: String,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	initial_level: int = 1,
	preview_mode: bool = false
) -> void:
	edge_to_cell = to_cell
	edge_index = placement_edge_index
	edge_id = placement_edge_id
	_configure_common(
		building_definition,
		from_cell,
		grid_manager,
		tile_manager,
		combat_manager,
		initial_level,
		preview_mode
	)

func _configure_common(
	building_definition: BuildingDefinition,
	building_cell: Vector3i,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	initial_level: int,
	preview_mode: bool
) -> void:
	definition = building_definition
	cell = building_cell
	_grid = grid_manager
	_tile_manager = tile_manager
	_combat_manager = combat_manager
	_preview_mode = preview_mode
	feature_enabled = not preview_mode
	if is_edge_placement():
		var endpoints: Array[Vector3] = _grid.get_edge_endpoints(cell, edge_index)
		var edge_midpoint := _grid.cell_to_world(cell)
		if endpoints.size() == 2:
			edge_midpoint = (endpoints[0] + endpoints[1]) * 0.5
		var edge_height := maxf(
			_tile_manager.get_world_height(cell),
			_tile_manager.get_world_height(edge_to_cell)
		)
		position = edge_midpoint + Vector3(0.0, edge_height, 0.0)
	else:
		position = _grid.cell_to_world(cell) + Vector3(0.0, _tile_manager.get_world_height(cell), 0.0)
	apply_level(initial_level)
	set_facing_index(edge_index if is_edge_placement() else 0)

func apply_level(value: int) -> bool:
	if definition == null or not definition.is_configured():
		return false
	var next_stats := definition.get_level_stats(value)
	if next_stats == null:
		return false
	var was_configured := _stats != null
	if _attack_strategy != null:
		_attack_strategy.reset(self)
	level = clampi(value, 1, definition.get_max_level())
	_stats = next_stats
	_locked_target = null
	_targeting_strategy = PriorityTargetingStrategy.new(_stats.target_priority)
	_configure_attack_strategy()
	if is_path_blocker():
		if _durability == null:
			_durability = BarrierDurabilityScript.new()
			_durability.durability_changed.connect(_on_durability_changed)
			_durability.depleted.connect(_on_durability_depleted)
		_durability.configure(_stats, was_configured)
	else:
		_durability = null
	_build_visual()
	set_facing_index(facing_index)
	if is_path_blocker():
		_update_durability_label()
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

func get_refund_amount() -> float:
	return _stats.refund_amount if _stats != null else 0.0

func is_path_blocker() -> bool:
	return definition != null and definition.is_defensive_structure()

func is_tile_path_blocker() -> bool:
	return is_path_blocker() and not is_edge_placement()

func is_edge_path_blocker() -> bool:
	return is_path_blocker() and is_edge_placement()

func is_edge_placement() -> bool:
	return definition != null and definition.is_edge_building() and edge_index >= 0 and not edge_id.is_empty()

func matches_directed_edge(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	return is_edge_placement() and cell == from_cell and edge_to_cell == to_cell

func blocks_edge_traversal(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	if not is_edge_path_blocker():
		return false
	if matches_directed_edge(from_cell, to_cell):
		return true
	return definition.blocks_both_directions and cell == to_cell and edge_to_cell == from_cell

func is_bidirectional_edge_blocker() -> bool:
	return is_edge_path_blocker() and definition.blocks_both_directions

func is_structure_alive() -> bool:
	return is_path_blocker() and _durability != null and _durability.is_alive() and not is_queued_for_deletion()

func get_structure_target_position() -> Vector3:
	return global_position + Vector3(0.0, _get_tower_height() * 0.45, 0.0)

func get_structure_hit_radius() -> float:
	var cell_size := _grid.cell_size if _grid != null else 1.0
	return cell_size * 0.30

func get_durability_ratio() -> float:
	return _durability.get_ratio() if _durability != null else 0.0

func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not feature_enabled or _preview_mode or _durability == null:
		return 0.0
	return _durability.take_damage(amount, attacker, affects_target(attacker))

func affects_target(target: Node) -> bool:
	if _stats == null:
		return false
	if _stats.affects_airborne or target == null or not is_instance_valid(target):
		return true
	if not target.has_method("is_airborne_unit"):
		return true
	return not bool(target.call("is_airborne_unit"))

func restore_durability(amount: float) -> float:
	return _durability.restore(amount) if _durability != null else 0.0

func acquire_target() -> CombatTarget:
	if _combat_manager == null or _targeting_strategy == null:
		return null
	if not is_instance_valid(_locked_target):
		_locked_target = null
	var candidates: Array[CombatTarget] = []
	for target in _combat_manager.get_targets_in_range(get_attack_origin(), get_targeting_range_world()):
		if affects_target(target):
			candidates.append(target)
	_locked_target = _targeting_strategy.select_target(candidates, get_attack_origin(), _locked_target)
	return _locked_target

func is_target_in_attack_range(target: CombatTarget) -> bool:
	if target == null or not is_instance_valid(target) or not affects_target(target):
		return false
	var origin := Vector2(global_position.x, global_position.z)
	var target_position := Vector2(target.global_position.x, target.global_position.z)
	return origin.distance_squared_to(target_position) <= get_attack_range_world() * get_attack_range_world()

func can_rotate_in_place() -> bool:
	return not is_edge_placement()

func rotate_facing(step: int = 1) -> bool:
	if not can_rotate_in_place():
		return false
	set_facing_index(facing_index + step)
	return true

func set_facing_index(value: int) -> void:
	var slots := get_facing_slot_count()
	facing_index = posmod(edge_index if is_edge_placement() else value, slots)
	var direction := get_facing_direction()
	rotation.y = atan2(-direction.x, -direction.z)
	facing_changed.emit(self, facing_index, slots)

func get_facing_slot_count() -> int:
	if _grid == null:
		return 6
	return _grid.get_edge_building_facing_count() if is_edge_placement() else _grid.get_tile_building_facing_count()

func get_facing_direction() -> Vector3:
	if is_edge_placement() and _grid != null:
		return (_grid.cell_to_world(edge_to_cell) - _grid.cell_to_world(cell)).normalized()
	if get_facing_slot_count() == 8:
		var square_angle := deg_to_rad(45.0 * float(facing_index))
		return Vector3(cos(square_angle), 0.0, sin(square_angle)).normalized()
	var hex_angle := deg_to_rad(-30.0 + 60.0 * float(facing_index))
	return Vector3(cos(hex_angle), 0.0, sin(hex_angle)).normalized()

func get_attack_origin() -> Vector3:
	return global_position + Vector3(0.0, _get_tower_height() * 0.82, 0.0)

func get_action_anchor() -> Vector3:
	var cell_size := _grid.cell_size if _grid != null else 1.0
	return global_position + Vector3(0.0, cell_size * ACTION_ANCHOR_HEIGHT_RATIO, 0.0)

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

func get_copy_kind() -> StringName:
	if definition == null or is_edge_placement():
		return &""
	if definition.kind == BuildingDefinition.Kind.BARRIER:
		return &"barrier"
	if definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		return &"laser_tower"
	if definition.kind == BuildingDefinition.Kind.ARROW_TOWER:
		return &"arrow_tower"
	return &""

func get_copy_display_name() -> String:
	return definition.display_name if definition != null else "建筑"

func get_copy_color() -> Color:
	return _stats.tower_color if _stats != null else Color.WHITE

func get_projectile_speed_world() -> float:
	return _stats.projectile_speed * _grid.cell_size if _stats != null and _grid != null else 1.0

func get_projectile_length_world() -> float:
	return _stats.projectile_length * _grid.cell_size if _stats != null and _grid != null else 0.2

func get_projectile_width_world() -> float:
	return _stats.projectile_width * _grid.cell_size if _stats != null and _grid != null else 0.05

func get_attack_color() -> Color:
	return _stats.attack_color if _stats != null else Color.WHITE

func notify_copy_attack(attack_kind: StringName, world_start: Vector3, world_end: Vector3, damage: float) -> void:
	copy_attack_triggered.emit(self, attack_kind, world_start, world_end, maxf(0.0, damage))

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
		notify_copy_attack(&"projectile", get_attack_origin(), target.get_target_position(), damage)
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

func create_copy_visual_snapshot() -> Node3D:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return null
	var snapshot := _visual_root.duplicate(0) as Node3D
	if snapshot == null:
		return null
	_sanitize_copy_visual_snapshot(snapshot)
	return snapshot

func get_copy_visual_transform() -> Transform3D:
	return global_transform * (_visual_root.transform if _visual_root != null else Transform3D.IDENTITY)

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
	elif definition.is_defensive_structure():
		_attack_strategy = null
	elif definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		_attack_strategy = LaserAttackStrategyScript.new()
	else:
		_attack_strategy = ArrowAttackStrategyScript.new()

func _build_visual() -> void:
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
	_attack_line_instance = null
	_attack_line_material = null
	_durability_label = null
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
	if is_edge_path_blocker():
		_build_direction_marker()
		if is_bidirectional_edge_blocker():
			_build_direction_marker(true)
	elif not is_path_blocker():
		_build_direction_marker()
		_build_attack_line()

func _build_default_body() -> void:
	if is_path_blocker():
		_build_barrier_body()
		return
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

func _build_barrier_body() -> void:
	var cell_size := _grid.cell_size
	var barrier_height := _get_tower_height() * 0.82
	var body_instance := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(cell_size * 0.88, barrier_height, cell_size * 0.20)
	body_instance.mesh = body_mesh
	body_instance.position.y = barrier_height * 0.5
	body_instance.material_override = _make_material(_stats.tower_color, false)
	_visual_root.add_child(body_instance)
	_durability_label = Label3D.new()
	_durability_label.position.y = barrier_height + cell_size * 0.18
	_durability_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_durability_label.no_depth_test = true
	_durability_label.font_size = 26
	_visual_root.add_child(_durability_label)
	_update_durability_label()

func _build_direction_marker(reverse_direction: bool = false) -> void:
	var cell_size := _grid.cell_size
	var tower_height := _get_tower_height()
	var direction_instance := MeshInstance3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(cell_size * 0.12, cell_size * 0.12, cell_size * direction_marker_ratio)
	direction_instance.mesh = marker_mesh
	var direction_sign := 1.0 if reverse_direction else -1.0
	direction_instance.position = Vector3(0.0, tower_height * 0.78, direction_sign * cell_size * direction_marker_ratio * 0.45)
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

func _sanitize_copy_visual_snapshot(node: Node) -> void:
	for child in node.get_children():
		if child is Label3D or child is Control or child is AnimationPlayer or child is AudioStreamPlayer3D:
			child.free()
		else:
			_sanitize_copy_visual_snapshot(child)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null:
		node.set_script(null)

func _get_tower_height() -> float:
	return _grid.cell_size * tower_height_ratio if _grid != null else tower_height_ratio

func _update_durability_label() -> void:
	if _durability_label == null:
		return
	_durability_label.text = "%d/%d" % [ceili(current_durability), ceili(maximum_durability)]

func _on_durability_changed(current: float, maximum: float) -> void:
	_update_durability_label()
	durability_changed.emit(self, current, maximum)

func _on_durability_depleted(attacker: Node) -> void:
	structure_destroyed.emit(self, attacker)

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
