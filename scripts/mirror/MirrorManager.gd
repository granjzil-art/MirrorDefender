## M5 copy-mirror entry point: edge lifecycle, deterministic copy graph,
## projection overlays, preview, and synchronized attack forwarding.
class_name MirrorManager
extends Node3D

const MirrorProjectionProjectileScript := preload("res://scripts/mirror/MirrorProjectionProjectile.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Definition")
@export var copy_mirror_definition: CopyMirrorDefinition

signal mirror_placed(mirror: CopyMirror)
signal mirror_removed(mirror: CopyMirror)
signal mirror_selected(mirror: CopyMirror)
signal mirror_changed(mirror: CopyMirror)
signal placement_failed(cell: Vector3i, reason: String)
signal projections_rebuilt(count: int)
signal attack_mirrored(projection: MirrorProjection, attack_kind: StringName)
signal preview_updated(info: Dictionary)
signal preview_cleared

var _grid: GridManager
var _tile_manager: TileManager
var _resource_manager: ResourceManager
var _combat_manager: CombatManager
var _building_manager: BuildingManager
var _edge_occupancy_registry: EdgeOccupancyRegistry

var _mirrors: Dictionary = {}
var _projections: Array[MirrorProjection] = []
var _projections_by_cell: Dictionary = {}
var _selected_mirror: CopyMirror
var _next_placement_order: int = 0
var _rebuild_queued: bool = false
var _mirror_exit_callbacks: Dictionary = {}

var _preview_mirror: CopyMirror
var _preview_projections: Array[MirrorProjection] = []
var _preview_info: Dictionary = {}
var _preview_active_from_side: bool = true

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
	if copy_mirror_definition != null and not copy_mirror_definition.changed.is_connected(_on_definition_changed):
		copy_mirror_definition.changed.connect(_on_definition_changed)
	if _building_manager != null:
		_building_manager.building_placed.connect(_on_building_placed)
		_building_manager.building_removed.connect(_on_building_removed)
		_building_manager.building_upgraded.connect(_on_building_upgraded)
		for building in _building_manager.get_buildings():
			_connect_attack_source(building)
	if _tile_manager != null:
		_tile_manager.level_loaded.connect(_on_level_loaded)
		_tile_manager.tile_changed.connect(_on_tile_changed)
		_tile_manager.obstacle_destroyed.connect(_on_obstacle_destroyed)
	queue_rebuild()

func place_copy_mirror(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: Variant = null
) -> CopyMirror:
	var validation := validate_placement(from_cell, edge_index, true)
	if not validation.failure.is_empty():
		placement_failed.emit(from_cell, validation.failure)
		return null
	var definition := copy_mirror_definition
	var resolved_side := definition.active_from_side_by_default if active_from_side == null else bool(active_from_side)
	var mirror := CopyMirror.new()
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
	if not _resource_manager.try_register_mirror(definition.cost):
		mirror.queue_free()
		placement_failed.emit(from_cell, "资源不足或达到镜子上限")
		return null
	if _edge_occupancy_registry != null and not _edge_occupancy_registry.try_register(validation.edge_id, mirror):
		_resource_manager.unregister_mirror(definition.cost)
		mirror.queue_free()
		placement_failed.emit(from_cell, "该物理边已被占用")
		return null
	mirror.placement_order = _next_placement_order
	_next_placement_order += 1
	mirror.side_changed.connect(_on_mirror_side_changed)
	var exit_callback := _on_mirror_tree_exited.bind(mirror)
	mirror.tree_exited.connect(exit_callback)
	_mirror_exit_callbacks[mirror] = exit_callback
	_mirrors[validation.edge_id] = mirror
	select_mirror(mirror)
	rebuild_now()
	mirror_placed.emit(mirror)
	return mirror

