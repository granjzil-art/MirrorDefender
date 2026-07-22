# 界面系统 · UI

## 职责
提供 HUD 与操作入口，承载卡槽、资源、检视、波次、全局状态和时间控制。M6 的整体布局、批次边界与验收事实源为 `Docs/07_M6_操作与UI大版本_需求与开发计划.md`。

## 分类 / 做法
- **M6 批次 1 正式 HUD（已实现）**：底部为独立复制镜卡加单行建筑卡；建筑卡数由关卡配置，默认 6。默认携带箭塔、激光塔、屏障，未使用位置显示空镜面；边障保留玩法但不进入默认卡组。整排不绘制也不拦截外层大卡槽，仅单张复制镜卡、建筑卡与空卡自身保留镜框，卡片之间的空白区域不属于 UI。
- **卡片状态**：卡片显示名称、可替换图标和 1 级建造费用；资源不足或达到对应上限时置灰且不可新选，选中卡使用金色镜框。`BuildingDefinition.card_icon` 与 `CopyMirrorDefinition.card_icon` 为空时使用稳定文字灰盒。
- **单次放置**：`RuntimeInteractionController` 是正式交互事实源。每次选卡只允许一次世界点击；成功、资源不足、上限、非法地块、非法边或未命中都会取消卡片/预览/实体选择并回 `SELECT`，成功放置的实体不会保持自动选中。
- **取消和输入消费**：左键执行肯定操作；右键在 GUI 分发前全局取消并回选择模式。正式卡片和按钮消费左键，点击 UI 不会穿透到世界。
- **战术慢放**：选卡或选中实体建筑、实体边建筑、实体镜子时，`GameTimeController` 默认切到 0.1x。右下按钮可关闭自动慢放；优先级固定为 `暂停 0x > 战术慢放 0.1x > 快速 2x > 正常 1x`。批次 1 已交付时间控制基础和慢放按钮，正式 2x/暂停菜单在批次 3 接入。
- **M6 批次 2 地块详情（已实现）**：选择模式点击含实体块建筑、任一相邻边建筑/复制镜、同格虚像或关卡元素的格时，右侧展开镜面详情板；空格、取消、选卡或放置完成时收起。条目可滚动，显示类型、实体/虚像、图标灰盒、等级、耐久、朝向、根源格、产生镜子及元素运行时状态。
- **两级显示配置（已实现）**：`InspectionDisplayConfig.visible` 是对象级开关；关闭后实体和由它产生的虚像都不进入列表。其余 `show_*` 是字段级开关，分别控制图标、类型、实体/虚像、功能、位置、高度、权限、等级、耐久、朝向、战斗、经济、容量、时序、对空及虚像谱系行。全部默认 `true`，保持已有显示。
- **名称与功能说明**：建筑、复制镜和地块定义各自持有 `inspection_display`；可编辑 `display_name` 和 `function_description`。空值向后兼容原显示名和内置说明，面板统一增加“功能：”行；虚像使用根源对象配置。
- **只读检视模型**：`TileInspectionService` 订阅交互选择和 Manager 状态信号，`TileInspectionModelBuilder` 仅通过公共查询生成稳定 Dictionary；`TileInspectorPanel` 不持有玩法 Manager，也不提供修改回调。虚像/单纯元素检视不触发慢放，实体建筑/镜子的慢放与世界悬浮操作保持原逻辑。
- **沿用原型布局**：
  - 顶部：资源栏
  - 底部：卡片式建造栏
  - 右侧：检视 / 升级面板
  - 左侧：机制图例
  - 小地图
  - 操作提示
