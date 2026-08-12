extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const Level3 := preload("res://resources/levels/Level3.tres")
const Level1 := preload("res://resources/levels/Level1.tres")
const Level1SkyDecorationScript := preload("res://scripts/presentation/Level1SkyDecoration.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[LevelCelestialDecoration] running")
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(Level3), "Level3 configures as the startup level")
	root.add_child(main)
	for _frame in 4:
		await process_frame

	var decoration := main.get_level_decoration() as LevelCelestialDecoration
	_expect(decoration != null, "Level3 instantiates its celestial decoration scene")
	_expect(main.lighting_controller.get_active_profile() == Level3.lighting_profile, "Level3 activates the dark showcase lighting profile")
	if decoration != null:
		_expect(decoration.get_ornament_count() == 35, "Level3 creates one moon and thirty-four hanging stars")
		var emissive_mesh_count := decoration.get_emissive_mesh_count()
		if emissive_mesh_count != 35:
			print("  Emissive mesh count: %d" % emissive_mesh_count)
		_expect(emissive_mesh_count == 35, "every ornament mesh receives self-illumination")
		_expect(_all_ornaments_are_double_scale(decoration), "the moon and every star use exactly double their previous scale")
		_expect(_count_nodes_of_type(decoration, OmniLight3D) == 5, "the denser ornament volume adds five restrained warm lights")
		_expect(_count_collision_nodes(decoration) == 0, "showcase ornaments add no gameplay collision")
		_expect(_has_square_ceiling(decoration), "a 34-unit square ceiling plate covers every suspension point")
		_expect(_all_cords_meet_ceiling(decoration), "every suspension cord terminates at the ceiling underside")
		var display_case := main.lighting_controller.get_display_case()
		_expect(display_case != null, "Level3 display case is available")
		if display_case != null:
			_expect(_all_ornaments_clear_case(decoration, display_case), "side and overhead ornaments preserve display-case clearance")
			_expect(_top_ornaments_clear_case_by_five(decoration, display_case), "the lowest overhead star remains at least five units above the case top")

	_expect(main.level_loader.load_level(Level1, Level1.resource_path), "another level can replace Level3")
	await process_frame
	_expect(is_instance_of(main.get_level_decoration(), Level1SkyDecorationScript), "Level3 ornaments are replaced by Level1's sky decoration")

	main.queue_free()
	await process_frame
	if _failures == 0:
		print("[LevelCelestialDecoration] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[LevelCelestialDecoration] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _all_ornaments_clear_case(decoration: Node3D, display_case: AcrylicDisplayCase) -> bool:
	var bounds := display_case.get_content_bounds()
	var size := display_case.get_case_size()
	var minimum_x := bounds.position.x
	var maximum_x := bounds.end.x
	var minimum_z := bounds.position.z
	var maximum_z := bounds.end.z
	var top_y := bounds.position.y + size.y
	for child in decoration.get_children():
		if not child.is_in_group(&"celestial_ornament") or not child is Node3D:
			continue
		var position_3d := (child as Node3D).position
		var inside_footprint := (
			position_3d.x >= minimum_x
			and position_3d.x <= maximum_x
			and position_3d.z >= minimum_z
			and position_3d.z <= maximum_z
		)
		if inside_footprint:
			if position_3d.y < top_y + 0.5:
				print("  Overhead clearance failure: %s at %s; case top %.3f" % [child.name, position_3d, top_y])
				return false
			continue
		var clearance_x := maxf(maxf(minimum_x - position_3d.x, position_3d.x - maximum_x), 0.0)
		var clearance_z := maxf(maxf(minimum_z - position_3d.z, position_3d.z - maximum_z), 0.0)
		if maxf(clearance_x, clearance_z) < 0.75:
			print("  Side clearance failure: %s at %s" % [child.name, position_3d])
			return false
	return size.x > 0.0 and size.z > 0.0


func _all_ornaments_are_double_scale(decoration: LevelCelestialDecoration) -> bool:
	for child in decoration.get_children():
		if not child is Node3D or not child.is_in_group(&"celestial_ornament"):
			continue
		var ornament := child as Node3D
		var expected_minimum := 12.0 if child.name == &"Moon" else 4.4
		if ornament.scale.x < expected_minimum or not ornament.scale.is_equal_approx(Vector3.ONE * ornament.scale.x):
			return false
	return true


func _has_square_ceiling(decoration: LevelCelestialDecoration) -> bool:
	var ceiling := decoration.get_node_or_null("CeilingPlate") as MeshInstance3D
	var quad := ceiling.mesh as QuadMesh if ceiling != null else null
	return (
		quad != null
		and is_equal_approx(quad.size.x, 34.0)
		and is_equal_approx(quad.size.y, 34.0)
		and is_equal_approx(ceiling.position.y, decoration.ceiling_underside_y)
	)


func _all_cords_meet_ceiling(decoration: LevelCelestialDecoration) -> bool:
	for child in decoration.get_children():
		if not child is Node3D or not child.is_in_group(&"celestial_ornament"):
			continue
		var bounds := decoration.get_ornament_bounds(child as Node3D)
		if not is_equal_approx(bounds.end.y, decoration.ceiling_underside_y):
			return false
	return true


func _top_ornaments_clear_case_by_five(decoration: LevelCelestialDecoration, display_case: AcrylicDisplayCase) -> bool:
	var case_top := display_case.get_content_bounds().position.y + display_case.get_case_size().y
	for child in decoration.get_children():
		if not child is Node3D or not child.is_in_group(&"celestial_ornament") or not String(child.name).begins_with("Top"):
			continue
		var bounds := decoration.get_ornament_bounds(child as Node3D)
		if bounds.position.y < case_top + 5.0:
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
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
