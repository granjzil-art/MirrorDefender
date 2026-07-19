@tool
## LevelResource -- data-only level definition.
##
## M2 owns grid and tile layout. Later milestones extend this same Resource with
## paths, waves, resources, and caps instead of creating parallel level formats.
class_name LevelResource
extends Resource

@export_group("Grid")
@export_enum("六边形", "正方形") var grid_shape: int = 0
@export_range(0.1, 10.0, 0.05, "or_greater") var grid_cell_size: float = 1.0
## HEX uses x as radius. SQUARE uses (columns, rows).
@export var grid_size: Vector2i = Vector2i(6, 6)

@export_group("Tiles")
@export_range(1, 16, 1) var height_levels: int = 3
@export_range(0.05, 5.0, 0.05, "or_greater") var height_step: float = 0.45
@export var tiles: Array = []

@export_group("Editor Terrain Colors")
@export var height_color_low: Color = Color(0.18, 0.60, 0.31, 1.0)
@export var height_color_middle: Color = Color(0.95, 0.76, 0.18, 1.0)
@export var height_color_high: Color = Color(0.84, 0.24, 0.20, 1.0)

@export_group("M3 Economy")
@export_range(0, 100000, 1, "or_greater") var initial_resource: int = 200
@export_range(0, 1000, 1, "or_greater") var building_cap: int = 20
@export_range(0, 1000, 1, "or_greater") var mirror_cap: int = 6
@export_range(0.0, 10000.0, 0.1, "or_greater") var base_resource_per_second: float = 0.5

@export_group("M4 Base")
@export var base_cell: Vector3i = Vector3i.ZERO
@export_range(1.0, 1000000.0, 1.0, "or_greater") var base_max_hp: float = 100.0

@export_group("M4 Paths")
@export var paths: Array[PathDefinition] = []
@export var spawn_points: Array[SpawnPointDefinition] = []

@export_group("M4 Waves")
@export var waves: Array[WaveDefinition] = []

func get_tile(cell: Vector3i) -> Variant:
	for raw_tile in tiles:
		var tile: Resource = raw_tile
		if tile == null:
			continue
		var tile_cell: Vector3i = tile.get("cell")
		if tile_cell == cell:
			return tile
	return null

func store_tile(tile: Resource) -> void:
	if tile == null:
		return
	var tile_cell: Vector3i = tile.get("cell")
	for index in range(tiles.size()):
		var current: Resource = tiles[index]
		if current == null:
			continue
		var current_cell: Vector3i = current.get("cell")
		if current_cell == tile_cell:
			tiles[index] = tile
			emit_changed()
			return
	tiles.append(tile)
	emit_changed()

func clear_tiles() -> void:
	tiles.clear()
	emit_changed()

func clamp_tile_heights() -> void:
	for raw_tile in tiles:
		var tile: Resource = raw_tile
		if tile != null:
			var current_height: int = tile.get("height_level")
			tile.set("height_level", clampi(current_height, 0, maxi(0, height_levels - 1)))
	emit_changed()

func get_height_color(height_level: int) -> Color:
	var maximum_level := maxi(1, height_levels - 1)
	var normalized_height := clampf(float(height_level) / float(maximum_level), 0.0, 1.0)
	if normalized_height <= 0.5:
		return height_color_low.lerp(height_color_middle, normalized_height * 2.0)
	return height_color_middle.lerp(height_color_high, (normalized_height - 0.5) * 2.0)

func get_path_by_id(path_id: StringName) -> PathDefinition:
	for path in paths:
		if path != null and path.path_id == path_id:
			return path
	return null

func get_spawn_point(spawn_id: StringName) -> SpawnPointDefinition:
	for spawn_point in spawn_points:
		if spawn_point != null and spawn_point.spawn_id == spawn_id:
			return spawn_point
	return null

## Complete preflight used by both the editor and LevelLoader. Validation is
## deliberately read-only so a rejected resource cannot partially mutate the
## currently running level.
func validate_runtime() -> Array[String]:
	var errors: Array[String] = []
	_validate_grid_and_tiles(errors)
	_validate_level_parameters(errors)
	_validate_m4_content(errors)
	return errors

## Compatibility entry retained for the level editor's M4 validation button.
func validate_m4() -> Array[String]:
	return validate_runtime()

