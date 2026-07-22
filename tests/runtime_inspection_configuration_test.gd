extends SceneTree

const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")
const TileInspectionModelBuilderScript := preload("res://scripts/ui/TileInspectionModelBuilder.gd")
const TileInspectorPanelScript := preload("res://scripts/ui/TileInspectorPanel.gd")

const CONFIGURED_RESOURCES: Dictionary = {
	"res://resources/buildings/ArrowTower.tres": "箭塔",
	"res://resources/buildings/LaserTower.tres": "激光塔",
	"res://resources/buildings/Barrier.tres": "屏障",
	"res://resources/buildings/EdgeBarrier.tres": "边屏障",
	"res://resources/mirrors/CopyMirror.tres": "复制镜",
	"res://resources/tile_definitions/Buildable.tres": "可建造",
	"res://resources/tile_definitions/BlockedRoad.tres": "不可建造路面",
	"res://resources/tile_definitions/Destructible.tres": "可破坏障碍",
	"res://resources/tile_definitions/Spike.tres": "尖刺格子",
	"res://resources/tile_definitions/Void.tres": "空洞格子",
	"res://resources/tile_definitions/Rock.tres": "大石头障碍",
}

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeInspectionConfiguration] running")
	_test_config_defaults()
	_test_production_resources()
	await _test_filtering_and_adaptive_layout()
	if _failures == 0:
		print("[RuntimeInspectionConfiguration] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeInspectionConfiguration] FAIL: %d of %d checks failed" % [_failures, _checks])
	quit(1)


func _test_config_defaults() -> void:
	var config: InspectionDisplayConfigScript = InspectionDisplayConfigScript.new()
	_expect(config.visible, "object visibility defaults to enabled")
	_expect(config.resolve_display_name("原名称") == "原名称", "empty custom name preserves the current name")
	_expect(config.resolve_function_description("原说明") == "原说明", "empty description preserves the built-in description")
	for property in [
		&"show_icon", &"show_category", &"show_entity_state", &"show_function_description",
		&"show_position", &"show_height", &"show_build_permissions", &"show_level",
		&"show_durability", &"show_orientation", &"show_airborne_effect", &"show_combat",
		&"show_economy", &"show_capacity", &"show_timing", &"show_projection_source",
		&"show_producing_mirror", &"show_copy_chain",
	]:
		_expect(bool(config.get(property)), "%s preserves its existing display by default" % property)


func _test_production_resources() -> void:
	for path in CONFIGURED_RESOURCES:
		var definition: Resource = load(path)
		_expect(definition != null, "%s loads" % path)
		if definition == null:
			continue
		var config: InspectionDisplayConfigScript = definition.get("inspection_display")
		_expect(config != null, "%s owns an inspector configuration" % path)
		if config == null:
			continue
		_expect(config.visible, "%s remains visible by default" % path)
		_expect(config.display_name == CONFIGURED_RESOURCES[path], "%s keeps its current display name" % path)
		_expect(not config.function_description.strip_edges().is_empty(), "%s provides an editable function description" % path)
	var mirror: CopyMirrorDefinition = load("res://resources/mirrors/CopyMirror.tres")
	_expect(mirror.inspection_display.function_description == "复制镜面法线方向最近非空地块上的全部对象到对称位置。", "copy mirror ships with the agreed functional wording")


func _test_filtering_and_adaptive_layout() -> void:
	var host := Node.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)

	var definition: TileDefinition = (load("res://resources/tile_definitions/Spike.tres") as TileDefinition).duplicate(true)
	var config: InspectionDisplayConfigScript = definition.inspection_display
	var tile := TileCellData.new()
	tile.configure(Vector3i.ZERO, TileCellData.TileType.BUILDABLE, 2, definition)
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_size = Vector2i(2, 2)
	level.tiles = [tile]
	_expect(loader.load_level(level, "memory://inspection-configuration"), "configuration fixture level loads")
	await process_frame

	var builder: TileInspectionModelBuilderScript = TileInspectionModelBuilderScript.new()
	builder.configure(grid, tile_manager, null, null, null)
	var initial_entry: Dictionary = builder.inspect_cell(Vector3i.ZERO).entries[0]
	_expect(String(initial_entry.name) == "尖刺格子", "configured default name is displayed")
	_expect(String(initial_entry.description) == config.function_description, "configured function description is displayed")
	_expect(_lines_contain(initial_entry, "高度档：2"), "height information remains visible by default")

	config.display_name = "测试地刺"
	config.function_description = "用于验证可编辑说明。"
	config.show_icon = false
	config.show_category = false
	config.show_entity_state = false
	config.show_position = false
	config.show_height = false
	config.show_build_permissions = false
	config.show_combat = false
	config.show_airborne_effect = false
	var compact_model: Dictionary = builder.inspect_cell(Vector3i.ZERO)
	var compact_entry: Dictionary = compact_model.entries[0]
	_expect(String(compact_entry.name) == "测试地刺", "custom object name overrides the default")
	_expect(String(compact_entry.description) == "用于验证可编辑说明。", "custom function description overrides the default")
	_expect((compact_entry.lines as Array).is_empty(), "disabled detail fields are omitted from the model")

	var panel: TileInspectorPanelScript = TileInspectorPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.display_model(compact_model)
	await process_frame
	var card := panel.get_node("GlassPanel/Layout/EntriesScroll/Entries/Entry0") as Control
	_expect(card.find_child("Preview", true, false) == null, "disabled icon removes its layout column")
	_expect(card.find_child("Type", true, false) == null, "disabled category and state remove their layout row")
	_expect(card.find_child("Details", true, false) == null, "empty details remove their layout row")
	var function_label := card.find_child("Function", true, false) as Label
	_expect(function_label != null and function_label.text == "功能：用于验证可编辑说明。", "function description renders as a dedicated row")
	_expect(is_equal_approx(card.custom_minimum_size.y, panel.compact_entry_minimum_height), "icon-free cards use the compact adaptive height")

	config.visible = false
	var hidden_model: Dictionary = builder.inspect_cell(Vector3i.ZERO)
	_expect(not hidden_model.has_content and (hidden_model.entries as Array).is_empty(), "object-level visibility omits the entire spike entry")
	panel.queue_free()
	host.queue_free()
	await process_frame


func _lines_contain(entry: Dictionary, fragment: String) -> bool:
	for raw_line in entry.get("lines", []):
		if fragment in String(raw_line):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
