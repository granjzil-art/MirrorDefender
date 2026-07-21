# 路径系统 · Path

> 实现状态：M4 已完成线性格子路径、出生点、运行时世界点解析、可视调试线和关卡编辑器路径页；已增加大石头触发的手工路径最短换路。

## 职责

保存设计者手工给出的有序格子序列，并将其转换为带地形高度的世界点供 EnemyUnit 移动。大石头阻断下一格时，可在现有手工路径中选择最短可用后缀；不做自由格网寻路，不改写路径资源。

## 分类 / 做法

- **线性路线**：每个 PathDefinition 是从出生点到据点的一串连续格子，至少两个格。
- **双网格**：连续性由当前 GridManager 的 `get_neighbors()` 判断，支持 HEX 与 SQUARE。
- **出生点**：每条 PathDefinition 与一个 SpawnPointDefinition 1:1 对应。路径是编辑事实源；出生点 ID、显示名和格坐标由路径派生，SpawnGroup 仍直接引用两个资源以兼容运行时接口。
- **世界点**：PathManager 读取每格 Tile 高度，生成格心加抬升量的 `PackedVector3Array`，敌人贴合台阶路线移动。
- **屏障语义**：边屏障和地块屏障仍是可攻击 Building，EnemyUnit 逐段查询并停步攻击，不触发换路。
- **地形换路**：大石头是“先换路、后攻击”的导航阻碍。EnemyUnit 抵达其前一格中心时，PathRoutePlanner 在其他手工路径中选择“当前格相交/相邻 + 后缀可通行”的最短候选；无候选时返回当前石头实体/投影作为攻击目标。
- **表现**：全部 `PathDefinition.cells` 的并集使用 `LevelResource.path_terrain_color`（默认 `#FFB93B`）绘制地块基底，运行时与关卡编辑器一致。PathManager 另行绘制可关闭的路线与出生点调试标记；BaseCore 绘制据点标记。没有任何有效线段时直接清空 mesh，不结束零顶点 ImmediateMesh surface。
- **编辑**：加载关卡或切入路径页时默认关闭“记录路径”，避免查看地图时误改路线；新增路径后自动开启记录，可按住左键连续拖过地块，画布会按鼠标轨迹采样并逐格记录。四边形同行/同列的跳格端点会自动补全中间格；加载旧关卡时也执行同一无歧义修复并标记为未保存。其它非相邻落点仍会被拒绝。
- **校验按钮**：“校验 M4 关卡”只读取当前内存中的 LevelResource 并列出配置错误，不保存、不加载、不启动运行时，也不会自动修复或改写路径。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| PathDefinition | `path_id` / `display_name` | 稳定标识与编辑器显示名。 |
| PathDefinition | `cells` | 起点到据点的有序 `Array[Vector3i]`。 |
| SpawnPointDefinition | `spawn_id` / `display_name` | 由对应路径派生：`path_N -> spawn_path_N`、`路径 N -> 路径 N 出生点`。 |
| SpawnPointDefinition | `cell` | 入口所在格，校验时必须在地图内。 |
| LevelResource | `path_terrain_color` | 所有路径经过格共用的地块基底色，默认 `#FFB93B`。 |
| PathManager | `show_paths` | 路线和出生点调试表现开关。 |
| PathManager | `path_color` / `spawn_color` / `line_lift` | 运行时灰盒颜色和抬升高度。 |
| PathRoutePlanner | `feature_enabled` | 大石头动态换路开关。 |
| PathRoutePlanner | `show_selected_detour` / `detour_color` / `line_lift` | 最近选中换路的调试线开关、颜色与抬升。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/path/PathDefinition.gd` | `PathDefinition` / `Resource` | 路径 ID、名称和有序格子。 |
| `scripts/path/SpawnPointDefinition.gd` | `SpawnPointDefinition` / `Resource` | 出生点 ID、名称和格坐标。 |
| `scripts/path/PathManager.gd` | `PathManager` / `Node3D` | 初始路径索引、世界点解析、校验和调试绘制入口。 |
| `scripts/path/PathBlockerPolicy.gd` | `PathBlockerPolicy` / `RefCounted` | 路径阻挡后的直接攻击/先换路后攻击策略枚举。 |
| `scripts/path/PathRoutePlanner.gd` | `PathRoutePlanner` / `Node3D` | 从手工路径集中选取确定性最短可用后缀，可选绘制换路调试线。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control` | 复用地形斜俯视投影绘制 M4 路线/入口/据点。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 路径编辑页和统一关卡保存。 |
| `tests/path_spawn_pairing_test.gd` | 无 / `SceneTree` | 1:1 命名、四边形连续记录/旧路径补全、关联识别和波次自动绑定回归。 |
| `tests/path_terrain_color_test.gd` | 无 / `SceneTree` | 路径格并集、默认色和运行时/编辑器一致性回归。 |

