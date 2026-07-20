# 索敌与战斗 · Combat

> 实现状态：已完成我方索敌/攻击策略、标准投射物与激光，以及敌人对路径屏障的冷却攻击和近战/远程投射物。

## 职责

管理可受击目标、空间候选查询、攻击策略、投射物生命周期和统一伤害计算；不管理波次或路径，但以 CombatTarget 契约服务 M4 EnemyUnit。

## 分类 / 做法

- **统一公式**：`DamageCalculator.compute(base, level_factor, extra_factor)`，三个乘区均取非负值。
- **单发伤害**：读取当前级 `base_damage`，发射前计算最终伤害，但只在 Projectile 命中存活目标时调用 `take_damage()`。飞行期间目标不掉血。
- **持续伤害**：读取当前级 `laser_dps`，每帧对射线段中的全部目标结算 `final_dps × delta`。
- **索敌范围**：箭塔仅从 `targeting_range` 内建立候选并应用优先级。
- **攻击范围**：所选目标必须在独立的 `attack_range` 内才会发射；投射物最大飞行距离也使用该范围。激光用它作为线段长度。
- **投射物表现**：Projectile 使用固定尺寸 BoxMesh 形成短直线，朝飞行方向旋转；飞近目标时不缩短，所以不会退化成点。
- **投射物跟踪**：目标存活时刷新目标位置；目标失效后飞向最后位置并在最大距离处销毁，不对失效目标结算伤害。
- **索敌优先级**：最近、最远、最高血、最低血、最快、首个进入、锁定；锁定失效后回退到最近。
- **目标实现**：CombatTarget 提供生命、速度、奖励、命中半径和灰盒表现；M3 靶标与 M4 EnemyUnit 都可注册。正式掉落不通过泛用 `target_killed`，而由 WaveManager 限定 EnemyUnit 的死亡信号结算。
- **空中目标过滤**：CombatTarget 用 `airborne` / `is_airborne_unit()` 暴露统一分类。每级建筑用 `affects_airborne` 决定是否接纳飞行目标；单体索敌、独立射程复核与激光线段结算使用同一过滤入口。
- **敌方攻击策略**：EnemyAttackStrategy 复用 IAttackStrategy 的 `tick/reset` 契约，只管理冷却；EnemyUnit 提供当前屏障目标和具体近战/远程执行入口。
- **敌方投射物**：EnemyProjectile 使用结构目标的动态方法契约，不把屏障注册进 CombatManager，避免我方塔误把我方建筑当敌人。攻击者或屏障失效时投射物自动清理。
- **目标生命周期**：CombatManager 对每个目标只保留一份死亡/离树回调；显式注销会先解除回调，因此同一对象可安全重新注册。外部 `queue_free()`、死亡和切关清理都汇入幂等注销；失效目标清理遍历稳定快照，允许 `target_removed` 监听者同步再次查询目标而不破坏迭代。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| CombatManager | `laser_hit_radius` | 激光线段额外命中半径。 |
| CombatTarget | `max_hp` / `move_speed` / `hit_radius` | 生命、最快索敌值和碰撞半径。 |
| CombatTarget | `airborne` | 运行时空中分类；EnemyUnit 从定义复制。 |
| BuildingLevelStats | `affects_airborne` | 当前等级的攻击、激光、屏障阻挡与反伤是否作用于飞行敌人；默认 true 兼容旧资源。 |
| BuildingLevelStats | `base_damage` / `laser_dps` | 当前级单发基础伤害 / 持续基础 DPS。 |
| BuildingLevelStats | `level_factor` / `extra_factor` | 当前级等级乘区 / 其它乘区。 |
| BuildingLevelStats | `targeting_range` / `attack_range` | 独立的候选半径 / 发射或激光范围。 |
| BuildingLevelStats | `attacks_per_second` | 单发冷却频率。 |
| BuildingLevelStats | `projectile_speed` | 投射物格/秒速度。 |
| BuildingLevelStats | `projectile_length` / `projectile_width` | 恒定短直线尺寸。 |
| BuildingLevelStats | `target_priority` | 七种索敌优先级枚举。 |
| EnemyDefinition | `attack_damage` / `attacks_per_second` / `attack_range` | 敌人攻击屏障的伤害、频率和格数射程。 |
| EnemyDefinition | `projectile_speed` / `projectile_length` / `projectile_width` | 0 为近战；正数及尺寸驱动 EnemyProjectile。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/combat/DamageCalculator.gd` | `DamageCalculator` / `RefCounted` | 无状态伤害公式。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 可受击目标契约、生命/死亡信号和 M3 靶标。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | M4 正式目标；附加护甲、路径移动和据点到达行为。 |
| `scripts/combat/CombatManager.gd` | `CombatManager` / `Node3D` | **战斗唯一入口**；目标注册、范围/线段查询和投射物管理。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 单发攻击的飞行、短直线表现、距离截止和命中结算。 |
| `scripts/combat/ITargetingStrategy.gd` | `ITargetingStrategy` / `RefCounted` | 索敌策略接口。 |
| `scripts/combat/PriorityTargetingStrategy.gd` | `PriorityTargetingStrategy` / `ITargetingStrategy` | 七种优先级实现。 |
| `scripts/combat/IAttackStrategy.gd` | `IAttackStrategy` / `RefCounted` | 攻击逐帧执行/重置接口。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 目标获取、独立射程检查、冷却和投射物发射。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定射线穿透与持续伤害。 |
| `scripts/combat/EnemyAttackStrategy.gd` | `EnemyAttackStrategy` / `IAttackStrategy` | 敌人攻击冷却和 `perform_attack` 调度。 |
| `scripts/combat/EnemyProjectile.gd` | `EnemyProjectile` / `Node3D` | 面向屏障方法契约的追踪投射物、表现与命中。 |

### 模块调用关系 / 数据流

```text
M3 debug target / M4 EnemyUnit -> CombatManager.register_target

