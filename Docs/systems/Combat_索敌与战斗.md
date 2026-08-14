# 索敌与战斗 · Combat

> 实现状态：已完成我方索敌/攻击策略、标准投射物、绕塔后追踪/直飞的范围导弹、可反射且有限穿透的寒冷持续激光、可反射脉冲镭射、我方投射物多镜反射、钉锤固定多方向齐射，以及对全部弹道类型统一生效的 Stuff 球形阻挡。

## 职责

管理可受击目标、空间候选查询、攻击策略、投射物生命周期和统一伤害计算；不管理波次或路径，但以 CombatTarget 契约服务 M4 EnemyUnit。

## 分类 / 做法

- **统一公式**：`DamageCalculator.compute(base, level_factor, extra_factor)`，三个乘区均取非负值。
- **单发伤害**：读取当前级 `base_damage`，发射前计算最终伤害，但只在 Projectile 命中存活目标时调用 `take_damage()`。飞行期间目标不掉血。
- **持续激光**：读取当前级 `laser_dps`，用 `take_damage_over_time(final_dps, delta)` 结算帧率无关的持续伤害。光路以 `laser_propagation_speed` 从塔身逐步增长，只对已传播到的路径结算命中；复用投射物反射查询，所有反射段共享一个 `attack_range` 路程预算；`projectile_penetration_count=N` 允许额外穿过 N 个敌人，第 N+1 个敌人承伤后成为终点。硬阻挡会把传播前沿锁回真实交点，阻挡消失后从该位置继续增长。主轴两侧的流动噪声正弦光丝是纯顶点表现，不参与这些查询。
- **寒冷与冻结**：持续光路命中和首敌爆发都施加当前级同一组减速倍率/时长。同类减速不叠乘，取更强倍率并刷新时间；冻结暂停移动与攻击，减速剩余时间在冻结期间暂停，解冻后继续。寒冷期间模型全部表面临时使用深蓝脉动 Shader，结束后恢复各网格原 `material_override`；不再生成脚下蓝色圆环，冻结冰壳仍独立保留。
- **首敌爆发**：2 级起按 `laser_burst_interval` 在当前已传播光路中首个存活敌人的目标中心发生半径 `laser_burst_radius` 的圆形爆发，使用 `base_damage × level_factor × extra_factor` 结算一次伤害并施加普通寒冷；3 级再追加 `laser_freeze_duration` 冻结。当前光路没有命中敌人时只维持计时/复制通知，不在传播终点空爆。
- **脉冲镭射**：`PulseLaserAttackStrategy` 不索敌，按 `attacks_per_second` 固定周期发射。`PulseLaserBeam` 在生成当下计算完整反射/阻挡路径；粗细和亮度按渐入、保持、渐出线性变化。伤害只在进入保持阶段的瞬间结算一次，且每个反射段独立查询全部路径目标。
- **索敌范围**：箭塔仅从 `targeting_range` 内建立候选并应用优先级。
- **攻击范围**：所选目标必须在独立的 `attack_range` 内才会发射；投射物最大飞行距离也使用该范围。激光用它作为线段长度。
- **投射物表现**：建筑、敌人与复制体投射物均可读取 `ModelAssetDefinition`；模型可视包围盒会精确拟合到 `visual_length/visual_width`，不再依赖资产根 Transform 或旧 Scale 校尺寸。为空或非法时使用同尺寸 BoxMesh 短直线回退；复制体沿用源建筑当前等级投射物资产并叠加虚像发光层。
- **投射物跟踪与反射**：首次命中反射面之前保持原追踪行为；命中反射镜生效面或亚克力柜内侧面后用 `r = d - 2(d·n)n` 转为直线弹道，可连续反射并命中后续线段上的首个有效敌人。实体反射镜同时按自身等级把伤害倍率乘入当前伤害、把穿透加成加入剩余预算；多次反射逐次累计。亚克力柜默认返回 `×1/+0`。背面不反射。每段移动（含防重入偏移）都累计到同一个 `attack_range` 世界距离预算，达到上限立即销毁。
- **三种投射物开火模式**：`TARGET_ONLY` 只在索敌成功且目标处于攻击范围时发射追踪弹；`TARGET_OR_FACING` 有目标时保持追踪，索敌候选为空时沿逻辑朝向直射；`FACING_ONLY` 完全不调用索敌，无论场上是否存在目标都按冷却沿逻辑朝向直射。两种方向弹都从生成起逐段查询弹道上的有效敌人；适用的空中敌人按战斗平面投影参与接触检测。三种模式共用伤害、速度、对空过滤、累计射程、Stuff、穿透与反射规则。
- **导弹弹道**：`projectile_is_missile` 启用后，发射时快照塔的世界起点和初始方向，随机顺/逆时针走完一次可调偏心环线并轻微起伏。绕圈阶段只是表现，不查询敌人、Stuff 或镜面，也不消耗射程。索敌导弹同时创建 `aim.png` 地面标记，出圈后按可调转向速度持续追踪同一目标；无目标导弹则沿发射时的朝向直飞。
- **导弹引爆与反射**：实体飞行阶段碰到任意敌人、弹道阻挡 Stuff 或达到共享总路程时立即引爆；爆炸用 XZ 圆形范围结算一次全额伤害，忽略高度差，因此命中空中单位。反射镜有效面和亚克力柜内侧只改变导弹真实方向、不引爆；复制镜未注册到两条查询链，因此直接穿过。速度正弦波动作用于真实路程，小幅侧移/滚转只作用于模型子根，不污染追踪和碰撞。
- **固定多方向齐射**：MaceAttackStrategy 不选择目标，只以 `has_target_in_range()` 作为1、2级的发射门控，并在每次冷却到期时围绕建筑逻辑朝向一次生成4或8枚水平投射物。3级的 `TARGET_OR_FACING` 允许无目标时绕过门控；每枚投射物仍共享普通投射物的速度、最大总距离、反射查询、对空过滤和穿透预算。
- **穿透与连续接触**：`projectile_penetration_count=N` 的单发弹最多命中 `N+1` 个敌人。一个目标进入同一投射物的连续接触表后不会重复受击；投射物离开其命中半径加清除距离后解除该表，反射返回并再次穿过时可以再次命中。穿透额度或累计飞行距离先达到上限时投射物销毁。
- **Stuff 统一弹道阻挡**：`StuffDefinition.blocks_ballistics` 启用且根源存活时，实体与复制 Stuff 都以 `StuffManager` 的全局统一球形命中体参与最近交点比较。追踪弹、方向弹、穿透弹、复制弹、敌方投射物、旧持续激光和脉冲镭射全部被吸收截止；穿透额度不能穿过 Stuff。Stuff 交点具有硬截止优先级，即使敌人命中球与阻挡球重叠，中心在阻挡点后方也不会被端帽命中。
- **索敌优先级**：最近、最远、最高血、最低血、最快、首个进入、锁定；锁定失效后回退到最近。`prioritizes_airborne` 启用时先把候选收缩为空中敌人，再应用上述优先级；新空中敌人会因而打断对地 `LOCKED`。正式箭塔和导弹塔三级全部启用。
- **目标实现**：CombatTarget 提供生命、速度、奖励、命中半径，以及通用减速/冻结计时、深蓝寒冷表面 Shader 和冻结冰壳；M3 靶标与 M4 EnemyUnit 都可注册。正式掉落不通过泛用 `target_killed`，而由 WaveManager 限定 EnemyUnit 的死亡信号结算。
- **空中目标过滤**：CombatTarget 用 `airborne` / `is_airborne_unit()` 暴露统一分类。每级建筑用 `affects_airborne` 决定是否接纳飞行目标；单体索敌、独立射程复核与激光线段结算使用同一过滤入口。
- **敌方攻击策略**：EnemyAttackStrategy 复用 IAttackStrategy 的 `tick/reset` 契约，只管理冷却；EnemyUnit 提供当前屏障目标和具体近战/远程执行入口。
- **敌方投射物**：EnemyProjectile 使用结构目标的动态方法契约，不把屏障注册进 CombatManager，避免我方塔误把我方建筑当敌人。攻击者或屏障失效时投射物自动清理。
- **目标生命周期**：CombatManager 对每个目标只保留一份死亡/离树回调；显式注销会先解除回调，因此同一对象可安全重新注册。外部 `queue_free()`、死亡和切关清理都汇入幂等注销；失效目标清理遍历稳定快照，允许 `target_removed` 监听者同步再次查询目标而不破坏迭代。
- **复制塔攻击事件**：Building 在真实投射物、持续激光 tick/首敌爆发或脉冲镭射发射时发出 `copy_attack_triggered`。MirrorManager 变换起点/方向后，先累计复制镜链各等级的伤害倍率/穿透加成，再为虚像独立重算反射、Stuff 和穿透截止；持续伤害、寒冷、首敌爆发与冻结都使用源建筑当前等级参数，虚像保存自己的首个命中点但不自持计时器。
- **复制塔投射物反射**：箭塔复制弹从生成起就是直线弹道，使用开火瞬间镜像后的方向而不追踪或保留固定终点；沿途命中、Stuff 截断和反射后命中都使用源建筑 `affects_target` 过滤，并独立消耗源建筑当前级 `attack_range` 总路程预算。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| CombatManager | `laser_hit_radius` | 激光线段额外命中半径。 |
| CombatTarget | `max_hp` / `move_speed` / `hit_radius` | 生命、最快索敌值和碰撞半径。 |
| CombatTarget | `airborne` | 运行时空中分类；EnemyUnit 从定义复制。 |
| BuildingLevelStats | `affects_airborne` | 当前等级的攻击、激光、屏障阻挡与反伤是否作用于飞行敌人；默认 true 兼容旧资源。 |
| BuildingLevelStats | `prioritizes_airborne` | 有空中候选时先收缩候选集，然后应用普通索敌优先级。 |
| BuildingLevelStats | `base_damage` / `laser_dps` | 当前级单发基础伤害 / 持续基础 DPS。 |
| BuildingLevelStats | `laser_beam_color` / `laser_beam_width` / `laser_beam_emission_energy` | 持续激光主轴和双正弦光丝共用的乳白淡蓝色、自发光强度，以及主轴宽度。 |
| BuildingLevelStats | `laser_propagation_speed` | 持续激光的逻辑/表现共用传播速度，单位为格/秒。 |
| BuildingLevelStats | `laser_slow_multiplier` / `laser_slow_duration` | 寒冷期间的有效移速倍率与离开光路后保留时间。 |
| BuildingLevelStats | `laser_burst_interval` / `laser_burst_radius` | 2/3 级首敌爆发周期与格数半径；间隔为 0 时关闭。 |
| BuildingLevelStats | `laser_freeze_duration` | 3 级首敌爆发的冻结时间；0 表示不冻结。 |
| BuildingLevelStats | `level_factor` / `extra_factor` | 当前级等级乘区 / 其它乘区。 |
| BuildingLevelStats | `targeting_range` / `attack_range` | 独立的候选半径 / 发射或激光范围。 |
| BuildingLevelStats | `attacks_per_second` | 单发冷却频率。 |
| BuildingLevelStats | `pulse_laser_width` / `pulse_laser_emission_energy` | 脉冲光线最大宽度与发光强度。 |
| BuildingLevelStats | `pulse_laser_fade_in_time` / `pulse_laser_hold_time` / `pulse_laser_fade_out_time` | 三阶段表现时长。 |
| BuildingDefinition | `pulse_laser_reflect_max` / `pulse_laser_reflection_colors` | 单次脉冲反射上限与赤橙黄绿青蓝紫循环。 |
| BuildingLevelStats | `projectile_fire_mode` | `TARGET_ONLY`、`TARGET_OR_FACING`、`FACING_ONLY` 三选一；逐等级独立，现有数值0/1保持序列化兼容，新模式追加为2。 |
| BuildingLevelStats | `projectile_speed` | 投射物格/秒速度。 |
| BuildingLevelStats | `projectile_length` / `projectile_width` | 恒定短直线尺寸。 |
| BuildingLevelStats | `projectile_direction_count` | 固定多方向齐射的方向数；钉锤1级4、2/3级8。 |
| BuildingLevelStats | `projectile_penetration_count` | 额外可穿过的敌人数；0表示首次命中后销毁。 |
| BuildingLevelStats | `projectile_model_asset` | 建筑及其复制体投射物共用的模型场景与附加 Scale。 |
| BuildingLevelStats | `projectile_is_missile` / `missile_explosion_radius` | 导弹开关与水平爆炸格数半径。 |
| BuildingLevelStats | `missile_orbit_*` | 绕圈时长、横/纵半径和高度起伏；建筑发射时转为世界单位快照。 |
| BuildingLevelStats | `missile_homing_turn_speed_degrees` / `missile_speed_variation_*` | 追踪最大转向速度与真实飞行速度波动。 |
| BuildingLevelStats | `missile_visual_wobble` / `missile_visual_roll_degrees` | 不参与逻辑命中的模型偏移与滚转。 |
| BuildingLevelStats | `missile_trail_*` / `missile_target_marker_size` / `missile_explosion_duration` | 程序化拖尾、目标标记和爆炸表现参数。 |
| BuildingLevelStats | `target_priority` | 七种索敌优先级枚举。 |
| EnemyDefinition | `attack_damage` / `attacks_per_second` / `attack_range` | 敌人攻击屏障的伤害、频率和格数射程。 |
| EnemyDefinition | `projectile_speed` / `projectile_length` / `projectile_width` | 0 为近战；正数及尺寸驱动 EnemyProjectile。 |
| EnemyDefinition | `projectile_model_asset` | 敌人投射物模型场景与附加 Scale。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/combat/DamageCalculator.gd` | `DamageCalculator` / `RefCounted` | 无状态伤害公式。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 可受击目标契约、生命/死亡信号和 M3 靶标。 |
| `scripts/unit/EnemyUnit.gd` | `EnemyUnit` / `CombatTarget` | M4 正式目标；附加护甲、路径移动和据点到达行为。 |
| `scripts/combat/CombatManager.gd` | `CombatManager` / `Node3D` | **战斗唯一入口**；目标注册、范围/线段查询和投射物管理。 |
| `scripts/combat/BallisticGeometry.gd` | `BallisticGeometry` / `RefCounted` | 投射物、光线与 Stuff 共用的稳定线段-球入射交点。 |
| `scripts/combat/ContinuousLaserPath.gd` | `ContinuousLaserPath` / `RefCounted` | 持续激光的共享射程、反射、Stuff 和有限穿透路径查询。 |
| `scripts/combat/ContinuousLaserVisual.gd` | `ContinuousLaserVisual` / `Node3D` | 本体/复制体共用的持续 BoxMesh 光段、发光材质和移动终点。 |
| `scripts/combat/LaserBurstEffect.gd` | `LaserBurstEffect` / `Node3D` | 真实/复制激光终点的短时扩散环和闪光。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 单发攻击的飞行、短直线表现、距离截止、穿透和连续接触去重。 |
| `scripts/combat/MissileProjectile.gd` | `MissileProjectile` / `Projectile` | 导弹绕圈、追踪/直飞、速度波动、镜面反射、Stuff/射程引爆与水平范围伤害。 |
| `scripts/combat/MissileTargetMarker.gd` | `MissileTargetMarker` / `Node3D` | 使用 `aim.png` 跟随索敌导弹标记目标脚下。 |
| `scripts/combat/MissileTrail.gd` | `MissileTrail` / `Node3D` | 独立世界空间带状拖尾，导弹销毁后继续衰减。 |
| `scripts/combat/MissileExplosionEffect.gd` | `MissileExplosionEffect` / `Node3D` | 程序化闪光、冲击环与烟雾壳。 |
| `scripts/combat/MaceAttackStrategy.gd` | `MaceAttackStrategy` / `IAttackStrategy` | 钉锤范围门控、等级开火模式和多方向齐射。 |
| `scripts/combat/ITargetingStrategy.gd` | `ITargetingStrategy` / `RefCounted` | 索敌策略接口。 |
| `scripts/combat/PriorityTargetingStrategy.gd` | `PriorityTargetingStrategy` / `ITargetingStrategy` | 七种优先级实现。 |
| `scripts/combat/IAttackStrategy.gd` | `IAttackStrategy` / `RefCounted` | 攻击逐帧执行/重置接口。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 目标获取、独立射程检查、冷却和投射物发射。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定朝向可反射光路、有限穿透、寒冷、反射伤害倍率与周期首敌爆发。 |
| `scripts/combat/PulseLaserAttackStrategy.gd` | `PulseLaserAttackStrategy` / `IAttackStrategy` | 无目标门控的周期固定朝向开火。 |
| `scripts/combat/PulseLaserBeam.gd` | `PulseLaserBeam` / `Node3D` | 脉冲路径、反射段、单次伤害与渐变表现。 |
| `scripts/combat/EnemyAttackStrategy.gd` | `EnemyAttackStrategy` / `IAttackStrategy` | 敌人攻击冷却和 `perform_attack` 调度。 |
| `scripts/combat/EnemyProjectile.gd` | `EnemyProjectile` / `Node3D` | 面向屏障方法契约的追踪投射物、表现与命中。 |
| `scripts/mirror/MirrorProjectionProjectile.gd` | `MirrorProjectionProjectile` / `Node3D` | 塔虚像使用的固定终点或从起点直射投射物；反射后使用共享距离预算的直线弹道。 |

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
  -> Projectile homes before first reflection
  -> ReflectMirror active-face hit: r = d - 2(d·n)n, then ballistic
  -> every segment consumes the same attack_range distance budget
  -> impact -> CombatTarget.take_damage -> projectile_hit / attack_performed

Missile Building
  -> Building.acquire_target: optional airborne candidate partition -> normal priority
  -> CombatManager.spawn_targeted_missile / spawn_directional_missile
  -> collision-free random-direction launch loop; range budget remains untouched
  -> targeted: aim marker follows target -> bounded homing turn
  -> facing: launch direction snapshot -> straight flight
  -> reflect mirror / acrylic: reflect and continue; copy mirror: no query hit
  -> enemy / Stuff / maximum distance -> one XZ-area explosion -> impacted per target

Laser Building facing
  -> propagation front += laser_propagation_speed * delta
  -> ContinuousLaserPath.trace uses the current front as its distance limit
  -> nearest reflect mirror / Stuff / penetration-stop enemy / max range
  -> hard stop clamps stored front; removal resumes growth from that endpoint
  -> every crossed target.take_damage_over_time + apply_movement_slow
  -> level 2 timer: first live hit target burst damage + same cold; no hit means no burst
  -> level 3 first-hit burst: append freeze; slow timer pauses until thaw

Pulse Laser Building facing
  -> attacks_per_second fixed clock, no target gate
  -> CombatManager.spawn_pulse_laser
  -> synchronously freeze nearest mirror / acrylic / Stuff path
  -> all reflected segments share attack_range and cycle colors
  -> fade-in enters hold -> each segment applies one penetrating damage pass

Building.copy_attack_triggered
  -> MirrorManager transforms start/end through projection lineage
  -> projectile: mirrored launch direction, straight ballistic query until hit/block/range
  -> laser: independently retrace reflection/blocking/penetration, store first hit, and mirror cold/burst/freeze

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
| `CombatTarget.get_target_marker_position` | `() -> Vector3` | 返回目标脚下标记位置；EnemyUnit 会扣除飞行高度投影到路面。 |

### CombatManager.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `register_target` | `(target: CombatTarget) -> bool` | 分配进入序号、建立唯一死亡/离树回调并加入候选；重复注册返回 false。 |
| `unregister_target` | `(target: CombatTarget) -> void` | 幂等移除候选、解除生命周期回调并广播。 |
| `get_targets_in_range` | `(origin: Vector3, range_world: float) -> Array[CombatTarget]` | 按 XZ 距离返回范围候选。 |
| `get_targets_on_segment` | `(start: Vector3, end: Vector3) -> Array[CombatTarget]` | 用点到线段距离返回全部激光触碰目标。 |
| `spawn_projectile` | `(start: Vector3, target: CombatTarget, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null, source_building: Building = null, penetration_count: int = 0) -> Projectile` | 创建、配置并跟踪投射物；最后一个参数为额外穿透预算。 |
| `spawn_directional_projectile` | `(start: Vector3, direction: Vector3, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null, source_building: Building = null, penetration_count: int = 0) -> Projectile` | 创建从起点即沿线段检敌的直线弹，复用投射物注册、反射查询、穿透和总路程预算。 |
| `spawn_targeted_missile` | `(start, target, speed, damage, maximum_distance, visual_length, visual_width, color, model_asset = null, source_building = null, configuration = {}) -> MissileProjectile` | 创建带目标标记、出圈追踪和范围引爆的导弹。 |
| `spawn_directional_missile` | `(start, direction, speed, damage, maximum_distance, visual_length, visual_width, color, model_asset = null, source_building = null, configuration = {}) -> MissileProjectile` | 创建出圈后沿发射朝向直飞的导弹。 |
| `spawn_pulse_laser` | `(start, direction, damage, maximum_distance, maximum_width, emission_energy, fade_in_time, hold_time, fade_out_time, colors, maximum_reflections, source_building = null) -> PulseLaserBeam` | 瞬时构造并跟踪一次完整脉冲光路。 |
| `Projectile.configure_directional` | `(start: Vector3, direction: Vector3, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null, source_building: Building = null, target_query: Callable = Callable(), reflection_resolver: Callable = Callable(), penetration_count: int = 0) -> void` | 配置无独立目标的方向弹道与额外穿透预算。 |
| `set_projectile_reflection_resolver` | `(resolver: Callable) -> void` | 注入 Mirror 模块聚合后的有限反射面查询，不让 CombatManager 持有镜子或柜体实现。 |
| `clear_projectile_reflection_resolver` | `(expected_owner: Object = null) -> void` | 仅由当前提供者安全清除反射查询。 |
| `set_projectile_blocker_resolver` / `clear_projectile_blocker_resolver` | `(resolver: Callable)` / `(expected_owner: Object = null)` | 注入或幂等清除 Stuff 最近球形阻挡查询。 |
| `spawn_debug_target` | `(world_position: Vector3) -> CombatTarget` | 生成并注册 M3 靶标。 |
| `clear_projectiles` | `() -> void` | 清理全部飞行投射物。 |
| `clear_targets` | `() -> void` | 切关时清空目标、投射物和进入序号。 |

### Projectile.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(start: Vector3, target: CombatTarget, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null, source_building: Building = null, target_query: Callable = Callable(), reflection_resolver: Callable = Callable()) -> void` | 配置追踪、伤害、总路程、目标过滤和镜面查询。 |
| `_process` | `(delta: float) -> void` | 首次反射前追踪，反射后沿严格反射方向推进；逐段结算命中和累计距离。 |
| `get_distance_traveled` / `has_reflected` | `() -> float` / `() -> bool` | 暴露累计总路程和弹道阶段供调试与回归。 |
| `_impact` | `(target: CombatTarget) -> bool` | 对当前线段实际命中的存活目标结算伤害；返回是否仍有穿透额度。 |

