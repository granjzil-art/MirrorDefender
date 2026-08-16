## Runtime tower assembled from a definition, current level stats, and strategies.
class_name Building
extends Node3D

const ArrowAttackStrategyScript := preload("res://scripts/combat/ArrowAttackStrategy.gd")
const LaserAttackStrategyScript := preload("res://scripts/combat/LaserAttackStrategy.gd")
const ContinuousLaserVisualScript := preload("res://scripts/combat/ContinuousLaserVisual.gd")
const PulseLaserAttackStrategyScript := preload("res://scripts/combat/PulseLaserAttackStrategy.gd")
const MaceAttackStrategyScript := preload("res://scripts/combat/MaceAttackStrategy.gd")
const BarrierDurabilityScript := preload("res://scripts/building/BarrierDurability.gd")
const SelectionHighlightScript := preload("res://scripts/presentation/SelectionHighlight.gd")
const ACTION_ANCHOR_HEIGHT_RATIO := 1.15
const FREE_FACING_SLOT_COUNT := 36
const FREE_FACING_STEP_DEGREES := 10.0

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Visual Scale")
@export_range(0.1, 2.0, 0.05, "or_greater") var tower_height_ratio: float = 0.75
@export_range(0.05, 1.0, 0.05, "or_greater") var base_radius_ratio: float = 0.24
@export_range(0.01, 1.0, 0.01, "or_greater") var direction_marker_ratio: float = 0.32
@export_range(0.05, 1.0, 0.05) var preview_alpha: float = 0.38
@export var valid_preview_color: Color = Color(0.12, 1.0, 0.24, 0.82)
@export var invalid_preview_color: Color = Color(1.0, 0.08, 0.08, 0.82)

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
var _preview_valid: bool = true
var _selected: bool = false
var _visual_root: Node3D
var _continuous_laser_visual: Node3D
var _durability_label: Label3D
var _durability: BarrierDurability
var _pulse_copy_mirror_state: Dictionary = {
	"phase": &"charging",
	"charge_count": 0,
	"charge_shots": 5,
	"pending_remaining": 0.0,
	"overdrive_remaining": 0.0,
	"overdrive_duration": 10.0,
	"generation": 0,
}
var _ice_copy_mirror_elapsed: float = 0.0
var _ice_copy_mirror_event_sequence: int = 0

func _process(delta: float) -> void:
	if not feature_enabled or _preview_mode or _stats == null:
		return
	_tick_pulse_copy_mirror_state(delta)
	if is_path_blocker():
		_durability.tick(delta)
	elif _attack_strategy != null:
		_attack_strategy.tick(self, delta)
		update_visual_orientation(delta)

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
		preview_mode,
		null
	)


## Runtime combat-data entry. The supplied level_data is authoritative for this
## instance and is intentionally not resolved through definition.levels.
func configure_runtime_level_data(
	building_definition: BuildingDefinition,
	level_data: BuildingLevelStats,
	building_level: int,
	building_cell: Vector3i,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	preview_mode: bool = false
) -> bool:
	edge_to_cell = Vector3i.ZERO
	edge_index = -1
	edge_id = ""
	return _configure_common(
		building_definition,
		building_cell,
		grid_manager,
		tile_manager,
		combat_manager,
		building_level,
		preview_mode,
		level_data
	)


func set_preview_valid(valid: bool) -> void:
	if not _preview_mode or _preview_valid == valid:
		return
	_preview_valid = valid
	_refresh_preview_materials(_visual_root)


func set_selected(selected: bool) -> void:
	_selected = selected
	if _visual_root != null and is_instance_valid(_visual_root):
		SelectionHighlightScript.apply_recursive(_visual_root, _selected and not _preview_mode)


func is_selected() -> bool:
	return _selected


func is_preview_valid() -> bool:
	return _preview_valid


func get_preview_display_color() -> Color:
	return invalid_preview_color if not _preview_valid else valid_preview_color


## Moves an existing tile-placement ghost without rebuilding its model tree.
func relocate_tile_preview(building_cell: Vector3i) -> bool:
	if not _preview_mode or is_edge_placement():
		return false
	cell = building_cell
	refresh_world_transform()
	return true


