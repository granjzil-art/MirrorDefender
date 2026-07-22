## Pure read-only model builder used by TileInspectionService.
class_name TileInspectionModelBuilder
extends RefCounted

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
## allows_tile_building, allows_edge_building, entries}`. Each entry contains
## `{kind, name, category, state, icon, accent, lines, has_source,
## source_cell, mirror_edge_id}` and never exposes a mutating callback.
func inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary:
	if _grid == null or _tile_manager == null or not _grid.is_in_bounds(cell):
		return empty_model()
	var tile: TileCellData = _tile_manager.get_tile(cell)
	if tile == null:
		return empty_model()
	var entries: Array[Dictionary] = []
	var occupant: Node = _tile_manager.get_occupant(cell)
	if occupant is Building:
		entries.append(_make_building_entry(occupant as Building))
	var effect: TileEffect = tile.get_effect()
	if effect != null or tile.is_destructible() or tile.get_visual_kind() != TileDefinition.VisualKind.NONE:
		entries.append(_make_tile_element_entry(tile, effect))
	_append_adjacent_edge_entries(cell, entries)
	if _mirror_manager != null:
		for projection in _mirror_manager.get_projections(cell):
			if projection.payload != null and projection.payload.is_source_valid():
				entries.append(_make_projection_entry(projection))
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


func _append_adjacent_edge_entries(cell: Vector3i, entries: Array[Dictionary]) -> void:
	if _grid == null:
		return
	for edge_index in range(_grid.edge_count()):
		var edge_id := _grid.canonical_edge_id(cell, edge_index)
		var edge_building := _building_manager.get_edge_building(edge_id) if _building_manager != null else null
		if edge_building != null:
			entries.append(_make_building_entry(edge_building))
			continue
		var mirror := _mirror_manager.get_mirror(edge_id) if _mirror_manager != null else null
		if mirror != null:
			entries.append(_make_mirror_entry(mirror))


func _make_building_entry(building: Building) -> Dictionary:
	var lines: Array[String] = []
	lines.append("等级：L%d / L%d" % [building.level, building.get_max_level()])
	if building.is_edge_placement():
		var connector := "↔" if building.is_bidirectional_edge_blocker() else "→"
		lines.append("边方向：%s %s %s" % [str(building.cell), connector, str(building.edge_to_cell)])
		lines.append("物理边：%s" % building.edge_id)
	else:
		lines.append("格位置：%s" % str(building.cell))
		lines.append("朝向：%d / %d" % [building.facing_index + 1, building.get_facing_slot_count()])
	var stats: BuildingLevelStats = building.get_level_stats()
	if building.is_path_blocker():
		lines.append("耐久：%d / %d" % [ceili(building.current_durability), ceili(building.maximum_durability)])
		if stats != null:
			lines.append("脱战 %.1fs · 回血 %.1f/s · 反伤 %.0f%%" % [stats.regeneration_delay, stats.regeneration_per_second, stats.damage_reflection_ratio * 100.0])
	elif stats != null:
		lines.append("索敌 %.1f · 射程 %.1f" % [stats.targeting_range, stats.attack_range])
		lines.append("攻速 %.2f/s · 产出 %.1f/s" % [stats.attacks_per_second, stats.resource_per_second])
	var icon: Texture2D = building.definition.card_icon if building.definition != null else null
	var accent := stats.tower_color if stats != null else Color(0.35, 0.75, 1.0)
	return _make_entry(&"edge_building" if building.is_edge_placement() else &"building", building.definition.display_name if building.definition != null else "建筑", "边建筑" if building.is_edge_placement() else "块建筑", "实体", icon, accent, lines)


func _make_mirror_entry(mirror: CopyMirror) -> Dictionary:
	var lines: Array[String] = ["物理边：%s" % mirror.edge_id, "两侧：%s ↔ %s" % [str(mirror.from_cell), str(mirror.to_cell)], "生效侧：%s" % str(mirror.get_active_cell())]
	var definition: CopyMirrorDefinition = mirror.definition
	return _make_entry(&"mirror", definition.display_name if definition != null else "复制镜", "边建筑", "实体", definition.card_icon if definition != null else null, definition.mirror_color if definition != null else Color(0.2, 0.78, 1.0), lines)


