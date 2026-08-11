## AcrylicDisplayCase -- dynamically sized acrylic cover and wooden plinth.
class_name AcrylicDisplayCase
extends Node3D

const AcrylicGlassShader := preload("res://resources/lighting/AcrylicGlass.gdshader")

var _grid: GridManager
var _terrain_manager: TerrainManager
var _definition: AcrylicDisplayCaseDefinition
var _visual_roots: Array[Node3D] = []
var _content_bounds: AABB = AABB()
var _case_size: Vector3 = Vector3.ZERO
var _panels_root: Node3D
var _edges_root: Node3D
var _base_root: Node3D
var _panel_materials: Array[ShaderMaterial] = []
var _edge_material: StandardMaterial3D


func configure(
	grid: GridManager,
	terrain_manager: TerrainManager,
	definition: AcrylicDisplayCaseDefinition,
	visual_roots: Array[Node3D] = []
) -> void:
	_grid = grid
	_terrain_manager = terrain_manager
	_definition = definition
	_visual_roots = visual_roots.duplicate()
	_ensure_roots()
	visible = _definition != null and _definition.feature_enabled


func rebuild_for_level() -> bool:
	_ensure_roots()
	_clear_generated_geometry()
	if _definition == null or not _definition.feature_enabled or _grid == null or _grid.get_shape() == null:
		visible = false
		return false
	var cells := _grid.enumerate_cells()
	if cells.is_empty():
		visible = false
		return false
	visible = true
	_content_bounds = _calculate_content_bounds(cells)
	_build_geometry(_content_bounds)
	return true


func apply_lighting(definition: DisplayCaseLightingDefinition) -> void:
	if definition == null:
		return
	for material in _panel_materials:
		material.set_shader_parameter("glass_tint", definition.glass_tint)
		material.set_shader_parameter("stripe_color", definition.stripe_color)
		material.set_shader_parameter("base_alpha", definition.base_alpha)
		material.set_shader_parameter("fresnel_alpha", definition.fresnel_alpha)
		material.set_shader_parameter("fresnel_power", definition.fresnel_power)
		material.set_shader_parameter("border_alpha", definition.border_alpha)
		material.set_shader_parameter("stripe_width", definition.stripe_width)
		material.set_shader_parameter("stripe_strength", definition.stripe_strength)
	if _edge_material != null:
		var edge_color := definition.edge_color
		edge_color.a = definition.edge_alpha
		_edge_material.albedo_color = edge_color
		_edge_material.emission = definition.edge_color
		_edge_material.emission_energy_multiplier = definition.edge_emission_energy


func get_content_bounds() -> AABB:
	return _content_bounds


func get_case_size() -> Vector3:
	return _case_size


func get_panel_count() -> int:
	return _panels_root.get_child_count() if _panels_root != null else 0


func get_edge_count() -> int:
	return _edges_root.get_child_count() if _edges_root != null else 0


func get_base_mesh() -> MeshInstance3D:
	if _base_root == null:
		return null
	return _base_root.get_node_or_null("WoodenBase") as MeshInstance3D


func get_projectile_reflection_surface_count() -> int:
	if (
		_definition == null
		or not _definition.feature_enabled
		or not _definition.projectile_reflection_enabled
		or _case_size.x <= 0.0
		or _case_size.y <= 0.0
		or _case_size.z <= 0.0
	):
		return 0
	return 4


