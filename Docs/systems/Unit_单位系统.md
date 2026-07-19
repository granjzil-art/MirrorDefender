# 单位系统 · Unit

> 实现状态：M4 已完成敌人数值定义、固定路径移动、屏障攻击状态、近战/远程攻击、护甲、据点伤害和死亡资源掉落。

## 职责

定义敌方进攻单位的可编辑数值与运行时行为。EnemyUnit 继承 CombatTarget 供我方建筑索敌；它沿 WaveManager 注入的路径移动，查询前方第一个屏障，进入射程后停止并通过敌方攻击策略攻击，路径畅通后继续前进。

## 分类 / 做法

- **敌人定义**：EnemyDefinition 在 Inspector 配置生命、移速、护甲、据点伤害、掉落、攻击伤害、攻速、射程、投射物和灰盒颜色。
- **固定路径移动**：EnemyUnit 同时接收 `PackedVector3Array` 世界点和 `Array[Vector3i]` 路径格；前者驱动移动，后者按顺序查询前方屏障。
- **路径阻挡**：阻挡查询是 Main 注入的 `Callable(BuildingManager.get_path_blocker)`。Unit 不导入 Building 类型，只依赖 `is_structure_alive/get_structure_target_position/take_structure_damage` 方法契约。
- **攻击状态**：前方第一个屏障进入 `attack_range` 后，近战和远程敌人都停止移动；屏障移除后立即退出攻击状态并继续原路径。
- **近战**：`projectile_speed = 0` 时由 EnemyAttackStrategy 按 `attacks_per_second` 直接调用结构承伤接口。
- **远程**：`projectile_speed > 0` 时生成 EnemyProjectile；投射物在命中仍存活屏障时结算伤害。弓箭手是测试资源。
- **受击**：先以 `max(0, incoming - armor)` 固定减伤，再交给 CombatTarget 扣血。屏障反伤也走该入口，因此可击杀敌人并正常掉落资源。
- **据点到达**：无屏障阻挡并抵达末点后触发 `reached_base`；WaveManager 调 BaseCore 扣血，单位不产生死亡掉落。

## 参数编辑入口

在 `resources/enemies/*.tres` 编辑敌人。当前示例：`Grunt.tres`、`Runner.tres`、`Archer.tres`。

| 分组 | 参数 | 说明 |
|---|---|---|
| Identity | `enemy_id` / `display_name` | 稳定标识与编辑器显示名。 |
| Stats | `max_hp` / `move_speed` / `armor` | 最大生命、路径移动速度、单次固定减伤。 |
| Stats | `base_damage` | 抵达据点时造成的伤害，不是攻击屏障的伤害。 |
| Stats | `reward` / `hit_radius` | 被击杀掉落资源 / 我方攻击命中半径。 |
| Attack | `attack_damage` | 每次对屏障造成的原始伤害。 |
| Attack | `attacks_per_second` | 每秒攻击次数。 |
| Attack | `attack_range` | 攻击射程，单位为格；生成时乘本关 `grid_cell_size`。 |
| Attack | `projectile_speed` | 0 为即时近战；大于 0 时为敌方投射物速度（格/秒）。 |
| Attack | `projectile_length` / `projectile_width` | 远程投射物短直线尺寸。 |
| Presentation | `visual_scene` / `body_color` / `body_height` | 美术替换接口与灰盒身体表现。 |
| Presentation | `attack_color` | 敌方投射物颜色。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/unit/EnemyDefinition.gd` | `EnemyDefinition` / `Resource` | 每种敌人的完整移动、攻击和表现参数。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | 路径移动、阻挡查询、攻击状态、护甲和据点到达。 |
| `scripts/unit/BaseCore.gd` | `BaseCore` / `Node3D` | 据点生命、地块占用、灰盒和失败信号。 |
| `scripts/combat/EnemyAttackStrategy.gd` | `EnemyAttackStrategy` / `IAttackStrategy` | 敌人攻击冷却和近战/投射物触发。 |
| `scripts/combat/EnemyProjectile.gd` | `EnemyProjectile` / `Node3D` | 追踪屏障、短直线表现和命中结算。 |
| `resources/enemies/Grunt.tres` | `EnemyDefinition` | 近战步兵示例。 |
| `resources/enemies/Runner.tres` | `EnemyDefinition` | 高频近战疾行者示例。 |
| `resources/enemies/Archer.tres` | `EnemyDefinition` | 3.2 格射程的远程弓箭手示例。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | 注入路径格/点和阻挡查询，生成单位并处理奖励/据点。 |

### 数据流

```text
SpawnGroup.enemy + PathDefinition.cells
  -> WaveManager._spawn_group_unit
  -> PathManager.get_world_points + BuildingManager blocker Callable
  -> EnemyUnit.configure_unit -> CombatManager.register_target

