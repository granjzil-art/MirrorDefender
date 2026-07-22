## Pure read-only model builder used by TileInspectionService.
class_name TileInspectionModelBuilder
extends RefCounted

const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

var _grid: GridManager
var _tile_manager: TileManager
var _building_manager: BuildingManager
var _mirror_manager: MirrorManager
var _tile_effect_system: TileEffectSystem


func configure(
	grid_manager: GridManager,
	tile_manager: TileManager,
	building_manager: BuildingManager,
	mirror_manager: MirrorManager,
	tile_effect_system: TileEffectSystem
) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager
	_building_manager = building_manager
	_mirror_manager = mirror_manager
	_tile_effect_system = tile_effect_system


## Returns `{has_content, cell, selected_edge_id, terrain_name, height_level,
## allows_tile_building, allows_edge_building, entries}`. Entries are already
## filtered by their object-level visibility policy and contain adaptive field
## switches in addition to their read-only lines.
func inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary:
	if _grid == null or _tile_manager == null or not _grid.is_in_bounds(cell):
		return empty_model()
	var tile: TileCellData = _tile_manager.get_tile(cell)
	if tile == null:
		return empty_model()
	var entries: Array[Dictionary] = []
	var occupant: Node = _tile_manager.get_occupant(cell)
	if occupant is Building:
		_append_entry(entries, _make_building_entry(occupant as Building))
	var effect: TileEffect = tile.get_effect()
	if effect != null or tile.is_destructible() or tile.get_visual_kind() != TileDefinition.VisualKind.NONE:
		_append_entry(entries, _make_tile_element_entry(tile, effect))
	_append_adjacent_edge_entries(cell, entries)
	if _mirror_manager != null:
		for projection in _mirror_manager.get_projections(cell):
			if projection.payload != null and projection.payload.is_source_valid():
				_append_entry(entries, _make_projection_entry(projection))
	return {
		"has_content": not entries.is_empty(),
		"cell": cell,
		"selected_edge_id": selected_edge_id,
		"terrain_name": tile.get_display_name(),
		"height_level": tile.height_level,
		"allows_tile_building": tile.allows_tile_building(),
		"allows_edge_building": tile.allows_edge_building(),
		"entries": entries,
	}


func empty_model() -> Dictionary:
	return {
		"has_content": false,
		"cell": Vector3i.ZERO,
		"selected_edge_id": "",
		"terrain_name": "",
		"height_level": 0,
		"allows_tile_building": false,
		"allows_edge_building": false,
		"entries": [],
	}


func _append_entry(entries: Array[Dictionary], entry: Dictionary) -> void:
	if not entry.is_empty():
		entries.append(entry)


func _append_adjacent_edge_entries(cell: Vector3i, entries: Array[Dictionary]) -> void:
	if _grid == null:
		return
	for edge_index in range(_grid.edge_count()):
		var edge_id := _grid.canonical_edge_id(cell, edge_index)
		var edge_building := _building_manager.get_edge_building(edge_id) if _building_manager != null else null
		if edge_building != null:
			_append_entry(entries, _make_building_entry(edge_building))
			continue
		var mirror := _mirror_manager.get_mirror(edge_id) if _mirror_manager != null else null
		if mirror != null:
			_append_entry(entries, _make_mirror_entry(mirror))


