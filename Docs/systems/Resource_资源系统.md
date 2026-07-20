# 资源系统 · Resource

> 实现状态：M3 已完成单一主资源、建筑/镜子计数上限、关卡基础产出和建筑逐级产出；M4 已接入敌人个体死亡掉落。

## 职责

管理当前主资源、建筑/镜子数量上限、原子消费/注册，以及基础与建筑两路被动产出。敌人死亡掉落的数值归 M4 敌人定义所有，ResourceManager 只提供入账接口。

## 分类 / 做法

- **关卡基础产出**：`LevelResource.base_resource_per_second`，加载关卡时复制到 ResourceManager，不依赖建筑。
- **建筑产出**：每个 `BuildingLevelStats.resource_per_second` 独立编辑；BuildingManager 在放置、升级、移除、清场后汇总所有建筑当前等级的产出。
- **敌人死亡掉落**：WaveManager 只订阅 EnemyUnit 的死亡信号，以 EnemyDefinition.`reward` 调用 `grant_enemy_drop(amount)`；M3 靶标死亡不接资源，到达据点的敌人也不掉落。
- **小数累计**：基础和建筑产出使用两个独立缓冲，累计到整数才调用 `gain()`，避免帧率差异和小数丢失。
- **建筑/镜子上限**：`try_register_building/mirror()` 同时检查 cap 和余额并扣费；调用方不拆成非原子步骤。
- **升级消费**：BuildingManager 读取下一等级的 `cost`，调用 `spend()`；等级切换失败时通过 `upgrade_rollback` 全额退回。
- **删除退款**：BuildingManager 删除选中建筑时读取当前 `BuildingLevelStats.refund_amount`，传给 `unregister_building(refund)`，使释放占格、减少计数、返还资源保持同一事务。
- **屏障摧毁**：敌人将屏障耐久打到 0 时调用 `unregister_building(0)`，只释放建筑上限和产出，不获得主动删除退款。

## 参数编辑入口

| 数据 | 编辑位置 | 参数 |
|---|---|---|
| 关卡初始资源与基础产出 | `resources/levels/*.tres` 的 `M3 Economy` | `initial_resource`、`building_cap`、`mirror_cap`、`base_resource_per_second` |
| 每种建筑每级产出 | `resources/buildings/*.tres -> Levels[n] -> Economy` | `resource_per_second` |
| 敌人个体死亡掉落 | `resources/enemies/*.tres -> Stats` | `reward`；仅被击杀的 EnemyUnit 调用 `grant_enemy_drop()`。 |

