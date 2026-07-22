# 建筑系统 · Building

> 实现状态：已完成箭塔、激光塔与屏障、三级完整参数、放置虚影、升级、逐级外观/产出、配置化目标追踪转向，以及屏障耐久、脱战回血和反伤。

## 职责

定义可放置防御建筑，用 `BuildingDefinition + BuildingLevelStats` 组合建筑身份和每级完整参数。`BuildingManager` 是放置、路径规则、预览、升级、占用、选择和移除的唯一入口。

## 分类 / 做法

- **三级参数**：建筑初始 1 级、上限 3 级。`levels[0..2]` 分别保存 1~3 级的完整经济、战斗、投射物和表现参数；升级直接切换到下一份参数，不把上一等级参数乘算后继承。
- **检视配置**：每个 `BuildingDefinition.inspection_display` 可独立编辑右侧详情中的显示名称、功能说明、对象可见性和字段行；不参与建筑玩法结算，虚像沿用根源建筑配置。
- **伤害公式**：单发伤害为当前级 `base_damage × level_factor × extra_factor`；持续伤害为当前级 `laser_dps × level_factor × extra_factor × delta`。`level_factor` 是当前建筑等级数据的一部分，不是全局等级曲线。
- **箭塔**：在 `targeting_range` 内选择目标，只在目标进入 `attack_range` 后发射投射物；伤害在投射物命中时结算。正式资源使用 `TRACK_TARGET`，锁定期间只转动视觉姿态，不改写放置 `facing_index`。
- **激光塔**：不索敌，使用 `FIXED_FACING`，沿玩家手动设置的世界朝向在 `attack_range` 内持续命中线段上的全部目标，按帧结算 DPS。
- **空中适用性**：每级 `affects_airborne` 统一控制箭塔候选、激光线段伤害、屏障阻挡与反伤是否作用于飞行敌人；升级切换到新等级自己的配置。
- **屏障**：`BuildingDefinition.Kind.BARRIER`，只允许放在敌人路径格；可跨越不可建造路面规则占格，但不能覆盖未清障障碍、出生点、据点、已有占用或敌人当前所在格。普通塔不能占据路径格。
- **耐久与升级**：屏障每级独立配置 `max_durability`。升级时最大耐久的增加量同步加到当前耐久，保留升级前已经损失的绝对耐久。
- **脱战回血**：屏障每次受伤重置计时；连续 `regeneration_delay` 秒未受伤后，按 `regeneration_per_second` 回耐久。大 delta 只结算越过延迟后的时间。
- **反伤与摧毁**：`damage_reflection_ratio` 按屏障实际承受伤害反射给攻击者；归零后由 BuildingManager 无退款移除、释放路径占位和建筑上限。玩家主动删除仍使用本级 `refund_amount`。
- **放置预览**：建造模式悬停可建造空格时创建不占格、不攻击的 1 级半透明建筑；预览保留塔种和朝向，R 旋转虚影，左键放置时继承该朝向。
- **无效格信息**：未选择塔种或当前格不可放置时不创建虚影；Main HUD 显示地块类型、高度、障碍/占用对象和占位建筑等级、索敌范围、射程。
- **美术替换**：每一级可指定 `visual_scene: PackedScene`。未指定时使用该级 `tower_color` 生成灰盒塔；`attack_color` 控制方向标记、箭/激光颜色。
- **卡片美术替换**：`BuildingDefinition.card_icon` 是 M6 正式卡槽的可选 `Texture2D` 接口；未配置时 BuildCardBar 使用建筑名首字灰盒，不影响资源校验或放置。
- **资源产出**：每一级独立配置 `resource_per_second`；放置、升级或移除后，BuildingManager 汇总当前所有建筑的当前级产出并同步到 ResourceManager。
- **选中操作**：选择模式点中建筑后，在其地块上方投影出删除、升级、旋转三个悬浮按钮；点空格立即隐藏。升级满级时仅升级按钮禁用，旋转不消耗资源。
- **删除退款**：每级 `refund_amount` 是删除该级建筑时的精确返还额。默认数值约为累计建造/升级投入的 50%，但不从费用自动推导。
- **放置事务**：依次校验定义、边界、`TileManager.can_place()`、建筑上限和资源。占格或扣费失败会回滚，不留下半放置建筑。
- **正式单次放置**：BuildingManager 仍维持通用“放置后选中”兼容行为；M6 `RuntimeInteractionController` 在卡片放置完成后立即清除该选择，并让成功/失败统一回 `SELECT`。其他调试或测试入口不受此 UI 规则反向耦合。
- **移除事务**：主动删除、战斗摧毁、切关清理和外部 `queue_free()` 共用幂等释放路径，统一解除信号、清除字典/地块占位、释放建筑上限、选择和产出；同一建筑不会重复退款或重复注销。
- **逻辑朝向与视觉朝向**：HEX 逻辑朝向为 6 档、SQUARE 为 8 档，不读取相机 yaw。`FIXED_FACING` 的逻辑和模型都跟随 `facing_index`；`TRACK_TARGET` 只在此基础上转动 `_visual_root` 追踪当前目标，失去目标后保持最后视觉朝向。

