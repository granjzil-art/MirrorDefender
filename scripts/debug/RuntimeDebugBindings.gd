## Registers runtime business commands and live debug providers outside the UI.
class_name RuntimeDebugBindings
extends Node

const DebugCommandRegistryScript := preload("res://scripts/debug/DebugCommandRegistry.gd")
const DebugCategoryRegistryScript := preload("res://scripts/debug/DebugCategoryRegistry.gd")
const ENEMY_DIRECTORY := "res://resources/enemies"

var command_registry: DebugCommandRegistryScript = DebugCommandRegistryScript.new()
var category_registry: DebugCategoryRegistryScript = DebugCategoryRegistryScript.new()

var _level_loader: LevelLoader
var _resource_manager: ResourceManager
var _wave_manager: WaveManager
var _path_manager: PathManager
var _path_route_planner: PathRoutePlanner
var _grid_manager: GridManager
var _combat_manager: CombatManager
var _mirror_manager: MirrorManager
var _stuff_editor_controller: Node
var _pick_provider: Callable


func configure(
	level_loader: LevelLoader,
	resource_manager: ResourceManager,
	wave_manager: WaveManager,
	path_manager: PathManager,
	path_route_planner: PathRoutePlanner,
	grid_manager: GridManager,
	combat_manager: CombatManager,
	mirror_manager: MirrorManager,
	stuff_editor_controller: Node = null
) -> void:
	_level_loader = level_loader
	_resource_manager = resource_manager
	_wave_manager = wave_manager
	_path_manager = path_manager
	_path_route_planner = path_route_planner
	_grid_manager = grid_manager
	_combat_manager = combat_manager
	_mirror_manager = mirror_manager
	_stuff_editor_controller = stuff_editor_controller
	command_registry = DebugCommandRegistryScript.new()
	category_registry = DebugCategoryRegistryScript.new()
	_register_categories()
	_register_commands()


func set_pick_provider(provider: Callable) -> void:
	_pick_provider = provider


func _register_categories() -> void:
	category_registry.register_category(&"grid", "网格", false, Callable(self, "_provide_grid"))
	category_registry.register_category(&"pick", "拾取", false, Callable(self, "_provide_pick"))
	category_registry.register_category(
		&"path",
		"路径",
		false,
		Callable(self, "_provide_path"),
		Callable(self, "_toggle_path_visual")
	)
	category_registry.register_category(
		&"reroute",
		"动态换路",
		false,
		Callable(self, "_provide_reroute"),
		Callable(self, "_toggle_reroute_visual")
	)
	category_registry.register_category(&"mirror", "镜子", false, Callable(self, "_provide_mirror"))
	category_registry.register_category(&"combat", "战斗", false, Callable(self, "_provide_combat"))
	category_registry.register_category(&"fps", "性能", false, Callable(self, "_provide_fps"))
	category_registry.register_category(&"wave", "波次", false, Callable(self, "_provide_wave"))


func _register_commands() -> void:
	command_registry.register_command(&"reload", "reload", "深度重载当前关卡", Callable(self, "_command_reload"))
	command_registry.register_command(&"load", "load <res://path.tres>", "加载指定 LevelResource", Callable(self, "_command_load"))
	command_registry.register_command(
		&"resource",
		"resource <add|set> <n>",
		"增加或设置当前资源",
		Callable(self, "_command_resource")
	)
	command_registry.register_command(&"wave", "wave start", "释放下一波", Callable(self, "_command_wave"))
	command_registry.register_command(
		&"spawn",
		"spawn <enemy_id> [path_id]",
		"在指定或首条路径生成一个敌人",
		Callable(self, "_command_spawn")
	)
	command_registry.register_command(
		&"debug",
		"debug <list|set category on|off>",
		"列出或切换调试分类",
		Callable(self, "_command_debug")
	)
	command_registry.register_command(
		&"stuff",
		"stuff edit <on|off>",
		"开启或关闭运行时关卡元素编辑",
		Callable(self, "_command_stuff")
	)


