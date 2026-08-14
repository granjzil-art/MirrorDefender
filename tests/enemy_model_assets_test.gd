extends SceneTree

const EXPECTED_MODELS: Array[Dictionary] = [
	{
		"definition": "res://resources/enemies/Flyer.tres",
		"scene": "res://assets/enemies/Flyers/flyer_runtime.tscn",
		"scale": Vector3(0.9, 0.9, 0.9),
		"animation": &"",
		"height_range": Vector2(0.5, 1.5),
	},
	{
		"definition": "res://resources/enemies/EliteMage.tres",
		"scene": "res://assets/enemies/wizard/wizard.tscn",
		"scale": Vector3(0.5, 0.5, 0.5),
		"animation": &"",
	},
	{
		"definition": "res://resources/enemies/SingleShieldSoldier.tres",
		"scene": "res://assets/enemies/low_poly_wild_boar/wild_boar.tscn",
		"scale": Vector3(0.45, 0.45, 0.45),
		"animation": &"",
	},
	{
		"definition": "res://resources/enemies/DoubleShieldSoldier.tres",
		"scene": "res://assets/enemies/stone-golem/stone_golem.tscn",
		"scale": Vector3(0.6, 0.6, 0.6),
		"animation": &"Defense(1_19)",
	},
	{
		"definition": "res://resources/enemies/EliteTitan.tres",
		"scene": "res://assets/enemies/low_poly_mammoth/mammoth.tscn",
		"scale": Vector3(0.84, 0.84, 0.84),
		"animation": &"Walk",
	},
	{
		"definition": "res://resources/enemies/Runner.tres",
		"scene": "res://assets/enemies/low_poly_fox/fox.tscn",
		"scale": Vector3(0.008, 0.008, 0.008),
		"animation": &"Take 001",
		"section": Vector2(14.75, 15.9),
	},
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[EnemyModelAssets] running")
	for expected in EXPECTED_MODELS:
		await _test_model(expected)
	if _failures == 0:
		print("[EnemyModelAssets] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[EnemyModelAssets] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_model(expected: Dictionary) -> void:
	var definition_path := String(expected.get("definition", ""))
	var definition := ResourceLoader.load(
		definition_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as EnemyDefinition
	_expect(definition != null, "%s loads" % definition_path.get_file())
	if definition == null:
		return
	var asset := definition.get_model_asset()
	_expect(asset != null and asset.scene != null, "%s owns a model asset" % definition_path.get_file())
	if asset == null or asset.scene == null:
		return
	_expect(
		asset.scene.resource_path == String(expected.get("scene", "")),
		"%s references the intended model scene" % definition_path.get_file()
	)
	var expected_scale: Vector3 = expected.get("scale", Vector3.ONE)
	_expect(
		asset.runtime_scale.is_equal_approx(expected_scale),
		"%s uses the intended runtime scale" % definition_path.get_file()
	)
	_expect(
		asset.validate_configuration().is_empty(),
		"%s model asset passes validation" % definition_path.get_file()
	)
	var bounds_result := asset.get_authored_visual_bounds()
	var bounds: AABB = bounds_result.get("bounds", AABB())
	var runtime_height := bounds.size.y * asset.runtime_scale.y
	var height_range: Vector2 = expected.get("height_range", Vector2(0.5, 1.3))
	_expect(
		bool(bounds_result.get("valid", false))
		and runtime_height >= height_range.x
		and runtime_height <= height_range.y,
		"%s model is normalized to a gameplay-sized height" % definition_path.get_file()
	)
	var animation_name: StringName = expected.get("animation", &"")
	if animation_name == &"":
		return
	var unit := EnemyUnit.new()
	unit.debug_visual_enabled = false
	unit.configure_unit(
		definition,
		PackedVector3Array([Vector3.ZERO, Vector3.RIGHT]),
		[Vector3i.ZERO, Vector3i(1, 0, 0)]
	)
	root.add_child(unit)
	await process_frame
	var animation_player := _find_animation_player(unit)
	_expect(animation_player != null, "%s runtime model contains an AnimationPlayer" % definition_path.get_file())
	if animation_player != null:
		_expect(
			animation_player.has_animation(animation_name),
			"%s exposes animation %s" % [definition_path.get_file(), String(animation_name)]
		)
		var animation := animation_player.get_animation(animation_name)
		_expect(
			animation != null and animation.loop_mode == Animation.LOOP_LINEAR,
			"%s animation loops" % definition_path.get_file()
		)
		_expect(
			animation_player.is_playing() and animation_player.current_animation == animation_name,
			"%s animation starts automatically" % definition_path.get_file()
		)
		if expected.has("section"):
			var expected_section: Vector2 = expected.get("section", Vector2.ZERO)
			_expect(animation_player.has_section(), "%s plays only an animation section" % definition_path.get_file())
			_expect(
				is_equal_approx(animation_player.get_section_start_time(), expected_section.x)
				and is_equal_approx(animation_player.get_section_end_time(), expected_section.y),
				"%s uses the final running section" % definition_path.get_file()
			)
			animation_player.advance(expected_section.y - expected_section.x + 0.2)
			_expect(
				animation_player.current_animation_position >= expected_section.x
				and animation_player.current_animation_position <= expected_section.y,
				"%s running section loops without returning to earlier clips" % definition_path.get_file()
			)
	unit.queue_free()
	await process_frame


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	print("  FAIL: %s" % message)
