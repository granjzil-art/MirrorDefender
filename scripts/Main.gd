## Main —— M3 主场景控制器
##
## 职责：装配 Level / Grid / Tile / Resource / Combat / Building / 相机与调试 HUD。
## 这是 M3 的验收入口场景。
##
## 操作：
##   WASD 平移镜头 / QE 旋转镜头 / XC 调俯仰 / 滚轮缩放
##   T    切换 六边形 <-> 正方形
##   鼠标悬停：高亮格；靠近边时高亮边（并显示 canonical_edge_id）
##   左键：执行正式卡槽当前模式（选择 / 单次放置）
##   右键：回到选择模式
##   R    旋转选中建筑朝向
##   F    清除锁定的可破坏障碍
extends Node3D

const LevelLoaderScript := preload("res://scripts/level/LevelLoader.gd")
const LevelDebugPanelScript := preload("res://scripts/level/LevelDebugPanel.gd")
const M3DebugPanelScript := preload("res://scripts/ui/M3DebugPanel.gd")
const BuildingActionPanelScript := preload("res://scripts/ui/BuildingActionPanel.gd")
const MirrorActionPanelScript := preload("res://scripts/ui/MirrorActionPanel.gd")
const PathManagerScript := preload("res://scripts/path/PathManager.gd")
const BaseCoreScript := preload("res://scripts/unit/BaseCore.gd")
const WaveManagerScript := preload("res://scripts/wave/WaveManager.gd")
const PathHoverPreviewScript := preload("res://scripts/path/PathHoverPreview.gd")
const PathHoverPreviewScene := preload("res://scenes/path/PathHoverPreview.tscn")
const TileEffectSystemScript := preload("res://scripts/tile/TileEffectSystem.gd")
const PathRoutePlannerScript := preload("res://scripts/path/PathRoutePlanner.gd")
const EdgeOccupancyRegistryScript := preload("res://scripts/shared/EdgeOccupancyRegistry.gd")
const MirrorManagerScript := preload("res://scripts/mirror/MirrorManager.gd")
const LevelReflectionSurfaceScript := preload("res://scripts/fx/LevelReflectionSurface.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const RuntimeHudScript := preload("res://scripts/ui/RuntimeHud.gd")
const CopyMirrorDefinitionResource := preload("res://resources/mirrors/CopyMirror.tres")
const LevelReflectionDefinitionResource := preload("res://resources/fx/LevelReflection.tres")
const BarrierDefinitionResource := preload("res://resources/buildings/Barrier.tres")
const EdgeBarrierDefinitionResource := preload("res://resources/buildings/EdgeBarrier.tres")

@onready var grid: GridManager = $GridManager
@onready var renderer: GridRenderer = $GridRenderer
@onready var tile_manager: TileManager = $TileManager
@onready var tile_renderer: TileRenderer = $TileRenderer
@onready var resource_manager: ResourceManager = $ResourceManager
@onready var combat_manager: CombatManager = $CombatManager
@onready var building_manager: BuildingManager = $BuildingManager
@onready var level_loader: LevelLoaderScript = $LevelLoader
@onready var cam_rig: CameraController = $CameraRig
@onready var hud_label: Label = $HUD/Panel/Info
@onready var hint_label: Label = $HUD/Hint
@onready var level_debug_panel: LevelDebugPanelScript = $HUD/LevelDebugPanel
@onready var m3_debug_panel: M3DebugPanelScript = $HUD/M3DebugPanel
@onready var runtime_hud: RuntimeHudScript = $HUD/RuntimeHud
@onready var runtime_interaction: RuntimeInteractionControllerScript = $RuntimeInteractionController
@onready var game_time_controller: GameTimeControllerScript = $GameTimeController

var _camera: Camera3D
var _building_action_panel: BuildingActionPanel
var _mirror_action_panel: MirrorActionPanel
var path_manager: PathManager
var base_core: BaseCore
var wave_manager: WaveManager
var tile_effect_system: TileEffectSystem
var path_route_planner: PathRoutePlanner
var edge_occupancy_registry: EdgeOccupancyRegistry
var mirror_manager: MirrorManager
var level_reflection_surface: LevelReflectionSurfaceScript
var path_hover_preview: PathHoverPreviewScript
var _has_selected_cell: bool = false
var _selected_cell: Vector3i = Vector3i.ZERO
var _has_selected_edge: bool = false
var _selected_edge_index: int = -1
var _selected_edge_id: String = ""

func _ready() -> void:
	_camera = cam_rig.get_camera()
	renderer.set_grid(grid)
	tile_manager.set_grid(grid)
	grid.set_cell_height_resolver(Callable(tile_manager, "get_world_height"))
	tile_renderer.set_grid(grid)
	tile_renderer.set_tile_manager(tile_manager)
	level_reflection_surface = LevelReflectionSurfaceScript.new()
	add_child(level_reflection_surface)
	level_reflection_surface.configure(grid, tile_manager, _camera, LevelReflectionDefinitionResource)
	building_manager.barrier = BarrierDefinitionResource
	building_manager.edge_barrier = EdgeBarrierDefinitionResource
	edge_occupancy_registry = EdgeOccupancyRegistryScript.new()
	building_manager.set_edge_occupancy_registry(edge_occupancy_registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	mirror_manager = MirrorManagerScript.new()
	add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = CopyMirrorDefinitionResource
	mirror_manager.configure(
		grid,
		tile_manager,
		resource_manager,
		combat_manager,
		building_manager,
		edge_occupancy_registry
	)
	mirror_manager.set_tile_visual_snapshot_resolver(Callable(tile_renderer, "create_tile_content_visual_snapshot"))
	mirror_manager.set_reflection_camera(_camera)
	building_manager.building_selected.connect(_on_building_selected_for_exclusivity)
	mirror_manager.mirror_selected.connect(_on_mirror_selected_for_exclusivity)
	building_manager.set_projection_blocker_resolver(Callable(mirror_manager, "resolve_projected_blocker"))
	tile_manager.set_navigation_overlay_resolver(Callable(mirror_manager, "blocks_enemy_navigation"))
	tile_manager.set_navigation_overlay_blocker_resolver(Callable(mirror_manager, "resolve_projected_navigation_blocker"))
	runtime_interaction.configure(building_manager, mirror_manager)
	runtime_interaction.world_selection_changed.connect(_on_world_selection_changed)
	game_time_controller.configure(runtime_interaction, building_manager, mirror_manager)
	runtime_hud.configure(
		runtime_interaction,
		game_time_controller,
		resource_manager,
		building_manager,
		mirror_manager
	)
	runtime_hud.restart_level_requested.connect(_on_restart_level_requested)
	runtime_hud.exit_game_requested.connect(_on_exit_game_requested)
	runtime_hud.modal_state_changed.connect(_on_runtime_modal_state_changed)
	runtime_hud.wave_paths_preview_requested.connect(_on_wave_paths_preview_requested)
	runtime_hud.wave_paths_preview_cleared.connect(_on_wave_paths_preview_cleared)
	m3_debug_panel.configure(building_manager, resource_manager, combat_manager, mirror_manager)
	_building_action_panel = BuildingActionPanelScript.new()
	$HUD.add_child(_building_action_panel)
	_building_action_panel.configure(building_manager, _camera)
	_mirror_action_panel = MirrorActionPanelScript.new()
	$HUD.add_child(_mirror_action_panel)
	_mirror_action_panel.configure(mirror_manager, _camera)
	path_manager = PathManagerScript.new()
	add_child(path_manager)
	path_manager.configure(grid, tile_manager)
	path_hover_preview = PathHoverPreviewScene.instantiate() as PathHoverPreviewScript
	add_child(path_hover_preview)
	path_hover_preview.configure(path_manager)
	base_core = BaseCoreScript.new()
	add_child(base_core)
	base_core.configure(grid, tile_manager)
	tile_effect_system = TileEffectSystemScript.new()
	add_child(tile_effect_system)
	tile_effect_system.configure(tile_manager)
	tile_effect_system.set_effect_overlay_resolver(Callable(mirror_manager, "get_projected_effects"))
	tile_effect_system.set_effect_overlay_binding_resolver(Callable(mirror_manager, "get_projected_effect_bindings"))
	tile_renderer.set_effect_visual_state_resolver(Callable(tile_effect_system, "get_void_fill_ratio"))
	tile_effect_system.effect_visual_state_changed.connect(_on_effect_visual_state_changed)
	runtime_hud.configure_inspection(
		grid,
		tile_manager,
		building_manager,
		mirror_manager,
		tile_effect_system
	)
	path_route_planner = PathRoutePlannerScript.new()
	add_child(path_route_planner)
	path_route_planner.configure(grid, tile_manager)
	wave_manager = WaveManagerScript.new()
	add_child(wave_manager)
	wave_manager.configure(
		path_manager,
		combat_manager,
		resource_manager,
		base_core,
		Callable(building_manager, "resolve_path_blocker"),
		Callable(path_route_planner, "find_detour"),
		Callable(path_manager, "get_cell_world_position"),
		Callable(tile_effect_system, "apply_enter"),
		Callable(tile_effect_system, "apply_stay"),
		Callable(tile_manager, "blocks_enemy_navigation")
	)
	runtime_hud.configure_global_info(resource_manager, wave_manager, base_core)
	runtime_hud.configure_wave_timeline(wave_manager)
	level_loader.configure(grid, tile_manager)
	level_loader.level_loaded.connect(_on_level_loaded)
	level_debug_panel.configure(level_loader)
	level_loader.load_initial_level()
	_update_hint()

func _process(_delta: float) -> void:
	if runtime_hud != null and runtime_hud.is_modal_open():
		return
	_update_pick()


## Cancellation is global and intentionally runs before GUI dispatch so a
## right-click over any HUD control still returns to SELECT.
func _input(event: InputEvent) -> void:
	if runtime_hud != null and runtime_hud.is_modal_open():
		if event.is_action_pressed("cancel_action") or event.is_action_pressed("ui_cancel"):
			runtime_hud.close_pause_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel_action"):
		runtime_interaction.cancel_to_select(true)
		get_viewport().set_input_as_handled()

func _update_pick() -> void:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()

	var edge := grid.pick_edge(_camera, mp)
	var cell := grid.pick_cell(_camera, mp)
	mirror_manager.set_inspected_cell(cell.cell if cell.hit else null)
	_update_building_preview(cell, edge)

	# 边优先高亮（靠近边时），否则高亮格。
	if edge.hit:
		renderer.highlight_edge(edge.cell, edge.edge_index, true)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)
	else:
		renderer.highlight_edge(Vector3i.ZERO, 0, false)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)

	_update_hud(cell, edge)

