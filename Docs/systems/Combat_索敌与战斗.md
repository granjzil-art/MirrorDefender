# 索敌与战斗 · Combat

> 实现状态：M3 已完成统一伤害公式、七种索敌优先级、瞬伤、穿透线段持续伤害和可供 M4 单位注册的目标入口。

## 职责
管理可受击目标、空间候选查询、可替换索敌/攻击策略和统一伤害计算，不包含波次或路径行为。

## 分类 / 做法
- **伤害公式**：`DamageCalculator.compute(base, level_factor, extra_factor)`；三个乘区都不允许负数。
- **索敌策略**：最近、最远、最高血、最低血、最快、首个进入、锁定。锁定目标无效后回退到最近目标。
- **箭塔瞬伤**：ArrowAttackStrategy 按冷却获取一个目标，一次调用 `take_damage(final_damage)`。
- **激光持续伤害**：LaserAttackStrategy 每帧取得固定射线起止点，对 `get_targets_on_segment()` 返回的每个目标结算 `final_dps × delta`。
- **M3 靶标**：CombatTarget 提供生命、速度、奖励、命中半径和灰盒表现；M4 单位注册同一契约，不改变塔代码。

## 关键参数

| 归属 | 参数 | 默认 | 说明 |
|---|---|---:|---|
| CombatManager | `feature_enabled` | true | 战斗模块总开关。 |
| CombatManager | `laser_hit_radius` | 0.18 | 激光线段额外命中半径。 |
| CombatManager | `debug_target_hp` / `speed` / `reward` | 100 / 1 / 5 | M3 靶标参数。 |
| CombatTarget | `max_hp` | 100 | 最大/初始生命。 |
| CombatTarget | `move_speed` | 1 | fastest 策略读取值。 |
| CombatTarget | `reward` | 5 | 死亡时由 CombatManager 转为击杀产出信号。 |
| CombatTarget | `hit_radius` | 0.3 | 线段触碰半径。 |
| BuildingDefinition | `target_priority` | nearest | 七种策略枚举。 |
| BuildingDefinition | `base_damage` / `laser_dps` | 塔种定 | 瞬伤固定值或持续 DPS 固定值。 |
| BuildingDefinition | `level_factor` / `extra_factor` | 1 / 1 | 伤害公式乘区。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/combat/DamageCalculator.gd` | `DamageCalculator` / `RefCounted` | 无状态伤害公式。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 可受击目标契约、生命/死亡信号和 M3 靶标表现。 |
| `scripts/combat/CombatManager.gd` | `CombatManager` / `Node3D` | **战斗唯一入口**；目标注册、范围/线段查询、死亡奖励转发。 |
| `scripts/combat/ITargetingStrategy.gd` | `ITargetingStrategy` / `RefCounted` | 索敌策略接口。 |
| `scripts/combat/PriorityTargetingStrategy.gd` | `PriorityTargetingStrategy` / `ITargetingStrategy` | 七种优先级实现。 |
| `scripts/combat/IAttackStrategy.gd` | `IAttackStrategy` / `RefCounted` | 攻击逐帧执行/重置接口。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 单目标冷却与瞬伤。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定射线穿透与持续伤害。 |

### 模块调用关系 / 数据流

```text
M3 debug target / future M4 Unit -> CombatManager.register_target

Arrow Building -> get_targets_in_range -> ITargetingStrategy.select_target
  -> DamageCalculator.compute -> CombatTarget.take_damage once

Laser Building facing -> segment(start, end)
  -> CombatManager.get_targets_on_segment
  -> every touched CombatTarget.take_damage(dps * delta)

CombatTarget.died -> CombatManager.target_killed(reward)
  -> Main -> ResourceManager.grant_kill_drop
```

## 函数索引

### DamageCalculator / CombatTarget

| 函数 | 签名 | 职责 |
|---|---|---|
| `DamageCalculator.compute` | `(base_damage: float, level_factor: float, extra_factor: float) -> float` | 返回三个非负乘区之积。 |
| `CombatTarget.configure_debug_target` | `(world_position: Vector3, hp: float, speed: float, reward_amount: float) -> void` | 配置 M3 靶标。 |
| `CombatTarget.take_damage` | `(amount: float) -> float` | 扣除生命，返回实际伤害并在归零时发 died。 |
| `CombatTarget.is_alive` | `() -> bool` | 排除死亡和待释放目标。 |
| `CombatTarget.get_target_position` | `() -> Vector3` | 返回攻击表现使用的目标点。 |

### CombatManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `register_target` | `(target: CombatTarget) -> bool` | 分配进入序号、订阅死亡并加入候选。 |
| `unregister_target` | `(target: CombatTarget) -> void` | 从候选移除并广播。 |
| `get_targets` | `() -> Array[CombatTarget]` | 清理失效引用后返回快照。 |
| `get_targets_in_range` | `(origin: Vector3, range_world: float) -> Array[CombatTarget]` | 按 XZ 距离返回范围候选。 |
| `get_targets_on_segment` | `(start: Vector3, end: Vector3) -> Array[CombatTarget]` | 用点到线段最近点和双方半径返回全部激光触碰目标。 |
| `spawn_debug_target` | `(world_position: Vector3) -> CombatTarget` | 生成并注册 M3 靶标。 |
| `clear_targets` | `() -> void` | 切关时清空目标并重置进入序号。 |

### 策略接口

| 函数 | 签名 | 职责 |
|---|---|---|
| `ITargetingStrategy.select_target` | `(candidates: Array[CombatTarget], origin: Vector3, locked_target: CombatTarget = null) -> CombatTarget` | 从候选返回一个目标或 null。 |
| `PriorityTargetingStrategy.select_target` | `同上` | 应用 priority；锁定失效时选择最近。 |
| `IAttackStrategy.tick` | `(building: Node, delta: float) -> void` | 推进一次攻击策略。 |
| `IAttackStrategy.reset` | `(building: Node) -> void` | 清理冷却或持续表现。 |

**信号**：CombatTarget.`health_changed` / `died`；CombatManager.`target_registered` / `target_removed` / `target_killed`。

## 约定事实源
- `Priority` 数值固定为 nearest/farthest/highest_hp/lowest_hp/fastest/first_in/locked 的 0~6 顺序。
- 激光命中在 XZ 平面计算，目标 Y 不影响 M3 穿透；M6 再在光路求解层加入地形高度阻挡。
- 已释放的锁定目标必须先经 `is_instance_valid()` 归一化为 null，再进入带类型策略参数。
- CombatManager 不生成正式敌人；M4 Unit 负责生命周期并注册/注销。

## 已知限制 / 初版不做的部分
- M3 靶标静止，仅用于战斗验收；移动、护甲、路径和据点伤害属于 M4。
- 不做克制、暴击、闪避、DOT 叠层或衰减。
- M6 才加入地形/障碍/镜面阻挡、反射和多段光路。
