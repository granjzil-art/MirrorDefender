## Physical mirror entry point: shared edge lifecycle and visuals, copy graph,
## projectile reflection, preview, and synchronized attack forwarding.
class_name MirrorManager
extends Node3D

const MirrorProjectionProjectileScript := preload("res://scripts/mirror/MirrorProjectionProjectile.gd")
const MirrorPlacementDataScript := preload("res://scripts/mirror/MirrorPlacementData.gd")
const BallisticGeometryScript := preload("res://scripts/combat/BallisticGeometry.gd")
const LaserAttackStrategyScript := preload("res://scripts/combat/LaserAttackStrategy.gd")
const ContinuousLaserPathScript := preload("res://scripts/combat/ContinuousLaserPath.gd")
const ReflectionDamageScript := preload("res://scripts/combat/ReflectionDamage.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Preview Performance")
@export var reuse_placement_preview_instances: bool = true

@export_group("Placement Availability")
## Disabled by default: mirror placement spends placement_cost with no cooldown.
## Enable to restore the retained independent cooldown/inventory implementation.
@export var placement_cooldown_enabled: bool = false

@export_group("Definition")
@export var copy_mirror_definition: CopyMirrorDefinition
@export var reflect_mirror_definition: ReflectMirrorDefinition

signal mirror_placed(mirror: CopyMirror)
## Runtime/player placement only; authored initial mirrors stay silent in SFX.
signal mirror_constructed(mirror: CopyMirror)
signal mirror_removed(mirror: CopyMirror)
signal mirror_selected(mirror: CopyMirror)
signal mirror_changed(mirror: CopyMirror)
signal mirror_relocated(mirror: CopyMirror, previous_cell: Vector3i, previous_edge_id: String)
signal mirror_upgraded(mirror: CopyMirror, previous_level: int, new_level: int)
signal placement_failed(cell: Vector3i, reason: String)
signal placement_cooldown_changed(
	mirror_kind: MirrorPlacementData.MirrorKind,
	remaining: float,
	duration: float,
	ready_ratio: float
)
signal projections_rebuilt(count: int)
signal building_preview_projections_rebuilt(count: int)
signal attack_mirrored(projection: MirrorProjection, attack_kind: StringName)
signal preview_updated(info: Dictionary)
signal preview_cleared

var _grid: GridManager
var _tile_manager: TileManager
var _stuff_manager: Node
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _building_manager: BuildingManager
var _edge_occupancy_registry: EdgeOccupancyRegistry
var _tile_visual_snapshot_resolver: Callable
var _path_connectivity_validator: Callable
var _reflection_camera: Camera3D
var _reflection_cursor: int = 0
var _projectile_reflection_providers: Dictionary = {}
var _cooldown_time_scale_resolver: Callable
var _copy_available_placements: int = 1
var _reflect_available_placements: int = 1
var _copy_placement_cooldown_remaining: float = 0.0
var _reflect_placement_cooldown_remaining: float = 0.0

var _mirrors: Dictionary = {}
var _projections: Array[MirrorProjection] = []
var _projections_by_cell: Dictionary = {}
var _selected_mirror: CopyMirror
var _next_placement_order: int = 0
var _rebuild_queued: bool = false
var _mirror_exit_callbacks: Dictionary = {}
var _attack_sources: Dictionary = {}
var _laser_projection_states: Dictionary = {}
var _pulse_projection_states: Dictionary = {}

var _preview_mirror: CopyMirror
var _preview_projections: Array[MirrorProjection] = []
var _building_preview_projections: Array[MirrorProjection] = []
var _preview_info: Dictionary = {}
var _preview_active_from_side: bool = true
var _preview_kind: MirrorPlacementData.MirrorKind = MirrorPlacementData.MirrorKind.COPY
var _preview_relocation_source: CopyMirror
var _preview_placement_failure: String = ""

func _process(delta: float) -> void:
	advance_placement_cooldowns(delta)
	_update_pulse_copy_specials(delta)
	_update_reflection_views()

func _exit_tree() -> void:
	_disconnect_dependencies()

func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	resource_manager: ResourceManager,
	combat_manager: CombatManager,
	building_manager: BuildingManager,
	edge_occupancy_registry: EdgeOccupancyRegistry
) -> void:
	_disconnect_dependencies()
	_grid = grid_manager
	_tile_manager = tile_manager
	_resource_manager = resource_manager
	_combat_manager = combat_manager
	_building_manager = building_manager
	_edge_occupancy_registry = edge_occupancy_registry
	_connect_definition_signals()
	_sync_attack_effect_runtime_limits()
	if _combat_manager != null:
		_combat_manager.set_projectile_reflection_resolver(Callable(self, "trace_projectile_reflection"))
		_combat_manager.set_projectile_blocker_resolver(Callable(self, "trace_ballistic_blocker"))
	if _building_manager != null:
		_building_manager.building_placed.connect(_on_building_placed)
		_building_manager.building_removed.connect(_on_building_removed)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		_building_manager.building_relocated.connect(_on_building_relocated)
		_building_manager.preview_updated.connect(_on_building_preview_updated)
		_building_manager.preview_cleared.connect(_on_building_preview_cleared)
		for building in _building_manager.get_buildings():
			_connect_attack_source(building)
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)
		_tile_manager.tile_changed.connect(_on_tile_changed)
		_tile_manager.obstacle_destroyed.connect(_on_obstacle_destroyed)
	queue_rebuild()


func set_runtime_definitions(
	copy_definition: CopyMirrorDefinition,
	reflect_definition: ReflectMirrorDefinition
) -> void:
	_disconnect_definition_signals()
	copy_mirror_definition = copy_definition
	reflect_mirror_definition = reflect_definition
	_connect_definition_signals()
	_sync_attack_effect_runtime_limits()
	for mirror in get_mirrors():
		mirror.rebind_definition(_get_definition(_get_mirror_kind(mirror)))
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		_preview_mirror.rebind_definition(_get_definition(_preview_kind))
	_on_definition_changed()


func _connect_definition_signals() -> void:
	if copy_mirror_definition != null and not copy_mirror_definition.changed.is_connected(_on_definition_changed):
		copy_mirror_definition.changed.connect(_on_definition_changed)
	if reflect_mirror_definition != null and not reflect_mirror_definition.changed.is_connected(_on_definition_changed):
		reflect_mirror_definition.changed.connect(_on_definition_changed)


func _disconnect_definition_signals() -> void:
	if copy_mirror_definition != null and copy_mirror_definition.changed.is_connected(_on_definition_changed):
		copy_mirror_definition.changed.disconnect(_on_definition_changed)
	if reflect_mirror_definition != null and reflect_mirror_definition.changed.is_connected(_on_definition_changed):
		reflect_mirror_definition.changed.disconnect(_on_definition_changed)


func _sync_attack_effect_runtime_limits() -> void:
	AttackEffectPayload.configure_runtime_limits(
		reflect_mirror_definition.maximum_total_reflections
			if reflect_mirror_definition != null
			else AttackEffectPayload.MAX_TOTAL_REFLECTIONS,
		reflect_mirror_definition.reflection_branch_budget
			if reflect_mirror_definition != null
			else AttackEffectPayload.DEFAULT_REFLECTION_BRANCH_BUDGET,
		copy_mirror_definition.impact_spawn_budget
			if copy_mirror_definition != null
			else AttackEffectPayload.DEFAULT_IMPACT_SPAWN_BUDGET
	)

func set_tile_visual_snapshot_resolver(resolver: Callable) -> void:
	_tile_visual_snapshot_resolver = resolver
	queue_rebuild()


func set_stuff_manager(value: Node) -> void:
	_disconnect_stuff_manager()
	_stuff_manager = value
	if _stuff_manager != null:
		if _stuff_manager.has_signal(&"stuff_loaded"):
			_stuff_manager.connect(&"stuff_loaded", _on_stuff_loaded)
		if _stuff_manager.has_signal(&"stuff_changed"):
			_stuff_manager.connect(&"stuff_changed", _on_stuff_changed)
	queue_rebuild()


## Adds a non-mirror finite-surface query without coupling Combat to its module.
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
	return


func get_projectile_reflection_provider_count() -> int:
	_purge_projectile_reflection_providers()
	return _projectile_reflection_providers.size()

func set_reflection_camera(camera: Camera3D) -> void:
	_reflection_camera = camera
	for mirror in get_mirrors():
		mirror.set_reflection_camera(camera)
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		_preview_mirror.set_reflection_camera(camera)


func set_path_connectivity_validator(value: Callable) -> void:
	_path_connectivity_validator = value


## Injects the battle/preparation phase scale without coupling this module to WaveManager.
func set_cooldown_time_scale_resolver(value: Callable) -> void:
	_cooldown_time_scale_resolver = value


func set_placement_cooldown_enabled(value: bool) -> void:
	if placement_cooldown_enabled == value:
		return
	placement_cooldown_enabled = value
	reset_placement_cooldowns()


func uses_placement_cooldown() -> bool:
	return placement_cooldown_enabled


## Resets both independently configured mirror kinds to one available placement
## and starts the next accumulation cycle.
func reset_placement_cooldowns() -> void:
	_copy_available_placements = 1
	_reflect_available_placements = 1
	_copy_placement_cooldown_remaining = get_placement_cooldown_duration(
		MirrorPlacementData.MirrorKind.COPY
	)
	_reflect_placement_cooldown_remaining = get_placement_cooldown_duration(
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
	)
	_emit_placement_cooldown_changed(MirrorPlacementData.MirrorKind.COPY)
	_emit_placement_cooldown_changed(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT)


## Advances cooldowns using already game-scaled delta and the injected wave-phase multiplier.
func advance_placement_cooldowns(delta: float) -> void:
	if not placement_cooldown_enabled or not is_finite(delta) or delta <= 0.0:
		return
	var phase_scale := 1.0
	if _cooldown_time_scale_resolver.is_valid():
		var resolved_scale: Variant = _cooldown_time_scale_resolver.call()
		if not (resolved_scale is float or resolved_scale is int):
			return
		phase_scale = float(resolved_scale)
	if not is_finite(phase_scale) or phase_scale <= 0.0:
		return
	var scaled_delta := delta * phase_scale
	if not is_finite(scaled_delta):
		return
	_advance_placement_cooldown(MirrorPlacementData.MirrorKind.COPY, scaled_delta)
	_advance_placement_cooldown(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT, scaled_delta)


func is_mirror_kind_ready(mirror_kind: MirrorPlacementData.MirrorKind) -> bool:
	if not placement_cooldown_enabled:
		return true
	return (
		get_placement_cooldown_duration(mirror_kind) <= 0.000001
		or get_available_mirror_count(mirror_kind) > 0
	)


func get_available_mirror_count(
	mirror_kind: MirrorPlacementData.MirrorKind
) -> int:
	if not placement_cooldown_enabled:
		return 1
	if get_placement_cooldown_duration(mirror_kind) <= 0.000001:
		return 1
	if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
		return maxi(0, _reflect_available_placements)
	return maxi(0, _copy_available_placements)


func get_placement_cooldown_remaining(
	mirror_kind: MirrorPlacementData.MirrorKind
) -> float:
	if not placement_cooldown_enabled:
		return 0.0
	if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
		return maxf(0.0, _reflect_placement_cooldown_remaining)
	return maxf(0.0, _copy_placement_cooldown_remaining)


