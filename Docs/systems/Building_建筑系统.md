# 建筑系统 · Building

> 实现状态：已完成箭塔、导弹塔、钉锤、持续激光塔、脉冲镭射塔与屏障、三级完整参数、36档自由朝向、放置虚影、升级、逐级外观/产出、配置化目标追踪/无目标直射、选中范围/占地/反射弹道提示、初始陈列持久化，以及屏障耐久、脱战回血和反伤。

## 职责

定义可放置防御建筑，用 `BuildingDefinition + BuildingLevelStats` 组合建筑身份和每级完整参数。`BuildingManager` 是放置、路径规则、预览、升级、占用、选择和移除的唯一入口。

## 分类 / 做法

- **三级参数**：建筑初始 1 级、上限 3 级。`levels[0..2]` 分别保存 1~3 级的完整经济、战斗、投射物和表现参数；升级直接切换到下一份参数，不把上一等级参数乘算后继承。
- **检视配置**：每个 `BuildingDefinition.inspection_display` 可独立编辑显示名称、基础功能说明、1–3 级说明、对象可见性和字段行。四段说明同时供建筑卡悬停框与选中建筑说明页使用；正文支持 `[color=#RRGGBB]…[/color]`、`[highlight=#RRGGBB]…[/highlight]` 和 `[b]…[/b]` 白名单标记，其他 BBCode 作为普通文字。说明不参与玩法结算，虚像沿用根源建筑配置。
- **伤害公式**：单发伤害为当前级 `base_damage × level_factor × extra_factor`；持续伤害为当前级 `laser_dps × level_factor × extra_factor × delta`。`level_factor` 是当前建筑等级数据的一部分，不是全局等级曲线。
- **箭塔**：在 `targeting_range` 内选择目标，只在目标进入 `attack_range` 后发射投射物；伤害在投射物命中时结算。`attack_range` 同时是经过反射镜后的累计总飞行距离上限。正式资源使用 `TRACK_TARGET`，锁定期间只转动视觉姿态，不改写放置 `facing_index`。
- **导弹塔 / 分级开火模式**：保留序列化 `CROSSBOW_TOWER=4` 和 `CrossbowTower.tres` 资源路径，对外名称/功能改为导弹塔，不破坏已有关卡引用。三级均使用 `TARGET_OR_FACING + projectile_is_missile`：有目标时标记并在绕圈后追踪，无目标时快照逻辑朝向并在绕圈后直飞。箭塔类可逐级选择 `TARGET_ONLY`、`TARGET_OR_FACING` 或 `FACING_ONLY`；最后一种完全跳过索敌，无论场上是否存在目标都只沿逻辑朝向周期直射。
- **钉锤 / 固定多方向齐射**：`resources/buildings/MaceTower.tres` 使用独立 `MACE_TOWER` 类型。1级按当前逻辑朝向四等分齐射，2级解锁八等分齐射；1、2级只有在半径 `targeting_range` 内存在有效敌人时开火。3级保持八向，提升本级伤害、飞行距离、攻速和穿透，并解锁 `TARGET_OR_FACING`，没有敌人时也持续齐射。钉锤不选择单个目标，也不自动转向。
- **激光塔**：不索敌，使用 `FIXED_FACING`。持续光路与其它塔共用反射镜和 Stuff 查询，所有反射段共享 `attack_range`；`projectile_penetration_count=N` 允许额外穿过 N 个敌人，下一个敌人承伤后截断光路。每次持续命中附带寒冷，目标模型表面临时切换为深蓝脉动 Shader；2 级起每隔可调时间在当前已传播光路的首个存活敌人处产生一次圆形伤害/减速爆发，无命中时不空爆，3 级再追加冻结。表现保留较粗直线主轴，并由两条左右平移、持续传播且带平滑噪声的细正弦光丝夹住；波形只作用于渲染顶点。复制塔从镜像起点独立重算同一套光路、首个命中点和效果，并复用相同光丝表现。
- **脉冲镭射塔**：保留旧激光塔的同时新增独立 `PULSE_LASER_TOWER`。固定朝向且无论有无敌人都按 `attacks_per_second` 周期开火；发射时瞬间固化整条可反射路径，渐入、保持、渐出均为线性可调。只在进入保持阶段的一瞬间按 `base_damage × level_factor × extra_factor` 结算；各反射光段独立无限穿透敌人，因此同一敌人可被不同光段多次命中。
- **空中适用性与优先级**：每级 `affects_airborne` 统一控制箭塔候选、激光线段伤害、屏障阻挡与反伤是否作用于飞行敌人；`prioritizes_airborne` 在有效候选中先取空中分组，再应用最近/最远/血量/锁定等原优先级。箭塔与导弹塔正式三级全部启用，空中敌人进入范围会打断旧的对地锁定。
- **屏障**：`BuildingDefinition.Kind.BARRIER`，只允许放在敌人路径格；可跨越不可建造路面规则占格，但不能覆盖未清障障碍、出生点、据点、已有占用或敌人当前所在格。普通塔不能占据路径格。
- **耐久与升级**：屏障每级独立配置 `max_durability`。升级时最大耐久的增加量同步加到当前耐久，保留升级前已经损失的绝对耐久。
- **脱战回血**：屏障每次受伤重置计时；连续 `regeneration_delay` 秒未受伤后，按 `regeneration_per_second` 回耐久。大 delta 只结算越过延迟后的时间。
- **反伤与摧毁**：`damage_reflection_ratio` 按屏障实际承受伤害反射给攻击者；归零后由 BuildingManager 无退款移除、释放路径占位和建筑上限。玩家主动拆除则全额返还建造与历次升级费用。
- **放置预览**：建造模式悬停可建造空格时创建不占格、不攻击的 1 级半透明建筑；预览保留塔种和朝向，R 旋转虚影，左键放置时继承该朝向。箭塔、导弹塔和钉锤同时显示当前 1 级 `targeting_range` 的蓝色圆形范围；激光和防御建筑不显示索敌圆。
- **封路预防**：屏障/边障的虚影会通过注入的 `PathPlacementConnectivityGuard` 假设加入当前同目标路网；会堵死最后可达路线时虚影保留但改为高亮红色。点击后在占格/扣费前二次校验并拒绝。
- **无效格信息**：未选择塔种或当前格不可放置时不创建虚影；Main HUD 显示地块类型、高度、障碍/占用对象和占位建筑等级、索敌范围、射程。
- **美术替换**：每一级通过 `model_asset: ModelAssetDefinition` 配置模型场景和附加运行时 Scale；实例会先把可视底部中心自动接地，再保留当前等级 Scale。`projectile_model_asset` 则精确拟合到该级的子弹长度/宽度。未指定时继续使用 `tower_color/attack_color` 灰盒。
- **卡片美术替换**：`BuildingDefinition.card_icon` 是程序镜面模式的可选透明建筑主体，不包含镜框、镜面、名称或费用。`full_card_art` 是原画卡面模式的独立完整卡面，可包含镜框、镜面和已烘焙名称但不能烘焙费用。BuildCardBar 默认程序化生成完整卡片；切换到原画模式后自动裁透明边、隐藏程序框和名称，只在建筑上方叠加实时费用。缺少对应素材时稳定回退程序镜面，不影响资源校验或放置。
- **资源产出**：每一级独立配置 `resource_per_second`；放置、升级或移除后，BuildingManager 汇总当前所有建筑的当前级产出并同步到 ResourceManager。
- **选中操作**：选择模式点中建筑后，在其动作锚点左/上/右投影出说明、升级、出售三个同尺寸图标；升级与出售数字位于对应图标上方，满级隐藏升级项。键盘 `R` 和滚轮的 10° 旋转仍保留，持续按住 `R` 按 Main 的真实时间重复参数连续旋转；边建筑仍拒绝自由旋转。
- **拆除退款**：主动拆除按当前等级动态累加 1 级建造费用和已经过等级的全部升级费用，100% 返还且无损失；不再配置独立退款数值。
- **放置事务**：依次校验定义、边界、`TileManager.can_place()`、建筑上限和资源。占格或扣费失败会回滚，不留下半放置建筑。
- **关卡初始建筑**：`BuildingPlacementData` 保存 Definition、格/边、逻辑朝向和等级。`BuildingManager.export_initial_placements()` 只导出真实建筑；加载时不扣 `initial_resource`，但注册建筑上限、恢复产出并继续使用正常删除/升级/战斗规则。初始陈列属于作者数据，静态预检通过后不重复执行玩家封路守卫。
- **正式单次放置**：BuildingManager 仍维持通用“放置后选中”兼容行为；M6 `RuntimeInteractionController` 在卡片放置完成后立即清除该选择，并让成功/失败统一回 `SELECT`。其他调试或测试入口不受此 UI 规则反向耦合。
- **移除事务**：主动删除、战斗摧毁、切关清理和外部 `queue_free()` 共用幂等释放路径，统一解除信号、清除字典/地块占位、释放建筑上限、选择和产出；同一建筑不会重复退款或重复注销。
- **逻辑朝向与视觉朝向**：所有块建筑的自由逻辑朝向统一为 36 档，每档 10°，不读取相机 yaw；边建筑仍严格沿关卡物理边，保留 HEX 6 边 / SQUARE 4 边。`FIXED_FACING` 的逻辑和模型都跟随 `facing_index`；`TRACK_TARGET` 只在此基础上转动 `_visual_root` 追踪当前目标，失去目标后回到逻辑朝向。Stuff 与斜坡仍使用各自随网格的拓扑方向，不受建筑朝向升级影响。
- **选中/放置世界 UI**：`BuildingSelectionVisualizer` 同时监听 BuildingManager 的选择和放置虚影信号；蓝色 `targeting_range` 圆优先跟随有效放置虚影，否则跟随已选索敌建筑。对 `Building.get_occupied_cells()` 返回的每个占格绘制的浅黄色半透明多边形仍只属于已选实体。当前单格建筑返回一个格；接口允许后续多格占用直接扩展返回数组。
- **旋转弹道预览**：选中已放置的攻击建筑或悬停有效放置预览时，绘制沿当前逻辑朝向的粗红色半透明弹道。单向塔显示一条，钉锤读取当前级真实 `projectile_direction_count` 显示4/8向；长度读取当前级 `attack_range`，粗细至少为可调下限并乘算当前级实际宽度。持续激光读取 `laser_beam_width`，显示完整规划光路而非实战中的移动传播前沿。预览通过 Main 注入统一反射、Stuff 阻挡与复制投影查询，因此静态几何最近交点与实战一致。预览只读，不查询敌人、不生成攻击或结算伤害；持续激光塔和脉冲镭射塔均显示，防御建筑不显示。