func _validate_grid_and_tiles(errors: Array[String]) -> void:
	if grid_shape != 0 and grid_shape != 1:
		errors.append("网格形状无效：%d" % grid_shape)
	if not is_finite(grid_cell_size) or grid_cell_size <= 0.0:
		errors.append("格距必须为有限正数")
	if grid_shape == 0:
		if grid_size.x < 1:
			errors.append("六边形地图半径必须至少为 1")
	elif grid_size.x < 1 or grid_size.y < 1:
		errors.append("正方形地图行列数必须至少为 1")
	if height_levels < 1:
		errors.append("高度档数必须至少为 1")
	if not is_finite(height_step) or height_step <= 0.0:
		errors.append("每档高度必须为有限正数")
	if grid_shape != 0 and grid_shape != 1:
		return
	var shape: IGridShape = _make_validation_shape()
	shape.setup(grid_cell_size)
	var tile_cells: Dictionary = {}
	for index in range(tiles.size()):
		var raw_tile: Variant = tiles[index]
		if not raw_tile is TileCellData:
			errors.append("地块数组第 %d 项不是 TileCellData" % (index + 1))
			continue
		var tile: TileCellData = raw_tile
		if tile_cells.has(tile.cell):
			errors.append("地块坐标重复：%s" % str(tile.cell))
		else:
			tile_cells[tile.cell] = true
		if not _is_valid_cell_coordinate(tile.cell):
			errors.append("地块坐标格式无效：%s" % str(tile.cell))
		elif not shape.is_in_bounds(tile.cell, grid_size):
			errors.append("地块 %s 位于地图外" % str(tile.cell))
		if tile.tile_type < TileCellData.TileType.BUILDABLE or tile.tile_type > TileCellData.TileType.BLOCKED:
			errors.append("地块 %s 的类型无效" % str(tile.cell))
		if tile.height_level < 0 or tile.height_level >= height_levels:
			errors.append("地块 %s 的高度档 %d 越界" % [str(tile.cell), tile.height_level])

func _validate_level_parameters(errors: Array[String]) -> void:
	if initial_resource < 0:
		errors.append("初始资源不能为负数")
	if building_cap < 0 or mirror_cap < 0:
		errors.append("建筑或镜面上限不能为负数")
	if not is_finite(base_resource_per_second) or base_resource_per_second < 0.0:
		errors.append("关卡基础资源产出必须为有限非负数")
	if not is_finite(base_max_hp) or base_max_hp <= 0.0:
		errors.append("据点生命值必须为有限正数")

func _validate_m4_content(errors: Array[String]) -> void:
	if grid_shape != 0 and grid_shape != 1 or not is_finite(grid_cell_size) or grid_cell_size <= 0.0:
		return
	var shape: IGridShape = _make_validation_shape()
	shape.setup(grid_cell_size)
	if not _is_valid_cell_coordinate(base_cell) or not shape.is_in_bounds(base_cell, grid_size):
		errors.append("据点格位于地图外")
	var path_ids: Dictionary = {}
	for path in paths:
		if path == null:
			errors.append("存在空路径")
			continue
		if path.path_id.is_empty() or path_ids.has(path.path_id):
			errors.append("路径 ID 为空或重复：%s" % path.display_name)
		path_ids[path.path_id] = true
		if path.cells.size() < 2:
			errors.append("路径 %s 至少需要两个格" % path.display_name)
		elif path.get_end_cell() != base_cell:
			errors.append("路径 %s 的终点 %s 不是据点格 %s" % [path.display_name, str(path.get_end_cell()), str(base_cell)])
		for index in range(path.cells.size()):
			var cell := path.cells[index]
			if not _is_valid_cell_coordinate(cell) or not shape.is_in_bounds(cell, grid_size):
				errors.append("路径 %s 含地图外格" % path.display_name)
				break
			if index > 0 and not shape.get_neighbors(path.cells[index - 1]).has(cell):
				errors.append("路径 %s：第 %d 格 %s 与第 %d 格 %s 不相邻" % [
					path.display_name,
					index,
					str(path.cells[index - 1]),
					index + 1,
					str(cell),
				])
				break
	var spawn_ids: Dictionary = {}
	for spawn_point in spawn_points:
		if spawn_point == null:
			errors.append("存在空出生点")
			continue
		if spawn_point.spawn_id.is_empty() or spawn_ids.has(spawn_point.spawn_id):
			errors.append("出生点 ID 为空或重复：%s" % spawn_point.display_name)
		spawn_ids[spawn_point.spawn_id] = true
		if not _is_valid_cell_coordinate(spawn_point.cell) or not shape.is_in_bounds(spawn_point.cell, grid_size):
			errors.append("出生点 %s 位于地图外" % spawn_point.display_name)
	for wave in waves:
		if wave == null:
			errors.append("存在空波次")
			continue
		if wave.spawn_groups.is_empty():
			errors.append("波次 %s 没有出怪组" % wave.display_name)
		for group in wave.spawn_groups:
			if group == null or group.enemy == null or group.spawn_point == null or group.path == null:
				errors.append("波次 %s 存在未完整配置的出怪组" % wave.display_name)
				continue
			if group.count < 1 or not is_finite(group.interval) or group.interval <= 0.0:
				errors.append("波次 %s 的数量或间隔无效" % wave.display_name)
			if not is_finite(group.start_delay) or group.start_delay < 0.0:
				errors.append("波次 %s 的组开始延迟无效" % wave.display_name)
			if not paths.has(group.path) or not spawn_points.has(group.spawn_point):
				errors.append("波次 %s 引用了不属于本关的路径或出生点" % wave.display_name)
			elif not group.path.cells.is_empty() and group.path.get_start_cell() != group.spawn_point.cell:
				errors.append("波次 %s 的出生点与路径起点不一致" % wave.display_name)

func _make_validation_shape() -> IGridShape:
	return HexGridShape.new() if grid_shape == 0 else SquareGridShape.new()

func _is_valid_cell_coordinate(cell: Vector3i) -> bool:
	return cell.x + cell.y + cell.z == 0 if grid_shape == 0 else cell.z == 0
