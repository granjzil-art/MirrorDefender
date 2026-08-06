# 关卡与存档 · Level

> 实现状态：已实现 LevelResource、编辑器/运行时原子加载、六机位、持久 AppFlow 与基础六槽分页选关。尚未实现关卡解锁、星级、通关进度、选关状态存档、局内读档或云存档。

## 职责

- 以 `LevelResource` 描述网格、地块、关卡元素、初始建筑/复制镜陈列、经济、据点、路径、波次、HUD 槽位、镜头预设和可选灯光方案，使新增正式关卡无需修改运行时代码。
- 以 `LevelLoader` 作为**唯一局内装配事务入口**，保证非法/失败加载不留下半装配状态。
- 以 `LevelSelectCatalog -> LevelSelectPageDefinition -> LevelResource` 显式维护正式上架目录、页面顺序和每页固定六槽顺序。
- 以持久 `AppFlowController` 管理“启动选关 -> 候选 Main 首载 -> 提交局内 -> 退出返回选关”的程序生命周期。
- 本系统当前只提供关卡选择与加载，不承担解锁、星级、通关进度或存档策略。

## 分类 / 做法

- **LevelResource**：统一保存关卡静态配置。`validate_runtime()` 只读校验网格、地块、初始建筑/镜子结构与占用、经济、据点、路径、出生点、波次、敌人、HUD 卡槽、镜头预设和可选 `lighting_profile`，不保存、不修复资源。
- **初始陈列**：`initial_building_placements` 保存真实建筑 Definition、格/边、逻辑朝向和等级；`initial_mirror_placements` 保存镜子种类（复制/投射物反射）、真实边与生效侧。Main 成功加载关卡后先恢复建筑、再按数组顺序恢复镜子；初始对象不扣资源但计入共享镜子 cap。
- **运行时原子加载**：`LevelLoader.load_level()` 在改动 Grid/Tile 前完成预检；TileManager 若意外拒绝，恢复旧 Grid，并保留旧 Tile/current level。成功后才广播 `level_loaded`，由 Main 重建其余 Manager。
- **正式目录**：`LevelSelectCatalog.pages` 是页面作者顺序；每项是 `LevelSelectPageDefinition`。目录校验只报告空页、重复页、跨页重复关卡和页面错误，不改写数组。
- **固定六槽页面**：`LevelSelectPageDefinition.SLOT_COUNT = 6`。`levels[0..5]` 是槽位作者顺序；null 是合法空槽，必须保留位置，不压缩、不自动填充。超过六项是配置错误。
- **页面显示顺序**：`LevelSelectView` 创建六个 `LevelSelectSlot` 并加入三列 `GridContainer`，因此视觉顺序固定为槽 1～3 第一行、槽 4～6 第二行。翻页只按 Catalog 数组相邻移动，不排序。
- **合法槽位**：`LevelSelectSlot` 对非空 LevelResource 调用 `validate_runtime()`；空槽或非法关卡保持可见但禁用，合法点击只发送原 `LevelResource`，不直接装配世界。
- **程序化缩略图**：`LevelThumbnail` 只读 LevelResource，以对应 HEX/SQUARE `IGridShape` 计算单元多边形，并绘制地形、路径、出生点与据点标记。它不实例化 GridManager、TileManager、PathManager、WaveManager 或任何玩法节点，不补齐稀疏地块，不写回兼容缓存/资源。
- **持久 AppFlow**：`project.godot` 启动 `AppRoot.tscn`。`AppFlowController` 自身不随单局销毁，`Content` 中任一时刻只提交一个选关页或一个活动 Main。
- **选关加载事务**：选中合法关卡后，AppFlow 先实例化隐藏且禁用处理的候选 Main，在入树前调用 `configure_startup_level(level)`；Main 入树后仍由 `LevelLoader.load_level()` 装配。只有 `startup_level_load_resolved(true, ...)` 才释放选关页并启用 Main；失败释放候选 Main并保留当前选关页。
- **直接 Main 兼容**：独立运行 `Main.tscn` 时若未注入启动关卡，仍调用 `LevelLoader.load_initial_level()`，便于编辑器和历史测试直接启动。
- **局内重启**：右侧按钮或暂停菜单只发高层请求；Main 调用 `LevelLoader.reload_current_level()`。资源路径关卡重新深加载 `.tres`，内存关卡深复制后再走同一加载事务。
- **退出当前关卡**：右侧叉号和暂停菜单退出按钮语义一致。Main 先 `prepare_for_level_transition()` 清理模态、时间倍率和路径预览，再发 `return_to_level_select_requested()`；AppFlow 延迟释放 Main，恢复 `Engine.time_scale = 1.0` 并创建新的选关页。不会调用 SceneTree 退出。
- **调试入口**：Main 内 `LevelDebugPanel` 与 F1 `load` 继续复用 LevelLoader，但不修改正式 Catalog，也不代表正式解锁/选关流程。
- **当前上架范围**：默认 `LevelSelectCatalog.tres` 只有一页；`LevelSelectPage01.tres` 第一槽显式引用 `M4DemoLevel.tres`，其余五槽为空。Demo/Test/测试夹具不会因位于 `resources/levels` 或 `tests` 而自动上架。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| LevelResource.`display_name` | `""` | 关卡名；空值回退资源文件名。 |
| LevelResource.`grid_shape` | 0 | 0=HEX，1=SQUARE，与 `GridManager.Shape` 顺序一致。 |
| LevelResource.`grid_cell_size` | 1.0 | 单格世界尺寸。 |
| LevelResource.`grid_size` | `(6,6)` | HEX 取 x 为半径；SQUARE 取列/行。 |
| LevelResource.`height_levels/height_step` | `3 / 0.45` | 离散高度档数与世界高度步长。 |
| LevelResource.`tiles` | `[]` | 按每项 `cell` 唯一的序列化地块数组。 |
| LevelResource.`initial_resource` | 200 | 切入关卡时主资源。 |
| LevelResource.`building_cap/mirror_cap` | `20 / 6` | 实体建筑与实体镜子上限。 |
| LevelResource.`initial_building_placements` | `[]` | 开局真实建筑的 Definition、格/边、逻辑朝向和等级。 |
| LevelResource.`initial_mirror_placements` | `[]` | 开局实体镜子的 `mirror_kind`、边与生效侧；数组顺序同时保持复制镜链装配顺序。 |
| LevelResource.`base_resource_per_second` | 0.5 | 关卡基础每秒资源。 |
| LevelResource.`building_card_slot_count` | 6 | 正式 HUD 建筑携带槽，范围 1～12；复制镜独立。 |
| LevelResource.`base_points/base_max_hp` | `[] / 100` | 多个据点位置共享一份生命。 |
| LevelResource.`base_cell` | `(0,0,0)` | 旧关卡兼容据点；`base_points` 空时只读映射为据点 1。 |
| LevelResource.`paths/spawn_points/waves` | `[]` | 本关路径、独立出生点和作者顺序波次。 |
| LevelResource.`camera_presets` | `[]` | 最多六个可空机位；索引 0～5 对应数字键 1～6。 |
| LevelResource.`lighting_profile` | `null` | 可选关卡灯光方案；空值使用 Main 注入的默认白色柔光。 |
| LevelSelectPageDefinition.`SLOT_COUNT` | 6 | 每页固定六槽，非可调分页大小。 |
| LevelSelectPageDefinition.`display_name` | `""` | 页面标题；空值回退“第 N 页”。 |
| LevelSelectPageDefinition.`levels` | `[]` | 作者槽位顺序；null 表示可见空槽。 |
| LevelSelectCatalog.`pages` | `[]` | 作者页面顺序；至少一页。 |
| LevelSelectSlot.`SLOT_SIZE` | `(300,210)` | 单个关卡槽基准尺寸。 |
| LevelLoader.`feature_enabled` | true | 运行时关卡装配总开关。 |
| LevelLoader.`initial_level` | M4DemoLevel | 直接启动 Main 时的兼容初始关卡。 |
| AppFlowController.`level_select_catalog` | LevelSelectCatalog.tres | 正式上架目录。 |
| AppFlowController.`level_select_scene/main_scene` | 对应 PackedScene | 选关与单局候选场景。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 全部关卡静态配置与只读运行时校验。 |
| `scripts/level/InitialLayoutValidator.gd` | `InitialLayoutValidator` / `RefCounted` | 初始建筑/镜子的 Definition、边界、方向、权限、cap、同格和同边冲突只读校验。 |
| `scripts/building/BuildingPlacementData.gd` | `BuildingPlacementData` / `Resource` | 单个初始真实建筑快照。 |
| `scripts/mirror/MirrorPlacementData.gd` | `MirrorPlacementData` / `Resource` | 单个初始实体镜子的种类、边与生效侧快照；旧资源默认复制镜。 |
| `scripts/level/LevelLoader.gd` | `LevelLoader` / `Node` | **唯一局内装配入口**；预检、Grid/Tile 原子安装、重载和结果信号。 |
| `scripts/level/LevelSelectCatalog.gd` | `LevelSelectCatalog` / `Resource` | 正式页面作者顺序与跨页只读校验。 |
| `scripts/level/LevelSelectPageDefinition.gd` | `LevelSelectPageDefinition` / `Resource` | 一页固定六槽、页面名和页内只读校验。 |
| `scripts/AppFlowController.gd` | `AppFlowController` / `Node` | 持久程序流；管理选关、候选 Main 提交/回滚和退关。 |
| `scripts/ui/LevelSelectView.gd` | `LevelSelectView` / `Control` | 固定 2×3 槽位、分页导航和 `level_selected` 信号。 |
| `scripts/ui/LevelSelectSlot.gd` | `LevelSelectSlot` / `Button` | 单槽合法性、标题、缩略图和禁用状态。 |
| `scripts/ui/LevelThumbnail.gd` | `LevelThumbnail` / `Control` | LevelResource 的只读程序化 2D 预览。 |
| `scripts/Main.gd` | `MainController` / `Node3D` | 接收启动关卡、装配 LevelLoader、广播首载结果和退关请求。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | Main 内开发快捷加载；不属于正式选关。 |
| `scripts/camera/CameraPresetDefinition.gd` | `CameraPresetDefinition` / `Resource` | 一个可空镜头槽的焦点、yaw、pitch 和距离。 |
| `scripts/shared/ConfigurationValidator.gd` | `ConfigurationValidator` / `RefCounted` | 跨资源无副作用的数值/范围/嵌套校验。 |
| `scenes/AppRoot.tscn` | 无 class_name / `Node` 场景 | 程序主场景；持久 AppFlow 与 Content 容器。 |
| `scenes/ui/LevelSelectView.tscn` | 无 class_name / `Control` 场景 | 全屏选关、三列 Grid、页名/页码与左右按钮。 |
| `scenes/Main.tscn` | 无 class_name / `Node3D` 场景 | 单局运行时；包含 LevelLoader 与 RuntimeHud。 |
| `resources/level_select/LevelSelectCatalog.tres` | `LevelSelectCatalog` / `Resource` | 默认正式目录。 |
| `resources/level_select/LevelSelectPage01.tres` | `LevelSelectPageDefinition` / `Resource` | 默认第一页：M4DemoLevel + 五个空槽。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` / `Resource` | 当前默认目录唯一上架正式关卡。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | 无 class_name / `Control` | 地块、路径、波次、镜头四页编辑和保存。 |
| `addons/mirror_tile_editor/camera_preset_editor.gd` | `CameraPresetEditor` / `VBoxContainer` | 六镜头槽写入、预览和清空。 |
| `tests/level_select_test.gd` | 无 class_name / `SceneTree` | Catalog/Page 校验、页面/槽位顺序、空槽、翻页、信号与只读缩略图回归。 |
| `tests/manual_wave_and_level_flow_test.gd` | 无 class_name / `SceneTree` | AppFlow 启动、首载提交/失败保留、退关、1x 恢复与直接 Main 兼容回归。 |
| `tests/manual_wave_release_test.gd` | 无 class_name / `SceneTree` | 选中关卡后的逐波状态与加载依赖回归。 |
| `tests/initial_layout_persistence_test.gd` | 无 class_name / `SceneTree` | 全量保存、普通保存隔离、建筑/镜子字段往返、免付费重载和 cap 计数回归。 |
| `tests/run_all_tests.ps1` | 无 class_name / PowerShell 脚本 | 全量入口已登记上述三个新增套件。 |

### 模块调用关系 / 数据流

```text
project.godot run/main_scene
  -> AppRoot.tscn / AppFlowController (persistent)
  -> validate LevelSelectCatalog (read-only)
  -> LevelSelectView.configure(catalog)
	 -> Catalog.pages[page_index]
	 -> Page.levels[slot_index 0..5]
	 -> LevelSelectSlot.set_level(level or null)
	 -> LevelThumbnail.set_level(level) read-only draw