Arrow Building
  -> CombatManager.get_targets_in_range(targeting_range)
  -> Building.affects_target filters airborne targets
  -> ITargetingStrategy.select_target
  -> Building.is_target_in_attack_range(attack_range)
  -> DamageCalculator.compute
  -> CombatManager.spawn_projectile
  -> Projectile flies with constant short-line mesh
  -> impact -> CombatTarget.take_damage -> projectile_hit / attack_performed

Laser Building facing
  -> segment(start, start + facing * attack_range)
  -> CombatManager.get_targets_on_segment
  -> Building.affects_target filters each touched target
  -> each target.take_damage(final_dps * delta)

CombatTarget.died -> CombatManager.target_killed(reward)
EnemyUnit.died -> WaveManager type check -> ResourceManager.grant_enemy_drop(reward)

EnemyUnit attack state -> EnemyAttackStrategy.tick
  -> projectile_speed == 0: blocker.take_structure_damage
  -> projectile_speed > 0: EnemyProjectile
       -> target/attacker alive check -> take_structure_damage(damage, attacker)
       -> barrier reflection -> EnemyUnit.take_damage
```

## 函数索引

### DamageCalculator / CombatTarget

| 函数 | 签名 | 职责 |
|---|---|---|
| `DamageCalculator.compute` | `(base_damage: float, level_factor: float, extra_factor: float) -> float` | 返回三个非负乘区之积。 |
| `CombatTarget.take_damage` | `(amount: float) -> float` | 扣除生命，返回实际伤害，并在归零时发 `died`。 |
| `CombatTarget.is_alive` | `() -> bool` | 排除死亡和待释放目标。 |
| `CombatTarget.is_airborne_unit` | `() -> bool` | 返回地块与建筑效果共用的空中分类。 |
| `CombatTarget.get_target_position` | `() -> Vector3` | 返回投射物使用的目标点。 |

### CombatManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `register_target` | `(target: CombatTarget) -> bool` | 分配进入序号、建立唯一死亡/离树回调并加入候选；重复注册返回 false。 |
| `unregister_target` | `(target: CombatTarget) -> void` | 幂等移除候选、解除生命周期回调并广播。 |
| `get_targets_in_range` | `(origin: Vector3, range_world: float) -> Array[CombatTarget]` | 按 XZ 距离返回范围候选。 |
| `get_targets_on_segment` | `(start: Vector3, end: Vector3) -> Array[CombatTarget]` | 用点到线段距离返回全部激光触碰目标。 |
| `spawn_projectile` | `(start: Vector3, target: CombatTarget, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color) -> Projectile` | 创建、配置并跟踪投射物。 |
| `spawn_debug_target` | `(world_position: Vector3) -> CombatTarget` | 生成并注册 M3 靶标。 |
| `clear_projectiles` | `() -> void` | 清理全部飞行投射物。 |
| `clear_targets` | `() -> void` | 切关时清空目标、投射物和进入序号。 |

### Projectile.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(start: Vector3, target: CombatTarget, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color) -> void` | 配置飞行、伤害、距离和恒定短直线外观。 |
| `_process` | `(delta: float) -> void` | 追踪/飞向最后目标点，处理命中和最大距离。 |
| `_impact` | `() -> void` | 仅对仍存活目标结算伤害并广播 `impacted`。 |