## Returns the nearest inward-facing intersection on the four finite side panels.
## The top panel is presentation-only and deliberately excluded from gameplay.
## Result keys match MirrorManager.trace_projectile_reflection().
func trace_projectile_reflection(start: Vector3, end: Vector3) -> Dictionary:
	var segment_length := start.distance_to(end)
	var result := {
		"hit": false,
		"position": end,
		"normal": Vector3.ZERO,
		"distance": segment_length,
		"mirror": null,
		"reflector": self,
		"surface_id": StringName(),
		"epsilon": 0.0001,
		"max_reflections_per_frame": 1,
	}
	if get_projectile_reflection_surface_count() == 0 or segment_length <= 0.000001:
		return result
	var local_start := to_local(start)
	var local_end := to_local(end)
	var local_segment := local_end - local_start
	if local_segment.length_squared() <= 0.000001:
		return result
	var center_x := _content_bounds.position.x + _content_bounds.size.x * 0.5
	var center_z := _content_bounds.position.z + _content_bounds.size.z * 0.5
	var minimum_x := center_x - _case_size.x * 0.5
	var maximum_x := center_x + _case_size.x * 0.5
	var minimum_z := center_z - _case_size.z * 0.5
	var maximum_z := center_z + _case_size.z * 0.5
	var minimum_y := _content_bounds.position.y
	var maximum_y := minimum_y + _case_size.y
	var surfaces: Array[Dictionary] = [
		{"id": &"front", "point": Vector3(center_x, minimum_y, maximum_z), "normal": Vector3.FORWARD},
		{"id": &"back", "point": Vector3(center_x, minimum_y, minimum_z), "normal": Vector3.BACK},
		{"id": &"left", "point": Vector3(minimum_x, minimum_y, center_z), "normal": Vector3.RIGHT},
		{"id": &"right", "point": Vector3(maximum_x, minimum_y, center_z), "normal": Vector3.LEFT},
	]
	var best_fraction := INF
	var best_local_normal := Vector3.ZERO
	var best_surface_ids: Array[StringName] = []
	for surface in surfaces:
		var normal: Vector3 = surface.get("normal", Vector3.ZERO)
		var denominator := local_segment.dot(normal)
		# Each active face points inward. Travel from outside to inside passes through.
		if denominator >= -0.000001:
			continue
		var plane_point: Vector3 = surface.get("point", Vector3.ZERO)
		var signed_start := (local_start - plane_point).dot(normal)
		if signed_start < -0.000001:
			continue
		var fraction := -signed_start / denominator
		if fraction <= 0.000001 or fraction > 1.0:
			continue
		var local_hit := local_start + local_segment * fraction
		if local_hit.y < minimum_y - 0.0001 or local_hit.y > maximum_y + 0.0001:
			continue
		var surface_id: StringName = surface.get("id", StringName())
		var inside_panel := (
			local_hit.x >= minimum_x - 0.0001 and local_hit.x <= maximum_x + 0.0001
			if surface_id == &"front" or surface_id == &"back"
			else local_hit.z >= minimum_z - 0.0001 and local_hit.z <= maximum_z + 0.0001
		)
		if not inside_panel:
			continue
		if fraction < best_fraction - 0.000001:
			best_fraction = fraction
			best_local_normal = normal
			best_surface_ids.assign([surface_id])
		elif absf(fraction - best_fraction) <= 0.000001:
			# Exact corner impacts reflect both outward components instead of leaking.
			best_local_normal = (best_local_normal + normal).normalized()
			best_surface_ids.append(surface_id)
	if not is_finite(best_fraction):
		return result
	var world_normal := (global_basis * best_local_normal).normalized()
	result.hit = true
	result.position = start.lerp(end, best_fraction)
	result.normal = world_normal
	result.distance = segment_length * best_fraction
	result.surface_id = StringName("+".join(PackedStringArray(best_surface_ids)))
	result.epsilon = maxf(0.0001, _grid.cell_size * _definition.collision_epsilon_ratio)
	result.max_reflections_per_frame = _definition.max_reflections_per_frame
	return result


func _ensure_roots() -> void:
	if _base_root == null:
		_base_root = Node3D.new()
		_base_root.name = "Base"
		add_child(_base_root)
	if _panels_root == null:
		_panels_root = Node3D.new()
		_panels_root.name = "Panels"
		add_child(_panels_root)
	if _edges_root == null:
		_edges_root = Node3D.new()
		_edges_root.name = "Edges"
		add_child(_edges_root)


func _clear_generated_geometry() -> void:
	for root_node in [_base_root, _panels_root, _edges_root]:
		if root_node == null:
			continue
		for child in root_node.get_children():
			child.free()
	_panel_materials.clear()
	_edge_material = null
	_case_size = Vector3.ZERO


