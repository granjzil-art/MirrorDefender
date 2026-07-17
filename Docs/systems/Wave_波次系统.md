# 波次系统 · Wave

> 实现状态：M4 已完成资源化波次/出怪组、并行延迟生成、准备期、胜负状态、运行时控制面板与关卡编辑器波次页。

## 职责

驱动经典塔防固定波次。每波由多个 SpawnGroup 并行计时生成；所有组生成完且场上敌人清空后进入准备期，最后一波完成即胜利，据点归零即失败。

## 分类 / 做法

- **WaveDefinition**：一波持有若干 SpawnGroupDefinition。
- **SpawnGroupDefinition**：直接引用敌人、出生点和路径；独立配置数量、出怪间隔和开始延迟，因此同一波可混编并行。
- **状态机**：`NO_WAVES -> READY -> ACTIVE -> PREPARING -> READY`，终态为 `VICTORY` 或 `DEFEAT`。
- **生成**：WaveManager 在 `ACTIVE` 中维护每组剩余数量、延迟与冷却；大 delta 可补发多个应生成单位。
- **胜负**：最后一波无存活单位后胜利；BaseCore.defeated 会取消待生成状态、清理单位并失败。
- **运行时入口**：右侧 `WaveStatusPanel` 显示据点、波次和敌人数，准备完成后“开始下一波”可用。
- **编辑**：关卡编辑器“波次”页可增删波次、出怪组，选择敌人/入口/路径并修改数量、间隔、延迟。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| LevelResource | `waves` | 固定波次数组，数量即总波数。 |
| LevelResource | `wave_prep_time` | 波次结束后的准备期秒数。 |
| LevelResource | `waves_auto_start` | 准备完成后是否自动开下一波。 |
| WaveDefinition | `display_name` | 编辑器/调试显示名。 |
| SpawnGroupDefinition | `enemy` | 直接引用 EnemyDefinition。 |
| SpawnGroupDefinition | `count` / `interval` / `start_delay` | 数量、生成间隔、组起始延迟。 |
| SpawnGroupDefinition | `spawn_point` / `path` | 直接引用本关入口与路线。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/wave/WaveDefinition.gd` | `WaveDefinition` / `Resource` | 一波的名称和出怪组数组。 |
| `scripts/wave/SpawnGroupDefinition.gd` | `SpawnGroupDefinition` / `Resource` | 一条敌人生成时间流。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | **波次唯一入口**；状态、计时、生成、奖励、胜负。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 运行时波次状态与开始按钮。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` | 两波可运行示例。 |

### 数据流

```text
LevelLoader.level_loaded -> Main
  -> PathManager.load_level / BaseCore.load_level / WaveManager.load_level

WaveStatusPanel.start -> WaveManager.start_next_wave
  -> SpawnGroup timers -> EnemyUnit + CombatManager.register_target
  -> Enemy died -> ResourceManager.grant_enemy_drop
  -> all groups spawned + no active enemies -> next prep or victory

EnemyUnit.reached_base -> BaseCore.take_damage
  -> BaseCore.defeated -> WaveManager.DEFEAT
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `WaveManager.configure` | `(path_manager: PathManager, combat_manager: CombatManager, resource_manager: ResourceManager, base_core: BaseCore) -> void` | 注入所有运行时公共入口。 |
| `WaveManager.load_level` | `(level_resource: LevelResource) -> void` | 清理旧单位、重置索引并进入 READY/NO_WAVES。 |
| `WaveManager.start_next_wave` | `() -> bool` | 在 READY 启动下一波，建立并行出怪状态。 |
| `WaveManager.get_state` / `get_state_name` | `() -> State` / `() -> String` | 返回状态枚举/可显示状态。 |
| `WaveManager.get_current_wave_number` / `get_total_wave_count` | `() -> int` | 返回当前波号和总波数。 |
| `WaveManager.get_active_enemy_count` | `() -> int` | 返回有效场上敌人数量。 |
| `WaveStatusPanel.configure` | `(wave_manager: WaveManager, base_core: BaseCore) -> void` | 订阅状态和据点生命。 |

**信号**：`state_changed`、`wave_started`、`wave_completed`、`enemy_spawned`、`enemy_reached_base`、`victory`、`defeat`。

## 约定事实源

- WaveManager 是当前波次、生成计时和存活单位计数事实源；LevelResource 只是静态配置。
- 敌人掉落由 EnemyUnit.`died` 结算；抵达据点、调试靶标和清关不产生掉落。
- 一波完成的必要条件是所有组已生成完且 active units 为零。

## 已知限制 / 初版不做的部分

- 无无限模式、动态难度、波次内条件触发、快进、暂停或复杂 DSL。
- 出怪组仅并行定时，不做串行编队、随机池或编队阵型。