## Moves an existing edge-placement ghost without rebuilding its model tree.
func relocate_edge_preview(
	from_cell: Vector3i,
	to_cell: Vector3i,
	placement_edge_index: int,
	placement_edge_id: String
) -> bool:
	if not _preview_mode or not definition.is_edge_building():
		return false
	cell = from_cell
	edge_to_cell = to_cell
	edge_index = placement_edge_index
	edge_id = placement_edge_id
	refresh_world_transform()
	set_facing_index(placement_edge_index)
	return true


## Relocates a live tile building without rebuilding its level/combat state.
## Occupancy ownership is updated atomically by BuildingManager before this is
## exposed to the rest of the runtime.
func relocate_runtime_tile(building_cell: Vector3i) -> bool:
	if _preview_mode or is_edge_placement():
		return false
	cell = building_cell
	refresh_world_transform()
	return true


## Live edge counterpart of relocate_runtime_tile(). Durability, upgrades,
## investment, and active attack strategy remain owned by this same instance.
func relocate_runtime_edge(
	from_cell: Vector3i,
	to_cell: Vector3i,
	placement_edge_index: int,
	placement_edge_id: String
) -> bool:
	if _preview_mode or definition == null or not definition.is_edge_building():
		return false
	cell = from_cell
	edge_to_cell = to_cell
	edge_index = placement_edge_index
	edge_id = placement_edge_id
	refresh_world_transform()
	set_facing_index(placement_edge_index)
	return true

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
		preview_mode,
		null
	)


## Edge-placement counterpart of configure_runtime_level_data().
func configure_edge_runtime_level_data(
	building_definition: BuildingDefinition,
	level_data: BuildingLevelStats,
	building_level: int,
	from_cell: Vector3i,
	to_cell: Vector3i,
	placement_edge_index: int,
	placement_edge_id: String,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	preview_mode: bool = false
) -> bool:
	edge_to_cell = to_cell
	edge_index = placement_edge_index
	edge_id = placement_edge_id
	return _configure_common(
		building_definition,
		from_cell,
		grid_manager,
		tile_manager,
		combat_manager,
		building_level,
		preview_mode,
		level_data
	)

func _configure_common(
	building_definition: BuildingDefinition,
	building_cell: Vector3i,
	grid_manager: GridManager,
	tile_manager: TileManager,
	combat_manager: CombatManager,
	initial_level: int,
	preview_mode: bool,
	level_data_override: BuildingLevelStats
) -> bool:
	definition = building_definition
	cell = building_cell
	_grid = grid_manager
	_tile_manager = tile_manager
	_combat_manager = combat_manager
	_preview_mode = preview_mode
	feature_enabled = not preview_mode
	refresh_world_transform()
	var configured := (
		apply_runtime_level_data(initial_level, level_data_override)
		if level_data_override != null
		else apply_level(initial_level)
	)
	if not configured:
		return false
	set_facing_index(edge_index if is_edge_placement() else 0)
	return true


## Re-samples the canonical terrain surface without rebuilding combat state.
func refresh_world_transform() -> void:
	if _grid == null or _tile_manager == null:
		return
	if is_edge_placement():
		var endpoints: Array[Vector3] = _grid.get_edge_endpoints(cell, edge_index)
		var edge_midpoint := _grid.cell_to_world(cell)
		if endpoints.size() == 2:
			edge_midpoint = (endpoints[0] + endpoints[1]) * 0.5
		var edge_height := maxf(
			_grid.sample_cell_surface_height(cell, edge_midpoint),
			_grid.sample_cell_surface_height(edge_to_cell, edge_midpoint)
		)
		position = edge_midpoint + Vector3(0.0, edge_height, 0.0)
	else:
		position = _grid.cell_to_world(cell) + Vector3(0.0, _tile_manager.get_world_height(cell), 0.0)

func apply_level(value: int) -> bool:
	if definition == null or not definition.is_configured():
		return false
	var next_stats := definition.get_level_stats(value)
	if next_stats == null:
		return false
	return apply_runtime_level_data(value, next_stats)


## Lightweight explicit level-data application used by runtime authoring. It
## never looks up definition.levels, so a temporary working copy can be applied
## without mutating the persistent Resource.
func apply_runtime_level_data(value: int, level_data: BuildingLevelStats) -> bool:
	if definition == null or level_data == null:
		return false
	if not level_data.validate_configuration().is_empty():
		return false
	var was_configured := _stats != null
	if _attack_strategy != null:
		_attack_strategy.reset(self)
	level = clampi(value, 1, definition.get_max_level())
	_stats = level_data
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


func can_downgrade() -> bool:
	return definition != null and level > 1


