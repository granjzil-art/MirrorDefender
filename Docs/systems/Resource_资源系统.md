# 资源系统 · Resource

> 实现状态：M3 已完成单一主资源、建筑/镜子计数上限、五类独立产出开关和 LevelResource 关卡配置。

## 职责
管理唯一主资源、建造事务所需的消费/注册接口、建筑与镜子数量上限，以及五类可独立开关的产出来源。

## 分类 / 做法
- **单一主资源**：`main_resource: float` 支持小数速率累计；UI 只显示向下取整值。
- **建筑/镜子上限**：`try_register_building/mirror()` 同时检查 cap 和资源并扣费，防止调用方分步产生竞态。
- **击杀掉落**：CombatManager.target_killed 经 Main 调 `grant_kill_drop(reward)`。
- **占领地块产出**：当前定义为“被建筑占用的可建造格数量 × tile_income_rate”；BuildingManager 注册/移除时同步数量。
- **生产建筑产出**：`producer_count × producer_income_rate`；当前两种塔不是生产建筑，但完整计数接口已实现。
- **时间增长**：固定 `time_growth_rate` 每秒。
- **破坏地块**：ResourceManager 订阅 TileManager.obstacle_destroyed，成功清障后一次性获得配置数量。
- 三类每秒产出各自使用小数缓冲，累计到整数才进入主资源，避免帧率影响和小数丢失。

## 关键参数

| 参数 | 默认 | 说明 |
|---|---:|---|
| `feature_enabled` | true | 资源模块总开关。 |
| `main_resource` / Level.`initial_resource` | 200 | 当前/关卡初始主资源。 |
| `building_cap` | 20 | 原件建筑数量上限。 |
| `mirror_cap` | 6 | 镜子数量上限，供 M5/M6 使用。 |
| `kill_drop_enabled` | true | 击杀奖励开关。 |
| `tile_income_enabled` / `tile_income_rate` | true / 1 | 每个建筑占用格每秒产出。 |
| `producer_income_enabled` / `producer_income_rate` | true / 2 | 每个生产建筑每秒产出。 |
| `time_growth_enabled` / `time_growth_rate` | true / 0.5 | 全局自然增长。 |
| `destroy_tile_income_enabled` / `destroy_tile_income_amount` | true / 20 | 清障一次性产出。 |

所有参数同时在 ResourceManager Inspector 和 LevelResource 的 M3 分组可见；加载关卡时 LevelResource 覆盖运行时值。

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/resource/ResourceManager.gd` | `ResourceManager` / `Node` | **资源唯一入口**；余额、cap 计数、五类产出和关卡配置。 |
| `scripts/level/LevelResource.gd` | `LevelResource` / `Resource` | 持久化关卡初始资源、上限和产出开关/速率。 |
| `scripts/building/BuildingManager.gd` | `BuildingManager` / `Node3D` | 使用原子建筑注册接口并同步占用格/生产建筑数量。 |
| `scripts/Main.gd` | `Node3D` | 连接战斗击杀奖励，并在 LevelLoader 成功后应用关卡经济。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded -> Main -> ResourceManager.apply_level_configuration

BuildingManager.place_building
  -> ResourceManager.can_add_building / can_afford
  -> ResourceManager.try_register_building(cost)

CombatManager.target_killed(reward) -> grant_kill_drop
TileManager.obstacle_destroyed -> grant_destroy_tile_income
ResourceManager._process -> tile / producer / time buffers -> gain

resource_changed / limits_changed -> M3DebugPanel / future production HUD
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `configure` | `(tile_manager: TileManager) -> void` | 注入 Tile 入口并订阅清障信号。 |
| `apply_level_configuration` | `(level_resource: LevelResource) -> void` | 复制经济参数，重置余额、计数和累计缓冲。 |
| `can_afford` | `(cost: float) -> bool` | 判断模块开启、非负费用且余额充足。 |
| `spend` | `(cost: float, reason: String = "spend") -> bool` | 扣费并广播；失败不改变余额。 |
| `gain` | `(amount: float, reason: String = "gain") -> void` | 增加正数资源并广播。 |
| `can_add_building` / `can_add_mirror` | `() -> bool` | 检查相应计数上限。 |
| `try_register_building` / `try_register_mirror` | `(cost: float) -> bool` | 原子检查 cap、扣费、增加计数。 |
| `unregister_building` / `unregister_mirror` | `(refund: float = 0.0) -> void` | 安全减少计数并可选返还。 |
| `set_occupied_tile_count` | `(value: int) -> void` | 设置占领地块产出基数。 |
| `set_producer_count` | `(value: int) -> void` | 设置生产建筑产出基数。 |
| `grant_kill_drop` | `(amount: float) -> void` | 按开关结算击杀奖励。 |
| `grant_destroy_tile_income` | `() -> void` | 按开关结算清障固定奖励。 |
| `get_building_count` / `get_mirror_count` | `() -> int` | 返回当前 cap 计数。 |
| `_flush_income` | `(buffer: float, reason: String) -> float` | 把累计整数部分入账并返回余数。 |

**信号**：`resource_changed(current, delta, reason)`、`limits_changed(building_count, building_limit, mirror_count, mirror_limit)`。

## 约定事实源
- LevelResource 是每关初始经济配置事实源；ResourceManager 是当前局余额与计数事实源。
- 建筑原件计入 building_cap；未来 M5 投影是否计数必须遵循 Mirror 文档，不得直接改 ResourceManager 计数。
- `reason` 使用 `building_cost`、`mirror_cost`、`kill_drop`、`tile_income`、`producer_income`、`time_growth`、`destroy_tile` 等稳定字符串，供 HUD/统计订阅。
- 每秒产出以 delta 累计，不依赖固定帧率。

## 已知限制 / 初版不做的部分
- 只有一种货币，不设资源存量上限、利息或溢出返还。
- 当前无生产建筑塔种，因此 producer source 的默认运行时计数为 0。
- 不持久化局内余额；SaveManager 属于后续范围。