func _calculate_content_bounds(cells: Array[Vector3i]) -> AABB:
	var minimum := Vector3(INF, 0.0, INF)
	var maximum := Vector3(-INF, 0.0, -INF)
	var layer_height := _grid.cell_size
	if _terrain_manager != null and _terrain_manager.get_layer_height() > 0.0:
		layer_height = _terrain_manager.get_layer_height()
	minimum.y = -layer_height
	maximum.y = 0.0
	for cell in cells:
		for corner in _grid.get_corners(cell):
			minimum.x = minf(minimum.x, corner.x)
			minimum.z = minf(minimum.z, corner.z)
			maximum.x = maxf(maximum.x, corner.x)
			maximum.z = maxf(maximum.z, corner.z)
		if _terrain_manager != null:
			maximum.y = maxf(maximum.y, _terrain_manager.get_world_height(cell))
	var visual_bounds_state := {
		"minimum": minimum,
		"maximum": maximum,
	}
	for visual_root in _visual_roots:
		_include_visual_bounds(visual_root, visual_bounds_state)
	minimum = visual_bounds_state.get("minimum", minimum)
	maximum = visual_bounds_state.get("maximum", maximum)
	var margin := _definition.horizontal_margin_cells * _grid.cell_size
	minimum.x -= margin
	minimum.z -= margin
	maximum.x += margin
	maximum.z += margin
	return AABB(minimum, maximum - minimum)