filled valid slot click
  -> LevelSelectView.level_selected(level)
  -> AppFlowController._on_level_selected(level)
  -> level.validate_runtime()
  -> instantiate candidate Main
  -> Main.configure_startup_level(level)
  -> add hidden/process-disabled candidate to Content
  -> Main._ready()
	 -> LevelLoader.configure(GridManager, TileManager)
	 -> LevelLoader.load_level(selected level)
		-> LevelResource.validate_runtime() read-only
		-> GridManager.apply_configuration(...)
		-> TileManager.load_level(level)
		-> failure: restore previous Grid, preserve current level
		-> success: LevelLoader.level_loaded(level, source_path)
		   -> Main rebuilds Resource/Combat/Path systems
		   -> BuildingManager.load_initial_placements (免付费、计入 cap)
		   -> MirrorManager.load_initial_placements (按数组顺序、免付费、计入 cap)
		   -> Main rebuilds Base/Wave/HUD/Camera systems
	 -> Main.startup_level_load_resolved(success, reason)
  -> AppFlowController deferred commit
	 -> success: free LevelSelectView, enable/show Main
	 -> failure: free candidate Main, keep current LevelSelectView

right WaveControlPanel restart / PauseMenu restart
  -> RuntimeHud.restart_level_requested
  -> Main._on_restart_level_requested()
  -> LevelLoader.reload_current_level()
  -> same full level_loaded rebuild transaction

