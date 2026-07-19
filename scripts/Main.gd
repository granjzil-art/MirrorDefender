## Main —— M3 主场景控制器
##
## 职责：装配 Level / Grid / Tile / Resource / Combat / Building / 相机与调试 HUD。
## 这是 M3 的验收入口场景。
##
## 操作：
##   WASD 平移镜头 / QE 旋转镜头 / XC + 滚轮 缩放
##   T    切换 六边形 <-> 正方形
##   鼠标悬停：高亮格；靠近边时高亮边（并显示 canonical_edge_id）
##   左键：执行 M3 面板当前模式（选择 / 建塔 / 放靶标）
##   右键：回到选择模式
##   R    旋转选中建筑朝向
##   F    清除锁定的可破坏障碍
extends Node3D

const LevelLoaderScript := preload("res://scripts/level/LevelLoader.gd")
const LevelDebugPanelScript := preload("res://scripts/level/LevelDebugPanel.gd")
const M3DebugPanelScript := preload("res://scripts/ui/M3DebugPanel.gd")
const BuildingActionPanelScript := preload("res://scripts/ui/BuildingActionPanel.gd")
const PathManagerScript := preload("res://scripts/path/PathManager.gd")
const BaseCoreScript := preload("res://scripts/unit/BaseCore.gd")
const WaveManagerScript := preload("res://scripts/wave/WaveManager.gd")
const WaveStatusPanelScript := preload("res://scripts/ui/WaveStatusPanel.gd")
const BarrierDefinitionResource := preload("res://resources/buildings/Barrier.tres")
const EdgeBarrierDefinitionResource := preload("res://resources/buildings/EdgeBarrier.tres")

@onready var grid: GridManager = $GridManager
@onready var renderer: GridRenderer = $GridRenderer
@onready var tile_manager: TileManager = $TileManager
@onready var tile_renderer: TileRenderer = $TileRenderer
@onready var resource_manager: ResourceManager = $ResourceManager
@onready var combat_manager: CombatManager = $CombatManager
@onready var building_manager: BuildingManager = $BuildingManager
@onready var level_loader: LevelLoaderScript = $LevelLoader
@onready var cam_rig: CameraController = $CameraRig
@onready var hud_label: Label = $HUD/Panel/Info
@onready var hint_label: Label = $HUD/Hint
@onready var level_debug_panel: LevelDebugPanelScript = $HUD/LevelDebugPanel
@onready var m3_debug_panel: M3DebugPanelScript = $HUD/M3DebugPanel

var _camera: Camera3D
var _building_action_panel: BuildingActionPanel
var path_manager: PathManager
var base_core: BaseCore
var wave_manager: WaveManager
var _wave_status_panel: WaveStatusPanel
var _has_selected_cell: bool = false
var _selected_cell: Vector3i = Vector3i.ZERO
var _has_selected_edge: bool = false
var _selected_edge_index: int = -1
var _selected_edge_id: String = ""

func _ready() -> void:
	_camera = cam_rig.get_camera()
	renderer.set_grid(grid)
	tile_manager.set_grid(grid)
	tile_renderer.set_grid(grid)
	tile_renderer.set_tile_manager(tile_manager)
	building_manager.barrier = BarrierDefinitionResource
	building_manager.edge_barrier = EdgeBarrierDefinitionResource
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	m3_debug_panel.configure(building_manager, resource_manager, combat_manager)
	_building_action_panel = BuildingActionPanelScript.new()
	$HUD.add_child(_building_action_panel)
	_building_action_panel.configure(building_manager, _camera)
	path_manager = PathManagerScript.new()
	add_child(path_manager)
	path_manager.configure(grid, tile_manager)
	base_core = BaseCoreScript.new()
	add_child(base_core)
	base_core.configure(grid, tile_manager)
	wave_manager = WaveManagerScript.new()
	add_child(wave_manager)
	wave_manager.configure(
		path_manager,
		combat_manager,
		resource_manager,
		base_core,
		Callable(building_manager, "resolve_path_blocker")
	)
	_wave_status_panel = WaveStatusPanelScript.new()
	$HUD.add_child(_wave_status_panel)
	_wave_status_panel.position = Vector2(1240.0, 270.0)
	_wave_status_panel.size = Vector2(344.0, 154.0)
	_wave_status_panel.configure(wave_manager, base_core)
	level_loader.configure(grid, tile_manager)
	level_loader.level_loaded.connect(_on_level_loaded)
	level_debug_panel.configure(level_loader)
	level_loader.load_initial_level()
	_update_hint()

func _process(_delta: float) -> void:
	_update_pick()

func _update_pick() -> void:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()

	var edge := grid.pick_edge(_camera, mp)
	var cell := grid.pick_cell(_camera, mp)
	_update_building_preview(cell, edge)

	# 边优先高亮（靠近边时），否则高亮格。
	if edge.hit:
		renderer.highlight_edge(edge.cell, edge.edge_index, true)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)
	else:
		renderer.highlight_edge(Vector3i.ZERO, 0, false)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)

	_update_hud(cell, edge)

