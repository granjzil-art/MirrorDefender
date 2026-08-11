extends SceneTree

const StuffCatalogScript := preload("res://scripts/stuff/StuffCatalog.gd")
const StuffDefinitionScript := preload("res://scripts/stuff/StuffDefinition.gd")

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_test_default_catalog()
	_test_catalog_validation()
	_test_navigation_contract()
	if _failures == 0:
		print("stuff_catalog_test: %d checks passed" % _checks)
		quit(0)
	else:
		push_error("stuff_catalog_test: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_default_catalog() -> void:
	var catalog: Resource = load("res://resources/stuffs/StuffCatalog.tres")
	_expect(catalog != null, "default StuffCatalog loads")
	_expect(catalog.validate_configuration().is_empty(), "default StuffCatalog validates")
	_expect(catalog.get_enabled_definitions().size() >= 4, "default catalog keeps its foundational enabled definitions")
	for required_id: StringName in [&"rock", &"spike", &"tree", &"void"]:
		_expect(catalog.get_definition(required_id) != null, "catalog resolves %s by stable id" % required_id)
	for blocker_path in [
		"res://resources/stuffs/Rock.tres",
		"res://resources/stuffs/tree1.tres",
		"res://resources/stuffs/highstone.tres",
		"res://resources/stuffs/stuff.tres",
	]:
		var blocker: StuffDefinition = load(blocker_path) as StuffDefinition
		_expect(blocker != null and blocker.blocks_ballistics, "%s enables the shared ballistic blocker" % blocker_path.get_file())
	var palm: StuffDefinition = load("res://resources/stuffs/Tree.tres") as StuffDefinition
	_expect(palm != null and not palm.blocks_ballistics, "unrequested palm tree keeps ballistic blocking disabled")


func _test_catalog_validation() -> void:
	var catalog := StuffCatalogScript.new()
	var first := _make_definition(&"tree", "树 A")
	var second := _make_definition(&"tree", "树 B")
	catalog.definitions = [first, second, null]
	var errors := catalog.validate_configuration()
	_expect(_contains(errors, "ID 重复"), "catalog rejects duplicate ids")
	_expect(_contains(errors, "为空"), "catalog rejects null entries")
	second.stuff_id = &"pine"
	catalog.definitions = [first]
	_expect(catalog.add_definition(second), "catalog adds one unique definition")
	_expect(not catalog.add_definition(second), "catalog rejects duplicate resource registration")
	second.authoring_enabled = false
	_expect(catalog.get_definition(&"pine") == null, "disabled definitions stay hidden from authoring")
	_expect(catalog.get_definition(&"pine", true) == second, "disabled definitions remain reference-resolvable")


func _test_navigation_contract() -> void:
	var definition := _make_definition(&"blocking_tree", "堵路树")
	definition.enemy_navigation = StuffDefinitionScript.EnemyNavigation.BLOCKED
	_expect(definition.blocks_enemy_navigation(), "explicit blocked Stuff owns navigation")
	definition.enemy_navigation = StuffDefinitionScript.EnemyNavigation.PASSABLE
	_expect(not definition.blocks_enemy_navigation(), "explicit passable Stuff ignores effect inference")
	var rock: Resource = load("res://resources/stuffs/Rock.tres")
	_expect(rock.enemy_navigation == StuffDefinitionScript.EnemyNavigation.BLOCKED, "formal rock migrated to explicit blocking")


func _make_definition(stuff_id: StringName, display_name: String) -> Resource:
	var definition := StuffDefinitionScript.new()
	definition.stuff_id = stuff_id
	definition.display_name = display_name
	definition.enemy_navigation = StuffDefinitionScript.EnemyNavigation.PASSABLE
	return definition


func _contains(errors: Array[String], needle: String) -> bool:
	for error in errors:
		if needle in error:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)
