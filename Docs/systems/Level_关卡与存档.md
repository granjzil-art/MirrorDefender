# 关卡与存档 · Level

> 实现状态：已实现 LevelResource、编辑器/运行时加载、调试选关及 M3 初始资源、建筑/镜子上限和五类产出配置；局内存档、路径与波次字段留待后续模块扩充。

## 职责
用一个数据资源描述关卡的网格、地块布局与经济配置，使新增关卡无需改运行时代码；为 M4~M7 的路径、波次和通关存档保留唯一扩展载体。

## 分类 / 做法
- **LevelResource**：自定义 `Resource`，保存网格、地块、高度色，以及 M3 初始资源、建筑/镜子上限和五类产出参数。
- **编辑器加载**：LevelResource 与其引用的 TileCellData 使用 `@tool`，使地块编辑器读取 `.tres` 时能调用 `get_tile()` 和地块状态方法，而非得到不可执行的 placeholder 资源。
- **布局按 cell 去重**：`tiles` 是为 Godot 序列化保留的 `Array`，但 `store_tile()` 将同 cell 的旧对象替换为新对象。运行期 TileManager 再建立 `Dictionary[Vector3i, TileCellData]` 索引。
- **编辑器保存**：地块编辑器调用 `ResourceSaver.save(level, path)` 写出 `.tres`；仅允许 `res://` 路径，保存后触发文件系统扫描。
- **运行期加载**：LevelLoader 是唯一装配入口，先把 LevelResource 的网格参数交给 GridManager，再让 TileManager 读取布局；缺失格自动补默认可建造数据。
- **调试选关**：运行时 LevelDebugPanel 可从 `res://` 选择 LevelResource `.tres`，调用与后续正式选关相同的 `LevelLoader.load_level_path()`；面板由独立 feature flag 控制。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
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
| `kill_drop_enabled` | true | 击杀奖励开关。 |
| `tile_income_enabled` / `tile_income_rate` | true / 1.0 | 建筑占用格每秒产出。 |
| `producer_income_enabled` / `producer_income_rate` | true / 2.0 | 生产建筑每秒产出。 |
| `time_growth_enabled` / `time_growth_rate` | true / 0.5 | 时间自然增长。 |
| `destroy_tile_income_enabled` / `destroy_tile_income_amount` | true / 20 | 清障一次性产出。 |
| LevelLoader.`feature_enabled` | true | 运行时关卡加载总开关。 |
| LevelLoader.`initial_level` | M2DemoLevel | 主场景启动时加载的关卡。 |
| LevelDebugPanel.`feature_enabled` | true | 运行时调试选关面板开关；正式发行可关闭。 |
| LevelDebugPanel.`initial_directory` | `res://resources/levels` | 调试文件选择器的起始目录。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | M2 网格/地块与 M3 经济参数的统一关卡定义。 |
| `scripts/level/LevelLoader.gd` | `LevelLoader` / `Node` | **运行时唯一关卡装配入口**；验证资源、重配 Grid、加载 Tile 并广播结果。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 可关闭的运行时调试选关入口，只依赖 LevelLoader 公共 API/信号。 |
| `resources/levels/M2DemoLevel.tres` | `LevelResource` | 主场景 M2 验收布局，含道路、两处障碍和 0~2 档高度示例。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 关卡资源的新建、读取和保存入口。 |
| `scripts/Main.gd` | `Node3D` 场景脚本 | 注入 LevelLoader 依赖；切关后应用经济配置并清空旧建筑、目标和拾取状态。 |
| `scenes/Main.tscn` | `Node3D` 场景 | 由 LevelLoader 的 `initial_level` 装配 M2DemoLevel，并挂载关卡/M3 调试面板。 |

### 模块调用关系 / 数据流

```text
Main._ready
  -> LevelLoader.configure(GridManager, TileManager)
  -> LevelLoader.load_initial_level()

Debug picker / future production level selection
  -> LevelLoader.load_level_path(path) or load_level(resource)
  -> validate LevelResource
  -> GridManager.apply_configuration(shape, size, range)
  -> TileManager.load_level(level)
       ├─ serialized tiles -> runtime Dictionary[cell, TileCellData]
       └─ TileManager.level_loaded -> TileRenderer rebuild
  -> LevelLoader.level_loaded
       ├─ ResourceManager.apply_level_configuration(level)
       ├─ CombatManager.clear_targets()
       └─ debug status / Main clears stale selection

Mirror Tile Editor
  -> creates / edits LevelResource (tiles + height colors)
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

### LevelLoader.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入关卡装配所需的两个模块入口。 |
| `load_initial_level` | `() -> bool` | 加载 Inspector 配置的初始关卡。 |
| `load_level` | `(level_resource: LevelResource, source_path: String = "") -> bool` | 应用 Grid 配置、加载 Tile 布局并广播成功；失败不替换当前关卡。 |
| `load_level_path` | `(path: String) -> bool` | 从 `res://` 读取 `.tres`，校验 LevelResource 后交给 `load_level()`。 |
| `get_current_level` | `() -> LevelResource` | 返回当前成功装配的关卡。 |
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
- 资源中的 TileCellData 是可保存的配置；TileCellData 的 `occupant` 是运行时字段，绝不写入关卡文件。
- 高度三色由 LevelResource 序列化，作为编辑器与运行时 TileRenderer 共用的地形颜色事实源；地块类型仍由障碍标记和玩法规则区分。
- `grid_shape` 与 GridManager 枚举的数值顺序必须保持一致；若未来扩展三角形，先扩展 Grid 枚举与迁移策略，再使用新数值。
- 关卡编辑器生成的是可追踪 `.tres`，不是外部表格；符合“配置优先在 Godot 检视面板/资源内完成”的项目规范。
- LevelLoader 是运行时关卡装配事实源；调试选关和未来正式选关共用其公共 API 与结果信号。
- 调试加载只接受 `res://` 下的 `.tres`；外部文件系统关卡包不属于当前接口范围。
- M3 经济字段缺省时使用 LevelResource 脚本默认值，旧关卡无需迁移即可运行；加载成功后 ResourceManager 是局内余额事实源。

## 已知限制 / 初版不做的部分

- 未实现 SaveManager、局内读档、关卡解锁与正式选关界面；LevelLoader 接口已预留给正式选关调用。
- 路径、波次与据点字段将在 M4 后续系统接入时加入同一资源。
- 不做云存档、多存档槽和关卡包导入。