func _command_reload(arguments: Array[String]) -> Dictionary:
	if not arguments.is_empty():
		return _error("用法：reload")
	if _level_loader == null:
		return _error("LevelLoader 未连接")
	return _ok("关卡已重载") if _level_loader.reload_current_level() else _error("关卡重载失败")


func _command_load(arguments: Array[String]) -> Dictionary:
	if arguments.size() != 1:
		return _error("用法：load <res://path.tres>")
	if _level_loader == null:
		return _error("LevelLoader 未连接")
	return _ok("已加载：%s" % arguments[0]) if _level_loader.load_level_path(arguments[0]) else _error("关卡加载失败")


func _command_resource(arguments: Array[String]) -> Dictionary:
	if arguments.size() != 2 or (arguments[0] != "add" and arguments[0] != "set"):
		return _error("用法：resource <add|set> <n>")
	if _resource_manager == null:
		return _error("ResourceManager 未连接")
	if not _resource_manager.feature_enabled:
		return _error("ResourceManager 已关闭")
	if not arguments[1].is_valid_float():
		return _error("资源数值必须是有限数字")
	var amount := arguments[1].to_float()
	if not is_finite(amount):
		return _error("资源数值必须是有限数字")
	if arguments[0] == "add":
		if amount <= 0.0:
			return _error("增加量必须大于 0")
		_resource_manager.gain(amount, "debug_command")
	else:
		if not _resource_manager.set_main_resource(amount, "debug_command"):
			return _error("资源设置失败；数值必须非负")
	return _ok("当前资源：%.1f" % _resource_manager.main_resource)


func _command_wave(arguments: Array[String]) -> Dictionary:
	if arguments != ["start"]:
		return _error("用法：wave start")
	if _wave_manager == null:
		return _error("WaveManager 未连接")
	var wave_number := _wave_manager.get_next_wave_number()
	return _ok("第 %d 波已释放" % wave_number) if _wave_manager.start_next_wave() else _error("当前状态无法释放下一波")


func _command_spawn(arguments: Array[String]) -> Dictionary:
	if arguments.size() < 1 or arguments.size() > 2:
		return _error("用法：spawn <enemy_id> [path_id]")
	if _level_loader == null or _wave_manager == null:
		return _error("敌人生成依赖未连接")
	var level := _level_loader.get_current_level()
	if level == null:
		return _error("当前没有关卡")
	var enemy := _find_enemy(level, arguments[0])
	if enemy == null:
		return _error("未找到敌人：%s" % arguments[0])
	var path: PathDefinition
	if arguments.size() == 2:
		path = level.get_path_by_id(StringName(arguments[1]))
		if path == null:
			return _error("当前关卡不存在路径：%s" % arguments[1])
	elif not level.paths.is_empty():
		path = level.paths[0]
	if path == null:
		return _error("当前关卡没有可用路径")
	var spawn_result := _wave_manager.spawn_debug_enemy(enemy, path)
	return spawn_result if bool(spawn_result.get("success", false)) else _error(str(spawn_result.get("message", "生成失败")))


func _command_debug(arguments: Array[String]) -> Dictionary:
	if arguments == ["list"]:
		var lines: Array[String] = []
		for entry in category_registry.list_categories():
			lines.append("%-8s %s" % [
				str(entry.get("id", "")),
				"on" if bool(entry.get("enabled", false)) else "off",
			])
		return _ok("\n".join(lines))
	if arguments.size() == 3 and arguments[0] == "set":
		var enabled_value := arguments[2].to_lower()
		if enabled_value != "on" and enabled_value != "off":
			return _error("分类状态必须为 on 或 off")
		var category_id := StringName(arguments[1].to_lower())
		if not category_registry.set_enabled(category_id, enabled_value == "on"):
			return _error("未知调试分类：%s" % arguments[1])
		return _ok("%s = %s" % [category_id, enabled_value])
	return _error("用法：debug list 或 debug set <category> <on|off>")