## 参数编辑入口

在 Godot 检视面板打开：

- `resources/buildings/ArrowTower.tres`
- `resources/buildings/CrossbowTower.tres`
- `resources/buildings/LaserTower.tres`
- `resources/buildings/PulseLaserTower.tres`
- `resources/buildings/Barrier.tres`

展开 `Levels` 数组中的三个 `BuildingLevelStats`。数组第 0/1/2 项对应建筑 1/2/3 级。

Definition 根节点的 `Orientation` 分组控制通用转向能力：

| 参数 | 说明 |
|---|---|
| `aim_mode` | `FIXED_FACING` 只跟随手动逻辑朝向；`TRACK_TARGET` 使视觉姿态追踪已锁定目标。新的转向索敌建筑应通过此字段声明能力，不在 Building 中按种类写死。 |
| `visual_turn_speed_degrees` | 追踪模式每秒最大视觉转向角度；不影响索敌、攻击频率或发射条件。 |
| `card_icon` | M6 正式卡槽透明建筑主体接口；不应烘焙完整卡面，可为空，空值使用名称首字灰盒。 |
| `full_card_art` | 可选完整卡面接口；原画模式自动裁透明留白并隐藏程序标题/框体，费用必须留给 HUD 动态叠加。 |

| 分组 | 参数 | 说明 |
|---|---|---|
| Economy | `cost` | 1 级为建造费用；2、3 级为升到该级的费用。 |
| Economy | `resource_per_second` | 该建筑处于本级时每秒提供的资源。 |
| Combat | `base_damage` | 单发攻击的基础伤害。 |
| Combat | `affects_airborne` | 本级攻击或屏障效果是否作用于飞行敌人；默认 true 兼容旧资源。 |
| Combat | `prioritizes_airborne` | 范围内有空中敌人时先收缩到空中候选，再套用 `target_priority`。 |
| Combat | `targeting_range` | 索敌候选半径，单位为格。 |
| Combat | `attack_range` | 允许发射/激光长度，单位为格，与索敌范围独立。 |
| Combat | `attacks_per_second` | 单发攻击频率。 |
| Combat | `laser_dps` | 持续攻击的基础每秒伤害。 |
| Combat | `level_factor` | 本级独立等级伤害因子。 |
| Combat | `extra_factor` | 其它伤害乘区预留。 |
| Combat | `target_priority` | 最近、最远、最高血、最低血、最快、首个进入、锁定。 |
| Continuous Laser | `laser_beam_color` / `laser_beam_width` | 持续射线主轴与双正弦光丝的共用颜色，以及主轴体积光段宽度；光丝粗细/偏移按主轴比例派生，宽度单位为格。 |
| Continuous Laser | `laser_beam_emission_energy` / `laser_propagation_speed` | 射线自发光强度与逻辑/表现共用传播速度（格/秒）。 |
| Continuous Laser | `laser_slow_multiplier` | 寒冷期间的实际移速倍率；0.4 表示以 40% 速度移动。 |
| Continuous Laser | `laser_slow_duration` | 离开光路或爆发后的寒冷保留时间。 |
| Continuous Laser | `laser_burst_interval` / `laser_burst_radius` | 2/3 级首敌爆发间隔与格数半径；间隔为 0 关闭爆发。 |
| Continuous Laser | `laser_freeze_duration` | 3 级冻结时间；冻结期间暂停移动、攻击和寒冷倒计时。 |
| Defense | `max_durability` | 屏障本级最大耐久；塔类忽略。 |
| Defense | `regeneration_delay` | 受伤后进入回血所需的无伤秒数。 |
| Defense | `regeneration_per_second` | 脱战后的每秒耐久恢复量，0 表示不回血。 |
| Defense | `damage_reflection_ratio` | 按实际承伤反射给攻击者的比例，范围 0~1。 |
| Projectile | `projectile_speed` | 单发投射物速度，单位为格/秒。 |
| Projectile | `projectile_fire_mode` | `TARGET_ONLY` 只对索敌目标开火；`TARGET_OR_FACING` 有目标追踪、无目标沿朝向直射；`FACING_ONLY` 完全不索敌，只沿逻辑朝向周期直射。该字段逐等级独立配置。 |
| Projectile | `projectile_length` | 短直线投射物长度，运行时下限 0.1，不会缩成点。 |
| Projectile | `projectile_width` | 投射物宽度。 |
| Projectile | `projectile_direction_count` | 固定齐射方向数，钉锤1级为4、2/3级为8；其它建筑保持1。 |
| Projectile | `projectile_penetration_count` | 标准投射物首次命中不计穿透；0表示命中1个目标后消失，N表示最多再穿过N个目标。导弹命中即引爆，不读取本字段。 |
| Projectile | `projectile_model_asset` | 建筑和对应复制体投射物共用的模型资产与运行时 Scale；为空使用短方块。 |
| Missile | `projectile_is_missile` / `missile_explosion_radius` | 启用导弹变体；爆炸半径单位为格。 |
| Missile | `missile_orbit_duration` / `missile_orbit_radius_x` / `missile_orbit_radius_z` / `missile_orbit_vertical_amplitude` | 绕塔一圈的时长、非正圆尺寸与上下起伏。 |
| Missile | `missile_homing_turn_speed_degrees` | 索敌导弹出圈后的每秒最大转向角，决定弯曲程度。 |
| Missile | `missile_speed_variation_ratio` / `missile_speed_variation_frequency` | 真实飞行速度的小幅正弦波动幅度与频率。 |
| Missile | `missile_visual_wobble` / `missile_visual_roll_degrees` | 仅模型子根使用的偏移/滚转，不影响追踪和碰撞。 |
| Missile | `missile_trail_lifetime` / `missile_trail_width` / `missile_target_marker_size` / `missile_explosion_duration` | 拖尾、`aim.png` 目标标记和程序化爆炸的表现参数。 |
| Presentation | `model_asset` | 本级模型资产与运行时 Scale；根节点必须继承 Node3D。 |
| Presentation | `tower_color` | 无外观场景时的塔体颜色。 |
| Presentation | `attack_color` | 投射物、激光和方向标记颜色。 |
| Pulse Laser | `pulse_laser_width` / `pulse_laser_emission_energy` | 脉冲光线最大粗细与最大亮度。 |
| Pulse Laser | `pulse_laser_fade_in_time` / `pulse_laser_hold_time` / `pulse_laser_fade_out_time` | 线性渐入、保持、渐出时长；伤害只在渐入跨入保持的时刻结算。 |

