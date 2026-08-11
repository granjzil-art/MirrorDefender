extends SceneTree

const MainScene := preload("res://scenes/Main.tscn")
const FormalLevel := preload("res://resources/levels/Level2.tres")
const DofDefinition := preload("res://resources/camera/MiniatureDofDefault.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[MiniatureDof] running")
	_test_definition()
	await _test_formal_level_runtime()
	await _test_dynamic_focus_scaling()
	if _failures == 0:
		print("[MiniatureDof] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MiniatureDof] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_definition() -> void:
	_expect(DofDefinition != null, "default miniature DOF resource loads")
	_expect(DofDefinition.validate_configuration().is_empty(), "default miniature DOF resource validates")
	_expect(DofDefinition.near_blur_enabled and DofDefinition.far_blur_enabled, "near and far depth blur are enabled")


func _test_formal_level_runtime() -> void:
	var main := MainScene.instantiate() as MainController
	_expect(main != null and main.configure_startup_level(FormalLevel), "Level2 configures for DOF test")
	root.add_child(main)
	await process_frame
	await process_frame
	var controller := main.miniature_dof_controller
	var camera := main.cam_rig.get_camera()
	_expect(controller != null, "Main creates MiniatureDofController")
	_expect(controller.is_effect_enabled(), "miniature DOF starts enabled")
	_expect(camera.attributes is CameraAttributesPractical, "main Camera3D owns practical camera attributes")
	var attributes := camera.attributes as CameraAttributesPractical
	_expect(attributes.dof_blur_near_enabled, "near blur is active")
	_expect(attributes.dof_blur_far_enabled, "far blur is active")
	_expect(attributes.dof_blur_amount > 0.0, "blur amount is visible")
	_expect(controller.get_near_distance() < controller.get_focus_depth(), "near blur begins before the focus plane")
	_expect(controller.get_far_distance() > controller.get_focus_depth(), "far blur begins behind the focus plane")
	controller.set_effect_enabled(false)
	_expect(camera.attributes == null, "disabling DOF restores the original camera attributes")
	controller.set_effect_enabled(true)
	_expect(camera.attributes == attributes, "re-enabling DOF restores the runtime attributes")
	main.queue_free()
	await process_frame


func _test_dynamic_focus_scaling() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var rig := Node3D.new()
	host.add_child(rig)
	var camera := Camera3D.new()
	rig.add_child(camera)
	camera.position = Vector3(0.0, 8.0, 8.0)
	camera.look_at(Vector3.ZERO)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(6, 6))
	var definition := DofDefinition.duplicate(true) as MiniatureDofDefinition
	var controller := MiniatureDofController.new()
	host.add_child(controller)
	_expect(controller.configure(camera, rig, grid, definition), "standalone DOF controller configures")
	var first_focus := controller.get_focus_depth()
	var first_band := controller.get_far_distance() - controller.get_near_distance()
	camera.position = Vector3(0.0, 12.0, 12.0)
	camera.look_at(Vector3.ZERO)
	_expect(controller.refresh_now(true), "focus refreshes after camera zoom changes")
	_expect(controller.get_focus_depth() > first_focus, "focus plane follows camera distance")
	grid.apply_configuration(GridManager.Shape.SQUARE, 2.0, Vector2i(3, 3))
	_expect(controller.refresh_now(true), "DOF refreshes for a square grid with different cell size")
	var second_band := controller.get_far_distance() - controller.get_near_distance()
	_expect(second_band > first_band, "clear focus band scales with grid cell size")
	definition.blur_amount = 0.06
	definition.near_transition_cells = 4.0
	_expect(controller.refresh_now(), "resource edits refresh without moving the camera")
	var attributes := controller.get_camera_attributes()
	_expect(is_equal_approx(attributes.dof_blur_amount, 0.06), "runtime blur amount edits reach CameraAttributes")
	_expect(
		is_equal_approx(attributes.dof_blur_near_transition, 8.0),
		"runtime transition edits remain scaled by cell size"
	)
	host.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
