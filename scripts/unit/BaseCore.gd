## Runtime base health owner used by M4 path arrivals and future HUD.
class_name BaseCore
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Visual")
@export var core_color: Color = Color(0.34, 0.72, 1.0, 1.0)
@export_range(0.2, 3.0, 0.05, "or_greater") var core_height: float = 0.9

signal health_changed(current_hp: float, maximum_hp: float)
signal defeated

var max_hp: float = 100.0
var current_hp: float = 100.0
## First base cell retained for compatibility. Use get_base_cells() for all.
var cell: Vector3i = Vector3i.ZERO
var _grid: GridManager
var _tile_manager: TileManager
var _base_cells: Array[Vector3i] = []
var _marker_roots: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _occupied_cells: Dictionary = {}

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager

func load_level(level_resource: LevelResource) -> void:
	if level_resource == null or _grid == null:
		_clear_runtime_points()
		visible = false
		return
	_clear_runtime_points()
	var base_points := level_resource.get_effective_base_points()
	if base_points.is_empty():
		visible = false
		return
	cell = base_points[0].cell
	max_hp = maxf(1.0, level_resource.base_max_hp)
	current_hp = max_hp
	position = Vector3.ZERO
	for base_point in base_points:
		if base_point == null:
			continue
		_base_cells.append(base_point.cell)
		if _tile_manager.place_occupant(base_point.cell, self):
			_occupied_cells[base_point.cell] = true
		_build_point_visual(base_point, level_resource)
	visible = true
	_emit_health_changed()

func take_damage(amount: float) -> float:
	if not feature_enabled or current_hp <= 0.0 or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current_hp)
	current_hp -= applied
	_emit_health_changed()
	if current_hp <= 0.0:
		defeated.emit()
	return applied

func is_alive() -> bool:
	return current_hp > 0.0


func get_base_cells() -> Array[Vector3i]:
	return _base_cells.duplicate()


func get_base_point_count() -> int:
	return _base_cells.size()


func get_marker_labels() -> Array[String]:
	var labels: Array[String] = []
	for label in _labels:
		if label != null and is_instance_valid(label):
			labels.append(label.text)
	return labels


func _build_point_visual(base_point: Resource, level_resource: LevelResource) -> void:
	var marker_root := Node3D.new()
	marker_root.name = "BasePoint_%s" % str(base_point.get("base_id"))
	marker_root.position = _grid.cell_to_world(base_point.cell) + Vector3(0.0, _tile_manager.get_world_height(base_point.cell), 0.0)
	add_child(marker_root)
	_marker_roots.append(marker_root)
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.46
	mesh.height = core_height
	mesh_instance.mesh = mesh
	mesh_instance.position.y = core_height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = core_color
	material.emission_enabled = true
	material.emission = core_color
	material.emission_energy_multiplier = 1.3
	mesh_instance.material_override = material
	marker_root.add_child(mesh_instance)
	var label := Label3D.new()
	label.position.y = core_height + 0.32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.text = level_resource.get_base_marker_label(base_point)
	marker_root.add_child(label)
	_labels.append(label)

func _emit_health_changed() -> void:
	for label in _labels:
		if label != null and is_instance_valid(label):
			var marker_name := label.text.get_slice("\n", 0)
			label.text = "%s\n共享生命 %d/%d" % [marker_name, ceili(current_hp), ceili(max_hp)]
	health_changed.emit(current_hp, max_hp)


func _clear_runtime_points() -> void:
	if _tile_manager != null:
		for raw_cell in _occupied_cells.keys():
			var occupied_cell: Vector3i = raw_cell
			_tile_manager.clear_occupant(occupied_cell, self)
	_occupied_cells.clear()
	_base_cells.clear()
	_labels.clear()
	for marker_root in _marker_roots:
		if marker_root != null and is_instance_valid(marker_root):
			marker_root.queue_free()
	_marker_roots.clear()
