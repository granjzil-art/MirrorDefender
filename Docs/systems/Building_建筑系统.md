# 建筑系统 · Building

> 实现状态：M3 已完成箭塔、激光塔、资源/上限放置校验、地块占用、选择与世界固定 6/8 向旋转。

## 职责
定义可放置防御建筑，并用数据定义、索敌策略和攻击策略组合运行时行为。BuildingManager 是其它模块唯一使用的建筑入口。

## 分类 / 做法
- **箭塔**：按 BuildingDefinition 的索敌优先级选择范围内单个 CombatTarget；按攻击间隔结算一次 `base_damage × level_factor × extra_factor`。
- **激光塔**：不索敌，沿当前世界朝向持续显示固定长度射线；每帧查询整条线段上的全部目标并结算 `laser_dps × level_factor × extra_factor × delta`。建筑不参与光路阻挡。
- **资源定义**：箭塔和激光塔参数分别存于 `resources/buildings/*.tres`；运行时 Building 不复制平衡数值。
- **放置事务**：BuildingManager 依次校验边界、TileManager.can_place、建筑上限和资源；占格与 ResourceManager 注册任一步失败都会回滚，不产生半放置状态。
- **离散朝向**：R 调用 `rotate_selected()`。HEX 为 6 档，每档 60 度且垂直于对应边；SQUARE 为 8 档，每档 45 度。方向只由 Grid 形状与 `facing_index` 计算，不读取相机 yaw。

## 关键参数

| 归属 | 参数 | 箭塔 / 激光塔默认 | 说明 |
|---|---|---:|---|
| BuildingDefinition | `cost` | 75 / 120 | 建造所需主资源。 |
| BuildingDefinition | `base_damage` | 20 / 0 | 箭塔固定伤害项。 |
| BuildingDefinition | `attack_range` | 4 / 6 | 格数；运行时乘 Grid.cell_size。 |
| BuildingDefinition | `attacks_per_second` | 1 / 1 | 箭塔每秒攻击次数。 |
| BuildingDefinition | `laser_dps` | 0 / 30 | 激光每秒基础伤害。 |
| BuildingDefinition | `level_factor` / `extra_factor` | 1 / 1 | 统一伤害公式的两个乘区。 |
| BuildingDefinition | `target_priority` | 最近 | 七种索敌优先级枚举。 |
| BuildingDefinition | `produces_resource` | false | 生产建筑产出接口；当前两种塔均关闭。 |
| Building | `feature_enabled` | true | 单个建筑行为开关。 |
| Building | `tower_height_ratio` / `base_radius_ratio` | 0.75 / 0.24 | 灰盒塔体相对格距尺寸。 |
| Building | `direction_marker_ratio` / `attack_flash_duration` | 0.32 / 0.12 | 朝向标记长度、箭塔射击线持续时间。 |
| BuildingManager | `feature_enabled` | true | 建筑模块总开关。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/building/BuildingDefinition.gd` | `BuildingDefinition` / `Resource` | 塔种、价格、战斗因子、索敌优先级和颜色的数据定义。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 单塔运行时实体；组合索敌/攻击策略，维护格、朝向和灰盒表现。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | **建筑唯一入口**；放置事务、占用、选择、旋转、移除和切关清理。 |
| `resources/buildings/ArrowTower.tres` | `BuildingDefinition` | 箭塔默认平衡参数。 |
| `resources/buildings/LaserTower.tres` | `BuildingDefinition` | 激光塔默认平衡参数。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 冷却驱动的单目标瞬伤。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定方向线段、穿透查询与持续伤害。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | M3 灰盒塔型/靶标模式、资源和上限状态。 |

### 模块调用关系 / 数据流

```text
Main input -> M3DebugPanel mode
  -> BuildingManager.place_building(cell, definition)
       -> TileManager.can_place / place_occupant
       -> ResourceManager.can_add_building / try_register_building
       -> Building.configure(GridManager, TileManager, CombatManager)

Building._process
  -> PriorityTargetingStrategy + ArrowAttackStrategy -> CombatTarget.take_damage
  -> LaserAttackStrategy -> CombatManager.get_targets_on_segment -> all targets take_damage