## 参数编辑入口

在 Godot 检视面板打开：

- `resources/buildings/ArrowTower.tres`
- `resources/buildings/LaserTower.tres`
- `resources/buildings/Barrier.tres`

展开 `Levels` 数组中的三个 `BuildingLevelStats`。数组第 0/1/2 项对应建筑 1/2/3 级。

Definition 根节点的 `Orientation` 分组控制通用转向能力：

| 参数 | 说明 |
|---|---|
| `aim_mode` | `FIXED_FACING` 只跟随手动逻辑朝向；`TRACK_TARGET` 使视觉姿态追踪已锁定目标。新的转向索敌建筑应通过此字段声明能力，不在 Building 中按种类写死。 |
| `visual_turn_speed_degrees` | 追踪模式每秒最大视觉转向角度；不影响索敌、攻击频率或发射条件。 |
| `card_icon` | M6 正式卡槽图标接口；可为空，空值使用名称首字灰盒。 |

| 分组 | 参数 | 说明 |
|---|---|---|
| Economy | `cost` | 1 级为建造费用；2、3 级为升到该级的费用。 |
| Economy | `refund_amount` | 删除处于该级的建筑时返还的精确主资源。 |
| Economy | `resource_per_second` | 该建筑处于本级时每秒提供的资源。 |
| Combat | `base_damage` | 单发攻击的基础伤害。 |
| Combat | `affects_airborne` | 本级攻击或屏障效果是否作用于飞行敌人；默认 true 兼容旧资源。 |
| Combat | `targeting_range` | 索敌候选半径，单位为格。 |
| Combat | `attack_range` | 允许发射/激光长度，单位为格，与索敌范围独立。 |
| Combat | `attacks_per_second` | 单发攻击频率。 |
| Combat | `laser_dps` | 持续攻击的基础每秒伤害。 |
| Combat | `level_factor` | 本级独立等级伤害因子。 |
| Combat | `extra_factor` | 其它伤害乘区预留。 |
| Combat | `target_priority` | 最近、最远、最高血、最低血、最快、首个进入、锁定。 |
| Defense | `max_durability` | 屏障本级最大耐久；塔类忽略。 |
| Defense | `regeneration_delay` | 受伤后进入回血所需的无伤秒数。 |
| Defense | `regeneration_per_second` | 脱战后的每秒耐久恢复量，0 表示不回血。 |
| Defense | `damage_reflection_ratio` | 按实际承伤反射给攻击者的比例，范围 0~1。 |
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
| `scripts/building/BuildingDefinition.gd` | `BuildingDefinition` / `Resource` | 建筑种类、显示名和最多三项等级数据。 |
| `scripts/shared/ConfigurationValidator.gd` | `ConfigurationValidator` / `RefCounted` | BuildingDefinition/BuildingLevelStats 共用的有限数、范围、颜色和嵌套错误校验。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | 当前级运行时实体；装配攻击/耐久组件、外观、朝向和预览状态。 |
| `scripts/building/BarrierDurability.gd` | `BarrierDurability` / `RefCounted` | 屏障耐久、升级保伤、脱战回血、反伤和耗尽信号。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | **建筑唯一入口**；放置事务、预览、升级、占用、选择、旋转、移除和产出汇总。 |
| `resources/buildings/ArrowTower.tres` | `BuildingDefinition` | 箭塔三等级参数。 |
| `resources/buildings/LaserTower.tres` | `BuildingDefinition` | 激光塔三等级参数。 |
| `resources/buildings/Barrier.tres` | `BuildingDefinition` | 屏障三等级耐久、回血、反伤与经济参数。 |
| `scripts/combat/ArrowAttackStrategy.gd` | `ArrowAttackStrategy` / `IAttackStrategy` | 单目标冷却、射程校验和投射物发射。 |
| `scripts/combat/LaserAttackStrategy.gd` | `LaserAttackStrategy` / `IAttackStrategy` | 固定方向线段、穿透查询与持续伤害。 |
| `scripts/combat/Projectile.gd` | `Projectile` / `Node3D` | 恒定短直线表现、追踪飞行、最大距离与命中结算。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 建造模式、升级按钮、预览/错误状态和经济摘要。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 将选中建筑上方世界坐标投影为删除、升级、旋转悬浮操作。 |