func get_placement_cooldown_duration(
	mirror_kind: MirrorPlacementData.MirrorKind
) -> float:
	if not placement_cooldown_enabled:
		return 0.0
	var definition := _get_definition(mirror_kind)
	if definition == null or not is_finite(definition.placement_cooldown_seconds):
		return 0.0
	return maxf(0.0, definition.placement_cooldown_seconds)


func get_placement_cooldown_ready_ratio(
	mirror_kind: MirrorPlacementData.MirrorKind
) -> float:
	if is_mirror_kind_ready(mirror_kind):
		return 1.0
	var duration := get_placement_cooldown_duration(mirror_kind)
	if duration <= 0.000001:
		return 1.0
	return clampf(1.0 - get_placement_cooldown_remaining(mirror_kind) / duration, 0.0, 1.0)


func _advance_placement_cooldown(
	mirror_kind: MirrorPlacementData.MirrorKind,
	delta: float
) -> void:
	var duration := get_placement_cooldown_duration(mirror_kind)
	if duration <= 0.000001:
		return
	var previous := get_placement_cooldown_remaining(mirror_kind)
	if previous <= 0.000001:
		previous = duration
	if delta < previous:
		_set_placement_cooldown_remaining(mirror_kind, previous - delta)
		if get_available_mirror_count(mirror_kind) == 0:
			_emit_placement_cooldown_changed(mirror_kind)
		return
	var elapsed_after_first := delta - previous
	var completed_cycles := 1 + floori(elapsed_after_first / duration)
	_set_available_mirror_count(
		mirror_kind,
		get_available_mirror_count(mirror_kind) + completed_cycles
	)
	var elapsed_in_current_cycle := fmod(elapsed_after_first, duration)
	_set_placement_cooldown_remaining(mirror_kind, duration - elapsed_in_current_cycle)
	_emit_placement_cooldown_changed(mirror_kind)


func _consume_available_mirror(mirror_kind: MirrorPlacementData.MirrorKind) -> bool:
	if not placement_cooldown_enabled:
		return true
	if get_placement_cooldown_duration(mirror_kind) <= 0.000001:
		return true
	var available := get_available_mirror_count(mirror_kind)
	if available <= 0:
		return false
	_set_available_mirror_count(mirror_kind, available - 1)
	_emit_placement_cooldown_changed(mirror_kind)
	return true


func _grant_available_mirror(mirror_kind: MirrorPlacementData.MirrorKind) -> void:
	if not placement_cooldown_enabled:
		return
	if get_placement_cooldown_duration(mirror_kind) > 0.000001:
		_set_available_mirror_count(
			mirror_kind,
			get_available_mirror_count(mirror_kind) + 1
		)
	_emit_placement_cooldown_changed(mirror_kind)


func _set_available_mirror_count(
	mirror_kind: MirrorPlacementData.MirrorKind,
	value: int
) -> void:
	var resolved := maxi(0, value)
	if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
		_reflect_available_placements = resolved
	else:
		_copy_available_placements = resolved


func _set_placement_cooldown_remaining(
	mirror_kind: MirrorPlacementData.MirrorKind,
	value: float
) -> void:
	var resolved := maxf(0.0, value) if is_finite(value) else 0.0
	if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
		_reflect_placement_cooldown_remaining = resolved
	else:
		_copy_placement_cooldown_remaining = resolved


func _emit_placement_cooldown_changed(
	mirror_kind: MirrorPlacementData.MirrorKind
) -> void:
	placement_cooldown_changed.emit(
		mirror_kind,
		get_placement_cooldown_remaining(mirror_kind),
		get_placement_cooldown_duration(mirror_kind),
		get_placement_cooldown_ready_ratio(mirror_kind)
	)

func place_copy_mirror(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant = null
) -> CopyMirror:
	return _place_mirror(
		from_cell,
		edge_index,
		active_from_side,
		MirrorPlacementData.MirrorKind.COPY,
		true,
		true,
		true,
		true
	)


func place_reflect_mirror(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant = null
) -> ReflectMirror:
	return _place_mirror(
		from_cell,
		edge_index,
		active_from_side,
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
		true,
		false,
		true,
		true
	) as ReflectMirror


## Captures real mirrors in copy-graph placement order; projections are excluded.
func export_initial_placements() -> Array[MirrorPlacementData]:
	var placements: Array[MirrorPlacementData] = []
	for mirror in get_mirrors():
		var placement := MirrorPlacementDataScript.new()
		placement.configure(
			mirror.from_cell,
			mirror.edge_index,
			mirror.active_from_side,
			_get_mirror_kind(mirror),
			mirror.level
		)
		placements.append(placement)
	return placements


## Keeps mirror placement order/state while re-sampling edited terrain.
func refresh_world_transforms() -> void:
	for mirror in get_mirrors():
		mirror.refresh_world_transform()
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		_preview_mirror.refresh_world_transform()
	rebuild_now()


## Rebuilds authored initial mirrors without charging initial_resource.
## Array order is the authoritative recursive-copy order.
func load_initial_placements(placements: Array) -> Array[String]:
	reset_placement_cooldowns()
	clear_mirrors(false)
	var errors: Array[String] = []
	for index in range(placements.size()):
		var raw_placement: Variant = placements[index]
		if not raw_placement is MirrorPlacementDataScript:
			errors.append("初始镜子 %d 数据类型无效" % (index + 1))
			continue
		var placement: MirrorPlacementData = raw_placement
		var placement_errors := placement.validate_configuration()
		if not placement_errors.is_empty():
			errors.append("初始镜子 %d 配置无效：%s" % [index + 1, "；".join(placement_errors)])
			continue
		var mirror := _place_mirror(
			placement.from_cell,
			placement.edge_index,
			placement.active_from_side,
			placement.mirror_kind,
			false,
			false,
			false,
			false,
			placement.level
		)
		if mirror == null:
			errors.append("初始镜子 %d 装配失败" % (index + 1))
	if not errors.is_empty():
		clear_mirrors(true)
	else:
		select_mirror(null)
	rebuild_now()
	return errors


func _place_mirror(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant,
	mirror_kind: MirrorPlacementData.MirrorKind,
	runtime_placement: bool,
	check_connectivity: bool,
	select_after_placement: bool,
	rebuild_after_placement: bool,
	initial_level: int = 1
) -> CopyMirror:
	var validation := validate_placement(from_cell, edge_index, runtime_placement, mirror_kind)
	if not validation.failure.is_empty():
		placement_failed.emit(from_cell, validation.failure)
		return null
	var definition := _get_definition(mirror_kind)
	var placement_cost := (
		0.0
		if not runtime_placement or placement_cooldown_enabled
		else maxf(0.0, definition.placement_cost)
	)
	var resolved_side := definition.active_from_side_by_default if active_from_side == null else bool(active_from_side)
	var mirror: CopyMirror = ReflectMirror.new() if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT else CopyMirror.new()
	add_child(mirror)
	mirror.configure(
		definition,
		from_cell,
		validation.to_cell,
		edge_index,
		validation.edge_id,
		_grid,
		_tile_manager,
		resolved_side
	)
	if not mirror.set_level(initial_level):
		mirror.queue_free()
		placement_failed.emit(from_cell, "镜子初始等级无效")
		return null
	mirror.placement_order = _next_placement_order
	mirror.set_reflection_camera(_reflection_camera)
	var connectivity_failure := (
		_validate_path_connectivity({"candidate_mirror": mirror})
		if check_connectivity and mirror.is_copy_mirror()
		else ""
	)
	if not connectivity_failure.is_empty():
		mirror.queue_free()
		placement_failed.emit(from_cell, connectivity_failure)
		return null
	var registered := (
		_resource_manager.try_register_mirror(
			mirror_kind,
			placement_cost,
			"reflect_mirror_cost" if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT else "copy_mirror_cost"
		)
		if runtime_placement
		else _resource_manager.try_register_initial_mirror(mirror_kind)
	)
	if not registered:
		mirror.queue_free()
		placement_failed.emit(
			from_cell,
			"%s放置条件不满足" % definition.display_name
			if runtime_placement
			else "初始%s超过独立上限" % definition.display_name
		)
		return null
	if _edge_occupancy_registry != null and not _edge_occupancy_registry.try_register(validation.edge_id, mirror):
		_resource_manager.unregister_mirror(mirror_kind, placement_cost)
		mirror.queue_free()
		placement_failed.emit(from_cell, "该物理边已被占用")
		return null
	var refundable_value := (
		definition.get_cumulative_cost(initial_level)
		if not runtime_placement
		else placement_cost
	)
	if refundable_value > 0.0:
		mirror._record_investment(refundable_value)
	_next_placement_order += 1
	mirror.side_changed.connect(_on_mirror_side_changed)
	var exit_callback := _on_mirror_tree_exited.bind(mirror)
	mirror.tree_exited.connect(exit_callback)
	_mirror_exit_callbacks[mirror] = exit_callback
	_mirrors[validation.edge_id] = mirror
	if runtime_placement:
		_consume_available_mirror(mirror_kind)
	if select_after_placement:
		select_mirror(mirror)
	if rebuild_after_placement:
		rebuild_now()
	mirror_placed.emit(mirror)
	if runtime_placement:
		mirror_constructed.emit(mirror)
	return mirror

func validate_placement(
	from_cell: Vector3i,
	edge_index: int,
	check_runtime_availability: bool = true,
	mirror_kind: MirrorPlacementData.MirrorKind = MirrorPlacementData.MirrorKind.COPY,
	ignored_edge_occupant: Node = null
) -> Dictionary:
	var result := {"failure": "", "to_cell": Vector3i.ZERO, "edge_id": ""}
	var definition := _get_definition(mirror_kind)
	if not feature_enabled or definition == null:
		result.failure = "镜子系统或对应配置未启用"
		return result
	var config_errors := definition.validate_configuration()
	if not config_errors.is_empty():
		result.failure = config_errors[0]
		return result
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		result.failure = "镜子系统依赖尚未注入"
		return result
	if not _grid.is_in_bounds(from_cell) or edge_index < 0 or edge_index >= _grid.edge_count():
		result.failure = "目标边位于地图外"
		return result
	var to_cell := _grid.neighbor_across_edge(from_cell, edge_index)
	result.to_cell = to_cell
	if not _grid.is_in_bounds(to_cell):
		result.failure = "镜子只能放在两个有效地块之间"
		return result
	if not _tile_manager.allows_edge_building(from_cell, edge_index):
		result.failure = "该物理边不允许放置镜子"
		return result
	var edge_id := _grid.canonical_edge_id(from_cell, edge_index)
	result.edge_id = edge_id
	var edge_occupant := _get_edge_occupant(edge_id)
	if edge_occupant != null and edge_occupant != ignored_edge_occupant:
		result.failure = "该物理边已被占用"
		return result
	if check_runtime_availability:
		if not _resource_manager.can_add_mirror(mirror_kind):
			result.failure = "已达到%s上限" % definition.display_name
		elif placement_cooldown_enabled and not is_mirror_kind_ready(mirror_kind):
			result.failure = "%s冷却中（%.1f 秒）" % [
				definition.display_name,
				get_placement_cooldown_remaining(mirror_kind),
			]
		elif not placement_cooldown_enabled and not _resource_manager.can_afford(definition.placement_cost):
			result.failure = "金币不足，需要 %d" % ceili(definition.placement_cost)
	return result


