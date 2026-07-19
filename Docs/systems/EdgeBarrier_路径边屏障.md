# 路径边屏障 · Directional Edge Barrier

## 职责

在不改变静态路径和地块占用的前提下，为路径的某一条物理边提供有方向的可摧毁阻挡。边屏障只影响沿其 `from_cell -> to_cell` 前进的敌人；其他路径和反向穿越同一物理边的敌人不受影响。

## 分类 / 放置规则

- `BuildingDefinition.Kind.EDGE_BARRIER` 是边屏障身份；`PlacementSurface.PATH_EDGE` 是可扩展的边放置规则。现有地块屏障继续使用 `BARRIER + PATH_TILE`。
- 六边形关卡有 6 个可选边方向；正方形关卡有 4 个可选边方向。普通地块建筑仍分别为 6 向与 8 向。
- 鼠标所处格是 `from_cell`，所选边的邻格是 `to_cell`。只有当前关卡路径确实包含该有向相邻段时才允许放置。
- 一个 `canonical_edge_id` 只允许一个边建筑；反向使用同一物理边时仍不能重复占位，但现有边屏障不会阻挡反向敌人。
- 地图边界、出生点或据点相邻边、已有边建筑，以及敌人当前占据的相邻格均拒绝放置。
- 边屏障在放置时按边中点定位、沿边对齐，并用顶部短标记指向被阻挡的 `to_cell`；放置后旋转按钮置灰。删除、升级、费用、退款、耐久、脱战回血、反伤与地块屏障共用同一流程。

## 关键参数

参数入口为 `resources/buildings/EdgeBarrier.tres` 的 `levels[0..2]`：

| 分组 | 参数 | 说明 |
|---|---|---|
| Economy | `cost` / `refund_amount` / `resource_per_second` | 建造或升级费用、当前级删除退款、每秒资源。 |
| Defense | `max_durability` | 当前等级最大耐久；升级增加最大值并保留已有损伤。 |
| Defense | `regeneration_delay` / `regeneration_per_second` | 脱战等待时间与每秒回血。 |
| Defense | `damage_reflection_ratio` | 对攻击者反伤比例，范围 0..1。 |
| Presentation | `visual_scene` / `tower_color` | 可替换外观与默认灰盒颜色。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/building/BuildingDefinition.gd` | `BuildingDefinition` / `Resource` | 定义建筑身份、放置表面与逐级参数入口。 |
| `scripts/building/BuildingPlacementRules.gd` | `BuildingPlacementRules` / `RefCounted` | 缓存路径格、有向路径边和保护格，集中校验地块/边放置。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 保存边两端、边索引和物理边键；复用耐久与表现。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | 原子建造、物理边占用、预览、选择、升级、删除和阻挡查询入口。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | 逐有向路径段查询阻挡，并沿折线路径移动到攻击射程。 |
| `scripts/combat/EnemyAttackStrategy.gd` | `EnemyAttackStrategy` / `IAttackStrategy` | 仅在攻击或投射物创建成功后写入冷却。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 提供“边障”模式与方向/耐久状态。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 边建筑保留删除/升级并禁用旋转。 |
| `resources/buildings/EdgeBarrier.tres` | `BuildingDefinition` | 默认三级边屏障数值。 |
| `tests/directional_edge_barrier_test.gd` | `SceneTree` | 形状、占位、方向、生命周期和敌人联调回归。 |

### 模块调用与数据流

```text
LevelResource.paths
  -> BuildingPlacementRules.rebuild_level_cache
  -> directed_edge_id(from, to) 有向规则

Main edge pick + “边障”模式
  -> BuildingManager.update_edge_preview / place_edge_building
  -> BuildingPlacementRules.validate_edge
  -> canonical_edge_id 物理占位 + ResourceManager 建筑事务

WaveManager
  -> EnemyUnit(path cells + BuildingManager.resolve_path_blocker Callable)
  -> 每段 resolve_path_blocker(from, to)
       ├─ 同向边屏障
       └─ 该段终点的地块屏障
  -> 进入射程后 EnemyAttackStrategy -> 结构承伤接口
