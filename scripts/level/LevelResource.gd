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
@export_range(0.0, 10000.0, 0.1, "or_greater") var wave_prep_time: float = 5.0
@export var waves_auto_start: bool = false

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

func validate_m4() -> Array[String]:
	var errors: Array[String] = []
	var shape: IGridShape = HexGridShape.new() if grid_shape == 0 else SquareGridShape.new()
	shape.setup(grid_cell_size)
	if not shape.is_in_bounds(base_cell, grid_size):
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
		for index in range(path.cells.size()):
			var cell := path.cells[index]
			if not shape.is_in_bounds(cell, grid_size):
				errors.append("路径 %s 含地图外格" % path.display_name)
				break
			if index > 0 and not shape.get_neighbors(path.cells[index - 1]).has(cell):
				errors.append("路径 %s 存在不相邻的格" % path.display_name)
				break
	var spawn_ids: Dictionary = {}
	for spawn_point in spawn_points:
		if spawn_point == null:
			errors.append("存在空出生点")
			continue
		if spawn_point.spawn_id.is_empty() or spawn_ids.has(spawn_point.spawn_id):
			errors.append("出生点 ID 为空或重复：%s" % spawn_point.display_name)
		spawn_ids[spawn_point.spawn_id] = true
		if not shape.is_in_bounds(spawn_point.cell, grid_size):
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
			if group.count < 1 or group.interval <= 0.0:
				errors.append("波次 %s 的数量或间隔无效" % wave.display_name)
			if not paths.has(group.path) or not spawn_points.has(group.spawn_point):
				errors.append("波次 %s 引用了不属于本关的路径或出生点" % wave.display_name)
			elif not group.path.cells.is_empty() and group.path.get_start_cell() != group.spawn_point.cell:
				errors.append("波次 %s 的出生点与路径起点不一致" % wave.display_name)
	return errors