### MissileProjectile.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure_targeted_missile` | `(start, target, speed, damage, maximum_distance, visual_length, visual_width, color, model_asset, source_building, target_query, reflection_resolver, blocker_resolver, configuration) -> void` | 快照目标、出圈参数、伤害/射程和三条查询入口，并创建标记/拖尾。 |
| `configure_directional_missile` | `(start, direction, speed, damage, maximum_distance, visual_length, visual_width, color, model_asset, source_building, target_query, reflection_resolver, blocker_resolver, configuration) -> void` | 快照无目标的朝向导弹。 |
| `_process` | `(delta: float) -> void` | 先消费无碰撞绕圈时间，再按可变速度推进真实弹道。 |
| `_explode` | `(contact_target: CombatTarget = null) -> void` | 生成爆炸表现，按 XZ 半径对存活候选各结算一次伤害。 |
| `is_orbiting` / `get_orbit_progress` | `() -> bool` / `() -> float` | 暴露绕圈阶段与 0~1 进度供测试/表现查询。 |

### EnemyAttackStrategy / EnemyProjectile

| 函数 | 签名 | 职责 |
|---|---|---|
| `EnemyAttackStrategy.tick` | `(attacker: Node, delta: float) -> void` | 冷却到期时读取攻击者当前结构目标并调用 `perform_attack`。 |
| `EnemyAttackStrategy.reset` | `(attacker: Node) -> void` | 目标切换/离开攻击状态时允许下一次进入立即攻击。 |
| `EnemyProjectile.configure` | `(start: Vector3, target: Node, attacker: Node, speed: float, damage: float, maximum_distance: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null) -> void` | 配置结构目标、攻击者、飞行和可替换模型。 |
| `EnemyProjectile._process` | `(delta: float) -> void` | 仅在攻击者与屏障都有效时追踪飞行。 |
| `EnemyProjectile._impact` | `() -> void` | 调用屏障 `take_structure_damage` 并广播实际伤害。 |

