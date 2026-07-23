# 关卡与存档 · Level

> 实现状态：已实现 LevelResource、编辑器/运行时加载、调试选关、M3 经济配置、M4 据点/路径/波次，以及 M6 六个可选镜头预设；局内存档与正式选关仍待后续模块扩充。

## 职责
用一个数据资源描述关卡的网格、地块布局、经济、据点、路径和波次，使新增关卡无需改运行时代码；为后续镜子和通关存档保留唯一扩展载体。

## 分类 / 做法
- **LevelResource**：自定义 `Resource`，保存网格、地块、高度色、M3 经济、M4 据点/路径/出生点/波次，以及 M6 六个可选镜头预设。建筑产出属于建筑逐级参数；敌人掉落属于 M4 敌人定义。
- **镜头槽位兼容**：`camera_presets` 最多持有 6 个 `CameraPresetDefinition`，数组位置对应数字键 1～6，元素可空。旧关卡缺少字段时保持空数组；加载和编辑器打开都不补齐、不回写。
- **运行时完整校验**：`validate_runtime()` 是只读预检，统一验证网格、地块类型/坐标/高度、经济与据点数值、路径、出生点、波次引用及波次使用的 EnemyDefinition。`validate_m4()` 是同一检查的兼容入口；两者都不保存、不加载、不修复关卡。
- **编辑器加载**：LevelResource 与其引用的 TileCellData 使用 `@tool`，使地块编辑器读取 `.tres` 时能调用 `get_tile()` 和地块状态方法，而非得到不可执行的 placeholder 资源。
- **布局按 cell 去重**：`tiles` 是为 Godot 序列化保留的 `Array`，但 `store_tile()` 将同 cell 的旧对象替换为新对象。运行期 TileManager 再建立 `Dictionary[Vector3i, TileCellData]` 索引。
- **编辑器保存**：关卡编辑器调用 `ResourceSaver.save(level, path)` 写出 `.tres`；仅允许 `res://` 路径。未保存的新建/加载、会清空地块的网格重建均需确认；网格重建可撤销/重做；校验失败的未完成关卡仅可经二次确认保存。
- **运行期加载**：LevelLoader 是唯一装配入口。它先完整校验 LevelResource，成功后才配置 Grid 并让 TileManager 构造下一份运行时布局；TileManager 若仍意外拒绝装配，Loader 会恢复旧 Grid 配置，旧 Tile 字典和当前关卡保持不变。缺失格自动补默认可建造数据。
- **局内重启**：暂停菜单只发出高层请求，`Main` 调用 `LevelLoader.reload_current_level()`。资源路径关卡重新走 `load_level_path()` 完整事务，内存关卡先深复制；所有 Manager 统一由新的 `level_loaded` 事件重置。
- **调试选关**：运行时 LevelDebugPanel 可从 `res://` 选择 LevelResource `.tres`，调用与后续正式选关相同的 `LevelLoader.load_level_path()`；面板由独立 feature flag 控制。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `display_name` | `""` | M6 右上全局信息的玩家可见关卡名；空值回退到关卡资源文件名。 |
| `grid_shape` | 0 | 0=HEX，1=SQUARE；与 `GridManager.Shape` 顺序一致。 |
| `grid_cell_size` | 1.0 | 交给 GridManager 的单格尺寸。 |
| `grid_size` | `(6, 6)` | HEX 取 x 为半径；SQUARE 取 `(列, 行)`。 |
| `height_levels` | 3 | Tile 高度档数，下限 1。 |
| `height_step` | 0.45 | 每个高度档对应的世界 Y 差。 |
| `height_color_low` | 绿 | 高度 0 的地形色，编辑器与运行时共用。 |
| `height_color_middle` | 黄 | 中间高度的地形色，编辑器与运行时共用。 |
| `height_color_high` | 红 | 最高高度的地形色，编辑器与运行时共用。 |
| `tiles` | `[]` | `TileCellData` 资源数组；每项持有自己的 `cell`。 |
| `initial_resource` | 200 | 切入关卡时的主资源。 |
| `building_cap` / `mirror_cap` | 20 / 6 | 原件建筑与镜子上限。 |
| `base_resource_per_second` | 0.5 | 本关基础每秒资源，与建筑产出独立。 |
| `building_card_slot_count` | 6 | M6 正式 HUD 的建筑携带槽数量，范围 1～12；复制镜独立槽不计入。 |
| `camera_presets` | `[]` | M6 最多 6 个可空 CameraPresetDefinition；索引 0～5 对应数字键 1～6。 |
| CameraPreset.`focus_position` | `(0,0,0)` | CameraController pivot 的世界坐标。 |
| CameraPreset.`yaw_degrees` / `pitch_degrees` | `0 / 50` | 水平旋转与俯仰角，均以度序列化。 |
| CameraPreset.`zoom_distance` | `16` | 相机到焦点的世界距离；运行时再按 CameraController 范围收紧。 |
| `base_points` / `base_max_hp` | `[]` / 100 | 独立 BasePointDefinition 位置数组及全部位置共享的最大生命。 |
| `base_cell` | `(0,0,0)` | 旧关卡兼容据点；`base_points` 为空时只读解析为据点 1。 |
| `paths` / `spawn_points` | `[]` | 路径数组与可被多路径共用的独立出生点数组。 |
| `waves` | `[]` | M4 固定波次数组，每项持有多个 SpawnGroup。 |
| SpawnGroup.`start_delay` | 0.0 | 相对首次点击“开始第一波”的全局延迟；后续波次无需再次点击。 |
| LevelLoader.`feature_enabled` | true | 运行时关卡加载总开关。 |
| LevelLoader.`initial_level` | M4DemoLevel | 主场景启动时加载的关卡。 |
| LevelDebugPanel.`feature_enabled` | true | 运行时调试选关面板开关；正式发行可关闭。 |
| LevelDebugPanel.`initial_directory` | `res://resources/levels` | 调试文件选择器的起始目录。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | M2 地块、M3 经济、M4 据点/路径/波次及 M6 HUD/镜头槽位的统一关卡定义。 |
| `scripts/camera/CameraPresetDefinition.gd` | `CameraPresetDefinition` / `Resource` | 一个可选镜头槽位的世界焦点、yaw、pitch 与缩放距离。 |
| `scripts/level/LevelLoader.gd` | `LevelLoader` / `Node` | **运行时唯一关卡装配入口**；验证资源、重配 Grid、加载 Tile 并广播结果。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 可关闭的运行时调试选关入口，只依赖 LevelLoader 公共 API/信号。 |
| `scripts/shared/ConfigurationValidator.gd` | `ConfigurationValidator` / `RefCounted` | 跨资源共享、无副作用的有限数/范围/颜色/嵌套错误校验。 |
| `resources/levels/M2DemoLevel.tres` | `LevelResource` | M2 地块编辑示例。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` | 两波 M4 可运行示例，含路径、出生点、据点和敌人配置。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 地块、路径、波次和镜头四页关卡资源编辑、读取和保存入口。 |
| `addons/mirror_tile_editor/tile_editor_plugin.gd` | `EditorPlugin` | 将面板挂到 Godot 主编辑区，并以 `EXPAND_FILL` 消费 MainScreen VBox 可用空间。 |
| `addons/mirror_tile_editor/camera_preset_editor.gd` | `CameraPresetEditor` / `VBoxContainer` | 独立镜头页的六槽写入、预览、清空组件。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control` | 地块/路径/镜头预览画布；公开运行时视角状态转换入口。 |
| `scripts/Main.gd` | `Node3D` 场景脚本 | 注入 Loader、路径、据点和波次依赖；切关时重置 M3/M4 运行时状态。 |
| `scenes/Main.tscn` | `Node3D` 场景 | 由 LevelLoader 的 `initial_level` 装配 M4DemoLevel，并挂载调试、建造和波次面板。 |