EnemyUnit._process
  -> scan remaining path cells through blocker Callable
  -> outside range: move without crossing attack-range boundary
  -> inside range: stop -> EnemyAttackStrategy
       ├─ melee -> blocker.take_structure_damage
       └─ ranged -> EnemyProjectile -> take_structure_damage
  -> blocker removed -> continue path

Building / Projectile / Laser / barrier reflection -> EnemyUnit.take_damage
  -> armor -> CombatTarget.died -> WaveManager -> enemy reward

EnemyUnit final point -> reached_base -> WaveManager -> BaseCore.take_damage
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyUnit.configure_unit` | `(enemy_definition: EnemyDefinition, path_points: PackedVector3Array, path_cells: Array[Vector3i] = [], grid_cell_size: float = 1.0, blocker_resolver: Callable = Callable()) -> void` | 在入树前装配数值、路径、射程换算和阻挡接口。 |
| `EnemyUnit._process` | `(delta: float) -> void` | 查询前方屏障，在移动/攻击状态间切换；攻击时不移动。 |
| `EnemyUnit.is_attacking` | `() -> bool` | 当前屏障有效且仍在射程内时返回 true。 |
| `EnemyUnit.get_attack_target` | `() -> Node` | 返回策略可攻击的当前屏障或 null。 |
| `EnemyUnit.perform_attack` | `(target: Node) -> void` | 根据 `projectile_speed` 选择即时近战或 EnemyProjectile。 |
| `EnemyUnit.take_damage` | `(amount: float) -> float` | 应用固定护甲并返回实际伤害。 |
| `EnemyUnit._find_first_path_blocker` | `() -> Node` | 从下一路径格向据点扫描第一个仍存活屏障。 |
| `BaseCore.configure` | `(grid_manager: GridManager, tile_manager: TileManager) -> void` | 注入位置和占用接口。 |
| `BaseCore.load_level` | `(level_resource: LevelResource) -> void` | 放置据点、占用据点格并重置生命。 |
| `BaseCore.take_damage` | `(amount: float) -> float` | 扣据点生命，归零时广播 `defeated`。 |

**信号**：EnemyUnit.`attack_started` / `attack_stopped` / `attack_performed` / `projectile_spawned` / `reached_base`；BaseCore.`health_changed` / `defeated`；继承 CombatTarget.`health_changed` / `died`。

## 约定事实源

- EnemyDefinition 是敌人数值事实源；EnemyUnit 是运行时生命、位置、路径进度和攻击状态事实源。
- `base_damage` 只伤害据点；`attack_damage` 只用于攻击路径屏障，两者禁止混用。
- `attack_range` 以格为单位，EnemyUnit 生成时固定换算为当前关卡世界距离。
- PathDefinition 顺序决定“前方”；敌人只攻击尚未经过路径格上的第一个屏障，不绕路、不回头。
- PathManager 路径点、EnemyUnit 和动态建筑共用 Main 局部坐标空间。
- `reward` 只在敌人被击杀时入账；抵达据点消失不掉资源。

## 已知限制 / 初版不做的部分

- 不做自动寻路、绕障、飞行层、仇恨选建筑、技能、群体队形或对象池。
- 敌人当前只攻击路径屏障，不主动攻击路外塔；远程投射物为追踪直线，不做抛物线。
- 护甲为单次固定减伤，不做百分比、穿甲或抗性类型。