- **重要改动**：顶部原"双方据点血条"改为 **【我方据点血量条 | 本波剩余敌人 x/y】**。
- 面板与逻辑解耦，通过信号/数据绑定更新（资源变化、波次进度、选中对象）。
- **当前调试 UI**：主场景右上角 LevelDebugPanel 显示当前关卡，并可从 `res://resources/levels` 选择 `.tres`；正式选关将复用 LevelLoader，不复用该调试面板外观。
- **旧建筑/镜子灰盒 UI**：M3DebugPanel 仍保留开发期实现供后续控制台迁移参考，但主场景默认 `feature_enabled=false`，不再参与正式交互状态。
- **放置反馈**：选择塔种后，可建造空格显示 1 级半透明塔虚影和朝向；无塔种或不可放置格不显示虚影，左侧 HUD 改为显示地块类型、高度、障碍、占位对象或占位建筑参数。
- **选中建筑操作**：选择模式点击有建筑地块后，`BuildingActionPanel` 在该建筑上方显示删除、升级、旋转；空格无效果。满级仅升级按钮置灰，删除显示当前等级配置的退款行为，旋转免费。
- **屏障反馈**：屏障模式只在合法路径格显示墙体虚影；左侧 HUD 和选择状态显示当前/最大耐久、脱战延迟、回血速度与反伤比例，屏障上方同时显示耐久数字。
- **边屏障反馈**：“边障”模式在任意两个有效地块之间显示贴边虚影，不要求已有路径；默认双向时 HUD 显示 `cell ↔ edge_to_cell`。放置后删除/升级可用，旋转因边对齐锁定而置灰。
- **复制镜反馈**：“复制镜”模式显示镜面生效侧、最近源格、对称目标格、整格内容名称与青蓝虚像；无源只警告仍可放置。`R` 翻面立即重算。选中后 `MirrorActionPanel` 悬浮提供删除/翻面，实体镜与建筑选择互斥。
- **M4 波次 UI**：右上 `WaveStatusPanel` 显示据点生命、当前/总波数、存活敌人数与波次状态；仅在 READY 状态允许点击一次“开始第一波”，后续波次按全局组延迟自动开始。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| 布局锚点 | 预设 | 各面板锚点（顶/底/左/右/小地图） |
| 缩放适配 | expand | UI 缩放模式（适配不同分辨率） |
| minimap_enabled | true | 小地图开关 |
| hint_enabled | true | 操作提示开关 |
| LevelDebugPanel.`feature_enabled` | true | 运行时调试选关面板开关。 |
| LevelDebugPanel.`initial_directory` | `res://resources/levels` | 关卡选择器起始目录。 |
| M3DebugPanel.`feature_enabled` | 脚本 true / Main false | M3 灰盒建造/靶标面板开关；正式主场景已覆盖为隐藏。 |
| WaveStatusPanel.`feature_enabled` | true | M4 波次状态与手动开波面板开关。 |
| LevelResource.`building_card_slot_count` | 6 | 正式建筑携带槽数，范围 1～12；复制镜独立槽不计入。 |
| BuildCardBar.`card_size` | `(96,126)` | 单张卡片的基准尺寸。 |
| BuildCardBar.`card_separation` | 6 | 建筑卡之间的像素间距。 |
| BuildCardBar.`mirror_slot_separation` | 14 | 独立镜子槽与建筑槽组之间的间距。 |
| TileInspectorPanel.`feature_enabled` | true | 批次 2 右侧详情板总开关。 |
| TileInspectorPanel.`preview_size` | 82 | 每条内容的图标/灰盒预览边长。 |
| TileInspectorPanel.`entry_minimum_height` / `compact_entry_minimum_height` / `entry_separation` | 112 / 54 / 8 | 有图标条目、隐藏图标后的紧凑条目最小高度及间距；超出面板高度后滚动。 |
| TileInspectorPanel.`fallback_icon` | null | 全局条目占位图；为空时用内容名称前两字灰盒。 |
| Definition.`inspection_display` | 独立资源 | 建筑、复制镜、地块定义的对象级开关、可编辑名称/功能说明和字段级开关。 |
| GameTimeController.`tactical_slow_enabled` | true | 是否在选卡/选中实体时自动慢放。 |
| GameTimeController.`tactical_slow_scale` | 0.1 | 战术慢放倍率。 |
| GameTimeController.`fast_scale` | 2.0 | 批次 3 正式按钮使用的快速倍率。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/Main.gd` | `Node3D` | 更新世界拾取并装配运行时 Manager、正式 HUD、悬浮操作和调试兼容面板。 |
| `scripts/ui/RuntimeInteractionController.gd` | `RuntimeInteractionController` / `Node` | 正式 SELECT/块放置/边放置/镜子放置状态机和单次尝试事务。 |
| `scripts/ui/GameTimeController.gd` | `GameTimeController` / `Node` | 统一求解暂停、战术慢放、2x 与 1x 的时间优先级。 |
| `scripts/ui/BuildCardBar.gd` | `BuildCardBar` / `Control` | 独立镜子槽、可调建筑槽、卡片可用性、选中框、空镜面和状态反馈。 |
| `scripts/shared/InspectionDisplayConfig.gd` | `InspectionDisplayConfig` / `Resource` | 跨建筑、镜子、地块共享的两级只读检视显示策略。 |
| `scripts/ui/TileInspectionService.gd` | `TileInspectionService` / `Node` | 保存检视选择、订阅动态状态并调度只读模型刷新。 |
| `scripts/ui/TileInspectionModelBuilder.gd` | `TileInspectionModelBuilder` / `RefCounted` | 将地块、建筑、边实体、镜子、虚像和元素状态聚合为稳定只读模型。 |
| `scripts/ui/TileInspectorPanel.gd` | `TileInspectorPanel` / `Control` | 把检视模型渲染为右侧镜面滚动条目，不执行玩法修改。 |
| `scenes/ui/TileInspectorPanel.tscn` | `Control` 场景 | 右侧中部响应式详情板场景和美术资源接口。 |
| `scripts/ui/RuntimeHud.gd` | `RuntimeHud` / `Control` | M6 正式 HUD 组合根；连接卡片、慢放、检视服务和详情板。 |
| `scenes/ui/RuntimeHud.tscn` | `Control` 场景 | 可复用正式 HUD 场景；批次 1-2 含底部卡片、慢放按钮和右侧详情。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 运行时调试关卡状态与资源选择按钮。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 箭塔/激光塔/屏障模式、升级、预览状态、经济/上限/靶标摘要和错误反馈。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 根据相机投影跟随选中建筑，提供删除、升级、旋转三项上下文操作。 |
| `scripts/ui/MirrorActionPanel.gd` | `MirrorActionPanel` / `Control` | 跟随选中复制镜，提供删除和生效侧翻面。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 显示据点/波次/敌人摘要，并请求 WaveManager 开始全局波次时间轴。 |
| `tests/runtime_ui_batch2_test.gd` | 无 / `SceneTree` | 48 项只读模型、动态刷新、选择语义、滚动和三档分辨率回归。 |
| `tests/runtime_inspection_configuration_test.gd` | 无 / `SceneTree` | 90 项默认兼容、正式资源、对象/字段过滤、名称/功能说明和自适应排版回归。 |
| `scenes/Main.tscn` | `Node3D` 场景 | HUD 左侧拾取信息、底部提示、右上选关及 M3 灰盒面板。 |

### 调用关系

```
HUD (CanvasLayer)
 ├─ TopBar: 资源栏 + [我方据点血量条 | 本波剩余敌人 x/y]
 ├─ BuildBar(底部): 建筑/镜子卡片
 ├─ InspectPanel(右): 选中对象检视/升级
 ├─ LegendPanel(左): 机制图例
 ├─ Minimap
 └─ HintPanel: 操作提示
