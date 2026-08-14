# 调试控制台 · Debug Console

## 职责

集中承载运行时调试信息、可视化开关和安全命令入口。正式 HUD 实例化一个按钮打开的控制台和一个左上角只读信息层；业务命令注册、命令解析和 UI 展示相互解耦。

## 分类 / 做法

- `F1` 是调试工具总开关，统一控制左侧控制台/关卡编辑/参数编辑按钮组、调试摘要、卡槽表现切换及灯光/树影/实树测试栏的显隐和可用性。正式游戏镜头键 `1/2` 不属于调试功能，不受 F1 影响。控制台改由“调试控制台”按钮打开；打开时仍作为最高 HUD 模态层，`Esc`、右键或关闭按钮关闭。
- F1 关闭期间，已勾选分类进入挂起态：路径、换路等世界调试表现立即关闭，但勾选状态保留；再次开启后恢复。脏的关卡/参数工作副本只隐藏或挂起，不静默丢弃。
- 固定分类为 `grid`、`pick`、`path`、`reroute`、`mirror`、`combat`、`fps`、`wave`。全部默认关闭，勾选框和 `debug set` 命令写入同一个 `DebugCategoryRegistry`。
- `path` 开关只控制手工路径调试线；出生点/据点数字是正式关卡信息，不随调试线关闭。`reroute` 控制最近换路调试线。
- 控制台右侧实时区与游戏画面左上角 `DebugOverlayPanel` 共同读取已启用分类；关闭控制台不关闭已启用信息，全部分类关闭时常驻层自动收起。
- 左上常驻层不拦截鼠标；其刷新使用真实时间，不受暂停、慢放或 2x 影响。旧“波次时间轴上方预留区”已随正式左侧时间轴移除而失效。
- 命令 UI 不包含业务 `match`。`RuntimeDebugBindings` 从正式 Manager 公共 API 注册业务回调；其它模块可继续调用 `register_command` 扩展。
- 命令解析支持单引号、双引号和反斜杠转义；空命令、未知命令、未闭合引号、参数错误和缺少依赖均返回结构化失败，不触发运行时报错。
- 旧 `Main/HUD/Panel`、`Hint` 和 `M3DebugPanel` 在正式主场景中隐藏且不再配置；右上角 `LevelDebugPanel` 按既有操作保留，继续提供当前关卡状态与“加载关卡”快捷入口，但不作为调试命令事实源。

## 首批命令

| 命令 | 行为 |
|---|---|
| `help [command]` | 列出全部注册命令或显示单个命令的用法与说明。 |
| `clear` | 清空控制台历史。 |
| `reload` | 通过 `LevelLoader.reload_current_level()` 深重载当前关卡。 |
| `load <res://path.tres>` | 通过正式 `LevelLoader` 加载并校验关卡。 |
| `resource add <n>` | 通过 `ResourceManager.gain()` 增加正数资源。 |
| `resource set <n>` | 通过 `ResourceManager.set_main_resource()` 设置有限非负资源。 |
| `wave start` | 每次请求 `WaveManager.start_next_wave()`，按释放游标只释放下一波；READY/ACTIVE 且仍有未释放波时成功。 |
| `spawn <enemy_id> [path_id]` | 从当前关卡已引用敌人中匹配 ID，并复用 `WaveManager.spawn_debug_enemy()` 生成事务；省略路径时使用首条路径。不会推进作者波次游标；在 `VICTORY/DEFEAT/CONFIG_ERROR` 终态拒绝。 |
| `debug list` | 列出全部分类当前 `on/off`。 |
| `debug set <category> <on\|off>` | 切换分类，与 UI 勾选框实时同步。 |