func _include_visual_bounds(node: Node, bounds_state: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var minimum: Vector3 = bounds_state.get("minimum", Vector3(INF, INF, INF))
	var maximum: Vector3 = bounds_state.get("maximum", Vector3(-INF, -INF, -INF))
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var relative_transform := global_transform.affine_inverse() * mesh_instance.global_transform
			var visual_bounds: AABB = relative_transform * mesh_instance.get_aabb()
			var visual_end := visual_bounds.end
			minimum.x = minf(minimum.x, visual_bounds.position.x)
			minimum.y = minf(minimum.y, visual_bounds.position.y)
			minimum.z = minf(minimum.z, visual_bounds.position.z)
			maximum.x = maxf(maximum.x, visual_end.x)
			maximum.y = maxf(maximum.y, visual_end.y)
			maximum.z = maxf(maximum.z, visual_end.z)
			bounds_state["minimum"] = minimum
			bounds_state["maximum"] = maximum
	for child in node.get_children():
		_include_visual_bounds(child, bounds_state)


func _build_geometry(bounds: AABB) -> void:
	var cell_size := _grid.cell_size
	var base_top := bounds.position.y
	var minimum_top := base_top + _definition.minimum_interior_height_cells * cell_size
	var content_top := bounds.end.y + _definition.top_margin_cells * cell_size
	var top_y := maxf(minimum_top, content_top)
	var width := bounds.size.x
	var depth := bounds.size.z
	var height := top_y - base_top
	var center_x := bounds.position.x + width * 0.5
	var center_z := bounds.position.z + depth * 0.5
	_case_size = Vector3(width, height, depth)

	_build_base(Vector3(center_x, base_top, center_z), width, depth, cell_size)
	_build_panels(Vector3(center_x, base_top, center_z), width, height, depth)
	_build_edges(Vector3(center_x, base_top, center_z), width, height, depth, cell_size)


func _build_base(center: Vector3, width: float, depth: float, cell_size: float) -> void:
	var overhang := _definition.base_overhang_cells * cell_size
	var thickness := _definition.base_thickness_cells * cell_size
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(width + overhang * 2.0, thickness, depth + overhang * 2.0)
	var base_instance := MeshInstance3D.new()
	base_instance.name = "WoodenBase"
	base_instance.mesh = base_mesh
	base_instance.position = center + Vector3.DOWN * thickness * 0.5
	var wood_material := StandardMaterial3D.new()
	wood_material.albedo_color = _definition.wood_color
	wood_material.roughness = _definition.wood_roughness
	wood_material.metallic = 0.0
	base_instance.material_override = wood_material
	_base_root.add_child(base_instance)

	var gasket := _definition.gasket_thickness_cells * cell_size
	var gasket_material := StandardMaterial3D.new()
	gasket_material.albedo_color = _definition.gasket_color
	gasket_material.roughness = 0.72
	_add_box(_base_root, "GasketFront", Vector3(width, gasket, gasket), center + Vector3(0.0, gasket * 0.5, depth * 0.5), gasket_material, true)
	_add_box(_base_root, "GasketBack", Vector3(width, gasket, gasket), center + Vector3(0.0, gasket * 0.5, -depth * 0.5), gasket_material, true)
	_add_box(_base_root, "GasketLeft", Vector3(gasket, gasket, depth), center + Vector3(-width * 0.5, gasket * 0.5, 0.0), gasket_material, true)
	_add_box(_base_root, "GasketRight", Vector3(gasket, gasket, depth), center + Vector3(width * 0.5, gasket * 0.5, 0.0), gasket_material, true)


func _build_panels(center: Vector3, width: float, height: float, depth: float) -> void:
	var middle_y := center.y + height * 0.5
	_add_panel("Front", Vector2(width, height), Vector3(center.x, middle_y, center.z + depth * 0.5), Vector3.ZERO, 0.52)
	_add_panel("Back", Vector2(width, height), Vector3(center.x, middle_y, center.z - depth * 0.5), Vector3(0.0, PI, 0.0), 0.70)
	_add_panel("Left", Vector2(depth, height), Vector3(center.x - width * 0.5, middle_y, center.z), Vector3(0.0, -PI * 0.5, 0.0), 0.62)
	_add_panel("Right", Vector2(depth, height), Vector3(center.x + width * 0.5, middle_y, center.z), Vector3(0.0, PI * 0.5, 0.0), 0.42)
	if _definition.top_panel_enabled:
		_add_panel("Top", Vector2(width, depth), Vector3(center.x, center.y + height, center.z), Vector3(-PI * 0.5, 0.0, 0.0), 0.82)


func _add_panel(
	panel_name: String,
	size: Vector2,
	panel_position: Vector3,
	panel_rotation: Vector3,
	stripe_position: float
) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var panel := MeshInstance3D.new()
	panel.name = panel_name
	panel.mesh = quad
	panel.position = panel_position
	panel.rotation = panel_rotation
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = AcrylicGlassShader
	material.render_priority = -30
	material.set_shader_parameter("stripe_position", stripe_position)
	panel.material_override = material
	_panel_materials.append(material)
	_panels_root.add_child(panel)


func _build_edges(center: Vector3, width: float, height: float, depth: float, cell_size: float) -> void:
	var thickness := _definition.edge_thickness_cells * cell_size
	_edge_material = StandardMaterial3D.new()
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_edge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_edge_material.emission_enabled = true
	_edge_material.render_priority = -20
	var bottom_y := center.y + thickness * 0.5
	var top_y := center.y + height - thickness * 0.5
	var middle_y := center.y + height * 0.5
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_box(
				_edges_root,
				"Vertical_%d_%d" % [int(x_sign), int(z_sign)],
				Vector3(thickness, height, thickness),
				Vector3(center.x + x_sign * width * 0.5, middle_y, center.z + z_sign * depth * 0.5),
				_edge_material,
				false
			)
	for y_value in [bottom_y, top_y]:
		var layer_name := "Bottom" if is_equal_approx(y_value, bottom_y) else "Top"
		_add_box(_edges_root, "%sFront" % layer_name, Vector3(width, thickness, thickness), Vector3(center.x, y_value, center.z + depth * 0.5), _edge_material, false)
		_add_box(_edges_root, "%sBack" % layer_name, Vector3(width, thickness, thickness), Vector3(center.x, y_value, center.z - depth * 0.5), _edge_material, false)
		_add_box(_edges_root, "%sLeft" % layer_name, Vector3(thickness, thickness, depth), Vector3(center.x - width * 0.5, y_value, center.z), _edge_material, false)
		_add_box(_edges_root, "%sRight" % layer_name, Vector3(thickness, thickness, depth), Vector3(center.x + width * 0.5, y_value, center.z), _edge_material, false)


func _add_box(
	parent: Node3D,
	instance_name: String,
	size: Vector3,
	box_position: Vector3,
	material: Material,
	cast_shadow: bool
) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = box
	instance.position = box_position
	instance.material_override = material
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(instance)
	return instance