`Building` 另有灰盒尺寸和 `preview_alpha`；它们是通用表现参数，不参与单级平衡。

`scenes/Main.tscn -> BuildingSelectionVisualizer -> Projectile Trajectory Preview` 分组控制红色弹道表现：

| 参数 | 说明 |
|---|---|
| `projectile_preview_enabled` | 总开关；关闭只隐藏预览，不改变真实投射物。 |
| `projectile_preview_color` | 粗射线颜色和透明度，默认红色半透明。 |
| `projectile_preview_minimum_width` | 世界单位最小粗细，防止实际投射物很细时预览难以辨认。 |
| `projectile_preview_width_multiplier` | 当前级实际 `projectile_width` 的显示倍率；最终宽度取该乘积与最小粗细的较大值。 |
| `projectile_preview_lift` | 仅对红色几何表现施加的向上偏移，避免与模型/地面深度重叠；反射查询仍使用真实攻击起点。 |
| `projectile_preview_max_segments_per_direction` | 单方向最多绘制的反射段数，仅为异常闭环保护；总可见长度仍受 `attack_range` 限制。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/building/BuildingLevelStats.gd` | `BuildingLevelStats` / `Resource` | 一项建筑等级的完整可编辑参数。 |
| `scripts/building/BuildingDefinition.gd` | `BuildingDefinition` / `Resource` | 建筑种类、显示名、格式化说明入口和最多三项等级数据。 |
| `scripts/building/BuildingPlacementData.gd` | `BuildingPlacementData` / `Resource` | 一个开局真实建筑的 Definition、格/边、逻辑朝向和等级快照。 |
| `scripts/shared/ConfigurationValidator.gd` | `ConfigurationValidator` / `RefCounted` | BuildingDefinition/BuildingLevelStats 共用的有限数、范围、颜色和嵌套错误校验。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 当前级运行时实体；装配攻击/耐久组件、外观、朝向和预览状态。 |
| `scripts/building/BarrierDurability.gd` | `BarrierDurability` / `RefCounted` | 屏障耐久、升级保伤、脱战回血、反伤和耗尽信号。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | **建筑唯一入口**；放置事务、预览、升级、占用、选择、旋转、移除和产出汇总。 |
| `scripts/building/BuildingSelectionVisualizer.gd` | `BuildingSelectionVisualizer` / `Node3D` | 订阅实体/放置预览的选择、等级和朝向变化，组合索敌范围、占地格与投射物弹道表现。 |
| `scripts/building/ProjectileTrajectoryPreview.gd` | `ProjectileTrajectoryPreview` / `Node3D` | 用当前级投射参数和注入的只读反射查询构建粗红色半透明多段弹道。 |
| `resources/buildings/ArrowTower.tres` | `BuildingDefinition` | 箭塔三等级参数。 |
| `resources/buildings/CrossbowTower.tres` | `BuildingDefinition` | 导弹塔三等级参数；保留旧路径与 Kind 作序列化兼容。 |
| `resources/buildings/MaceTower.tres` | `BuildingDefinition` | 钉锤三等级固定多方向齐射、穿透和无目标开火参数。 |
| `resources/buildings/LaserTower.tres` | `BuildingDefinition` | 激光塔三等级参数。 |
| `resources/buildings/PulseLaserTower.tres` | `BuildingDefinition` | 脉冲镭射塔三等级参数、反射上限与七色循环。 |
| `resources/buildings/Barrier.tres` | `BuildingDefinition` | 屏障三等级耐久、回血、反伤与经济参数。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 单目标冷却、射程校验和投射物发射。 |
| `scripts/combat/MaceAttackStrategy.gd` | `MaceAttackStrategy` / `IAttackStrategy` | 只做范围门控、冷却和四/八方向齐射，不选择目标。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 持续激光的寒冷结算、2/3 级首敌爆发时钟、反射倍率与复制攻击事件。 |
| `scripts/combat/ContinuousLaserPath.gd` | `ContinuousLaserPath` / `RefCounted` | 按共享射程解算反射段、Stuff 交点、有限穿透和最终终点。 |
| `scripts/combat/ContinuousLaserVisual.gd` | `ContinuousLaserVisual` / `Node3D` | 持续体积光主轴、双平移流动噪声正弦光丝、可调材质与可见终点。 |
| `scripts/combat/LaserBurstEffect.gd` | `LaserBurstEffect` / `Node3D` | 首敌爆发的冰蓝扩散环与闪光。 |
| `scripts/combat/CombatTarget.gd` | `CombatTarget` / `Node3D` | 统一生命与不叠层寒冷/冻结状态、计时和基础视觉反馈。 |
| `scripts/combat/PulseLaserAttackStrategy.gd` | `PulseLaserAttackStrategy` / `IAttackStrategy` | 无目标门控的固定朝向周期开火。 |
| `scripts/combat/PulseLaserBeam.gd` | `PulseLaserBeam` / `Node3D` | 瞬时固化反射路径、独立光段伤害与线性粗细/亮度时序。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 恒定短直线表现、首次镜面前追踪、镜面后直线多次反射、累计距离与命中结算。 |
| `scripts/combat/MissileProjectile.gd` | `MissileProjectile` / `Projectile` | 导弹快照参数、绕圈、追踪/直飞、反射与范围引爆。 |
| `scripts/combat/MissileTargetMarker.gd` / `MissileTrail.gd` / `MissileExplosionEffect.gd` | `Node3D` 表现类 | 目标脚下标记、世界空间拖尾和程序化爆炸。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 建造模式、升级按钮、预览/错误状态和经济摘要。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 将选中建筑上方世界坐标投影为删除、升级、旋转悬浮操作。 |
| `tests/projectile_trajectory_preview_test.gd` | 无 / `SceneTree` | 31项单向旋转、镜面反射、共享总射程、钉锤4/8向、三种索敌塔放置蓝圈、激光光路与防御建筑过滤回归。 |

### 模块调用关系 / 数据流

```text
M3DebugPanel 建造模式 + Main 鼠标悬停
  -> BuildingManager.update_preview(cell, definition)
  -> valid geometry: preview Building(level=1, preview=true), no Tile occupant
  -> path blocker: PathPlacementConnectivityGuard.validate_change
	 -> safe: normal translucent preview
	 -> closes last target route: red invalid preview, final placement rejected
  -> invalid: clear ghost; Main HUD reads Tile/occupant information

