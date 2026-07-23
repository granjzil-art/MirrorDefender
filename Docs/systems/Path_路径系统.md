# 路径系统 · Path

> 实现状态：M4 已完成线性格子路径与大石头动态换路；M6 批次 4 已完成独立出生点、多据点目标锁定、同目标手工路径优先和限定路网 A* 回退。

## 职责

保存“独立出生点 → 手工路径 → 独立目标据点”的静态配置，并将路径转为带地形高度的世界点供 EnemyUnit 移动。大石头阻断下一格时，先选同目标据点的最短手工路径后缀，再在该据点所属手工路径格并集上执行 A*；永不转向其他据点，也不改写路径资源。

## 分类 / 做法

- **线性路线**：每个 PathDefinition 是从出生点到据点的一串连续格子，至少两个格。
- **双网格**：连续性由当前 GridManager 的 `get_neighbors()` 判断，支持 HEX 与 SQUARE。
- **独立出生点**：SpawnPointDefinition 独立配置 ID、名称、数字标记和格坐标；多条路径可共用同一出生点。PathDefinition.`spawn_point` 是新事实源，旧关卡仍可通过波次引用/首格唯一匹配只读解析。
- **多据点**：BasePointDefinition 独立配置 ID、名称、数字标记和格坐标；PathDefinition.`target_base` 锁定路径目标。多个位置共用 LevelResource.`base_max_hp`。旧关卡 `base_cell` 以只读虚拟“据点 1”兼容，只有用户编辑据点时才显式物化。
- **世界点**：PathManager 读取每格 Tile 高度，生成格心加抬升量的 `PackedVector3Array`，敌人贴合台阶路线移动。
- **屏障语义**：边屏障和地块屏障仍是可攻击 Building，EnemyUnit 逐段查询并停步攻击，不触发换路。
- **地形换路**：大石头是“先换路、后攻击”的导航阻碍。EnemyUnit 逻辑上进入“前一格→石头格”路径段时，PathRoutePlanner 仅查找与敌人初始路径相同 `target_base` 的候选。先选“当前格相交/相邻 + 后缀可通行”的最短完整手工后缀；无候选时，用可替换 `IAutoRouteStrategy` 在同目标路径格并集上做确定性 A*。两层都失败才返回当前石头实体/投影作为攻击目标。
- **表现**：全部 `PathDefinition.cells` 的并集使用 `LevelResource.path_terrain_color`（默认 `#FFB93B`）绘制地块基底，运行时与关卡编辑器一致。PathManager 另行绘制可关闭的路线与出生点调试标记；BaseCore 绘制据点标记。没有任何有效线段时直接清空 mesh，不结束零顶点 ImmediateMesh surface。
- **M6 悬停流向**：`PathHoverPreview` 只在波次块悬停时读取 PathManager 世界点，为该波全部唯一路径绘制发光折线和从入口向据点循环移动的标记；使用真实时间，不改变路径、敌人或波次。悬停离开、暂停和切关会清空。
- **编辑**：加载关卡或切入路径页时默认关闭“记录路径”，避免查看地图时误改路线；新增路径后自动开启记录，可按住左键连续拖过地块，画布会按鼠标轨迹采样并逐格记录。四边形同行/同列的跳格端点会自动补全中间格；加载旧关卡时也执行同一无歧义修复并标记为未保存。其它非相邻落点仍会被拒绝。
- **校验按钮**：“校验 M4 关卡”只读取当前内存中的 LevelResource 并列出配置错误，不保存、不加载、不启动运行时，也不会自动修复或改写路径。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| PathDefinition | `path_id` / `display_name` | 稳定标识与编辑器显示名。 |
| PathDefinition | `cells` / `spawn_point` / `target_base` | 出生点到指定据点的有序格，及显式端点引用。 |
| SpawnPointDefinition | `spawn_id` / `display_name` / `display_number` | 独立出生点标识、可编辑名称和场景数字。 |
| SpawnPointDefinition | `cell` | 入口所在格，校验时必须在地图内。 |
| BasePointDefinition | `base_id` / `display_name` / `display_number` / `cell` | 独立据点位置与数字标记；全部共享据点生命。 |
| LevelResource | `path_terrain_color` | 所有路径经过格共用的地块基底色，默认 `#FFB93B`。 |
| PathManager | `show_paths` | 路线和出生点调试表现开关。 |
| PathManager | `path_color` / `spawn_color` / `line_lift` | 运行时灰盒颜色和抬升高度。 |
| PathRoutePlanner | `feature_enabled` | 大石头动态换路开关。 |
| PathRoutePlanner | `automatic_route_enabled` | 手工后缀失败时，是否启用同目标路网 A* 回退。 |
| PathRoutePlanner | `show_selected_detour` / `detour_color` / `line_lift` | 最近选中换路的调试线开关、颜色与抬升。 |
| PathHoverPreview | `feature_enabled` | M6 波次悬停世界流向总开关。 |
| PathHoverPreview | `flow_speed` / `markers_per_path` / `line_lift` / `marker_radius` | 流动速度、每条路径标记数、折线抬升和标记半径。 |
| PathHoverPreview | `line_color` / `marker_color` / `emission_energy` | 默认发光颜色和强度。 |
| PathHoverPreview | `line_material` / `marker_material` / `marker_mesh` | 折线材质、标记材质与标记 Mesh 美术替换接口。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/path/PathDefinition.gd` | `PathDefinition` / `Resource` | 路径 ID、名称、有序格子和显式首尾端点。 |
| `scripts/path/SpawnPointDefinition.gd` | `SpawnPointDefinition` / `Resource` | 独立出生点 ID、名称、数字和格坐标。 |
| `scripts/path/BasePointDefinition.gd` | `BasePointDefinition` / `Resource` | 独立据点 ID、名称、数字和格坐标。 |
| `scripts/path/PathManager.gd` | `PathManager` / `Node3D` | 初始路径索引、世界点解析、校验和调试绘制入口。 |
| `scripts/path/PathBlockerPolicy.gd` | `PathBlockerPolicy` / `RefCounted` | 路径阻挡后的直接攻击/先换路后攻击策略枚举。 |
| `scripts/path/PathRoutePlanner.gd` | `PathRoutePlanner` / `Node3D` | 同目标手工后缀优先的换路编排与调试线。 |
| `scripts/path/IAutoRouteStrategy.gd` / `PathNetworkAStarStrategy.gd` | `RefCounted` | 可替换自动寻路接口与限定路网的确定性 A* 实现。 |
| `scripts/path/PathHoverPreview.gd` / `scenes/path/PathHoverPreview.tscn` | `PathHoverPreview` / `Node3D` | 波次悬停期间的多路径发光折线和真实时间流向标记；场景提供 Inspector 参数入口。 |
| `addons/mirror_tile_editor/tile_editor_canvas.gd` | `Control` | 复用地形斜俯视投影绘制 M4 路线/入口/据点。 |
| `addons/mirror_tile_editor/tile_editor_panel.gd` | `Control` | 路径编辑页和统一关卡保存。 |
| `tests/path_spawn_pairing_test.gd` | 无 / `SceneTree` | 独立出生点、共用入口、多据点端点、旧关卡兼容和波次派生绑定回归。 |
| `tests/path_terrain_color_test.gd` | 无 / `SceneTree` | 路径格并集、默认色和运行时/编辑器一致性回归。 |

### 数据流

```text
LevelResource.paths / spawn_points / base_points
  -> PathManager.load_level -> path_id index + runtime line markers
  -> TileRenderer / Level Editor canvas -> path-cell union -> path_terrain_color base
  -> WaveManager SpawnGroupDefinition.path
  -> PathManager.get_world_points + PathDefinition.cells -> EnemyUnit initial movement/blocker order
  -> rock at next cell -> PathRoutePlanner.find_detour(target_base locked)
     ├─ same-target manual suffix -> temporary per-enemy route
     ├─ target road-cell union -> PathNetworkAStarStrategy
     └─ both missing -> concrete rock blocker -> EnemyUnit attack state

