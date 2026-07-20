## Runtime projection overlay. It never occupies TileCellData.
class_name MirrorProjection
extends Node3D

var payload: MirrorCopyPayload
var preview_mode: bool = false

var _grid: GridManager
var _tile_manager: TileManager
var _definition: CopyMirrorDefinition
var _laser_line: MeshInstance3D
var _laser_material: StandardMaterial3D

func configure(
	copy_payload: MirrorCopyPayload,
	grid_manager: GridManager,
	tile_manager: TileManager,
	mirror_definition: CopyMirrorDefinition,
	stack_index: int = 0,
	p_preview_mode: bool = false
) -> void:
	payload = copy_payload
	_grid = grid_manager
	_tile_manager = tile_manager
	_definition = mirror_definition
	preview_mode = p_preview_mode
	var base_height := _tile_manager.get_world_height(payload.projected_cell) if _tile_manager != null else 0.0
	var layer_offset := float(stack_index) * _grid.cell_size * _definition.projection_layer_offset_ratio
	position = _grid.cell_to_world(payload.projected_cell) + Vector3(0.0, base_height + layer_offset, 0.0)
	_build_visual()

func is_structure_alive() -> bool:
	return payload != null and payload.copy_kind == &"barrier" and payload.is_source_valid()

func get_structure_target_position() -> Vector3:
	return global_position + Vector3(0.0, _grid.cell_size * 0.42, 0.0)

func get_structure_hit_radius() -> float:
	return _grid.cell_size * 0.30 if _grid != null else 0.3

func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not is_structure_alive() or not payload.root_source.has_method("take_structure_damage"):
		return 0.0
	return float(payload.root_source.call("take_structure_damage", amount, attacker))

func affects_target(target: Node) -> bool:
	if payload == null or not payload.is_source_valid():
		return false
	if payload.root_source != null and payload.root_source.has_method("affects_target"):
		return bool(payload.root_source.call("affects_target", target))
	if payload.tile_effect != null:
		return payload.tile_effect.affects_target(target)
	return true

func get_tile_effect() -> TileEffect:
	return payload.tile_effect if payload != null and payload.is_source_valid() else null

func show_laser(world_end: Vector3) -> void:
	if _laser_line == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _laser_material)
	mesh.surface_add_vertex(_laser_line.to_local(global_position + Vector3(0.0, _grid.cell_size * 0.82, 0.0)))
	mesh.surface_add_vertex(_laser_line.to_local(world_end))
	mesh.surface_end()
	_laser_line.mesh = mesh

func _build_visual() -> void:
	if payload == null or _grid == null or _definition == null:
		return
	var body := MeshInstance3D.new()
	var mesh: PrimitiveMesh
	match payload.copy_kind:
		&"barrier":
			var box := BoxMesh.new()
			box.size = Vector3(_grid.cell_size * 0.86, _grid.cell_size * 0.64, _grid.cell_size * 0.18)
			mesh = box
			body.position.y = box.size.y * 0.5
		&"rock":
			var rock := BoxMesh.new()
			rock.size = Vector3(_grid.cell_size * 0.66, _grid.cell_size * 0.62, _grid.cell_size * 0.66)
			mesh = rock
			body.position.y = rock.size.y * 0.5
		&"spike":
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = _grid.cell_size * 0.22
			spike.height = _grid.cell_size * 0.46
			mesh = spike
			body.position.y = spike.height * 0.5
		&"void":
			var disc := CylinderMesh.new()
			disc.top_radius = _grid.cell_size * 0.36
			disc.bottom_radius = _grid.cell_size * 0.36
			disc.height = _grid.cell_size * 0.025
			mesh = disc
			body.position.y = disc.height * 0.5
		_:
			var tower := CylinderMesh.new()
			tower.top_radius = _grid.cell_size * 0.20
			tower.bottom_radius = _grid.cell_size * 0.28
			tower.height = _grid.cell_size * 0.72
			mesh = tower
			body.position.y = tower.height * 0.5
	body.mesh = mesh
	body.material_override = _make_projection_material(payload.primary_color)
	add_child(body)
	if payload.copy_kind == &"laser_tower":
		_laser_line = MeshInstance3D.new()
		_laser_material = _make_projection_material(payload.primary_color)
		_laser_line.material_override = _laser_material
		add_child(_laser_line)

func _make_projection_material(source_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var color := source_color.lerp(_definition.projection_tint, 0.62)
	color.a = _definition.projection_alpha * (0.68 if preview_mode else 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 2.2
	return material