func _update_hud(cell: Dictionary, edge: Dictionary) -> void:
	var shape_name := "六边形(HEX)" if grid.grid_shape == GridManager.Shape.HEX else "正方形(SQUARE)"
	var lines: Array[String] = []
	lines.append("关卡标签: %s | 网格: %s | 格距: %.2f" % [str(grid.get_geometry_tag()), shape_name, grid.cell_size])
	if base_core != null and wave_manager != null:
		var base_current: int = ceili(base_core.current_hp)
		var base_maximum: int = ceili(base_core.max_hp)
		var wave_current := wave_manager.get_current_wave_number()
		var wave_total := wave_manager.get_total_wave_count()
		var active_enemies := wave_manager.get_active_enemy_count()
		var wave_state := wave_manager.get_state_name()
		lines.append("据点: %d/%d | 波次 %d/%d | 敌人 %d | %s" % [
			base_current,
			base_maximum,
			wave_current,
			wave_total,
			active_enemies,
			wave_state,
		])
	if cell.hit:
		lines.append("拾取格 cell = %s" % str(cell.cell))
		var tile := tile_manager.get_tile(cell.cell)
		if tile != null:
			lines.append("地块: %s | 高度档: %d" % [tile.get_display_name(), tile.height_level])
			var occupant := tile_manager.get_occupant(cell.cell)
			if occupant is Building:
				var occupied_building: Building = occupant
				var occupied_stats := occupied_building.get_level_stats()
				if occupied_building.is_path_blocker():
					lines.append("占位: %s L%d/%d | 耐久 %d/%d | 脱战 %.1fs 后 +%.1f/s" % [
						occupied_building.definition.display_name,
						occupied_building.level,
						occupied_building.get_max_level(),
						ceili(occupied_building.current_durability),
						ceili(occupied_building.maximum_durability),
						occupied_stats.regeneration_delay,
						occupied_stats.regeneration_per_second,
					])
				else:
					lines.append("占位: %s L%d/%d | 索敌 %.1f | 射程 %.1f" % [
						occupied_building.definition.display_name,
						occupied_building.level,
						occupied_building.get_max_level(),
						occupied_stats.targeting_range,
						occupied_stats.attack_range,
					])
			elif occupant != null:
				lines.append("占位对象: %s" % occupant.name)
			if tile.is_destructible():
				lines.append("按 F 清除障碍，转为可建造")
		var projection_lines := mirror_manager.get_projection_inspection_lines(cell.cell)
		if not projection_lines.is_empty():
			lines.append("重叠虚像 %d 个：%s" % [projection_lines.size(), "；".join(projection_lines)])
		var preview := building_manager.get_preview_building()
		if preview != null and preview.cell == cell.cell:
			if preview.is_edge_placement():
				var preview_connector := "↔" if preview.is_bidirectional_edge_blocker() else "→"
				lines.append("放置预览: %s L1 | %s %s %s（贴边固定）" % [
					preview.definition.display_name,
					str(preview.cell),
					preview_connector,
					str(preview.edge_to_cell),
				])
			else:
				lines.append("放置预览: %s L1 | 朝向 %d/%d" % [
					preview.definition.display_name,
					preview.facing_index + 1,
					preview.get_facing_slot_count(),
				])
	else:
		lines.append("拾取格 cell = (界外)")
	if edge.hit:
		lines.append("拾取边 index = %d" % edge.edge_index)
		lines.append("边唯一键 = %s" % edge.id)
		var edge_building := building_manager.get_edge_building(edge.id)
		if edge_building != null:
			var edge_connector := "↔" if edge_building.is_bidirectional_edge_blocker() else "→"
			lines.append("边占位: %s L%d/%d | %s %s %s | 耐久 %d/%d" % [
				edge_building.definition.display_name,
				edge_building.level,
				edge_building.get_max_level(),
				str(edge_building.cell),
				edge_connector,
				str(edge_building.edge_to_cell),
				ceili(edge_building.current_durability),
				ceili(edge_building.maximum_durability),
			])
		else:
			var edge_mirror := mirror_manager.get_mirror(edge.id)
			if edge_mirror != null:
				lines.append("边占位: 复制镜 | 生效侧 %s | 当前投影 %d" % [
					str(edge_mirror.get_active_cell()),
					mirror_manager.get_projections().size(),
				])
	else:
		lines.append("拾取边 = (无)")
	if _has_selected_cell:
		lines.append("已锁定格 cell = %s" % str(_selected_cell))
	if _has_selected_edge:
		lines.append("已锁定边 index = %d | %s" % [_selected_edge_index, _selected_edge_id])
	var selected_building := building_manager.get_selected_building()
	if selected_building != null:
		var selected_stats := selected_building.get_level_stats()
		if selected_building.is_edge_placement():
			var selected_connector := "↔" if selected_building.is_bidirectional_edge_blocker() else "→"
			lines.append("建筑: %s L%d/%d | %s %s %s（贴边固定）" % [
				selected_building.definition.display_name,
				selected_building.level,
				selected_building.get_max_level(),
				str(selected_building.cell),
				selected_connector,
				str(selected_building.edge_to_cell),
			])
		else:
			lines.append("建筑: %s L%d/%d | 世界朝向 %d/%d" % [
				selected_building.definition.display_name,
				selected_building.level,
				selected_building.get_max_level(),
				selected_building.facing_index + 1,
				selected_building.get_facing_slot_count(),
			])
		if selected_building.is_path_blocker():
			lines.append("耐久 %d/%d | 脱战 %.1fs | 回血 %.1f/s | 反伤 %.0f%%" % [
				ceili(selected_building.current_durability),
				ceili(selected_building.maximum_durability),
				selected_stats.regeneration_delay,
				selected_stats.regeneration_per_second,
				selected_stats.damage_reflection_ratio * 100.0,
			])
		else:
			lines.append("伤害 %.1f | 索敌 %.1f | 射程 %.1f | 产出 %.1f/s" % [
				selected_building.get_instant_damage() if selected_building.definition.kind == BuildingDefinition.Kind.ARROW_TOWER else selected_building.get_laser_damage_per_second(),
				selected_stats.targeting_range,
				selected_stats.attack_range,
				selected_stats.resource_per_second,
			])
	var selected_mirror := mirror_manager.get_selected_mirror()
	if selected_mirror != null:
		lines.append("镜子: 复制镜 | 边 %s | 生效侧 %s | R 翻面 / Delete 删除" % [
			selected_mirror.edge_id,
			str(selected_mirror.get_active_cell()),
		])
	var mirror_preview := mirror_manager.get_preview_info()
	if not mirror_preview.is_empty():
		if bool(mirror_preview.get("has_source", false)):
			lines.append("镜像预览: %s → %s | %s" % [
				str(mirror_preview.source_cell),
				str(mirror_preview.target_cell),
				"、".join(mirror_preview.types),
			])
		else:
			lines.append("镜像预览: %s" % str(mirror_preview.warning))
	hud_label.text = "\n".join(lines)