func get_level_stats() -> BuildingLevelStats:
	return _stats

func get_max_level() -> int:
	return definition.get_max_level() if definition != null else 0

func get_upgrade_cost() -> float:
	if not can_upgrade():
		return 0.0
	var next_stats := definition.get_level_stats(level + 1)
	return next_stats.cost if next_stats != null else 0.0


func get_downgrade_refund() -> float:
	if not can_downgrade():
		return 0.0
	var current_stats := definition.get_level_stats(level)
	return maxf(0.0, current_stats.cost) if current_stats != null else 0.0

func get_resource_per_second() -> float:
	return _stats.resource_per_second if _stats != null else 0.0

func get_refund_amount() -> float:
	return definition.get_cumulative_cost(level) if definition != null else 0.0

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
	var airborne_candidates: Array[CombatTarget] = []
	for target in _combat_manager.get_targets_in_range(get_attack_origin(), get_targeting_range_world()):
		if affects_target(target):
			candidates.append(target)
			if target.is_airborne_unit():
				airborne_candidates.append(target)
	if _stats.prioritizes_airborne and not airborne_candidates.is_empty():
		candidates = airborne_candidates
	_locked_target = _targeting_strategy.select_target(candidates, get_attack_origin(), _locked_target)
	return _locked_target


func has_target_in_range() -> bool:
	if _combat_manager == null or _stats == null:
		return false
	for target in _combat_manager.get_targets_in_range(get_attack_origin(), get_targeting_range_world()):
		if affects_target(target):
			return true
	return false

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
		return FREE_FACING_SLOT_COUNT
	return _grid.get_edge_building_facing_count() if is_edge_placement() else FREE_FACING_SLOT_COUNT

func get_facing_direction() -> Vector3:
	if is_edge_placement() and _grid != null:
		return (_grid.cell_to_world(edge_to_cell) - _grid.cell_to_world(cell)).normalized()
	var angle := deg_to_rad(FREE_FACING_STEP_DEGREES * float(facing_index))
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()

## Updates presentation only. Logical facing_index and fixed-direction attacks
## remain owned by set_facing_index().
func update_visual_orientation(delta: float) -> bool:
	if definition == null or definition.aim_mode != BuildingDefinition.AimMode.TRACK_TARGET:
		return false
	if _visual_root == null or not is_instance_valid(_visual_root):
		return false
	var target := _get_valid_visual_target()
	var world_direction := get_facing_direction()
	if target != null:
		world_direction = target.get_target_position() - get_attack_origin()
	world_direction.y = 0.0
	if world_direction.length_squared() <= 0.000001:
		return false
	var local_direction := global_basis.inverse() * world_direction.normalized()
	var desired_yaw := atan2(-local_direction.x, -local_direction.z)
	var current_yaw := _visual_root.rotation.y
	var yaw_delta := wrapf(desired_yaw - current_yaw, -PI, PI)
	var maximum_step := deg_to_rad(definition.visual_turn_speed_degrees) * maxf(0.0, delta)
	var applied_delta := clampf(yaw_delta, -maximum_step, maximum_step)
	if is_zero_approx(applied_delta):
		return false
	_visual_root.rotation.y = wrapf(current_yaw + applied_delta, -PI, PI)
	return true

func get_visual_facing_direction() -> Vector3:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return get_facing_direction()
	return -_visual_root.global_basis.z.normalized()

func get_attack_origin() -> Vector3:
	return global_position + Vector3(0.0, _get_tower_height() * 0.82, 0.0)

func get_action_anchor() -> Vector3:
	var cell_size := _grid.cell_size if _grid != null else 1.0
	return global_position + Vector3(0.0, cell_size * ACTION_ANCHOR_HEIGHT_RATIO, 0.0)

func get_laser_end() -> Vector3:
	return get_attack_origin() + get_facing_direction() * get_attack_range_world()

func get_targeting_range_world() -> float:
	return _stats.targeting_range * _grid.cell_size


func uses_targeting_range() -> bool:
	return (
		definition != null
		and not definition.is_defensive_structure()
		and not fires_only_along_facing()
		and (
			definition.aim_mode == BuildingDefinition.AimMode.TRACK_TARGET
			or definition.kind == BuildingDefinition.Kind.MACE_TOWER
		)
	)

func get_attack_range_world() -> float:
	return _stats.attack_range * _grid.cell_size

func get_attacks_per_second() -> float:
	return _stats.attacks_per_second


