## GridManager —— 网格管理器（当前网格的唯一对外入口）
##
## 铁律「模块化」：其它模块(地块/镜子/路径/UI)只通过 GridManager 查询几何，
## 不直接 new 具体形状。
## 铁律「参数化」：cell_size / grid_shape / grid_size 均 @export，运行时可调。
##
## 拾取：与每个地块的可见顶面求交，支持运行时高低地形；边拾取使用相同顶面高度。
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
var _cell_height_resolver: Callable

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

## Returns the source/target pair at a discrete distance from an internal edge.
## Coordinate stepping stays encapsulated here so mirror gameplay remains
## independent from square/hex storage details.
func get_mirror_cell_pair(
	from_cell: Vector3i,
	edge_index: int,
	active_from_side: bool,
	distance_from_edge: int
) -> Dictionary:
	var result := {
		"valid": false,
		"source_cell": Vector3i.ZERO,
		"target_cell": Vector3i.ZERO,
	}
	if not is_in_bounds(from_cell) or edge_index < 0 or edge_index >= edge_count():
		return result
	var to_cell := neighbor_across_edge(from_cell, edge_index)
	if not is_in_bounds(to_cell):
		return result
	var source_near := from_cell if active_from_side else to_cell
	var target_near := to_cell if active_from_side else from_cell
	var step := source_near - target_near
	var offset := maxi(1, distance_from_edge) - 1
	var source_cell := source_near + step * offset
	var target_cell := target_near - step * offset
	result["source_cell"] = source_cell
	result["target_cell"] = target_cell
	result["valid"] = is_in_bounds(source_cell) and is_in_bounds(target_cell)
	return result

## Direction-sensitive route segment key. Unlike canonical_edge_id, reversing
## from/to produces a different key and therefore a different blocking rule.
func directed_edge_id(from_cell: Vector3i, to_cell: Vector3i) -> String:
	if not get_neighbors(from_cell).has(to_cell):
		return ""
	return "%d,%d,%d>%d,%d,%d" % [
		from_cell.x,
		from_cell.y,
		from_cell.z,
		to_cell.x,
		to_cell.y,
		to_cell.z,
	]

func find_edge_index(from_cell: Vector3i, to_cell: Vector3i) -> int:
	for edge_index in range(edge_count()):
		if neighbor_across_edge(from_cell, edge_index) == to_cell:
			return edge_index
	return -1

func edge_count() -> int:
	return shape.edge_count()

func get_geometry_tag() -> StringName:
	return &"hex" if grid_shape == Shape.HEX else &"square"

func get_tile_building_facing_count() -> int:
	return 6 if grid_shape == Shape.HEX else 8

func get_edge_building_facing_count() -> int:
	return edge_count()

func enumerate_cells() -> Array[Vector3i]:
	return shape.enumerate_cells(grid_size)

func is_in_bounds(cell: Vector3i) -> bool:
	return shape.is_in_bounds(cell, grid_size)

## Injects a read-only `func(cell: Vector3i) -> float` height query without
## creating a Grid -> Tile module dependency.
func set_cell_height_resolver(resolver: Callable) -> void:
	_cell_height_resolver = resolver

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
	return raycast_ground_from_ray(origin, dir)

func raycast_ground_from_ray(origin: Vector3, dir: Vector3) -> Dictionary:
	if absf(dir.y) < 1e-6:
		return {"hit": false, "pos": Vector3.ZERO}
	var t := -origin.y / dir.y
	if t < 0.0:
		return {"hit": false, "pos": Vector3.ZERO}
	return {"hit": true, "pos": origin + dir * t}

## Returns the nearest visible tile-top intersection for an arbitrary ray.
func raycast_grid_surface(origin: Vector3, direction: Vector3) -> Dictionary:
	if shape == null or direction.is_zero_approx() or absf(direction.y) < 1e-6:
		return {"hit": false, "pos": Vector3.ZERO, "cell": Vector3i.ZERO}
	var nearest_distance := INF
	var nearest_cell := Vector3i.ZERO
	var nearest_position := Vector3.ZERO
	for cell in enumerate_cells():
		var surface_height := _resolve_cell_height(cell)
		var distance := (surface_height - origin.y) / direction.y
		if distance < 0.0 or distance >= nearest_distance:
			continue
		var position := origin + direction * distance
		if not _is_point_inside_cell(position, cell):
			continue
		nearest_distance = distance
		nearest_cell = cell
		nearest_position = position
	if not is_finite(nearest_distance):
		return {"hit": false, "pos": Vector3.ZERO, "cell": Vector3i.ZERO}
	return {"hit": true, "pos": nearest_position, "cell": nearest_cell}

## 拾取格：返回 {hit, cell, pos}。
func pick_cell(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	return pick_cell_from_ray(
		camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos)
	)

func pick_cell_from_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	return raycast_grid_surface(origin, direction.normalized())

## 拾取边：返回 {hit, cell, edge_index, id}。
## 在命中格的所有边里找离光标世界点最近的一条，且距离 < 阈值。
func pick_edge(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	return pick_edge_from_ray(
		camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos)
	)

func pick_edge_from_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	var g := raycast_grid_surface(origin, direction.normalized())
	if not g.hit:
		return {"hit": false}
	var hit_pos: Vector3 = g.pos
	var cell: Vector3i = g.cell
	var surface_height := _resolve_cell_height(cell)
	var best_i: int = -1
	var best_d: float = INF
	var n: int = edge_count()
	for i in range(n):
		var mid: Vector3 = shape.get_edge_midpoint(cell, i)
		mid.y = surface_height
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

func _resolve_cell_height(cell: Vector3i) -> float:
	if not _cell_height_resolver.is_valid():
		return 0.0
	var resolved: Variant = _cell_height_resolver.call(cell)
	if resolved is float or resolved is int:
		var height := float(resolved)
		return height if is_finite(height) else 0.0
	return 0.0

func _is_point_inside_cell(world_position: Vector3, cell: Vector3i) -> bool:
	var polygon := PackedVector2Array()
	for corner in get_corners(cell):
		polygon.append(Vector2(corner.x, corner.z))
	return Geometry2D.is_point_in_polygon(Vector2(world_position.x, world_position.z), polygon)