func _update_hint() -> void:
	hint_label.text = "WASD 平移 | QE 旋转 | X 降低/C 提高俯仰 | 滚轮缩放 | 左键选择/单次放置 | 右键取消 | R 旋转/镜子翻面 | Delete 删除镜子 | F 清障"

func _unhandled_input(event: InputEvent) -> void:
	if runtime_hud != null and runtime_hud.is_modal_open():
		return
	if event.is_action_pressed("toggle_grid_shape"):
		if grid.grid_shape == GridManager.Shape.HEX:
			grid.grid_shape = GridManager.Shape.SQUARE
		else:
			grid.grid_shape = GridManager.Shape.HEX
		var current_level := level_loader.get_current_level()
		if current_level != null:
			tile_manager.load_level(current_level)
	elif event.is_action_pressed("place_select"):
		_handle_primary_action()
	elif event.is_action_pressed("rotate_facing"):
		if runtime_interaction.is_copy_mirror_mode():
			mirror_manager.flip_preview()
		elif mirror_manager.get_selected_mirror() != null:
			mirror_manager.flip_selected()
		elif runtime_interaction.get_selected_definition() != null:
			building_manager.rotate_preview()
		else:
			building_manager.rotate_selected()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		mirror_manager.remove_selected_mirror()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_destroy_selected_obstacle()