### 模块调用关系 / 数据流

```text
M3DebugPanel 建造模式 + Main 鼠标悬停
  -> BuildingManager.update_preview(cell, definition)
  -> valid: preview Building(level=1, preview=true), no Tile occupant
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
  -> delete: remove_selected_building -> unregister_building(current_level.refund_amount)
  -> upgrade: upgrade_selected
  -> rotate: rotate_selected(+1), no resource cost

Arrow Building._process
  -> acquire in targeting_range
	-> aim_mode=TRACK_TARGET: rotate visual_root toward locked target
  -> Building.affects_target filters airborne targets
  -> verify attack_range
  -> CombatManager.spawn_projectile
  -> Projectile impact -> CombatTarget.take_damage

Laser Building._process
	-> aim_mode=FIXED_FACING: use manually editable facing_index
  -> fixed facing segment of attack_range
  -> applicable touched CombatTarget.take_damage(final_dps * delta)

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
| `get_max_level` | `() -> int` | 返回 `min(3, levels.size())`。 |
| `validate_configuration` | `() -> Array[String]` | 校验身份、放置/朝向枚举、转向速度、1~3 级完整性，并逐级校验全部可编辑参数。BuildingLevelStats 提供同名数值校验。 |
| `is_configured` | `() -> bool` | 仅当 `validate_configuration()` 无错误时返回 true。 |

### Building.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(definition: BuildingDefinition, cell: Vector3i, grid: GridManager, tiles: TileManager, combat: CombatManager, initial_level: int = 1, preview_mode: bool = false) -> void` | 注入依赖、定位并应用初始等级；预览模式禁用攻击。 |
| `apply_level` | `(value: int) -> bool` | 切换整套等级参数，重建策略与外观。 |
| `can_upgrade` / `get_upgrade_cost` | `() -> bool` / `() -> float` | 判断是否未到上限并读取下一等级费用。 |
| `get_level_stats` | `() -> BuildingLevelStats` | 返回当前级参数事实源。 |
| `get_refund_amount` | `() -> float` | 返回当前级配置的精确删除退款。 |
| `is_path_blocker` / `is_structure_alive` | `() -> bool` | 判断是否为可阻挡路径且仍有耐久的屏障。 |
| `take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 委托耐久组件结算实际承伤、反伤和耗尽。 |
| `affects_target` | `(target: Node) -> bool` | 依据当前级 `affects_airborne` 判断攻击或阻挡是否作用于目标。 |
| `restore_durability` / `get_durability_ratio` | `(amount: float) -> float` / `() -> float` | 恢复耐久并返回实际值 / 返回 0~1 耐久比例。 |
| `get_structure_target_position` / `get_structure_hit_radius` | `() -> Vector3` / `() -> float` | 为近战距离和敌方投射物提供通用结构目标契约。 |
| `acquire_target` | `() -> CombatTarget` | 在当前级索敌范围内按优先级更新锁定目标。 |
| `is_target_in_attack_range` | `(target: CombatTarget) -> bool` | 用独立攻击范围判断目标是否可发射。 |
| `get_targeting_range_world` / `get_attack_range_world` | `() -> float` | 把格数范围转换为世界距离。 |
| `get_instant_damage` / `get_laser_damage_per_second` | `() -> float` | 用当前级三个乘区返回单发伤害或最终 DPS。 |
| `launch_projectile` | `(target: CombatTarget, damage: float) -> Projectile` | 用当前级速度/尺寸/颜色通过 CombatManager 发射。 |
| `get_action_anchor` | `() -> Vector3` | 返回悬浮操作按钮使用的建筑上方世界锚点。 |
| `rotate_facing` / `set_facing_index` | `(step: int = 1) -> void` / `(value: int) -> void` | 更新世界固定离散朝向。 |
| `update_visual_orientation` / `get_visual_facing_direction` | `(delta: float) -> bool` / `() -> Vector3` | 按 Definition 的追踪能力平滑更新模型姿态，并读取当前视觉前向；不改逻辑 `facing_index`。 |
| `create_copy_visual_snapshot` / `sync_copy_visual_snapshot` | `() -> Node3D` / `(snapshot: Node3D) -> bool` | 创建无行为视觉快照，并把实体模型的子节点变换、可见性与骨骼姿态同步到既有快照。 |
| `shutdown` | `() -> void` | 停止策略并清理锁定。 |

### BarrierDurability.gd

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(stats: BuildingLevelStats, preserve_damage: bool) -> void` | 应用本级最大耐久；升级时增加最大值差并保留已有损伤。 |
| `tick` | `(delta: float) -> void` | 计算无伤延迟后的有效回血时长。 |
| `take_damage` | `(amount: float, attacker: Node = null, can_reflect_to_attacker: bool = true) -> float` | 扣耐久、重置脱战计时，按适用性反伤并在归零时发 `depleted`。 |
| `restore` / `is_alive` / `get_ratio` | `(amount: float) -> float` / `() -> bool` / `() -> float` | 恢复耐久、判断有效、读取耐久比例。 |

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
| `remove_building` | `(cell: Vector3i, refund: float = 0.0) -> bool` | 通过幂等释放事务清理占格、计数、回调与建筑产出后销毁建筑。 |
| `remove_selected_building` | `() -> bool` | 按选中建筑当前级 `refund_amount` 原子删除并返还资源。 |
| `clear_buildings` | `(update_resource_count: bool = true) -> void` | 切关时清理全部建筑和预览。 |
| `select_at` / `rotate_selected` | `(cell: Vector3i) -> Building` / `(step: int = 1) -> bool` | 选择或旋转实际建筑。 |
| `get_path_blocker` | `(cell: Vector3i, target: Node = null) -> Node` | 返回该路径格对指定目标有效且仍存活的屏障。 |
| `resolve_path_blocker` | `(from_cell: Vector3i, to_cell: Vector3i, target: Node = null) -> Node` | 依次查询对指定目标有效的边屏障和终点地块屏障。 |
| `is_path_cell` | `(cell: Vector3i) -> bool` | 查询关卡路径格缓存。 |
| `_cache_path_cells` | `(level_resource: LevelResource) -> void` | 切关时缓存所有路径格以及出生点/据点保护格。 |
| `_sync_building_income` | `() -> void` | 汇总所有当前级 `resource_per_second`。 |

