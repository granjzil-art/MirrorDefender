## GridManager —— 网格管理器（当前网格的唯一对外入口）
##
## 铁律「模块化」：其它模块(地块/镜子/路径/UI)只通过 GridManager 查询几何，
## 不直接 new 具体形状。
## 铁律「参数化」：cell_size / grid_shape / grid_size 均 @export，运行时可调。
##
## 拾取：地面视为 y=0 平面，用相机射线求交得世界点，再 world_to_cell 反算格；
## 边拾取 = 在命中格及其邻格候选边中，取"点到边中点最近且 < edge_pick_threshold"的边。
class_name GridManager
extends Node3D

enum Shape { HEX, SQUARE }

@export_group("Grid")
@export var grid_shape: Shape = Shape.HEX:
	set(value):
		grid_shape = value
		if is_inside_tree():
			_rebuild_shape()
			grid_changed.emit()
@export var cell_size: float = 1.0:
	set(value):
		cell_size = maxf(0.01, value)
		if is_inside_tree():
			_rebuild_shape()
			grid_changed.emit()
## hex: (半径, 未用)；square: (列数, 行数)。
@export var grid_size: Vector2i = Vector2i(6, 6):
	set(value):
		grid_size = value
		if is_inside_tree():
			grid_changed.emit()

@export_group("Picking")
## 边拾取阈值（世界单位）：光标离边中点小于此值才算选中该边。
@export var edge_pick_threshold: float = 0.35

## 网格结构变化（形状/尺寸/格距改变）时发出，供渲染层重建。
signal grid_changed

var shape: IGridShape

func _ready() -> void:
	_rebuild_shape()
	grid_changed.emit()

func _rebuild_shape() -> void:
	match grid_shape:
		Shape.HEX:
			shape = HexGridShape.new()
		Shape.SQUARE:
			shape = SquareGridShape.new()
		_:
			shape = HexGridShape.new()
	shape.setup(cell_size)

# ---- 对外统一 API（转发到当前 shape）----

func cell_to_world(cell: Vector3i) -> Vector3:
	return shape.cell_to_world(cell)

func world_to_cell(world: Vector3) -> Vector3i:
	return shape.world_to_cell(world)

func get_neighbors(cell: Vector3i) -> Array[Vector3i]:
	return shape.get_neighbors(cell)

func distance(a: Vector3i, b: Vector3i) -> int:
	return shape.distance(a, b)

func get_corners(cell: Vector3i) -> PackedVector3Array:
	return shape.get_corners(cell)

func get_edge_endpoints(cell: Vector3i, edge_index: int) -> Array[Vector3]:
	return shape.get_edge_endpoints(cell, edge_index)

func neighbor_across_edge(cell: Vector3i, edge_index: int) -> Vector3i:
	return shape.neighbor_across_edge(cell, edge_index)

func canonical_edge_id(cell: Vector3i, edge_index: int) -> String:
	return shape.canonical_edge_id(cell, edge_index)

func edge_count() -> int:
	return shape.edge_count()

func enumerate_cells() -> Array[Vector3i]:
	return shape.enumerate_cells(grid_size)

func is_in_bounds(cell: Vector3i) -> bool:
	return shape.is_in_bounds(cell, grid_size)

## Applies level-owned grid data through GridManager, preserving its public API.
func apply_configuration(p_shape: int, p_cell_size: float, p_grid_size: Vector2i) -> void:
	grid_shape = p_shape
	cell_size = p_cell_size
	grid_size = p_grid_size

# ---- 拾取 ----

## 由屏幕射线求 y=0 平面交点。无交点返回 has=false。
func raycast_ground(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-6:
		return {"hit": false, "pos": Vector3.ZERO}
	var t := -origin.y / dir.y
	if t < 0.0:
		return {"hit": false, "pos": Vector3.ZERO}
	return {"hit": true, "pos": origin + dir * t}

## 拾取格：返回 {hit, cell}。
func pick_cell(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var g := raycast_ground(camera, screen_pos)
	if not g.hit:
		return {"hit": false, "cell": Vector3i.ZERO}
	var hit_pos: Vector3 = g.pos
	var cell: Vector3i = world_to_cell(hit_pos)
	if not is_in_bounds(cell):
		return {"hit": false, "cell": cell}
	return {"hit": true, "cell": cell, "pos": hit_pos}

## 拾取边：返回 {hit, cell, edge_index, id}。
## 在命中格的所有边里找离光标世界点最近的一条，且距离 < 阈值。
func pick_edge(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var g := raycast_ground(camera, screen_pos)
	if not g.hit:
		return {"hit": false}
	var hit_pos: Vector3 = g.pos
	var cell: Vector3i = world_to_cell(hit_pos)
	if not is_in_bounds(cell):
		return {"hit": false}
	var best_i: int = -1
	var best_d: float = INF
	var n: int = edge_count()
	for i in range(n):
		var mid: Vector3 = shape.get_edge_midpoint(cell, i)
		var d: float = hit_pos.distance_to(mid)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0 or best_d > edge_pick_threshold:
		return {"hit": false}
	return {
		"hit": true,
		"cell": cell,
		"edge_index": best_i,
		"id": canonical_edge_id(cell, best_i),
	}