func _handle_primary_action() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var cell_pick: Dictionary = grid.pick_cell(_camera, mouse_position)
	var edge_pick: Dictionary = grid.pick_edge(_camera, mouse_position)
	runtime_interaction.handle_primary(cell_pick, edge_pick)

func _update_building_preview(cell_pick: Dictionary, edge_pick: Dictionary) -> void:
	if runtime_interaction.is_copy_mirror_mode():
		building_manager.clear_preview()
		if get_viewport().gui_get_hovered_control() != null or not edge_pick.hit:
			mirror_manager.clear_preview()
			return
		mirror_manager.update_preview(edge_pick.cell, edge_pick.edge_index)
		return
	mirror_manager.clear_preview()
	var definition := runtime_interaction.get_selected_definition()
	if definition == null or get_viewport().gui_get_hovered_control() != null:
		building_manager.clear_preview()
		return
	if definition.is_edge_building():
		if not edge_pick.hit:
			building_manager.clear_preview()
			return
		var from_cell: Vector3i = edge_pick.cell
		var placement_edge_index: int = edge_pick.edge_index
		building_manager.update_edge_preview(from_cell, placement_edge_index, definition)
		return
	if not cell_pick.hit:
		building_manager.clear_preview()
		return
	var cell: Vector3i = cell_pick.cell
	building_manager.update_preview(cell, definition)