### 数据流

```text
LevelResource.paths / spawn_points
  -> PathManager.load_level -> path_id index + runtime line markers
  -> TileRenderer / Level Editor canvas -> path-cell union -> path_terrain_color base
  -> WaveManager SpawnGroupDefinition.path
  -> PathManager.get_world_points + PathDefinition.cells -> EnemyUnit initial movement/blocker order
  -> rock at next cell -> PathRoutePlanner.find_detour
     ├─ found -> temporary per-enemy route (does not mutate PathDefinition)
     └─ missing -> concrete rock blocker -> EnemyUnit attack state

LevelResource.paths -> BuildingManager path-cell cache
  -> ordinary towers rejected / barrier allowed outside spawn and base

Level Editor path page
  -> enable record + click neighboring cells -> PathDefinition.cells
  -> create/sync paired spawn / set base -> LevelResource
  -> wave path selection -> paired SpawnPointDefinition reference
  -> validate_m4 -> base/path/spawn/wave consistency report (read-only)
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `PathDefinition.has_minimum_cells` | `() -> bool` | 至少有两个格时返回 true。 |
| `PathDefinition.get_start_cell` / `get_end_cell` | `() -> Vector3i` | 返回首/末格；空路径返回 ZERO。 |
| `SpawnPointDefinition.make_id_for_path` | `(path: PathDefinition) -> StringName` | 生成 `spawn_<path_id>` 的 1:1 出生点 ID。 |
| `SpawnPointDefinition.make_display_name_for_path` | `(path: PathDefinition) -> String` | 生成“`<路径名> 出生点`”显示名。 |
| `SpawnPointDefinition.sync_with_path` | `(path: PathDefinition) -> void` | 同步出生点 ID、名称和路径首格。 |
| `LevelResource.get_spawn_point_candidates_for_path` | `(path: PathDefinition) -> Array[SpawnPointDefinition]` | 综合新 ID、旧波次引用和起点格，返回全部候选且不改写数据。 |
| `LevelResource.get_spawn_point_for_path` | `(path: PathDefinition) -> SpawnPointDefinition` | 仅候选唯一时返回出生点；缺失或歧义均返回 null。 |
| `LevelResource.get_path_for_spawn_point` | `(spawn_point: SpawnPointDefinition) -> PathDefinition` | 以相同兼容规则反查对应路径。 |
| `PathManager.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入网格和地形高度接口。 |
| `PathManager.load_level` | `(level_resource: LevelResource) -> void` | 重建 ID 索引和路径表现。 |
| `PathManager.get_path_definition` | `(path_id: StringName) -> PathDefinition` | 通过稳定 ID 返回路径定义。 |
| `PathManager.get_world_points` | `(path: PathDefinition) -> PackedVector3Array` | 把路径格转为带高度世界点。 |
| `PathManager.is_path_valid` | `(path: PathDefinition) -> bool` | 校验边界、长度和相邻连续性。 |
| `PathRoutePlanner.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入网格相邻与地块可通行事实源。 |
| `PathRoutePlanner.load_level` | `(level_resource: LevelResource) -> void` | 替换候选手工路径集并清理调试线。 |
| `PathRoutePlanner.find_detour` | `(current_path: PathDefinition, current_cell: Vector3i, blocked_cell: Vector3i, target: Node = null) -> Dictionary` | 返回 `{triggered: bool, found: bool, path: PathDefinition, cells: Array[Vector3i], cost: int, join_cell: Vector3i, blocker: Node}`；选不含导航阻碍的最短后缀，平分按路径序列化顺序；失败时返回当前石头攻击代理。 |
| `LevelResource.validate_m4` | `() -> Array[String]` | 只读检查据点边界，路径长度/边界/逐段相邻/终点，出生点边界，以及波次组数量、间隔和引用；空数组表示通过。 |
| `TileEditorCanvas._record_path_between` | `(from: Vector2, to: Vector2) -> void` | 按屏幕轨迹采样鼠标拖动，为路径页依次发送经过格。 |
| `TileEditorPanel._on_path_canvas_clicked` | `(cell: Vector3i) -> void` | 仅在记录开启时追加格；四边形同行/同列跳格会补全中间格，其它非相邻落点仍拒绝。 |
| `TileEditorPanel._normalize_square_path_gaps` | `(level: LevelResource) -> int` | 加载时将旧四边形路径中同行/同列的首尾段补成逐格路径，返回新增格数。 |
| `TileEditorPanel._sync_spawn_for_path` | `(path: PathDefinition, known_spawn: SpawnPointDefinition = null) -> SpawnPointDefinition` | 为路径复用或创建唯一出生点并同步命名/起点。 |
| `TileEditorPanel._get_path_option_label` / `_get_spawn_option_label` | `(...Definition) -> String` | 为路径页和波次页生成同一套“显示名 `[ID]`”标签。 |

## 约定事实源

- 路径顺序是出生点到据点，敌人不可反向解释。
- 路径颜色的事实源是所有 `PathDefinition.cells` 的格并集，而非单条当前选中路径；地块基底色与 PathManager 调试线色是两个独立表现参数。
- 波次中的 `SpawnGroupDefinition.path` 始终是初始路径；换路是单个敌人的运行时状态，不改写初始配置。
- 路径只在格坐标相同时算相交；仅画面线段交叉不建立连接。当前格与候选格必须由 `GridManager.get_neighbors()` 证明相邻，因此同时支持 HEX/SQUARE。
- 候选后缀只排除大石头等导航阻碍；空洞与尖刺均可被选中，敌人进入后再结算地块效果。建筑屏障不使路径失效，仍由敌人停步攻击。
- `canonical_edge_id` 是默认双向边屏障的阻挡事实；路径正反穿过同一物理边均受阻。只有关闭 `blocks_both_directions` 的未来变种才使用 `from_cell -> to_cell` 单向规则。
- 每条路径的末格必须等于 LevelResource.`base_cell`；出生点与路径 1:1，它的格始终同步为路径首格。波次中路径是选择事实源，出生点随之自动绑定。
- 路径页与波次页的路径选项统一使用 `display_name [path_id]`，禁止用子资源的 `resource_path` 或所属关卡文件名作为标签。
- PathDefinition / SpawnPointDefinition 必须由 LevelResource 持有；SpawnGroup 只能引用本关对象。
- 路径首格和 `base_cell` 是屏障保护格；中间路径格只允许屏障类建筑，普通塔不得占路。
- 运行时名称不能使用 `get_path()`，该名称被 Godot Node 保留；统一使用 `get_path_definition()`。

## 已知限制 / 初版不做的部分

- 不做自由格网 A*、导航网格或一次串联多条候选路径。每次阻挡事件只转入一条手工路径的后缀；后续再遇阻碍时可再次选路。
- 旧关卡未使用 `spawn_<path_id>` 命名时，编辑器会综合已有 SpawnGroup 引用与起点格识别候选；只有候选唯一时才会绑定。多个候选会显示歧义提示且不创建更多出生点。只有点击“同步当前路径出生点”或编辑该路径时才会将唯一旧出生点改为新命名。
