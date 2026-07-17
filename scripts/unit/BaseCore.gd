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
var cell: Vector3i = Vector3i.ZERO
var _grid: GridManager
var _tile_manager: TileManager
var _mesh_instance: MeshInstance3D
var _label: Label3D
var _has_occupancy: bool = false

func configure(grid_manager: GridManager, tile_manager: TileManager) -> void:
	_grid = grid_manager
	_tile_manager = tile_manager

func load_level(level_resource: LevelResource) -> void:
	if level_resource == null or _grid == null:
		_clear_occupancy()
		visible = false
		return
	_clear_occupancy()
	cell = level_resource.base_cell
	max_hp = maxf(1.0, level_resource.base_max_hp)
	current_hp = max_hp
	global_position = _grid.cell_to_world(cell) + Vector3(0.0, _tile_manager.get_world_height(cell), 0.0)
	_has_occupancy = _tile_manager.place_occupant(cell, self)
	visible = true
	_build_visual()
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

func _build_visual() -> void:
	if _mesh_instance != null:
		_mesh_instance.queue_free()
	if _label != null:
		_label.queue_free()
	_mesh_instance = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.46
	mesh.height = core_height
	_mesh_instance.mesh = mesh
	_mesh_instance.position.y = core_height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = core_color
	material.emission_enabled = true
	material.emission = core_color
	material.emission_energy_multiplier = 1.3
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	_label = Label3D.new()
	_label.position.y = core_height + 0.28
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 28
	add_child(_label)

func _emit_health_changed() -> void:
	if _label != null:
		_label.text = "据点 %d/%d" % [ceili(current_hp), ceili(max_hp)]
	health_changed.emit(current_hp, max_hp)

func _clear_occupancy() -> void:
	if _has_occupancy and _tile_manager != null:
		_tile_manager.clear_occupant(cell, self)
	_has_occupancy = false