LevelResource.paths -> BuildingManager path-cell cache
  -> ordinary towers rejected / barrier allowed outside spawn and base

Level Editor path page
  -> author numbered spawn/base locations independently
  -> select origin + target, then record neighboring cells -> PathDefinition
  -> wave path selection -> derive the path's SpawnPointDefinition
  -> validate_m4 -> base/path/spawn/wave consistency report (read-only)

WaveTimelinePanel hover paths -> RuntimeHud signal -> Main
  -> PathHoverPreview.preview_paths -> PathManager.get_world_points
  -> line + spawn-to-base looping markers
PathManager.paths_loaded / hover exit / pause -> PathHoverPreview.clear_preview
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `PathDefinition.has_minimum_cells` | `() -> bool` | 至少有两个格时返回 true。 |
| `PathDefinition.get_start_cell` / `get_end_cell` | `() -> Vector3i` | 返回首/末格；空路径返回 ZERO。 |
| `SpawnPointDefinition.make_id_for_path` | `(path: PathDefinition) -> StringName` | 生成 `spawn_<path_id>` 的 1:1 出生点 ID。 |
| `SpawnPointDefinition.make_display_name_for_path` | `(path: PathDefinition) -> String` | 生成“`<路径名> 出生点`”显示名。 |
| `SpawnPointDefinition.sync_with_path` | `(path: PathDefinition) -> void` | 同步出生点 ID、名称和路径首格。 |
| `LevelResource.resolve_path_spawn_point` / `resolve_path_target_base` | `(path) -> ...Definition` | 优先解析显式端点，并为旧关卡提供只读唯一匹配。 |
| `LevelResource.get_effective_base_points` | `() -> Array[BasePointDefinition]` | 返回显式据点；旧关卡返回不写回资源的 `base_cell` 兼容据点。 |
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
| `PathRoutePlanner.find_detour` | `(current_path: PathDefinition, current_cell: Vector3i, blocked_cell: Vector3i, target: Node = null) -> Dictionary` | 返回换路结果、`route_source` 与 `target_base_id`；手工后缀优先，再调用同目标路网 A*，失败时返回当前石头攻击代理。 |
| `PathRoutePlanner.set_auto_route_strategy` | `(strategy: IAutoRouteStrategy) -> void` | 注入可替换自动寻路策略。 |
| `PathHoverPreview.configure` | `(path_manager: PathManager) -> void` | 注入只读世界点入口并订阅切关信号。 |
| `PathHoverPreview.preview_paths` | `(paths: Array) -> void` | 清理旧内容并同时构建全部有效路径的发光线和流动标记。 |
| `PathHoverPreview.clear_preview` | `() -> void` | 清除全部悬停路径状态、线 Mesh 和标记。 |
| `PathHoverPreview.advance_visual_time` | `(real_delta: float) -> void` | 以真实时间推进所有标记，暂停时仍可独立运行。 |
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
- 每条路径的首格必须等于所选 `spawn_point.cell`，末格必须等于所选 `target_base.cell`；路径不得在终点前经过其他据点。
- 多条路径可共用出生点或据点。波次中 `SpawnGroup.path` 是选择事实源，出生点由路径派生；敌人出生后的目标据点不可转换。
- 路径页与波次页的路径选项统一使用 `display_name [path_id]`，禁止用子资源的 `resource_path` 或所属关卡文件名作为标签。
- PathDefinition / SpawnPointDefinition 必须由 LevelResource 持有；SpawnGroup 只能引用本关对象。
- 路径首格和 `base_cell` 是屏障保护格；中间路径格只允许屏障类建筑，普通塔不得占路。
- 运行时名称不能使用 `get_path()`，该名称被 Godot Node 保留；统一使用 `get_path_definition()`。

## 已知限制 / 初版不做的部分

- 自动 A* 不在全地图自由地形上行走；其可通行图只是“所有目标为同一据点的手工路径格”并集。
- 旧关卡的出生点和 `base_cell` 只读兼容；若候选出生点不唯一，校验会拒绝猜测。编辑器加载不会自动改写旧资源，用户首次编辑据点时才物化显式 `base_points`。
