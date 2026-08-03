# 波次系统 · Wave

> 实现状态：现役流程为 2026-07-27 的**逐波手动释放**。旧“只手动首波、后续按全局时间自动开始”的纵向时间轴实现保留兼容脚本/历史记录，但不在正式 HUD 实例化。

## 职责

`WaveManager` 是局内波次释放、生成调度、活动敌人、奖励和胜负状态的唯一事实源。玩家每次操作只释放下一条作者波次；已释放波次可同时生成和存活。系统保留每波内部各出怪组的相对延迟与同组间隔，不自动释放任何尚未提交的波次。

## 分类 / 状态与时间语义

- **静态配置**：`LevelResource.waves` 按数组作者顺序保存 `WaveDefinition`；每波包含多个 `SpawnGroupDefinition`，组直接引用敌人、初始路径、数量、间隔与 `start_delay`。
- **释放游标**：`_released_wave_count` 是唯一运行时游标，也是“最近已释放波号”。`get_next_wave_number()` 返回游标后一波，全部释放后返回 `0`。每次 `start_next_wave()` 最多推进一次游标。
- **状态机**：`NO_WAVES -> READY -> ACTIVE -> VICTORY/DEFEAT`；关卡、依赖、路径或生成失败进入 `CONFIG_ERROR`。`READY` 可释放第一波；`ACTIVE` 仍可继续释放后续波，不等待旧波完成。
- **兼容入口**：`start_battle()` 只在 `READY` 且游标为 `0` 时转调 `start_next_wave()`；不再代表“启动全部波次时间轴”。
- **局内连续时间**：第一波释放时 `_battle_elapsed` 归零；之后每帧按缩放后的游戏 `delta` 累加，释放后续波不会重置。
- **每波时间原点**：释放第 `w` 波时，`release_time_w = _battle_elapsed`。设 `min_delay_w = min(group.start_delay)`，则每组首只敌人的调度时刻为：

```text
relative_delay(group) = max(0, group.start_delay - min_delay_w)
first_spawn_time(group) = release_time_w + relative_delay(group)
next_spawn_time += max(0.01, group.interval)
```

  因此本波最早组在点击后立即尝试生成；其它组只保留同一波内部的作者相对延迟。不同波的 `start_delay` 不共享绝对时间原点。
- **允许重叠**：新波释放不清理旧波 `_spawn_states` 或活动单位；多波可同时生成、移动和战斗。
- **释放与开始不同**：`wave_released` 表示该波释放事务成功并推进游标；`wave_started` 表示该波第一只敌人已成功加入 `CombatManager`。立即生成时 `wave_started` 可能在 `wave_released` 之前发出，调用方只能按语义区分，不能依赖二者先后顺序。
- **逐波完成**：一波至少成功生成过一只敌人、该波全部组生成完且该波活动敌人为空时发送一次 `wave_completed`；完成不自动释放下一波。
- **路径显示阶段事实**：`ACTIVE` 同时包含“仍在生成/有存活敌人”和“等待玩家释放下一波”的静默区间。`is_wave_action_active()` 用待生成组与活动单位区分二者；`should_show_continuous_paths()` 只在 `READY` 或仍有下一波的真实静默区间返回 true。活动路径请求按未完成的已释放波求并集，并保留地面/空中档案；表现层在行动期为每条唯一实时路线循环一条“出生点 → 目标据点”的短发光线段。行动结束不会截断已经生成的短线，短线离开终点后才切换为与悬停预览一致的波间青色流线，或在终局隐藏。
- **胜利条件**：仅当 `are_all_waves_released()`、全部已建生成状态的 `remaining == 0`、且 `_active_units` 为空时进入 `VICTORY`。未释放波仍存在时，即使场上清空也不得胜利。Debug spawn 复用 `_active_units`，因此同样阻塞最终胜利。
- **失败与配置错误**：共享 `BaseCore` 生命归零进入 `DEFEAT`；预检/生成失败进入 `CONFIG_ERROR`。二者都会停止生成并清理活动敌人和敌方投射物，不得误判胜利。
- **Debug spawn 边界**：`spawn_debug_enemy()` 不释放作者波次、不推进游标、不增加组生成计数；要求非空 EnemyDefinition、当前关卡路径，且当前状态不是 `VICTORY/DEFEAT/CONFIG_ERROR`。F1 `spawn` 业务绑定会额外把敌人限制为当前关卡波次已引用定义；WaveManager 公共入口本身不扫描或验证敌人资源归属。终态一律拒绝。
- **正式 UI**：右侧 `WaveControlPanel` 提供“释放下一波 / 快速重启 / 退出当前关卡”三个按钮。`WaveTimelineModel` 只复用为下一波悬停摘要；旧 `WaveTimelinePanel` 与 `WaveStatusPanel` 不在正式 `RuntimeHud.tscn` 实例化。

