# 波次系统 · Wave

> 实现状态：M4 已完成资源化波次/出怪组、全局延迟时间轴、胜负状态与关卡编辑器波次页；M6 批次 4 已完成正式纵向时间轴和悬停路径预览入口。

## 职责

驱动经典塔防固定波次。玩家只需手动开始第一波；从这次点击起，所有 SpawnGroup 按各自 `start_delay` 在同一条全局时间轴上自动开始。所有组生成完且场上敌人清空后胜利，据点归零则失败。

## 分类 / 做法

- **WaveDefinition**：持有若干 SpawnGroupDefinition，负责编辑组织、显示名称和逐波完成事件；它不阻塞后续波次计时。
- **SpawnGroupDefinition**：直接引用敌人和初始路径；独立配置数量、出怪间隔和距第一波开始的延迟。出生点与目标据点分别由路径的 `spawn_point` / `target_base` 派生；保留 `group.spawn_point` 仅为旧关卡兼容。
- **状态机**：`NO_WAVES -> READY -> ACTIVE`，正常终态为 `VICTORY` 或 `DEFEAT`；依赖、路径或生成失败进入 `CONFIG_ERROR`。只有 READY 到 ACTIVE 需要玩家操作一次。
- **全局时间轴**：WaveManager 在首次点击时为全部波次建立生成状态；每组首只敌人的时间为 `start_delay`，后续敌人按 `interval` 生成。
- **波次重叠**：不同波次可以同时出怪。某波第一次实际生成时发送 `wave_started`；该波组全部生成且该波存活敌人为零时发送 `wave_completed`。
- **胜负**：全部波次的全部组生成结束且场上敌人清空后胜利；多个据点位置由同一 BaseCore 共享生命，共享生命归零后失败。
- **生成事务**：只有 EnemyUnit 成功加入 CombatManager 后，才发送 `wave_started` 并扣减该组剩余数量。失败会清空待生成状态和临时单位、广播配置错误，绝不把失败敌人计为已生成或触发假胜利。
- **屏障联调**：Main 将 BuildingManager 的阻挡查询 Callable 注入 WaveManager；每个新 EnemyUnit 同时获得路径世界点、路径格、关卡格距和该查询接口。切关/失败会连同敌方投射物清理。
- **正式运行时入口**：左侧 `WaveTimelinePanel` 在 READY 显示“开始第一波”；进入 ACTIVE 后按钮隐藏，不再要求点击后续波次。旧 `WaveStatusPanel` 保留兼容但主场景不再实例化。
- **只读时间轴投影**：`WaveTimelineModel` 以一波全部组中最小 `start_delay` 作为波次块计划时间，聚合敌人总数并去重路径；不排序、不改写关卡资源。块底到达当前时间线代表计划时间到达。
- **悬停信息**：只使用自定义大详情窗，禁用原生 Tooltip 以避免双窗重叠。每组简化为“组N：敌人 ×数量 | 出生点N → 据点N”，不显示路径名、延迟或间隔；世界路径流光仍覆盖该波所有唯一路径。
- **编辑**：关卡编辑器“路径”页先独立维护出生点与据点，每条路径选择首尾端点；“波次”页只选敌人和路径，出生点读只随路径派生。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| LevelResource | `waves` | 固定波次数组，波次用于组织和显示，不建立串行等待关系。 |
| WaveDefinition | `display_name` | 编辑器/调试显示名。 |
| SpawnGroupDefinition | `enemy` | 直接引用 EnemyDefinition。 |
| SpawnGroupDefinition | `count` / `interval` | 生成数量与同组相邻敌人的生成间隔。 |
| SpawnGroupDefinition | `start_delay` | 从玩家首次点击“开始第一波”到本组首只敌人生成的全局延迟秒数。 |
| SpawnGroupDefinition | `path` | 本关初始路径；同时决定出生点和敌人锁定的目标据点。 |
| SpawnGroupDefinition | `spawn_point` | 旧关卡兼容引用；新编辑流程不允许与路径起点不一致。 |
| EnemyDefinition | `ui_icon` | 波次块/构成列表的可选敌人图标；为空使用 UI 灰盒。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/wave/WaveDefinition.gd` | `WaveDefinition` / `Resource` | 一波的名称和出怪组数组。 |
| `scripts/wave/SpawnGroupDefinition.gd` | `SpawnGroupDefinition` / `Resource` | 一条敌人生成时间流。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | **波次唯一入口**；全局计时、生成、逐波事件、奖励和胜负。 |
| `scripts/ui/WaveTimelineModel.gd` | `WaveTimelineModel` / `RefCounted` | 波次资源到 UI 字典的纯只读投影。 |
| `scripts/ui/WaveTimelinePanel.gd` / `scenes/ui/WaveTimelinePanel.tscn` | `WaveTimelinePanel` / `Control` | 正式纵向时间轴、首次开始按钮和悬停详情。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 旧 M4 兼容状态面板；主场景不再实例化。 |
| `tests/runtime_ui_batch4_test.gd` | 无 / `SceneTree` | 时间投影、首波操作、悬停信息、路径请求和响应式布局回归。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` | 两波全局时间轴示例；第二波在 8/9/10 秒生成步兵、疾行者和弓箭手组。 |