func fires_along_facing_without_target() -> bool:
	return (
		_stats != null
		and _stats.projectile_fire_mode in [
			BuildingLevelStats.ProjectileFireMode.TARGET_OR_FACING,
			BuildingLevelStats.ProjectileFireMode.FACING_ONLY,
		]
	)


func fires_only_along_facing() -> bool:
	return (
		_stats != null
		and _stats.projectile_fire_mode == BuildingLevelStats.ProjectileFireMode.FACING_ONLY
	)


func get_projectile_direction_count() -> int:
	return _stats.projectile_direction_count if _stats != null else 1


func get_projectile_penetration_count() -> int:
	return _stats.projectile_penetration_count if _stats != null else 0


## Returns the horizontal launch directions used by a facing-based projectile
## or laser attack at the current level. Target-tracking towers expose their
## logical facing so read-only placement/rotation previews do not need a fake
## target.
func get_projectile_launch_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = []
	if definition == null or _stats == null or definition.is_defensive_structure():
		return directions
	var direction_count := 1
	if definition.kind == BuildingDefinition.Kind.MACE_TOWER:
		direction_count = clampi(_stats.projectile_direction_count, 1, 8)
	var base_direction := get_facing_direction()
	var base_angle := atan2(base_direction.z, base_direction.x)
	for index in range(direction_count):
		var direction_angle := base_angle + TAU * float(index) / float(direction_count)
		directions.append(Vector3(cos(direction_angle), 0.0, sin(direction_angle)).normalized())
	return directions

func get_instant_damage() -> float:
	return DamageCalculator.compute(_stats.base_damage, _stats.level_factor, _stats.extra_factor)

func get_laser_damage_per_second() -> float:
	return DamageCalculator.compute(_stats.laser_dps, _stats.level_factor, _stats.extra_factor)


func get_laser_beam_color() -> Color:
	return _stats.laser_beam_color if _stats != null else Color(0.88, 0.96, 1.0, 0.96)


func get_laser_beam_width_world() -> float:
	return _stats.laser_beam_width * _grid.cell_size if _stats != null and _grid != null else 0.08


func get_laser_beam_emission_energy() -> float:
	return _stats.laser_beam_emission_energy if _stats != null else 0.0


func get_laser_propagation_speed_world() -> float:
	return _stats.laser_propagation_speed * _grid.cell_size if _stats != null and _grid != null else 1.0


func get_laser_slow_multiplier() -> float:
	return _stats.laser_slow_multiplier if _stats != null else 1.0


func get_laser_slow_duration() -> float:
	return _stats.laser_slow_duration if _stats != null else 0.0


func get_laser_burst_interval() -> float:
	return _stats.laser_burst_interval if _stats != null else 0.0


func get_laser_burst_radius_world() -> float:
	return _stats.laser_burst_radius * _grid.cell_size if _stats != null and _grid != null else 0.0


func get_laser_burst_radius_cells() -> float:
	return _stats.laser_burst_radius if _stats != null else 0.0


func get_laser_burst_damage() -> float:
	return get_instant_damage()


func get_laser_freeze_duration() -> float:
	return _stats.laser_freeze_duration if _stats != null else 0.0

func get_combat_manager() -> CombatManager:
	return _combat_manager


func get_grid_cell_size() -> float:
	return _grid.cell_size if _grid != null else 1.0


func advance_ice_copy_mirror_clock(delta: float, interval: float) -> int:
	var resolved_interval := maxf(0.0, interval)
	if resolved_interval <= 0.0:
		return 0
	_ice_copy_mirror_elapsed += maxf(0.0, delta)
	var event_count := 0
	while _ice_copy_mirror_elapsed >= resolved_interval:
		_ice_copy_mirror_elapsed -= resolved_interval
		_ice_copy_mirror_event_sequence += 1
		event_count += 1
	return event_count


func get_ice_copy_mirror_state() -> Dictionary:
	return {
		"elapsed": _ice_copy_mirror_elapsed,
		"event_sequence": _ice_copy_mirror_event_sequence,
	}

