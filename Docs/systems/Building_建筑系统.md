# 建筑系统 · Building

> 实现状态：M3 已完成箭塔、激光塔、三级完整参数、放置虚影、升级、独立索敌/攻击范围、逐级外观与逐级资源产出。

## 职责

定义可放置防御建筑，用 `BuildingDefinition + BuildingLevelStats` 组合塔种身份和每级完整参数。`BuildingManager` 是放置、预览、升级、占用、选择和移除的唯一入口。

## 分类 / 做法

- **三级参数**：建筑初始 1 级、上限 3 级。`levels[0..2]` 分别保存 1~3 级的完整经济、战斗、投射物和表现参数；升级直接切换到下一份参数，不把上一等级参数乘算后继承。
- **伤害公式**：单发伤害为当前级 `base_damage × level_factor × extra_factor`；持续伤害为当前级 `laser_dps × level_factor × extra_factor × delta`。`level_factor` 是当前建筑等级数据的一部分，不是全局等级曲线。
- **箭塔**：在 `targeting_range` 内选择目标，只在目标进入 `attack_range` 后发射投射物；伤害在投射物命中时结算，发射时不扣血。
- **激光塔**：不索敌，沿世界固定朝向在 `attack_range` 内持续命中线段上的全部目标，按帧结算 DPS。
- **放置预览**：建造模式悬停可建造空格时创建不占格、不攻击的 1 级半透明建筑；预览保留塔种和朝向，R 旋转虚影，左键放置时继承该朝向。
- **无效格信息**：未选择塔种或当前格不可放置时不创建虚影；Main HUD 显示地块类型、高度、障碍/占用对象和占位建筑等级、索敌范围、射程。
- **美术替换**：每一级可指定 `visual_scene: PackedScene`。未指定时使用该级 `tower_color` 生成灰盒塔；`attack_color` 控制方向标记、箭/激光颜色。
- **资源产出**：每一级独立配置 `resource_per_second`；放置、升级或移除后，BuildingManager 汇总当前所有建筑的当前级产出并同步到 ResourceManager。
- **放置事务**：依次校验定义、边界、`TileManager.can_place()`、建筑上限和资源。占格或扣费失败会回滚，不留下半放置建筑。
- **离散朝向**：HEX 为 6 档、每档 60 度；SQUARE 为 8 档、每档 45 度。方向只取决于 Grid 形状和 `facing_index`，不读取相机 yaw。

## 参数编辑入口

在 Godot 检视面板打开：

- `resources/buildings/ArrowTower.tres`
- `resources/buildings/LaserTower.tres`

展开 `Levels` 数组中的三个 `BuildingLevelStats`。数组第 0/1/2 项对应建筑 1/2/3 级。

| 分组 | 参数 | 说明 |
|---|---|---|
| Economy | `cost` | 1 级为建造费用；2、3 级为升到该级的费用。 |
| Economy | `resource_per_second` | 该建筑处于本级时每秒提供的资源。 |
| Combat | `base_damage` | 单发攻击的基础伤害。 |
| Combat | `targeting_range` | 索敌候选半径，单位为格。 |
| Combat | `attack_range` | 允许发射/激光长度，单位为格，与索敌范围独立。 |
| Combat | `attacks_per_second` | 单发攻击频率。 |
| Combat | `laser_dps` | 持续攻击的基础每秒伤害。 |
| Combat | `level_factor` | 本级独立等级伤害因子。 |
| Combat | `extra_factor` | 其它伤害乘区预留。 |
| Combat | `target_priority` | 最近、最远、最高血、最低血、最快、首个进入、锁定。 |
| Projectile | `projectile_speed` | 单发投射物速度，单位为格/秒。 |
| Projectile | `projectile_length` | 短直线投射物长度，运行时下限 0.1，不会缩成点。 |
| Projectile | `projectile_width` | 投射物宽度。 |
| Presentation | `visual_scene` | 本级外观场景接口；根节点应为 Node3D。 |
| Presentation | `tower_color` | 无外观场景时的塔体颜色。 |
| Presentation | `attack_color` | 投射物、激光和方向标记颜色。 |

`Building` 另有灰盒尺寸和 `preview_alpha`；它们是通用表现参数，不参与单级平衡。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/building/BuildingLevelStats.gd` | `BuildingLevelStats` / `Resource` | 一项建筑等级的完整可编辑参数。 |
| `scripts/building/BuildingDefinition.gd` | `BuildingDefinition` / `Resource` | 塔种身份、显示名和最多三项等级数据。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 当前级运行时实体；装配策略、外观、朝向、投射物发射和预览状态。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | **建筑唯一入口**；放置事务、预览、升级、占用、选择、旋转、移除和产出汇总。 |
| `resources/buildings/ArrowTower.tres` | `BuildingDefinition` | 箭塔三等级参数。 |
| `resources/buildings/LaserTower.tres` | `BuildingDefinition` | 激光塔三等级参数。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 单目标冷却、射程校验和投射物发射。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定方向线段、穿透查询与持续伤害。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 恒定短直线表现、追踪飞行、最大距离与命中结算。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 建造模式、升级按钮、预览/错误状态和经济摘要。 |

### 模块调用关系 / 数据流

```text
M3DebugPanel 建造模式 + Main 鼠标悬停
  -> BuildingManager.update_preview(cell, definition)
  -> valid: preview Building(level=1, preview=true), no Tile occupant
  -> invalid: clear ghost; Main HUD reads Tile/occupant information

Main 左键
  -> BuildingManager.place_building(cell, definition, preview_facing)
     -> TileManager.can_place / place_occupant
     -> ResourceManager.try_register_building(level_1.cost)
     -> Building.configure(..., initial_level=1)