## 关键参数

| 归属 | 参数 | 说明 |
|---|---|---|
| WaveManager | `feature_enabled = true` | 波次功能总开关；关闭时不能释放波次或 Debug spawn。 |
| LevelResource | `waves: Array[WaveDefinition]` | 作者顺序即释放顺序，不排序、不压缩。 |
| WaveDefinition | `display_name: String` | 波次详情与调试显示名。 |
| SpawnGroupDefinition | `enemy: EnemyDefinition` | 该组生成的敌人定义。 |
| SpawnGroupDefinition | `path: PathDefinition` | 初始路径，同时确定出生点和锁定目标据点。 |
| SpawnGroupDefinition | `count: int` | 该组成功生成总数。 |
| SpawnGroupDefinition | `interval: float` | 同组相邻敌人的游戏时间间隔；运行时下限为 `0.01` 秒。 |
| SpawnGroupDefinition | `start_delay: float` | 只参与**本波内部**归一；不是距第一波开始的全局绝对延迟。 |
| SpawnGroupDefinition | `spawn_point` | 旧资源兼容引用；现役端点由路径解析且必须与路径首格一致。 |
| EnemyDefinition | `ui_icon: Texture2D` | 下一波详情的可选图标；为空使用 `WaveControlPanel.fallback_enemy_icon` 或文字灰盒。 |
| WaveControlPanel | `feature_enabled = true` | 右侧三按钮总开关。 |
| WaveControlPanel | `button_size = 68.0` | 三个圆形按钮边长，Inspector 范围 48～96。 |
| WaveControlPanel | `start_next_wave_icon/restart_level_icon/exit_level_icon` | 三按钮可选美术资源。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/wave/WaveDefinition.gd` | `WaveDefinition` / `Resource` | 一波的名称与作者顺序出怪组数组。 |
| `scripts/wave/SpawnGroupDefinition.gd` | `SpawnGroupDefinition` / `Resource` | 单组敌人、路径、数量、间隔和波内延迟配置。 |
| `scripts/wave/WaveManager.gd` | `WaveManager` / `Node` | **波次唯一运行时入口**；释放游标、波内调度、生成事务、活动单位、奖励和胜负。 |
| `scripts/ui/WaveTimelineModel.gd` | `WaveTimelineModel` / `RefCounted` | 把波次资源只读聚合为敌人、端点、路径和摘要 Dictionary；现役仅供下一波详情复用。 |
| `scripts/ui/WaveControlPanel.gd` | `WaveControlPanel` / `Control` | 右侧三按钮、下一波悬停详情及路径预览信号；不维护释放游标。 |
| `scenes/ui/WaveControlPanel.tscn` | 无 class_name / `Control` 场景 | 三个 68px 圆形按钮与向左展开的下一波详情板。 |
| `scripts/ui/RuntimeHud.gd` | `RuntimeHud` / `Control` | 注入 WaveManager，转发重启/退出和路径预览信号，模态时抑制预览。 |
| `scripts/ui/WaveTimelinePanel.gd` / `scenes/ui/WaveTimelinePanel.tscn` | `WaveTimelinePanel` / `Control` | 旧纵向时间轴兼容实现；不在正式 HUD 实例化。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 旧 M4 首波/摘要兼容脚本；不在正式 HUD 实例化。 |
| `scripts/debug/RuntimeDebugBindings.gd` | `RuntimeDebugBindings` / `Node` | 把 `wave start` 绑定到 `start_next_wave()`，并为 `spawn` 解析当前关卡敌人与路径。 |
| `resources/levels/M4DemoLevel.tres` | `LevelResource` / `Resource` | 默认正式上架关卡；作者波次数组保持原顺序。 |
| `tests/manual_wave_release_test.gd` | 无 class_name / `SceneTree` | 逐波释放、重叠、波内归一、游标、信号、胜利、配置失败和终态 Debug spawn 回归。 |
| `tests/manual_wave_and_level_flow_test.gd` | 无 class_name / `SceneTree` | 正式三按钮、连续 `wave start`、退出返回选关和直接 Main 兼容回归。 |
| `tests/runtime_ui_batch4_test.gd` | 无 class_name / `SceneTree` | 历史时间轴模型与路径摘要兼容回归；不证明旧 Panel 仍为现役 HUD。 |

### 模块调用关系 / 数据流

```text
LevelLoader.level_loaded(level)
  -> Main._on_level_loaded
     -> PathManager.load_level(level)
     -> BaseCore.load_level(level)
     -> WaveManager.load_level(level)
     -> RuntimeHud.apply_level_configuration(level)
        -> WaveControlPanel.set_level(level)

