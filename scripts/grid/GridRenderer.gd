## GridRenderer —— 网格线框 + 格/边高亮渲染（初版色块/点线面美术）
##
## 职责：监听 GridManager.grid_changed 重建线框；每帧根据鼠标拾取高亮格与边。
## 不含逻辑，纯表现层。铁律「模块化」：只读 GridManager，不改其状态。
class_name GridRenderer
extends Node3D

@export_group("Colors")
@export var line_color: Color = Color(0.30, 0.42, 0.60, 0.85)
@export var cell_highlight_color: Color = Color(0.30, 0.62, 1.0, 0.35)
@export var edge_highlight_color: Color = Color(1.0, 0.30, 0.30, 0.95)
@export_group("Sizes")
@export var line_lift: float = 0.02       # 线离地高度，防 z-fighting
@export var edge_highlight_lift: float = 0.05

@export var grid: GridManager

var _grid_mesh_inst: MeshInstance3D
var _cell_hi_inst: MeshInstance3D
var _edge_hi_inst: MeshInstance3D
var _line_mat: StandardMaterial3D
var _cell_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D

func _ready() -> void:
	_setup_materials()
	_setup_instances()
	if grid:
		_connect_grid()

## 注入当前网格入口，并负责信号订阅与首次绘制。
## Main 作为场景装配层调用此公开方法；其它系统只读 GridManager。
func set_grid(value: GridManager) -> void:
	if grid != null and grid.grid_changed.is_connected(_rebuild_grid_lines):
		grid.grid_changed.disconnect(_rebuild_grid_lines)
	grid = value
	if is_node_ready() and grid != null:
		_connect_grid()

func _connect_grid() -> void:
	if not grid.grid_changed.is_connected(_rebuild_grid_lines):
		grid.grid_changed.connect(_rebuild_grid_lines)
	_rebuild_grid_lines()

func _setup_materials() -> void:
	_line_mat = _make_unshaded(line_color)
	_cell_mat = _make_unshaded(cell_highlight_color)
	_edge_mat = _make_unshaded(edge_highlight_color)

func _make_unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = false
	return m

func _setup_instances() -> void:
	_grid_mesh_inst = MeshInstance3D.new()
	_grid_mesh_inst.material_override = _line_mat
	add_child(_grid_mesh_inst)

	_cell_hi_inst = MeshInstance3D.new()
	_cell_hi_inst.material_override = _cell_mat
	_cell_hi_inst.visible = false
	add_child(_cell_hi_inst)

	_edge_hi_inst = MeshInstance3D.new()
	_edge_hi_inst.material_override = _edge_mat
	_edge_hi_inst.visible = false
	add_child(_edge_hi_inst)

## 重建所有格的边线（ImmediateMesh, PRIMITIVE_LINES）。
func _rebuild_grid_lines() -> void:
	if grid == null or grid.shape == null:
		return
	var im := ImmediateMesh.new()
	var has_grid_geometry: bool = false
	for cell in grid.enumerate_cells():
		var corners := grid.get_corners(cell)
		var n := corners.size()
		for i in range(n):
			if not has_grid_geometry:
				im.surface_begin(Mesh.PRIMITIVE_LINES)
				has_grid_geometry = true
			var a := corners[i] + Vector3(0, line_lift, 0)
			var b := corners[(i + 1) % n] + Vector3(0, line_lift, 0)
			im.surface_add_vertex(a)
			im.surface_add_vertex(b)
	if has_grid_geometry:
		im.surface_end()
		_grid_mesh_inst.mesh = im
	else:
		_grid_mesh_inst.mesh = null

## 高亮某格（填充多边形）。cell=null 时隐藏。
func highlight_cell(cell: Vector3i, has: bool) -> void:
	if not has or grid == null:
		_cell_hi_inst.visible = false
		return
	var corners := grid.get_corners(cell)
	var n := corners.size()
	if n < 3:
		_cell_hi_inst.visible = false
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := grid.cell_to_world(cell) + Vector3(0, line_lift + 0.005, 0)
	for i in range(n):
		var a := corners[i] + Vector3(0, line_lift + 0.005, 0)
		var b := corners[(i + 1) % n] + Vector3(0, line_lift + 0.005, 0)
		im.surface_add_vertex(center)
		im.surface_add_vertex(a)
		im.surface_add_vertex(b)
	im.surface_end()
	_cell_hi_inst.mesh = im
	_cell_hi_inst.visible = true

## 高亮某条边（画一条抬高的线段）。has=false 时隐藏。
func highlight_edge(cell: Vector3i, edge_index: int, has: bool) -> void:
	if not has or grid == null:
		_edge_hi_inst.visible = false
		return
	var ep := grid.get_edge_endpoints(cell, edge_index)
	if ep.is_empty():
		_edge_hi_inst.visible = false
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3(0, edge_highlight_lift, 0)
	im.surface_add_vertex(ep[0] + lift)
	im.surface_add_vertex(ep[1] + lift)
	im.surface_end()
	_edge_hi_inst.mesh = im
	_edge_hi_inst.visible = true
