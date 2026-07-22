# 界面系统 · UI

## 职责
提供 HUD 与操作入口，承载卡槽、资源、检视、波次、全局状态和时间控制。M6 的整体布局、批次边界与验收事实源为 `Docs/07_M6_操作与UI大版本_需求与开发计划.md`。

## 分类 / 做法
- **M6 批次 1 正式 HUD（已实现）**：底部为独立复制镜槽加单行建筑卡槽；建筑槽数由关卡配置，默认 6。默认携带箭塔、激光塔、屏障，未使用位置显示空镜面；边障保留玩法但不进入默认卡组。
- **卡片状态**：卡片显示名称、可替换图标和 1 级建造费用；资源不足或达到对应上限时置灰且不可新选，选中卡使用金色镜框。`BuildingDefinition.card_icon` 与 `CopyMirrorDefinition.card_icon` 为空时使用稳定文字灰盒。
- **单次放置**：`RuntimeInteractionController` 是正式交互事实源。每次选卡只允许一次世界点击；成功、资源不足、上限、非法地块、非法边或未命中都会取消卡片/预览/实体选择并回 `SELECT`，成功放置的实体不会保持自动选中。
- **取消和输入消费**：左键执行肯定操作；右键在 GUI 分发前全局取消并回选择模式。正式卡片和按钮消费左键，点击 UI 不会穿透到世界。
- **战术慢放**：选卡或选中实体建筑、实体边建筑、实体镜子时，`GameTimeController` 默认切到 0.1x。右下按钮可关闭自动慢放；优先级固定为 `暂停 0x > 战术慢放 0.1x > 快速 2x > 正常 1x`。批次 1 已交付时间控制基础和慢放按钮，正式 2x/暂停菜单在批次 3 接入。
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
| GameTimeController.`tactical_slow_enabled` | true | 是否在选卡/选中实体时自动慢放。 |
| GameTimeController.`tactical_slow_scale` | 0.1 | 战术慢放倍率。 |
| GameTimeController.`fast_scale` | 2.0 | 批次 3 正式按钮使用的快速倍率。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/Main.gd` | `Node3D` | 更新拾取/建筑 HUD，装配 M4 运行时节点并注入调试、建造和波次面板。 |
| `scripts/ui/RuntimeInteractionController.gd` | `RuntimeInteractionController` / `Node` | 正式 SELECT/块放置/边放置/镜子放置状态机和单次尝试事务。 |
| `scripts/ui/GameTimeController.gd` | `GameTimeController` / `Node` | 统一求解暂停、战术慢放、2x 与 1x 的时间优先级。 |
| `scripts/ui/BuildCardBar.gd` | `BuildCardBar` / `Control` | 独立镜子槽、可调建筑槽、卡片可用性、选中框、空镜面和状态反馈。 |
| `scripts/ui/RuntimeHud.gd` | `RuntimeHud` / `Control` | M6 正式 HUD 组合根；将卡片和慢放按钮连接到控制器。 |
| `scenes/ui/RuntimeHud.tscn` | `Control` 场景 | 可复用正式 HUD 场景；批次 1 含底部卡槽和右下慢放按钮。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 运行时调试关卡状态与资源选择按钮。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 箭塔/激光塔/屏障模式、升级、预览状态、经济/上限/靶标摘要和错误反馈。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 根据相机投影跟随选中建筑，提供删除、升级、旋转三项上下文操作。 |
| `scripts/ui/MirrorActionPanel.gd` | `MirrorActionPanel` / `Control` | 跟随选中复制镜，提供删除和生效侧翻面。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 显示据点/波次/敌人摘要，并请求 WaveManager 开始全局波次时间轴。 |
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
| `GameTimeController.gd` | `configure(interaction, building_manager, mirror_manager) -> void` | 订阅交互与实体选择，建立战术上下文。 |
| `GameTimeController.gd` | `set_tactical_slow_enabled(enabled) -> void` | 开关自动战术慢放并立即重算倍率。 |
| `GameTimeController.gd` | `set_fast_enabled(enabled)` / `set_paused(paused)` | 保存快速/暂停请求并按固定优先级重算。 |
| `BuildCardBar.gd` | `configure(resource_manager, mirror_definition, building_definitions, slot_count) -> void` | 构造独立镜子卡、建筑卡和空镜面并订阅经济信号。 |
| `RuntimeHud.gd` | `configure(...) -> void` | 组合卡槽、交互和时间控制器。 |
| `RuntimeHud.gd` | `apply_level_configuration(level) -> void` | 切关时应用本关建筑槽数。 |

## 已知限制 / 初版不做的部分
- 不做敌方据点相关 UI（已改为我方据点血量 + 剩余敌人计数）。
- 不做设置/存档/主菜单等元界面（Level 系统另述存档数据）。
- 当前选关面板是可关闭的开发调试入口，不代表正式选关界面与关卡解锁流程。
- M3 面板已默认隐藏；其调试能力会在 M6 批次 6 迁移到 F1 控制台后移除正常运行依赖。
- M6 批次 1 只完成卡槽、单次放置和战术慢放基础；地块详情、经济滚动、全局信息、正式 2x/暂停、波次时间轴、机位和控制台按 `Docs/07_M6_操作与UI大版本_需求与开发计划.md` 后续批次实现。
- WaveStatusPanel 是 M4 灰盒入口；M7 再将其整合为顶部正式 HUD 的据点血量和本波进度。
- 小地图仅静态缩略，不做迷雾/交互点选。