默认关卡基础产出为 `0.5/s`；当前箭塔和激光塔三等级产出默认均为 `0.0/s`，可直接在对应等级资源中修改。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `feature_enabled` | true | 资源模块总开关。 |
| `main_resource` / Level.`initial_resource` | 200 | 当前/关卡初始主资源。 |
| `building_cap` | 20 | 原件建筑数量上限。 |
| `mirror_cap` | 6 | 镜子数量上限，供 M5/M6 使用。 |
| `base_resource_per_second` | 0.5 | 当前关卡的基础每秒产出。 |
| BuildingLevelStats.`resource_per_second` | 0.0 | 单个建筑处于该等级时的每秒产出。 |
| BuildingLevelStats.`refund_amount` | 塔种/等级定 | 删除处于该级建筑时的精确返还额。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/resource/ResourceManager.gd` | `ResourceManager` / `Node` | **资源唯一入口**；余额、cap、两路被动产出和敌人掉落入账接口。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 持久化初始资源、上限和关卡基础产出。 |
| `scripts/building/BuildingLevelStats.gd` | `BuildingLevelStats` / `Resource` | 持久化每种建筑每级的 `cost` 与 `resource_per_second`。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | 使用原子注册/消费接口并同步当前建筑产出总和。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | 监听 EnemyUnit 死亡，并把 EnemyDefinition.`reward` 结算到资源。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 显示当前资源、总每秒产出和建筑上限。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded
  -> ResourceManager.apply_level_configuration(level)
     -> initial_resource / caps / base_resource_per_second

BuildingManager.place / upgrade / remove / clear
  -> sum(each Building.current_level.resource_per_second)
  -> ResourceManager.set_building_resource_per_second(total)

BuildingActionPanel delete -> BuildingManager.remove_selected_building
  -> ResourceManager.unregister_building(current_level.refund_amount)

Barrier durability depleted -> BuildingManager.remove_building(cell, 0)
  -> ResourceManager.unregister_building(0), no refund

ResourceManager._process
  -> base buffer -> gain(whole, "base_income")
  -> building buffer -> gain(whole, "building_income")

EnemyUnit.died
  -> WaveManager checks EnemyUnit -> enemy definition reward
  -> ResourceManager.grant_enemy_drop(amount)

resource_changed / limits_changed / income_rates_changed
  -> M3DebugPanel / future production HUD
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `apply_level_configuration` | `(level_resource: LevelResource) -> void` | 复制初始资源、cap 和基础产出，清零计数、建筑产出与缓冲。 |
| `can_afford` | `(cost: float) -> bool` | 判断模块开启、费用非负且余额充足。 |
| `spend` | `(cost: float, reason: String = "spend") -> bool` | 原子扣费并广播；失败不改余额。 |
| `gain` | `(amount: float, reason: String = "gain") -> void` | 增加正数资源并广播。 |
| `try_register_building` / `try_register_mirror` | `(cost: float) -> bool` | 检查 cap、扣费并增加相应计数。 |
| `unregister_building` / `unregister_mirror` | `(refund: float = 0.0) -> void` | 安全减少计数并可选退款。 |
| `set_building_resource_per_second` | `(value: float) -> void` | 设置所有当前建筑的逐秒产出总和。 |
| `grant_enemy_drop` | `(amount: float) -> void` | 以 `enemy_drop` 原因入账；M4 敌人死亡调用。 |
| `get_building_resource_per_second` | `() -> float` | 返回建筑产出总和。 |
| `get_total_resource_per_second` | `() -> float` | 返回基础产出与建筑产出之和。 |
| `_flush_income` | `(buffer: float, reason: String) -> float` | 把缓冲整数部分入账并返回余数。 |

**信号**：`resource_changed(current, delta, reason)`、`limits_changed(building_count, building_limit, mirror_count, mirror_limit)`、`income_rates_changed(base_per_second, buildings_per_second)`。

## 约定事实源

- LevelResource 是关卡初始经济与基础产出的事实源；ResourceManager 是当前局余额、计数和累计缓冲事实源。
- 建筑当前级 `BuildingLevelStats.resource_per_second` 和 `refund_amount` 分别是单塔产出、删除退款的事实源；ResourceManager 不保存塔种固定数值表。
- `refund_amount` 只用于玩家主动删除；战斗摧毁屏障固定传 0，不从配置退款。
- 敌人掉落数值属于 EnemyDefinition，不复用 M3 调试靶标的 reward 作为正式配置；WaveManager 的类型收窄是防止靶标误入账的唯一连接点。
- `reason` 固定使用 `level_loaded`、`building_cost`、`building_upgrade`、`upgrade_rollback`、`base_income`、`building_income`、`enemy_drop` 等可追踪标识。
- 实体复制镜通过 `try_register_mirror(copy_mirror_definition.cost)` 与 `unregister_mirror(refund)` 参与镜子上限和经济；虚像不注册建筑/镜子、不产出资源、不计任何 cap。

## 已知限制 / 初版不做的部分

- M4 不把泛用的 `CombatManager.target_killed` 兑换为资源，避免调试靶标或未来中立目标误入账。
- 暂无资源上限、负资源、复利、小数 UI 或离线累计。
- M5 已确认虚像不计入上限和产出；未来变种若要改变经济语义，必须新增显式参数，不能复用原件注册逻辑。