func _make_tile_element_entry(tile: TileCellData, effect: TileEffect) -> Dictionary:
	var lines: Array[String] = ["格位置：%s" % str(tile.cell), "高度档：%d" % tile.height_level, "块建筑：%s · 边建筑：%s" % ["允许" if tile.allows_tile_building() else "禁止", "允许" if tile.allows_edge_building() else "禁止"]]
	if effect is RockTileEffect:
		var obstacle: Node = _tile_manager.get_runtime_obstacle(tile.cell)
		if obstacle is TileObstacleRuntime:
			var rock: TileObstacleRuntime = obstacle
			lines.append("耐久：%d / %d" % [ceili(rock.current_durability), ceili(rock.max_durability)])
	elif effect is SpikeTileEffect:
		var spike: SpikeTileEffect = effect
		lines.append("持续伤害：%.1f/s · %s护甲" % [spike.damage_per_second, "忽略" if spike.ignores_armor else "计算"])
	elif effect is VoidTileEffect:
		var void_effect: VoidTileEffect = effect
		var current_fill := _tile_effect_system.get_void_current_fill(tile.cell) if _tile_effect_system != null else 0
		lines.append("装填：%d / %d" % [current_fill, void_effect.max_capacity])
		lines.append("吞噬间隔 %.2fs · 每点恢复 %.2fs" % [void_effect.swallow_interval, void_effect.recovery_seconds_per_point])
	if effect != null:
		lines.append("对空中敌人：%s" % ("有效" if effect.affects_airborne else "无效"))
	var definition: TileDefinition = tile.definition
	return _make_entry(&"tile_element", tile.get_display_name(), "关卡元素", "实体", definition.ui_icon if definition != null else null, tile.get_visual_color(), lines)


func _make_projection_entry(projection: MirrorProjection) -> Dictionary:
	var payload: MirrorCopyPayload = projection.payload
	var producing_mirror := String(payload.lineage.back()) if not payload.lineage.is_empty() else "未知"
	var lines: Array[String] = ["投影格：%s" % str(payload.projected_cell), "根源格：%s" % str(payload.root_source_cell), "产生镜子：%s" % producing_mirror, "复制链深度：%d" % payload.chain_depth]
	var icon: Texture2D
	var category := "关卡元素"
	if payload.root_source is Building:
		var source_building: Building = payload.root_source
		category = "边建筑" if source_building.is_edge_placement() else "块建筑"
		icon = source_building.definition.card_icon if source_building.definition != null else null
		lines.append("等级：L%d / L%d" % [source_building.level, source_building.get_max_level()])
		if source_building.is_path_blocker():
			lines.append("共享耐久：%d / %d" % [ceili(source_building.current_durability), ceili(source_building.maximum_durability)])
		else:
			lines.append("源逻辑朝向：%d / %d" % [source_building.facing_index + 1, source_building.get_facing_slot_count()])
	elif payload.root_source is TileObstacleRuntime:
		var obstacle: TileObstacleRuntime = payload.root_source
		lines.append("共享耐久：%d / %d" % [ceili(obstacle.current_durability), ceili(obstacle.max_durability)])
	if payload.tile_effect is VoidTileEffect:
		var void_effect: VoidTileEffect = payload.tile_effect
		var current_fill := _tile_effect_system.get_void_current_fill(payload.root_source_cell) if _tile_effect_system != null else 0
		lines.append("共享装填：%d / %d" % [current_fill, void_effect.max_capacity])
	elif payload.tile_effect is SpikeTileEffect:
		var spike: SpikeTileEffect = payload.tile_effect
		lines.append("持续伤害：%.1f/s" % spike.damage_per_second)
	if icon == null and _tile_manager != null:
		var source_tile: TileCellData = _tile_manager.get_tile(payload.root_source_cell)
		if source_tile != null and source_tile.definition != null:
			icon = source_tile.definition.ui_icon
	var entry := _make_entry(&"projection", payload.display_name, category, "虚像", icon, payload.primary_color, lines)
	entry["has_source"] = true
	entry["source_cell"] = payload.root_source_cell
	entry["mirror_edge_id"] = producing_mirror
	return entry


func _make_entry(kind: StringName, display_name: String, category: String, state: String, icon: Texture2D, accent: Color, lines: Array[String]) -> Dictionary:
	return {"kind": kind, "name": display_name, "category": category, "state": state, "icon": icon, "accent": accent, "lines": lines, "has_source": false, "source_cell": Vector3i.ZERO, "mirror_edge_id": ""}
