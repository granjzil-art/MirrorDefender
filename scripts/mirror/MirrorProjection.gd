## Runtime projection overlay. It reuses a source building or tile-content
## snapshot, applies the exact composed reflection, and never occupies TileCellData.
class_name MirrorProjection
extends Node3D

static var _shared_rim_shader: Shader

const PathBlockerPolicyScript := preload("res://scripts/path/PathBlockerPolicy.gd")
const PROJECTION_PRIORITY_BASE := 8
const PROJECTION_PRIORITY_STRIDE := 2
const PREVIEW_PRIORITY_OFFSET := 64

var payload: MirrorCopyPayload
var preview_mode: bool = false

var _grid: GridManager
var _tile_manager: TileManager
var _definition: CopyMirrorDefinition
var _tile_visual_snapshot_resolver: Callable
var _stack_index: int = 0
var _accent_color: Color = Color.WHITE
var _visual_snapshot: Node3D
var _laser_line: MeshInstance3D
var _laser_material: StandardMaterial3D
var _inspection_label: Label3D

func _process(_delta: float) -> void:
	sync_source_visual_pose()

func configure(
	copy_payload: MirrorCopyPayload,
	grid_manager: GridManager,
	tile_manager: TileManager,
	mirror_definition: CopyMirrorDefinition,
	stack_index: int = 0,
	p_preview_mode: bool = false,
	tile_visual_snapshot_resolver: Callable = Callable()
) -> void:
	payload = copy_payload
	_grid = grid_manager
	_tile_manager = tile_manager
	_definition = mirror_definition
	_stack_index = stack_index
	preview_mode = p_preview_mode
	_tile_visual_snapshot_resolver = tile_visual_snapshot_resolver
	var base_height := _tile_manager.get_world_height(payload.projected_cell) if _tile_manager != null else 0.0
	position = _grid.cell_to_world(payload.projected_cell) + Vector3(0.0, base_height, 0.0)
	_accent_color = _resolve_accent_color()
	_build_visual()

func is_structure_alive() -> bool:
	return payload != null and payload.copy_kind in [&"barrier", &"rock"] and payload.is_source_valid()

func get_structure_target_position() -> Vector3:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_structure_target_position"):
		var source_position: Vector3 = payload.root_source.call("get_structure_target_position")
		return payload.transform_point(source_position)
	return global_position + Vector3(0.0, _grid.cell_size * 0.42, 0.0)

func get_structure_hit_radius() -> float:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_structure_hit_radius"):
		return float(payload.root_source.call("get_structure_hit_radius"))
	return _grid.cell_size * 0.30 if _grid != null else 0.3

func take_structure_damage(amount: float, attacker: Node = null) -> float:
	if not is_structure_alive() or not payload.root_source.has_method("take_structure_damage"):
		return 0.0
	return float(payload.root_source.call("take_structure_damage", amount, attacker))

func get_path_blocker_response() -> int:
	if payload != null and payload.root_source != null and payload.root_source.has_method("get_path_blocker_response"):
		return int(payload.root_source.call("get_path_blocker_response"))
	return PathBlockerPolicyScript.Response.DIRECT_ATTACK

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

func get_visual_snapshot() -> Node3D:
	return _visual_snapshot

func get_inspection_text() -> String:
	if payload == null:
		return ""
	return "%s · 虚像%d · 复制链%d" % [payload.display_name, _stack_index + 1, payload.chain_depth]

func set_inspection_active(active: bool) -> void:
	if _inspection_label != null:
		_inspection_label.visible = active or preview_mode

func show_laser(world_start: Vector3, world_end: Vector3) -> void:
	if _laser_line == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _laser_material)
	mesh.surface_add_vertex(world_start)
	mesh.surface_add_vertex(world_end)
	mesh.surface_end()
	_laser_line.mesh = mesh

func _build_visual() -> void:
	if payload == null or _grid == null or _definition == null:
		return
	_visual_snapshot = _create_source_snapshot()
	if _visual_snapshot != null:
		add_child(_visual_snapshot)
		_visual_snapshot.top_level = true
		_apply_projection_materials(_visual_snapshot)
		sync_source_visual_pose()
	_build_stack_indicator()
	_build_inspection_label()
	if payload.copy_kind == &"laser_tower":
		_laser_line = MeshInstance3D.new()
		_laser_line.top_level = true
		_laser_line.global_transform = Transform3D.IDENTITY
		_laser_material = _make_line_material(_accent_color)
		_laser_line.material_override = _laser_material
		add_child(_laser_line)

func _create_source_snapshot() -> Node3D:
	if payload.root_source != null and payload.root_source.has_method("create_copy_visual_snapshot"):
		return payload.root_source.call("create_copy_visual_snapshot") as Node3D
	if payload.tile_effect != null and _tile_visual_snapshot_resolver.is_valid():
		return _tile_visual_snapshot_resolver.call(payload.root_source_cell) as Node3D
	return null