**信号**：CombatTarget.`health_changed` / `died`；CombatManager.`target_registered` / `target_removed` / `target_killed` / `projectile_spawned` / `projectile_hit` / `pulse_laser_spawned` / `pulse_laser_hit`；Projectile.`impacted`；PulseLaserBeam.`impacted`；EnemyProjectile.`impacted`。

## 约定事实源

- 当前建筑等级数据是伤害、范围、攻速和投射物参数的唯一事实源。
- `BuildingLevelStats.affects_airborne` 是当前等级对飞行敌人生效与否的唯一事实源；`prioritizes_airborne` 只决定有效候选中的分组顺序，不能绕过该过滤。
- `targeting_range` 不代表可攻击；`attack_range` 不负责生成候选。
- 单发攻击的逻辑命中时刻与视觉投射物命中时刻一致。
- 敌人命中仍沿用 CombatManager 线段查询；Stuff 弹道阻挡的空间事实源是 `StuffManager` 全局球形中心/半径，不使用各模型自带碰撞体。
- CombatManager 不生成正式敌人，也不直接修改资源；WaveManager 是 EnemyUnit 掉落的唯一资源桥接者。
- CombatManager 的 `_targets` 与其回调表必须同步增删；任何外部释放都由 `tree_exited` 回收，重新注册不得叠加旧回调。
- 屏障不是 CombatTarget，也不进入 CombatManager 敌对候选；EnemyProjectile 通过结构方法契约造成伤害。

## 已知限制 / 初版不做的部分

- M3 调试靶标仍静止；EnemyUnit 的移动、护甲、路径和统一 1 点漏怪惩罚实现见 Unit、Path、Wave 文档。
- 标准投射物首次反射前追踪目标，反射后为直线弹道；导弹是独立变体，反射后下一帧仍可转回所标记目标。当前两者都未对象池化，正式大量单位阶段需评估。
- 不做克制、暴击、闪避、DOT 叠层或衰减。