func _make_building_entry(building: Building) -> Dictionary:
	var definition: BuildingDefinition = building.definition
	var config: InspectionDisplayConfigScript = definition.inspection_display if definition != null else null
	if not _is_object_visible(config):
		return {}
	var lines: Array[String] = []
	if _shows(config, &"show_level"):
		lines.append("等级：L%d / L%d" % [building.level, building.get_max_level()])
	if building.is_edge_placement():
		if _shows(config, &"show_position"):
			var connector := "↔" if building.is_bidirectional_edge_blocker() else "→"
			lines.append("边方向：%s %s %s" % [str(building.cell), connector, str(building.edge_to_cell)])
			lines.append("物理边：%s" % building.edge_id)
	elif _shows(config, &"show_position"):
		lines.append("格位置：%s" % str(building.cell))
	if not building.is_edge_placement() and _shows(config, &"show_orientation"):
		lines.append("朝向：%d / %d" % [building.facing_index + 1, building.get_facing_slot_count()])
	var stats: BuildingLevelStats = building.get_level_stats()
	_append_building_gameplay_lines(lines, building, config, false)
	var icon: Texture2D = definition.card_icon if definition != null else null
	var accent := stats.tower_color if stats != null else Color(0.35, 0.75, 1.0)
	var fallback_name := definition.display_name if definition != null else "建筑"
	return _make_entry(
		&"edge_building" if building.is_edge_placement() else &"building",
		_resolve_name(config, fallback_name),
		"边建筑" if building.is_edge_placement() else "块建筑",
		"实体", icon, accent, lines, config, _building_description(definition)
	)


func _make_mirror_entry(mirror: CopyMirror) -> Dictionary:
	var definition: CopyMirrorDefinition = mirror.definition
	var config: InspectionDisplayConfigScript = definition.inspection_display if definition != null else null
	if not _is_object_visible(config):
		return {}
	var lines: Array[String] = []
	if _shows(config, &"show_position"):
		lines.append("物理边：%s" % mirror.edge_id)
		lines.append("两侧：%s ↔ %s" % [str(mirror.from_cell), str(mirror.to_cell)])
	if _shows(config, &"show_orientation"):
		lines.append("生效侧：%s" % str(mirror.get_active_cell()))
	var fallback_name := definition.display_name if definition != null else "复制镜"
	return _make_entry(&"mirror", _resolve_name(config, fallback_name), "边建筑", "实体",
		definition.card_icon if definition != null else null,
		definition.mirror_color if definition != null else Color(0.2, 0.78, 1.0),
		lines, config, "复制镜面法线方向最近非空地块上的全部对象到对称位置。")


func _make_tile_element_entry(tile: TileCellData, effect: TileEffect) -> Dictionary:
	var definition: TileDefinition = tile.definition
	var config: InspectionDisplayConfigScript = definition.inspection_display if definition != null else null
	if not _is_object_visible(config):
		return {}
	var lines: Array[String] = []
	if _shows(config, &"show_position"):
		lines.append("格位置：%s" % str(tile.cell))
	if _shows(config, &"show_height"):
		lines.append("高度档：%d" % tile.height_level)
	if _shows(config, &"show_build_permissions"):
		lines.append("块建筑：%s · 边建筑：%s" % ["允许" if tile.allows_tile_building() else "禁止", "允许" if tile.allows_edge_building() else "禁止"])
	_append_tile_effect_lines(lines, tile.cell, effect, config, false)
	return _make_entry(&"tile_element", _resolve_name(config, tile.get_display_name()), "关卡元素", "实体",
		definition.ui_icon if definition != null else null, tile.get_visual_color(), lines, config,
		_tile_description(definition, effect))


func _append_tile_effect_lines(lines: Array[String], source_cell: Vector3i, effect: TileEffect, config: InspectionDisplayConfigScript, shared: bool) -> void:
	var prefix := "共享" if shared else ""
	if effect is RockTileEffect and _shows(config, &"show_durability"):
		var obstacle: Node = _tile_manager.get_runtime_obstacle(source_cell) if _tile_manager != null else null
		if obstacle is TileObstacleRuntime:
			lines.append("%s耐久：%d / %d" % [prefix, ceili(obstacle.current_durability), ceili(obstacle.max_durability)])
	elif effect is SpikeTileEffect and _shows(config, &"show_combat"):
		var spike: SpikeTileEffect = effect
		lines.append("持续伤害：%.1f/s · %s护甲" % [spike.damage_per_second, "忽略" if spike.ignores_armor else "计算"])
	elif effect is VoidTileEffect:
		var void_effect: VoidTileEffect = effect
		if _shows(config, &"show_capacity"):
			var current_fill := _tile_effect_system.get_void_current_fill(source_cell) if _tile_effect_system != null else 0
			lines.append("%s装填：%d / %d" % [prefix, current_fill, void_effect.max_capacity])
		if not shared and _shows(config, &"show_timing"):
			lines.append("吞噬间隔 %.2fs · 每点恢复 %.2fs" % [void_effect.swallow_interval, void_effect.recovery_seconds_per_point])
	if effect != null and _shows(config, &"show_airborne_effect"):
		lines.append("对空中敌人：%s" % ("有效" if effect.affects_airborne else "无效"))


