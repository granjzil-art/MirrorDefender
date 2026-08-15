extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[MirrorBodySelection] running")
	await _test_two_sided_body_pick_and_selection()
	if _failures == 0:
		print("[MirrorBodySelection] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[MirrorBodySelection] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_two_sided_body_pick_and_selection() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	grid.apply_configuration(GridManager.Shape.SQUARE, 1.0, Vector2i(4, 4))
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	var mirror := CopyMirror.new()
	mirror_manager.add_child(mirror)
	var from_cell := Vector3i(1, 1, 0)
	var to_cell := Vector3i(2, 1, 0)
	var edge_index := grid.find_edge_index(from_cell, to_cell)
	mirror.configure(
		TestDefinitionFactory.make_copy_mirror_definition(),
		from_cell,
		to_cell,
		edge_index,
		grid.canonical_edge_id(from_cell, edge_index),
		grid,
		tile_manager,
		true
	)
	_expect(
		(mirror.get_node("MirrorBody") as MeshInstance3D).mesh is ArrayMesh
		and mirror.get_reflection_surface().mesh is ArrayMesh,
		"copy mirror uses an oval prism body and inset oval reflection face"
	)
	var reflect_mirror := ReflectMirror.new()
	mirror_manager.add_child(reflect_mirror)
	reflect_mirror.configure(
		TestDefinitionFactory.make_reflect_mirror_definition(),
		from_cell,
		to_cell,
		edge_index,
		"reflect-shape-fixture",
		grid,
		tile_manager,
		true
	)
	_expect(
		(reflect_mirror.get_node("MirrorBody") as MeshInstance3D).mesh is BoxMesh
		and reflect_mirror.get_reflection_surface().mesh is QuadMesh,
		"reflect mirror keeps its original rectangular body and reflection face"
	)
	mirror_manager.set("_mirrors", {mirror.edge_id: mirror})
	var body_center := mirror.global_position + Vector3.UP * mirror.get_mirror_height() * 0.5
	var face_normal := mirror.get_active_normal()
	var front_pick := mirror_manager.pick_mirror_from_ray(
		body_center + face_normal * 2.0,
		-face_normal
	)
	var back_pick := mirror_manager.pick_mirror_from_ray(
		body_center - face_normal * 2.0,
		face_normal
	)
	_expect(
		bool(front_pick.get("hit", false)) and front_pick.get("mirror") == mirror,
		"the mirror body is pickable from its reflective side"
	)
	_expect(
		bool(back_pick.get("hit", false)) and back_pick.get("mirror") == mirror,
		"the mirror body is pickable from its back side"
	)
	var edge_direction := mirror.get_edge_direction().normalized()
	var outside_pick := mirror_manager.pick_mirror_from_ray(
		body_center + face_normal * 2.0 + edge_direction * mirror.get_mirror_width(),
		-face_normal
	)
	_expect(not bool(outside_pick.get("hit", false)), "rays outside the visible body do not select the mirror")

	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	var interaction := RuntimeInteractionController.new()
	host.add_child(interaction)
	interaction.configure(building_manager, mirror_manager)
	interaction.handle_primary({"hit": false}, {"hit": false}, back_pick)
	_expect(mirror_manager.get_selected_mirror() == mirror, "a direct body hit selects the mirror without a ground-edge hit")
	var copy_selection_overlay := (mirror.get_node("MirrorBody") as MeshInstance3D).material_overlay as ShaderMaterial
	var copy_selection_color: Color = (
		copy_selection_overlay.get_shader_parameter("highlight_color")
		if copy_selection_overlay != null
		else Color.BLACK
	)
	_expect(
		copy_selection_overlay != null
		and copy_selection_color.g > 0.9
		and copy_selection_color.r < 0.3,
		"selected copy mirror receives the conspicuous green shader overlay"
	)
	var copy_surface_overlay := mirror.get_reflection_surface().material_overlay as ShaderMaterial
	var copy_surface_color: Color = (
		copy_surface_overlay.get_shader_parameter("highlight_color")
		if copy_surface_overlay != null
		else Color.BLACK
	)
	_expect(
		copy_surface_overlay != null
		and copy_surface_color.g > 0.9
		and copy_surface_color.r < 0.3,
		"selected copy mirror highlights the observer-facing oval surface, not only its hidden body"
	)
	mirror.flip_side()
	_expect(
		mirror.get_reflection_surface().material_overlay == copy_surface_overlay,
		"copy-mirror green surface highlight survives active-side flipping"
	)
	mirror.set_selected(false)
	_expect(
		mirror.get_reflection_surface().material_overlay == null
		and (mirror.get_node("MirrorBody") as MeshInstance3D).material_overlay == null,
		"clearing copy-mirror selection removes both surface and body highlights"
	)
	mirror.set_selected(true)
	reflect_mirror.set_selected(true)
	var reflect_selection_overlay := (reflect_mirror.get_node("MirrorBody") as MeshInstance3D).material_overlay as ShaderMaterial
	_expect(
		reflect_selection_overlay != null,
		"selected reflect mirror receives the same green shader overlay"
	)
	reflect_mirror.set_selected(false)
	_expect(
		(reflect_mirror.get_node("MirrorBody") as MeshInstance3D).material_overlay == null,
		"clearing reflect-mirror selection removes the green overlay"
	)
	_expect(
		interaction.has_world_selection()
		and interaction.get_world_selection_cell() == mirror.from_cell
		and interaction.get_world_selection_edge_id() == mirror.edge_id,
		"direct body selection preserves the mirror's canonical world-selection context"
	)
	host.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  OK  %s" % message)
	else:
		_failures += 1
		push_error("  FAIL  %s" % message)