func _update_hud(cell: Dictionary, edge: Dictionary) -> void:
	var shape_name := "六边形(HEX)" if grid.grid_shape == GridManager.Shape.HEX else "正方形(SQUARE)"
	var lines: Array[String] = []
	lines.append("关卡标签: %s | 网格: %s | 格距: %.2f" % [str(grid.get_geometry_tag()), shape_name, grid.cell_size])
	if base_core != null and wave_manager != null:
		var base_current: int = ceili(base_core.current_hp)
		var base_maximum: int = ceili(base_core.max_hp)
		var wave_current := wave_manager.get_current_wave_number()
		var wave_total := wave_manager.get_total_wave_count()
		var active_enemies := wave_manager.get_active_enemy_count()
		var wave_state := wave_manager.get_state_name()
		lines.append("据点: %d/%d | 波次 %d/%d | 敌人 %d | %s" % [
			base_current,
			base_maximum,
			wave_current,
			wave_total,
			active_enemies,
			wave_state,
		])
	if cell.hit:
		lines.append("拾取格 cell = %s" % str(cell.cell))
		var tile := tile_manager.get_tile(cell.cell)
		if tile != null:
			lines.append("地块: %s | 高度档: %d" % [tile.get_display_name(), tile.height_level])
			var occupant := tile_manager.get_occupant(cell.cell)
			if occupant is Building:
				var occupied_building: Building = occupant
				var occupied_stats := occupied_building.get_level_stats()
				if occupied_building.is_path_blocker():
					lines.append("占位: %s L%d/%d | 耐久 %d/%d | 脱战 %.1fs 后 +%.1f/s" % [
						occupied_building.definition.display_name,
						occupied_building.level,
						occupied_building.get_max_level(),
						ceili(occupied_building.current_durability),
						ceili(occupied_building.maximum_durability),
						occupied_stats.regeneration_delay,
						occupied_stats.regeneration_per_second,
					])
				else:
					lines.append("占位: %s L%d/%d | 索敌 %.1f | 射程 %.1f" % [
						occupied_building.definition.display_name,
						occupied_building.level,
						occupied_building.get_max_level(),
						occupied_stats.targeting_range,
						occupied_stats.attack_range,
					])
			elif occupant != null:
				lines.append("占位对象: %s" % occupant.name)
			if tile.is_destructible():
				lines.append("按 F 清除障碍，转为可建造")
		var preview := building_manager.get_preview_building()
		if preview != null and preview.cell == cell.cell:
			if preview.is_edge_placement():
				var preview_connector := "↔" if preview.is_bidirectional_edge_blocker() else "→"
				lines.append("放置预览: %s L1 | %s %s %s（贴边固定）" % [
					preview.definition.display_name,
					str(preview.cell),
					preview_connector,
					str(preview.edge_to_cell),
				])
			else:
				lines.append("放置预览: %s L1 | 朝向 %d/%d" % [
					preview.definition.display_name,
					preview.facing_index + 1,
					preview.get_facing_slot_count(),
				])
	else:
		lines.append("拾取格 cell = (界外)")
	if edge.hit:
		lines.append("拾取边 index = %d" % edge.edge_index)
		lines.append("边唯一键 = %s" % edge.id)
		var edge_building := building_manager.get_edge_building(edge.id)
		if edge_building != null:
			var edge_connector := "↔" if edge_building.is_bidirectional_edge_blocker() else "→"
			lines.append("边占位: %s L%d/%d | %s %s %s | 耐久 %d/%d" % [
				edge_building.definition.display_name,
				edge_building.level,
				edge_building.get_max_level(),
				str(edge_building.cell),
				edge_connector,
				str(edge_building.edge_to_cell),
				ceili(edge_building.current_durability),
				ceili(edge_building.maximum_durability),
			])
	else:
		lines.append("拾取边 = (无)")
	if _has_selected_cell:
		lines.append("已锁定格 cell = %s" % str(_selected_cell))
	if _has_selected_edge:
		lines.append("已锁定边 index = %d | %s" % [_selected_edge_index, _selected_edge_id])
	var selected_building := building_manager.get_selected_building()
	if selected_building != null:
		var selected_stats := selected_building.get_level_stats()
		if selected_building.is_edge_placement():
			var selected_connector := "↔" if selected_building.is_bidirectional_edge_blocker() else "→"
			lines.append("建筑: %s L%d/%d | %s %s %s（贴边固定）" % [
				selected_building.definition.display_name,
				selected_building.level,
				selected_building.get_max_level(),
				str(selected_building.cell),
				selected_connector,
				str(selected_building.edge_to_cell),
			])
		else:
			lines.append("建筑: %s L%d/%d | 世界朝向 %d/%d" % [
				selected_building.definition.display_name,
				selected_building.level,
				selected_building.get_max_level(),
				selected_building.facing_index + 1,
				selected_building.get_facing_slot_count(),
			])
		if selected_building.is_path_blocker():
			lines.append("耐久 %d/%d | 脱战 %.1fs | 回血 %.1f/s | 反伤 %.0f%%" % [
				ceili(selected_building.current_durability),
				ceili(selected_building.maximum_durability),
				selected_stats.regeneration_delay,
				selected_stats.regeneration_per_second,
				selected_stats.damage_reflection_ratio * 100.0,
			])
		else:
			lines.append("伤害 %.1f | 索敌 %.1f | 射程 %.1f | 产出 %.1f/s" % [
				selected_building.get_instant_damage() if selected_building.definition.kind == BuildingDefinition.Kind.ARROW_TOWER else selected_building.get_laser_damage_per_second(),
				selected_stats.targeting_range,
				selected_stats.attack_range,
				selected_stats.resource_per_second,
			])
	hud_label.text = "\n".join(lines)