func _destroy_selected_obstacle() -> void:
	if not _has_selected_cell:
		return
	tile_manager.destroy_obstacle_at(_selected_cell)

func _on_level_loaded(level_resource: LevelResource, source_path: String) -> void:
	resource_manager.apply_level_configuration(level_resource)
	combat_manager.clear_targets()
	path_manager.load_level(level_resource)
	path_route_planner.load_level(level_resource)
	base_core.load_level(level_resource)
	wave_manager.load_level(level_resource)
	runtime_hud.apply_level_configuration(level_resource, source_path)
	_has_selected_cell = false
	_has_selected_edge = false
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)
	runtime_interaction.cancel_to_select(true)

func _on_effect_visual_state_changed(source_cell: Vector3i, fill_ratio: float) -> void:
	tile_renderer.refresh_effect_visual(source_cell, fill_ratio)
	mirror_manager.rebuild_now()

func _on_building_selected_for_exclusivity(building: Building) -> void:
	if building != null and mirror_manager.get_selected_mirror() != null:
		mirror_manager.select_mirror(null)

func _on_mirror_selected_for_exclusivity(mirror: CopyMirror) -> void:
	if mirror != null and building_manager.get_selected_building() != null:
		building_manager.select_building(null)


func _on_world_selection_changed(has_cell: bool, cell: Vector3i, edge_id: String) -> void:
	_has_selected_cell = has_cell
	_selected_cell = cell if has_cell else Vector3i.ZERO
	_selected_edge_id = edge_id if has_cell else ""
	_has_selected_edge = not _selected_edge_id.is_empty()
	_selected_edge_index = -1
	if not _has_selected_edge:
		return
	for edge_index in range(grid.edge_count()):
		if grid.canonical_edge_id(_selected_cell, edge_index) == _selected_edge_id:
			_selected_edge_index = edge_index
			return


func _on_restart_level_requested() -> void:
	if level_loader.reload_current_level():
		runtime_hud.close_pause_menu()


func _on_exit_game_requested() -> void:
	get_tree().quit()


func _on_runtime_modal_state_changed(open: bool) -> void:
	cam_rig.set_input_enabled(not open)
	if not open:
		return
	building_manager.clear_preview(false)
	mirror_manager.clear_preview()
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)


func _on_wave_paths_preview_requested(paths: Array) -> void:
	if path_hover_preview != null:
		path_hover_preview.preview_paths(paths)


func _on_wave_paths_preview_cleared() -> void:
	if path_hover_preview != null:
		path_hover_preview.clear_preview()