**信号**：`building_placed`、`building_removed`、`building_selected`、`building_upgraded`、`building_destroyed`、`placement_failed`、`upgrade_failed`、`preview_updated`、`preview_cleared`；Building.`level_changed` / `facing_changed` / `attack_performed` / `durability_changed` / `structure_destroyed`。

## 约定事实源

- 建筑空间唯一键是 Grid `Vector3i cell`；占用事实源是 TileManager。
- 当前等级事实源是 `Building.level + Building._stats`；禁止把等级差写成隐式全局倍率。
- 1 级 `cost` 是建造费用，2/3 级 `cost` 是升到该级的费用；`refund_amount` 是删除当前级的精确返还，不由 `cost` 自动计算。
- `targeting_range` 只决定候选；`attack_range` 决定是否能发射或激光长度，两者不得互相代替。
- `BuildingDefinition.Kind` 当前固定为 `ARROW_TOWER=0`、`LASER_TOWER=1`、`BARRIER=2`、`EDGE_BARRIER=3`。
- `BuildingDefinition.AimMode` 是转向能力的事实源：`FIXED_FACING=0`、`TRACK_TARGET=1`。不得以 `Kind` 分支写死自动转向。
- 路径格缓存来自当前 LevelResource；普通塔不得占路。屏障可覆盖 BUILDABLE 或 BLOCKED 路面，但不得覆盖未清障的 DESTRUCTIBLE 格。
- 屏障摧毁属于战斗损失，不返还资源；主动删除属于玩家操作，按本级 `refund_amount` 返还。
- BuildingManager 的 cell 字典、Tile occupant、ResourceManager 建筑计数和生命周期回调必须作为同一事务更新；外部释放只做无退款清理。
- HEX 档 0 为世界 -30 度，随后每档 +60 度；SQUARE 档 0 为 +X，随后每档 +45 度。

## 使用入口

运行 `scenes/Main.tscn`：右上建筑面板选择箭塔/激光塔/屏障，移动鼠标查看虚影，R 调整预览朝向，左键放置。屏障虚影只会出现在路径的非保护格；选中后左侧 HUD 显示耐久、脱战延迟、回血和反伤。切回“选择”可使用删除、升级、旋转按钮。

## 已知限制 / 初版不做的部分

- 当前正式美术为空时使用逐级颜色灰盒；`visual_scene` 已预留，但资产制作与动画不属于 M3。
- 暂无分支升级树或降级；删除只使用每级固定退款，不支持全局售卖比例或确认弹窗。
- M5 投影镜像已覆盖塔、地块屏障和地块元素；当前由 MirrorManager 枚举复制来源，尚未形成 CONTRIBUTING 所述统一 `ICopyable` 契约，该扩展点在架构治理批次 5 处理。M6 再加入反射镜与镜面光路。