func _update_hint() -> void:
	hint_label.text = "WASD 平移 | QE 旋转 | XC/滚轮 缩放 | 左键执行模式 | 边障可放任意内部共享边 | 右键选择模式 | R 旋转建筑 | F 清障 | 右上开始波次"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_grid_shape"):
		if grid.grid_shape == GridManager.Shape.HEX:
			grid.grid_shape = GridManager.Shape.SQUARE
		else:
			grid.grid_shape = GridManager.Shape.HEX
		var current_level := level_loader.get_current_level()
		if current_level != null:
			tile_manager.load_level(current_level)
	elif event.is_action_pressed("place_select"):
		_handle_primary_action()
	elif event.is_action_pressed("cancel_action"):
		m3_debug_panel.cancel_to_select()
	elif event.is_action_pressed("rotate_facing"):
		if m3_debug_panel.get_selected_definition() != null:
			building_manager.rotate_preview()
		else:
			building_manager.rotate_selected()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_destroy_selected_obstacle()

func _handle_primary_action() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var cell_pick: Dictionary = grid.pick_cell(_camera, mouse_position)
	var edge_pick: Dictionary = grid.pick_edge(_camera, mouse_position)
	if not cell_pick.hit:
		m3_debug_panel.report_no_cell()
		return
	var cell: Vector3i = cell_pick.cell
	_selected_cell = cell
	_has_selected_cell = true
	match m3_debug_panel.get_mode():
		M3DebugPanelScript.InteractionMode.BUILD_ARROW, M3DebugPanelScript.InteractionMode.BUILD_LASER, M3DebugPanelScript.InteractionMode.BUILD_BARRIER:
			building_manager.place_building(
				cell,
				m3_debug_panel.get_selected_definition(),
				building_manager.get_preview_facing_index()
			)
		M3DebugPanelScript.InteractionMode.BUILD_EDGE_BARRIER:
			if not edge_pick.hit:
				m3_debug_panel.report_no_cell()
				return
			var edge_cell: Vector3i = edge_pick.cell
			var edge_index: int = edge_pick.edge_index
			building_manager.place_edge_building(
				edge_cell,
				edge_index,
				m3_debug_panel.get_selected_definition()
			)
		M3DebugPanelScript.InteractionMode.SPAWN_TARGET:
			var target_position := grid.cell_to_world(cell)
			target_position.y = tile_manager.get_world_height(cell) + 0.02
			if combat_manager.spawn_debug_target(target_position) != null:
				m3_debug_panel.report_target_spawned()
		_:
			_lock_current_pick()
			building_manager.select_at(cell, edge_pick.id if edge_pick.hit else "")

func _update_building_preview(cell_pick: Dictionary, edge_pick: Dictionary) -> void:
	var definition := m3_debug_panel.get_selected_definition()
	if definition == null or get_viewport().gui_get_hovered_control() != null:
		building_manager.clear_preview()
		return
	if definition.is_edge_building():
		if not edge_pick.hit:
			building_manager.clear_preview()
			return
		var from_cell: Vector3i = edge_pick.cell
		var placement_edge_index: int = edge_pick.edge_index
		building_manager.update_edge_preview(from_cell, placement_edge_index, definition)
		return
	if not cell_pick.hit:
		building_manager.clear_preview()
		return
	var cell: Vector3i = cell_pick.cell
	building_manager.update_preview(cell, definition)

func _lock_current_pick() -> void:
	var mp := get_viewport().get_mouse_position()
	var cell: Dictionary = grid.pick_cell(_camera, mp)
	var edge: Dictionary = grid.pick_edge(_camera, mp)
	_has_selected_cell = cell.hit
	if _has_selected_cell:
		_selected_cell = cell.cell
	_has_selected_edge = edge.hit
	if _has_selected_edge:
		_selected_edge_index = edge.edge_index
		_selected_edge_id = edge.id

func _destroy_selected_obstacle() -> void:
	if not _has_selected_cell:
		return
	tile_manager.destroy_obstacle_at(_selected_cell)

func _on_level_loaded(level_resource: LevelResource, _source_path: String) -> void:
	resource_manager.apply_level_configuration(level_resource)
	combat_manager.clear_targets()
	path_manager.load_level(level_resource)
	base_core.load_level(level_resource)
	wave_manager.load_level(level_resource)
	_has_selected_cell = false
	_has_selected_edge = false
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)
	m3_debug_panel.cancel_to_select()
