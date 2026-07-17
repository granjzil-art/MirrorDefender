## IGridShape —— 网格形状接口（抽象基类）
##
## 铁律「可拓展」：会变的部分走接口。网格形状(六边形/正方形/未来三角形)
## 都实现这一套虚方法，GridManager 只依赖此接口，不关心具体形状。
##
## 坐标约定：
##  - 对外统一用 Vector3i 表示"格坐标 cell"。
##      六边形: (q, r, s)  且 q + r + s = 0 (立方体坐标)
##      正方形: (col, row, 0)
##  - 世界坐标统一用 Vector3 (XZ 平面, Y=高度, M1 恒为 0)。
##
## 边(Edge)约定：
##  - 一条边用 (cell, edge_index) 描述。
##  - 六边形 edge_index ∈ [0,6)，正方形 ∈ [0,4)。
##  - canonical_edge_id: 相邻两格共享的同一物理边映射到同一字符串键，
##    供「一条边至多一面镜」占用校验。
class_name IGridShape
extends RefCounted

## 单格尺寸（世界单位）。由 GridManager 注入。
var cell_size: float = 1.0

func setup(p_cell_size: float) -> void:
	cell_size = p_cell_size

# ---- 以下为子类必须重写的虚方法 ----

## 该形状每格的边数（hex=6, square=4）。
func edge_count() -> int:
	push_error("IGridShape.edge_count() 未实现")
	return 0

## 格坐标 -> 世界坐标（格心，XZ 平面）。
func cell_to_world(_cell: Vector3i) -> Vector3:
	push_error("IGridShape.cell_to_world() 未实现")
	return Vector3.ZERO

## 世界坐标 -> 最近格坐标。
func world_to_cell(_world: Vector3) -> Vector3i:
	push_error("IGridShape.world_to_cell() 未实现")
	return Vector3i.ZERO

## 相邻格列表。
func get_neighbors(_cell: Vector3i) -> Array[Vector3i]:
	push_error("IGridShape.get_neighbors() 未实现")
	return []

## 两格间距离（格数）。
func distance(_a: Vector3i, _b: Vector3i) -> int:
	push_error("IGridShape.distance() 未实现")
	return 0

## 该格所有角点（世界坐标），顺序与 edge_index 对应：
## 第 i 条边 = corner[i] -> corner[(i+1)%n]。
func get_corners(_cell: Vector3i) -> PackedVector3Array:
	push_error("IGridShape.get_corners() 未实现")
	return PackedVector3Array()

## 返回该格第 edge_index 条边的两个端点（世界坐标）。
func get_edge_endpoints(cell: Vector3i, edge_index: int) -> Array[Vector3]:
	var corners := get_corners(cell)
	var n := corners.size()
	if n == 0:
		return []
	var a := corners[edge_index % n]
	var b := corners[(edge_index + 1) % n]
	return [a, b]

## 边中点（世界坐标）——用于边拾取距离比较。
func get_edge_midpoint(cell: Vector3i, edge_index: int) -> Vector3:
	var ep := get_edge_endpoints(cell, edge_index)
	if ep.is_empty():
		return Vector3.ZERO
	return (ep[0] + ep[1]) * 0.5

## 与第 edge_index 条边共享该边的邻格坐标（可能越界，需上层判断范围）。
func neighbor_across_edge(_cell: Vector3i, _edge_index: int) -> Vector3i:
	push_error("IGridShape.neighbor_across_edge() 未实现")
	return Vector3i.ZERO

## 规范化边键：把 (cellA,i) 与其邻格视角的 (cellB,j) 映射到同一字符串。
## 做法：取共享边两端点世界坐标，量化后排序拼接 —— 与从哪一侧看无关。
func canonical_edge_id(cell: Vector3i, edge_index: int) -> String:
	var ep := get_edge_endpoints(cell, edge_index)
	if ep.is_empty():
		return ""
	var p0 := ep[0]
	var p1 := ep[1]
	# 量化到 1e-3，避免浮点误差；再按字典序排序两端点，保证方向无关。
	var k0 := _quantize_key(p0)
	var k1 := _quantize_key(p1)
	if k0 <= k1:
		return k0 + "|" + k1
	return k1 + "|" + k0

func _quantize_key(p: Vector3) -> String:
	var x: int = roundi(p.x * 1000.0)
	var z: int = roundi(p.z * 1000.0)
	return str(x) + "," + str(z)

## 枚举给定范围内的所有格（供渲染/编辑器铺格）。
## grid_size 语义由子类解释（hex=半径, square=行列数）。
func enumerate_cells(_grid_size: Vector2i) -> Array[Vector3i]:
	push_error("IGridShape.enumerate_cells() 未实现")
	return []

## 判断格是否在范围内。
func is_in_bounds(_cell: Vector3i, _grid_size: Vector2i) -> bool:
	push_error("IGridShape.is_in_bounds() 未实现")
	return false