### 数据流

```text
LevelLoader.level_loaded -> Main
  -> PathManager.load_level / BaseCore.load_level / WaveManager.load_level

WaveTimelinePanel.start first wave -> WaveManager.start_battle
  -> build every wave/group timeline from t=0
  -> SpawnGroup.start_delay + interval -> EnemyUnit(path points + cells + blocker Callable)
  -> CombatManager.register_target
       └─ failure -> CONFIG_ERROR (no decrement, no victory)
  -> Enemy died -> ResourceManager.grant_enemy_drop
  -> each wave groups exhausted + its active enemies empty -> wave_completed
  -> all groups exhausted + all active enemies empty -> VICTORY

EnemyUnit.reached_base -> BaseCore.take_damage
  -> BaseCore.defeated -> WaveManager.DEFEAT

LevelResource.waves -> WaveTimelineModel.build (read-only)
  -> earliest group delay + enemy totals + numbered spawn/base endpoints
  -> WaveTimelinePanel block position / hover details
  -> hover path signal -> RuntimeHud -> Main -> PathHoverPreview
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `WaveManager.configure` | `(path_manager: PathManager, combat_manager: CombatManager, resource_manager: ResourceManager, base_core: BaseCore, path_blocker_resolver: Callable = Callable()) -> void` | 注入运行时公共入口和可选路径屏障查询。 |
| `WaveManager.load_level` | `(level_resource: LevelResource) -> void` | 清理旧单位、校验关卡、重置全局时间轴并进入 READY/NO_WAVES/CONFIG_ERROR。 |
| `WaveManager.start_battle` | `() -> bool` | 在 READY 预检依赖并接受唯一一次手动开始；立即失败时返回 false 并进入 CONFIG_ERROR。 |
| `WaveManager.start_next_wave` | `() -> bool` | 兼容旧调用的包装；等价调用 `start_battle()`，ACTIVE 中不会再次开始。 |
| `WaveManager.get_battle_elapsed` | `() -> float` | 返回首次开始后的全局计时秒数；未开始时为 0。 |
| `WaveManager.get_state` / `get_state_name` | `() -> State` / `() -> String` | 返回状态枚举/可显示状态。 |
| `WaveManager.get_configuration_error` | `() -> String` | 返回最近一次配置失败原因；非错误状态为空。 |
| `WaveManager.get_current_wave_number` / `get_total_wave_count` | `() -> int` | 返回最近已开始波号和总波数。 |
| `WaveManager.get_active_enemy_count` | `() -> int` | 返回全部波次的有效场上敌人数量。 |
| `WaveManager._clear_enemy_projectiles` | `() -> void` | 切关或失败时清理仍在飞行的 EnemyProjectile。 |
| `WaveTimelineModel.build` | `(level: LevelResource) -> Array[Dictionary]` | 返回 `wave_index/wave_number/display_name/scheduled_time/groups/enemy_totals/paths/primary_icon/summary` 只读条目。 |
| `WaveTimelinePanel.configure` | `(wave_manager: WaveManager) -> void` | 订阅公开波次信号并刷新状态/颜色。 |
| `WaveTimelinePanel.set_level` | `(level: LevelResource) -> void` | 为新关卡重建时间轴并清理旧悬停状态。 |
| `WaveTimelinePanel.set_preview_suppressed` | `(suppressed: bool) -> void` | 暂停等模态开启时关闭详情与世界路径预览。 |
| `WaveStatusPanel.configure` | `(wave_manager: WaveManager, base_core: BaseCore) -> void` | 旧兼容面板订阅状态和据点生命。 |

**信号**：`state_changed`、`wave_started`、`wave_completed`、`enemy_spawned`、`enemy_reached_base`、`configuration_failed`、`victory`、`defeat`。

## 约定事实源

- WaveManager 是全局时间轴、当前状态和存活单位计数事实源；LevelResource 只保存静态配置。
- `start_delay` 是相对首次手动开始的绝对延迟，不是“上一波结束后的等待时间”。波次顺序不会自动改写该值。
- 第一波若要立即出现，第一波出怪组应配置 `start_delay = 0`；M4DemoLevel 遵循此约定。
- 不同波次可因时间配置而重叠。波次完成仅影响事件和显示，不暂停全局时间轴。
- 敌人掉落由 EnemyUnit.`died` 结算；抵达据点、调试靶标和清关不产生掉落。
- 全局胜利条件是所有组已生成完且全部 active units 为零。
- 出怪计数只在单位成功注册后递减；`CONFIG_ERROR` 是配置/依赖故障，不等同于胜利或失败玩法结算。
- 正式波次块的计划时间固定取该波最早组延迟；组内其余时间只作为策划配置，正式悬停不显示。时间轴不拥有或修正波次数据。
- 敌人的目标据点在生成时由初始路径确定；大石头换路只能使用到该据点的路网，不得改去另一据点。

## 已知限制 / 初版不做的部分

- 无无限模式、动态难度、波次内条件触发或复杂 DSL。
- 当前同一波只显示一个时间轴块；同波各组不同的精确开始点不拆成独立小块。
- 出怪组不做随机池或编队阵型。