R -> BuildingManager.rotate_selected -> Building.rotate_facing
TileManager.level_loaded -> BuildingManager.clear_buildings
```

Building 模块通过注入的 Manager 公共 API 工作；不直接读取 LevelResource、TileCellData 数组或相机状态。

## 函数索引

### Building.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(building_definition: BuildingDefinition, building_cell: Vector3i, grid_manager: GridManager, tile_manager: TileManager, combat_manager: CombatManager) -> void` | 注入定义和模块入口，定位塔体并装配攻击策略。 |
| `acquire_target` | `() -> CombatTarget` | 查询范围候选并按策略更新安全的锁定目标。 |
| `rotate_facing` | `(step: int = 1) -> void` | 按离散档位旋转。 |
| `set_facing_index` | `(value: int) -> void` | 环绕钳制档位、更新世界 yaw 并发 facing_changed。 |
| `get_facing_slot_count` | `() -> int` | HEX 返回 6，SQUARE 返回 8。 |
| `get_facing_direction` | `() -> Vector3` | 返回不依赖相机的世界 XZ 单位向量。 |
| `get_attack_origin` / `get_laser_end` | `() -> Vector3` | 返回射击起点和当前固定方向射线终点。 |
| `get_instant_damage` / `get_laser_damage_per_second` | `() -> float` | 通过 DamageCalculator 返回公式结果。 |
| `show_attack_line` | `(world_end: Vector3, persistent: bool) -> void` | 重建箭塔闪线或持续激光线。 |
| `notify_attack` | `(target: CombatTarget, damage: float, continuous: bool) -> void` | 广播实际造成的正伤害。 |
| `shutdown` | `() -> void` | 停止攻击并清理锁定与光线。 |

### BuildingManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(grid_manager: GridManager, tile_manager: TileManager, resource_manager: ResourceManager, combat_manager: CombatManager) -> void` | 注入四个公共模块入口并订阅切关信号。 |
| `place_building` | `(cell: Vector3i, definition: BuildingDefinition) -> Building` | 原子校验、占格、扣费并返回新建筑；失败返回 null。 |
| `remove_building` | `(cell: Vector3i, refund: float = 0.0) -> bool` | 释放占格/计数并销毁塔。 |
| `clear_buildings` | `(update_resource_count: bool = true) -> void` | 清理全部运行时建筑，供切关使用。 |
| `get_building` | `(cell: Vector3i) -> Building` | 返回该格建筑或 null。 |
| `get_buildings` | `() -> Array[Building]` | 返回当前有效建筑快照。 |
| `select_at` / `select_building` | `(cell: Vector3i) -> Building` / `(building: Building) -> void` | 更新当前选择并广播。 |
| `rotate_selected` | `(step: int = 1) -> bool` | 旋转当前选择；无选择返回 false。 |
| `get_definition` | `(kind: int) -> BuildingDefinition` | 返回主场景配置的箭塔或激光塔定义。 |
| `_validate_placement` | `(cell: Vector3i, definition: BuildingDefinition) -> String` | 返回空串或可显示的失败原因。 |

**信号**：`building_placed`、`building_removed`、`building_selected`、`placement_failed(cell, reason)`、Building.`facing_changed`、Building.`attack_performed`。

## 约定事实源
- 建筑空间唯一键是 Grid `Vector3i cell`，运行时占用事实源是 TileManager。
- `BuildingDefinition.Kind` 数值固定为 `ARROW_TOWER=0`、`LASER_TOWER=1`，与两份资源及调试面板一致。
- HEX 档 0 的世界方向角为 -30 度，之后每档 +60 度；SQUARE 档 0 为 +X，之后每档 +45 度。
- 建筑不阻挡激光；M6 光路系统接入后仍需保留此规则。

## 使用入口
运行 `scenes/Main.tscn`，在右上 M3 面板选择箭塔或激光塔，左键点击可建造格；切回“选择”后点塔，按 R 旋转。右键随时返回选择模式。

## 已知限制 / 初版不做的部分
- 当前为灰盒 Mesh 与线表现，不做弹道飞行、正式特效、升级树或售卖比例。
- 投影镜像与 ICopyable 在 M5 接入；当前建筑均为原件。
- 当前两种塔都不是生产建筑；ResourceManager 已提供 producer_count 入口。