M3DebugPanel 升级
  -> BuildingManager.upgrade_selected
     -> spend(next_level.cost)
     -> Building.apply_level(next_level)
     -> sync sum(Building.current_stats.resource_per_second)

Arrow Building._process
  -> acquire in targeting_range
  -> verify attack_range
  -> CombatManager.spawn_projectile
  -> Projectile impact -> CombatTarget.take_damage

Laser Building._process
  -> fixed facing segment of attack_range
  -> all touched CombatTarget.take_damage(final_dps * delta)
```

## 函数索引

### BuildingDefinition / BuildingLevelStats

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_level_stats` | `(value: int) -> BuildingLevelStats` | 把等级钳制到已配置范围并返回对应完整参数。 |
| `get_max_level` | `() -> int` | 返回 `min(3, levels.size())`。 |
| `is_configured` | `() -> bool` | 至少存在有效 1 级参数时返回 true。 |

### Building.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(definition: BuildingDefinition, cell: Vector3i, grid: GridManager, tiles: TileManager, combat: CombatManager, initial_level: int = 1, preview_mode: bool = false) -> void` | 注入依赖、定位并应用初始等级；预览模式禁用攻击。 |
| `apply_level` | `(value: int) -> bool` | 切换整套等级参数，重建策略与外观。 |
| `can_upgrade` / `get_upgrade_cost` | `() -> bool` / `() -> float` | 判断是否未到上限并读取下一等级费用。 |
| `get_level_stats` | `() -> BuildingLevelStats` | 返回当前级参数事实源。 |
| `acquire_target` | `() -> CombatTarget` | 在当前级索敌范围内按优先级更新锁定目标。 |
| `is_target_in_attack_range` | `(target: CombatTarget) -> bool` | 用独立攻击范围判断目标是否可发射。 |
| `get_targeting_range_world` / `get_attack_range_world` | `() -> float` | 把格数范围转换为世界距离。 |
| `get_instant_damage` / `get_laser_damage_per_second` | `() -> float` | 用当前级三个乘区返回单发伤害或最终 DPS。 |
| `launch_projectile` | `(target: CombatTarget, damage: float) -> Projectile` | 用当前级速度/尺寸/颜色通过 CombatManager 发射。 |
| `rotate_facing` / `set_facing_index` | `(step: int = 1) -> void` / `(value: int) -> void` | 更新世界固定离散朝向。 |
| `shutdown` | `() -> void` | 停止策略并清理锁定。 |

### BuildingManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(grid: GridManager, tiles: TileManager, resources: ResourceManager, combat: CombatManager) -> void` | 注入模块入口，并深度刷新 `.tres` 等级资源缓存。 |
| `place_building` | `(cell: Vector3i, definition: BuildingDefinition, placement_facing: int = -1) -> Building` | 原子放置 1 级建筑并可继承预览朝向。 |
| `upgrade_selected` | `() -> bool` | 升级当前选择。 |
| `upgrade_building` | `(building: Building) -> bool` | 扣下一等级费用、切换完整参数；失败回滚费用。 |
| `update_preview` | `(cell: Vector3i, definition: BuildingDefinition) -> bool` | 在可建造空格创建/更新不占格虚影。 |
| `clear_preview` | `(clear_definition: bool = true) -> void` | 清理虚影；可保留塔种/朝向供跨无效格移动。 |
| `rotate_preview` | `(step: int = 1) -> bool` | 旋转当前虚影。 |
| `remove_building` | `(cell: Vector3i, refund: float = 0.0) -> bool` | 释放占格、计数与建筑产出后销毁建筑。 |
| `clear_buildings` | `(update_resource_count: bool = true) -> void` | 切关时清理全部建筑和预览。 |
| `select_at` / `rotate_selected` | `(cell: Vector3i) -> Building` / `(step: int = 1) -> bool` | 选择或旋转实际建筑。 |
| `_sync_building_income` | `() -> void` | 汇总所有当前级 `resource_per_second`。 |

**信号**：`building_placed`、`building_removed`、`building_selected`、`building_upgraded`、`placement_failed`、`upgrade_failed`、`preview_updated`、`preview_cleared`；Building.`level_changed` / `facing_changed` / `attack_performed`。

## 约定事实源

- 建筑空间唯一键是 Grid `Vector3i cell`；占用事实源是 TileManager。
- 当前等级事实源是 `Building.level + Building._stats`；禁止把等级差写成隐式全局倍率。
- 1 级 `cost` 是建造费用，2/3 级 `cost` 是升到该级的费用。
- `targeting_range` 只决定候选；`attack_range` 决定是否能发射或激光长度，两者不得互相代替。
- `BuildingDefinition.Kind` 固定为 `ARROW_TOWER=0`、`LASER_TOWER=1`。
- HEX 档 0 为世界 -30 度，随后每档 +60 度；SQUARE 档 0 为 +X，随后每档 +45 度。

## 使用入口

运行 `scenes/Main.tscn`：右上 M3 面板选择箭塔/激光塔，移动鼠标查看虚影，R 调整预览朝向，左键放置；切回“选择”点击建筑后可查看参数、旋转或点击“升级”。

## 已知限制 / 初版不做的部分

- 当前正式美术为空时使用逐级颜色灰盒；`visual_scene` 已预留，但资产制作与动画不属于 M3。
- 暂无售卖、分支升级树或降级。
- 投影镜像与 ICopyable 在 M5 接入；M6 再加入地形/障碍/镜面光路阻挡。