func validate_placement(from_cell: Vector3i, edge_index: int, check_economy: bool = true) -> Dictionary:
	var result := {"failure": "", "to_cell": Vector3i.ZERO, "edge_id": ""}
	if not feature_enabled or copy_mirror_definition == null:
		result.failure = "复制镜系统或配置未启用"
		return result
	var config_errors := copy_mirror_definition.validate_configuration()
	if not config_errors.is_empty():
		result.failure = config_errors[0]
		return result
	if _grid == null or _tile_manager == null or _resource_manager == null or _combat_manager == null:
		result.failure = "复制镜系统依赖尚未注入"
		return result
	if not _grid.is_in_bounds(from_cell) or edge_index < 0 or edge_index >= _grid.edge_count():
		result.failure = "目标边位于地图外"
		return result
	var to_cell := _grid.neighbor_across_edge(from_cell, edge_index)
	result.to_cell = to_cell
	if not _grid.is_in_bounds(to_cell):
		result.failure = "镜子只能放在两个有效地块之间"
		return result
	if not _tile_manager.allows_edge_building(from_cell) or not _tile_manager.allows_edge_building(to_cell):
		result.failure = "该边两侧的地块未同时允许边建筑"
		return result
	var edge_id := _grid.canonical_edge_id(from_cell, edge_index)
	result.edge_id = edge_id
	if _get_edge_occupant(edge_id) != null:
		result.failure = "该物理边已被占用"
		return result
	if _has_enemy_on_adjacent_cell(from_cell, to_cell):
		result.failure = "敌人当前占据该边的相邻格"
		return result
	if check_economy:
		if not _resource_manager.can_add_mirror():
			result.failure = "已达到镜子上限"
		elif not _resource_manager.can_afford(copy_mirror_definition.cost):
			result.failure = "主资源不足"
	return result

func remove_selected_mirror() -> bool:
	return remove_mirror(get_selected_mirror())

func remove_mirror(mirror: CopyMirror, refund: float = -1.0) -> bool:
	if mirror == null or not is_instance_valid(mirror) or not _mirrors.has(mirror.edge_id):
		return false
	var resolved_refund := copy_mirror_definition.refund if refund < 0.0 else refund
	_mirrors.erase(mirror.edge_id)
	if _edge_occupancy_registry != null:
		_edge_occupancy_registry.unregister(mirror.edge_id, mirror)
	if _resource_manager != null:
		_resource_manager.unregister_mirror(resolved_refund)
	if _selected_mirror == mirror:
		select_mirror(null)
	if mirror.side_changed.is_connected(_on_mirror_side_changed):
		mirror.side_changed.disconnect(_on_mirror_side_changed)
	_disconnect_mirror_exit(mirror)
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
			_resource_manager.unregister_mirror(0.0)
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

func select_at_edge(edge_id: String) -> CopyMirror:
	var occupant := _get_edge_occupant(edge_id)
	var mirror: CopyMirror = occupant if occupant is CopyMirror else null
	select_mirror(mirror)
	return mirror

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

func get_projections(cell: Variant = null) -> Array[MirrorProjection]:
	if cell is Vector3i:
		var by_cell: Array[MirrorProjection] = []
		for raw_projection in _projections_by_cell.get(cell, []):
			if raw_projection is MirrorProjection and is_instance_valid(raw_projection):
				by_cell.append(raw_projection)
		return by_cell
	return _projections.duplicate()

func get_projected_effects(cell: Vector3i) -> Array[TileEffect]:
	var effects: Array[TileEffect] = []
	for projection in get_projections(cell):
		var effect := projection.get_tile_effect()
		if effect != null:
			effects.append(effect)
	return effects

func blocks_enemy_navigation(cell: Vector3i, target: Node = null) -> bool:
	for effect in get_projected_effects(cell):
		if effect.blocks_enemy_navigation(target):
			return true
	return false

func resolve_projected_blocker(cell: Vector3i, target: Node = null) -> Node:
	for projection in get_projections(cell):
		if projection.payload.copy_kind == &"barrier" and projection.is_structure_alive() and projection.affects_target(target):
			return projection
	return null

func update_preview(from_cell: Vector3i, edge_index: int) -> bool:
	var validation := validate_placement(from_cell, edge_index, false)
	if not validation.failure.is_empty():
		clear_preview()
		return false
	var edge_id: String = validation.edge_id
	if _preview_mirror == null or _preview_mirror.edge_id != edge_id or _preview_mirror.from_cell != from_cell:
		clear_preview()
		_preview_mirror = CopyMirror.new()
		add_child(_preview_mirror)
		_preview_mirror.configure(
			copy_mirror_definition,
			from_cell,
			validation.to_cell,
			edge_index,
			edge_id,
			_grid,
			_tile_manager,
			_preview_active_from_side,
			true
		)
	_refresh_preview_projection()
	return true

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
	_clear_preview_projections()
	_preview_info = {}
	if had_preview:
		preview_cleared.emit()