Main 左键
  -> BuildingManager.place_building(cell, definition, preview_facing)
	 -> tower: reject path cell -> TileManager.can_place / place_occupant
	 -> barrier: require non-protected path cell -> place_path_occupant
	 -> ResourceManager.try_register_building(level_1.cost)
	 -> Building.configure(..., initial_level=1)

M3DebugPanel 升级
  -> BuildingManager.upgrade_selected
	 -> spend(next_level.cost)
	 -> Building.apply_level(next_level)
	 -> sync sum(Building.current_stats.resource_per_second)

Select occupied cell
  -> BuildingManager.select_at -> BuildingActionPanel projects action anchor
  -> demolish: remove_selected_building -> unregister_building(definition.get_cumulative_cost(current_level))
  -> upgrade: upgrade_selected
  -> rotate: rotate_selected(+1), no resource cost
  -> BuildingSelectionVisualizer -> ProjectileTrajectoryPreview
	 -> Building.get_projectile_launch_directions + current attack_range/projectile_width
	 -> injected MirrorManager.trace_projectile_reflection
  -> MirrorManager.projections_rebuilt -> Main -> visualizer.refresh (镜面陈列变化后重算)
	 -> red read-only segments; no Projectile or damage state

Arrow / Mace Building._process

Missile Tower (stable CROSSBOW_TOWER kind)
  -> Building.acquire_target: airborne partition before target_priority
  -> targeted: launch_projectile -> CombatManager.spawn_targeted_missile
  -> no target: launch_directional_projectile -> CombatManager.spawn_directional_missile
  -> get_missile_configuration snapshots all level/world-scaled tuning
  -> projectile lives under CombatManager, so source removal does not cancel it
  -> acquire in targeting_range
	-> aim_mode=TRACK_TARGET: rotate visual_root toward locked target
	-> no target + TARGET_OR_FACING: spawn straight projectile along logical facing
	-> FACING_ONLY: skip acquire_target and always spawn along logical facing
  -> Building.affects_target filters airborne targets
  -> verify attack_range
  -> CombatManager.spawn_projectile
  -> Projectile impact -> CombatTarget.take_damage