数据绑定: ResourceManager / WaveManager / 选中对象 → 信号更新 UI

LevelDebugPanel -> LevelLoader.load_level_path(path)
LevelLoader.level_loaded / level_load_failed -> LevelDebugPanel status

BuildCardBar card signal -> RuntimeInteractionController mode
Main cell/edge input -> RuntimeInteractionController.handle_primary
  -> BuildingManager / MirrorManager placement transaction
  -> success or failure -> clear preview/selection -> SELECT
RuntimeInteractionController mode + BuildingManager/MirrorManager selection
  -> GameTimeController -> Engine.time_scale
RuntimeInteractionController.world_selection_changed
  -> RuntimeHud -> TileInspectionService selected cell
  -> source Definition.inspection_display
     -> visible 过滤整个对象 / show_* 过滤字段
  -> TileInspectionModelBuilder public Manager queries
  -> `{has_content, cell, terrain_name, height_level, permissions, entries}`；entry 含名称、功能、布局开关和可见详情行
  -> TileInspectorPanel dynamic cards / collapsed empty state
Tile/Building/Mirror/TileEffect signals + selected source live signals
  -> TileInspectionService deferred coalesced refresh
ResourceManager resource_changed / limits_changed -> BuildCardBar availability
LevelResource.building_card_slot_count -> RuntimeHud -> BuildCardBar slot count

Legacy M3DebugPanel（主场景默认隐藏）
  -> 仅保留开发期摘要与后续 F1 控制台迁移参考
