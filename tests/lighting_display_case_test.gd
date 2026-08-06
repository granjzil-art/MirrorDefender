extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const DemoLevel1 := preload("res://resources/levels/DemoLevel1.tres")
const CaseDefinition := preload("res://resources/lighting/AcrylicDisplayCase.tres")
const WhiteSoft := preload("res://resources/lighting/WhiteSoft.tres")
const WarmYellow := preload("res://resources/lighting/WarmYellow.tres")
const CyanRed := preload("res://resources/lighting/CyanRedContrast.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[LightingDisplayCase] running")
	_test_profile_resources()
	await _test_demo_level_runtime()
	await _test_dynamic_case_bounds()
	if _failures == 0:
		print("[LightingDisplayCase] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[LightingDisplayCase] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_profile_resources() -> void:
	var profiles: Array[LightingProfile] = [WhiteSoft, WarmYellow, CyanRed]
	var expected_ids := [&"white_soft", &"warm_yellow", &"cyan_red_contrast"]
	for index in range(profiles.size()):
		var profile := profiles[index]
		_expect(profile != null, "profile %d loads" % index)
		_expect(profile.profile_id == expected_ids[index], "profile %d keeps stable id" % index)
		_expect(profile.validate_configuration().is_empty(), "profile %d validates" % index)


func _test_demo_level_runtime() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(DemoLevel1), "DemoLevel1 configures as startup level")
	root.add_child(main)
	await process_frame
	await process_frame
	var controller := main.lighting_controller
	_expect(controller != null, "DemoLevel1 creates LightingController")
	_expect(controller.get_active_profile() == WhiteSoft, "DemoLevel1 starts with white soft profile")
	_expect(controller.get_generated_light_count() == 2, "white soft profile creates two lights")
	var display_case := controller.get_display_case()
	_expect(display_case != null, "DemoLevel1 creates acrylic display case")
	_expect(display_case.get_panel_count() == 5, "display case creates four walls and a top")
	_expect(display_case.get_edge_count() == 12, "display case creates twelve acrylic edges")
	_expect(display_case.get_base_mesh() != null, "display case creates wooden base")
	var demo_size := display_case.get_case_size()
	_expect(demo_size.x > 20.0 and demo_size.z > 9.0, "DemoLevel1 20x9 grid expands case with margin")
	_expect(demo_size.y >= 4.5, "case height preserves minimum diorama clearance")
	_expect(_count_collision_nodes(display_case) == 0, "display case never blocks gameplay picking")
	_expect(controller.get_reflection_probe() != null, "display case owns one reflection probe")
	_expect(controller.apply_profile_by_index(1, 0.0), "warm profile switches immediately")
	_expect(controller.get_active_profile() == WarmYellow, "warm profile becomes active")
	_expect(controller.get_generated_light_count() == 2, "warm profile creates two lights")
	_expect(controller.apply_profile_by_index(2, 0.0), "cyan-red profile switches immediately")
	_expect(controller.get_active_profile() == CyanRed, "cyan-red profile becomes active")
	_expect(controller.get_generated_light_count() == 3, "cyan-red profile creates three lights")
	main.queue_free()
	await process_frame


func _test_dynamic_case_bounds() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(20, 9))
	var display_case := AcrylicDisplayCase.new()
	host.add_child(display_case)
	display_case.configure(grid, null, CaseDefinition)
	_expect(display_case.rebuild_for_level(), "case builds from grid without authored mesh dependency")
	var large_size := display_case.get_case_size()
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(4, 3))
	_expect(display_case.rebuild_for_level(), "case rebuilds after grid size changes")
	var small_size := display_case.get_case_size()
	_expect(small_size.x < large_size.x and small_size.z < large_size.z, "case dimensions follow smaller level")
	grid.apply_configuration(GridManager.Shape.HEX, 1.25, Vector2i(3, 3))
	_expect(display_case.rebuild_for_level(), "case rebuilds for HEX grid and different cell size")
	var hex_size := display_case.get_case_size()
	_expect(hex_size.x > 0.0 and hex_size.z > 0.0, "HEX case dimensions remain valid")
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