func get_copy_kind() -> StringName:
	if definition == null or is_edge_placement():
		return &""
	if definition.kind == BuildingDefinition.Kind.BARRIER:
		return &"barrier"
	if definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		return &"laser_tower"
	if definition.kind == BuildingDefinition.Kind.ARROW_TOWER:
		return &"arrow_tower"
	if definition.kind == BuildingDefinition.Kind.CROSSBOW_TOWER:
		return &"crossbow_tower"
	if definition.kind == BuildingDefinition.Kind.MACE_TOWER:
		return &"mace_tower"
	if definition.kind == BuildingDefinition.Kind.PULSE_LASER_TOWER:
		return &"pulse_laser_tower"
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
	if definition != null:
		if definition.kind == BuildingDefinition.Kind.LASER_TOWER:
			return get_laser_beam_width_world()
		if definition.kind == BuildingDefinition.Kind.PULSE_LASER_TOWER:
			return get_pulse_laser_width_world()
	return _stats.projectile_width * _grid.cell_size if _stats != null and _grid != null else 0.05

func get_attack_color() -> Color:
	return _stats.attack_color if _stats != null else Color.WHITE

func get_projectile_model_asset() -> ModelAssetDefinition:
	return _stats.projectile_model_asset if _stats != null else null


func uses_missile_projectiles() -> bool:
	return _stats != null and _stats.projectile_is_missile


func get_missile_configuration() -> Dictionary:
	if _stats == null:
		return {}
	var cell_size := _grid.cell_size if _grid != null else 1.0
	return {
		"cell_size": cell_size,
		"explosion_radius": _stats.missile_explosion_radius * cell_size,
		"orbit_duration": _stats.missile_orbit_duration,
		"orbit_radius_x": _stats.missile_orbit_radius_x * cell_size,
		"orbit_radius_z": _stats.missile_orbit_radius_z * cell_size,
		"orbit_vertical_amplitude": _stats.missile_orbit_vertical_amplitude * cell_size,
		"homing_turn_speed_degrees": _stats.missile_homing_turn_speed_degrees,
		"speed_variation_ratio": _stats.missile_speed_variation_ratio,
		"speed_variation_frequency": _stats.missile_speed_variation_frequency,
		"visual_wobble": _stats.missile_visual_wobble * cell_size,
		"visual_roll_degrees": _stats.missile_visual_roll_degrees,
		"trail_lifetime": _stats.missile_trail_lifetime,
		"trail_width": _stats.missile_trail_width * cell_size,
		"target_marker_size": _stats.missile_target_marker_size * cell_size,
		"explosion_duration": _stats.missile_explosion_duration,
	}


func notify_copy_attack(attack_kind: StringName, world_start: Vector3, world_end: Vector3, damage: float) -> void:
	copy_attack_triggered.emit(self, attack_kind, world_start, world_end, maxf(0.0, damage))


func get_pulse_laser_width_world() -> float:
	return _stats.pulse_laser_width * _grid.cell_size if _stats != null and _grid != null else 0.1


func get_pulse_laser_emission_energy() -> float:
	return _stats.pulse_laser_emission_energy if _stats != null else 0.0


func get_pulse_laser_fade_in_time() -> float:
	return _stats.pulse_laser_fade_in_time if _stats != null else 0.0


func get_pulse_laser_hold_time() -> float:
	return _stats.pulse_laser_hold_time if _stats != null else 0.0


func get_pulse_laser_fade_out_time() -> float:
	return _stats.pulse_laser_fade_out_time if _stats != null else 0.0


func get_pulse_laser_reflection_colors() -> Array[Color]:
	return definition.pulse_laser_reflection_colors.duplicate() if definition != null else []


func get_pulse_laser_reflect_max() -> int:
	return _stats.pulse_laser_reflect_max if _stats != null else 0


## Registers one successful source pulse for all L2-copy projections sharing
## this entity. Pending/overdrive pulses never charge the next cycle.
func register_pulse_copy_mirror_charge(
	charge_shots: int,
	pulse_visual_duration: float,
	overdrive_duration: float
) -> Dictionary:
	if definition == null or definition.kind != BuildingDefinition.Kind.PULSE_LASER_TOWER:
		return get_pulse_copy_mirror_state()
	if StringName(_pulse_copy_mirror_state.get("phase", &"charging")) != &"charging":
		return get_pulse_copy_mirror_state()
	var required := maxi(1, charge_shots)
	_pulse_copy_mirror_state["charge_shots"] = required
	_pulse_copy_mirror_state["overdrive_duration"] = maxf(0.0, overdrive_duration)
	var count := mini(required, int(_pulse_copy_mirror_state.get("charge_count", 0)) + 1)
	_pulse_copy_mirror_state["charge_count"] = count
	if count >= required:
		_pulse_copy_mirror_state["phase"] = &"pending"
		_pulse_copy_mirror_state["pending_remaining"] = maxf(
			0.000001,
			pulse_visual_duration
		)
	return get_pulse_copy_mirror_state()


