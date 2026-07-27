extends SceneTree

const DebugCommandRegistryScript := preload("res://scripts/debug/DebugCommandRegistry.gd")
const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")
const RuntimeDebugBindingsScript := preload("res://scripts/debug/RuntimeDebugBindings.gd")
const DebugConsoleScript := preload("res://scripts/ui/DebugConsole.gd")
const RuntimeHudScript := preload("res://scripts/ui/RuntimeHud.gd")

var _checks: int = 0
var _failures: int = 0
var _toggle_value: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUIBatch6] running")
	_test_input_and_command_registry()
	var bindings := await _test_runtime_bindings()
	await _test_console_scene(bindings)
	await _test_runtime_hud_modal(bindings)
	await _test_main_scene_migration()
	if is_instance_valid(bindings):
		bindings.queue_free()
	await process_frame
	if _failures == 0:
		print("[RuntimeUIBatch6] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[RuntimeUIBatch6] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_input_and_command_registry() -> void:
	_expect(InputMap.has_action("toggle_debug_console"), "InputMap exposes the F1 console action")
	var events := InputMap.action_get_events("toggle_debug_console")
	var has_f1 := false
	for event in events:
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F1:
			has_f1 = true
	_expect(has_f1, "the console action is bound to physical F1")
	var registry := DebugCommandRegistryScript.new()
	_expect(
		registry.register_command(&"echo", "echo <text>", "echo arguments", Callable(self, "_echo_command")),
		"command registry accepts an external command handler"
	)
	var quoted := registry.execute("echo \"mirror world\" tail")
	_expect(bool(quoted.get("success", false)), "quoted command arguments parse successfully")
	_expect(str(quoted.get("message", "")) == "mirror world|tail", "quoted text remains one argument")
	var malformed := registry.execute("echo \"missing")
	_expect(not bool(malformed.get("success", true)), "unclosed quotes return a structured failure")
	var unknown := registry.execute("not_a_command")
	_expect(not bool(unknown.get("success", true)), "unknown commands return a structured failure")
	var help := registry.execute("help echo")
	_expect(bool(help.get("success", false)) and str(help.get("message", "")).contains("echo <text>"), "help reads registry metadata")
	var clear := registry.execute("clear")
	_expect(bool(clear.get("clear", false)), "clear uses a structured console result")


func _test_runtime_bindings() -> RuntimeDebugBindingsScript:
	var resource_manager := ResourceManager.new()
	root.add_child(resource_manager)
	var bindings := RuntimeDebugBindingsScript.new()
	root.add_child(bindings)
	await process_frame
	bindings.configure(null, resource_manager, null, null, null, null, null, null)
	var command_names: Array[String] = []
	for entry in bindings.command_registry.list_commands():
		command_names.append(str(entry.get("name", "")))
	for expected in ["help", "clear", "reload", "load", "resource", "wave", "spawn", "debug"]:
		_expect(command_names.has(expected), "runtime registry exposes %s" % expected)
	var category_ids: Array[String] = []
	for entry in bindings.category_registry.list_categories():
		category_ids.append(str(entry.get("id", "")))
	for expected in ["grid", "pick", "path", "reroute", "mirror", "combat", "fps", "wave"]:
		_expect(category_ids.has(expected), "runtime registry exposes %s category" % expected)
	_expect(category_ids.size() == 8, "runtime debug categories have one stable eight-item source")
	var added := bindings.command_registry.execute("resource add 25")
	_expect(bool(added.get("success", false)) and is_equal_approx(resource_manager.main_resource, 225.0), "resource add uses ResourceManager gain")
	var set_result := bindings.command_registry.execute("resource set 17.5")
	_expect(bool(set_result.get("success", false)) and is_equal_approx(resource_manager.main_resource, 17.5), "resource set uses the public ResourceManager setter")
	var invalid_resource := bindings.command_registry.execute("resource set -2")
	_expect(not bool(invalid_resource.get("success", true)), "resource command rejects negative state")
	var debug_set := bindings.command_registry.execute("debug set fps on")
	_expect(bool(debug_set.get("success", false)) and bindings.category_registry.is_enabled(&"fps"), "debug set changes the shared category source")
	var debug_list := bindings.command_registry.execute("debug list")
	_expect(str(debug_list.get("message", "")).contains("fps") and str(debug_list.get("message", "")).contains("on"), "debug list reports live category state")
	var unavailable_wave := bindings.command_registry.execute("wave start")
	_expect(not bool(unavailable_wave.get("success", true)), "missing business dependencies fail without runtime errors")
	resource_manager.queue_free()
	return bindings


func _test_console_scene(bindings: RuntimeDebugBindingsScript) -> void:
	var scene := load("res://scenes/ui/DebugConsole.tscn") as PackedScene
	_expect(scene != null, "debug console scene loads")
	if scene == null:
		return
	for viewport_size in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080)]:
		var host := Control.new()
		host.size = viewport_size
		root.add_child(host)
		var console: DebugConsoleScript = scene.instantiate() as DebugConsoleScript
		host.add_child(console)
		await process_frame
		console.configure(bindings.command_registry, bindings.category_registry)
		var toggle_event := InputEventAction.new()
		toggle_event.action = &"toggle_debug_console"
		toggle_event.pressed = true
		console._input(toggle_event)
		await process_frame
		_expect(console.is_open(), "F1 action opens the console as a modal at %s" % str(viewport_size))
		var frame := console.get_node("Shade/ConsoleFrame") as Control
		var rect := frame.get_global_rect()
		_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "console stays inside the top-left viewport edge at %s" % str(viewport_size))
		_expect(rect.end.x <= viewport_size.x + 0.1 and rect.end.y <= viewport_size.y + 0.1, "console stays inside the bottom-right viewport edge at %s" % str(viewport_size))
		_expect(console.get_category_checkbox(&"fps") != null, "console builds category controls from the registry")
		var result: Dictionary = console.submit_command("debug set combat on")
		_expect(bool(result.get("success", false)), "console delegates commands to the registry")
		_expect(console.get_history_text().contains("> debug set combat on"), "console records command history")
		console.submit_command("clear")
		_expect(console.get_history_text().is_empty(), "clear removes console history")
		console.close_console()
		_expect(not console.is_open(), "console closes explicitly")
		host.queue_free()
		await process_frame