func _make_projection_entry(projection: MirrorProjection) -> Dictionary:
	var payload: MirrorCopyPayload = projection.payload
	var source_building: Building = payload.root_source as Building
	var source_tile: TileCellData = _tile_manager.get_tile(payload.root_source_cell) if _tile_manager != null else null
	var config: InspectionDisplayConfigScript
	if source_building != null and source_building.definition != null:
		config = source_building.definition.inspection_display
	elif source_tile != null and source_tile.definition != null:
		config = source_tile.definition.inspection_display
	if not _is_object_visible(config):
		return {}
	var producing_mirror := String(payload.lineage.back()) if not payload.lineage.is_empty() else "未知"
	var lines: Array[String] = []
	if _shows(config, &"show_position"):
		lines.append("投影格：%s" % str(payload.projected_cell))
	if _shows(config, &"show_projection_source"):
		lines.append("根源格：%s" % str(payload.root_source_cell))
	if _shows(config, &"show_producing_mirror"):
		lines.append("产生镜子：%s" % producing_mirror)
	if _shows(config, &"show_copy_chain"):
		lines.append("复制链深度：%d" % payload.chain_depth)
	var icon: Texture2D
	var category := "关卡元素"
	var description := _tile_description(source_tile.definition if source_tile != null else null, payload.tile_effect)
	if source_building != null:
		category = "边建筑" if source_building.is_edge_placement() else "块建筑"
		icon = source_building.definition.card_icon if source_building.definition != null else null
		description = _building_description(source_building.definition)
		if _shows(config, &"show_level"):
			lines.append("等级：L%d / L%d" % [source_building.level, source_building.get_max_level()])
		if not source_building.is_path_blocker() and _shows(config, &"show_orientation"):
			lines.append("源逻辑朝向：%d / %d" % [source_building.facing_index + 1, source_building.get_facing_slot_count()])
		_append_building_gameplay_lines(lines, source_building, config, true)
	else:
		_append_tile_effect_lines(lines, payload.root_source_cell, payload.tile_effect, config, true)
	if icon == null and source_tile != null and source_tile.definition != null:
		icon = source_tile.definition.ui_icon
	var entry := _make_entry(&"projection", _resolve_name(config, payload.display_name), category, "虚像",
		icon, payload.primary_color, lines, config, description)
	entry["has_source"] = true
	entry["source_cell"] = payload.root_source_cell
	entry["mirror_edge_id"] = producing_mirror
	return entry


