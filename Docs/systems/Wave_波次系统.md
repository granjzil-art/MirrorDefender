# 波次系统 · Wave

> 实现状态：M4 已完成资源化波次/出怪组、全局延迟时间轴、胜负状态、运行时控制面板与关卡编辑器波次页。

## 职责

驱动经典塔防固定波次。玩家只需手动开始第一波；从这次点击起，所有 SpawnGroup 按各自 `start_delay` 在同一条全局时间轴上自动开始。所有组生成完且场上敌人清空后胜利，据点归零则失败。

## 分类 / 做法

- **WaveDefinition**：持有若干 SpawnGroupDefinition，负责编辑组织、显示名称和逐波完成事件；它不阻塞后续波次计时。
- **SpawnGroupDefinition**：直接引用敌人、出生点和路径；独立配置数量、出怪间隔，以及距第一波开始的延迟。
- **状态机**：`NO_WAVES -> READY -> ACTIVE`，终态为 `VICTORY` 或 `DEFEAT`；只有 READY 到 ACTIVE 需要玩家操作一次。
- **全局时间轴**：WaveManager 在首次点击时为全部波次建立生成状态；每组首只敌人的时间为 `start_delay`，后续敌人按 `interval` 生成。
- **波次重叠**：不同波次可以同时出怪。某波第一次实际生成时发送 `wave_started`；该波组全部生成且该波存活敌人为零时发送 `wave_completed`。
- **胜负**：全部波次的全部组生成结束且场上敌人清空后胜利；BaseCore.defeated 会取消待生成状态、清理单位并失败。
- **屏障联调**：Main 将 BuildingManager 的阻挡查询 Callable 注入 WaveManager；每个新 EnemyUnit 同时获得路径世界点、路径格、关卡格距和该查询接口。切关/失败会连同敌方投射物清理。
- **运行时入口**：右侧 `WaveStatusPanel` 在 READY 显示“开始第一波”；进入 ACTIVE 后按钮禁用，不再要求点击后续波次。
- **编辑**：关卡编辑器“波次”页可增删波次和出怪组，选择敌人/入口/路径，并修改数量、间隔和“距第一波开始延迟”。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| LevelResource | `waves` | 固定波次数组，波次用于组织和显示，不建立串行等待关系。 |
| WaveDefinition | `display_name` | 编辑器/调试显示名。 |
| SpawnGroupDefinition | `enemy` | 直接引用 EnemyDefinition。 |
| SpawnGroupDefinition | `count` / `interval` | 生成数量与同组相邻敌人的生成间隔。 |
| SpawnGroupDefinition | `start_delay` | 从玩家首次点击“开始第一波”到本组首只敌人生成的全局延迟秒数。 |
| SpawnGroupDefinition | `spawn_point` / `path` | 直接引用本关入口与路线。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/wave/WaveDefinition.gd` | `WaveDefinition` / `Resource` | 一波的名称和出怪组数组。 |
| `scripts/wave/SpawnGroupDefinition.gd` | `SpawnGroupDefinition` / `Resource` | 一条敌人生成时间流。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | **波次唯一入口**；全局计时、生成、逐波事件、奖励和胜负。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 运行时波次状态与首次开始按钮。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` | 两波全局时间轴示例；第二波在 8/9/10 秒生成步兵、疾行者和弓箭手组。 |

### 数据流

```text
LevelLoader.level_loaded -> Main
  -> PathManager.load_level / BaseCore.load_level / WaveManager.load_level

WaveStatusPanel.start first wave -> WaveManager.start_battle
  -> build every wave/group timeline from t=0
  -> SpawnGroup.start_delay + interval -> EnemyUnit(path points + cells + blocker Callable)
  -> CombatManager.register_target
  -> Enemy died -> ResourceManager.grant_enemy_drop
  -> each wave groups exhausted + its active enemies empty -> wave_completed
  -> all groups exhausted + all active enemies empty -> VICTORY

EnemyUnit.reached_base -> BaseCore.take_damage
  -> BaseCore.defeated -> WaveManager.DEFEAT
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `WaveManager.configure` | `(path_manager: PathManager, combat_manager: CombatManager, resource_manager: ResourceManager, base_core: BaseCore, path_blocker_resolver: Callable = Callable()) -> void` | 注入运行时公共入口和可选路径屏障查询。 |
| `WaveManager.load_level` | `(level_resource: LevelResource) -> void` | 清理旧单位、重置全局时间轴并进入 READY/NO_WAVES。 |
| `WaveManager.start_battle` | `() -> bool` | 在 READY 接受唯一一次手动开始，建立全部波次的全局出怪时间轴。 |
| `WaveManager.start_next_wave` | `() -> bool` | 兼容旧调用的包装；等价调用 `start_battle()`，ACTIVE 中不会再次开始。 |
| `WaveManager.get_battle_elapsed` | `() -> float` | 返回首次开始后的全局计时秒数；未开始时为 0。 |
| `WaveManager.get_state` / `get_state_name` | `() -> State` / `() -> String` | 返回状态枚举/可显示状态。 |
| `WaveManager.get_current_wave_number` / `get_total_wave_count` | `() -> int` | 返回最近已开始波号和总波数。 |
| `WaveManager.get_active_enemy_count` | `() -> int` | 返回全部波次的有效场上敌人数量。 |
| `WaveManager._clear_enemy_projectiles` | `() -> void` | 切关或失败时清理仍在飞行的 EnemyProjectile。 |
| `WaveStatusPanel.configure` | `(wave_manager: WaveManager, base_core: BaseCore) -> void` | 订阅状态和据点生命。 |

**信号**：`state_changed`、`wave_started`、`wave_completed`、`enemy_spawned`、`enemy_reached_base`、`victory`、`defeat`。

## 约定事实源

- WaveManager 是全局时间轴、当前状态和存活单位计数事实源；LevelResource 只保存静态配置。
- `start_delay` 是相对首次手动开始的绝对延迟，不是“上一波结束后的等待时间”。波次顺序不会自动改写该值。
- 第一波若要立即出现，第一波出怪组应配置 `start_delay = 0`；M4DemoLevel 遵循此约定。
- 不同波次可因时间配置而重叠。波次完成仅影响事件和显示，不暂停全局时间轴。
- 敌人掉落由 EnemyUnit.`died` 结算；抵达据点、调试靶标和清关不产生掉落。
- 全局胜利条件是所有组已生成完且全部 active units 为零。

## 已知限制 / 初版不做的部分

- 无无限模式、动态难度、波次内条件触发、快进、暂停或复杂 DSL。
- 不提供可视化时间轴预览；关卡设计者当前通过各组 `start_delay` 数值编排重叠节奏。
- 出怪组不做随机池或编队阵型。