### 模块调用关系 / 数据流

```text
Main._ready
  -> LevelLoader.configure(GridManager, TileManager)
  -> LevelLoader.load_initial_level()

Debug picker / future production level selection
  -> LevelLoader.load_level_path(path) or load_level(resource)
  -> LevelResource.validate_runtime() (read-only preflight)
	 └─ failure: preserve current Grid / Tile / current level
  -> GridManager.apply_configuration(shape, size, range)
  -> TileManager.load_level(level)
	   ├─ serialized tiles -> cloned runtime Dictionary[cell, TileCellData]
	   ├─ unexpected rejection -> restore previous Grid; keep previous Tile/current level
	   └─ TileManager.level_loaded -> TileRenderer rebuild
  -> LevelLoader.level_loaded
	   ├─ ResourceManager.apply_level_configuration(level)
	   ├─ CombatManager.clear_targets()
	   ├─ PathManager.load_level(level) -> BaseCore.load_level(level)
	   ├─ WaveManager.load_level(level)
	   ├─ RuntimeHud.apply_level_configuration(level, source_path) -> 建筑卡槽数量 + 关卡显示名
	   ├─ CameraPresetController.load_level(level) -> 六个可选运行时机位
	   └─ debug status / Main clears stale selection

Mirror Level Editor
  -> creates / edits LevelResource (tiles + height colors + M4 paths/waves + M6 camera presets)
  -> “镜头”页从独立 TileEditorCanvas 写入/预览/清空 1～6 号槽
  -> ResourceSaver.save(.../*.tres)
  -> LevelLoader.load_level(resource) can install that resource at runtime
```

