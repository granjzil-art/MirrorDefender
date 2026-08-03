extends SceneTree

const Authoring := preload("res://addons/mirror_tile_editor/terrain_stuff_authoring.gd")
const EditorCanvasScript := preload("res://addons/mirror_tile_editor/terrain_stuff_canvas.gd")
const EditorPageScript := preload("res://addons/mirror_tile_editor/terrain_stuff_editor.gd")
const EditorPanelScript := preload("res://addons/mirror_tile_editor/tile_editor_panel.gd")
const LevelResourceScript := preload("res://scripts/level/LevelResource.gd")
const PathDefinitionScript := preload("res://scripts/path/PathDefinition.gd")
const SquareGridShapeScript := preload("res://scripts/grid/SquareGridShape.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")
const WaveDefinitionScript := preload("res://scripts/wave/WaveDefinition.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_legacy_import_and_single_source()
	_test_independent_grid_tools()
	_test_multi_stuff_authoring()
	_test_s1_ramp_authoring()
	_test_grid_rebuild_scope()
	_test_editor_page_contract()
	if _failures == 0:
		print("terrain_stuff_editor_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("terrain_stuff_editor_test: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_legacy_import_and_single_source() -> void:
	var level := LevelResourceScript.new()
	level.grid_shape = 1
	level.grid_size = Vector2i(3, 2)
	var rock := TileCellDataScript.new()
	rock.configure(Vector3i(1, 0, 0), TileCellDataScript.TileType.BLOCKED, 2, load("res://resources/tile_definitions/Rock.tres"))
	level.tiles = [rock]
	var shape := _make_square_shape(level)
	var result := Authoring.prepare_level(level, shape)
	_expect(bool(result["migrated"]), "legacy editor load reports one-way import")
	_expect(level.terrain_content_version == 2, "editor import switches canonical content version")
	_expect(level.tiles.is_empty(), "legacy Tile array is removed from canonical authoring document")
	_expect(level.grid_cells.size() == 6, "editor materializes every Grid cell for direct authoring")
	_expect(level.stuff_placements.size() == 1, "legacy rock imports as independent Stuff")
	var rock_grid := Authoring.get_grid_cell(level, Vector3i(1, 0, 0))
	_expect(rock_grid != null and rock_grid.layer_count == 3, "legacy 0-based height becomes 1-based layer count")
	_expect(rock_grid.allows_tile_building and rock_grid.allows_edge_building, "legacy rock underlying Grid remains buildable")
	var second := Authoring.prepare_level(level, shape)
	_expect(not bool(second["changed"]), "canonical preparation is idempotent")


func _test_independent_grid_tools() -> void:
	var level := _make_canonical_level(Vector2i(4, 2))
	var shape := _make_square_shape(level)
	Authoring.prepare_level(level, shape)
	var cell := Vector3i(2, 1, 0)
	var sand: TerrainDefinition = load("res://resources/terrains/Sand.tres")
	_expect(Authoring.paint_terrain(level, cell, sand), "terrain brush changes terrain identity")
	_expect(Authoring.paint_layer(level, cell, 4), "layer brush changes only layer count")
	_expect(Authoring.paint_permissions(level, cell, false, true), "permission brush changes independent build flags")
	var data := Authoring.get_grid_cell(level, cell)
	_expect(data.get_effective_terrain(level.default_terrain) == sand, "terrain choice survives layer and permission edits")
	_expect(data.layer_count == 4, "fourth voxel layer is authorable")
	_expect(not data.allows_tile_building and data.allows_edge_building, "tile and edge permissions remain independent")
	_expect(not Authoring.paint_layer(level, cell, 4), "idempotent brush write reports no change")


func _test_multi_stuff_authoring() -> void:
	var level := _make_canonical_level(Vector2i(3, 2))
	var shape := _make_square_shape(level)
	Authoring.prepare_level(level, shape)
	var cell := Vector3i(1, 1, 0)
	var first := StuffDefinitionScript.new()
	first.stuff_id = &"first"
	first.display_name = "First"
	first.exclusive_with_other_stuff = false
	var second := StuffDefinitionScript.new()
	second.stuff_id = &"second"
	second.display_name = "Second"
	second.exclusive_with_other_stuff = false
	var first_result := Authoring.add_stuff(level, cell, first, 7)
	var second_result := Authoring.add_stuff(level, cell, second, 3)
	_expect(bool(first_result["success"]) and bool(second_result["success"]), "two bilateral opt-in Stuff instances can share one cell")
	_expect(Authoring.get_stuff_at(level, cell).size() == 2, "editor preserves every same-cell Stuff placement")
	var first_placement: StuffPlacementData = first_result["placement"]
	_expect(first_placement.facing_index == 7, "square Stuff supports eight authored facings")
	_expect(Authoring.set_stuff_facing(level, first_placement.placement_id, 2), "Stuff facing is independently editable")
	_expect(Authoring.remove_stuff(level, first_placement.placement_id), "one Stuff can be removed by stable placement ID")
	_expect(Authoring.get_stuff_at(level, cell).size() == 1, "removing one Stuff does not delete its same-cell peer")
	var exclusive: StuffDefinition = load("res://resources/stuffs/Rock.tres")
	var rejected := Authoring.add_stuff(level, cell, exclusive)
	_expect(not bool(rejected["success"]), "default-exclusive Stuff is rejected against occupied cell")


func _test_s1_ramp_authoring() -> void:
	var level := _make_canonical_level(Vector2i(6, 3))
	var shape := _make_square_shape(level)
	Authoring.prepare_level(level, shape)
	var result := Authoring.place_ramp(level, shape, Vector3i(1, 1, 0), 0, 2, 1)
	_expect(bool(result["success"]), "S1 click places a valid 1:2 ramp")
	var ramp: RampPlacementData = result["ramp"]
	_expect(ramp.anchor_cell == Vector3i(1, 1, 0) and ramp.facing_index == 0, "ramp anchor is the lowest cell and direction points uphill")
	_expect(Authoring.get_grid_cell(level, Vector3i(0, 1, 0)).layer_count == 1, "S1 aligns low connector to base layer")
	_expect(Authoring.get_grid_cell(level, Vector3i(1, 1, 0)).layer_count == 1, "S1 aligns first footprint cell")
	_expect(Authoring.get_grid_cell(level, Vector3i(2, 1, 0)).layer_count == 1, "S1 aligns full multi-cell footprint")
	_expect(Authoring.get_grid_cell(level, Vector3i(3, 1, 0)).layer_count == 2, "S1 raises high connector exactly one layer")
	_expect(level.validate_runtime().is_empty(), "S1 output passes canonical runtime validation")
	# Reproduce Inspector/old-resource drift: the ramp stays visually valid because
	# its mesh reads RampPlacementData, while canonical Grid layers are wrong.
	Authoring.get_grid_cell(level, Vector3i(0, 1, 0)).layer_count = 4
	Authoring.get_grid_cell(level, Vector3i(1, 1, 0)).layer_count = 3
	Authoring.get_grid_cell(level, Vector3i(2, 1, 0)).layer_count = 2
	Authoring.get_grid_cell(level, Vector3i(3, 1, 0)).layer_count = 1
	var repaired := Authoring.prepare_level(level, shape)
	_expect(bool(repaired["changed"]) and int(repaired["normalized_ramps"]) == 1, "editor load auto-normalizes a visually valid ramp's canonical voxels")
	_expect(Authoring.get_grid_cell(level, Vector3i(0, 1, 0)).layer_count == 1, "normalization repairs the low connector")
	_expect(Authoring.get_grid_cell(level, Vector3i(1, 1, 0)).layer_count == 1, "normalization repairs the first footprint voxel")
	_expect(Authoring.get_grid_cell(level, Vector3i(2, 1, 0)).layer_count == 1, "normalization repairs every footprint voxel")
	_expect(Authoring.get_grid_cell(level, Vector3i(3, 1, 0)).layer_count == 2, "normalization repairs the high connector")
	var high_constraint := Authoring.get_ramp_layer_constraint(level, shape, Vector3i(3, 1, 0))
	_expect(not high_constraint.is_empty() and int(high_constraint["expected_layer"]) == 2, "high connector is exposed as a ramp-owned layer constraint")
	_expect(level.validate_runtime().is_empty(), "normalized ramp passes canonical runtime validation")
	var repaired_again := Authoring.prepare_level(level, shape)
	_expect(not bool(repaired_again["changed"]), "ramp normalization is idempotent")
	var overlap := Authoring.place_ramp(level, shape, Vector3i(2, 1, 0), 0, 1, 1)
	_expect(not bool(overlap["success"]), "ramp authoring rejects overlapping footprints")
	var outside := Authoring.place_ramp(level, shape, Vector3i(5, 0, 0), 0, 1, 1)
	_expect(not bool(outside["success"]), "ramp authoring rejects missing high connector")
	_expect(Authoring.remove_ramp(level, ramp.ramp_id), "selected ramp can be removed")
	_expect(level.ramp_placements.is_empty(), "ramp removal deletes only ramp placement")
	_expect(Authoring.get_grid_cell(level, Vector3i(3, 1, 0)).layer_count == 2, "ramp removal preserves author-visible layer edits")


func _test_grid_rebuild_scope() -> void:
	var level := _make_canonical_level(Vector2i(3, 2))
	var shape := _make_square_shape(level)
	Authoring.prepare_level(level, shape)
	var path := PathDefinitionScript.new()
	path.path_id = &"path_keep"
	var wave := WaveDefinitionScript.new()
	level.paths = [path]
	level.waves = [wave]
	var rock: StuffDefinition = load("res://resources/stuffs/Rock.tres")
	Authoring.add_stuff(level, Vector3i(1, 1, 0), rock)
	Authoring.rebuild_grid(level, shape, 1, Vector2i(2, 2))
	_expect(level.grid_cells.size() == 4 and level.stuff_placements.is_empty(), "grid rebuild replaces only Terrain/Ramp/Stuff content")
	_expect(level.paths.size() == 1 and level.paths[0] == path, "grid rebuild preserves path page data")
	_expect(level.waves.size() == 1 and level.waves[0] == wave, "grid rebuild preserves wave page data")


func _test_editor_page_contract() -> void:
	_expect(EditorPanelScript != null, "main level editor panel compiles with canonical page integration")
	var page := EditorPageScript.new()
	page.custom_minimum_size = Vector2(1280.0, 720.0)
	root.add_child(page)
	var level := _make_canonical_level(Vector2i(4, 3))
	var result := page.set_level(level)
	_expect(not bool(result["migrated"]), "canonical editor page accepts canonical level without migration")
	_expect(page.find_child("SelectedCellHelp", true, false) != null, "editor page exposes independent cell inspector")
	_expect(page.get_child_count() == 3, "editor page outer split keeps exactly two layout children plus its dialog")
	var content_split := page.get_child(1) as HSplitContainer
	_expect(content_split != null and content_split.get_child_count() == 2, "canonical canvas and inspector use a legal nested two-child split")
	var hidden_canvas: TerrainStuffCanvas = EditorCanvasScript.new()
	hidden_canvas.visible = false
	hidden_canvas.size = Vector2.ZERO
	root.add_child(hidden_canvas)
	hidden_canvas.set_level(level)
	_expect(bool(hidden_canvas.get("_view_reset_pending")), "zero-size hidden editor records one pending view reset")
	hidden_canvas.size = Vector2(640.0, 480.0)
	# SceneTree._init() runs before a rendered layout frame, so exercise the
	# resized callback explicitly instead of depending on frame delivery here.
	hidden_canvas.call("_on_canvas_resized")
	_expect(not bool(hidden_canvas.get("_view_reset_pending")), "first valid resize consumes the pending view reset")
	hidden_canvas.queue_free()
	page.queue_free()


func _make_canonical_level(size: Vector2i) -> LevelResource:
	var level := LevelResourceScript.new()
	level.grid_shape = 1
	level.grid_size = size
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 0.45
	level.height_levels = 4
	level.height_step = 0.45
	return level


func _make_square_shape(level: LevelResource) -> SquareGridShape:
	var shape := SquareGridShapeScript.new()
	shape.setup(level.grid_cell_size)
	return shape


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)