func update_relocation_preview(
	source: CopyMirror,
	selected_cell: Vector3i,
	edge_index: int
) -> bool:
	if source == null or not is_instance_valid(source) or get_mirror(source.edge_id) != source:
		clear_preview()
		return false
	return _update_mirror_preview(
		selected_cell,
		edge_index,
		_get_mirror_kind(source),
		true,
		source
	)


func is_relocation_preview_valid(source: CopyMirror) -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and _preview_relocation_source == source
		and _preview_mirror != null
		and is_instance_valid(_preview_mirror)
		and bool(_preview_info.get("valid", false))
	)


## Applies the exact currently displayed adjustment ghost without changing
## mirror costs, caps, cooldown stock, upgrades, or instance identity.
func commit_relocation_preview(source: CopyMirror) -> bool:
	if not is_relocation_preview_valid(source):
		return false
	return relocate_mirror(source, _preview_mirror.from_cell, _preview_mirror.edge_index)


## Moves one live mirror without spending/refunding resources or changing the
## cooldown stock. The same object retains upgrades and its investment ledger.
func relocate_mirror(
	source: CopyMirror,
	selected_cell: Vector3i,
	edge_index: int
) -> bool:
	if source == null or not is_instance_valid(source) or get_mirror(source.edge_id) != source:
		return false
	var mirror_kind := _get_mirror_kind(source)
	var validation := validate_placement(
		selected_cell,
		edge_index,
		false,
		mirror_kind,
		source
	)
	var failure: String = validation.failure
	if failure.is_empty() and source.is_copy_mirror():
		var candidate := CopyMirror.new()
		add_child(candidate)
		candidate.configure(
			source.definition,
			selected_cell,
			validation.to_cell,
			edge_index,
			validation.edge_id,
			_grid,
			_tile_manager,
			true,
			true
		)
		candidate.set_level(source.level)
		candidate.placement_order = source.placement_order
		failure = _validate_path_connectivity({
			"candidate_mirror": candidate,
			"removed_mirror": source,
		})
		candidate.free()
	if not failure.is_empty():
		placement_failed.emit(selected_cell, failure)
		return false
	var previous_cell := source.from_cell
	var previous_to_cell := source.to_cell
	var previous_edge_index := source.edge_index
	var previous_edge_id := source.edge_id
	var previous_active_from_side := source.active_from_side
	_mirrors.erase(previous_edge_id)
	if _edge_occupancy_registry != null:
		_edge_occupancy_registry.unregister(previous_edge_id, source)
	if not source.relocate_runtime(
		selected_cell,
		validation.to_cell,
		edge_index,
		validation.edge_id,
		true
	):
		_restore_mirror_relocation(
			source,
			previous_cell,
			previous_to_cell,
			previous_edge_index,
			previous_edge_id,
			previous_active_from_side
		)
		return false
	if (
		_edge_occupancy_registry != null
		and not _edge_occupancy_registry.try_register(validation.edge_id, source)
	):
		_restore_mirror_relocation(
			source,
			previous_cell,
			previous_to_cell,
			previous_edge_index,
			previous_edge_id,
			previous_active_from_side
		)
		return false
	_mirrors[validation.edge_id] = source
	select_mirror(source)
	mirror_relocated.emit(source, previous_cell, previous_edge_id)
	mirror_changed.emit(source)
	rebuild_now()
	return true


func _restore_mirror_relocation(
	source: CopyMirror,
	previous_cell: Vector3i,
	previous_to_cell: Vector3i,
	previous_edge_index: int,
	previous_edge_id: String,
	previous_active_from_side: bool
) -> void:
	source.relocate_runtime(
		previous_cell,
		previous_to_cell,
		previous_edge_index,
		previous_edge_id,
		previous_active_from_side
	)
	if _edge_occupancy_registry != null:
		_edge_occupancy_registry.try_register(previous_edge_id, source)
	_mirrors[previous_edge_id] = source

func remove_selected_mirror() -> bool:
	return remove_mirror(get_selected_mirror())


func upgrade_selected_mirror() -> bool:
	return upgrade_mirror(get_selected_mirror())


func upgrade_mirror(mirror: CopyMirror) -> bool:
	if (
		mirror == null
		or not is_instance_valid(mirror)
		or not _mirrors.has(mirror.edge_id)
		or _mirrors[mirror.edge_id] != mirror
		or not mirror.can_upgrade()
	):
		return false
	var previous_level := mirror.level
	var cost := mirror.get_upgrade_cost()
	if cost > 0.0 and not invest_in_mirror(mirror, cost, "mirror_upgrade_cost"):
		return false
	if not mirror.set_level(previous_level + 1):
		# This branch is unreachable after can_upgrade(), but keep the transaction
		# recoverable if a runtime definition is mutated during the call.
		if cost > 0.0 and _resource_manager != null:
			mirror._rollback_investment(cost)
			_resource_manager.gain(cost, "mirror_upgrade_rollback")
		return false
	rebuild_now()
	mirror_changed.emit(mirror)
	mirror_upgraded.emit(mirror, previous_level, mirror.level)
	return true


## Atomically spends and records later investment so demolition can return the
## exact lifetime total without trusting the mirror definition's current cost.
func invest_in_mirror(
	mirror: CopyMirror,
	amount: float,
	reason: String = "mirror_investment"
) -> bool:
	if (
		mirror == null
		or not is_instance_valid(mirror)
		or not _mirrors.has(mirror.edge_id)
		or _mirrors[mirror.edge_id] != mirror
		or _resource_manager == null
		or not is_finite(amount)
		or amount <= 0.0
	):
		return false
	if not _resource_manager.spend(amount, reason):
		return false
	if mirror._record_investment(amount):
		return true
	_resource_manager.gain(amount, "mirror_investment_rollback")
	return false

func remove_mirror(mirror: CopyMirror) -> bool:
	if mirror == null or not is_instance_valid(mirror) or not _mirrors.has(mirror.edge_id):
		return false
	var mirror_kind := _get_mirror_kind(mirror)
	_mirrors.erase(mirror.edge_id)
	if _edge_occupancy_registry != null:
		_edge_occupancy_registry.unregister(mirror.edge_id, mirror)
	if _resource_manager != null:
		_resource_manager.unregister_mirror(
			mirror_kind,
			mirror.get_refund_amount(),
			"mirror_refund"
		)
	if _selected_mirror == mirror:
		select_mirror(null)
	if mirror.side_changed.is_connected(_on_mirror_side_changed):
		mirror.side_changed.disconnect(_on_mirror_side_changed)
	_disconnect_mirror_exit(mirror)
	_grant_available_mirror(mirror_kind)
	mirror_removed.emit(mirror)
	mirror.queue_free()
	rebuild_now()
	return true

func clear_mirrors(update_resource_count: bool = true) -> void:
	var snapshot := get_mirrors()
	for mirror in snapshot:
		_mirrors.erase(mirror.edge_id)
		if _edge_occupancy_registry != null:
			_edge_occupancy_registry.unregister(mirror.edge_id, mirror)
		if update_resource_count and _resource_manager != null:
			_resource_manager.unregister_mirror(_get_mirror_kind(mirror))
		_disconnect_mirror_exit(mirror)
		mirror.queue_free()
	_mirror_exit_callbacks.clear()
	_next_placement_order = 0
	select_mirror(null)
	clear_preview()
	rebuild_now()

func flip_selected() -> bool:
	var mirror := get_selected_mirror()
	if mirror == null:
		return false
	mirror.flip_side()
	return true


## Rotates a selected live mirror around its currently active tile. Unlike R,
## this changes the occupied edge while keeping the reflective side inward.
func rotate_selected_mirror(step: int = 1) -> bool:
	var mirror := get_selected_mirror()
	if mirror == null or _grid == null or _grid.edge_count() <= 0 or step == 0:
		return false
	var active_cell := mirror.get_active_cell()
	var passive_cell := mirror.to_cell if mirror.active_from_side else mirror.from_cell
	var current_edge := _grid.find_edge_index(active_cell, passive_cell)
	if current_edge < 0:
		return false
	var target_edge := wrapi(current_edge + step, 0, _grid.edge_count())
	return relocate_mirror(mirror, active_cell, target_edge)

func select_at_edge(edge_id: String) -> CopyMirror:
	var occupant := _get_edge_occupant(edge_id)
	var mirror: CopyMirror = occupant if occupant is CopyMirror else null
	select_mirror(mirror)
	return mirror