后续模块只扩展 LevelResource 字段或新增其持有的子资源，不创建平行关卡格式。正式选关 UI 只能调用 LevelLoader，不直接操作 GridManager/TileManager。

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_tile` | `(cell: Vector3i) -> Variant` | 返回给定 cell 的 TileCellData 或 null；返回 Variant 是序列化边界，调用方须显式收窄类型。 |
| `store_tile` | `(tile: Resource) -> void` | 以 `tile.cell` 覆盖/插入布局并标记资源已变化。 |
| `clear_tiles` | `() -> void` | 清空布局，供编辑器按新网格参数重建默认格。 |
| `clamp_tile_heights` | `() -> void` | 将所有序列化地块的高度收紧到当前 `height_levels`。 |
| `get_height_color` | `(height_level: int) -> Color` | 低→中→高两段插值得到关卡统一的高度色。 |
| `get_camera_preset` | `(slot_index: int) -> CameraPresetDefinition` | 读取零基 0～5 槽；越界、数组未增长或元素为空均返回 null。 |
| `set_camera_preset` | `(slot_index: int, preset: CameraPresetDefinition) -> bool` | 只增长到目标槽并保存子资源；不物化后续空槽。 |
| `clear_camera_preset` | `(slot_index: int) -> bool` | 将已配置槽设为空并发出资源 changed；无配置返回 false。 |
| `get_configured_camera_preset_count` | `() -> int` | 统计前六槽非空预设数。 |
| `get_path_by_id` | `(path_id: StringName) -> PathDefinition` | 从本关路径数组按稳定 ID 返回定义或 null。 |
| `get_spawn_point` | `(spawn_id: StringName) -> SpawnPointDefinition` | 从本关出生点数组按稳定 ID 返回定义或 null。 |
| `validate_runtime` | `() -> Array[String]` | 只读返回完整运行时配置错误；覆盖 Grid、Tile、经济、据点、路径、出生点和波次，空数组表示可安装。 |
| `validate_m4` | `() -> Array[String]` | 编辑器兼容入口，直接返回 `validate_runtime()` 的同一结果。 |

### LevelLoader.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入关卡装配所需的两个模块入口。 |
| `load_initial_level` | `() -> bool` | 加载 Inspector 配置的初始关卡。 |
| `load_level` | `(level_resource: LevelResource, source_path: String = "") -> bool` | 先只读预检，再应用 Grid 配置、原子安装 Tile 布局并广播成功；失败不改变当前关卡。 |
| `load_level_path` | `(path: String) -> bool` | 从 `res://` 读取 `.tres`，校验 LevelResource 后交给 `load_level()`。 |
| `get_current_level` | `() -> LevelResource` | 返回当前成功装配的关卡。 |
| `get_current_source_path` | `() -> String` | 返回当前关卡的资源路径或内存标识。 |
| `reload_current_level` | `() -> bool` | 通过完整 Loader 事务重载当前关卡；内存关卡使用新的深复制对象。 |
| `_report_failure` | `(source_path: String, reason: String) -> void` | 统一发送加载失败信号。 |

