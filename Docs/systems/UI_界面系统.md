# 界面系统 · UI

## 职责
提供 HUD 与操作入口，沿用原型布局，承载资源、建造、检视、波次与机制图例等信息。

## 分类 / 做法
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
- **建筑/镜子灰盒 UI**：LevelDebugPanel 下方的 M3DebugPanel 显示资源、总每秒产出、建筑/镜子上限和靶标数，提供选择、箭塔、激光塔、屏障、边障、复制镜、靶标七个互斥模式及当前建筑升级按钮。
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
| M3DebugPanel.`feature_enabled` | true | M3 灰盒建造/靶标面板开关。 |
| WaveStatusPanel.`feature_enabled` | true | M4 波次状态与手动开波面板开关。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/Main.gd` | `Node3D` | 更新拾取/建筑 HUD，装配 M4 运行时节点并注入调试、建造和波次面板。 |
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

M3DebugPanel mode -> Main cell/edge input -> BuildingManager / CombatManager
  -> barrier mode -> BuildingManager path/protected/enemy occupancy validation
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

## 已知限制 / 初版不做的部分
- 不做敌方据点相关 UI（已改为我方据点血量 + 剩余敌人计数）。
- 不做设置/存档/主菜单等元界面（Level 系统另述存档数据）。
- 当前选关面板是可关闭的开发调试入口，不代表正式选关界面与关卡解锁流程。
- M3 面板同样是灰盒验收入口；当前升级按钮与虚影逻辑可复用，但不代表 M7 的正式卡片建造栏、检视面板或小地图外观。
- WaveStatusPanel 是 M4 灰盒入口；M7 再将其整合为顶部正式 HUD 的据点血量和本波进度。
- 小地图仅静态缩略，不做迷雾/交互点选。