func get_preview_info() -> Dictionary:
	return _preview_info.duplicate(true)

func queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild_now")

func rebuild_now() -> void:
	_rebuild_queued = false
	_clear_projection_nodes()
	if not feature_enabled or copy_mirror_definition == null or _grid == null or _tile_manager == null:
		projections_rebuilt.emit(0)
		return
	var payloads := _calculate_projection_payloads(get_mirrors())
	var stack_counts: Dictionary = {}
	for payload in payloads:
		if not payload.is_source_valid():
			continue
		var stack_index := int(stack_counts.get(payload.projected_cell, 0))
		stack_counts[payload.projected_cell] = stack_index + 1
		var projection := MirrorProjection.new()
		add_child(projection)
		projection.configure(payload, _grid, _tile_manager, copy_mirror_definition, stack_index)
		_projections.append(projection)
		if not _projections_by_cell.has(payload.projected_cell):
			_projections_by_cell[payload.projected_cell] = []
		_projections_by_cell[payload.projected_cell].append(projection)
	projections_rebuilt.emit(_projections.size())
	if _preview_mirror != null:
		_refresh_preview_projection()

func _calculate_projection_payloads(mirrors: Array[CopyMirror]) -> Array[MirrorCopyPayload]:
	var base_content := _build_base_content_map()
	var current: Array[MirrorCopyPayload] = []
	var maximum_passes := maxi(2, copy_mirror_definition.copy_chain_max * maxi(1, mirrors.size()) + 2)
	for _pass_index in range(maximum_passes):
		var content := _duplicate_content_map(base_content)
		for payload in current:
			_append_content(content, payload.projected_cell, payload)
		var next: Array[MirrorCopyPayload] = []
		var claimed_targets: Dictionary = {}
		for mirror in mirrors:
			var group := _build_projection_group(mirror, content, claimed_targets)
			if not group.is_empty():
				claimed_targets[group[0].projected_cell] = true
				next.append_array(group)
		if _payload_signature(next) == _payload_signature(current):
			return next
		current = next
	return current

