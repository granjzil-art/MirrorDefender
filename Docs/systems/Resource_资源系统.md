# 资源系统 · Resource

> 实现状态：M3 已完成单一主资源、建筑/镜子计数上限、关卡基础产出和建筑逐级产出；M4 已接入敌人个体死亡掉落。

## 职责

管理当前主资源、建筑/镜子数量上限、原子消费/注册，以及基础与建筑两路被动产出。敌人死亡掉落的数值归 M4 敌人定义所有，ResourceManager 只提供入账接口。

## 分类 / 做法

- **关卡基础产出**：`LevelResource.base_resource_per_second`，加载关卡时复制到 ResourceManager，不依赖建筑。
- **建筑产出**：每个 `BuildingLevelStats.resource_per_second` 独立编辑；BuildingManager 在放置、升级、移除、清场后汇总所有建筑当前等级的产出。
- **敌人死亡掉落**：WaveManager 只订阅 EnemyUnit 的死亡信号，以 EnemyDefinition.`reward` 调用 `grant_enemy_drop(amount)`；M3 靶标死亡不接资源，到达据点的敌人也不掉落。
- **小数累计**：基础和建筑产出使用两个独立缓冲，累计到整数才调用 `gain()`，避免帧率差异和小数丢失。
- **建筑/镜子上限**：`try_register_building()` 检查 cap、扣费并登记建筑；`try_register_mirror(kind, cost)` 检查复制镜或反射镜的独立 cap，默认金币模式下同一事务扣费并登记该种实体镜。
- **初始陈列注册**：`try_register_initial_building/mirror()` 只检查 cap 并增加计数，不扣 `initial_resource`；仅供关卡静态初始陈列装配，玩家建造不得调用。
- **升级消费**：BuildingManager 读取下一等级的 `cost`，调用 `spend()`；等级切换失败时通过 `upgrade_rollback` 全额退回。
- **拆除退款**：BuildingManager 删除选中建筑时通过 `BuildingDefinition.get_cumulative_cost(current_level)` 累加建造和历次升级费用，传给 `unregister_building(refund)` 100% 返还，使释放占格、减少计数、返还资源保持同一事务。
- **屏障摧毁**：敌人将屏障耐久打到 0 时调用 `unregister_building(0)`，只释放建筑上限和产出，不获得主动删除退款。
- **调试设置**：F1 `resource add/set` 只调用 ResourceManager 公共入口；`set_main_resource` 拒绝非有限数和负数，并以真实差值广播，经济 HUD 无需特殊刷新通道。

## 参数编辑入口

| 数据 | 编辑位置 | 参数 |
|---|---|---|
| 关卡初始资源与基础产出 | `resources/levels/*.tres` 的 `M3 Economy` | `initial_resource`、`building_cap`、`copy_mirror_cap`、`reflect_mirror_cap`、`base_resource_per_second` |
| 镜子单次放置费用 | `resources/mirrors/*.tres -> Placement Economy` | `placement_cost`；只在默认金币模式使用。 |
| 每种建筑每级产出 | `resources/buildings/*.tres -> Levels[n] -> Economy` | `resource_per_second` |
| 敌人个体死亡掉落 | `resources/enemies/*.tres -> Stats` | `reward`；仅被击杀的 EnemyUnit 调用 `grant_enemy_drop()`。 |