MaceAttackStrategy
  -> level 1/2: has_target_in_range gate
  -> level 3 + TARGET_OR_FACING: gate bypass when no target
  -> Building.launch_multi_direction_projectiles
  -> each Projectile shares speed, maximum distance and penetration budget

Laser Building._process
	-> aim_mode=FIXED_FACING: use manually editable facing_index
  -> propagation front advances by current-level speed
  -> ContinuousLaserPath: reflect / Stuff / finite penetration / moving endpoint
  -> hard stop clamps front; blocker removal resumes visible and logical growth
  -> crossed CombatTarget.take_damage_over_time + cold slow
  -> level 2/3 endpoint timer: burst damage + cold (+ level 3 freeze)
  -> copy_attack_triggered: every projection independently retraces and applies the same effects

EnemyUnit blocker query -> BuildingManager.get_path_blocker(next path cells)
  -> enemy attack -> Building.take_structure_damage
  -> BarrierDurability: damage / reflection / delayed regeneration
  -> depleted -> BuildingManager.remove_building(refund=0) -> path released
```

## 函数索引

### BuildingDefinition / BuildingLevelStats

| 函数 | 签名 | 职责 |
|---|---|---|
| `get_level_stats` | `(value: int) -> BuildingLevelStats` | 把等级钳制到已配置范围并返回对应完整参数。 |
| `get_cumulative_cost` | `(value: int) -> float` | 累加从 1 级到目标等级的全部费用，作为主动拆除的无损退款。 |
| `BuildingLevelStats.get_model_asset` | `() -> ModelAssetDefinition` | 返回新模型契约，或兼容包装旧 `visual_scene`。 |
| `get_max_level` | `() -> int` | 返回 `min(3, levels.size())`。 |
| `validate_configuration` | `() -> Array[String]` | 校验身份、放置/朝向枚举、转向速度、1~3 级完整性，并逐级校验全部可编辑参数。BuildingLevelStats 提供同名数值校验。 |
| `is_configured` | `() -> bool` | 仅当 `validate_configuration()` 无错误时返回 true。 |

### Building.gd

- `refresh_world_transform() -> void`：运行时 Terrain 预览/提交后只重新采样格心或共享边坡高，不重建等级、攻击、耐久和冷却状态。

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(definition: BuildingDefinition, cell: Vector3i, grid: GridManager, tiles: TileManager, combat: CombatManager, initial_level: int = 1, preview_mode: bool = false) -> void` | 注入依赖、定位并应用初始等级；预览模式禁用攻击。 |
| `apply_level` | `(value: int) -> bool` | 切换整套等级参数，重建策略与外观。 |
| `can_upgrade` / `get_upgrade_cost` | `() -> bool` / `() -> float` | 判断是否未到上限并读取下一等级费用。 |
| `get_level_stats` | `() -> BuildingLevelStats` | 返回当前级参数事实源。 |
| `get_refund_amount` | `() -> float` | 返回定义中从 1 级到当前级的累计投入。 |
| `is_path_blocker` / `is_structure_alive` | `() -> bool` | 判断是否为可阻挡路径且仍有耐久的屏障。 |
| `take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 委托耐久组件结算实际承伤、反伤和耗尽。 |
| `affects_target` | `(target: Node) -> bool` | 依据当前级 `affects_airborne` 判断攻击或阻挡是否作用于目标。 |
| `restore_durability` / `get_durability_ratio` | `(amount: float) -> float` / `() -> float` | 恢复耐久并返回实际值 / 返回 0~1 耐久比例。 |
| `get_structure_target_position` / `get_structure_hit_radius` | `() -> Vector3` / `() -> float` | 为近战距离和敌方投射物提供通用结构目标契约。 |
| `acquire_target` | `() -> CombatTarget` | 在当前级索敌范围内组建候选；`prioritizes_airborne` 启用且存在空中候选时先收缩分组，再用原优先级更新锁定。 |
| `is_target_in_attack_range` | `(target: CombatTarget) -> bool` | 用独立攻击范围判断目标是否可发射。 |
| `get_targeting_range_world` / `get_attack_range_world` | `() -> float` | 把格数范围转换为世界距离。 |
| `uses_targeting_range` | `() -> bool` | 告诉只读选择表现该建筑是否实际使用圆形索敌候选范围。 |
| `get_instant_damage` / `get_laser_damage_per_second` | `() -> float` | 用当前级三个乘区返回单发伤害或最终 DPS。 |
| `launch_projectile` | `(target: CombatTarget, damage: float) -> Projectile` | 用当前级速度/尺寸/颜色/模型资产通过 CombatManager 发射；导弹开关启用时切换到带目标标记的导弹入口。 |
| `launch_directional_projectile` | `(damage: float, direction_override: Vector3 = Vector3.ZERO) -> Projectile` | 沿逻辑朝向或指定向量发射；导弹开关启用时快照方向并切换到绕圈后直飞的导弹入口。 |
| `launch_multi_direction_projectiles` | `(damage: float) -> Array[Projectile]` | 按当前等级方向数围绕逻辑朝向一次生成全部水平齐射投射物。 |
| `get_projectile_launch_directions` | `() -> Array[Vector3]` | 返回当前逻辑朝向对应的单向或钉锤4/8向水平发射列表；实战齐射以及投射物/激光只读弹道预览共用。 |
| `has_target_in_range` | `() -> bool` | 只检查有效目标是否位于当前级索敌范围，不锁定目标。 |
| `get_projectile_direction_count` / `get_projectile_penetration_count` | `() -> int` / `() -> int` | 返回当前级齐射方向数和额外穿透预算。 |
| `fires_along_facing_without_target` | `() -> bool` | 读取当前级 `projectile_fire_mode`，不按建筑种类硬编码。 |
| `fires_only_along_facing` | `() -> bool` | 当且仅当本级为 `FACING_ONLY` 时返回 true，供攻击策略跳过索敌并隐藏索敌范围。 |
| `get_occupied_cells` | `() -> Array[Vector3i]` | 返回当前建筑真实占格，供选择表现和未来多格建筑复用。 |
| `get_projectile_model_asset` | `() -> ModelAssetDefinition` | 返回复制体投射物必须沿用的当前等级资产。 |
| `uses_missile_projectiles` | `() -> bool` | 读取当前级 `projectile_is_missile`。 |
| `get_missile_configuration` | `() -> Dictionary` | 快照当前级全部导弹参数；格数尺寸转为世界单位，其它键保留秒/比率/角度语义。 |
| `get_action_anchor` | `() -> Vector3` | 返回悬浮操作按钮使用的建筑上方世界锚点。 |
| `rotate_facing` / `set_facing_index` | `(step: int = 1) -> void` / `(value: int) -> void` | 更新世界固定离散朝向。 |
| `update_visual_orientation` / `get_visual_facing_direction` | `(delta: float) -> bool` / `() -> Vector3` | 按 Definition 的追踪能力平滑更新模型姿态，并读取当前视觉前向；不改逻辑 `facing_index`。 |
| `create_copy_visual_snapshot` / `sync_copy_visual_snapshot` | `() -> Node3D` / `(snapshot: Node3D) -> bool` | 创建无行为视觉快照，并把实体模型的子节点变换、可见性与骨骼姿态同步到既有快照。 |
| `shutdown` | `() -> void` | 停止策略并清理锁定。 |

### BuildingSelectionVisualizer / ProjectileTrajectoryPreview

| 函数 | 签名 | 职责 |
|---|---|---|
| `BuildingSelectionVisualizer.set_projectile_reflection_resolver` | `(value: Callable) -> void` | 注入统一最近反射面查询并立即重建当前弹道。 |
| `BuildingSelectionVisualizer.refresh` | `() -> void` | 地形高度或世界位置变化后重建范围、占地与弹道。 |
| `ProjectileTrajectoryPreview.configure_style` | `(feature_enabled: bool, color: Color, minimum_width: float, width_multiplier: float, lift: float, max_segments_per_direction: int) -> void` | 应用可调表现参数，不写入建筑或战斗状态。 |
| `ProjectileTrajectoryPreview.rebuild` | `(building: Building) -> void` | 读取当前级方向、射程和投射物宽度，逐段调用反射查询并生成粗射线网格。 |
| `ProjectileTrajectoryPreview.debug_get_segments` | `() -> Array[Dictionary]` | 返回 `{start, end, length, direction_index, reflection_index}` 深副本供回归检查。 |

### BarrierDurability.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(stats: BuildingLevelStats, preserve_damage: bool) -> void` | 应用本级最大耐久；升级时增加最大值差并保留已有损伤。 |
| `tick` | `(delta: float) -> void` | 计算无伤延迟后的有效回血时长。 |
| `take_damage` | `(amount: float, attacker: Node = null, can_reflect_to_attacker: bool = true) -> float` | 扣耐久、重置脱战计时，按适用性反伤并在归零时发 `depleted`。 |
| `restore` / `is_alive` / `get_ratio` | `(amount: float) -> float` / `() -> bool` / `() -> float` | 恢复耐久、判断有效、读取耐久比例。 |

