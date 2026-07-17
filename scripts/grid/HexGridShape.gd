## HexGridShape —— 六边形网格（flat-top，立方体坐标）
##
## 坐标：cell = (q, r, s)，约束 q + r + s = 0，用 Vector3i 存。
## flat-top（平顶）：六边形有左右两个尖角、上下两条水平边的对立形态——
##   flat-top 实际是"左右为尖顶点，顶部/底部为水平边"。
##
## 几何（flat-top，size = 外接圆半径 = cell_size）：
##   width  = 2 * size
##   height = sqrt(3) * size
##   水平相邻格心间距 = 3/2 * size
##   垂直相邻格心间距 = sqrt(3) * size
##
## 角点角度（flat-top）：300°,0°,60°,120°,180°,240°。
## 边 i 连接 corner[i] -> corner[(i+1)%6]。
class_name HexGridShape
extends IGridShape

const SQRT3 := 1.7320508075688772

# 立方体坐标 6 个方向（flat-top，与 edge_index 的外法线方向对应）。
const _DIRS: Array[Vector3i] = [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1),
]

func edge_count() -> int:
	return 6

func cell_to_world(cell: Vector3i) -> Vector3:
	var q := cell.x
	var r := cell.y
	var x := cell_size * (1.5 * q)
	var z := cell_size * (SQRT3 * (r + q * 0.5))
	return Vector3(x, 0.0, z)

func world_to_cell(world: Vector3) -> Vector3i:
	# 逆变换到分数轴坐标，再做立方体取整。
	var q_f := (2.0 / 3.0 * world.x) / cell_size
	var r_f := (-1.0 / 3.0 * world.x + SQRT3 / 3.0 * world.z) / cell_size
	return _cube_round(q_f, r_f, -q_f - r_f)

func _cube_round(qf: float, rf: float, sf: float) -> Vector3i:
	var q: float = roundf(qf)
	var r: float = roundf(rf)
	var s: float = roundf(sf)
	var dq: float = absf(q - qf)
	var dr: float = absf(r - rf)
	var ds: float = absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	else:
		s = -q - r
	return Vector3i(int(q), int(r), int(s))

func get_neighbors(cell: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d in _DIRS:
		out.append(cell + d)
	return out

func distance(a: Vector3i, b: Vector3i) -> int:
	return int((absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)) / 2.0)

func get_corners(cell: Vector3i) -> PackedVector3Array:
	var center := cell_to_world(cell)
	var pts := PackedVector3Array()
	for i in range(6):
		# 从 300° 起，使 edge0 的法线为 330°，与 _DIRS[0] 对应。
		var ang := deg_to_rad(-60.0 + 60.0 * i)
		pts.append(center + Vector3(cell_size * cos(ang), 0.0, cell_size * sin(ang)))
	return pts

func neighbor_across_edge(cell: Vector3i, edge_index: int) -> Vector3i:
	return cell + _DIRS[edge_index % 6]

func enumerate_cells(grid_size: Vector2i) -> Array[Vector3i]:
	# hex 用半径 grid_size.x 生成一个正六边形范围的地图。
	var radius := grid_size.x
	var out: Array[Vector3i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = maxi(-radius, -q - radius)
		var r_max: int = mini(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			out.append(Vector3i(q, r, -q - r))
	return out

func is_in_bounds(cell: Vector3i, grid_size: Vector2i) -> bool:
	var radius := grid_size.x
	return distance(Vector3i.ZERO, cell) <= radius
