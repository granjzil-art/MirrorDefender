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
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	m3_debug_panel.configure(building_manager, resource_manager, combat_manager)
	_building_action_panel = BuildingActionPanelScript.new()
	$HUD.add_child(_building_action_panel)
	_building_action_panel.configure(building_manager, _camera)
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
	_update_building_preview(cell)

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
	lines.append("网格: %s   格距: %.2f" % [shape_name, grid.cell_size])
	if cell.hit:
		lines.append("拾取格 cell = %s" % str(cell.cell))
		var tile := tile_manager.get_tile(cell.cell)
		if tile != null:
			lines.append("地块: %s | 高度档: %d" % [tile.get_display_name(), tile.height_level])
			var occupant := tile_manager.get_occupant(cell.cell)
			if occupant is Building:
				var occupied_building: Building = occupant
				var occupied_stats := occupied_building.get_level_stats()
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
	else:
		lines.append("拾取边 = (无)")
	if _has_selected_cell:
		lines.append("已锁定格 cell = %s" % str(_selected_cell))
	if _has_selected_edge:
		lines.append("已锁定边 index = %d | %s" % [_selected_edge_index, _selected_edge_id])
	var selected_building := building_manager.get_selected_building()
	if selected_building != null:
		var selected_stats := selected_building.get_level_stats()
		lines.append("建筑: %s L%d/%d | 世界朝向 %d/%d" % [
			selected_building.definition.display_name,
			selected_building.level,
			selected_building.get_max_level(),
			selected_building.facing_index + 1,
			selected_building.get_facing_slot_count(),
		])
		lines.append("伤害 %.1f | 索敌 %.1f | 射程 %.1f | 产出 %.1f/s" % [
			selected_building.get_instant_damage() if selected_building.definition.kind == BuildingDefinition.Kind.ARROW_TOWER else selected_building.get_laser_damage_per_second(),
			selected_stats.targeting_range,
			selected_stats.attack_range,
			selected_stats.resource_per_second,
		])
	hud_label.text = "\n".join(lines)

func _update_hint() -> void:
	hint_label.text = "WASD 平移 | QE 旋转 | XC/滚轮 缩放 | 左键执行模式 | 右键选择模式 | R 旋转建筑 | F 清障"

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
	if not cell_pick.hit:
		m3_debug_panel.report_no_cell()
		return
	var cell: Vector3i = cell_pick.cell
	_selected_cell = cell
	_has_selected_cell = true
	match m3_debug_panel.get_mode():
		M3DebugPanelScript.InteractionMode.BUILD_ARROW, M3DebugPanelScript.InteractionMode.BUILD_LASER:
			building_manager.place_building(
				cell,
				m3_debug_panel.get_selected_definition(),
				building_manager.get_preview_facing_index()
			)
		M3DebugPanelScript.InteractionMode.SPAWN_TARGET:
			var target_position := grid.cell_to_world(cell)
			target_position.y = tile_manager.get_world_height(cell) + 0.02
			if combat_manager.spawn_debug_target(target_position) != null:
				m3_debug_panel.report_target_spawned()
		_:
			_lock_current_pick()
			building_manager.select_at(cell)

func _update_building_preview(cell_pick: Dictionary) -> void:
	var definition := m3_debug_panel.get_selected_definition()
	if definition == null or not cell_pick.hit or get_viewport().gui_get_hovered_control() != null:
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
	_has_selected_cell = false
	_has_selected_edge = false
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)
	m3_debug_panel.cancel_to_select()