### BuildingManager.gd

- `refresh_world_transforms() -> void`：批量转发现有实体与放置预览的表面位置刷新；不增删建筑、不扣费、不改变资源产出。

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(grid: GridManager, tiles: TileManager, resources: ResourceManager, combat: CombatManager) -> void` | 注入模块入口，并深度刷新 `.tres` 等级资源缓存。 |
| `place_building` | `(cell: Vector3i, definition: BuildingDefinition, placement_facing: int = -1) -> Building` | 原子放置 1 级建筑并可继承预览朝向。 |
| `export_initial_placements` | `() -> Array[BuildingPlacementData]` | 按稳定空间键导出全部真实建筑；排除预览与镜像虚像。 |
| `load_initial_placements` | `(placements: Array) -> Array[String]` | 免建造费装配开局建筑并计入 cap；任一失败清理本批已装配实体。 |
| `upgrade_selected` | `() -> bool` | 升级当前选择。 |
| `upgrade_building` | `(building: Building) -> bool` | 扣下一等级费用、切换完整参数；失败回滚费用。 |
| `update_preview` | `(cell: Vector3i, definition: BuildingDefinition) -> bool` | 在可建造空格创建/更新不占格虚影。 |
| `set_path_connectivity_validator` | `(value: Callable) -> void` | 注入障碍假设放置校验，不反向持有 Path 模块。 |
| `clear_preview` | `(clear_definition: bool = true) -> void` | 清理虚影；可保留塔种/朝向供跨无效格移动。 |
| `rotate_preview` | `(step: int = 1) -> bool` | 旋转当前虚影。 |
| `remove_building` | `(cell: Vector3i, refund: float = 0.0) -> bool` | 通过幂等释放事务清理占格、计数、回调与建筑产出后销毁建筑。 |
| `remove_selected_building` | `() -> bool` | 原子拆除选中建筑，并全额返还当前级累计建造与升级费用。 |
| `clear_buildings` | `(update_resource_count: bool = true) -> void` | 切关时清理全部建筑和预览。 |
| `select_at` / `rotate_selected` | `(cell: Vector3i) -> Building` / `(step: int = 1) -> bool` | 选择或旋转实际建筑。 |
| `get_path_blocker` | `(cell: Vector3i, target: Node = null) -> Node` | 返回该路径格对指定目标有效且仍存活的屏障。 |
| `resolve_path_blocker` | `(from_cell: Vector3i, to_cell: Vector3i, target: Node = null) -> Node` | 依次查询对指定目标有效的边屏障和终点地块屏障。 |
| `resolve_physical_path_blocker` | `(from_cell: Vector3i, to_cell: Vector3i, target: Node = null) -> Node` | 只查实体边/格屏障；供放置校验与假设镜像图分层合并。 |
| `is_path_cell` | `(cell: Vector3i) -> bool` | 查询关卡路径格缓存。 |
| `_cache_path_cells` | `(level_resource: LevelResource) -> void` | 切关时缓存所有路径格以及出生点/据点保护格。 |
| `_sync_building_income` | `() -> void` | 汇总所有当前级 `resource_per_second`。 |

**信号**：`building_placed`、`building_removed`、`building_selected`、`building_upgraded`、`building_destroyed`、`placement_failed`、`upgrade_failed`、`preview_updated`、`preview_cleared`；Building.`level_changed` / `facing_changed` / `attack_performed` / `durability_changed` / `structure_destroyed`。

## 约定事实源

- 建筑空间唯一键是 Grid `Vector3i cell`；占用事实源是 TileManager。
- 块建筑读取共享格心表面高度；边建筑读取物理边中点的两侧坡面采样并取较高值，因此连续坡面贴边、断崖边不嵌入地形。
- 当前等级事实源是 `Building.level + Building._stats`；禁止把等级差写成隐式全局倍率。
- 1 级 `cost` 是建造费用，2/3 级 `cost` 是升到该级的费用；主动拆除退款唯一由 1..当前级的 `cost` 之和推导。
- `targeting_range` 只决定候选；`attack_range` 决定是否能发射或激光长度，两者不得互相代替。
- `BuildingDefinition.Kind` 序列化索引固定为 `ARROW_TOWER=0`、`LASER_TOWER=1`、`BARRIER=2`、`EDGE_BARRIER=3`、`CROSSBOW_TOWER=4`、`MACE_TOWER=5`、`PULSE_LASER_TOWER=6`；新类型必须继续追加。
- `BuildingDefinition.AimMode` 是转向能力的事实源：`FIXED_FACING=0`、`TRACK_TARGET=1`。不得以 `Kind` 分支写死自动转向。
- 路径格缓存来自当前 LevelResource；普通塔不得占路。屏障可覆盖 BUILDABLE 或 BLOCKED 路面，但不得覆盖未清障的 DESTRUCTIBLE 格。
- 屏障连通性校验不以建筑类型重写寻路；BuildingManager 只提供实体阻挡查询和未登记候选对象，目标据点/路网事实属于 Path 模块。
- 屏障摧毁属于战斗损失，不返还资源；主动拆除属于玩家操作，100% 返还当前级累计费用。
- BuildingManager 的 cell 字典、Tile occupant、ResourceManager 建筑计数和生命周期回调必须作为同一事务更新；外部释放只做无退款清理。
- HEX 档 0 为世界 -30 度，随后每档 +60 度；SQUARE 档 0 为 +X，随后每档 +45 度。

## 使用入口

运行 `scenes/Main.tscn`：底部第三建筑卡为镭射塔（原屏障位置）；屏障玩法与资源仍保留，但不进入默认卡组。R 调整预览朝向，左键放置。

## 已知限制 / 初版不做的部分

- 当前正式美术为空时使用逐级颜色灰盒；模型场景和附加 Scale 的通用规则见 `Presentation_模型资产契约.md`。
- 暂无分支升级树或降级；主动拆除固定全额退款，不支持全局售卖比例或确认弹窗。
- 当前由 MirrorManager 枚举复制来源，尚未形成 CONTRIBUTING 所述统一 `ICopyable` 契约；镭射塔已显式加入现有复制攻击分支。