func _command_stuff(arguments: Array[String]) -> Dictionary:
	if arguments.size() != 2 or arguments[0] != "edit" or arguments[1] not in ["on", "off"]:
		return _error("用法：stuff edit <on|off>")
	if _stuff_editor_controller == null or not _stuff_editor_controller.has_method("set_active"):
		return _error("运行时关卡元素编辑器未连接")
	var enabled := arguments[1] == "on"
	if not bool(_stuff_editor_controller.call("set_active", enabled)):
		return _error("无法%s关卡元素编辑；可能存在未保存修改" % ("开启" if enabled else "关闭"))
	return _ok("关卡元素编辑已%s" % ("开启" if enabled else "关闭"))


func _find_enemy(level: LevelResource, enemy_id: String) -> EnemyDefinition:
	var normalized := enemy_id.to_lower()
	for wave in level.waves:
		if wave == null:
			continue
		for group in wave.spawn_groups:
			if group == null or group.enemy == null:
				continue
			if String(group.enemy.enemy_id).to_lower() == normalized:
				return group.enemy
	var directory := DirAccess.open(ENEMY_DIRECTORY)
	if directory == null:
		return null
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			var definition := ResourceLoader.load(
				"%s/%s" % [ENEMY_DIRECTORY, file_name]
			) as EnemyDefinition
			if definition != null and String(definition.enemy_id).to_lower() == normalized:
				directory.list_dir_end()
				return definition
		file_name = directory.get_next()
	directory.list_dir_end()
	return null


func _provide_grid() -> String:
	if _grid_manager == null:
		return "GridManager 未连接"
	return "%s | 尺寸 %s | 格距 %.2f" % [
		str(_grid_manager.get_geometry_tag()),
		str(_grid_manager.grid_size),
		_grid_manager.cell_size,
	]


func _provide_pick() -> String:
	return str(_pick_provider.call()) if _pick_provider.is_valid() else "当前无拾取提供器"


func _provide_path() -> String:
	var level := _level_loader.get_current_level() if _level_loader != null else null
	var path_count := level.paths.size() if level != null else 0
	return "路径 %d | 调试线 %s" % [
		path_count,
		"显示" if _path_manager != null and _path_manager.show_paths else "隐藏",
	]


func _provide_reroute() -> String:
	if _path_route_planner == null:
		return "PathRoutePlanner 未连接"
	return "自动寻路 %s | 路线高亮 %s" % [
		"开启" if _path_route_planner.automatic_route_enabled else "关闭",
		"显示" if _path_route_planner.show_selected_detour else "隐藏",
	]


func _provide_mirror() -> String:
	if _mirror_manager == null or _resource_manager == null:
		return "MirrorManager 未连接"
	var selected := _mirror_manager.get_selected_mirror()
	return "复制镜 %d/%d | 反射镜 %d/%d | 选中 %s" % [
		_resource_manager.get_copy_mirror_count(),
		_resource_manager.copy_mirror_cap,
		_resource_manager.get_reflect_mirror_count(),
		_resource_manager.reflect_mirror_cap,
		selected.edge_id if selected != null else "无",
	]


func _provide_combat() -> String:
	if _combat_manager == null or _resource_manager == null:
		return "CombatManager 未连接"
	return "目标 %d | 建筑 %d/%d" % [
		_combat_manager.get_targets().size(),
		_resource_manager.get_building_count(),
		_resource_manager.building_cap,
	]


func _provide_fps() -> String:
	return "FPS %d | time_scale %.2f" % [Engine.get_frames_per_second(), Engine.time_scale]


func _provide_wave() -> String:
	if _wave_manager == null:
		return "WaveManager 未连接"
	return "%s | 波次 %d/%d | 敌人 %d" % [
		_wave_manager.get_state_name(),
		_wave_manager.get_current_wave_number(),
		_wave_manager.get_total_wave_count(),
		_wave_manager.get_active_enemy_count(),
	]


func _toggle_path_visual(enabled: bool) -> void:
	if _path_manager != null:
		_path_manager.set_debug_paths_visible(enabled)


func _toggle_reroute_visual(enabled: bool) -> void:
	if _path_route_planner != null:
		_path_route_planner.set_debug_route_visible(enabled)


func _ok(message: String) -> Dictionary:
	return {"success": true, "message": message, "clear": false}


func _error(message: String) -> Dictionary:
	return {"success": false, "message": message, "clear": false}