func _build_projection_group(
	mirror: CopyMirror,
	content: Dictionary,
	claimed_targets: Dictionary
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
		if not copy_mirror_definition.projection_ignores_occupancy:
			if _building_manager.get_building(pair.target_cell) != null or claimed_targets.has(pair.target_cell):
				return result
		for source_payload in eligible:
			result.append(source_payload.copy_through(mirror.edge_id, pair.target_cell, endpoints[0], endpoints[1]))
		return result
	return result

func _build_base_content_map() -> Dictionary:
	var content: Dictionary = {}
	if _building_manager != null:
		for building in _building_manager.get_buildings():
			var kind := building.get_copy_kind()
			if kind.is_empty():
				continue
			var payload := MirrorCopyPayload.new()
			payload.stable_key = "building:%d" % building.get_instance_id()
			payload.copy_kind = kind
			payload.display_name = building.get_copy_display_name()
			payload.source_cell = building.cell
			payload.projected_cell = building.cell
			payload.root_source = building
			payload.primary_color = building.get_copy_color()
			_append_content(content, building.cell, payload)
	if _tile_manager != null:
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
			payload.projected_cell = tile.cell
			payload.tile_effect = effect
			payload.primary_color = effect.get_copy_color()
			_append_content(content, tile.cell, payload)
	return content

func _refresh_preview_projection() -> void:
	_clear_preview_projections()
	if _preview_mirror == null or not is_instance_valid(_preview_mirror):
		return
	var content := _build_base_content_map()
	for projection in _projections:
		if projection.payload != null and projection.payload.is_source_valid():
			_append_content(content, projection.payload.projected_cell, projection.payload)
	var group := _build_projection_group(_preview_mirror, content, {})
	_preview_info = {
		"edge_id": _preview_mirror.edge_id,
		"active_cell": _preview_mirror.get_active_cell(),
		"has_source": not group.is_empty(),
		"source_cell": group[0].source_cell if not group.is_empty() else Vector3i.ZERO,
		"target_cell": group[0].projected_cell if not group.is_empty() else Vector3i.ZERO,
		"types": [],
		"warning": "未找到可复制的非空地块，仍可放置" if group.is_empty() else "",
	}
	var stack_index := 0
	for payload in group:
		_preview_info.types.append(payload.display_name)
		var projection := MirrorProjection.new()
		add_child(projection)
		projection.configure(payload, _grid, _tile_manager, copy_mirror_definition, stack_index, true)
		_preview_projections.append(projection)
		stack_index += 1
	preview_updated.emit(_preview_info)

func _clear_projection_nodes() -> void:
	for projection in _projections:
		if is_instance_valid(projection):
			projection.queue_free()
	_projections.clear()
	_projections_by_cell.clear()

func _clear_preview_projections() -> void:
	for projection in _preview_projections:
		if is_instance_valid(projection):
			projection.queue_free()
	_preview_projections.clear()

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

func _has_enemy_on_adjacent_cell(from_cell: Vector3i, to_cell: Vector3i) -> bool:
	for target in _combat_manager.get_targets():
		var cell := _grid.world_to_cell(target.global_position)
		if cell == from_cell or cell == to_cell:
			return true
	return false

func _connect_attack_source(building: Building) -> void:
	if building != null and not building.copy_attack_triggered.is_connected(_on_copy_attack_triggered):
		building.copy_attack_triggered.connect(_on_copy_attack_triggered)

func _on_copy_attack_triggered(
	building: Building,
	attack_kind: StringName,
	world_start: Vector3,
	world_end: Vector3,
	damage: float
) -> void:
	if _combat_manager == null or not is_instance_valid(building):
		return
	for projection in _projections:
		if not is_instance_valid(projection) or projection.payload.root_source != building:
			continue
		var start := projection.payload.transform_point(world_start)
		var end := projection.payload.transform_point(world_end)
		if attack_kind == &"projectile" and projection.payload.copy_kind == &"arrow_tower":
			var projectile := MirrorProjectionProjectileScript.new()
			_combat_manager.add_child(projectile)
			projectile.configure(
				_combat_manager,
				building,
				start,
				end,
				building.get_projectile_speed_world(),
				damage,
				building.get_projectile_length_world(),
				building.get_projectile_width_world(),
				building.get_attack_color().lerp(copy_mirror_definition.projection_tint, 0.55)
			)
			attack_mirrored.emit(projection, attack_kind)
		elif attack_kind == &"laser" and projection.payload.copy_kind == &"laser_tower":
			projection.show_laser(end)
			for target in _combat_manager.get_targets_on_segment(start, end):
				if building.affects_target(target):
					target.take_damage(damage)
			attack_mirrored.emit(projection, attack_kind)

func _on_building_placed(building: Building) -> void:
	_connect_attack_source(building)
	rebuild_now()

func _on_building_removed(_building: Building) -> void:
	queue_rebuild()

func _on_building_upgraded(_building: Building, _previous_level: int, _new_level: int) -> void:
	rebuild_now()

func _on_tile_changed(_cell: Vector3i, _tile: TileCellData) -> void:
	rebuild_now()

func _on_obstacle_destroyed(_cell: Vector3i) -> void:
	queue_rebuild()

func _on_definition_changed() -> void:
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
		_resource_manager.unregister_mirror(0.0)
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
	clear_mirrors(true)

func _disconnect_dependencies() -> void:
	if copy_mirror_definition != null and copy_mirror_definition.changed.is_connected(_on_definition_changed):
		copy_mirror_definition.changed.disconnect(_on_definition_changed)
	if _building_manager != null:
		if _building_manager.building_placed.is_connected(_on_building_placed):
			_building_manager.building_placed.disconnect(_on_building_placed)
		if _building_manager.building_removed.is_connected(_on_building_removed):
			_building_manager.building_removed.disconnect(_on_building_removed)
		if _building_manager.building_upgraded.is_connected(_on_building_upgraded):
			_building_manager.building_upgraded.disconnect(_on_building_upgraded)
	if _tile_manager != null:
		if _tile_manager.level_loaded.is_connected(_on_level_loaded):
			_tile_manager.level_loaded.disconnect(_on_level_loaded)
		if _tile_manager.tile_changed.is_connected(_on_tile_changed):
			_tile_manager.tile_changed.disconnect(_on_tile_changed)
		if _tile_manager.obstacle_destroyed.is_connected(_on_obstacle_destroyed):
			_tile_manager.obstacle_destroyed.disconnect(_on_obstacle_destroyed)