### EnemyAttackStrategy / EnemyProjectile

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyAttackStrategy.tick` | `(attacker: Node, delta: float) -> void` | 冷却到期时读取攻击者当前结构目标并调用 `perform_attack`。 |
| `EnemyAttackStrategy.reset` | `(attacker: Node) -> void` | 目标切换/离开攻击状态时允许下一次进入立即攻击。 |
| `EnemyProjectile.configure` | `(start: Vector3, target: Node, attacker: Node, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color) -> void` | 配置结构目标、攻击者、飞行和外观。 |
| `EnemyProjectile._process` | `(delta: float) -> void` | 仅在攻击者与屏障都有效时追踪飞行。 |
| `EnemyProjectile._impact` | `() -> void` | 调用屏障 `take_structure_damage` 并广播实际伤害。 |

**信号**：CombatTarget.`health_changed` / `died`；CombatManager.`target_registered` / `target_removed` / `target_killed` / `projectile_spawned` / `projectile_hit`；Projectile.`impacted`；EnemyProjectile.`impacted`。

## 约定事实源

- 当前建筑等级数据是伤害、范围、攻速和投射物参数的唯一事实源。
- `BuildingLevelStats.affects_airborne` 是当前等级对飞行敌人生效与否的唯一事实源；攻击策略不得各自维护空中白名单。
- `targeting_range` 不代表可攻击；`attack_range` 不负责生成候选。
- 单发攻击的逻辑命中时刻与视觉投射物命中时刻一致。
- 激光命中在 XZ 平面计算；M6 再加入地形、障碍和镜面阻挡。
- CombatManager 不生成正式敌人，也不直接修改资源；WaveManager 是 EnemyUnit 掉落的唯一资源桥接者。
- CombatManager 的 `_targets` 与其回调表必须同步增删；任何外部释放都由 `tree_exited` 回收，重新注册不得叠加旧回调。
- 屏障不是 CombatTarget，也不进入 CombatManager 敌对候选；EnemyProjectile 通过结构方法契约造成伤害。

## 已知限制 / 初版不做的部分

- M3 调试靶标仍静止；EnemyUnit 的移动、护甲、路径和据点伤害实现见 Unit、Path、Wave 文档。
- 投射物当前追踪目标，无加速度、抛物线、范围爆炸或对象池；正式大量单位阶段需评估池化。
- 不做克制、暴击、闪避、DOT 叠层或衰减。