## 关键参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| Main.`debug_console_enabled` | true | 正式主场景控制台与左上常驻调试层总开关。 |
| DebugConsole.`feature_enabled` | true | 控制台组件开关。 |
| DebugConsole.`live_refresh_interval` | 0.2 秒 | 实时分类摘要刷新间隔，使用系统毫秒而非缩放后的游戏时间。 |
| DebugConsole.`max_history_lines` | 200 | 命令历史最大行数。 |
| DebugConsole.`panel_texture` / `execute_icon` | null | 控制台背景和执行按钮美术替换接口；空值使用镜面玻璃灰盒。 |
| DebugOverlayPanel.`feature_enabled` | true | 游戏画面左上角常驻调试信息总开关。 |
| DebugOverlayPanel.`refresh_interval` | 0.2 秒 | 常驻信息刷新间隔，使用系统毫秒。 |
| DebugOverlayPanel.`panel_texture` | null | 常驻信息背景美术接口；空值使用镜面玻璃灰盒。 |
| PathManager.`show_paths` | 由 `path` 分类控制 | 仅手工路径调试线，不影响数字端点。 |
| PathRoutePlanner.`show_selected_detour` | 由 `reroute` 分类控制 | 最近成功换路路线调试线。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/debug/DebugCommandRegistry.gd` | `DebugCommandRegistry` / `RefCounted` | 命令元数据、分词、分发和结构化结果；内置 `help/clear`。 |
| `scripts/debug/DebugCategoryRegistry.gd` | `DebugCategoryRegistry` / `RefCounted` | 八类开关、只读提供器与可选可视化切换回调。 |
| `scripts/debug/RuntimeDebugBindings.gd` | `RuntimeDebugBindings` / `Node` | 将 Level/Resource/Wave/Path/Grid/Combat/Mirror 公共 API 注册为命令和分类提供器。 |
| `scripts/ui/DebugConsole.gd` | `DebugConsole` / `Control` | 按钮打开的模态、分类勾选、实时区、历史和输入框；不实现业务命令。 |
| `scenes/ui/DebugConsole.tscn` | `Control` 场景 | 响应式镜面控制台层和可替换美术接口。 |
| `scripts/ui/DebugOverlayPanel.gd` | `DebugOverlayPanel` / `Control` | 独立于控制台开关状态，持续渲染已启用分类的左上角只读摘要。 |
| `scenes/ui/DebugOverlayPanel.tscn` | 无 class_name / `Control` 场景 | 左上角固定调试信息区域和可替换背景接口；不依赖旧波次时间轴。 |
| `scripts/ui/RuntimeHud.gd` | `RuntimeHud` / `Control` | 将暂停与控制台合并为一个模态事实边界。 |
| `scripts/Main.gd` | `Node3D` | 只装配 RuntimeDebugBindings、注入拾取提供器并响应统一模态信号。 |
| `tests/runtime_ui_batch6_test.gd` | 无 / `SceneTree` | 命令解析、八类开关、业务绑定、三档布局、模态和旧面板迁移回归。 |

### 数据流

```text
F1
  -> Main 调试总开关
  -> RuntimeHud / LightingTestPanel / DebugCategoryRegistry.suspended

console button / close / Esc
  -> DebugConsole.open_changed
  -> RuntimeHud._sync_modal_state
  -> Main._on_runtime_modal_state_changed
  -> camera input lock + preview/highlight clear

DebugConsole command text
  -> DebugCommandRegistry.execute
  -> registered Callable in RuntimeDebugBindings
  -> LevelLoader / ResourceManager / WaveManager public API
  -> {success: bool, message: String, clear: bool}
  -> DebugConsole history

CheckBox or debug set
  -> DebugCategoryRegistry.set_enabled
  -> shared category_changed signal
  -> checkbox synchronization
  -> optional PathManager/PathRoutePlanner visual toggle
  -> enabled provider snapshot
     -> DebugConsole live output
     -> DebugOverlayPanel persistent top-left output