默认关卡基础产出为 `0.5/s`；当前箭塔和激光塔三等级产出默认均为 `0.0/s`，可直接在对应等级资源中修改。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `feature_enabled` | true | 资源模块总开关。 |
| `main_resource` / Level.`initial_resource` | 200 | 当前/关卡初始主资源。 |
| `building_cap` | 20 | 原件建筑数量上限。 |
| `copy_mirror_cap` / `reflect_mirror_cap` | 5 / 10 | 复制镜和反射镜的独立实体数量上限。 |
| MirrorDefinition.`placement_cost` | 100 | 默认金币模式的镜子单次放置费用。 |
| `base_resource_per_second` | 0.5 | 当前关卡的基础每秒产出。 |
| BuildingLevelStats.`resource_per_second` | 0.0 | 单个建筑处于该等级时的每秒产出。 |
| BuildingDefinition.`get_cumulative_cost(level)` | 1..当前级 `cost` 之和 | 玩家主动拆除建筑时的无损返还额。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/resource/ResourceManager.gd` | `ResourceManager` / `Node` | **资源唯一入口**；余额、cap、两路被动产出和敌人掉落入账接口。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 持久化初始资源、上限和关卡基础产出。 |
| `scripts/building/BuildingLevelStats.gd` | `BuildingLevelStats` / `Resource` | 持久化每种建筑每级的 `cost` 与 `resource_per_second`。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | 使用原子注册/消费接口并同步当前建筑产出总和。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | 监听 EnemyUnit 死亡，并把 EnemyDefinition.`reward` 结算到资源。 |
| `scripts/ui/EconomyPanel.gd` | `EconomyPanel` / `Control` | 正式显示资源滚动数字和逐事件弹字。 |
| `scripts/debug/RuntimeDebugBindings.gd` | `RuntimeDebugBindings` / `Node` | 把 resource add/set 注册为调试命令，不直接修改字段。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded
  -> ResourceManager.apply_level_configuration(level)
     -> initial_resource / caps / base_resource_per_second

BuildingManager.place / upgrade / downgrade / remove / clear
  -> sum(each Building.current_level.resource_per_second)
  -> ResourceManager.set_building_resource_per_second(total)

BuildingActionPanel downgrade -> BuildingManager.downgrade_selected
  -> ResourceManager.gain(current_level.cost, "building_downgrade_refund")

BuildingActionPanel upgrade -> BuildingManager.upgrade_selected
  -> ResourceManager.spend(next_level.cost, "building_upgrade")

Barrier durability depleted -> BuildingManager.remove_building(cell, 0)
  -> ResourceManager.unregister_building(0), no refund

ResourceManager._process
  -> base buffer -> gain(whole, "base_income")
  -> building buffer -> gain(whole, "building_income")

EnemyUnit.died
  -> WaveManager checks EnemyUnit -> enemy definition reward
  -> ResourceManager.grant_enemy_drop(amount)

resource_changed / limits_changed / income_rates_changed
  -> EconomyPanel / GlobalInfoPanel / BuildCardBar

F1 resource add/set -> RuntimeDebugBindings
  -> ResourceManager.gain / set_main_resource
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `apply_level_configuration` | `(level_resource: LevelResource) -> void` | 复制初始资源、cap 和基础产出，清零计数、建筑产出与缓冲。 |
| `can_afford` | `(cost: float) -> bool` | 判断模块开启、费用和余额均为有限数、费用非负且余额充足。 |
| `spend` | `(cost: float, reason: String = "spend") -> bool` | 原子扣费并广播；失败不改余额。 |
| `gain` | `(amount: float, reason: String = "gain") -> void` | 增加有限正数资源并广播；NaN/Infinity 不改变余额。 |
| `set_main_resource` | `(value: float, reason: String = "set") -> bool` | 设置有限非负余额，以新旧差值广播；非法值返回 false 且不修改状态。 |
| `try_register_building` | `(cost: float) -> bool` | 检查建筑 cap、扣费并增加建筑计数。 |
| `try_register_mirror` | `(mirror_kind: int, cost: float = 0.0, reason: String = "mirror_cost") -> bool` | 原子检查对应镜子 cap/余额、可选扣费并增加该种实体镜计数。 |
| `try_register_initial_building` / `try_register_initial_mirror` | `()` / `(mirror_kind: int) -> bool` | 免付费登记关卡初始实体并增加相应计数，仍严格遵守对应 cap。 |
| `unregister_building` | `(refund: float = 0.0) -> void` | 安全减少建筑计数并可选退款。 |
| `unregister_mirror` | `(mirror_kind: int, rollback_refund: float = 0.0) -> void` | 安全减少对应实体镜计数；只有放置事务回滚可传入退费，玩家删除传 0。 |
| `set_building_resource_per_second` | `(value: float) -> void` | 设置所有当前建筑的有限逐秒产出总和；非有限值被拒绝。 |
| `grant_enemy_drop` | `(amount: float) -> void` | 以 `enemy_drop` 原因入账；M4 敌人死亡调用。 |
| `get_building_resource_per_second` | `() -> float` | 返回建筑产出总和。 |
| `get_total_resource_per_second` | `() -> float` | 返回基础产出与建筑产出之和。 |
| `_flush_income` | `(buffer: float, reason: String) -> float` | 把缓冲整数部分入账并返回余数。 |

**信号**：`resource_changed(current, delta, reason)`、`limits_changed(building_count, building_limit, copy_mirror_count, copy_mirror_limit, reflect_mirror_count, reflect_mirror_limit)`、`income_rates_changed(base_per_second, buildings_per_second)`。

## 约定事实源

- LevelResource 是关卡初始经济与基础产出的事实源；ResourceManager 是当前局余额、计数和累计缓冲事实源。
- 建筑当前级 `BuildingLevelStats.resource_per_second` 是单塔产出的事实源；主动拆除退款由 `BuildingDefinition` 对 1..当前级的 `cost` 动态求和，ResourceManager 不保存塔种固定数值表。
- 累计费用退款只用于玩家主动拆除；战斗摧毁屏障固定传 0，不退款。
- 敌人掉落数值属于 EnemyDefinition，不复用 M3 调试靶标的 reward 作为正式配置；WaveManager 的类型收窄是防止靶标误入账的唯一连接点。
- `reason` 固定使用 `level_loaded`、`building_cost`、`building_upgrade`、`upgrade_rollback`、`base_income`、`building_income`、`enemy_drop` 等可追踪标识。
- 实体复制镜和反射镜通过带 `mirror_kind` 的公共入口参与各自独立上限。默认金币模式成功放置扣费、删除不退费；可选冷却模式传入零费用，其库存、周期累计和拆除返还由 MirrorManager 处理。虚像不注册建筑/镜子、不产出资源、不计任何 cap。
- 所有公开交易入口拒绝 NaN/Infinity，防止一次非法配置永久污染余额或被动产出缓冲。

## 已知限制 / 初版不做的部分

- M4 不把泛用的 `CombatManager.target_killed` 兑换为资源，避免调试靶标或未来中立目标误入账。
- 暂无资源上限、负资源、复利、小数 UI 或离线累计。
- M5 已确认虚像不计入上限和产出；未来变种若要改变经济语义，必须新增显式参数，不能复用原件注册逻辑。
