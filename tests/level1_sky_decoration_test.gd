extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level1 := preload("res://resources/levels/Level1.tres")
const Level2 := preload("res://resources/levels/Level2.tres")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[Level1SkyDecoration] running")
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(Level1), "Level1 configures as the startup level")
	root.add_child(main)
	for _frame in 6:
		await process_frame

	var decoration := main.get_level_decoration()
	_expect(decoration != null, "Level1 instantiates its sky decoration scene")
	if decoration != null:
		_expect(decoration.get_sun_count() == 1, "Level1 creates one large sun")
		_expect(decoration.get_cloud_count() == 16, "Level1 fills the surrounding volume with sixteen clouds")
		_expect(decoration.get_emissive_mesh_count(&"sky_sun") == 1, "the visible sun mesh is emissive")
		_expect(decoration.get_emissive_mesh_count(&"sky_cloud") == 16, "every visible cloud mesh is emissive")
		_expect(_each_cloud_selects_one_mesh(decoration), "each cloud wrapper selects exactly one of the four source models")
		_expect(decoration.sun_emission_energy > decoration.cloud_emission_energy, "sun self-emission is stronger than cloud self-emission")
		_expect(_materials_match_authored_energy(decoration), "runtime materials preserve the separate sun and cloud intensities")
		_expect(_count_nodes_of_type(decoration, OmniLight3D) == 1, "the sun adds one local warm light")
		_expect(_count_collision_nodes(decoration) == 0, "sky decorations add no gameplay collision")
		var display_case := main.lighting_controller.get_display_case()
		_expect(display_case != null, "Level1 display case is available")
		if display_case != null:
			_expect(_all_models_clear_case(decoration, display_case), "side and overhead models preserve display-case viewing clearance")

	_expect(main.level_loader.load_level(Level2, Level2.resource_path), "another level can replace Level1")
	await process_frame
	_expect(main.get_level_decoration() == null, "Level1 sky decorations are removed after switching to Level2")

	main.queue_free()
	await process_frame
	if _failures == 0:
		print("[Level1SkyDecoration] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[Level1SkyDecoration] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _each_cloud_selects_one_mesh(decoration: Node) -> bool:
	for child in decoration.get_children():
		if child.is_in_group(&"sky_cloud"):
			if not child.has_method(&"get_visible_mesh_count") or child.get_visible_mesh_count() != 1:
				return false
	return true


func _materials_match_authored_energy(decoration: Node) -> bool:
	for child in decoration.get_children():
		var expected_energy := -1.0
		if child.is_in_group(&"sky_sun"):
			expected_energy = decoration.sun_emission_energy
		elif child.is_in_group(&"sky_cloud"):
			expected_energy = decoration.cloud_emission_energy
		if expected_energy < 0.0:
			continue
		if not _visible_materials_match_energy(child, expected_energy):
			return false
	return true


func _visible_materials_match_energy(node: Node, expected_energy: float) -> bool:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree():
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
				if material == null or not material.emission_enabled:
					return false
				if not is_equal_approx(material.emission_energy_multiplier, expected_energy):
					return false
	for child in node.get_children():
		if not _visible_materials_match_energy(child, expected_energy):
			return false
	return true


func _all_models_clear_case(decoration: Node, display_case: AcrylicDisplayCase) -> bool:
	var content_bounds := display_case.get_content_bounds()
	var case_size := display_case.get_case_size()
	var minimum_x := content_bounds.position.x
	var maximum_x := content_bounds.end.x
	var minimum_z := content_bounds.position.z
	var maximum_z := content_bounds.end.z
	var top_y := content_bounds.position.y + case_size.y
	for child in decoration.get_children():
		if not child is Node3D:
			continue
		if not child.is_in_group(&"sky_sun") and not child.is_in_group(&"sky_cloud"):
			continue
		var visual_bounds: AABB = decoration.get_visual_bounds(child as Node3D)
		var outside_sides: bool = (
			visual_bounds.end.x <= minimum_x - 1.0
			or visual_bounds.position.x >= maximum_x + 1.0
			or visual_bounds.end.z <= minimum_z - 1.0
			or visual_bounds.position.z >= maximum_z + 1.0
		)
		var safely_overhead: bool = visual_bounds.position.y >= top_y + 2.0
		if not outside_sides and not safely_overhead:
			print("  Clearance failure: %s bounds=%s case_top=%.3f" % [child.name, visual_bounds, top_y])
			return false
	return true


func _count_nodes_of_type(node: Node, type: Variant) -> int:
	var count := 1 if is_instance_of(node, type) else 0
	for child in node.get_children():
		count += _count_nodes_of_type(child, type)
	return count


func _count_collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_nodes(child)
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + message)
		return
	_failures += 1
	print("  FAIL: " + message)
