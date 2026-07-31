extends SceneTree

const GridCellDataScript := preload("res://scripts/terrain/GridCellData.gd")
const LevelResourceScript := preload("res://scripts/level/LevelResource.gd")
const RampPlacementDataScript := preload("res://scripts/terrain/RampPlacementData.gd")
const SquareGridShapeScript := preload("res://scripts/grid/SquareGridShape.gd")
const HexGridShapeScript := preload("res://scripts/grid/HexGridShape.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")
const StuffPlacementDataScript := preload("res://scripts/stuff/StuffPlacementData.gd")
const TerrainDefinitionScript := preload("res://scripts/terrain/TerrainDefinition.gd")
const TileCellDataScript := preload("res://scripts/tile/TileCellData.gd")

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_separate_contracts()
	_test_ramp_footprints()
	_test_legacy_snapshot()
	_test_canonical_validation()
	if _failures == 0:
		print("terrain_stuff_contract_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("terrain_stuff_contract_test: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_separate_contracts() -> void:
	var grass: TerrainDefinitionScript = load("res://resources/terrains/Grass.tres")
	var sand: TerrainDefinitionScript = load("res://resources/terrains/Sand.tres")
	var water: TerrainDefinitionScript = load("res://resources/terrains/Water.tres")
	var mud: TerrainDefinitionScript = load("res://resources/terrains/Mud.tres")
	_expect(grass != null and sand != null and water != null and mud != null, "four canonical terrain resources load")
	_expect(not _has_property(grass, &"allows_tile_building"), "terrain identity does not own build permission")
	_expect(not _has_property(grass, &"effect"), "terrain identity does not own Stuff effects")
	var cell := GridCellDataScript.new()
	cell.configure(Vector3i.ZERO, grass, 4, false, true)
	_expect(cell.layer_count == 4 and is_equal_approx(cell.get_surface_height(0.5), 1.5), "four voxel layers expose compatible top height")
	_expect(not cell.allows_tile_building and cell.allows_edge_building, "Grid stores independent placement attributes")
	var first := StuffDefinitionScript.new()
	var second := StuffDefinitionScript.new()
	_expect(not first.can_coexist_with(second), "Stuff defaults are mutually exclusive")
	first.exclusive_with_other_stuff = false
	_expect(not first.can_coexist_with(second), "coexistence requires both Stuff definitions to opt in")
	second.exclusive_with_other_stuff = false
	_expect(first.can_coexist_with(second) and second.can_coexist_with(first), "two opt-in Stuff definitions coexist symmetrically")
	for path in [
		"res://resources/stuffs/Rock.tres",
		"res://resources/stuffs/Spike.tres",
		"res://resources/stuffs/Void.tres",
		"res://resources/stuffs/Tree.tres",
	]:
		var definition: StuffDefinitionScript = load(path)
		_expect(definition != null and definition.exclusive_with_other_stuff, "%s uses default exclusivity" % path.get_file())


func _test_ramp_footprints() -> void:
	var square := SquareGridShapeScript.new()
	square.setup(1.0)
	var square_ramp := RampPlacementDataScript.new()
	square_ramp.anchor_cell = Vector3i(1, 1, 0)
	square_ramp.facing_index = 0
	square_ramp.run_length = 4
	var square_cells := square_ramp.get_footprint_cells(square)
	_expect(square_cells == [
		Vector3i(1, 1, 0), Vector3i(2, 1, 0), Vector3i(3, 1, 0), Vector3i(4, 1, 0)
	], "square 1:4 ramp occupies four cells uphill")
	_expect(square_ramp.get_low_neighbor(square) == Vector3i(0, 1, 0), "square ramp resolves low connection")
	_expect(square_ramp.get_high_neighbor(square) == Vector3i(5, 1, 0), "square ramp resolves high connection")
	var hex := HexGridShapeScript.new()
	hex.setup(1.0)
	var hex_ramp := RampPlacementDataScript.new()
	hex_ramp.anchor_cell = Vector3i.ZERO
	hex_ramp.facing_index = 1
	hex_ramp.run_length = 3
	_expect(hex_ramp.get_footprint_cells(hex) == [
		Vector3i(0, 0, 0), Vector3i(1, 0, -1), Vector3i(2, 0, -2)
	], "hex 1:3 ramp follows one of six edge directions")
	_expect(hex_ramp.get_low_neighbor(hex) == Vector3i(-1, 0, 1), "hex ramp resolves opposite low connection")


func _test_legacy_snapshot() -> void:
	var level := LevelResourceScript.new()
	level.grid_shape = 1
	level.grid_size = Vector2i(4, 2)
	level.height_step = 0.5
	var rock := TileCellDataScript.new()
	rock.configure(Vector3i(0, 0, 0), TileCellDataScript.TileType.BLOCKED, 2, load("res://resources/tile_definitions/Rock.tres"))
	var spike := TileCellDataScript.new()
	spike.configure(Vector3i(1, 0, 0), TileCellDataScript.TileType.BLOCKED, 0, load("res://resources/tile_definitions/Spike.tres"))
	var road := TileCellDataScript.new()
	road.configure(Vector3i(2, 0, 0), TileCellDataScript.TileType.BLOCKED, 1, load("res://resources/tile_definitions/BlockedRoad.tres"))
	level.tiles = [rock, spike, road]
	var snapshot := level.get_effective_content_snapshot()
	var migrated_cells: Array = snapshot["grid_cells"]
	var migrated_stuff: Array = snapshot["stuff_placements"]
	_expect(bool(snapshot["migrated"]), "legacy read produces a transient migration snapshot")
	_expect(migrated_cells.size() == 3 and migrated_stuff.size() == 2, "legacy elements split from three underlying Grid cells")
	_expect(migrated_cells[0].layer_count == 3 and migrated_cells[1].layer_count == 1, "legacy 0-based heights map to 1-based voxel layers")
	_expect(migrated_cells[0].allows_tile_building and migrated_cells[0].allows_edge_building, "legacy rock receives buildable underlying Grid")
	_expect(not migrated_cells[2].allows_tile_building and migrated_cells[2].allows_edge_building, "legacy road becomes a Grid attribute without Stuff")
	_expect(migrated_stuff[0].definition.effect != null and migrated_stuff[0].definition.blocks_tile_building, "legacy rock effect and restriction move to Stuff")
	_expect(level.terrain_content_version == 0 and level.grid_cells.is_empty(), "read-only snapshot does not mutate legacy level")
	_expect(level.migrate_legacy_content_in_place(), "explicit migration materializes canonical content")
	_expect(level.terrain_content_version == 2 and level.tiles.size() == 3, "batch 1 migration keeps legacy tiles for current runtime")
	_expect(not level.migrate_legacy_content_in_place(), "canonical migration is idempotent")


func _test_canonical_validation() -> void:
	var level := LevelResourceScript.new()
	level.grid_shape = 1
	level.grid_size = Vector2i(6, 3)
	level.terrain_content_version = 2
	level.default_terrain = load("res://resources/terrains/Grass.tres")
	level.layer_height = 0.5
	for x in range(6):
		var cell := GridCellDataScript.new()
		var layer_count := 2 if x >= 3 else 1
		cell.configure(Vector3i(x, 1, 0), level.default_terrain, layer_count)
		level.grid_cells.append(cell)
	var ramp := RampPlacementDataScript.new()
	ramp.ramp_id = &"test_ramp"
	ramp.anchor_cell = Vector3i(1, 1, 0)
	ramp.facing_index = 0
	ramp.run_length = 2
	ramp.base_layer = 1
	level.ramp_placements.append(ramp)
	_expect(level.validate_runtime().is_empty(), "valid canonical 1:2 ramp connects layer 1 to layer 2")
	var first_definition := StuffDefinitionScript.new()
	first_definition.stuff_id = &"a"
	first_definition.display_name = "A"
	var second_definition := StuffDefinitionScript.new()
	second_definition.stuff_id = &"b"
	second_definition.display_name = "B"
	var first := StuffPlacementDataScript.new()
	first.configure(&"a_1", Vector3i(2, 1, 0), first_definition)
	var second := StuffPlacementDataScript.new()
	second.configure(&"b_1", Vector3i(2, 1, 0), second_definition)
	level.stuff_placements = [first, second]
	_expect(_contains_text(level.validate_runtime(), "互斥"), "canonical validation rejects default-overlapping Stuff")
	first_definition.exclusive_with_other_stuff = false
	second_definition.exclusive_with_other_stuff = false
	_expect(not _contains_text(level.validate_runtime(), "互斥"), "canonical validation accepts two opt-in Stuff instances")
	ramp.run_length = 4
	_expect(not level.validate_runtime().is_empty(), "ramp validation rejects footprint/endpoints that no longer match")


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _contains_text(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if needle in error:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)