## Entity and projection entries share this exact gameplay-row contract so a
## copied tower never loses source combat/economy information.
func _append_building_gameplay_lines(
	lines: Array[String],
	building: Building,
	config: InspectionDisplayConfigScript,
	shared_runtime_state: bool
) -> void:
	var stats: BuildingLevelStats = building.get_level_stats()
	if building.is_path_blocker():
		if _shows(config, &"show_durability"):
			lines.append("%s耐久：%d / %d" % [
				"共享" if shared_runtime_state else "",
				ceili(building.current_durability),
				ceili(building.maximum_durability),
			])
		if stats != null and _shows(config, &"show_combat"):
			lines.append("脱战 %.1fs · 回血 %.1f/s · 反伤 %.0f%%" % [stats.regeneration_delay, stats.regeneration_per_second, stats.damage_reflection_ratio * 100.0])
	elif stats != null:
		if _shows(config, &"show_combat"):
			lines.append("索敌 %.1f · 射程 %.1f" % [stats.targeting_range, stats.attack_range])
		var attack_rate_text: String
		if building.definition != null and building.definition.kind == BuildingDefinition.Kind.LASER_TOWER:
			attack_rate_text = "DPS %.1f" % building.get_laser_damage_per_second()
		else:
			attack_rate_text = "攻速 %.2f/s" % stats.attacks_per_second
		if _shows(config, &"show_combat") and _shows(config, &"show_economy"):
			lines.append("%s · 产出 %.1f/s" % [attack_rate_text, stats.resource_per_second])
		elif _shows(config, &"show_combat"):
			lines.append(attack_rate_text)
		elif _shows(config, &"show_economy"):
			lines.append("产出 %.1f/s" % stats.resource_per_second)
	if stats != null and _shows(config, &"show_airborne_effect"):
		lines.append("对空中敌人：%s" % ("有效" if stats.affects_airborne else "无效"))


func _make_entry(kind: StringName, display_name: String, category: String, state: String,
	icon: Texture2D, accent: Color, lines: Array[String], config: InspectionDisplayConfigScript,
	fallback_description: String) -> Dictionary:
	return {
		"kind": kind,
		"name": display_name,
		"category": category,
		"state": state,
		"icon": icon,
		"accent": accent,
		"description": _resolve_description(config, fallback_description),
		"show_icon": _shows(config, &"show_icon"),
		"show_category": _shows(config, &"show_category"),
		"show_state": _shows(config, &"show_entity_state"),
		"show_description": _shows(config, &"show_function_description"),
		"lines": lines,
		"has_source": false,
		"source_cell": Vector3i.ZERO,
		"mirror_edge_id": "",
	}


func _is_object_visible(config: InspectionDisplayConfigScript) -> bool:
	return config == null or config.visible


func _shows(config: InspectionDisplayConfigScript, property: StringName) -> bool:
	return config == null or bool(config.get(property))


func _resolve_name(config: InspectionDisplayConfigScript, fallback: String) -> String:
	return config.resolve_display_name(fallback) if config != null else fallback


func _resolve_description(config: InspectionDisplayConfigScript, fallback: String) -> String:
	return config.resolve_function_description(fallback) if config != null else fallback


func _building_description(definition: BuildingDefinition) -> String:
	if definition == null:
		return "可由玩家放置、升级、旋转或删除的建筑。"
	match definition.kind:
		BuildingDefinition.Kind.ARROW_TOWER:
			return "自动索敌并发射投射物，攻击索敌范围和射程内的敌人。"
		BuildingDefinition.Kind.LASER_TOWER:
			return "沿建筑当前朝向持续发射激光，对光路上的敌人造成持续伤害。"
		BuildingDefinition.Kind.BARRIER:
			return "放置在敌人路径格上阻挡敌人，承受攻击并在脱战后恢复耐久。"
		BuildingDefinition.Kind.EDGE_BARRIER:
			return "沿地块边放置，阻挡穿越该边的近战敌人。"
	return "可由玩家放置、升级、旋转或删除的建筑。"


func _tile_description(definition: TileDefinition, effect: TileEffect) -> String:
	if effect is SpikeTileEffect:
		return "敌人停留在该格时持续受到伤害。"
	if effect is VoidTileEffect:
		return "按吞噬间隔消灭格上生命值最高且满足条件的敌人，并占用容量。"
	if effect is RockTileEffect:
		return "阻挡敌人前进；敌人优先尝试换路，无路可走时攻击石头。"
	if definition != null and definition.surface_kind == TileDefinition.SurfaceKind.DESTRUCTIBLE:
		return "清除障碍后转为允许建造的地块。"
	return "关卡中直接配置、可被检视的地块内容。"