func get_pulse_copy_mirror_state() -> Dictionary:
	return _pulse_copy_mirror_state.duplicate(true)


func _tick_pulse_copy_mirror_state(delta: float) -> void:
	var remaining_delta := maxf(0.0, delta)
	var phase := StringName(_pulse_copy_mirror_state.get("phase", &"charging"))
	if phase == &"pending":
		var pending := maxf(0.0, float(_pulse_copy_mirror_state.get("pending_remaining", 0.0)))
		var pending_step := minf(pending, remaining_delta)
		pending -= pending_step
		remaining_delta -= pending_step
		_pulse_copy_mirror_state["pending_remaining"] = pending
		if pending <= 0.000001:
			phase = &"overdrive"
			_pulse_copy_mirror_state["phase"] = phase
			_pulse_copy_mirror_state["charge_count"] = 0
			_pulse_copy_mirror_state["overdrive_remaining"] = maxf(
				0.0,
				float(_pulse_copy_mirror_state.get("overdrive_duration", 10.0))
			)
			_pulse_copy_mirror_state["generation"] = (
				int(_pulse_copy_mirror_state.get("generation", 0)) + 1
			)
	if phase == &"overdrive" and remaining_delta > 0.0:
		var overdrive := maxf(0.0, float(_pulse_copy_mirror_state.get("overdrive_remaining", 0.0)))
		overdrive = maxf(0.0, overdrive - remaining_delta)
		_pulse_copy_mirror_state["overdrive_remaining"] = overdrive
		if overdrive <= 0.000001:
			_pulse_copy_mirror_state["phase"] = &"charging"
			_pulse_copy_mirror_state["charge_count"] = 0


func launch_pulse_laser() -> PulseLaserBeam:
	if _combat_manager == null or _stats == null or definition == null:
		return null
	var start := get_attack_origin()
	var direction := get_facing_direction()
	var damage := get_instant_damage()
	var beam := _combat_manager.spawn_pulse_laser(
		start,
		direction,
		damage,
		get_attack_range_world(),
		get_pulse_laser_width_world(),
		get_pulse_laser_emission_energy(),
		get_pulse_laser_fade_in_time(),
		get_pulse_laser_hold_time(),
		get_pulse_laser_fade_out_time(),
		get_pulse_laser_reflection_colors(),
		get_pulse_laser_reflect_max(),
		self
	)
	if beam != null:
		beam.impacted.connect(_on_pulse_laser_impacted)
		notify_copy_attack(
			&"pulse_laser",
			start,
			start + direction * get_attack_range_world(),
			damage
		)
	return beam

func launch_projectile(target: CombatTarget, damage: float) -> Projectile:
	if _combat_manager == null or _stats == null:
		return null
	var projectile: Projectile
	if uses_missile_projectiles():
		projectile = _combat_manager.spawn_targeted_missile(
			get_attack_origin(),
			target,
			_stats.projectile_speed * _grid.cell_size,
			damage,
			get_attack_range_world(),
			_stats.projectile_length * _grid.cell_size,
			_stats.projectile_width * _grid.cell_size,
			_stats.attack_color,
			_stats.projectile_model_asset,
			self,
			get_missile_configuration()
		)
	else:
		projectile = _combat_manager.spawn_projectile(
			get_attack_origin(),
			target,
			_stats.projectile_speed * _grid.cell_size,
			damage,
			get_attack_range_world(),
			_stats.projectile_length * _grid.cell_size,
			_stats.projectile_width * _grid.cell_size,
			_stats.attack_color,
			_stats.projectile_model_asset,
			self,
			_stats.projectile_penetration_count
		)
	if projectile != null:
		projectile.impacted.connect(_on_projectile_impacted)
		notify_copy_attack(
			&"missile" if uses_missile_projectiles() else &"projectile",
			get_attack_origin(),
			target.get_target_position(),
			damage
		)
	return projectile