```

### 约定事实源

- `canonical_edge_id` 是方向无关的物理占位事实源；`directed_edge_id(from_cell, to_cell)` 是方向相关的玩法判定事实源，两者不可互换。
- 边屏障的阻挡方向由放置时的鼠标所在格决定，放置后固定；`Building.cell` 是 `from_cell`，`edge_to_cell` 是 `to_cell`。
- 若两条路径共享完全相同的有向段，两条路径都会受同一边屏障影响；仅经过邻近格或另一条边的路径不受影响。
- EnemyUnit 不导入 Building 类型，只调用注入的解析器及 `is_structure_alive/get_structure_target_position/take_structure_damage` 结构契约。

## 函数索引

| 文件 | 函数签名 | 职责 |
|---|---|---|
| `BuildingPlacementRules.gd` | `configure(grid_manager: GridManager, tile_manager: TileManager, resource_manager: ResourceManager, combat_manager: CombatManager) -> void` | 注入只读校验依赖。 |
| `BuildingPlacementRules.gd` | `rebuild_level_cache(level_resource: LevelResource) -> void` | 从关卡重建路径格、有向路径边与保护格缓存。 |
| `BuildingPlacementRules.gd` | `validate_tile(cell: Vector3i, definition: BuildingDefinition, check_economy: bool = true) -> String` | 返回地块放置失败原因，空串表示允许。 |
| `BuildingPlacementRules.gd` | `validate_edge(from_cell: Vector3i, placement_edge_index: int, definition: BuildingDefinition, edge_building_resolver: Callable, check_economy: bool = true) -> Dictionary` | 返回 `{failure: String, to_cell: Vector3i, edge_id: String}`。 |
| `Building.gd` | `configure_edge(building_definition: BuildingDefinition, from_cell: Vector3i, to_cell: Vector3i, placement_edge_index: int, placement_edge_id: String, grid_manager: GridManager, tile_manager: TileManager, combat_manager: CombatManager, initial_level: int = 1, preview_mode: bool = false) -> void` | 在共享建筑运行时上装配边位置和方向。 |
| `Building.gd` | `is_edge_placement() -> bool` | 判断当前建筑是否有效绑定物理边。 |
| `Building.gd` | `matches_directed_edge(from_cell: Vector3i, to_cell: Vector3i) -> bool` | 精确匹配阻挡方向。 |
| `Building.gd` | `can_rotate_in_place() -> bool` | 边建筑返回 false，地块建筑返回 true。 |
| `BuildingManager.gd` | `place_edge_building(from_cell: Vector3i, placement_edge_index: int, definition: BuildingDefinition) -> Building` | 原子放置边建筑，失败返回 null。 |
| `BuildingManager.gd` | `update_edge_preview(from_cell: Vector3i, placement_edge_index: int, definition: BuildingDefinition) -> bool` | 创建贴边且不占位的合法预览。 |
| `BuildingManager.gd` | `get_edge_building(edge_id: String) -> Building` | 按物理边唯一键读取边建筑。 |
| `BuildingManager.gd` | `resolve_path_blocker(from_cell: Vector3i, to_cell: Vector3i) -> Node` | 先查同向边屏障，再查终点地块屏障。 |

## 使用入口

运行 `scenes/Main.tscn`，在右上建筑面板选择“边障”。把鼠标放在路径前进方向一侧的格内并靠近目标边：合法时显示贴边蓝色虚影，左键建造。选择已建边屏障后可删除或升级，旋转按钮会置灰。

## 已知限制

- 当前没有路径 ID 级的阻挡白名单；共享同一有向格段的路径共同受阻。
- 当前边屏障不参与自动寻路，敌人会停下攻击，摧毁后继续原路线。
- 高低地块交界处使用相邻两格较高地面作为灰盒底高，正式美术需自行处理墙脚衔接。