```

## 函数索引

| 文件 | 函数签名 | 职责 |
|---|---|---|
| `DebugCommandRegistry.gd` | `register_command(command_name: StringName, usage: String, description: String, handler: Callable) -> bool` | 注册或替换一个根命令。 |
| `DebugCommandRegistry.gd` | `execute(input: String) -> Dictionary` | 返回 `{success: bool, message: String, clear: bool}`；所有语法/命令错误同样结构化。 |
| `DebugCommandRegistry.gd` | `list_commands() -> Array[Dictionary]` | 返回按注册顺序的 `name/usage/description/handler` 元数据副本。 |
| `DebugCategoryRegistry.gd` | `register_category(category_id: StringName, display_name: String, enabled: bool = false, provider: Callable = Callable(), toggle_handler: Callable = Callable()) -> bool` | 注册分类、实时提供器和可选表现开关。 |
| `DebugCategoryRegistry.gd` | `set_enabled(category_id: StringName, enabled: bool) -> bool` | 修改共享分类状态并调用可视化切换器。 |
| `DebugCategoryRegistry.gd` | `list_categories() -> Array[Dictionary]` | 返回 `id/display_name/enabled/provider/toggle_handler` 元数据副本。 |
| `DebugCategoryRegistry.gd` | `get_enabled_snapshot() -> Array[Dictionary]` | 返回已启用分类的 `{id, display_name, text}` 实时快照。 |
| `RuntimeDebugBindings.gd` | `configure(level_loader: LevelLoader, resource_manager: ResourceManager, wave_manager: WaveManager, path_manager: PathManager, path_route_planner: PathRoutePlanner, grid_manager: GridManager, combat_manager: CombatManager, mirror_manager: MirrorManager) -> void` | 重建命令/分类注册表并注入正式业务入口。 |
| `RuntimeDebugBindings.gd` | `set_pick_provider(provider: Callable) -> void` | 注入 Main 当前鼠标拾取摘要，不反向持有 Main。 |
| `RuntimeDebugBindings.gd` | `_command_wave(arguments: Array[String]) -> Dictionary` | 仅接受 `start`，读取下一波号并调用 `WaveManager.start_next_wave()`；返回 `{success, message}`。 |
| `RuntimeDebugBindings.gd` | `_command_spawn(arguments: Array[String]) -> Dictionary` | 解析当前关卡已引用敌人与路径并调用 Debug 生成入口；终态失败保持结构化结果。 |
| `DebugConsole.gd` | `configure(command_registry: DebugCommandRegistry, category_registry: DebugCategoryRegistry) -> void` | 绑定注册表并安全断开旧分类信号。 |
| `DebugConsole.gd` | `open_console()` / `close_console()` / `toggle_console()` / `is_open() -> bool` | 管理 F1 模态可见性。 |
| `DebugConsole.gd` | `submit_command(input: String) -> Dictionary` | 委托注册表执行并更新有限历史。 |
| `DebugOverlayPanel.gd` | `configure(category_registry: DebugCategoryRegistry) -> void` | 订阅共享分类开关并安全断开旧注册表。 |
| `DebugOverlayPanel.gd` | `refresh_now() -> void` | 查询已启用分类、刷新左上摘要并在空集合时自动隐藏。 |
| `DebugOverlayPanel.gd` | `get_display_text() -> String` | 返回当前显示文本，供只读检查和回归测试。 |
| `RuntimeHud.gd` | `configure_debug_console(command_registry: DebugCommandRegistry, category_registry: DebugCategoryRegistry) -> void` | 将同一分类事实源同时注入控制台和左上常驻层。 |
| `RuntimeHud.gd` | `is_modal_open() -> bool` / `close_top_modal() -> void` | 统一暂停和控制台输入边界，优先关闭控制台。 |

新增命令：`stuff edit on` 开启运行时关卡元素编辑，`stuff edit off` 在会话无未保存修改时关闭；有脏修改时必须先在工作区保存或放弃。
| `ResourceManager.gd` | `set_main_resource(value: float, reason: String = "set") -> bool` | 设置有限非负资源并广播真实差值。 |
| `WaveManager.gd` | `spawn_debug_enemy(enemy: EnemyDefinition, path: PathDefinition) -> Dictionary` | 不修改波次时间轴，复用单位配置、Combat 注册和清理生命周期。 |
| `PathManager.gd` | `set_debug_paths_visible(enabled: bool) -> void` | 重建手工路径调试线；端点数字始终保留。 |
| `PathRoutePlanner.gd` | `set_debug_route_visible(enabled: bool) -> void` | 开关换路线；关闭时立即清理旧 Mesh。 |

## 已知限制

- 控制台只查找当前关卡波次已引用的敌人，不提供任意磁盘资源扫描。
- `wave start` 每次只释放下一波，不能跳波或自动释放全部剩余波次。
- `spawn` 不推进释放游标，但生成的活动敌人会参与最终清场判定；`VICTORY`、`DEFEAT`、`CONFIG_ERROR` 下禁止生成。
- 分类状态只在本次运行中保存；不写入玩家设置或关卡资源。
- 控制台打开不会自动暂停模拟时间，只锁定世界与相机输入；玩家可先暂停再打开控制台。
- 保留旧调试面板脚本用于历史兼容；正式主场景仅配置并展示 `LevelDebugPanel` 作为快捷选关入口，其他旧调试面板不再配置或展示。
