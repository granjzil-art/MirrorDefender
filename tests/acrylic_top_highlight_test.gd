extends SceneTree

const Level1 := preload("res://resources/levels/Level1.tres")
const Level2 := preload("res://resources/levels/Level2.tres")
const Level3 := preload("res://resources/levels/Level3.tres")
const Level4 := preload("res://resources/levels/Level4.tres")
const WhiteSoft := preload("res://resources/lighting/WhiteSoft.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[AcrylicTopHighlight] running")
	var levels: Array[LevelResource] = [Level1, Level2, Level3, Level4]
	var definition_ids: Dictionary = {}
	for level in levels:
		var definition := level.display_case_definition
		_expect(definition != null, "%s owns a display-case definition" % level.resource_path.get_file())
		_expect(
			definition != null and definition.validate_configuration().is_empty(),
			"%s display-case definition validates" % level.resource_path.get_file()
		)
		if definition != null:
			definition_ids[definition.get_instance_id()] = true
	_expect(definition_ids.size() == levels.size(), "all authored levels own independent display-case resources")
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(6, 5))
	var lighting := LightingController.new()
	host.add_child(lighting)
	var profiles: Array[LightingProfile] = [WhiteSoft]
	lighting.configure(null, null, grid, null, profiles)
	_expect(lighting.apply_level(Level1), "lighting controller builds the first level-owned display case")
	var display_case := lighting.get_display_case()
	_expect(
		display_case != null and display_case.get_definition() == Level1.display_case_definition,
		"runtime display case uses Level1's own definition"
	)
	var top := display_case.get_node_or_null("Panels/Top") as MeshInstance3D
	var front := display_case.get_node_or_null("Panels/Front") as MeshInstance3D
	_expect(top != null and front != null, "display case creates separate top and side panels")
	var top_material := top.material_override as ShaderMaterial if top != null else null
	var front_material := front.material_override as ShaderMaterial if front != null else null
	_expect(
		top_material != null
		and is_equal_approx(float(top_material.get_shader_parameter("surface_specular")), 0.0),
		"top panel disables the direct specular hotspot"
	)
	_expect(
		front_material != null
		and is_equal_approx(float(front_material.get_shader_parameter("surface_specular")), 0.9),
		"side panels retain their existing acrylic highlight"
	)
	display_case.apply_lighting(WhiteSoft.display_case_lighting)
	_expect(
		top_material != null
		and is_equal_approx(float(top_material.get_shader_parameter("surface_specular")), 0.0),
		"applying the existing lighting profile does not restore the top hotspot"
	)
	_expect(lighting.apply_level(Level2), "lighting controller accepts a second level-owned display case")
	_expect(
		display_case.get_definition() == Level2.display_case_definition
		and display_case.get_definition() != Level1.display_case_definition,
		"level switching replaces rather than shares the display-case definition"
	)
	host.queue_free()
	await process_frame
	if _failures == 0:
		print("[AcrylicTopHighlight] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[AcrylicTopHighlight] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
