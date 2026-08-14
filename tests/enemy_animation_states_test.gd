extends SceneTree

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[EnemyAnimationStates] running")
	await _test_flyer_wing_overlay()
	await _test_titan_state_animations()
	await _test_double_shield_leg_overlay()
	await _test_simple_model_motions()
	if _failures == 0:
		print("[EnemyAnimationStates] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[EnemyAnimationStates] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_flyer_wing_overlay() -> void:
	var unit := await _spawn_unit("res://resources/enemies/Flyer.tres", true)
	var controller := _find_node_with_method(unit, &"get_overlay_animation_name")
	var player := _find_animation_player(unit)
	_expect(controller != null, "Flyer installs a bone overlay controller")
	_expect(
		player != null and not player.is_playing(),
		"Flyer disables the imported full-body Action so it cannot deform the wing skin"
	)
	if player != null:
		_expect(
			_count_wing_tracks(player.get_animation(&"Action")) > 0,
			"Flyer keeps the imported Action source unchanged"
		)
	if controller != null:
		_expect(controller.call("get_overlay_animation_name") == &"WingFlap", "Flyer exposes the WingFlap overlay")
		_expect(int(controller.call("get_overlay_bone_count")) == 2, "Flyer binds both wing root bones")
		_expect(
			controller.restore_bone_chains_to_authored_pose
			and int(controller.call("get_authored_chain_bone_count")) == 8,
			"Flyer restores both complete wing chains to their authored spread pose"
		)
		_expect(
			controller.rotation_space == controller.RotationSpace.SKELETON
			and controller.rotation_axis.is_equal_approx(Vector3.BACK),
			"Flyer flaps around the skeleton Z axis"
		)
		_expect(not controller.one_sided_motion, "Flyer uses a small symmetric up/down wing swing")
		_expect(float(controller.call("get_overlay_weight")) > 0.0, "Flyer wing overlay activates while moving")
		_expect(bool(controller.call("is_overlay_pose_applied")), "Flyer wing pose reaches Skeleton3D rendering")
	await _free_unit(unit)


func _test_titan_state_animations() -> void:
	var idle_unit := await _spawn_unit("res://resources/enemies/EliteTitan.tres", false)
	var idle_controller := _find_node_with_method(idle_unit, &"get_visual_animation_state")
	_expect(idle_controller != null, "Titan installs its state animation controller")
	if idle_controller != null:
		_expect(idle_controller.call("get_visual_animation_state") == &"Idle", "Titan plays Idle while stopped")
	await _free_unit(idle_unit)

	var moving_unit := await _spawn_unit("res://resources/enemies/EliteTitan.tres", true)
	var moving_controller := _find_node_with_method(moving_unit, &"get_visual_animation_state")
	_expect(
		moving_controller != null and moving_controller.call("get_visual_animation_state") == &"Walk",
		"Titan switches to Walk while moving"
	)
	_expect(
		moving_controller != null and bool(moving_controller.call("is_walk_and_head_shake_playing")),
		"Titan layers HeadShake over Walk while moving"
	)
	var overlay_player := _find_named_animation_player(moving_unit, &"HeadShakeOverlay")
	_expect(
		overlay_player != null
		and overlay_player.get_animation(&"HeadShakeOverlay").get_track_count() == 7,
		"Titan HeadShake overlay contains only the seven head and neck tracks"
	)
	await _free_unit(moving_unit)


func _test_double_shield_leg_overlay() -> void:
	var unit := await _spawn_unit("res://resources/enemies/DoubleShieldSoldier.tres", true)
	var controller := _find_node_with_method(unit, &"get_overlay_animation_name")
	var player := _find_animation_player(unit)
	_expect(
		player != null and player.current_animation == &"Defense(1_19)",
		"Double shield soldier keeps its existing Defense animation"
	)
	_expect(
		controller != null and controller.call("get_overlay_animation_name") == &"LegSwing",
		"Double shield soldier adds a separate LegSwing overlay"
	)
	_expect(
		controller != null and int(controller.call("get_overlay_bone_count")) == 2,
		"Double shield soldier binds both thigh bones"
	)
	_expect(
		controller != null and float(controller.call("get_overlay_weight")) > 0.0,
		"Double shield soldier leg overlay activates while moving"
	)
	await _free_unit(unit)


func _test_simple_model_motions() -> void:
	var mage := await _spawn_unit("res://resources/enemies/EliteMage.tres", false)
	var mage_controller := _find_node_with_method(mage, &"get_motion_name")
	_expect(
		mage_controller != null and mage_controller.call("get_motion_name") == &"StoppedHover",
		"Elite mage uses the stopped hover motion"
	)
	_expect(
		mage_controller != null and float(mage_controller.call("get_motion_weight")) > 0.0,
		"Elite mage hover activates while stopped"
	)
	await _free_unit(mage)

	for fixture in [
		["res://resources/enemies/SingleShieldSoldier.tres", "Single shield boar"],
		["res://resources/enemies/Grunt.tres", "Grunt"],
	]:
		var unit := await _spawn_unit(String(fixture[0]), true)
		var controller := _find_node_with_method(unit, &"get_motion_name")
		_expect(
			controller != null and controller.call("get_motion_name") == &"MovingLean",
			"%s uses the forward/back moving lean" % String(fixture[1])
		)
		_expect(
			controller != null and float(controller.call("get_motion_weight")) > 0.0,
			"%s lean activates while moving" % String(fixture[1])
		)
		await _free_unit(unit)


func _spawn_unit(definition_path: String, moving: bool) -> EnemyUnit:
	var definition := ResourceLoader.load(
		definition_path,
		"",
		ResourceLoader.CACHE_MODE_REPLACE_DEEP
	) as EnemyDefinition
	var unit := EnemyUnit.new()
	unit.debug_visual_enabled = false
	var points := PackedVector3Array([Vector3.ZERO])
	var cells: Array[Vector3i] = [Vector3i.ZERO]
	if moving:
		points.append(Vector3(10.0, 0.0, 0.0))
		cells.append(Vector3i(10, 0, 0))
	unit.configure_unit(definition, points, cells)
	root.add_child(unit)
	await process_frame
	await process_frame
	return unit


func _free_unit(unit: EnemyUnit) -> void:
	unit.queue_free()
	await process_frame


func _find_node_with_method(node: Node, method_name: StringName) -> Node:
	if node.has_method(method_name):
		return node
	for child in node.get_children():
		var result := _find_node_with_method(child, method_name)
		if result != null:
			return result
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


func _find_named_animation_player(node: Node, node_name: StringName) -> AnimationPlayer:
	if node is AnimationPlayer and node.name == node_name:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_named_animation_player(child, node_name)
		if result != null:
			return result
	return null


func _count_wing_tracks(animation: Animation) -> int:
	if animation == null:
		return 0
	var count := 0
	for track_index in animation.get_track_count():
		var path := animation.track_get_path(track_index)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(path.get_subname_count() - 1))
		if bone_name.begins_with("w0") and (
			bone_name.contains(".L_") or bone_name.contains(".R_")
		):
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	print("  FAIL: %s" % message)
