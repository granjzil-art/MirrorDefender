## SquareGridShape —— 正方形网格（行列坐标）
##
## 坐标：cell = (col, row, 0)，用 Vector3i 存（第三分量恒 0，与 hex 统一签名）。
## 世界坐标：x = col * cell_size, z = row * cell_size（格心）。
##
## 角点（以格心为中心，边长 = cell_size）：
##   corner0 = (+h,-h)  corner1 = (+h,+h)  corner2 = (-h,+h)  corner3 = (-h,-h)   h = cell_size/2
## 边 i = corner[i] -> corner[(i+1)%4]：
##   边0 右, 边1 上, 边2 左, 边3 下（与 _DIRS 对应）。
class_name SquareGridShape
extends IGridShape

const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0),   # 边0 右邻
	Vector3i(0, 1, 0),   # 边1 上邻(+z)
	Vector3i(-1, 0, 0),  # 边2 左邻
	Vector3i(0, -1, 0),  # 边3 下邻(-z)
]

func edge_count() -> int:
	return 4

func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * cell_size, 0.0, cell.y * cell_size)

func world_to_cell(world: Vector3) -> Vector3i:
	var col: int = roundi(world.x / cell_size)
	var row: int = roundi(world.z / cell_size)
	return Vector3i(col, row, 0)

func get_neighbors(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d in _DIRS:
		out.append(cell + d)
	return out

func distance(a: Vector3i, b: Vector3i) -> int:
	# 曼哈顿距离（初版无对角移动）。
	return absi(a.x - b.x) + absi(a.y - b.y)

func get_corners(cell: Vector3i) -> PackedVector3Array:
	var c := cell_to_world(cell)
	var h := cell_size * 0.5
	var pts := PackedVector3Array()
	# 从右下角开始逆时针排列，使 edge_index 与 _DIRS 严格一一对应。
	pts.append(c + Vector3(h, 0.0, -h))
	pts.append(c + Vector3(h, 0.0, h))
	pts.append(c + Vector3(-h, 0.0, h))
	pts.append(c + Vector3(-h, 0.0, -h))
	return pts

func neighbor_across_edge(cell: Vector3i, edge_index: int) -> Vector3i:
	return cell + _DIRS[edge_index % 4]

func enumerate_cells(grid_size: Vector2i) -> Array[Vector3i]:
	# square 用 grid_size = (cols, rows)。
	var out: Array[Vector3i] = []
	for col in range(grid_size.x):
		for row in range(grid_size.y):
			out.append(Vector3i(col, row, 0))
	return out

func is_in_bounds(cell: Vector3i, grid_size: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y