right WaveControlPanel exit / PauseMenu exit
  -> RuntimeHud.exit_level_requested
  -> Main.prepare_for_level_transition()
	 -> RuntimeHud.prepare_for_level_transition()
	 -> close console/pause, clear wave/path preview
	 -> GameTimeController.reset_runtime_state()
	 -> Engine.time_scale = 1.0
  -> Main.return_to_level_select_requested()
  -> AppFlowController.return_to_level_select()
  -> deferred free Main
  -> create/configure fresh LevelSelectView
  -> SceneTree and AppFlow remain alive

F1 load / LevelDebugPanel
  -> LevelLoader.load_level_path(path)
  -> same validation and installation transaction
  -> does not modify Catalog or unlock state

RuntimeStuffEditorPanel 全量保存
  -> RuntimeStuffEditSession.save("", true)
  -> StuffManager.export_placements()
  -> BuildingManager.export_initial_placements()
  -> MirrorManager.export_initial_placements()
  -> LevelResource duplicate + validate_runtime()
  -> ResourceSaver.save(res:// editor or user:// exported runtime)
```

## 函数索引

### LevelResource / LevelLoader

| 函数 | 签名 | 职责 |
|---|---|---|
| `LevelResource.get_tile` | `(cell: Vector3i) -> Variant` | 返回序列化 TileCellData 或 null；调用方须收窄类型。 |
| `LevelResource.store_tile` | `(tile: Resource) -> void` | 按 `tile.cell` 覆盖/插入序列化布局。 |
| `LevelResource.get_height_color` | `(height_level: int) -> Color` | 返回编辑器/运行时共享高度色。 |
| `LevelResource.get_camera_preset` | `(slot_index: int) -> CameraPresetDefinition` | 读取 0～5 槽；越界/未配置返回 null。 |
| `LevelResource.set_camera_preset` | `(slot_index: int, preset: CameraPresetDefinition) -> bool` | 设置单槽且只增长到目标索引。 |
| `LevelResource.clear_camera_preset` | `(slot_index: int) -> bool` | 清空已有槽；不物化其它空槽。 |
| `LevelResource.get_path_by_id` | `(path_id: StringName) -> PathDefinition` | 按稳定 ID 返回本关路径。 |
| `LevelResource.get_spawn_point` | `(spawn_id: StringName) -> SpawnPointDefinition` | 按稳定 ID 返回本关出生点。 |
| `LevelResource.validate_runtime` | `() -> Array[String]` | 只读返回完整运行时配置错误；空数组表示可装配。 |
| `InitialLayoutValidator.validate` | `(level: Resource, shape: IGridShape) -> Array[String]` | 校验初始建筑/镜子的配置、边界、方向、权限、cap 以及同格/同边占用。 |
| `LevelLoader.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入原子装配依赖。 |
| `LevelLoader.load_initial_level` | `() -> bool` | 直接 Main 兼容入口，加载 Inspector 初始关卡。 |
| `LevelLoader.load_level` | `(level_resource: LevelResource, source_path: String = "") -> bool` | 预检并原子安装 Grid/Tile，成功后广播。 |
| `LevelLoader.load_level_path` | `(path: String) -> bool` | 仅从 `res://*.tres` 深加载 LevelResource 后转入 `load_level()`。 |
| `LevelLoader.get_current_level` | `() -> LevelResource` | 返回最后成功装配的关卡。 |
| `LevelLoader.get_current_source_path` | `() -> String` | 返回最后成功来源路径。 |
| `LevelLoader.reload_current_level` | `() -> bool` | 资源路径重新加载；内存关卡深复制后走完整事务。 |

### Catalog / Page / View / Thumbnail

| 函数 | 签名 | 职责 |
|---|---|---|
| `LevelSelectCatalog.get_page_count` | `() -> int` | 返回作者页面数。 |
| `LevelSelectCatalog.get_page` | `(page_index: int) -> LevelSelectPageDefinition` | 按零基作者顺序取页；越界返回 null。 |
| `LevelSelectCatalog.validate_configuration` | `() -> Array[String]` | 只读校验空页、重复页、跨页重复关卡与嵌套错误。 |
| `LevelSelectPageDefinition.get_level` | `(slot_index: int) -> LevelResource` | 按 0～5 槽取关卡；越界/未配置/null 返回 null。 |
| `LevelSelectPageDefinition.get_levels_for_slots` | `() -> Array[LevelResource]` | 返回恰好六项、保留 null 位置的槽位快照。 |
| `LevelSelectPageDefinition.validate_configuration` | `() -> Array[String]` | 只读校验最多六槽、页内重复和关卡合法性。 |
| `LevelSelectView.configure` | `(catalog: LevelSelectCatalog) -> void` | 注入目录并回到第一页。 |
| `LevelSelectView.get_current_page_index` | `() -> int` | 返回当前零基页面索引。 |
| `LevelSelectView.get_page_count` | `() -> int` | 返回当前目录页面数。 |
| `LevelSelectView.get_slot_count` | `() -> int` | 返回实际创建槽数，现役固定为 6。 |
| `LevelSelectView.get_slot_level` | `(slot_index: int) -> LevelResource` | 返回当前页槽位关卡；空/越界为 null。 |
| `LevelSelectSlot.set_level` | `(value: LevelResource) -> void` | 只读校验并刷新禁用、标题和缩略图。 |
| `LevelSelectSlot.clear` | `() -> void` | 清除当前槽显示状态。 |
| `LevelSelectSlot.get_level` | `() -> LevelResource` | 返回当前槽原资源。 |
| `LevelSelectSlot.get_thumbnail` | `() -> LevelThumbnail` | 返回内嵌缩略图控件。 |
| `LevelThumbnail.set_level` | `(value: LevelResource) -> void` | 只读重建绘制缓存。 |
| `LevelThumbnail.clear` | `() -> void` | 清理预览缓存，不改关卡资源。 |
| `LevelThumbnail.debug_get_draw_data` | `() -> Array[Dictionary]` | 返回单元缓存深副本；键含 `cell/polygon_world/color/height_level/is_explicit/is_path`。 |
| `LevelThumbnail.debug_get_path_draw_data` | `() -> Array[PackedVector2Array]` | 返回路径点数组副本。 |
| `LevelThumbnail.debug_get_spawn_draw_data` / `debug_get_base_draw_data` | `() -> Array[Dictionary]` | 返回 `{position: Vector2, number: int}` 标记副本。 |

### AppFlow / Main

| 函数 | 签名 | 职责 |
|---|---|---|
| `AppFlowController.get_active_level_select` | `() -> Control` | 返回当前选关页或 null。 |
| `AppFlowController.get_active_main` | `() -> Node` | 返回已提交 Main 或 null。 |
| `AppFlowController.get_active_content_count` | `() -> int` | 返回 Content 子节点数，稳定态应为 1。 |
| `AppFlowController.return_to_level_select` | `() -> void` | 幂等发起延迟退关。 |
| `AppFlowController._on_level_selected` | `(level: LevelResource) -> void` | 校验选择并开始候选 Main 事务。 |
| `AppFlowController._start_level` | `(level: LevelResource) -> void` | 实例化、注入、连接并挂入隐藏候选 Main。 |
| `AppFlowController._on_startup_level_load_resolved` | `(success: bool, reason: String) -> void` | 记录首载结果并延迟提交。 |
| `AppFlowController._commit_start_level` | `() -> void` | 成功切换到 Main；失败保留选关。 |
| `MainController.configure_startup_level` | `(level: LevelResource) -> bool` | 仅入树前接受 AppFlow 选择的启动关卡。 |
| `MainController.prepare_for_level_transition` | `() -> void` | 清理局内 UI/时间/路径状态并恢复 1x。 |

## 信号索引

| 信号 | 签名 | 语义 |
|---|---|---|
| `LevelLoader.level_loaded` | `(level_resource: LevelResource, source_path: String)` | Grid/Tile 成功提交后的唯一加载成功事件。 |
| `LevelLoader.level_load_failed` | `(source_path: String, reason: String)` | 失败原因；当前成功关卡保持不变。 |
| `LevelSelectView.level_selected` | `(level: LevelResource)` | 合法已填槽被点击；尚未装配。 |
| `MainController.startup_level_load_resolved` | `(success: bool, reason: String)` | AppFlow 候选 Main 首载完成。 |
| `MainController.return_to_level_select_requested` | `()` | 请求退关并返回选关；不退出程序。 |

## 约定事实源

- LevelLoader 是局内关卡装配唯一事实源；AppFlow 选择、F1 load、LevelDebugPanel、重启都必须最终经过它。
- `LevelSelectCatalog.pages` 的数组索引是页面顺序；`LevelSelectPageDefinition.levels` 的 0～5 索引是槽位顺序。任何 null 都保留，不压缩、不排序。
- 目录是显式白名单，不扫描 `resources/levels`。测试关卡、DemoLevel1/2 或测试夹具不会自动上架；当前只显式上架 M4DemoLevel。
- 程序启动场景是 AppRoot，不是 Main。AppFlow 跨单局持久；选关页和 Main 都是可替换 Content 子节点。
- 选关到局内是两阶段事务：候选 Main 先完成 LevelLoader 首载，成功才释放旧选关页；失败不得留下半活动 Main。
- 重启不离开 Main；退出当前关卡必须释放 Main 并重建选关。退出不终止 SceneTree。
- 退关前必须恢复 `Engine.time_scale = 1.0`，关闭暂停/控制台并清理波次路径预览；AppFlow 再次确保 1x。
- LevelThumbnail 只读 LevelResource。稀疏格仅在绘制缓存中以默认地形表达，资源数组、兼容据点缓存、路径和端点都不被修改。
- `tiles` 空间唯一键是 TileCellData.`cell`，数组顺序不代表空间顺序；TileManager 加载时克隆运行时对象，occupant/清障/运行时高度不写回资源。
- `camera_presets` 索引 0～5 是镜头槽事实源；空数组/空元素均表示未配置，校验不填默认值。
- `lighting_profile` 仅指定关卡首次加载的表现方案；空值是合法兼容状态，不在关卡资源中复制默认方案。
- `paths/spawn_points/base_points/waves` 必须属于同一 LevelResource；路径方向恒为出生点到目标据点。
- 波次在资源中仍按作者数组组织；现役运行时每波手动释放，`start_delay` 只按本波最小值归一，详见 Wave 文档。
- 当前“持久化”仅包括 `RuntimeSettings` 的用户设置；没有关卡进度持久化。
- 运行时作者“全量保存”是关卡配置导出，不是玩家进度存档：它写入当前 `grid_cells / ramp_placements / stuff_placements / initial_building_placements / initial_mirror_placements`。波次、路径、镜头、经济、敌人、耐久、冷却和虚像仍不从运行时状态反写。
- 运行时 Terrain/Ramp 候选在 `LevelResource` 深副本上通过 `validate_runtime()` 后才允许预览/提交；保存旧关卡时会物化规范内容版本并清空旧 `tiles` 双重事实源。

## 已知限制 / 初版不做的部分

- 基础分页选关已实现，但没有 SaveManager、关卡解锁、星级、通关进度、关卡完成记录或选关状态恢复。
- 不做局内保存/读取、多存档槽、云存档和外部关卡包导入。
- 退出当前关卡固定返回第一页；当前不保存上次页面索引或焦点槽位。
- 程序化缩略图不显示运行时建筑、敌人、镜像、动态效果或相机截图。
- 默认目录只含一个正式关卡；增加页面/关卡必须显式编辑 Catalog/Page 资源并通过只读校验。
- 本轮新增测试已登记，本次文档同步按要求未运行测试。
