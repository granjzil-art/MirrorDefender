# 索敌与战斗 · Combat

> 实现状态：M3 已完成统一伤害公式、七种索敌优先级、独立索敌/攻击范围、标准投射物单发攻击和穿透线段持续伤害。

## 职责

管理可受击目标、空间候选查询、攻击策略、投射物生命周期和统一伤害计算；不包含 M4 的波次、路径和敌人掉落配置。

## 分类 / 做法

- **统一公式**：`DamageCalculator.compute(base, level_factor, extra_factor)`，三个乘区均取非负值。
- **单发伤害**：读取当前级 `base_damage`，发射前计算最终伤害，但只在 Projectile 命中存活目标时调用 `take_damage()`。飞行期间目标不掉血。
- **持续伤害**：读取当前级 `laser_dps`，每帧对射线段中的全部目标结算 `final_dps × delta`。
- **索敌范围**：箭塔仅从 `targeting_range` 内建立候选并应用优先级。
- **攻击范围**：所选目标必须在独立的 `attack_range` 内才会发射；投射物最大飞行距离也使用该范围。激光用它作为线段长度。
- **投射物表现**：Projectile 使用固定尺寸 BoxMesh 形成短直线，朝飞行方向旋转；飞近目标时不缩短，所以不会退化成点。
- **投射物跟踪**：目标存活时刷新目标位置；目标失效后飞向最后位置并在最大距离处销毁，不对失效目标结算伤害。
- **索敌优先级**：最近、最远、最高血、最低血、最快、首个进入、锁定；锁定失效后回退到最近。
- **M3 靶标**：CombatTarget 提供生命、速度、奖励、命中半径和灰盒表现；`reward` 只随 `target_killed` 广播，M3 不兑换资源，M4 再连接掉落配置。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| CombatManager | `laser_hit_radius` | 激光线段额外命中半径。 |
| CombatTarget | `max_hp` / `move_speed` / `hit_radius` | 生命、最快索敌值和碰撞半径。 |
| BuildingLevelStats | `base_damage` / `laser_dps` | 当前级单发基础伤害 / 持续基础 DPS。 |
| BuildingLevelStats | `level_factor` / `extra_factor` | 当前级等级乘区 / 其它乘区。 |
| BuildingLevelStats | `targeting_range` / `attack_range` | 独立的候选半径 / 发射或激光范围。 |
| BuildingLevelStats | `attacks_per_second` | 单发冷却频率。 |
| BuildingLevelStats | `projectile_speed` | 投射物格/秒速度。 |
| BuildingLevelStats | `projectile_length` / `projectile_width` | 恒定短直线尺寸。 |
| BuildingLevelStats | `target_priority` | 七种索敌优先级枚举。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/combat/DamageCalculator.gd` | `DamageCalculator` / `RefCounted` | 无状态伤害公式。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 可受击目标契约、生命/死亡信号和 M3 靶标。 |
| `scripts/combat/CombatManager.gd` | `CombatManager` / `Node3D` | **战斗唯一入口**；目标注册、范围/线段查询和投射物管理。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 单发攻击的飞行、短直线表现、距离截止和命中结算。 |
| `scripts/combat/ITargetingStrategy.gd` | `ITargetingStrategy` / `RefCounted` | 索敌策略接口。 |
| `scripts/combat/PriorityTargetingStrategy.gd` | `PriorityTargetingStrategy` / `ITargetingStrategy` | 七种优先级实现。 |
| `scripts/combat/IAttackStrategy.gd` | `IAttackStrategy` / `RefCounted` | 攻击逐帧执行/重置接口。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 目标获取、独立射程检查、冷却和投射物发射。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定射线穿透与持续伤害。 |

### 模块调用关系 / 数据流

```text
M3 debug target / future M4 Unit -> CombatManager.register_target

Arrow Building
  -> CombatManager.get_targets_in_range(targeting_range)
  -> ITargetingStrategy.select_target
  -> Building.is_target_in_attack_range(attack_range)
  -> DamageCalculator.compute
  -> CombatManager.spawn_projectile
  -> Projectile flies with constant short-line mesh
  -> impact -> CombatTarget.take_damage -> projectile_hit / attack_performed

Laser Building facing
  -> segment(start, start + facing * attack_range)
  -> CombatManager.get_targets_on_segment
  -> each target.take_damage(final_dps * delta)

CombatTarget.died -> CombatManager.target_killed(reward)
  -> M4 enemy/drop system will call ResourceManager.grant_enemy_drop
```

## 函数索引

### DamageCalculator / CombatTarget

| 函数 | 签名 | 职责 |
|---|---|---|
| `DamageCalculator.compute` | `(base_damage: float, level_factor: float, extra_factor: float) -> float` | 返回三个非负乘区之积。 |
| `CombatTarget.take_damage` | `(amount: float) -> float` | 扣除生命，返回实际伤害，并在归零时发 `died`。 |
| `CombatTarget.is_alive` | `() -> bool` | 排除死亡和待释放目标。 |
| `CombatTarget.get_target_position` | `() -> Vector3` | 返回投射物使用的目标点。 |

### CombatManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `register_target` | `(target: CombatTarget) -> bool` | 分配进入序号、订阅死亡并加入候选。 |
| `unregister_target` | `(target: CombatTarget) -> void` | 从候选移除并广播。 |
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

**信号**：CombatTarget.`health_changed` / `died`；CombatManager.`target_registered` / `target_removed` / `target_killed` / `projectile_spawned` / `projectile_hit`；Projectile.`impacted`。

## 约定事实源

- 当前建筑等级数据是伤害、范围、攻速和投射物参数的唯一事实源。
- `targeting_range` 不代表可攻击；`attack_range` 不负责生成候选。
- 单发攻击的逻辑命中时刻与视觉投射物命中时刻一致。
- 激光命中在 XZ 平面计算；M6 再加入地形、障碍和镜面阻挡。
- CombatManager 不生成正式敌人，也不直接修改资源。

## 已知限制 / 初版不做的部分

- M3 靶标静止；移动、护甲、路径、据点伤害与敌人个体掉落属于 M4。
- 投射物当前追踪目标，无加速度、抛物线、范围爆炸或对象池；正式大量单位阶段需评估池化。
- 不做克制、暴击、闪避、DOT 叠层或衰减。