右侧“释放下一波” / F1 `wave start`
  -> WaveControlPanel._on_start_pressed / RuntimeDebugBindings._command_wave
  -> WaveManager.start_next_wave()
     -> validate whole current LevelResource and injected dependencies
     -> wave_index = released_wave_count
     -> for each group: next_spawn_time = battle_elapsed + normalized relative_delay
     -> process due groups without removing older wave states
     -> successful CombatManager.register_target(unit)
        -> enemy_spawned(unit)
        -> first success of wave -> wave_started(wave_number, wave)
     -> successful release -> released_wave_count += 1
        -> wave_released(wave_number, wave)
        -> next_wave_changed(next_number or 0, next_wave or null)

WaveControlPanel hover start button
  -> WaveManager.get_next_wave_number()
  -> WaveTimelineModel.build(level) entry at release cursor
  -> paths_preview_requested(paths: Array)
  -> RuntimeHud.wave_paths_preview_requested(paths: Array)
  -> Main._on_wave_paths_preview_requested(paths: Array)
  -> PathHoverPreview.preview_paths(paths)
Pause / console / button exit / level transition
  -> WaveControlPanel.clear_hover_preview()
  -> RuntimeHud.wave_paths_preview_cleared
  -> Main -> PathHoverPreview.clear_preview()

EnemyUnit.died -> ResourceManager.grant_enemy_drop(reward)
EnemyUnit.reached_base -> BaseCore.take_damage(damage)
BaseCore.defeated -> WaveManager -> DEFEAT

all waves released
+ every spawn state remaining == 0
+ active units (authored and Debug) empty
  -> VICTORY