Main mouse hover -> BuildingManager.update_preview -> ghost or Tile/occupant HUD
ResourceManager.resource_changed / limits_changed / income_rates_changed -> M3DebugPanel summary
BuildingManager.placement_failed / building_selected / building_upgraded / preview_updated -> M3DebugPanel status
M3DebugPanel upgrade button -> BuildingManager.upgrade_selected
BuildingActionPanel buttons -> BuildingManager.remove_selected_building / upgrade_selected / rotate_selected
M3DebugPanel copy-mirror mode -> MirrorManager.update_preview / place_copy_mirror
MirrorActionPanel buttons -> MirrorManager.remove_selected_mirror / flip_selected
WaveManager.state_changed / wave_started / wave_completed -> WaveStatusPanel refresh
BaseCore.health_changed -> WaveStatusPanel refresh
WaveStatusPanel "开始第一波" -> WaveManager.start_battle -> later waves auto-start by SpawnGroup.start_delay
```

## 函数索引

| 文件 | 函数签名 | 职责 |
|---|---|---|
| `LevelDebugPanel.gd` | `configure(level_loader: LevelLoader) -> void` | 注入正式关卡加载入口并订阅结果信号。 |
| `LevelDebugPanel.gd` | `_show_file_dialog() -> void` | 打开资源关卡选择器。 |
| `LevelDebugPanel.gd` | `_on_file_selected(path: String) -> void` | 请求 LevelLoader 切换运行时关卡。 |
| `LevelDebugPanel.gd` | `_on_level_loaded(level_resource: LevelResource, source_path: String) -> void` | 更新当前关卡名。 |
| `LevelDebugPanel.gd` | `_on_level_load_failed(source_path: String, reason: String) -> void` | 显示加载失败原因。 |
| `M3DebugPanel.gd` | `configure(building_manager, resource_manager, combat_manager, mirror_manager = null) -> void` | 注入建筑、战斗、经济与 M5 镜子入口并订阅状态信号。 |
| `M3DebugPanel.gd` | `get_mode() -> InteractionMode` | 返回当前互斥交互模式。 |
| `M3DebugPanel.gd` | `get_selected_definition() -> BuildingDefinition` | 返回当前箭塔、激光塔、地块屏障、边屏障定义或 null。 |
| `M3DebugPanel.gd` | `select_mode(value: InteractionMode) -> void` | 更新按钮状态、模式文本并广播。 |
| `M3DebugPanel.gd` | `cancel_to_select() -> void` | 右键取消时回到选择模式。 |
| `M3DebugPanel.gd` | `_refresh_summary() -> void` | 从 Manager 读取资源、上限与目标数量。 |
| `M3DebugPanel.gd` | `_on_upgrade_pressed() -> void` | 请求 BuildingManager 升级当前选择。 |
| `M3DebugPanel.gd` | `_on_preview_updated(building: Building) -> void` | 显示预览塔种、1 级和离散朝向。 |
| `BuildingActionPanel.gd` | `configure(building_manager: BuildingManager, camera: Camera3D) -> void` | 注入建筑公共入口与投影相机，并订阅选择/升级/删除信号。 |
| `BuildingActionPanel.gd` | `_update_projection() -> void` | 将选中建筑动作锚点投影到屏幕，越过相机背面时隐藏。 |
| `BuildingActionPanel.gd` | `_on_delete_pressed()` / `_on_upgrade_pressed()` / `_on_rotate_pressed()` | 调用三个 BuildingManager 公共操作。 |
| `MirrorActionPanel.gd` | `configure(mirror_manager: MirrorManager, camera: Camera3D) -> void` | 订阅镜子选择/删除/翻面并把按钮投影到镜面上方。 |
| `WaveStatusPanel.gd` | `configure(wave_manager: WaveManager, base_core: BaseCore) -> void` | 订阅波次与据点状态并初始化显示。 |
| `WaveStatusPanel.gd` | `_on_start_pressed() -> void` | 在 READY 时请求 WaveManager 启动唯一一次全局波次时间轴。 |
| `RuntimeInteractionController.gd` | `select_building_card(definition) -> bool` | 清除实体选择并进入块/边建筑放置状态。 |
| `RuntimeInteractionController.gd` | `select_copy_mirror_card() -> bool` | 清除实体选择并进入复制镜边放置状态。 |
| `RuntimeInteractionController.gd` | `handle_primary(cell_pick, edge_pick) -> Dictionary` | 在选择模式选实体，或执行恰好一次放置并返回稳定结果。 |
| `RuntimeInteractionController.gd` | `cancel_to_select(clear_world_selection=true) -> void` | 清卡、清预览、按需清实体并回选择模式。 |
| `RuntimeInteractionController.gd` | `has_world_selection() -> bool` / `get_world_selection_cell() -> Vector3i` / `get_world_selection_edge_id() -> String` | 返回正式选择模式当前锁定格/边；变化通过 `world_selection_changed(has_cell, cell, edge_id)` 广播。 |
| `GameTimeController.gd` | `configure(interaction, building_manager, mirror_manager) -> void` | 订阅交互与实体选择，建立战术上下文。 |
| `GameTimeController.gd` | `set_tactical_slow_enabled(enabled) -> void` | 开关自动战术慢放并立即重算倍率。 |
| `GameTimeController.gd` | `set_fast_enabled(enabled)` / `set_paused(paused)` | 保存快速/暂停请求并按固定优先级重算。 |
| `BuildCardBar.gd` | `configure(resource_manager, mirror_definition, building_definitions, slot_count) -> void` | 构造独立镜子卡、建筑卡和空镜面并订阅经济信号。 |
| `RuntimeHud.gd` | `configure(...) -> void` | 组合卡槽、交互和时间控制器。 |
| `RuntimeHud.gd` | `configure_inspection(grid_manager, tile_manager, building_manager, mirror_manager, tile_effect_system) -> void` | 注入批次 2 只读检视依赖并同步现有选择。 |
| `RuntimeHud.gd` | `apply_level_configuration(level) -> void` | 切关时应用本关建筑槽数。 |
| `TileInspectionService.gd` | `configure(grid_manager, tile_manager, building_manager, mirror_manager, tile_effect_system) -> void` | 订阅内容/耐久/方向/投影/装填变化，重复配置前安全断开旧信号。 |
| `TileInspectionService.gd` | `set_selected_cell(has_cell: bool, cell: Vector3i, edge_id: String = "") -> void` | 接收正式选择事实源并触发合并刷新。 |
| `TileInspectionService.gd` | `inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary` | 返回 Builder 的只读快照；顶层键为 `has_content/cell/selected_edge_id/terrain_name/height_level/allows_tile_building/allows_edge_building/entries`。 |
| `InspectionDisplayConfig.gd` | `resolve_display_name(fallback: String) -> String` / `resolve_function_description(fallback: String) -> String` | 使用非空自定义文本，否则回退到当前名称或内置说明。 |
| `TileInspectionModelBuilder.gd` | `inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary` | 聚合本格 occupant、全部相邻边实体、同格投影和元素运行时数据；先按对象级 `visible` 过滤，条目键含 `kind/name/category/state/icon/accent/description/show_icon/show_category/show_state/show_description/lines/has_source/source_cell/mirror_edge_id`。 |
| `TileInspectorPanel.gd` | `display_model(model: Dictionary) -> void` | 非空时按字段开关自适应重建滚动条目并展开，空模型时收起。 |
| `TileInspectorPanel.gd` | `clear_inspection() -> void` | 清除当前只读快照及动态条目。 |

## 已知限制 / 初版不做的部分
- 不做敌方据点相关 UI（已改为我方据点血量 + 剩余敌人计数）。
- 不做设置/存档/主菜单等元界面（Level 系统另述存档数据）。
- 当前选关面板是可关闭的开发调试入口，不代表正式选关界面与关卡解锁流程。
- M3 面板已默认隐藏；其调试能力会在 M6 批次 6 迁移到 F1 控制台后移除正常运行依赖。
- M6 批次 1-2 已完成卡片、单次放置、战术慢放基础和地块详情；经济滚动、全局信息、正式 2x/暂停、波次时间轴、机位和控制台按 `Docs/07_M6_操作与UI大版本_需求与开发计划.md` 后续批次实现。
- WaveStatusPanel 是 M4 灰盒入口；M7 再将其整合为顶部正式 HUD 的据点血量和本波进度。
- 小地图仅静态缩略，不做迷雾/交互点选。
