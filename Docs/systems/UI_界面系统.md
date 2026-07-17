# 界面系统 · UI

## 职责
提供 HUD 与操作入口，沿用原型布局，承载资源、建造、检视、机制图例等信息。

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

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/Main.gd` | `Node3D` | 更新当前拾取 HUD，并注入 LevelDebugPanel 的 Loader 依赖。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 运行时调试关卡状态与资源选择按钮。 |
| `scenes/Main.tscn` | `Node3D` 场景 | HUD 左侧拾取信息、底部操作提示和右上调试选关装配。 |

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
```

## 函数索引

| 文件 | 函数签名 | 职责 |
|---|---|---|
| `LevelDebugPanel.gd` | `configure(level_loader: LevelLoader) -> void` | 注入正式关卡加载入口并订阅结果信号。 |
| `LevelDebugPanel.gd` | `_show_file_dialog() -> void` | 打开资源关卡选择器。 |
| `LevelDebugPanel.gd` | `_on_file_selected(path: String) -> void` | 请求 LevelLoader 切换运行时关卡。 |
| `LevelDebugPanel.gd` | `_on_level_loaded(level_resource: LevelResource, source_path: String) -> void` | 更新当前关卡名。 |
| `LevelDebugPanel.gd` | `_on_level_load_failed(source_path: String, reason: String) -> void` | 显示加载失败原因。 |

## 已知限制 / 初版不做的部分
- 不做敌方据点相关 UI（已改为我方据点血量 + 剩余敌人计数）。
- 不做设置/存档/主菜单等元界面（Level 系统另述存档数据）。
- 当前选关面板是可关闭的开发调试入口，不代表正式选关界面与关卡解锁流程。
- 小地图仅静态缩略，不做迷雾/交互点选。