## Picks the nearest real mirror body under a viewport position. Copy and
## projectile-reflect mirrors share the same two-sided body hit contract.
func pick_mirror(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if camera == null:
		return {"hit": false}
	return pick_mirror_from_ray(
		camera.project_ray_origin(screen_position),
		camera.project_ray_normal(screen_position)
	)


func pick_mirror_from_ray(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	if ray_direction.length_squared() <= 0.000001:
		return {"hit": false}
	var direction := ray_direction.normalized()
	var nearest_mirror: CopyMirror
	var nearest_distance := INF
	for mirror in get_mirrors():
		var distance := mirror.get_pick_distance(ray_origin, direction)
		if distance >= 0.0 and distance < nearest_distance:
			nearest_mirror = mirror
			nearest_distance = distance
	if nearest_mirror == null:
		return {"hit": false}
	return {
		"hit": true,
		"mirror": nearest_mirror,
		"distance": nearest_distance,
		"position": ray_origin + direction * nearest_distance,
		"cell": nearest_mirror.from_cell,
		"edge_id": nearest_mirror.edge_id,
	}

func select_mirror(mirror: CopyMirror) -> void:
	if _selected_mirror != null and is_instance_valid(_selected_mirror):
		_selected_mirror.set_selected(false)
	_selected_mirror = mirror
	if _selected_mirror != null and is_instance_valid(_selected_mirror):
		_selected_mirror.set_selected(true)
	mirror_selected.emit(_selected_mirror)

func get_selected_mirror() -> CopyMirror:
	return _selected_mirror if _selected_mirror != null and is_instance_valid(_selected_mirror) else null

func get_mirror(edge_id: String) -> CopyMirror:
	if not _mirrors.has(edge_id):
		return null
	var mirror: CopyMirror = _mirrors[edge_id]
	return mirror if is_instance_valid(mirror) else null

func get_mirrors() -> Array[CopyMirror]:
	var result: Array[CopyMirror] = []
	for raw_mirror in _mirrors.values():
		if raw_mirror is CopyMirror and is_instance_valid(raw_mirror):
			result.append(raw_mirror)
	result.sort_custom(func(a: CopyMirror, b: CopyMirror) -> bool: return a.placement_order < b.placement_order)
	return result


func _get_definition(mirror_kind: MirrorPlacementData.MirrorKind) -> MirrorDefinition:
	if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT:
		return reflect_mirror_definition
	return copy_mirror_definition


func _get_mirror_kind(mirror: CopyMirror) -> MirrorPlacementData.MirrorKind:
	return (
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
		if mirror != null and mirror.is_projectile_reflector()
		else MirrorPlacementData.MirrorKind.COPY
	)


func _get_reflection_scheduling_definition() -> MirrorDefinition:
	if copy_mirror_definition != null and copy_mirror_definition.reflection_enabled:
		return copy_mirror_definition
	if reflect_mirror_definition != null and reflect_mirror_definition.reflection_enabled:
		return reflect_mirror_definition
	return null


func get_copy_mirrors() -> Array[CopyMirror]:
	var result: Array[CopyMirror] = []
	for mirror in get_mirrors():
		if mirror.is_copy_mirror():
			result.append(mirror)
	return result


func get_reflect_mirrors() -> Array[ReflectMirror]:
	var result: Array[ReflectMirror] = []
	for mirror in get_mirrors():
		if mirror is ReflectMirror and mirror.is_projectile_reflector():
			result.append(mirror as ReflectMirror)
	return result


## Returns the nearest active-face intersection across physical reflect mirrors
## and registered external finite-surface providers such as the acrylic case.
## Result keys: hit, position, normal, distance, mirror, reflector, surface_id,
## epsilon, max_reflections_per_frame.
func trace_projectile_reflection(start: Vector3, end: Vector3) -> Dictionary:
	var result := {
		"hit": false,
		"position": end,
		"normal": Vector3.ZERO,
		"distance": start.distance_to(end),
		"mirror": null,
		"reflector": null,
		"surface_id": StringName(),
		"epsilon": 0.0001,
		"max_reflections_per_frame": 1,
		"damage_multiplier": 1.0,
		"penetration_bonus": 0,
		"attack_effects": [],
		"is_reflect_mirror": false,
		"mirror_level": 0,
		"is_upgraded_reflect_mirror": false,
	}
	var segment := end - start
	var segment_length := segment.length()
	if segment_length <= 0.000001:
		return result
	var best_fraction := INF
	for mirror in get_reflect_mirrors():
		var definition := mirror.definition as ReflectMirrorDefinition
		if definition == null:
			continue
		var normal := mirror.get_active_normal()
		var denominator := segment.dot(normal)
		# The active side faces along +normal. Back-face travel passes through.
		if denominator >= -0.000001:
			continue
		var signed_start := (start - mirror.global_position).dot(normal)
		if signed_start < -0.000001:
			continue
		var fraction := -signed_start / denominator
		if fraction <= 0.000001 or fraction > 1.0 or fraction >= best_fraction:
			continue
		var hit_position := start + segment * fraction
		var endpoints := mirror.get_axis_endpoints()
		if endpoints.size() != 2:
			continue
		var edge := endpoints[1] - endpoints[0]
		var edge_length_squared := edge.length_squared()
		if edge_length_squared <= 0.000001:
			continue
		var along_edge := (hit_position - endpoints[0]).dot(edge) / edge_length_squared
		if along_edge < -0.0001 or along_edge > 1.0001:
			continue
		var base_height := mirror.global_position.y
		if hit_position.y < base_height - 0.0001 or hit_position.y > base_height + mirror.get_mirror_height() + 0.0001:
			continue
		best_fraction = fraction
		result.hit = true
		result.position = hit_position
		result.normal = normal
		result.distance = segment_length * fraction
		result.mirror = mirror
		result.reflector = mirror
		result.surface_id = StringName(mirror.edge_id)
		result.epsilon = maxf(0.0001, _grid.cell_size * definition.collision_epsilon_ratio)
		result.max_reflections_per_frame = definition.max_reflections_per_frame
		result.damage_multiplier = mirror.get_damage_multiplier()
		result.penetration_bonus = mirror.get_penetration_bonus()
		result.attack_effects = definition.get_attack_effects(mirror.level)
		result.is_reflect_mirror = true
		result.mirror_level = mirror.level
		result.is_upgraded_reflect_mirror = mirror.level >= 2
	var stale_provider_ids: Array[int] = []
	for raw_provider_id in _projectile_reflection_providers.keys():
		var provider_id := int(raw_provider_id)
		var entry: Dictionary = _projectile_reflection_providers.get(provider_id, {})
		var owner_reference: WeakRef = entry.get("owner") as WeakRef
		var owner: Object = owner_reference.get_ref() if owner_reference != null else null
		var resolver: Callable = entry.get("resolver", Callable())
		if owner == null or not is_instance_valid(owner) or not resolver.is_valid():
			stale_provider_ids.append(provider_id)
			continue
		var candidate_value: Variant = resolver.call(start, end)
		if not candidate_value is Dictionary:
			continue
		var candidate: Dictionary = candidate_value
		if not bool(candidate.get("hit", false)):
			continue
		var candidate_distance := float(candidate.get("distance", INF))
		if (
			not is_finite(candidate_distance)
			or candidate_distance < 0.0
			or candidate_distance > segment_length + 0.0001
			or bool(result.hit) and candidate_distance >= float(result.distance) - 0.000001
		):
			continue
		result = candidate.duplicate()
		result["distance"] = candidate_distance
		if not result.has("mirror"):
			result["mirror"] = null
		if not result.has("reflector"):
			result["reflector"] = owner
		if not result.has("surface_id"):
			result["surface_id"] = StringName()
		if not result.has("epsilon"):
			result["epsilon"] = 0.0001
		if not result.has("max_reflections_per_frame"):
			result["max_reflections_per_frame"] = 1
		if not result.has("damage_multiplier"):
			result["damage_multiplier"] = 1.0
		if not result.has("penetration_bonus"):
			result["penetration_bonus"] = 0
		if not result.has("attack_effects"):
			result["attack_effects"] = []
		if not result.has("is_reflect_mirror"):
			result["is_reflect_mirror"] = false
		if not result.has("mirror_level"):
			result["mirror_level"] = 0
		if not result.has("is_upgraded_reflect_mirror"):
			result["is_upgraded_reflect_mirror"] = false
	for provider_id in stale_provider_ids:
		_projectile_reflection_providers.erase(provider_id)
	return result


## Returns the nearest live real/projected Stuff sphere that blocks ballistics.
func trace_ballistic_blocker(
	start: Vector3,
	end: Vector3,
	excluded: Object = null
) -> Dictionary:
	var result := {
		"hit": false,
		"position": end,
		"distance": start.distance_to(end),
		"blocker": null,
	}
	var best_distance := INF
	if _stuff_manager != null and _stuff_manager.has_method("trace_ballistic_blocker"):
		var raw_real_hit: Variant = _stuff_manager.call(
			"trace_ballistic_blocker",
			start,
			end,
			excluded
		)
		if raw_real_hit is Dictionary:
			var real_hit: Dictionary = raw_real_hit
			if bool(real_hit.get("hit", false)):
				best_distance = float(real_hit.get("distance", INF))
				result = real_hit.duplicate()
	if (
		_stuff_manager == null
		or not _stuff_manager.has_method("get_ballistic_blocker_center")
		or not _stuff_manager.has_method("get_ballistic_blocker_radius")
	):
		return result
	var blocker_radius := float(_stuff_manager.call("get_ballistic_blocker_radius"))
	for projection in _projections:
		if (
			projection == excluded
			or not is_instance_valid(projection)
			or not projection.blocks_ballistics()
			or projection.payload == null
			or not projection.payload.root_source is StuffRuntime
		):
			continue
		var source_runtime := projection.payload.root_source as StuffRuntime
		var source_center: Vector3 = _stuff_manager.call(
			"get_ballistic_blocker_center",
			source_runtime
		)
		var center := projection.payload.transform_point(source_center)
		var distance := BallisticGeometryScript.ray_sphere_entry_distance(
			start,
			end,
			center,
			blocker_radius
		)
		if distance < 0.0 or distance >= best_distance:
			continue
		best_distance = distance
		var direction := (end - start).normalized()
		result.hit = true
		result.position = start + direction * distance
		result.distance = distance
		result.blocker = projection
	return result


func _purge_projectile_reflection_providers() -> void:
	var stale_provider_ids: Array[int] = []
	for raw_provider_id in _projectile_reflection_providers.keys():
		var provider_id := int(raw_provider_id)
		var entry: Dictionary = _projectile_reflection_providers.get(provider_id, {})
		var owner_reference: WeakRef = entry.get("owner") as WeakRef
		var resolver: Callable = entry.get("resolver", Callable())
		if owner_reference == null or owner_reference.get_ref() == null or not resolver.is_valid():
			stale_provider_ids.append(provider_id)
	for provider_id in stale_provider_ids:
		_projectile_reflection_providers.erase(provider_id)
	return

func get_projections(cell: Variant = null) -> Array[MirrorProjection]:
	if cell is Vector3i:
		var by_cell: Array[MirrorProjection] = []
		for raw_projection in _projections_by_cell.get(cell, []):
			if raw_projection is MirrorProjection and is_instance_valid(raw_projection):
				by_cell.append(raw_projection)
		return by_cell
	return _projections.duplicate()


## Returns the complete recursive blocker set for current mirrors plus an
## optional unregistered source/mirror. This is the sole prospective mirror
## graph query used by placement connectivity validation.
func get_prospective_blocked_cells(
	extra_source: Variant = null,
	candidate_mirror: Variant = null,
	target: Node = null,
	excluded_source: Variant = null,
	excluded_mirror: Variant = null
) -> Dictionary:
	var mirrors := get_mirrors()
	if excluded_mirror is CopyMirror:
		mirrors.erase(excluded_mirror)
	if candidate_mirror is CopyMirror and is_instance_valid(candidate_mirror):
		mirrors.append(candidate_mirror)
		mirrors.sort_custom(func(a: CopyMirror, b: CopyMirror) -> bool: return a.placement_order < b.placement_order)
	var blocked: Dictionary = {}
	for payload in _calculate_projection_payloads(mirrors, extra_source, excluded_source):
		if not _payload_blocks_enemy_navigation(payload, target):
			continue
		blocked[payload.projected_cell] = true
	return blocked

func set_inspected_cell(cell: Variant = null) -> void:
	for projection in _projections:
		if is_instance_valid(projection):
			projection.set_inspection_active(cell is Vector3i and projection.payload.projected_cell == cell)

func get_projection_inspection_lines(cell: Vector3i) -> Array[String]:
	var lines: Array[String] = []
	for projection in get_projections(cell):
		lines.append(projection.get_inspection_text())
	return lines

func get_projected_effects(cell: Vector3i) -> Array[TileEffect]:
	var effects: Array[TileEffect] = []
	for projection in get_projections(cell):
		var effect := projection.get_tile_effect()
		if effect != null:
			effects.append(effect)
	return effects

## Stateful tile effects retain the real source cell as their runtime identity,
## so every direct/recursive projection shares source capacity and cooldown.
func get_projected_effect_bindings(cell: Vector3i) -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for projection in get_projections(cell):
		var effect := projection.get_tile_effect()
		if effect == null or projection.payload == null:
			continue
		bindings.append({
			"effect": effect,
			"source_cell": projection.payload.root_source_cell,
			"state_key": (
				projection.payload.root_source.call("get_effect_state_key")
				if projection.payload.root_source != null
				and projection.payload.root_source.has_method("get_effect_state_key")
				else effect.get_runtime_state_key(projection.payload.root_source_cell)
			),
		})
	return bindings

func blocks_enemy_navigation(cell: Vector3i, target: Node = null) -> bool:
	for projection in get_projections(cell):
		if projection.blocks_enemy_navigation(target):
			return true
	return false

func resolve_projected_blocker(cell: Vector3i, target: Node = null) -> Node:
	for projection in get_projections(cell):
		if projection.payload.copy_kind == &"barrier" and projection.is_structure_alive() and projection.affects_target(target):
			return projection
	return null

## Projected terrain blockers remain separate from direct-attack building
## blockers so EnemyUnit can run authored-path rerouting before attacking them.
func resolve_projected_navigation_blocker(cell: Vector3i, target: Node = null) -> Node:
	for projection in get_projections(cell):
		if (
			projection.blocks_enemy_navigation(target)
			and projection.is_destructible()
			and projection.is_structure_alive()
			and projection.affects_target(target)
		):
			return projection
	return null

func update_preview(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant = null
) -> bool:
	return _update_mirror_preview(
		from_cell,
		edge_index,
		MirrorPlacementData.MirrorKind.COPY,
		active_from_side
	)


func update_reflect_preview(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant = null
) -> bool:
	return _update_mirror_preview(
		from_cell,
		edge_index,
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
		active_from_side
	)


func _update_mirror_preview(
	from_cell: Vector3i,
	edge_index: int,
	mirror_kind: MirrorPlacementData.MirrorKind,
	active_from_side: Variant = null,
	relocation_source: CopyMirror = null
) -> bool:
	var validation := validate_placement(
		from_cell,
		edge_index,
		false,
		mirror_kind,
		relocation_source
	)
	var placement_failure: String = validation.failure
	if not placement_failure.is_empty() and not _can_render_mirror_preview(
		from_cell,
		edge_index,
		mirror_kind
	):
		clear_preview()
		return false
	if active_from_side != null:
		_preview_active_from_side = bool(active_from_side)
	var edge_id: String = validation.edge_id
	if edge_id.is_empty():
		edge_id = _grid.canonical_edge_id(from_cell, edge_index)
	var to_cell := _grid.neighbor_across_edge(from_cell, edge_index)
	if (
		not reuse_placement_preview_instances
		or _preview_mirror == null
		or not is_instance_valid(_preview_mirror)
		or _preview_kind != mirror_kind
		or _preview_relocation_source != relocation_source
	):
		clear_preview()
		_preview_relocation_source = relocation_source
		_preview_kind = mirror_kind
		_preview_mirror = (
			ReflectMirror.new()
			if mirror_kind == MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT
			else CopyMirror.new()
		)
		add_child(_preview_mirror)
		_preview_mirror.configure(
			_get_definition(mirror_kind),
			from_cell,
			to_cell,
			edge_index,
			edge_id,
			_grid,
			_tile_manager,
			_preview_active_from_side,
			true
		)
		_preview_mirror.set_reflection_camera(_reflection_camera)
		if relocation_source != null:
			_preview_mirror.set_level(relocation_source.level)
			_preview_mirror.placement_order = relocation_source.placement_order
	else:
		_preview_mirror.relocate_preview(
			from_cell,
			to_cell,
			edge_index,
			edge_id
		)
		if _preview_mirror.active_from_side != _preview_active_from_side:
			_preview_mirror.flip_side()
	_preview_placement_failure = placement_failure
	_preview_mirror.visible = true
	_refresh_preview_projection()
	return placement_failure.is_empty()


func _can_render_mirror_preview(
	from_cell: Vector3i,
	edge_index: int,
	mirror_kind: MirrorPlacementData.MirrorKind
) -> bool:
	var definition := _get_definition(mirror_kind)
	return (
		feature_enabled
		and definition != null
		and definition.validate_configuration().is_empty()
		and _grid != null
		and _tile_manager != null
		and _resource_manager != null
		and _combat_manager != null
		and _grid.is_in_bounds(from_cell)
		and edge_index >= 0
		and edge_index < _grid.edge_count()
	)

func flip_preview() -> bool:
	if _preview_mirror == null or not is_instance_valid(_preview_mirror):
		return false
	_preview_active_from_side = not _preview_active_from_side
	_preview_mirror.flip_side()
	_refresh_preview_projection()
	return true

func clear_preview() -> void:
	var had_preview := _preview_mirror != null or not _preview_projections.is_empty()
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		_preview_mirror.queue_free()
	_preview_mirror = null
	_preview_relocation_source = null
	_preview_placement_failure = ""
	_clear_preview_projections()
	_preview_info = {}
	if had_preview:
		preview_cleared.emit()

func get_preview_info() -> Dictionary:
	return _preview_info.duplicate(true)


func get_preview_mirror() -> CopyMirror:
	return _preview_mirror if _preview_mirror != null and is_instance_valid(_preview_mirror) else null


func get_preview_projections() -> Array[MirrorProjection]:
	var result: Array[MirrorProjection] = []
	for projection in _preview_projections:
		if projection != null and is_instance_valid(projection):
			result.append(projection)
	return result


## Supplies the source Building and generated copy payloads belonging to the
## active copy-mirror placement preview. Reflect-mirror previews return empty.
func get_preview_projectile_trajectory() -> Dictionary:
	var result := {
		"building": null,
		"payloads": [],
	}
	if (
		_preview_mirror == null
		or not is_instance_valid(_preview_mirror)
		or not _preview_mirror.is_copy_mirror()
	):
		return result
	var source_building: Building
	var payloads: Array[MirrorCopyPayload] = []
	for projection in get_preview_projections():
		var payload := projection.payload
		if (
			payload == null
			or not payload.is_source_valid()
			or not payload.root_source is Building
		):
			continue
		var candidate := payload.root_source as Building
		if source_building == null:
			source_building = candidate
		if candidate == source_building:
			payloads.append(payload)
	result.building = source_building
	result.payloads = payloads
	return result


func get_building_preview_projections() -> Array[MirrorProjection]:
	var result: Array[MirrorProjection] = []
	for projection in _building_preview_projections:
		if projection != null and is_instance_valid(projection):
			result.append(projection)
	return result


## Returns only the copy transforms belonging to this real or placement-preview
## source. The selection visualizer uses them without taking mirror ownership.
func get_projectile_trajectory_copy_payloads(building: Building) -> Array[MirrorCopyPayload]:
	var result: Array[MirrorCopyPayload] = []
	if building == null or not is_instance_valid(building):
		return result
	var candidates: Array[MirrorProjection] = (
		get_building_preview_projections()
		if _building_manager != null and building == _building_manager.get_preview_building()
		else get_projections()
	)
	for projection in candidates:
		if (
			projection.payload != null
			and projection.payload.is_source_valid()
			and projection.payload.root_source == building
		):
			result.append(projection.payload)
	return result

func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild_now")

func rebuild_now() -> void:
	_rebuild_queued = false
	_clear_projection_nodes()
	if not feature_enabled or copy_mirror_definition == null or _grid == null or _tile_manager == null:
		_laser_projection_states.clear()
		_pulse_projection_states.clear()
		projections_rebuilt.emit(0)
		_clear_building_preview_projections()
		building_preview_projections_rebuilt.emit(0)
		return
	var payloads := _calculate_projection_payloads(get_copy_mirrors())
	var stack_counts: Dictionary = {}
	var active_laser_state_keys: Dictionary = {}
	var active_pulse_state_keys: Dictionary = {}
	for payload in payloads:
		if not payload.is_source_valid():
			continue
		var stack_index := int(stack_counts.get(payload.projected_cell, 0))
		stack_counts[payload.projected_cell] = stack_index + 1
		var projection := MirrorProjection.new()
		add_child(projection)
		projection.configure(
			payload,
			_grid,
			_tile_manager,
			copy_mirror_definition,
			stack_index,
			false,
			_tile_visual_snapshot_resolver
		)
		if payload.copy_kind == &"laser_tower":
			active_laser_state_keys[payload.stable_key] = true
			if _laser_projection_states.has(payload.stable_key):
				projection.restore_laser_propagation_state(
					_laser_projection_states[payload.stable_key]
				)
		elif payload.copy_kind == &"pulse_laser_tower":
			active_pulse_state_keys[payload.stable_key] = true
			if _pulse_projection_states.has(payload.stable_key):
				projection.restore_pulse_special_state(
					_pulse_projection_states[payload.stable_key]
				)
		_projections.append(projection)
		if not _projections_by_cell.has(payload.projected_cell):
			_projections_by_cell[payload.projected_cell] = []
		_projections_by_cell[payload.projected_cell].append(projection)
	for state_key in _laser_projection_states.keys():
		if not active_laser_state_keys.has(state_key):
			_laser_projection_states.erase(state_key)
	for state_key in _pulse_projection_states.keys():
		if not active_pulse_state_keys.has(state_key):
			_pulse_projection_states.erase(state_key)
	projections_rebuilt.emit(_projections.size())
	if _preview_mirror != null:
		_refresh_preview_projection()
	_refresh_building_preview_projections(
		_building_manager.get_preview_building() if _building_manager != null else null
	)

func _calculate_projection_payloads(
	mirrors: Array[CopyMirror],
	extra_source: Variant = null,
	excluded_source: Variant = null
) -> Array[MirrorCopyPayload]:
	var base_content := _build_base_content_map(extra_source, excluded_source)
	var current: Array[MirrorCopyPayload] = []
	var maximum_passes := maxi(2, copy_mirror_definition.copy_chain_max * maxi(1, mirrors.size()) + 2)
	for _pass_index in range(maximum_passes):
		var content := _duplicate_content_map(base_content)
		for payload in current:
			_append_content(content, payload.projected_cell, payload)
		var next: Array[MirrorCopyPayload] = []
		for mirror in mirrors:
			if not mirror.is_copy_mirror():
				continue
			var group := _build_projection_group(mirror, content)
			if not group.is_empty():
				next.append_array(group)
		if _payload_signature(next) == _payload_signature(current):
			return next
		current = next
	return current

func _build_projection_group(
	mirror: CopyMirror,
	content: Dictionary
) -> Array[MirrorCopyPayload]:
	var result: Array[MirrorCopyPayload] = []
	var endpoints := mirror.get_axis_endpoints()
	if endpoints.size() != 2:
		return result
	var maximum_distance := maxi(1, _grid.enumerate_cells().size())
	for distance_from_edge in range(1, maximum_distance + 1):
		var pair := _grid.get_mirror_cell_pair(
			mirror.from_cell,
			mirror.edge_index,
			mirror.active_from_side,
			distance_from_edge
		)
		if not pair.valid:
			break
		var candidates: Array = content.get(pair.source_cell, [])
		var eligible: Array[MirrorCopyPayload] = []
		for raw_payload in candidates:
			if raw_payload is MirrorCopyPayload and raw_payload.can_pass_through(mirror.edge_id, copy_mirror_definition.copy_chain_max):
				eligible.append(raw_payload)
		if eligible.is_empty():
			continue
		eligible.sort_custom(func(a: MirrorCopyPayload, b: MirrorCopyPayload) -> bool: return a.stable_key < b.stable_key)
		# Projections are presentation/combat overlays, never tile occupants. They
		# may overlap any one real entity and any number of other projections.
		# projection_ignores_occupancy remains serialized only for old resources;
		# the runtime invariant is now unconditional.
		for source_payload in eligible:
			var next_chain_depth := source_payload.chain_depth + 1
			var next_payload := source_payload.copy_through(
				mirror.edge_id,
				pair.target_cell,
				endpoints[0],
				endpoints[1],
				mirror.get_damage_multiplier(),
				mirror.get_penetration_bonus(),
				copy_mirror_definition.get_projection_alpha_for_depth(
					mirror.level,
					next_chain_depth,
					source_payload.projection_alpha if source_payload.chain_depth > 0 else -1.0
				),
				mirror.level
			)
			if mirror.definition != null:
				mirror.definition.apply_copy_attack_effects(
					next_payload.attack_effects,
					mirror.level,
					{
						"mirror": mirror,
						"copy_kind": next_payload.copy_kind,
						"chain_depth": next_payload.chain_depth,
						"copy_upgrade_count": next_payload.copy_upgrade_count,
					}
				)
			result.append(next_payload)
		return result
	return result

func _build_base_content_map(
	extra_source: Variant = null,
	excluded_source: Variant = null
) -> Dictionary:
	var content: Dictionary = {}
	if _building_manager != null:
		for building in _building_manager.get_buildings():
			if building == excluded_source:
				continue
			_append_building_content(content, building)
	if extra_source is Building and is_instance_valid(extra_source):
		_append_building_content(content, extra_source as Building, "candidate")
	if _stuff_manager != null:
		for runtime in _stuff_manager.call("get_all_stuff"):
			_append_stuff_content(content, runtime)
	elif _tile_manager != null:
		for tile in _tile_manager.get_tiles():
			var effect := tile.get_effect()
			if effect == null:
				continue
			var kind := effect.get_copy_kind()
			if kind.is_empty():
				continue
			var payload := MirrorCopyPayload.new()
			payload.stable_key = "effect:%s:%d" % [str(tile.cell), effect.get_instance_id()]
			payload.copy_kind = kind
			payload.display_name = effect.get_copy_display_name()
			payload.source_cell = tile.cell
			payload.root_source_cell = tile.cell
			payload.projected_cell = tile.cell
			if effect.creates_runtime_obstacle():
				payload.root_source = _tile_manager.get_runtime_obstacle(tile.cell)
				payload.uses_structure_lifetime = true
			payload.tile_effect = effect
			payload.primary_color = effect.get_copy_color()
			_append_content(content, tile.cell, payload)
	if extra_source is StuffRuntime and is_instance_valid(extra_source):
		_append_stuff_content(content, extra_source as StuffRuntime, "candidate_stuff")
	return content


func _append_stuff_content(
	content: Dictionary,
	runtime: StuffRuntime,
	key_prefix: String = "stuff"
) -> void:
	if runtime == null or not is_instance_valid(runtime):
		return
	var kind := runtime.get_copy_kind()
	if kind.is_empty():
		return
	var payload := MirrorCopyPayload.new()
	payload.stable_key = "%s:%s" % [key_prefix, String(runtime.placement_id)]
	payload.copy_kind = kind
	payload.display_name = runtime.get_copy_display_name()
	payload.source_cell = runtime.cell
	payload.root_source_cell = runtime.cell
	payload.projected_cell = runtime.cell
	payload.root_source = runtime
	payload.tile_effect = runtime.get_effect()
	payload.uses_structure_lifetime = true
	payload.primary_color = runtime.get_copy_color()
	_append_content(content, payload.source_cell, payload)


func _append_building_content(content: Dictionary, building: Building, key_prefix: String = "building") -> void:
	if building == null or not is_instance_valid(building):
		return
	var kind := building.get_copy_kind()
	if kind.is_empty():
		return
	var payload := MirrorCopyPayload.new()
	payload.stable_key = "%s:%d" % [key_prefix, building.get_instance_id()]
	payload.copy_kind = kind
	payload.display_name = building.get_copy_display_name()
	payload.source_cell = building.cell
	payload.root_source_cell = building.cell
	payload.projected_cell = building.cell
	payload.root_source = building
	payload.uses_structure_lifetime = building.is_path_blocker()
	payload.primary_color = building.get_copy_color()
	_append_content(content, building.cell, payload)

func _refresh_preview_projection() -> void:
	if _preview_mirror == null or not is_instance_valid(_preview_mirror):
		_clear_preview_projections()
		return
	if not _preview_placement_failure.is_empty():
		_clear_preview_projections()
		_preview_mirror.set_preview_valid(false)
		_preview_info = {
			"edge_id": _preview_mirror.edge_id,
			"active_cell": _preview_mirror.get_active_cell(),
			"has_source": false,
			"source_cell": Vector3i.ZERO,
			"target_cell": Vector3i.ZERO,
			"types": [],
			"valid": false,
			"failure": _preview_placement_failure,
			"warning": _preview_placement_failure,
			"mirror_kind": _preview_kind,
		}
		preview_updated.emit(_preview_info)
		return
	if not _preview_mirror.is_copy_mirror():
		_clear_preview_projections()
		_preview_mirror.set_preview_valid(true)
		_preview_info = {
			"edge_id": _preview_mirror.edge_id,
			"active_cell": _preview_mirror.get_active_cell(),
			"has_source": false,
			"source_cell": Vector3i.ZERO,
			"target_cell": Vector3i.ZERO,
			"types": [],
			"valid": true,
			"failure": "",
			"warning": "生效面将按入射角反射我方投射物",
			"mirror_kind": MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
		}
		preview_updated.emit(_preview_info)
		return
	var group: Array[MirrorCopyPayload] = []
	if _preview_relocation_source != null:
		var prospective_mirrors := get_mirrors()
		prospective_mirrors.erase(_preview_relocation_source)
		prospective_mirrors.append(_preview_mirror)
		prospective_mirrors.sort_custom(
			func(a: CopyMirror, b: CopyMirror) -> bool:
				return a.placement_order < b.placement_order
		)
		for payload in _calculate_projection_payloads(prospective_mirrors):
			if payload.lineage.has(_preview_mirror.edge_id):
				group.append(payload)
	else:
		var content := _build_base_content_map()
		for projection in _projections:
			if projection.payload != null and projection.payload.is_source_valid():
				_append_content(content, projection.payload.projected_cell, projection.payload)
		group = _build_projection_group(_preview_mirror, content)
	var connectivity_change := {"candidate_mirror": _preview_mirror}
	if _preview_relocation_source != null:
		connectivity_change["removed_mirror"] = _preview_relocation_source
	var connectivity_failure := _validate_path_connectivity(connectivity_change)
	var preview_valid := connectivity_failure.is_empty()
	_preview_mirror.set_preview_valid(preview_valid)
	_preview_info = {
		"edge_id": _preview_mirror.edge_id,
		"active_cell": _preview_mirror.get_active_cell(),
		"has_source": not group.is_empty(),
		"source_cell": group[0].source_cell if not group.is_empty() else Vector3i.ZERO,
		"target_cell": group[0].projected_cell if not group.is_empty() else Vector3i.ZERO,
		"types": [],
		"valid": preview_valid,
		"failure": connectivity_failure,
		"warning": connectivity_failure if not preview_valid else ("未找到可复制的非空地块，仍可放置" if group.is_empty() else ""),
		"mirror_kind": MirrorPlacementData.MirrorKind.COPY,
	}
	var stack_index := 0
	var next_projections: Array[MirrorProjection] = []
	var reusable_projections: Array = _preview_projections.duplicate() if reuse_placement_preview_instances else []
	if not reuse_placement_preview_instances:
		_clear_preview_projections()
	for payload in group:
		_preview_info.types.append(payload.display_name)
		var projection := _take_reusable_preview_projection(
			reusable_projections,
			payload,
			stack_index,
			preview_valid
		)
		if projection == null:
			projection = MirrorProjection.new()
			add_child(projection)
			projection.configure(
				payload,
				_grid,
				_tile_manager,
				copy_mirror_definition,
				stack_index,
				true,
				_tile_visual_snapshot_resolver,
				preview_valid
			)
		next_projections.append(projection)
		stack_index += 1
	_release_unused_preview_projections(reusable_projections)
	_preview_projections = next_projections
	preview_updated.emit(_preview_info)


func _refresh_building_preview_projections(building: Building) -> void:
	if (
		building == null
		or not is_instance_valid(building)
		or (
			_building_manager != null
			and not _building_manager.is_preview_placement_valid()
		)
		or not feature_enabled
		or copy_mirror_definition == null
		or _grid == null
		or _tile_manager == null
	):
		_clear_building_preview_projections()
		building_preview_projections_rebuilt.emit(0)
		return
	var stack_counts: Dictionary = {}
	for raw_cell in _projections_by_cell:
		stack_counts[raw_cell] = (_projections_by_cell[raw_cell] as Array).size()
	var next_projections: Array[MirrorProjection] = []
	var reusable_projections: Array = _building_preview_projections.duplicate() if reuse_placement_preview_instances else []
	if not reuse_placement_preview_instances:
		_clear_building_preview_projections()
	for payload in _calculate_projection_payloads(get_copy_mirrors(), building):
		if not payload.is_source_valid() or payload.root_source != building:
			continue
		var stack_index := int(stack_counts.get(payload.projected_cell, 0))
		stack_counts[payload.projected_cell] = stack_index + 1
		var projection := _take_reusable_preview_projection(
			reusable_projections,
			payload,
			stack_index,
			building.is_preview_valid()
		)
		if projection == null:
			projection = MirrorProjection.new()
			add_child(projection)
			projection.configure(
				payload,
				_grid,
				_tile_manager,
				copy_mirror_definition,
				stack_index,
				true,
				_tile_visual_snapshot_resolver,
				building.is_preview_valid()
			)
		next_projections.append(projection)
	_release_unused_preview_projections(reusable_projections)
	_building_preview_projections = next_projections
	building_preview_projections_rebuilt.emit(_building_preview_projections.size())


func _take_reusable_preview_projection(
	candidates: Array,
	payload: MirrorCopyPayload,
	stack_index: int,
	preview_valid: bool
) -> MirrorProjection:
	for index in range(candidates.size()):
		var candidate := candidates[index] as MirrorProjection
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate.retarget_preview(payload, stack_index, preview_valid):
			candidates.remove_at(index)
			return candidate
	return null


func _release_unused_preview_projections(candidates: Array) -> void:
	for candidate_value in candidates:
		var candidate := candidate_value as MirrorProjection
		if candidate != null and is_instance_valid(candidate):
			candidate.visible = false
			candidate.queue_free()


func _validate_path_connectivity(change: Dictionary) -> String:
	if not _path_connectivity_validator.is_valid():
		return ""
	return String(_path_connectivity_validator.call(change))


func _payload_affects_target(payload: MirrorCopyPayload, target: Node) -> bool:
	if payload.root_source != null and payload.root_source.has_method("affects_target"):
		return bool(payload.root_source.call("affects_target", target))
	if payload.tile_effect != null:
		return payload.tile_effect.affects_target(target)
	return true


func _payload_blocks_enemy_navigation(payload: MirrorCopyPayload, target: Node) -> bool:
	if payload == null or not payload.is_source_valid():
		return false
	# Barrier buildings have no TileEffect/Stuff definition; their copy kind is
	# itself the navigation contract.
	if payload.copy_kind == &"barrier":
		return _payload_affects_target(payload, target)
	if payload.root_source != null and payload.root_source.has_method("blocks_enemy_navigation"):
		return bool(payload.root_source.call("blocks_enemy_navigation", target))
	if payload.tile_effect != null:
		return payload.tile_effect.blocks_enemy_navigation(target)
	return false

func _clear_projection_nodes() -> void:
	for projection in _projections:
		if is_instance_valid(projection):
			if (
				projection.payload != null
				and projection.payload.copy_kind == &"laser_tower"
				and not projection.payload.stable_key.is_empty()
			):
				_laser_projection_states[projection.payload.stable_key] = (
					projection.get_laser_propagation_state()
				)
			elif (
				projection.payload != null
				and projection.payload.copy_kind == &"pulse_laser_tower"
				and not projection.payload.stable_key.is_empty()
			):
				_pulse_projection_states[projection.payload.stable_key] = (
					projection.get_pulse_special_state()
				)
			projection.visible = false
			projection.queue_free()
	_projections.clear()
	_projections_by_cell.clear()

func _clear_preview_projections() -> void:
	for projection in _preview_projections:
		if is_instance_valid(projection):
			projection.visible = false
			projection.queue_free()
	_preview_projections.clear()


func _clear_building_preview_projections() -> void:
	for projection in _building_preview_projections:
		if is_instance_valid(projection):
			projection.visible = false
			projection.queue_free()
	_building_preview_projections.clear()

func _update_reflection_views() -> void:
	if not feature_enabled:
		return
	if _reflection_camera == null or not is_instance_valid(_reflection_camera):
		return
	var scheduling_definition := _get_reflection_scheduling_definition()
	if scheduling_definition == null or not scheduling_definition.reflection_enabled:
		return
	var interval := maxi(1, scheduling_definition.reflection_update_interval_frames)
	if Engine.get_process_frames() % interval != 0:
		return
	var candidates: Array[CopyMirror] = get_mirrors()
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		candidates.append(_preview_mirror)
	if candidates.is_empty():
		_reflection_cursor = 0
		return
	_reflection_cursor %= candidates.size()
	var updated := 0
	var checked := 0
	var maximum_updates := maxi(1, scheduling_definition.reflection_max_updates_per_frame)
	while checked < candidates.size() and updated < maximum_updates:
		var index := (_reflection_cursor + checked) % candidates.size()
		if candidates[index].request_reflection_refresh():
			updated += 1
		checked += 1
	_reflection_cursor = (_reflection_cursor + maxi(1, checked)) % candidates.size()

func _append_content(content: Dictionary, cell: Vector3i, payload: MirrorCopyPayload) -> void:
	if not content.has(cell):
		content[cell] = []
	content[cell].append(payload)

func _duplicate_content_map(source: Dictionary) -> Dictionary:
	var duplicate: Dictionary = {}
	for cell in source:
		duplicate[cell] = source[cell].duplicate()
	return duplicate

func _payload_signature(payloads: Array[MirrorCopyPayload]) -> String:
	var entries: Array[String] = []
	for payload in payloads:
		entries.append("%s@%s" % [payload.stable_key, str(payload.projected_cell)])
	entries.sort()
	return "|".join(entries)

func _get_edge_occupant(edge_id: String) -> Object:
	if _edge_occupancy_registry != null:
		return _edge_occupancy_registry.get_occupant(edge_id)
	if _building_manager != null:
		var building := _building_manager.get_edge_building(edge_id)
		if building != null:
			return building
	return get_mirror(edge_id)

func _connect_attack_source(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.copy_attack_triggered.is_connected(_on_copy_attack_triggered):
		building.copy_attack_triggered.connect(_on_copy_attack_triggered)
	_attack_sources[building] = true

func _disconnect_attack_source(building: Building) -> void:
	if building != null and is_instance_valid(building):
		if building.copy_attack_triggered.is_connected(_on_copy_attack_triggered):
			building.copy_attack_triggered.disconnect(_on_copy_attack_triggered)
	_attack_sources.erase(building)

func _disconnect_attack_sources() -> void:
	for source in _attack_sources.keys():
		if source is Building:
			_disconnect_attack_source(source)
	_attack_sources.clear()


func _get_pulse_overdrive_effect(payload: MirrorCopyPayload) -> Resource:
	if payload == null or payload.attack_effects == null:
		return null
	return payload.attack_effects.get_effect_resource(&"pulse_laser_overdrive")


func _get_copy_definition_effect(effect_id: StringName) -> Resource:
	if copy_mirror_definition == null:
		return null
	for effect in copy_mirror_definition.get_attack_effects(2):
		if effect != null and effect.get_effect_id() == effect_id:
			return effect
	return null


func _update_pulse_copy_specials(delta: float) -> void:
	if _combat_manager == null or _grid == null:
		return
	for projection in _projections:
		if (
			projection == null
			or not is_instance_valid(projection)
			or projection.payload == null
			or projection.payload.copy_kind != &"pulse_laser_tower"
		):
			continue
		var effect := _get_pulse_overdrive_effect(projection.payload)
		var source := projection.payload.root_source as Building
		if effect == null or source == null or not is_instance_valid(source):
			continue
		var source_state := source.get_pulse_copy_mirror_state()
		var source_start := source.get_attack_origin()
		var source_end := source_start + source.get_facing_direction() * source.get_attack_range_world()
		var world_start := projection.payload.transform_point(source_start)
		var world_end := projection.payload.transform_point(source_end)
		var direction := world_end - world_start
		if direction.length_squared() <= 0.000001:
			continue
		var phase := StringName(source_state.get("phase", &"charging"))
		if phase != &"overdrive":
			projection.clear_pulse_overdrive_path()
			projection.update_pulse_charge_orb(
				world_start,
				effect.get("charge_orb_color") as Color,
				source.get_pulse_laser_width_world()
					* float(effect.get("charge_orb_radius_multiplier")),
				float(effect.get("charge_orb_min_scale")),
				float(effect.get("charge_orb_max_scale")),
				float(effect.get("charge_orb_pulse_speed")),
				delta
			)
			projection.set_pulse_special_inspection_status(
				"充能 %d/%d" % [
					int(source_state.get("charge_count", 0)),
					int(source_state.get("charge_shots", 5)),
				]
			)
			continue
		projection.hide_pulse_charge_orb()
		var overdrive_duration := maxf(
			0.0,
			float(source_state.get("overdrive_duration", 10.0))
		)
		var overdrive_remaining := maxf(
			0.0,
			float(source_state.get("overdrive_remaining", 0.0))
		)
		var elapsed := maxf(0.0, overdrive_duration - overdrive_remaining)
		var visible_distance := projection.advance_pulse_overdrive_propagation(
			int(source_state.get("generation", 0)),
			delta,
			source.get_attack_range_world(),
			float(effect.get("propagation_speed_cells_per_second")) * _grid.cell_size,
			elapsed
		)
		var runtime_effects := projection.payload.attack_effects.instantiate_attack()
		var path: Dictionary = ContinuousLaserPathScript.trace(
			_combat_manager,
			source,
			world_start,
			direction.normalized(),
			visible_distance,
			1_000_000,
			_combat_manager.get_projectile_reflection_resolver(),
			Callable(self, "trace_ballistic_blocker"),
			runtime_effects,
			1.0,
			0,
			&"pulse_overdrive"
		)
		var copy_count := clampi(projection.payload.copy_upgrade_count, 1, 3)
		var dps := (
			source.get_instant_damage()
			* source.get_attacks_per_second()
			* maxf(0.0, projection.payload.damage_multiplier)
			* maxf(0.0, float(effect.call("get_dps_multiplier", copy_count)))
		)
		_apply_pulse_overdrive_damage(path, dps, delta)
		var base_width := (
			source.get_pulse_laser_width_world()
			* maxf(0.0, float(effect.call("get_beam_width_multiplier", copy_count)))
		)
		var overdrive_colors := source.get_pulse_laser_reflection_colors()
		var overdrive_base_color := (
			overdrive_colors[0]
			if not overdrive_colors.is_empty()
			else source.get_attack_color()
		)
		projection.show_pulse_overdrive_path(
			path.get("segments", []),
			path.get("endpoint", world_start),
			overdrive_base_color,
			base_width,
			source.get_pulse_laser_emission_energy(),
			{
				"thickness_multiplier": effect.get("sine_thickness_multiplier"),
				"amplitude_ratio": effect.get("sine_amplitude_ratio"),
				"wavelength_ratio": effect.get("sine_wavelength_ratio"),
				"flow_cycles_per_second": effect.get("sine_flow_cycles_per_second"),
				"samples_per_cycle": effect.get("sine_samples_per_cycle"),
				"min_subdivisions": effect.get("sine_min_subdivisions"),
				"max_subdivisions": effect.get("sine_max_subdivisions"),
			}
		)
		projection.set_pulse_special_inspection_status(
			"爆发 %.1fs" % overdrive_remaining
		)


func _apply_pulse_overdrive_damage(path: Dictionary, damage_per_second: float, delta: float) -> void:
	var duration := maxf(0.0, delta)
	if damage_per_second <= 0.0 or duration <= 0.0:
		return
	for raw_reflection in path.get("reflections", []):
		if not raw_reflection is Dictionary:
			continue
		var reflection := raw_reflection as Dictionary
		ReflectionDamageScript.apply(
			reflection,
			damage_per_second
				* maxf(0.0, float(reflection.get("path_damage_multiplier", 1.0)))
				* duration
		)
	for raw_hit in path.get("hits", []):
		if not raw_hit is Dictionary:
			continue
		var hit := raw_hit as Dictionary
		var target := hit.get("target") as CombatTarget
		if target == null or not is_instance_valid(target) or not target.is_alive():
			continue
		var hit_dps := damage_per_second * maxf(
			0.0,
			float(hit.get("damage_multiplier", path.get("damage_multiplier", 1.0)))
		)
		target.take_damage_over_time(hit_dps, duration)

func _on_copy_attack_triggered(
	building: Building,
	attack_kind: StringName,
	world_start: Vector3,
	world_end: Vector3,
	damage: float
) -> void:
	if _combat_manager == null or not is_instance_valid(building):
		return
	var ice_event_count := 0
	if attack_kind == &"laser" and building.get_copy_kind() == &"laser_tower":
		var ice_clock_effect := _get_copy_definition_effect(&"ice_copy_burst")
		if ice_clock_effect != null:
			var source_dps := building.get_laser_damage_per_second()
			var source_delta := maxf(0.0, damage) / source_dps if source_dps > 0.0 else 0.0
			ice_event_count = building.advance_ice_copy_mirror_clock(
				source_delta,
				float(ice_clock_effect.get("burst_interval"))
			)
	if attack_kind == &"pulse_laser":
		for projection in _projections:
			if (
				projection == null
				or not is_instance_valid(projection)
				or projection.payload == null
				or projection.payload.root_source != building
				or projection.payload.copy_kind != &"pulse_laser_tower"
			):
				continue
			var pulse_effect := _get_pulse_overdrive_effect(projection.payload)
			if pulse_effect == null:
				continue
			building.register_pulse_copy_mirror_charge(
				int(pulse_effect.get("charge_shots")),
				building.get_pulse_laser_fade_in_time()
					+ building.get_pulse_laser_hold_time()
					+ building.get_pulse_laser_fade_out_time(),
				float(pulse_effect.get("overdrive_duration"))
			)
			break
	for projection in _projections:
		if not is_instance_valid(projection) or projection.payload.root_source != building:
			continue
		var copy_damage_multiplier := maxf(0.0, projection.payload.damage_multiplier)
		var copied_damage := maxf(0.0, damage) * copy_damage_multiplier
		var copied_penetration := (
			building.get_projectile_penetration_count()
			+ maxi(0, projection.payload.penetration_bonus)
		)
		var start := projection.payload.transform_point(world_start)
		var end := projection.payload.transform_point(world_end)
		var attack_effects := (
			projection.payload.attack_effects.instantiate_attack()
			if projection.payload.attack_effects != null
			else AttackEffectPayload.new()
		)
		if (
			attack_kind in [&"missile", &"directional_missile"]
			and projection.payload.copy_kind == &"crossbow_tower"
		):
			var missile_direction := end - start
			if missile_direction.length_squared() <= 0.000001:
				continue
			var copied_missile := _combat_manager.spawn_directional_missile(
				start,
				missile_direction.normalized(),
				building.get_projectile_speed_world(),
				copied_damage,
				building.get_attack_range_world(),
				building.get_projectile_length_world(),
				building.get_projectile_width_world(),
				building.get_attack_color().lerp(copy_mirror_definition.projection_tint, 0.55),
				building.get_projectile_model_asset(),
				building,
				building.get_missile_configuration(),
				attack_effects
			)
			if copied_missile != null:
				attack_mirrored.emit(projection, attack_kind)
		elif (
			attack_kind == &"projectile"
			and projection.payload.copy_kind in [&"arrow_tower", &"crossbow_tower", &"mace_tower"]
		):
			var projectile := MirrorProjectionProjectileScript.new()
			_combat_manager.add_child(projectile)
			projectile.configure(
				_combat_manager,
				building,
				start,
				end,
				building.get_projectile_speed_world(),
				copied_damage,
				building.get_projectile_length_world(),
				building.get_projectile_width_world(),
				building.get_attack_color().lerp(copy_mirror_definition.projection_tint, 0.55),
				building.get_projectile_model_asset(),
				building.get_attack_range_world(),
				_combat_manager.get_projectile_reflection_resolver(),
				true,
				copied_penetration,
				Callable(self, "trace_ballistic_blocker"),
				attack_effects
			)
			attack_mirrored.emit(projection, attack_kind)
		elif (
			attack_kind == &"directional_projectile"
			and projection.payload.copy_kind in [&"arrow_tower", &"crossbow_tower", &"mace_tower"]
		):
			var directional_projectile := MirrorProjectionProjectileScript.new()
			_combat_manager.add_child(directional_projectile)
			directional_projectile.configure(
				_combat_manager,
				building,
				start,
				end,
				building.get_projectile_speed_world(),
				copied_damage,
				building.get_projectile_length_world(),
				building.get_projectile_width_world(),
				building.get_attack_color().lerp(copy_mirror_definition.projection_tint, 0.55),
				building.get_projectile_model_asset(),
				building.get_attack_range_world(),
				_combat_manager.get_projectile_reflection_resolver(),
				true,
				copied_penetration,
				Callable(self, "trace_ballistic_blocker"),
				attack_effects
			)
			attack_mirrored.emit(projection, attack_kind)
		elif attack_kind == &"pulse_laser" and projection.payload.copy_kind == &"pulse_laser_tower":
			if _get_pulse_overdrive_effect(projection.payload) != null:
				continue
			var direction := end - start
			if direction.length_squared() <= 0.000001:
				continue
			var pulse_beam := _combat_manager.spawn_pulse_laser(
				start,
				direction.normalized(),
				copied_damage,
				building.get_attack_range_world(),
				building.get_pulse_laser_width_world(),
				building.get_pulse_laser_emission_energy(),
				building.get_pulse_laser_fade_in_time(),
				building.get_pulse_laser_hold_time(),
				building.get_pulse_laser_fade_out_time(),
				building.get_pulse_laser_reflection_colors(),
				building.get_pulse_laser_reflect_max(),
				building,
				attack_effects
			)
			if pulse_beam != null:
				attack_mirrored.emit(projection, attack_kind)
		elif attack_kind == &"laser" and projection.payload.copy_kind == &"laser_tower":
			var projected_laser_direction := end - start
			if projected_laser_direction.length_squared() <= 0.000001:
				continue
			var source_damage_per_second := building.get_laser_damage_per_second()
			var damage_per_second := source_damage_per_second * copy_damage_multiplier
			var duration := damage / source_damage_per_second if source_damage_per_second > 0.0 else 0.0
			var propagation_distance := projection.advance_laser_propagation(
				start,
				projected_laser_direction,
				duration,
				building.get_attack_range_world(),
				building.get_laser_propagation_speed_world()
			)
			var path: Dictionary = LaserAttackStrategyScript.trace_laser_path(
				building,
				_combat_manager,
				start,
				projected_laser_direction,
				propagation_distance,
				projection.payload.penetration_bonus,
				attack_effects
			)
			if path.get("termination", &"none") in [&"enemy", &"stuff"]:
				projection.clamp_laser_propagation(
					LaserAttackStrategyScript.get_path_length(path)
				)
			projection.show_laser_path(
				path.get("segments", []),
				path.get("endpoint", start)
			)
			projection.set_laser_reflection_damage_multiplier(
				LaserAttackStrategyScript.get_path_damage_multiplier(path)
			)
			projection.set_laser_burst_target(
				LaserAttackStrategyScript.get_first_hit_position(path)
			)
			LaserAttackStrategyScript.apply_continuous_hits(
				building,
				path,
				damage_per_second,
				duration,
				false
			)
			if ice_event_count > 0:
				var ice_effect := attack_effects.get_effect_resource(&"ice_copy_burst")
				var burst_target := projection.get_laser_burst_target()
				if ice_effect != null and bool(burst_target.get("hit", false)):
					for _event_index in range(ice_event_count):
						ice_effect.call(
							"apply_copy_burst",
							building,
							_combat_manager,
							burst_target.get("position", start),
							projection.payload.copy_upgrade_count,
							copy_damage_multiplier
								* projection.get_laser_reflection_damage_multiplier()
						)
			attack_mirrored.emit(projection, attack_kind)

func _on_building_placed(building: Building) -> void:
	_connect_attack_source(building)
	rebuild_now()

func _on_building_removed(building: Building) -> void:
	_disconnect_attack_source(building)
	queue_rebuild()

func _on_building_upgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	rebuild_now()


func _on_building_relocated(
	_building: Building,
	_previous_cell: Vector3i,
	_previous_edge_id: String
) -> void:
	rebuild_now()


func _on_building_preview_updated(building: Building) -> void:
	_refresh_building_preview_projections(building)


func _on_building_preview_cleared() -> void:
	_clear_building_preview_projections()
	building_preview_projections_rebuilt.emit(0)

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	rebuild_now()

func _on_obstacle_destroyed(_cell: Vector3i) -> void:
	queue_rebuild()

func _on_definition_changed() -> void:
	_sync_attack_effect_runtime_limits()
	var copy_duration := get_placement_cooldown_duration(MirrorPlacementData.MirrorKind.COPY)
	_set_placement_cooldown_remaining(
		MirrorPlacementData.MirrorKind.COPY,
		copy_duration if get_placement_cooldown_remaining(MirrorPlacementData.MirrorKind.COPY) <= 0.000001 else minf(
			get_placement_cooldown_remaining(MirrorPlacementData.MirrorKind.COPY),
			copy_duration
		)
	)
	var reflect_duration := get_placement_cooldown_duration(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT)
	_set_placement_cooldown_remaining(
		MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT,
		reflect_duration if get_placement_cooldown_remaining(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT) <= 0.000001 else minf(
			get_placement_cooldown_remaining(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT),
			reflect_duration
		)
	)
	_emit_placement_cooldown_changed(MirrorPlacementData.MirrorKind.COPY)
	_emit_placement_cooldown_changed(MirrorPlacementData.MirrorKind.PROJECTILE_REFLECT)
	for mirror in get_mirrors():
		mirror.refresh_visual()
		mirror_changed.emit(mirror)
	if _preview_mirror != null and is_instance_valid(_preview_mirror):
		_preview_mirror.refresh_visual()
	rebuild_now()

func _on_mirror_side_changed(mirror: CopyMirror) -> void:
	rebuild_now()
	mirror_changed.emit(mirror)

func _on_mirror_tree_exited(mirror: CopyMirror) -> void:
	if mirror == null or not _mirrors.has(mirror.edge_id) or _mirrors[mirror.edge_id] != mirror:
		_mirror_exit_callbacks.erase(mirror)
		return
	_mirrors.erase(mirror.edge_id)
	if _edge_occupancy_registry != null:
		_edge_occupancy_registry.unregister(mirror.edge_id, mirror)
	if _resource_manager != null:
		_resource_manager.unregister_mirror(_get_mirror_kind(mirror))
	if _selected_mirror == mirror:
		select_mirror(null)
	_mirror_exit_callbacks.erase(mirror)
	mirror_removed.emit(mirror)
	queue_rebuild()

func _disconnect_mirror_exit(mirror: CopyMirror) -> void:
	if mirror == null or not is_instance_valid(mirror):
		_mirror_exit_callbacks.erase(mirror)
		return
	if _mirror_exit_callbacks.has(mirror):
		var callback: Callable = _mirror_exit_callbacks[mirror]
		if mirror.tree_exited.is_connected(callback):
			mirror.tree_exited.disconnect(callback)
	_mirror_exit_callbacks.erase(mirror)

func _on_level_loaded(_level_resource: LevelResource) -> void:
	reset_placement_cooldowns()
	clear_mirrors(true)


func _on_stuff_loaded(_level_resource: LevelResource) -> void:
	queue_rebuild()


func _on_stuff_changed(_cell: Vector3i) -> void:
	queue_rebuild()

func _disconnect_dependencies() -> void:
	_disconnect_attack_sources()
	_disconnect_stuff_manager()
	_disconnect_definition_signals()
	if _combat_manager != null:
		_combat_manager.clear_projectile_reflection_resolver(self)
		_combat_manager.clear_projectile_blocker_resolver(self)
	if _building_manager != null:
		if _building_manager.building_placed.is_connected(_on_building_placed):
			_building_manager.building_placed.disconnect(_on_building_placed)
		if _building_manager.building_removed.is_connected(_on_building_removed):
			_building_manager.building_removed.disconnect(_on_building_removed)
		if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
			_building_manager.building_upgraded.disconnect(_on_building_upgraded)
		if _building_manager.building_relocated.is_connected(_on_building_relocated):
			_building_manager.building_relocated.disconnect(_on_building_relocated)
		if _building_manager.preview_updated.is_connected(_on_building_preview_updated):
			_building_manager.preview_updated.disconnect(_on_building_preview_updated)
		if _building_manager.preview_cleared.is_connected(_on_building_preview_cleared):
			_building_manager.preview_cleared.disconnect(_on_building_preview_cleared)
	if _tile_manager != null:
		if _tile_manager.level_loaded.is_connected(_on_level_loaded):
			_tile_manager.level_loaded.disconnect(_on_level_loaded)
		if _tile_manager.tile_changed.is_connected(_on_tile_changed):
			_tile_manager.tile_changed.disconnect(_on_tile_changed)
		if _tile_manager.obstacle_destroyed.is_connected(_on_obstacle_destroyed):
			_tile_manager.obstacle_destroyed.disconnect(_on_obstacle_destroyed)


func _disconnect_stuff_manager() -> void:
	if _stuff_manager == null:
		return
	var loaded_callback := Callable(self, "_on_stuff_loaded")
	if _stuff_manager.is_connected(&"stuff_loaded", loaded_callback):
		_stuff_manager.disconnect(&"stuff_loaded", loaded_callback)
	var changed_callback := Callable(self, "_on_stuff_changed")
	if _stuff_manager.is_connected(&"stuff_changed", changed_callback):
		_stuff_manager.disconnect(&"stuff_changed", changed_callback)
