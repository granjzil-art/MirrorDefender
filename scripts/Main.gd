## Main —— M1 主场景控制器
##
## 职责：装配 Level / Grid / Tile / 相机 / 渲染，处理拾取并驱动高亮，更新 HUD。
## 这是 M2 的验收入口场景。
##
## 操作：
##   WASD 平移镜头 / QE 旋转镜头 / XC + 滚轮 缩放
##   T    切换 六边形 <-> 正方形
##   鼠标悬停：高亮格；靠近边时高亮边（并显示 canonical_edge_id）
##   左键：锁定当前拾取格/边并显示到 HUD
##   F    清除锁定的可破坏障碍
extends Node3D

const LevelLoaderScript := preload("res://scripts/level/LevelLoader.gd")
const LevelDebugPanelScript := preload("res://scripts/level/LevelDebugPanel.gd")

@onready var grid: GridManager = $GridManager
@onready var renderer: GridRenderer = $GridRenderer
@onready var tile_manager: TileManager = $TileManager
@onready var tile_renderer: TileRenderer = $TileRenderer
@onready var level_loader: LevelLoaderScript = $LevelLoader
@onready var cam_rig: CameraController = $CameraRig
@onready var hud_label: Label = $HUD/Panel/Info
@onready var hint_label: Label = $HUD/Hint
@onready var level_debug_panel: LevelDebugPanelScript = $HUD/LevelDebugPanel

var _camera: Camera3D
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
			if tile.is_destructible():
				lines.append("按 F 清除障碍，转为可建造")
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
	hud_label.text = "\n".join(lines)

func _update_hint() -> void:
	hint_label.text = "WASD 平移镜头 | QE 旋转 | XC/滚轮 缩放 | T 切换网格形状 | 左键锁定格/边 | F 清除可破坏障碍"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_grid_shape"):
		if grid.grid_shape == GridManager.Shape.HEX:
			grid.grid_shape = GridManager.Shape.SQUARE
		else:
			grid.grid_shape = GridManager.Shape.HEX
	elif event.is_action_pressed("place_select"):
		_lock_current_pick()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_destroy_selected_obstacle()

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

func _on_level_loaded(_level_resource: LevelResource, _source_path: String) -> void:
	_has_selected_cell = false
	_has_selected_edge = false
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)
