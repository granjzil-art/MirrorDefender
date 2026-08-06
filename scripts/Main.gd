## Main —— M3 主场景控制器
##
## 职责：装配 Level / Grid / Tile / Resource / Combat / Building / 相机与正式 HUD。
##
## 操作：
##   WASD 平移镜头 / QE 旋转镜头 / XC 调俯仰 / 滚轮缩放
##   鼠标悬停：高亮格；靠近边时高亮边（并显示 canonical_edge_id）
##   左键：执行正式卡槽当前模式（选择 / 单次放置）
##   右键：回到选择模式
##   R    旋转选中建筑朝向
##   F    清除锁定的可破坏障碍
##   F1   打开/关闭调试控制台
class_name MainController
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
const RuntimePathDisplayScene := preload("res://scenes/path/RuntimePathDisplayController.tscn")
const TileEffectSystemScript := preload("res://scripts/tile/TileEffectSystem.gd")
const PathRoutePlannerScript := preload("res://scripts/path/PathRoutePlanner.gd")
const PathPlacementConnectivityGuardScript := preload("res://scripts/path/PathPlacementConnectivityGuard.gd")
const EdgeOccupancyRegistryScript := preload("res://scripts/shared/EdgeOccupancyRegistry.gd")
const MirrorManagerScript := preload("res://scripts/mirror/MirrorManager.gd")
const LevelReflectionSurfaceScript := preload("res://scripts/fx/LevelReflectionSurface.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const RuntimeHudScript := preload("res://scripts/ui/RuntimeHud.gd")
const TerrainManagerScript := preload("res://scripts/terrain/TerrainManager.gd")
const TerrainRendererScript := preload("res://scripts/terrain/TerrainRenderer.gd")
const StuffManagerScript := preload("res://scripts/stuff/StuffManager.gd")
const StuffRendererScript := preload("res://scripts/stuff/StuffRenderer.gd")
const StuffPlacementValidatorScript := preload("res://scripts/stuff/StuffPlacementValidator.gd")
const RuntimeStuffEditSessionScript := preload("res://scripts/stuff/RuntimeStuffEditSession.gd")
const RuntimeStuffEditorControllerScript := preload("res://scripts/stuff/RuntimeStuffEditorController.gd")
const CameraPresetControllerScript := preload("res://scripts/camera/CameraPresetController.gd")
const MiniatureDofControllerScript := preload("res://scripts/camera/MiniatureDofController.gd")
const RuntimeDebugBindingsScript := preload("res://scripts/debug/RuntimeDebugBindings.gd")
const LightingControllerScript := preload("res://scripts/lighting/LightingController.gd")
const LightingTestPanelScript := preload("res://scripts/ui/LightingTestPanel.gd")
const BuildingSelectionVisualizerScript := preload("res://scripts/building/BuildingSelectionVisualizer.gd")
const HoldRepeatGateScript := preload("res://scripts/shared/HoldRepeatGate.gd")
const CopyMirrorDefinitionResource := preload("res://resources/mirrors/CopyMirror.tres")
const ReflectMirrorDefinitionResource := preload("res://resources/mirrors/ReflectMirror.tres")
const LevelReflectionDefinitionResource := preload("res://resources/fx/LevelReflection.tres")
const BarrierDefinitionResource := preload("res://resources/buildings/Barrier.tres")
const EdgeBarrierDefinitionResource := preload("res://resources/buildings/EdgeBarrier.tres")
const AcrylicDisplayCaseDefinitionResource := preload("res://resources/lighting/AcrylicDisplayCase.tres")
const WhiteSoftLightingProfile := preload("res://resources/lighting/WhiteSoft.tres")
const WarmYellowLightingProfile := preload("res://resources/lighting/WarmYellow.tres")
const CyanRedLightingProfile := preload("res://resources/lighting/CyanRedContrast.tres")
const MiniatureDofDefinitionResource := preload("res://resources/camera/MiniatureDofDefault.tres")

@export_group("M6 Camera Presets")
@export var camera_presets_enabled: bool = true
@export_range(0.0, 5.0, 0.01, "or_greater") var camera_preset_transition_duration: float = 0.35
@export var camera_preset_transition_curve: Curve

@export_group("Miniature Depth Of Field")
@export var miniature_dof_enabled: bool = true
@export var miniature_dof_test_shortcut_enabled: bool = true

@export_group("M6 Debug Console")
@export var debug_console_enabled: bool = true

@export_group("Lighting Presentation")
@export var lighting_enabled: bool = true
@export var lighting_test_panel_enabled: bool = true
@export var lighting_test_shortcuts_enabled: bool = true

@export_group("Building Rotation Repeat")
@export_range(0.0, 2.0, 0.01, "or_greater") var selected_rotation_hold_delay: float = 0.3
@export_range(0.02, 1.0, 0.01, "or_greater") var selected_rotation_repeat_interval: float = 0.08
@export_range(1, 12, 1, "or_greater") var selected_rotation_max_repeats_per_frame: int = 4

signal return_to_level_select_requested
signal startup_level_load_resolved(success: bool, reason: String)

@onready var grid: GridManager = $GridManager
@onready var renderer: GridRenderer = $GridRenderer
@onready var terrain_manager: TerrainManagerScript = $TerrainManager
@onready var terrain_renderer: TerrainRendererScript = $TerrainRenderer
@onready var stuff_manager: StuffManagerScript = $StuffManager
@onready var stuff_renderer: StuffRendererScript = $StuffRenderer
@onready var tile_manager: TileManager = $TileManager
@onready var tile_renderer: TileRenderer = $TileRenderer
@onready var resource_manager: ResourceManager = $ResourceManager
@onready var combat_manager: CombatManager = $CombatManager
@onready var building_manager: BuildingManager = $BuildingManager
@onready var building_selection_visualizer: BuildingSelectionVisualizerScript = $BuildingSelectionVisualizer
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
var path_placement_connectivity_guard: PathPlacementConnectivityGuard
var edge_occupancy_registry: EdgeOccupancyRegistry
var mirror_manager: MirrorManager
var level_reflection_surface: LevelReflectionSurfaceScript
var path_hover_preview: PathHoverPreviewScript
var runtime_path_display: RuntimePathDisplayController
var camera_preset_controller: CameraPresetControllerScript
var miniature_dof_controller: MiniatureDofControllerScript
var runtime_debug_bindings: RuntimeDebugBindingsScript
var lighting_controller: LightingControllerScript
var lighting_test_panel: LightingTestPanelScript
var stuff_placement_validator: StuffPlacementValidatorScript
var runtime_stuff_edit_session: RuntimeStuffEditSessionScript
var runtime_stuff_editor: RuntimeStuffEditorControllerScript
var _has_selected_cell: bool = false
var _selected_cell: Vector3i = Vector3i.ZERO
var _has_selected_edge: bool = false
var _selected_edge_index: int = -1
var _selected_edge_id: String = ""
var _debug_cell_pick: Dictionary = {}
var _debug_edge_pick: Dictionary = {}
var _startup_level: LevelResource
var _selected_rotation_repeat: HoldRepeatGate = HoldRepeatGateScript.new()


func configure_startup_level(level: LevelResource) -> bool:
	if is_node_ready() or level == null:
		return false
	_startup_level = level
	return true


func _ready() -> void:
	_selected_rotation_repeat.configure(
		selected_rotation_hold_delay,
		selected_rotation_repeat_interval,
		selected_rotation_max_repeats_per_frame
	)
	_camera = cam_rig.get_camera()
	cam_rig.cancel_requested.connect(_on_camera_cancel_requested)
	hud_label.get_parent().visible = false
	hint_label.visible = false
	m3_debug_panel.feature_enabled = false
	m3_debug_panel.visible = false
	runtime_hud.debug_console.feature_enabled = debug_console_enabled
	runtime_hud.debug_overlay_panel.feature_enabled = debug_console_enabled
	camera_preset_controller = CameraPresetControllerScript.new()
	add_child(camera_preset_controller)
	camera_preset_controller.feature_enabled = camera_presets_enabled
	camera_preset_controller.transition_duration = camera_preset_transition_duration
	camera_preset_controller.transition_curve = camera_preset_transition_curve
	camera_preset_controller.configure(cam_rig)
	miniature_dof_controller = MiniatureDofControllerScript.new()
	miniature_dof_controller.name = "MiniatureDofController"
	miniature_dof_controller.feature_enabled = miniature_dof_enabled
	miniature_dof_controller.test_shortcut_enabled = miniature_dof_test_shortcut_enabled
	add_child(miniature_dof_controller)
	miniature_dof_controller.configure(_camera, cam_rig, grid, MiniatureDofDefinitionResource)
	renderer.set_grid(grid)
	terrain_manager.set_grid(grid)
	terrain_renderer.set_grid(grid)
	terrain_renderer.set_terrain_manager(terrain_manager)
	stuff_manager.configure(grid, terrain_manager)
	stuff_renderer.configure(grid, stuff_manager)
	tile_manager.set_grid(grid)
	tile_manager.legacy_content_runtime_enabled = false
	tile_manager.set_stuff_runtime_provider(stuff_manager)
	tile_manager.set_surface_height_resolver(Callable(terrain_manager, "get_world_height"))
	tile_manager.set_base_placement_resolvers(
		Callable(terrain_manager, "allows_tile_building"),
		Callable(terrain_manager, "allows_edge_building")
	)
	grid.set_cell_height_resolver(Callable(terrain_manager, "get_world_height"))
	grid.set_cell_surface_height_resolver(Callable(terrain_manager, "sample_surface_height"))
	grid.set_surface_raycast_resolver(Callable(terrain_manager, "raycast_surface"))
	tile_renderer.set_grid(grid)
	tile_renderer.set_tile_manager(tile_manager)
	lighting_controller = LightingControllerScript.new()
	lighting_controller.name = "LightingController"
	lighting_controller.feature_enabled = lighting_enabled
	lighting_controller.test_shortcuts_enabled = lighting_test_shortcuts_enabled
	add_child(lighting_controller)
	var lighting_profiles: Array[LightingProfile] = [
		WhiteSoftLightingProfile,
		WarmYellowLightingProfile,
		CyanRedLightingProfile,
	]
	var lighting_visual_roots: Array[Node3D] = [terrain_renderer, stuff_renderer]
	lighting_controller.configure(
		$WorldEnvironment,
		$Sun,
		grid,
		terrain_manager,
		AcrylicDisplayCaseDefinitionResource,
		lighting_profiles,
		lighting_visual_roots
	)
	if lighting_test_panel_enabled:
		lighting_test_panel = LightingTestPanelScript.new()
		lighting_test_panel.name = "LightingTestPanel"
		$HUD.add_child(lighting_test_panel)
		lighting_test_panel.configure(lighting_controller)
	level_reflection_surface = LevelReflectionSurfaceScript.new()
	add_child(level_reflection_surface)
	level_reflection_surface.configure(grid, tile_manager, _camera, LevelReflectionDefinitionResource)
	building_manager.barrier = BarrierDefinitionResource
	building_manager.edge_barrier = EdgeBarrierDefinitionResource
	edge_occupancy_registry = EdgeOccupancyRegistryScript.new()
	building_manager.set_edge_occupancy_registry(edge_occupancy_registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	building_selection_visualizer.configure(grid, building_manager)
	mirror_manager = MirrorManagerScript.new()
	add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = CopyMirrorDefinitionResource
	mirror_manager.reflect_mirror_definition = ReflectMirrorDefinitionResource
	mirror_manager.configure(
		grid,
		tile_manager,
		resource_manager,
		combat_manager,
		building_manager,
		edge_occupancy_registry
	)
	mirror_manager.set_tile_visual_snapshot_resolver(Callable(tile_renderer, "create_tile_content_visual_snapshot"))
	mirror_manager.set_stuff_manager(stuff_manager)
	mirror_manager.set_reflection_camera(_camera)
	building_manager.building_selected.connect(_on_building_selected_for_exclusivity)
	mirror_manager.mirror_selected.connect(_on_mirror_selected_for_exclusivity)
	building_manager.set_projection_blocker_resolver(Callable(mirror_manager, "resolve_projected_blocker"))
	tile_manager.set_navigation_overlay_resolver(Callable(mirror_manager, "blocks_enemy_navigation"))
	tile_manager.set_navigation_overlay_blocker_resolver(Callable(mirror_manager, "resolve_projected_navigation_blocker"))
	path_placement_connectivity_guard = PathPlacementConnectivityGuardScript.new()
	add_child(path_placement_connectivity_guard)
	path_placement_connectivity_guard.configure(
		grid,
		tile_manager,
		Callable(building_manager, "resolve_physical_path_blocker"),
		Callable(mirror_manager, "get_prospective_blocked_cells")
	)
	building_manager.set_path_connectivity_validator(
		Callable(path_placement_connectivity_guard, "validate_change")
	)
	mirror_manager.set_path_connectivity_validator(
		Callable(path_placement_connectivity_guard, "validate_change")
	)
	stuff_placement_validator = StuffPlacementValidatorScript.new()
	stuff_placement_validator.configure(
		grid,
		tile_manager,
		terrain_manager,
		stuff_manager,
		edge_occupancy_registry,
		Callable(path_placement_connectivity_guard, "validate_change")
	)
	runtime_stuff_edit_session = RuntimeStuffEditSessionScript.new()
	add_child(runtime_stuff_edit_session)
	runtime_stuff_edit_session.configure(
		stuff_manager,
		stuff_placement_validator,
		Callable(self, "_refresh_runtime_stuff_routes"),
		Callable(building_manager, "export_initial_placements"),
		Callable(mirror_manager, "export_initial_placements"),
		terrain_manager,
		Callable(self, "_refresh_runtime_level_authoring")
	)
	runtime_stuff_editor = RuntimeStuffEditorControllerScript.new()
	runtime_stuff_editor.name = "RuntimeStuffEditorController"
	add_child(runtime_stuff_editor)
	runtime_stuff_editor.configure(
		grid,
		terrain_manager,
		stuff_manager,
		stuff_renderer,
		level_loader,
		runtime_stuff_edit_session,
		game_time_controller
	)
	runtime_interaction.configure(building_manager, mirror_manager)
	runtime_interaction.world_selection_changed.connect(_on_world_selection_changed)
	game_time_controller.configure(runtime_interaction, building_manager, mirror_manager)
	runtime_hud.configure(
		runtime_interaction,
		game_time_controller,
		resource_manager,
		building_manager,
		mirror_manager,
		6,
		runtime_stuff_editor
	)
	runtime_hud.restart_level_requested.connect(_on_restart_level_requested)
	runtime_hud.exit_level_requested.connect(_on_exit_level_requested)
	runtime_hud.modal_state_changed.connect(_on_runtime_modal_state_changed)
	runtime_hud.wave_paths_preview_requested.connect(_on_wave_paths_preview_requested)
	runtime_hud.wave_paths_preview_cleared.connect(_on_wave_paths_preview_cleared)
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
	tile_effect_system.set_base_effect_provider(stuff_manager)
	tile_effect_system.set_effect_overlay_resolver(Callable(mirror_manager, "get_projected_effects"))
	tile_effect_system.set_effect_overlay_binding_resolver(Callable(mirror_manager, "get_projected_effect_bindings"))
	stuff_renderer.set_effect_visual_state_resolver(Callable(tile_effect_system, "get_void_fill_ratio_for_key"))
	tile_effect_system.effect_visual_state_changed.connect(_on_effect_visual_state_changed)
	tile_effect_system.effect_binding_visual_state_changed.connect(stuff_renderer.refresh_effect_visual)
	runtime_hud.configure_inspection(
		grid,
		tile_manager,
		building_manager,
		mirror_manager,
		tile_effect_system,
		stuff_manager,
		terrain_manager
	)
	path_route_planner = PathRoutePlannerScript.new()
	add_child(path_route_planner)
	path_route_planner.configure(grid, tile_manager)
	path_route_planner.route_snapshot_changed.connect(path_manager.set_runtime_route_snapshot)
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
	runtime_path_display = RuntimePathDisplayScene.instantiate() as RuntimePathDisplayController
	add_child(runtime_path_display)
	runtime_path_display.configure(wave_manager, path_manager)
	runtime_hud.configure_global_info(resource_manager, wave_manager, base_core)
	runtime_hud.configure_wave_controls(wave_manager)
	runtime_debug_bindings = RuntimeDebugBindingsScript.new()
	add_child(runtime_debug_bindings)
	runtime_debug_bindings.configure(
		level_loader,
		resource_manager,
		wave_manager,
		path_manager,
		path_route_planner,
		grid,
		combat_manager,
		mirror_manager,
		runtime_stuff_editor
	)
	runtime_debug_bindings.set_pick_provider(Callable(self, "_get_debug_pick_summary"))
	runtime_hud.configure_debug_console(
		runtime_debug_bindings.command_registry,
		runtime_debug_bindings.category_registry
	)
	level_loader.configure(grid, tile_manager, terrain_manager, stuff_manager)
	level_loader.level_loaded.connect(_on_level_loaded)
	level_debug_panel.configure(level_loader)
	var startup_loaded := false
	if _startup_level != null:
		startup_loaded = level_loader.load_level(_startup_level, _startup_level.resource_path)
	else:
		startup_loaded = level_loader.load_initial_level()
	startup_level_load_resolved.emit(
		startup_loaded,
		"" if startup_loaded else "初始关卡加载失败"
	)

func _process(_delta: float) -> void:
	_update_selected_rotation_repeat(_get_unscaled_input_delta(_delta))
	if runtime_hud != null and runtime_hud.is_modal_open():
		return
	_update_pick()


func _get_unscaled_input_delta(delta: float) -> float:
	if Engine.time_scale > 0.000001:
		return delta / Engine.time_scale
	return 0.0


func _update_selected_rotation_repeat(unscaled_delta: float) -> void:
	if not _selected_rotation_repeat.is_active():
		return
	if not Input.is_action_pressed("rotate_facing"):
		_selected_rotation_repeat.release()
		return
	if (
		runtime_hud == null
		or runtime_hud.is_modal_open()
		or runtime_stuff_editor == null
		or runtime_stuff_editor.is_active()
		or runtime_interaction == null
		or runtime_interaction.is_mirror_mode()
		or runtime_interaction.get_selected_definition() != null
		or mirror_manager == null
		or mirror_manager.get_selected_mirror() != null
		or building_manager == null
	):
		_selected_rotation_repeat.release()
		return
	var selected_building := building_manager.get_selected_building()
	if selected_building == null or not selected_building.can_rotate_in_place():
		_selected_rotation_repeat.release()
		return
	var repeat_count := _selected_rotation_repeat.advance(unscaled_delta)
	for _repeat_index in range(repeat_count):
		if not building_manager.rotate_selected():
			_selected_rotation_repeat.release()
			return
	return


## Modal cancellation remains press-based. Non-modal world cancellation is
## emitted by CameraController only when a right press/release stays a click.
func _input(event: InputEvent) -> void:
	if runtime_hud != null and runtime_hud.is_modal_open():
		if event.is_action_pressed("cancel_action") or event.is_action_pressed("ui_cancel"):
			runtime_hud.close_top_modal()
			get_viewport().set_input_as_handled()
		return

func _update_pick() -> void:
	var vp := get_viewport()
	var mp := vp.get_mouse_position()

	var edge := grid.pick_edge(_camera, mp)
	var cell := grid.pick_cell(_camera, mp)
	_debug_cell_pick = cell
	_debug_edge_pick = edge
	mirror_manager.set_inspected_cell(cell.cell if cell.hit else null)
	_update_building_preview(cell, edge)

	# 边优先高亮（靠近边时），否则高亮格。
	if edge.hit:
		renderer.highlight_edge(edge.cell, edge.edge_index, true)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)
	else:
		renderer.highlight_edge(Vector3i.ZERO, 0, false)
		renderer.highlight_cell(cell.cell if cell.hit else Vector3i.ZERO, cell.hit)



func _get_debug_pick_summary() -> String:
	var lines: Array[String] = []
	if bool(_debug_cell_pick.get("hit", false)):
		var cell: Vector3i = _debug_cell_pick.get("cell", Vector3i.ZERO)
		lines.append("格 %s | 高度 %.2f" % [str(cell), tile_manager.get_world_height(cell)])
	else:
		lines.append("格：未命中")
	if bool(_debug_edge_pick.get("hit", false)):
		lines.append("边 %s" % str(_debug_edge_pick.get("id", "")))
	else:
		lines.append("边：未命中")
	return "\n".join(lines)

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
				selected_building.get_laser_damage_per_second() if selected_building.definition.kind == BuildingDefinition.Kind.LASER_TOWER else selected_building.get_instant_damage(),
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
	if event.is_action_released("rotate_facing"):
		_selected_rotation_repeat.release()
	if runtime_hud != null and runtime_hud.is_modal_open():
		return
	if runtime_stuff_editor != null and runtime_stuff_editor.is_active():
		if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
			if event.keycode == KEY_Z:
				runtime_stuff_editor.undo()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_Y:
				runtime_stuff_editor.redo()
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("place_select"):
			_handle_primary_action()
		elif event.is_action_pressed("rotate_facing"):
			_selected_rotation_repeat.release()
			runtime_stuff_editor.rotate_current()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
			runtime_stuff_editor.remove_selected()
		return
	if event.is_action_pressed("place_select"):
		_handle_primary_action()
	elif event.is_action_pressed("rotate_facing"):
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		_selected_rotation_repeat.release()
		if runtime_interaction.is_mirror_mode():
			mirror_manager.flip_preview()
		elif mirror_manager.get_selected_mirror() != null:
			mirror_manager.flip_selected()
		elif runtime_interaction.get_selected_definition() != null:
			building_manager.rotate_preview()
		else:
			if building_manager.rotate_selected():
				_selected_rotation_repeat.press()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		mirror_manager.remove_selected_mirror()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		_destroy_selected_obstacle()

func _handle_primary_action() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var cell_pick: Dictionary = grid.pick_cell(_camera, mouse_position)
	var edge_pick: Dictionary = grid.pick_edge(_camera, mouse_position)
	if runtime_stuff_editor != null and runtime_stuff_editor.is_active():
		runtime_stuff_editor.handle_primary(cell_pick)
		return
	runtime_interaction.handle_primary(cell_pick, edge_pick)

func _update_building_preview(cell_pick: Dictionary, edge_pick: Dictionary) -> void:
	if runtime_stuff_editor != null and runtime_stuff_editor.is_active():
		building_manager.clear_preview()
		mirror_manager.clear_preview()
		runtime_stuff_editor.update_preview(
			cell_pick,
			get_viewport().gui_get_hovered_control() != null
		)
		return
	if runtime_stuff_editor != null:
		runtime_stuff_editor.clear_preview()
	if runtime_interaction.is_mirror_mode():
		building_manager.clear_preview()
		if get_viewport().gui_get_hovered_control() != null or not edge_pick.hit:
			mirror_manager.clear_preview()
			return
		if runtime_interaction.is_reflect_mirror_mode():
			mirror_manager.update_reflect_preview(edge_pick.cell, edge_pick.edge_index)
		else:
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
	if runtime_stuff_editor != null:
		runtime_stuff_editor.abort_for_level_transition()
	if path_hover_preview != null:
		path_hover_preview.clear_preview()
	renderer.refresh_surface()
	resource_manager.apply_level_configuration(level_resource)
	combat_manager.clear_targets()
	path_manager.load_level(level_resource)
	path_route_planner.load_level(level_resource)
	path_placement_connectivity_guard.load_level(level_resource)
	var initial_layout_errors := building_manager.load_initial_placements(
		level_resource.initial_building_placements
	)
	if initial_layout_errors.is_empty():
		initial_layout_errors.append_array(mirror_manager.load_initial_placements(
			level_resource.initial_mirror_placements
		))
	if not initial_layout_errors.is_empty():
		building_manager.clear_buildings(true)
		mirror_manager.clear_mirrors(true)
		push_error("初始建筑陈列装配失败：\n%s" % "\n".join(initial_layout_errors))
	base_core.load_level(level_resource)
	wave_manager.load_level(level_resource)
	camera_preset_controller.load_level(level_resource)
	if miniature_dof_controller != null:
		miniature_dof_controller.refresh_now(true)
	if lighting_controller != null:
		lighting_controller.apply_level(level_resource)
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


func prepare_for_level_transition() -> void:
	if runtime_hud != null:
		runtime_hud.prepare_for_level_transition()
	elif game_time_controller != null:
		game_time_controller.reset_runtime_state()
	if path_hover_preview != null:
		path_hover_preview.clear_preview()
	Engine.time_scale = 1.0


func _on_restart_level_requested() -> void:
	if level_loader.reload_current_level():
		prepare_for_level_transition()


func _on_exit_level_requested() -> void:
	prepare_for_level_transition()
	return_to_level_select_requested.emit()


func _on_camera_cancel_requested() -> void:
	if runtime_hud != null and runtime_hud.is_modal_open():
		return
	if runtime_stuff_editor != null and runtime_stuff_editor.is_active():
		runtime_stuff_editor.cancel_current_tool()
		get_viewport().set_input_as_handled()
		return
	runtime_interaction.cancel_to_select(true)
	get_viewport().set_input_as_handled()
	return


func _refresh_runtime_stuff_routes() -> void:
	if path_route_planner != null:
		path_route_planner.refresh_route_snapshot()


func _refresh_runtime_level_authoring() -> void:
	renderer.refresh_surface()
	stuff_manager.refresh_world_transforms()
	building_manager.refresh_world_transforms()
	if building_selection_visualizer != null:
		building_selection_visualizer.refresh()
	if mirror_manager != null:
		mirror_manager.refresh_world_transforms()
	if path_route_planner != null:
		path_route_planner.refresh_route_snapshot()
	if path_manager != null:
		path_manager.refresh_surface_positions()
	if base_core != null:
		base_core.refresh_world_transforms()


func _on_runtime_modal_state_changed(open: bool) -> void:
	cam_rig.set_input_enabled(not open)
	if not open:
		return
	building_manager.clear_preview(false)
	mirror_manager.clear_preview()
	renderer.highlight_cell(Vector3i.ZERO, false)
	renderer.highlight_edge(Vector3i.ZERO, 0, false)


func _on_wave_paths_preview_requested(paths: Array) -> void:
	if runtime_path_display != null:
		runtime_path_display.set_external_preview_active(true)
	if path_hover_preview != null:
		path_hover_preview.preview_paths(paths)


func _on_wave_paths_preview_cleared() -> void:
	if path_hover_preview != null:
		path_hover_preview.clear_preview()
	if runtime_path_display != null:
		runtime_path_display.set_external_preview_active(false)