func launch_directional_projectile(damage: float, direction_override: Vector3 = Vector3.ZERO) -> Projectile:
	if _combat_manager == null or _stats == null or _grid == null:
		return null
	var start := get_attack_origin()
	var direction := direction_override if direction_override.length_squared() > 0.000001 else get_facing_direction()
	var projectile: Projectile
	if uses_missile_projectiles():
		projectile = _combat_manager.spawn_directional_missile(
			start,
			direction,
			_stats.projectile_speed * _grid.cell_size,
			damage,
			get_attack_range_world(),
			_stats.projectile_length * _grid.cell_size,
			_stats.projectile_width * _grid.cell_size,
			_stats.attack_color,
			_stats.projectile_model_asset,
			self,
			get_missile_configuration()
		)
	else:
		projectile = _combat_manager.spawn_directional_projectile(
			start,
			direction,
			_stats.projectile_speed * _grid.cell_size,
			damage,
			get_attack_range_world(),
			_stats.projectile_length * _grid.cell_size,
			_stats.projectile_width * _grid.cell_size,
			_stats.attack_color,
			_stats.projectile_model_asset,
			self,
			_stats.projectile_penetration_count
		)
	if projectile != null:
		projectile.impacted.connect(_on_projectile_impacted)
		notify_copy_attack(
			&"directional_missile" if uses_missile_projectiles() else &"directional_projectile",
			start,
			start + direction * get_attack_range_world(),
			damage
		)
	return projectile


func launch_multi_direction_projectiles(damage: float) -> Array[Projectile]:
	var projectiles: Array[Projectile] = []
	if _stats == null:
		return projectiles
	for direction in get_projectile_launch_directions():
		var projectile := launch_directional_projectile(damage, direction)
		if projectile != null:
			projectiles.append(projectile)
	return projectiles


## Presentation-facing occupancy contract. Multi-cell placement can extend this
## list later without changing the selection visualizer API.
func get_occupied_cells() -> Array[Vector3i]:
	var occupied: Array[Vector3i] = []
	if not is_edge_placement():
		occupied.append(cell)
	return occupied

func show_attack_line(world_end: Vector3, _persistent: bool) -> void:
	show_attack_path([{"start": get_attack_origin(), "end": world_end}], world_end)


func show_attack_path(segments: Array, world_endpoint: Vector3) -> void:
	if _continuous_laser_visual == null:
		return
	_continuous_laser_visual.show_path(segments, world_endpoint)

func clear_attack_visual() -> void:
	if _continuous_laser_visual != null:
		_continuous_laser_visual.clear_path()

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

## Copies the source model's live child-node pose into an existing behaviorless
## snapshot. The snapshot root transform is applied separately by the mirror so
## the full pose can receive the exact composed reflection matrix.
func sync_copy_visual_snapshot(snapshot: Node3D) -> bool:
	if snapshot == null or not is_instance_valid(snapshot):
		return false
	if _visual_root == null or not is_instance_valid(_visual_root):
		return false
	snapshot.visible = _visual_root.visible
	_sync_copy_visual_children(_visual_root, snapshot)
	return true

func notify_attack(target: CombatTarget, damage: float, continuous: bool) -> void:
	if damage > 0.0:
		attack_performed.emit(self, target, damage, continuous)

func shutdown() -> void:
	feature_enabled = false
	_locked_target = null
	_pulse_copy_mirror_state["phase"] = &"charging"
	_pulse_copy_mirror_state["charge_count"] = 0
	_pulse_copy_mirror_state["pending_remaining"] = 0.0
	_pulse_copy_mirror_state["overdrive_remaining"] = 0.0
	_ice_copy_mirror_elapsed = 0.0
	_ice_copy_mirror_event_sequence = 0
	if _attack_strategy != null:
		_attack_strategy.reset(self)

func _configure_attack_strategy() -> void:
	if _preview_mode:
		_attack_strategy = null
	elif definition.is_defensive_structure():
		_attack_strategy = null
	elif definition.kind == BuildingDefinition.Kind.LASER_TOWER:
		_attack_strategy = LaserAttackStrategyScript.new()
	elif definition.kind == BuildingDefinition.Kind.PULSE_LASER_TOWER:
		_attack_strategy = PulseLaserAttackStrategyScript.new()
	elif definition.kind == BuildingDefinition.Kind.MACE_TOWER:
		_attack_strategy = MaceAttackStrategyScript.new()
	else:
		_attack_strategy = ArrowAttackStrategyScript.new()