**信号**：`level_loaded(level_resource: LevelResource, source_path: String)`、`level_load_failed(source_path: String, reason: String)`。

### LevelDebugPanel.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(level_loader: LevelLoader) -> void` | 订阅 Loader 成功/失败信号，并刷新当前关卡状态。 |
| `_show_file_dialog` | `() -> void` | 打开仅浏览 `res://` 的 LevelResource 选择器。 |
| `_on_file_selected` | `(path: String) -> void` | 将选中路径交给 `LevelLoader.load_level_path()`。 |
| `_on_level_loaded` | `(level_resource: LevelResource, source_path: String) -> void` | 显示当前运行时关卡名。 |
| `_on_level_load_failed` | `(source_path: String, reason: String) -> void` | 显示失败原因，当前关卡保持不变。 |

## 约定事实源

- `tiles` 的顺序不代表空间顺序；唯一键是每个 TileCellData 的 `cell`。
- 资源中的 TileCellData 是可保存的配置快照；TileManager 加载时为每格克隆运行时对象。`occupant`、局内清障和局内高度修改只存在于该运行实例，绝不写回关卡资源。
- 高度三色由 LevelResource 序列化，作为编辑器与运行时 TileRenderer 共用的地形颜色事实源；地块类型仍由障碍标记和玩法规则区分。
- `grid_shape` 与 GridManager 枚举的数值顺序必须保持一致；若未来扩展三角形，先扩展 Grid 枚举与迁移策略，再使用新数值。
- 关卡编辑器生成的是可追踪 `.tres`，不是外部表格；符合“配置优先在 Godot 检视面板/资源内完成”的项目规范。
- LevelLoader 是运行时关卡装配事实源；调试选关和未来正式选关共用其公共 API 与结果信号。
- 局内重启也必须经过 LevelLoader，UI 不能直接重置 Grid、Tile 或各个 Manager。
- 调试加载只接受 `res://` 下的 `.tres`；外部文件系统关卡包不属于当前接口范围。
- M3 经济字段缺省时使用 LevelResource 脚本默认值，旧关卡无需迁移即可运行；加载成功后 ResourceManager 是局内余额事实源。
- `building_card_slot_count` 缺省为 6，旧关卡无需迁移；范围由 `validate_runtime()` 校验。复制镜固定槽不占此数量。
- `camera_presets` 的数组索引是镜头槽位事实源，最大 6；空数组和空元素都表示未配置。`validate_runtime()` 只读校验数量、有限坐标、角度与正距离，不填默认机位。
- LevelResource 只保存关卡基础产出；建筑每秒产出在各塔 `levels[n].resource_per_second`，敌人掉落在 EnemyDefinition，三者禁止混写。
- `paths`、`spawn_points`、`base_points` 和 `waves` 均由同一个 LevelResource 持有；Path/SpawnGroup 的资源引用必须属于该关卡，不能跨关卡复用对象。
- 路径顺序恒为所选出生点到所选目标据点；`validate_m4()` 要求首尾格精确对应显式/兼容端点，不允许出生点与据点重格，也不允许路径在终点前经过其他据点。
- 波次在资源中仍按数组组织，但运行时只手动开始第一波；全部 SpawnGroup 的 `start_delay` 都以这次点击为零点，允许不同波次重叠。
- 镜头预设保存运行时世界语义，不保存编辑器像素缩放。关卡编辑器只在用户点击“写入当前视角”或“清空”时改变数组，预览不修改资源。

## 已知限制 / 初版不做的部分

- 未实现 SaveManager、局内读档、关卡解锁与正式选关界面；LevelLoader 接口已预留给正式选关调用。
- 当前不做局内读档、关卡解锁和正式选关界面；后续系统只能扩展本资源，不另建平行关卡格式。
- 不做云存档、多存档槽和关卡包导入。
