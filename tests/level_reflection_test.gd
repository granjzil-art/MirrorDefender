extends SceneTree

const LevelReflectionDefinitionScript := preload("res://scripts/fx/LevelReflectionDefinition.gd")
const LevelReflectionSurfaceScript := preload("res://scripts/fx/LevelReflectionSurface.gd")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[LevelReflection] running")
	_test_definition_ranges()
	await _test_shape(GridManager.Shape.SQUARE, Vector2i(5, 3))
	await _test_shape(GridManager.Shape.HEX, Vector2i(2, 2))
	if _failures == 0:
		print("[LevelReflection] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[LevelReflection] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)

func _test_definition_ranges() -> void:
	var definition := LevelReflectionDefinitionScript.new()
	var vertical_offset_hint := ""
	for property_entry in definition.get_property_list():
		var property_data: Dictionary = property_entry
		var property_name: StringName = property_data.get("name", &"")
		if property_name == &"vertical_offset":
			vertical_offset_hint = str(property_data.get("hint_string", ""))
			break
	_expect(vertical_offset_hint.begins_with("0.02,20"), "vertical_offset Inspector range reaches 20 world units")

func _test_shape(shape: GridManager.Shape, grid_size: Vector2i) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(shape, 1.0, grid_size)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.global_position = Vector3(1.5, 8.0, 5.0)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var definition := LevelReflectionDefinitionScript.new()
	definition.vertical_offset = 0.25
	definition.edge_margin_cells = 2.0
	definition.reflection_resolution = 384
	definition.update_interval_frames = 1
	var reflection := LevelReflectionSurfaceScript.new()
	host.add_child(reflection)
	reflection.configure(grid, tile_manager, camera, definition)
	await process_frame

	var surface := reflection.get_surface()
	var viewport := reflection.get_reflection_viewport()
	var reflected_camera := reflection.get_reflection_camera()
	_expect(surface != null and surface.mesh is PlaneMesh, "%s builds one horizontal reflection plane" % grid.get_geometry_tag())
	_expect(surface.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s reflection plane never casts gameplay-scene shadows" % grid.get_geometry_tag())
	_expect(not surface.get_layer_mask_value(1) and surface.get_layer_mask_value(20), "%s reflection plane uses only the isolated reflection layer" % grid.get_geometry_tag())
	_expect(viewport != null and viewport.world_3d == host.get_world_3d(), "%s reflection viewport shares the live level World3D" % grid.get_geometry_tag())
	_expect(reflected_camera != null and not reflected_camera.get_cull_mask_value(20), "%s reflected camera excludes every reflection surface to stop recursion" % grid.get_geometry_tag())
	_expect(reflection.get_surface_y() < 0.0, "%s reflection plane stays below the terrain baseline" % grid.get_geometry_tag())
	_expect(reflection.get_surface_size().x > 1.0 and reflection.get_surface_size().y > 1.0, "%s reflection plane covers the grid plus configured margin" % grid.get_geometry_tag())
	_expect(viewport.size.x <= definition.reflection_resolution and viewport.size.y <= definition.reflection_resolution, "%s render target keeps its configured longest-edge budget" % grid.get_geometry_tag())
	_expect(reflection.refresh_now(), "%s schedules a live planar reflection refresh" % grid.get_geometry_tag())
	_expect(reflected_camera.projection == Camera3D.PROJECTION_FRUSTUM, "%s reflection camera uses a plane-fitted off-axis frustum" % grid.get_geometry_tag())
	var expected_y := 2.0 * reflection.get_surface_y() - camera.global_position.y
	_expect(is_equal_approx(reflected_camera.global_position.y, expected_y), "%s reflected eye mirrors the source camera across the horizontal plane" % grid.get_geometry_tag())
	var previous_eye := reflected_camera.global_position
	camera.global_position += Vector3(2.0, 1.0, -1.5)
	camera.look_at(Vector3.ZERO)
	reflection.refresh_now()
	_expect(reflected_camera.global_position.distance_to(previous_eye) > 0.1, "%s camera movement immediately changes the reflected viewpoint" % grid.get_geometry_tag())
	var previous_surface_y := reflection.get_surface_y()
	definition.vertical_offset += 0.25
	definition.emit_changed()
	_expect(reflection.get_surface_y() < previous_surface_y, "%s live definition changes rebuild the reflection surface" % grid.get_geometry_tag())
	_expect(_count_collision_nodes(reflection) == 0, "%s presentation node creates no collision or gameplay occupancy" % grid.get_geometry_tag())
	host.queue_free()
	await process_frame

func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_nodes(child)
	return count

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