func _build_visual() -> void:
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
	_continuous_laser_visual = null
	_durability_label = null
	_visual_root = Node3D.new()
	add_child(_visual_root)
	var model_asset: ModelAssetDefinition = _stats.get_model_asset()
	var custom_visual: Node3D = model_asset.instantiate_grounded_model(&"BuildingModel") if model_asset != null else null
	if custom_visual != null:
		_visual_root.add_child(custom_visual)
		if _preview_mode:
			_apply_preview_materials(custom_visual)
	else:
		_build_default_body()
	if is_edge_path_blocker():
		_build_direction_marker()
		if is_bidirectional_edge_blocker():
			_build_direction_marker(true)
	elif not is_path_blocker():
		_build_attack_line()
	set_selected(_selected)

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
	if definition == null or definition.kind != BuildingDefinition.Kind.LASER_TOWER:
		return
	_continuous_laser_visual = ContinuousLaserVisualScript.new()
	_continuous_laser_visual.name = &"ContinuousLaserVisual"
	_visual_root.add_child(_continuous_laser_visual)
	_continuous_laser_visual.configure(
		get_laser_beam_color(),
		get_laser_beam_width_world(),
		get_laser_beam_emission_energy()
	)

func _apply_preview_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		mesh_instance.material_override = _make_material(_stats.tower_color, false)
	for child in node.get_children():
		_apply_preview_materials(child)


func _refresh_preview_materials(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.material_override as StandardMaterial3D
		if material != null and material.has_meta(&"preview_source_color"):
			_apply_preview_material_state(
				material,
				material.get_meta(&"preview_source_color", Color.WHITE),
				bool(material.get_meta(&"preview_emissive", false))
			)
	for child in node.get_children():
		_refresh_preview_materials(child)
func _sanitize_copy_visual_snapshot(node: Node) -> void:
	for child in node.get_children():
		if (
			child.name == &"ContinuousLaserVisual"
			or child is Label3D
			or child is Control
			or child is AnimationPlayer
			or child is AudioStreamPlayer3D
		):
			child.free()
		else:
			_sanitize_copy_visual_snapshot(child)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null:
		node.set_script(null)

func _sync_copy_visual_children(source: Node3D, snapshot: Node3D) -> void:
	for raw_child in source.get_children():
		if not raw_child is Node3D:
			continue
		var source_child := raw_child as Node3D
		var snapshot_child := snapshot.get_node_or_null(NodePath(str(source_child.name))) as Node3D
		if snapshot_child == null:
			continue
		snapshot_child.transform = source_child.transform
		snapshot_child.visible = source_child.visible
		if source_child is Skeleton3D and snapshot_child is Skeleton3D:
			_sync_copy_skeleton_pose(source_child as Skeleton3D, snapshot_child as Skeleton3D)
		_sync_copy_visual_children(source_child, snapshot_child)

func _sync_copy_skeleton_pose(source: Skeleton3D, snapshot: Skeleton3D) -> void:
	var bone_count := mini(source.get_bone_count(), snapshot.get_bone_count())
	for bone_index in range(bone_count):
		snapshot.set_bone_pose_position(bone_index, source.get_bone_pose_position(bone_index))
		snapshot.set_bone_pose_rotation(bone_index, source.get_bone_pose_rotation(bone_index))
		snapshot.set_bone_pose_scale(bone_index, source.get_bone_pose_scale(bone_index))

func _get_valid_visual_target() -> CombatTarget:
	if _locked_target == null or not is_instance_valid(_locked_target):
		_locked_target = null
		return null
	if not _locked_target.is_alive():
		_locked_target = null
		return null
	return _locked_target

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
	material.set_meta(&"preview_source_color", color)
	material.set_meta(&"preview_emissive", emissive)
	_apply_preview_material_state(material, color, emissive)
	return material


func _apply_preview_material_state(
	material: StandardMaterial3D,
	color: Color,
	emissive: bool
) -> void:
	var base_color := get_preview_display_color() if _preview_mode else color
	var resolved_color := base_color
	if _preview_mode:
		resolved_color.a = maxf(preview_alpha, base_color.a)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = resolved_color
	material.roughness = 0.65
	material.emission_enabled = false
	if emissive or _preview_mode:
		material.emission_enabled = true
		material.emission = base_color
		material.emission_energy_multiplier = 2.8 if _preview_mode else 2.0

func _on_projectile_impacted(target: CombatTarget, applied_damage: float) -> void:
	notify_attack(target, applied_damage, false)


func _on_pulse_laser_impacted(
	target: CombatTarget,
	applied_damage: float,
	_segment_index: int
) -> void:
	notify_attack(target, applied_damage, false)