func _test_runtime_hud_modal(bindings: RuntimeDebugBindingsScript) -> void:
	var scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	_expect(scene != null, "runtime HUD scene includes batch 6")
	if scene == null:
		return
	var host := Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)
	var hud: RuntimeHudScript = scene.instantiate() as RuntimeHudScript
	host.add_child(hud)
	await process_frame
	bindings.category_registry.set_enabled(&"fps", true)
	hud.configure_debug_console(bindings.command_registry, bindings.category_registry)
	_expect(hud.debug_console != null, "runtime HUD owns the F1 console")
	_expect(hud.debug_overlay_panel != null, "runtime HUD owns the persistent debug overlay")
	_expect(
		hud.debug_overlay_panel.visible and hud.debug_overlay_panel.get_display_text().contains("[性能]"),
		"an enabled console category renders in the game-view overlay"
	)
	var overlay_rect: Rect2 = hud.debug_overlay_panel.get_global_rect()
	var wave_controls_rect: Rect2 = hud.wave_control_panel.get_global_rect()
	_expect(
		overlay_rect.position.x >= 0.0 and overlay_rect.position.y >= 0.0 and not overlay_rect.intersects(wave_controls_rect),
		"debug overlay stays clear of the right-side wave controls"
	)
	hud.debug_console.open_console()
	await process_frame
	_expect(hud.is_modal_open() and hud.is_debug_console_open(), "console participates in the unified HUD modal boundary")
	hud.close_top_modal()
	_expect(not hud.is_modal_open(), "closing the top modal restores world input eligibility")
	_expect(hud.debug_overlay_panel.visible, "closing the console keeps enabled debug information on the game view")
	for entry in bindings.category_registry.list_categories():
		bindings.category_registry.set_enabled(entry.get("id", &""), false)
	_expect(not hud.debug_overlay_panel.visible, "debug overlay hides when every category is disabled")
	host.queue_free()
	await process_frame


func _test_main_scene_migration() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_expect(scene != null, "main scene loads with batch 6 composition")
	if scene == null:
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var hud_panel := main.get_node("HUD/Panel") as Control
	var hint := main.get_node("HUD/Hint") as Control
	var level_debug := main.get_node("HUD/LevelDebugPanel") as Control
	var m3_debug := main.get_node("HUD/M3DebugPanel") as Control
	_expect(not hud_panel.visible and not hint.visible, "scattered main debug text is hidden")
	_expect(level_debug.visible and not m3_debug.visible, "legacy level load panel is restored while M3 debug panel stays hidden")
	_expect(_has_level_load_controls(level_debug), "legacy level load panel exposes current-level status and load button")
	_expect(main.runtime_debug_bindings != null, "Main composes one runtime debug bindings module")
	_expect(
		main.runtime_hud.debug_console != null and main.runtime_hud.debug_overlay_panel != null,
		"Main exposes debug through the formal HUD console and persistent overlay"
	)
	var marker_labels: Array[String] = main.path_manager.get_spawn_marker_labels()
	_expect(not main.path_manager.show_paths and not marker_labels.is_empty(), "path debug lines default off while numbered endpoints remain")
	var path_on: Dictionary = main.runtime_debug_bindings.command_registry.execute("debug set path on")
	_expect(bool(path_on.get("success", false)) and main.path_manager.show_paths, "path category enables only the debug route lines")
	var path_off: Dictionary = main.runtime_debug_bindings.command_registry.execute("debug set path off")
	_expect(bool(path_off.get("success", false)) and not main.path_manager.show_paths, "path category disables the debug route lines")
	await process_frame
	_expect(not main.path_manager.get_spawn_marker_labels().is_empty(), "disabling path debug preserves numbered endpoint markers")
	var spawn_result: Dictionary = main.runtime_debug_bindings.command_registry.execute("spawn flyer main")
	_expect(bool(spawn_result.get("success", false)), "spawn command reuses the live WaveManager enemy transaction")
	main.queue_free()
	await process_frame
	Engine.time_scale = 1.0


func _echo_command(arguments: Array[String]) -> Dictionary:
	return {"success": true, "message": "|".join(arguments), "clear": false}


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % description)
		return
	_failures += 1
	push_error("  FAIL: %s" % description)


func _has_level_load_controls(panel: Control) -> bool:
	var has_load_button := false
	var has_level_status := false
	for child in panel.find_children("*", "Button", true, false):
		if (child as Button).text == "加载关卡":
			has_load_button = true
			break
	for child in panel.find_children("*", "Label", true, false):
		if (child as Label).text.begins_with("关卡："):
			has_level_status = true
			break
	return has_load_button and has_level_status
