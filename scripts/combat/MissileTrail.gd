## Short world-space ribbon that survives long enough to fade after its missile.
class_name MissileTrail
extends Node3D

const MIN_POINT_DISTANCE_SQUARED := 0.000025

var _source: Node3D
var _width: float = 0.05
var _lifetime: float = 0.4
var _color: Color = Color(1.0, 0.45, 0.08, 0.9)
var _points: Array[Dictionary] = []
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func configure(source: Node3D, width: float, lifetime: float, color: Color) -> void:
	_source = source
	_width = maxf(0.005, width)
	_lifetime = maxf(0.05, lifetime)
	_color = color
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_visual()
	_append_source_point()


func _process(delta: float) -> void:
	var resolved_delta := maxf(0.0, delta)
	for point in _points:
		point["age"] = float(point.get("age", 0.0)) + resolved_delta
	while not _points.is_empty() and float(_points[0].get("age", 0.0)) >= _lifetime:
		_points.pop_front()
	if _source != null and is_instance_valid(_source) and not _source.is_queued_for_deletion():
		_append_source_point()
	else:
		_source = null
	_rebuild_mesh()
	if _source == null and _points.is_empty():
		queue_free()


func _append_source_point() -> void:
	if _source == null or not is_instance_valid(_source):
		return
	var world_position := _source.global_position
	if _source.has_method("get_trail_position"):
		world_position = _source.call("get_trail_position")
	if not _points.is_empty():
		var previous: Vector3 = _points[-1].get("position", world_position)
		if previous.distance_squared_to(world_position) < MIN_POINT_DISTANCE_SQUARED:
			_points[-1]["age"] = 0.0
			return
	_points.append({"position": world_position, "age": 0.0})
	while _points.size() > 96:
		_points.pop_front()


func _build_visual() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = &"MissileTrailRibbon"
	_mesh_instance.mesh = _mesh
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.emission_enabled = true
	_material.emission = _color
	_material.emission_energy_multiplier = 3.2
	add_child(_mesh_instance)


func _rebuild_mesh() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for index in range(_points.size()):
		var entry := _points[index]
		var position_world: Vector3 = entry.get("position", Vector3.ZERO)
		var previous_world: Vector3 = _points[maxi(0, index - 1)].get("position", position_world)
		var next_world: Vector3 = _points[mini(_points.size() - 1, index + 1)].get("position", position_world)
		var tangent := (next_world - previous_world).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		if side.length_squared() <= 0.000001:
			side = Vector3.RIGHT
		var life_factor := clampf(1.0 - float(entry.get("age", 0.0)) / _lifetime, 0.0, 1.0)
		var order_factor := float(index + 1) / float(_points.size())
		var alpha := life_factor * order_factor * _color.a
		var half_width := _width * lerpf(0.15, 0.5, order_factor)
		var vertex_color := Color(_color.r, _color.g, _color.b, alpha)
		_mesh.surface_set_color(vertex_color)
		_mesh.surface_add_vertex(to_local(position_world + side * half_width))
		_mesh.surface_set_color(vertex_color)
		_mesh.surface_add_vertex(to_local(position_world - side * half_width))
	_mesh.surface_end()
