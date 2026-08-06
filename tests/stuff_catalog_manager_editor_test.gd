extends SceneTree

const ManagerScript := preload("res://addons/mirror_tile_editor/stuff_catalog_manager.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Engine.is_editor_hint():
		print("stuff_catalog_manager_editor_test: skipped outside editor context")
		quit(0)
		return
	var manager := ManagerScript.new()
	root.add_child(manager)
	await process_frame
	if manager.get_catalog() == null:
		push_error("stuff_catalog_manager_editor_test: catalog failed to load")
		quit(1)
		return
	var item_lists := manager.find_children("*", "ItemList", true, false)
	if item_lists.is_empty() or (item_lists[0] as ItemList).item_count != 4:
		push_error("stuff_catalog_manager_editor_test: catalog list did not render four entries")
		quit(1)
		return
	print("stuff_catalog_manager_editor_test: editor UI smoke passed")
	manager.queue_free()
	quit(0)