```

## 函数索引

| 函数 | 签名 | 职责 |
|---|---|---|
| `WaveManager.configure` | `(path_manager: PathManager, combat_manager: CombatManager, resource_manager: ResourceManager, base_core: BaseCore, path_blocker_resolver: Callable = Callable(), route_resolver: Callable = Callable(), cell_world_resolver: Callable = Callable(), tile_enter_resolver: Callable = Callable(), tile_stay_resolver: Callable = Callable(), navigation_blocker_resolver: Callable = Callable()) -> void` | 注入路径、战斗、经济、据点及敌人运行所需解析器。 |
| `WaveManager.load_level` | `(level_resource: LevelResource) -> void` | 清理旧单位/投射物，重置释放游标、连续时间和生成状态，只读校验后进入 `READY/NO_WAVES/CONFIG_ERROR`。 |
| `WaveManager.start_battle` | `() -> bool` | 兼容第一波入口；仅 `READY` 且尚未释放时转调 `start_next_wave()`。 |
| `WaveManager.start_next_wave` | `() -> bool` | 预检并只释放游标指向的一波；允许 `READY/ACTIVE`，成功后游标前进一位。 |
| `WaveManager.get_state` | `() -> State` | 返回当前状态枚举。 |
| `WaveManager.get_state_name` | `() -> String` | 返回含释放/下一波/连续时间信息的可显示状态。 |
| `WaveManager.get_current_wave_number` | `() -> int` | 返回最近已释放波号；首波前为 0，不代表最近 `wave_started` 波号。 |
| `WaveManager.get_total_wave_count` | `() -> int` | 返回作者波次数。 |
| `WaveManager.get_released_wave_count` | `() -> int` | 返回释放游标计数。 |
| `WaveManager.get_next_wave_number` | `() -> int` | 返回下一可释放的 1 基波号；全部释放后为 0。 |
| `WaveManager.get_next_wave` | `() -> WaveDefinition` | 返回释放游标指向的定义；无下一波时为 null。 |
| `WaveManager.can_start_next_wave` | `() -> bool` | 检查功能开关、关卡、`READY/ACTIVE` 状态和剩余作者波次。 |
| `WaveManager.are_all_waves_released` | `() -> bool` | 判断非空作者波次数组是否已全部推进游标。 |
| `WaveManager.is_wave_action_active` | `() -> bool` | `ACTIVE` 中仍有待生成组或活动单位时返回 true。 |
| `WaveManager.should_show_continuous_paths` | `() -> bool` | 首波前或仍有下一波的真实清场间隙返回 true。 |
| `WaveManager.get_active_path_requests` | `() -> Array[Dictionary]` | 返回未完成已释放波的唯一 `{path, airborne}` 路线请求。 |
| `WaveManager.get_all_path_requests` | `() -> Array[Dictionary]` | 返回关卡全部波次使用的唯一导航档案路线请求。 |
| `WaveManager.get_active_enemy_count` | `() -> int` | 清理失效句柄后返回作者生成与 Debug spawn 的全部活动敌人数。 |
| `WaveManager.get_battle_elapsed` | `() -> float` | 返回第一波释放后累计的缩放游戏时间；后续释放不归零。 |
| `WaveManager.get_configuration_error` | `() -> String` | 返回最近配置错误文本。 |
| `WaveManager.spawn_debug_enemy` | `(enemy: EnemyDefinition, path: PathDefinition) -> Dictionary` | 返回 `{success: bool, message: String}`；复用真实注册事务，不改变作者释放/组计数，终态拒绝。 |
| `WaveControlPanel.configure` | `(wave_manager: WaveManager) -> void` | 安全重连 `next_wave_changed/wave_released/state_changed` 并刷新按钮。 |
| `WaveControlPanel.set_level` | `(level: LevelResource) -> void` | 只读构建下一波详情条目并清理旧关预览。 |
| `WaveControlPanel.set_preview_suppressed` | `(suppressed: bool) -> void` | 暂停/控制台模态时清理并禁止路径预览。 |
| `WaveControlPanel.clear_hover_preview` | `() -> void` | 隐藏详情并发送路径清理信号。 |
| `WaveControlPanel.get_previewed_wave_number` | `() -> int` | 返回当前悬停预览的下一波号；未预览为 0。 |
| `WaveTimelineModel.build` | `(level: LevelResource) -> Array[Dictionary]` | 返回作者顺序条目；除唯一 `paths` 外增加 `{path, airborne}` 的 `path_requests`，仅作只读摘要与真实路线预览。 |

## 信号索引

| 信号 | 签名 | 语义 |
|---|---|---|
| `state_changed` | `(state: WaveManager.State, current_wave: int, total_waves: int, active_enemy_count: int)` | 状态、最近释放波号、总波数和全部活动敌人数快照。 |
| `wave_released` | `(wave_number: int, wave: WaveDefinition)` | 一次手动释放成功并提交该波。 |
| `next_wave_changed` | `(wave_number: int, wave: WaveDefinition)` | 加载关卡或释放后更新下一波；全部释放时为 `(0, null)`。 |
| `wave_started` | `(wave_number: int, wave: WaveDefinition)` | 本波第一只敌人成功注册；不等同于按钮释放。 |
| `wave_completed` | `(wave_number: int)` | 本波组已生成完且该波活动敌人为空。 |
| `enemy_spawned` | `(unit: EnemyUnit)` | 一个作者或 Debug 敌人已完成配置和 Combat 注册。 |
| `enemy_reached_base` | `(unit: EnemyUnit, damage: float)` | 单位抵达据点并请求结算伤害。 |
| `configuration_failed` | `(reason: String)` | 波次预检或生成事务失败并进入 `CONFIG_ERROR`。 |
| `victory` / `defeat` | `()` / `()` | 进入不可逆玩法终态。 |
| `WaveControlPanel.restart_level_requested` | `()` | 请求组合根完整重载当前关卡。 |
| `WaveControlPanel.exit_level_requested` | `()` | 请求退出当前关卡并返回选关页，不退出程序。 |
| `WaveControlPanel.paths_preview_requested` | `(paths: Array)` | 请求预览下一波全部唯一路径。 |
| `WaveControlPanel.paths_preview_cleared` | `()` | 请求清理世界路径预览。 |

## 约定事实源

- 页面或 UI 不维护波次进度；`_released_wave_count`、`_spawn_states`、`_active_units` 和 `_state` 只由 `WaveManager` 写入。
- `LevelResource.waves` 的数组顺序就是释放顺序；UI、Debug 命令不得排序或跳过。
- `start_delay` 的现役语义是**波内相对布局输入**；每次释放用本波最小值归一。旧“距第一次点击的全局绝对秒数”只属于历史批次记录。
- `_battle_elapsed` 是第一波释放后连续的局内模拟时间；每波调度原点是其释放时刻，二者同时存在且不可混淆。
- `wave_released`、`wave_started`、`wave_completed` 分别代表提交、首次成功生成、该波清场；任何 UI 不得用一个信号替代另一个。
- 活动敌人数组包含作者生成与 Debug spawn；胜利只看全部波已释放、全部组已生成和该数组为空。
- 生成计数只在单位成功注册后递减；失败进入 `CONFIG_ERROR`，不推进释放游标、不伪造开始/完成/胜利。
- 敌人目标据点由初始路径锁定；大石头换路只能在同目标据点路网内进行。
- 正式 HUD 只实例化 `WaveControlPanel`；旧 Timeline/Status 文件保留兼容，不代表现役布局。

## 已知限制 / 初版不做的部分

- 无无限模式、动态难度、条件释放、自动释放策略、波次队列快捷操作或复杂 DSL。
- 同一波详情聚合所有组，不拆分组级可点击控件；组间延迟与间隔仍只在资源中配置。
- F1 `spawn` 只匹配当前关卡波次已引用敌人且不扫描磁盘；`WaveManager.spawn_debug_enemy()` 仅校验敌人非空和路径属于当前关卡。
- 本轮新增测试已登记，但本次文档同步按要求未运行测试。