func _get_snapshot_transform() -> Transform3D:
	if payload.root_source != null and payload.root_source.has_method("get_copy_visual_transform"):
		var source_transform: Transform3D = payload.root_source.call("get_copy_visual_transform")
		return payload.transform_transform(source_transform)
	return payload.get_composed_transform()

## Synchronizes the existing behaviorless snapshot without rebuilding the
## projection node. Dynamic source pose is copied first, then the complete
## source transform receives every reflection in the payload chain.
func sync_source_visual_pose() -> bool:
	if is_queued_for_deletion():
		return false
	if _visual_snapshot == null or not is_instance_valid(_visual_snapshot):
		return false
	if payload == null or not payload.is_source_valid():
		visible = false
		return false
	visible = true
	if payload.root_source != null and payload.root_source.has_method("sync_copy_visual_snapshot"):
		payload.root_source.call("sync_copy_visual_snapshot", _visual_snapshot)
	_visual_snapshot.global_transform = _get_snapshot_transform()
	return true

func _apply_projection_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var source_material := mesh_instance.material_override
		if source_material == null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			source_material = mesh_instance.mesh.surface_get_material(0)
		mesh_instance.material_override = _make_projection_material(source_material)
		mesh_instance.material_overlay = _make_rim_material()
	for child in node.get_children():
		_apply_projection_materials(child)

func _make_projection_material(source_material: Material) -> StandardMaterial3D:
	var material := source_material.duplicate() as StandardMaterial3D if source_material is StandardMaterial3D else StandardMaterial3D.new()
	var source_color := material.albedo_color
	if source_color == Color(0.0, 0.0, 0.0, 1.0) and payload != null:
		source_color = payload.primary_color
	var tint_strength := clampf(_definition.projection_tint_strength, 0.0, 1.0)
	var color := source_color.lerp(_accent_color, tint_strength)
	color.a = _definition.projection_alpha * (0.76 if preview_mode else 1.0)
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = _get_render_priority(false)
	material.emission_enabled = true
	material.emission = source_color.lerp(_accent_color, maxf(0.34, tint_strength))
	material.emission_energy_multiplier = _definition.projection_emission_energy
	return material

func _make_rim_material() -> ShaderMaterial:
	if _shared_rim_shader == null:
		_shared_rim_shader = Shader.new()
		_shared_rim_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform vec4 accent : source_color;
uniform float rim_alpha = 0.42;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	ALBEDO = accent.rgb;
	EMISSION = accent.rgb * (0.8 + rim * 1.8);
	ALPHA = clamp(rim * rim_alpha, 0.0, 0.78);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _shared_rim_shader
	material.render_priority = _get_render_priority(true)
	material.set_shader_parameter("accent", _accent_color)
	material.set_shader_parameter("rim_alpha", _definition.projection_rim_alpha)
	return material

func _build_stack_indicator() -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	var ring_spacing := _grid.cell_size * _definition.projection_ring_spacing_ratio
	mesh.inner_radius = _grid.cell_size * 0.29 + ring_spacing * float(_stack_index)
	mesh.outer_radius = mesh.inner_radius + _grid.cell_size * _definition.projection_ring_thickness_ratio
	ring.mesh = mesh
	ring.position.y = _grid.cell_size * 0.025
	ring.material_override = _make_line_material(_accent_color)
	add_child(ring)

func _build_inspection_label() -> void:
	_inspection_label = Label3D.new()
	_inspection_label.text = get_inspection_text()
	_inspection_label.position.y = _grid.cell_size * (1.08 + float(_stack_index) * 0.16)
	_inspection_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_inspection_label.no_depth_test = true
	_inspection_label.font_size = 24
	_inspection_label.modulate = _accent_color
	_inspection_label.outline_size = 6
	_inspection_label.visible = preview_mode
	add_child(_inspection_label)

func _make_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = _definition.projection_emission_energy
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = _get_render_priority(true)
	return material

func _get_render_priority(overlay_pass: bool) -> int:
	var preview_offset := PREVIEW_PRIORITY_OFFSET if preview_mode else 0
	var priority := PROJECTION_PRIORITY_BASE + preview_offset + _stack_index * PROJECTION_PRIORITY_STRIDE
	if overlay_pass:
		priority += 1
	return clampi(priority, Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)

func _resolve_accent_color() -> Color:
	var stable_hash := absi(payload.stable_key.hash()) if payload != null else 0
	var hue_shift := fmod(float(stable_hash % 997) / 997.0 + float(_stack_index) * 0.173, 1.0)
	var palette_color := Color.from_hsv(hue_shift, 0.58, 1.0, 1.0)
	return _definition.projection_tint.lerp(palette_color, 0.46)
