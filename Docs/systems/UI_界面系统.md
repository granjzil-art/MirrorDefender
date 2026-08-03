# 界面系统 · UI

## 职责
提供程序启动选关、局内 HUD 与操作入口，承载六槽分页、卡槽、资源、检视、逐波释放、全局状态、时间控制和退关生命周期。M6 的整体布局、批次边界与验收事实源为 `Docs/07_M6_操作与UI大版本_需求与开发计划.md`。

## 分类 / 做法
- **M6 批次 1 正式 HUD（已实现）**：底部为独立复制镜卡加单行建筑卡；建筑卡数由关卡配置，默认 6。默认携带箭塔、激光塔、屏障，未使用位置显示空镜面；边障保留玩法但不进入默认卡组。整排不绘制也不拦截外层大卡槽，仅单张复制镜卡、建筑卡与空卡自身保留镜框，卡片之间的空白区域不属于 UI。
- **卡片状态**：卡片显示名称、可替换图标和 1 级建造费用；资源不足或达到对应上限时置灰且不可新选，选中卡使用金色镜框。`BuildingDefinition.card_icon` 与 `CopyMirrorDefinition.card_icon` 为空时使用稳定文字灰盒。
- **单次放置**：`RuntimeInteractionController` 是正式交互事实源。每次选卡只允许一次世界点击；成功、资源不足、上限、非法地块、非法边或未命中都会取消卡片/预览/实体选择并回 `SELECT`，成功放置的实体不会保持自动选中。
- **取消和输入消费**：左键执行肯定操作；右键短点击在释放时全局取消并回选择模式，右键拖动超过阈值后改为运行时相机旋转且不取消。中/右键仅从世界区域起手可导航相机；正式卡片和按钮消费左键，点击 UI 不会穿透到世界。
- **正式时间控制（批次 3 已实现）**：右下独立慢放、2x 和暂停/继续按钮，`GameTimeController` 固定按 `暂停 0x > 战术慢放 0.1x > 快速 2x > 正常 1x` 求解。暂停前的 2x 请求会保留，继续后恢复。选卡或选中实体建筑/镜子时仍默认触发 0.1x。
- **M6 批次 2 地块详情（已实现）**：选择模式点击含实体块建筑、任一相邻边建筑/复制镜、同格虚像或关卡元素的格时，右侧展开镜面详情板；空格、取消、选卡或放置完成时收起。条目可滚动，显示类型、实体/虚像、图标灰盒、等级、耐久、朝向、根源格、产生镜子及元素运行时状态。
- **两级显示配置（已实现）**：`InspectionDisplayConfig.visible` 是对象级开关；关闭后实体和由它产生的虚像都不进入列表。其余 `show_*` 是字段级开关，分别控制图标、类型、实体/虚像、功能、位置、高度、权限、等级、耐久、朝向、战斗、经济、容量、时序、对空及虚像谱系行。全部默认 `true`，保持已有显示。
- **名称与功能说明**：建筑、复制镜和地块定义各自持有 `inspection_display`；可编辑 `display_name` 和 `function_description`。空值向后兼容原显示名和内置说明，面板统一增加“功能：”行；虚像使用根源对象配置。
- **复制建筑参数一致性**：实体建筑与建筑虚像共用同一详情行生成入口；虚像除来源/镜子/链深度外，继续展示源实体当前等级的索敌、射程、攻击速率、产出、对空或屏障耐久/恢复/反伤信息，并服从源定义的同一组 `show_*` 开关。单发箭塔展示攻速，持续激光塔展示 `laser_dps × level_factor × extra_factor` 的最终 DPS。
- **右上全局信息（批次 3 已实现）**：`GlobalInfoPanel` 展示关卡显示名、据点生命、场上敌人数、建筑数/上限与镜子数/上限。数据只读来自 `LevelResource`、`BaseCore`、`WaveManager` 和 `ResourceManager` 公共信号。
- **右下经济反馈（批次 3 已实现）**：`EconomyPanel` 保留每次资源增减事件，独立生成 `+x/-x` 上浮渐隐文字，主数字在旧值和最新值间滚动。动画用真实时间计算，在 0x 暂停时仍正常播放。
- **暂停菜单（批次 3 已实现，退出语义已更新）**：模态镜面层阻断世界选择和相机输入，提供设置、深重载当前关卡和退出当前关卡。主音量、窗口/全屏、UI 缩放即时写入 `user://settings.cfg`；退出发送 `exit_level_requested()`，经 Main/AppFlow 返回选关页，不退出程序。
- **最右侧波次三按钮（2026-07-27 现役）**：`WaveControlPanel` 贴画面最右侧纵向提供释放下一波、快速重启、退出当前关卡。释放按钮每次只调用一次 `WaveManager.start_next_wave()`；最后一波释放后禁用，另外两按钮仍可用。
- **下一波悬停预览（2026-08-03）**：悬停释放按钮时，`WaveTimelineModel` 聚合下一波敌人构成、唯一路径及地面/空中路线档案；请求经 `WaveControlPanel -> RuntimeHud -> Main -> PathHoverPreview` 转发并读取周期刷新的真实弯折路线。离开、点击、切关、暂停或控制台模态打开都会清除预览。
- **旧左侧时间轴（历史兼容）**：`WaveTimelinePanel.gd/.tscn` 保留 2026-07-22 批次 4 历史实现，但 `RuntimeHud.tscn` 已不再实例化；“首波手动、后续自动”和纵向绝对时间轴不再是现役事实。
- **F1 调试控制台（批次 6 已实现）**：最高 HUD 层提供八类实时开关、命令历史和注册表命令输入。控制台与暂停菜单共享 `RuntimeHud.is_modal_open()` 输入边界；控制台打开时阻断世界、相机、六机位和波次路径预览，但不自动改变游戏时间。
- **左上常驻调试信息（批次 6 已实现）**：控制台勾选或 `debug set` 启用的分类会同步显示在游戏画面左上角；关闭控制台后继续按真实时间刷新，全部关闭时自动收起。旧“波次时间轴上方预留区”仅是历史布局描述，现役左侧无正式时间轴。
- **只读检视模型**：`TileInspectionService` 订阅交互选择和 Manager 状态信号，`TileInspectionModelBuilder` 仅通过公共查询生成稳定 Dictionary；`TileInspectorPanel` 不持有玩法 Manager，也不提供修改回调。详情板位于画面最左侧中部；虚像/单纯元素检视不触发慢放，实体建筑/镜子的慢放与世界悬浮操作保持原逻辑。
- **现役布局**：程序启动/退关时由 `LevelSelectView` 在纯黑幕上仅显示 2×3 六槽缩略图和两侧翻页箭头，不显示外框、标题、页名、页码、关卡名或空槽；局内底部是镜子/建筑卡，左侧中部是按需地块详情，右上是全局信息，最右侧中部是三波次按钮，右下是经济/时间，暂停与控制台位于模态层。左侧不再实例化正式波次时间轴。
- **全局信息**：右上显示我方据点生命、当前场上敌人数、建筑/镜子容量与关卡名；不维护“本波剩余”第二份状态。
- 面板与逻辑解耦，通过信号/数据绑定更新（资源变化、释放游标、场上敌人、选中对象和 AppFlow 生命周期）。
- **纯缩略图分页选关（2026-07-27 现役）**：`AppRoot/AppFlowController` 是持久程序根，启动先创建 `LevelSelectView`。目录按 `LevelSelectCatalog.pages` 作者顺序翻页，每页固定六槽并按 `levels[0..5]` 以 GridContainer 行优先顺序显示；网格距屏幕四边固定 16 px，三列两行等分其余空间，槽间距 12 px，不再使用固定 `924×432` 网格或 `300×210` 槽尺寸。null 保留排版位置但完全透明且不可点击。左右箭头与鼠标滚轮共用 `change_page(delta)`：下一页时当前页左滑、目标页从右滑入，上一页反向，默认 0.25 秒 QUAD 缓出；双页面缓冲避免中间黑屏。动画期间槽位锁定，最多保存最后一次合法翻页请求，首尾钳制且不循环。`LevelThumbnail` 只读程序化绘制 LevelResource，内部地图保持比例居中，不实例化玩法节点。
- **旧调试 UI 已迁移**：主场景左上散落文字、提示与 `M3DebugPanel` 均隐藏且不再配置；右上 `LevelDebugPanel` 作为 Main 内开发快捷入口保留，但不属于正式 `RuntimeHud`、不替代 AppFlow 选关。F1 注册表仍并行提供关卡加载、资源修改、逐波释放和敌人生成命令。
- **放置反馈**：选择塔种后，可建造空格显示 1 级半透明塔虚影和朝向；无塔种或不可放置格不显示虚影，左侧 HUD 改为显示地块类型、高度、障碍、占位对象或占位建筑参数。
- **选中建筑操作**：选择模式点击有建筑地块后，`BuildingActionPanel` 在该建筑上方显示删除、升级、旋转；空格无效果。满级仅升级按钮置灰，删除显示当前等级配置的退款行为，旋转免费。
- **屏障反馈**：屏障模式只在合法路径格显示墙体虚影；左侧 HUD 和选择状态显示当前/最大耐久、脱战延迟、回血速度与反伤比例，屏障上方同时显示耐久数字。
- **边屏障反馈**：“边障”模式在任意两个有效地块之间显示贴边虚影，不要求已有路径；默认双向时 HUD 显示 `cell ↔ edge_to_cell`。放置后删除/升级可用，旋转因边对齐锁定而置灰。
- **复制镜反馈**：“复制镜”模式显示镜面生效侧、最近源格、对称目标格、整格内容名称与青蓝虚像；无源只警告仍可放置。`R` 翻面立即重算。选中后 `MirrorActionPanel` 悬浮提供删除/翻面，实体镜与建筑选择互斥。
- **旧波次 UI 兼容**：`WaveStatusPanel` 与 `WaveTimelinePanel` 均保留脚本/场景用于历史兼容和模型回归，但二者都不在正式 `RuntimeHud.tscn` 实例化；现役操作统一由右侧 `WaveControlPanel` 承担。

## 关键参数
> 全部为 Godot `@export`，编辑器运行时可调。

| 参数名 | 默认值 | 说明 |
|---|---|---|
| 布局锚点 | 预设 | 各面板锚点（顶/底/左/右/小地图） |
| 缩放适配 | expand | UI 缩放模式（适配不同分辨率） |
| minimap_enabled | true | 小地图开关 |
| hint_enabled | true | 操作提示开关 |
| Main.`debug_console_enabled` | true | 正式 F1 控制台与左上常驻调试层总开关。 |
| DebugConsole.`live_refresh_interval` / `max_history_lines` | 0.2 / 200 | 实时摘要刷新间隔和命令历史行数上限。 |
| DebugConsole.`panel_texture` / `execute_icon` | null | 控制台镜面背景与执行按钮美术接口。 |
| DebugOverlayPanel.`feature_enabled` / `refresh_interval` | true / 0.2 | 左上常驻调试摘要总开关和真实时间刷新间隔。 |
| DebugOverlayPanel.`panel_texture` | null | 左上常驻摘要镜面背景美术接口。 |
| WaveStatusPanel.`feature_enabled` | true | 旧 M4 兼容面板开关；正式主场景不再实例化。 |
| LevelResource.`building_card_slot_count` | 6 | 正式建筑携带槽数，范围 1～12；复制镜独立槽不计入。 |
| BuildCardBar.`card_size` | `(96,126)` | 单张卡片的基准尺寸。 |
| BuildCardBar.`card_separation` | 6 | 建筑卡之间的像素间距。 |
| BuildCardBar.`mirror_slot_separation` | 14 | 独立镜子槽与建筑槽组之间的间距。 |
| TileInspectorPanel.`feature_enabled` | true | 批次 2 左侧详情板总开关。 |
| TileInspectorPanel.`preview_size` | 82 | 每条内容的图标/灰盒预览边长。 |
| TileInspectorPanel.`entry_minimum_height` / `compact_entry_minimum_height` / `entry_separation` | 112 / 54 / 8 | 有图标条目、隐藏图标后的紧凑条目最小高度及间距；超出面板高度后滚动。 |
| TileInspectorPanel.`fallback_icon` | null | 全局条目占位图；为空时用内容名称前两字灰盒。 |
| Definition.`inspection_display` | 独立资源 | 建筑、复制镜、地块定义的对象级开关、可编辑名称/功能说明和字段级开关。 |
| GameTimeController.`tactical_slow_enabled` | true | 是否在选卡/选中实体时自动慢放。 |
| GameTimeController.`tactical_slow_scale` | 0.1 | 战术慢放倍率。 |
| GameTimeController.`fast_scale` | 2.0 | 批次 3 正式按钮使用的快速倍率。 |
| EconomyPanel.`feature_enabled` | true | 右下经济显示总开关。 |
| EconomyPanel.`number_roll_duration` / `popup_duration` / `popup_rise_distance` | 0.35 / 0.9 / 54 | 资源主数字滚动时长、增减弹字时长与上浮距离。 |
| EconomyPanel.`resource_icon` / `gain_color` / `spend_color` | null / 金 / 橙 | 资源图标与正负反馈颜色美术接口。 |
| GlobalInfoPanel.`feature_enabled` | true | 右上全局信息总开关。 |
| TimeControlPanel.`feature_enabled` | true | 慢放、2x、暂停按钮总开关。 |
| TimeControlPanel.`*_icon` | null | 慢放、快速和暂停按钮的可选图标接口。 |
| PauseMenu.`feature_enabled` | true | 暂停模态层总开关。 |
| PauseMenu.`settings_path` | `user://settings.cfg` | 局外设置持久化路径。 |
| PauseMenu.`collapsed_height` / `expanded_height` | 230 / 410 | 设置折叠与展开时的模态板高度。 |
| PauseMenu.`settings_icon` / `restart_icon` / `exit_icon` | null | 三个模态操作按钮的可选图标接口。 |
| WaveControlPanel.`feature_enabled` | true | 右侧三按钮总开关。 |
| WaveControlPanel.`button_size` | 68 | 释放、重启、退出三个圆形按钮边长，范围 48～96。 |
| WaveControlPanel.`start_next_wave_icon/restart_level_icon/exit_level_icon/fallback_enemy_icon` | null | 三按钮与下一波敌人图标的美术替换接口；空值使用文字灰盒。 |
| LevelSelectPageDefinition.`SLOT_COUNT` | 6 | 每页固定 2×3 六槽；null 位置保留且不可点击。 |
| LevelSelectView.`GridMargin` | 16 px | 选关六槽网格距屏幕四边的固定安全边距。 |
| LevelSelectView.`LevelGrid` 间距 | 12 px | 三列两行之间的横纵间距；其余空间由六槽等分。 |
| LevelSelectView.`page_slide_duration` | 0.25 s | 双页面横向滑动时长；范围 0.05～1.0 秒，使用真实时间。 |

## 关键架构

### 文件构成

| 文件 | class_name / 基类 | 角色 |
|---|---|---|
| `scripts/AppFlowController.gd` | `AppFlowController` / `Node` | 持久程序流根；任一时刻提交一个选关页或一个已成功首载的 Main。 |
| `scenes/AppRoot.tscn` | 无 class_name / `Node` 场景 | `project.godot` 主场景；装配 Catalog、LevelSelectView 场景和 Main 场景。 |
| `scripts/Main.gd` | `MainController` / `Node3D` | 局内组合根；装配 Manager、正式 HUD、路径预览、调试绑定并把退出请求上送 AppFlow。 |
| `scripts/ui/RuntimeInteractionController.gd` | `RuntimeInteractionController` / `Node` | 正式 SELECT/块放置/边放置/镜子放置状态机和单次尝试事务。 |
| `scripts/ui/GameTimeController.gd` | `GameTimeController` / `Node` | 统一求解暂停、战术慢放、2x 与 1x 的时间优先级。 |
| `scripts/ui/RuntimeSettings.gd` | `RuntimeSettings` / `RefCounted` | 读写并应用主音量、窗口模式和 UI 缩放。 |
| `scripts/ui/EconomyPanel.gd` / `scenes/ui/EconomyPanel.tscn` | `EconomyPanel` / `Control` | 真实时间资源数字滚动和多事件弹字。 |
| `scripts/ui/GlobalInfoPanel.gd` / `scenes/ui/GlobalInfoPanel.tscn` | `GlobalInfoPanel` / `Control` | 信号驱动的关卡/据点/敌人/容量摘要。 |
| `scripts/ui/TimeControlPanel.gd` / `scenes/ui/TimeControlPanel.tscn` | `TimeControlPanel` / `Control` | 慢放、2x 和暂停的正式控件。 |
| `scripts/ui/PauseMenu.gd` / `scenes/ui/PauseMenu.tscn` | `PauseMenu` / `Control` | 阻断世界输入的暂停模态层与局外设置入口。 |
| `scripts/ui/WaveTimelineModel.gd` | `WaveTimelineModel` / `RefCounted` | 把关卡波次资源只读投影为稳定摘要；现役供下一波详情复用。 |
| `scripts/ui/WaveControlPanel.gd` | `WaveControlPanel` / `Control` | 右侧释放下一波/重启/退出三按钮、下一波详情与路径预览信号。 |
| `scenes/ui/WaveControlPanel.tscn` | 无 class_name / `Control` 场景 | 正式 HUD 的三个圆形按钮和向左展开详情板。 |
| `scripts/ui/WaveTimelinePanel.gd` / `scenes/ui/WaveTimelinePanel.tscn` | `WaveTimelinePanel` / `Control` | 旧左侧纵向时间轴兼容文件；正式 HUD 不实例化。 |
| `scripts/ui/BuildCardBar.gd` | `BuildCardBar` / `Control` | 独立镜子槽、可调建筑槽、卡片可用性、选中框、空镜面和状态反馈。 |
| `scripts/shared/InspectionDisplayConfig.gd` | `InspectionDisplayConfig` / `Resource` | 跨建筑、镜子、地块共享的两级只读检视显示策略。 |
| `scripts/ui/TileInspectionService.gd` | `TileInspectionService` / `Node` | 保存检视选择、订阅动态状态并调度只读模型刷新。 |
| `scripts/ui/TileInspectionModelBuilder.gd` | `TileInspectionModelBuilder` / `RefCounted` | 将地块、建筑、边实体、镜子、虚像和元素状态聚合为稳定只读模型。 |
| `scripts/ui/TileInspectorPanel.gd` | `TileInspectorPanel` / `Control` | 把检视模型渲染为左侧镜面滚动条目，不执行玩法修改。 |
| `scenes/ui/TileInspectorPanel.tscn` | `Control` 场景 | 左侧中部响应式详情板场景和美术资源接口。 |
| `scripts/ui/RuntimeHud.gd` | `RuntimeHud` / `Control` | M6 正式 HUD 组合根；连接卡片、检视、全局/经济、时间、暂停、右侧波次三按钮和调试控制台。 |
| `scenes/ui/RuntimeHud.tscn` | 无 class_name / `Control` 场景 | 正式局内 HUD；实例化 WaveControlPanel，不实例化旧 WaveTimelinePanel。 |
| `scripts/ui/LevelSelectView.gd` | `LevelSelectView` / `Control` | 纯黑幕双页面 2×3 六槽、两侧箭头、滚轮/按钮横向滑动与关卡选择信号。 |
| `scripts/ui/LevelSelectSlot.gd` | `LevelSelectSlot` / `Button` | 无框无文字缩略图槽；空/非法资源透明禁用，滑动期间独立锁定交互。 |
| `scripts/ui/LevelThumbnail.gd` | `LevelThumbnail` / `Control` | 只读程序化绘制网格、地形、路径、出生点和据点；不创建玩法节点。 |
| `scenes/ui/LevelSelectView.tscn` | 无 class_name / `Control` 场景 | 全屏纯黑选关；裁剪容器内含两组固定三列两行缩略图网格与两侧纯箭头。 |
| `resources/level_select/LevelSelectCatalog.tres` | `LevelSelectCatalog` / `Resource` | 正式选关目录；按作者顺序显式引用页面资源。 |
| `resources/level_select/LevelSelectPage*.tres` | `LevelSelectPageDefinition` / `Resource` | 各页固定六槽的作者关卡顺序；null 位置保持透明占位。 |
| `scripts/ui/DebugConsole.gd` / `scenes/ui/DebugConsole.tscn` | `DebugConsole` / `Control` | 响应式镜面 F1 模态、分类勾选、实时摘要和命令输入；业务实现外置。 |
| `scripts/ui/DebugOverlayPanel.gd` / `scenes/ui/DebugOverlayPanel.tscn` | `DebugOverlayPanel` / `Control` | 在控制台关闭后仍持续显示已启用分类的左上角只读摘要。 |
| `scripts/level/LevelDebugPanel.gd` | `LevelDebugPanel` / `Control` | 右上角运行时选关快捷入口；显示当前关卡并通过正式 LevelLoader 打开资源选择器。 |
| `scripts/ui/M3DebugPanel.gd` | `M3DebugPanel` / `Control` | 旧 M3 灰盒兼容脚本；正式主场景隐藏且不配置。 |
| `scripts/ui/BuildingActionPanel.gd` | `BuildingActionPanel` / `Control` | 根据相机投影跟随选中建筑，提供删除、升级、旋转三项上下文操作。 |
| `scripts/ui/MirrorActionPanel.gd` | `MirrorActionPanel` / `Control` | 跟随选中复制镜，提供删除和生效侧翻面。 |
| `scripts/ui/WaveStatusPanel.gd` | `WaveStatusPanel` / `Control` | 旧 M4 兼容摘要/首波入口；正式主场景不再实例化。 |
| `tests/runtime_ui_batch2_test.gd` | 无 / `SceneTree` | 58 项只读模型、自定义功能说明、实体/复制塔 Combat 一致性、激光最终 DPS、动态刷新、选择语义、滚动和三档分辨率回归。 |
| `tests/runtime_inspection_configuration_test.gd` | 无 / `SceneTree` | 94 项默认兼容、正式资源/BuildingManager 箭塔深加载绑定、对象/字段过滤、名称/功能说明和自适应排版回归；不锁死策划自定义名称、可见性或说明文本。 |
| `tests/runtime_ui_batch3_test.gd` | 无 / `SceneTree` | 69 项全局/经济信号、真实时间动画、时间优先级、设置持久化、深重载和三档分辨率回归。 |
| `tests/runtime_ui_batch4_test.gd` | 无 / `SceneTree` | 47 项只读波次模型、单悬停窗、窄时间轴、编号端点文案、共享据点生命、多路径流向和三档分辨率回归。 |
| `tests/runtime_ui_batch6_test.gd` | 无 class_name / `SceneTree` | 77 项 F1、注册表、八类开关、业务命令、三档控制台布局、左上常驻摘要、统一模态和旧入口迁移回归。 |
| `tests/manual_wave_release_test.gd` | 无 class_name / `SceneTree` | 逐波释放、重叠、波内归一、胜利和 Debug 终态边界回归。 |
| `tests/level_select_test.gd` | 无 class_name / `SceneTree` | Catalog/Page 校验、六槽分页顺序、空槽、翻页、信号和只读缩略图回归。 |
| `tests/manual_wave_and_level_flow_test.gd` | 无 class_name / `SceneTree` | AppFlow 启动/提交/回退/返回、右侧三按钮与直接 Main 兼容回归。 |
| `scenes/Main.tscn` | 无 class_name / `Node3D` 场景 | 局内 Main；实例化 RuntimeHud，并保留 HUD 外的 LevelDebugPanel/M3DebugPanel 兼容节点。 |

### 调用关系

```text
project.godot -> AppRoot.tscn -> AppFlowController (persistent)
  -> LevelSelectView.configure(LevelSelectCatalog)
     -> pages 按 Catalog.pages 作者顺序
     -> slots 按 Page.levels[0..5] 行优先顺序，null 保留为空槽
     -> LevelSelectSlot -> LevelThumbnail read-only draw
     -> level_selected(level: LevelResource)
  -> AppFlowController._start_level(level)
     -> Main.configure_startup_level(level)
     -> Main enters tree -> LevelLoader.load_level(level)
     -> startup_level_load_resolved(success, reason)
     -> success: commit Main and release LevelSelectView
     -> failure: free candidate Main and preserve LevelSelectView

RuntimeHud (Main/HUD)
  ├─ BuildCardBar: 底部镜子/建筑卡
  ├─ GlobalInfoPanel: 右上关卡/据点/敌人/容量
  ├─ WaveControlPanel: 最右侧下一波/重启/退出三按钮
  ├─ TileInspectorPanel: 左侧按需只读详情
  ├─ EconomyPanel + TimeControlPanel: 右下经济/慢放/2x/暂停
  ├─ PauseMenu: 模态设置/重启/退出当前关卡
  └─ DebugConsole + DebugOverlayPanel

BuildCardBar -> RuntimeInteractionController -> BuildingManager / MirrorManager
RuntimeInteractionController.world_selection_changed
  -> RuntimeHud -> TileInspectionService -> TileInspectionModelBuilder
  -> `{has_content, cell, selected_edge_id, terrain_name, height_level,
       allows_tile_building, allows_edge_building, entries}`
  -> TileInspectorPanel
RuntimeInteractionController + Building/Mirror selection
  -> GameTimeController -> Engine.time_scale
ResourceManager / BaseCore / WaveManager signals
  -> BuildCardBar / EconomyPanel / GlobalInfoPanel

WaveControlPanel start -> WaveManager.start_next_wave()
WaveControlPanel hover next wave
  -> WaveTimelineModel.build(level) read-only entry at release cursor
  -> paths_preview_requested(paths)
  -> RuntimeHud.wave_paths_preview_requested(paths)
  -> Main -> PathHoverPreview.preview_paths(paths)
Pause / console / click / level transition
  -> WaveControlPanel.clear_hover_preview()
  -> RuntimeHud -> Main -> PathHoverPreview.clear_preview()

WaveControlPanel or PauseMenu restart
  -> RuntimeHud.restart_level_requested
  -> Main -> LevelLoader.reload_current_level()
WaveControlPanel or PauseMenu exit current level
  -> RuntimeHud.exit_level_requested
  -> Main.prepare_for_level_transition()
  -> Main.return_to_level_select_requested
  -> AppFlowController frees Main, restores Engine.time_scale = 1.0,
     creates a fresh LevelSelectView; SceneTree stays alive

DebugConsole -> DebugCommandRegistry -> RuntimeDebugBindings
  -> LevelLoader / ResourceManager / WaveManager public APIs
DebugCategoryRegistry -> DebugConsole + DebugOverlayPanel + optional Path/Route visuals
DebugConsole.open_changed + PauseMenu -> RuntimeHud unified modal -> Main input lock

BuildingActionPanel -> BuildingManager remove / upgrade / rotate
MirrorActionPanel -> MirrorManager remove / flip
WaveTimelinePanel / WaveStatusPanel / M3DebugPanel：兼容文件保留，正式 RuntimeHud 不实例化
LevelDebugPanel：Main 内开发快捷入口，位于正式 RuntimeHud 之外
```

## 函数索引

| 文件 | 函数签名 | 职责 |
|---|---|---|
| `AppFlowController.gd` | `return_to_level_select() -> void` | 幂等发起延迟退关事务，避免信号栈内释放 Main。 |
| `AppFlowController.gd` | `_on_level_selected(level: LevelResource) -> void` | 只接受通过运行时校验的非空关卡并开始候选 Main 事务。 |
| `AppFlowController.gd` | `_start_level(level: LevelResource) -> void` | 实例化候选 Main、先注入启动关卡、连接结果/退出信号并以隐藏禁用状态加入树。 |
| `AppFlowController.gd` | `_on_startup_level_load_resolved(success: bool, reason: String) -> void` | 记录 Main 首载结果并延迟提交。 |
| `AppFlowController.gd` | `_commit_start_level() -> void` | 成功时释放选关并启用 Main；失败时只释放候选 Main、保留选关。 |
| `LevelSelectView.gd` | `configure(catalog: LevelSelectCatalog) -> void` | 注入目录并回到第一页；按作者顺序刷新固定六槽。 |
| `LevelSelectView.gd` | `change_page(delta: int) -> void` | 箭头和滚轮共用的非循环滑动入口；动画中保存最后一次合法方向。 |
| `LevelSelectView.gd` | `_start_page_slide(target_page_index: int, delta: int) -> void` | 绑定备用页，锁定槽位并并行动画当前/目标页面。 |
| `LevelSelectView.gd` | `_on_slide_finished() -> void` | 提交页码、交换页面池、恢复位置并处理排队请求。 |
| `LevelSelectView.gd` | `get_slot_control(slot_index: int) -> LevelSelectSlot` | 返回固定位置的槽控件；越界返回 null。 |
| `LevelSelectView.gd` | `get_slot_level(slot_index: int) -> LevelResource` | 返回当前页零基槽位的原关卡引用；越界/空槽为 null。 |
| `LevelSelectView.gd` | `_gui_input(event: InputEvent) -> void` | 消费真实滚轮按下事件；下滚前进一页、上滚后退一页。 |
| `LevelSelectSlot.gd` | `set_level(value: LevelResource) -> void` | 只读校验并刷新缩略图；空或非法资源透明禁用。 |
| `LevelSelectSlot.gd` | `set_interaction_locked(value: bool) -> void` | 设置滑动期交互锁，不改变空槽/非法槽的基础可用性。 |
| `LevelSelectSlot.gd` | `get_thumbnail() -> LevelThumbnail` | 返回槽位内程序化缩略图控件。 |
| `LevelThumbnail.gd` | `set_level(value: LevelResource) -> void` | 只读重建绘制缓存并请求重绘，不写回资源。 |
| `LevelThumbnail.gd` | `debug_get_draw_data() -> Array[Dictionary]` | 返回单元绘制缓存深副本，防止测试修改内部状态。 |
| `Main.gd` | `configure_startup_level(level: LevelResource) -> bool` | 仅入树前接受 AppFlow 选择的启动关卡。 |
| `Main.gd` | `prepare_for_level_transition() -> void` | 清理模态、倍率、预览并恢复 `Engine.time_scale = 1.0`。 |
| `LevelDebugPanel.gd` | `configure(level_loader: LevelLoader) -> void` | 注入正式关卡加载入口并订阅结果信号。 |
| `LevelDebugPanel.gd` | `_show_file_dialog() -> void` | 打开资源关卡选择器。 |
| `LevelDebugPanel.gd` | `_on_file_selected(path: String) -> void` | 请求 LevelLoader 切换运行时关卡。 |
| `LevelDebugPanel.gd` | `_on_level_loaded(level_resource: LevelResource, source_path: String) -> void` | 更新当前关卡名。 |
| `LevelDebugPanel.gd` | `_on_level_load_failed(source_path: String, reason: String) -> void` | 显示加载失败原因。 |
| `M3DebugPanel.gd` | `configure(building_manager, resource_manager, combat_manager, mirror_manager = null) -> void` | 注入建筑、战斗、经济与 M5 镜子入口并订阅状态信号。 |
| `M3DebugPanel.gd` | `get_mode() -> InteractionMode` | 返回当前互斥交互模式。 |
| `M3DebugPanel.gd` | `get_selected_definition() -> BuildingDefinition` | 返回当前箭塔、激光塔、地块屏障、边屏障定义或 null。 |
| `M3DebugPanel.gd` | `select_mode(value: InteractionMode) -> void` | 更新按钮状态、模式文本并广播。 |
| `M3DebugPanel.gd` | `cancel_to_select() -> void` | 右键取消时回到选择模式。 |
| `M3DebugPanel.gd` | `_refresh_summary() -> void` | 从 Manager 读取资源、上限与目标数量。 |
| `M3DebugPanel.gd` | `_on_upgrade_pressed() -> void` | 请求 BuildingManager 升级当前选择。 |
| `M3DebugPanel.gd` | `_on_preview_updated(building: Building) -> void` | 显示预览塔种、1 级和离散朝向。 |
| `BuildingActionPanel.gd` | `configure(building_manager: BuildingManager, camera: Camera3D) -> void` | 注入建筑公共入口与投影相机，并订阅选择/升级/删除信号。 |
| `BuildingActionPanel.gd` | `_update_projection() -> void` | 将选中建筑动作锚点投影到屏幕，越过相机背面时隐藏。 |
| `BuildingActionPanel.gd` | `_on_delete_pressed()` / `_on_upgrade_pressed()` / `_on_rotate_pressed()` | 调用三个 BuildingManager 公共操作。 |
| `MirrorActionPanel.gd` | `configure(mirror_manager: MirrorManager, camera: Camera3D) -> void` | 订阅镜子选择/删除/翻面并把按钮投影到镜面上方。 |
| `WaveControlPanel.gd` | `configure(wave_manager: WaveManager) -> void` | 订阅下一波、释放和状态信号，不维护第二份游标。 |
| `WaveControlPanel.gd` | `set_level(level: LevelResource) -> void` | 重建只读摘要条目并清理旧关悬停。 |
| `WaveControlPanel.gd` | `set_preview_suppressed(suppressed: bool) -> void` | 模态打开时禁止并清理详情/世界路径预览。 |
| `WaveControlPanel.gd` | `clear_hover_preview() -> void` | 隐藏详情并发送 `paths_preview_cleared()`。 |
| `WaveControlPanel.gd` | `get_previewed_wave_number() -> int` | 返回当前预览的下一波号；未预览为 0。 |
| `WaveTimelineModel.gd` | `build(level: LevelResource) -> Array[Dictionary]` | 只读生成作者顺序摘要；`paths` 保持唯一路径兼容，`path_requests` 额外区分地面/空中真实路线。 |
| `WaveTimelinePanel.gd` | `configure(wave_manager: WaveManager) -> void` 等 | 旧纵向时间轴兼容 API；正式 HUD 不调用。 |
| `WaveStatusPanel.gd` | `configure(wave_manager: WaveManager, base_core: BaseCore) -> void` | 旧 M4 兼容摘要；正式 HUD 不调用。 |
| `RuntimeHud.gd` | `configure_wave_controls(wave_manager: WaveManager) -> void` | 注入现役 WaveManager 并由 WaveControlPanel 驱动逐波操作。 |
| `RuntimeInteractionController.gd` | `select_building_card(definition) -> bool` | 清除实体选择并进入块/边建筑放置状态。 |
| `RuntimeInteractionController.gd` | `select_copy_mirror_card() -> bool` | 清除实体选择并进入复制镜边放置状态。 |
| `RuntimeInteractionController.gd` | `handle_primary(cell_pick, edge_pick) -> Dictionary` | 在选择模式选实体，或执行恰好一次放置并返回稳定结果。 |
| `RuntimeInteractionController.gd` | `cancel_to_select(clear_world_selection=true) -> void` | 清卡、清预览、按需清实体并回选择模式。 |
| `RuntimeInteractionController.gd` | `has_world_selection() -> bool` / `get_world_selection_cell() -> Vector3i` / `get_world_selection_edge_id() -> String` | 返回正式选择模式当前锁定格/边；变化通过 `world_selection_changed(has_cell, cell, edge_id)` 广播。 |
| `GameTimeController.gd` | `configure(interaction: RuntimeInteractionController, building_manager: BuildingManager, mirror_manager: MirrorManager) -> void` | 订阅交互与实体选择，建立战术上下文。 |
| `GameTimeController.gd` | `set_tactical_slow_enabled(enabled: bool) -> void` | 开关自动战术慢放并立即重算倍率。 |
| `GameTimeController.gd` | `set_fast_enabled(enabled: bool) -> void` / `set_paused(paused: bool) -> void` | 保存快速/暂停请求并按固定优先级重算。 |
| `GameTimeController.gd` | `reset_runtime_state() -> void` | 退关前清除快速/暂停请求并恢复 `Engine.time_scale = 1.0`。 |
| `EconomyPanel.gd` | `configure(resource_manager) -> void` | 订阅资源变化，不持有任何经济修改入口。 |
| `EconomyPanel.gd` | `advance_ui_time(real_delta: float) -> void` | 以不受 `Engine.time_scale` 影响的 delta 推进滚动数字和弹字。 |
| `GlobalInfoPanel.gd` | `configure(resource_manager, wave_manager, base_core) -> void` | 订阅容量、敌人数和据点生命信号。 |
| `GlobalInfoPanel.gd` | `set_level_context(level, source_path="") -> void` | 使用可编辑关卡名，空值时回退到资源文件名。 |
| `TimeControlPanel.gd` | `configure(time_controller) -> void` | 将正式按钮与时间状态双向同步。 |
| `PauseMenu.gd` | `configure(root_window: Window) -> void` | 读取、应用设置并绑定目标窗口。 |
| `PauseMenu.gd` | `open_menu() -> void` / `close_menu() -> void` / `is_open() -> bool` | 管理模态可见性及设置折叠状态。 |
| `RuntimeSettings.gd` | `load_from_file(path)` / `save_to_file(path)` | 使用 `ConfigFile` 持久化局外设置。 |
| `RuntimeSettings.gd` | `apply_to_runtime(root_window) -> void` | 应用主音量、窗口模式与 UI 缩放。 |
| `BuildCardBar.gd` | `configure(resource_manager, mirror_definition, building_definitions, slot_count) -> void` | 构造独立镜子卡、建筑卡和空镜面并订阅经济信号。 |
| `RuntimeHud.gd` | `configure(interaction: RuntimeInteractionController, time_controller: GameTimeController, resource_manager: ResourceManager, building_manager: BuildingManager, mirror_manager: MirrorManager, slot_count: int = 6) -> void` | 组合卡槽、交互、经济、时间和暂停控制器。 |
| `RuntimeHud.gd` | `configure_global_info(resource_manager: ResourceManager, wave_manager: WaveManager, base_core: BaseCore) -> void` | 注入全局只读显示依赖。 |
| `RuntimeHud.gd` | `configure_debug_console(command_registry: DebugCommandRegistry, category_registry: DebugCategoryRegistry) -> void` | 注入外置命令与分类事实源。 |
| `DebugOverlayPanel.gd` | `configure(category_registry: DebugCategoryRegistry) -> void` | 订阅与控制台相同的分类事实源。 |
| `DebugOverlayPanel.gd` | `refresh_now() -> void` | 刷新左上角摘要并在无启用分类时收起。 |
| `RuntimeHud.gd` | `configure_inspection(grid_manager: GridManager, tile_manager: TileManager, building_manager: BuildingManager, mirror_manager: MirrorManager, tile_effect_system: TileEffectSystem) -> void` | 注入只读检视依赖并同步现有选择。 |
| `RuntimeHud.gd` | `apply_level_configuration(level: LevelResource, source_path: String = "") -> void` | 切关时应用建筑槽数、关卡显示名及下一波摘要。 |
| `RuntimeHud.gd` | `prepare_for_level_transition() -> void` | 退关前清理波次预览、控制台、暂停和时间倍率。 |
| `RuntimeHud.gd` | `is_modal_open() -> bool` / `close_top_modal() -> void` | 合并暂停和控制台状态，优先关闭控制台。 |
| `TileInspectionService.gd` | `configure(grid_manager, tile_manager, building_manager, mirror_manager, tile_effect_system) -> void` | 订阅内容/耐久/方向/投影/装填变化，重复配置前安全断开旧信号。 |
| `TileInspectionService.gd` | `set_selected_cell(has_cell: bool, cell: Vector3i, edge_id: String = "") -> void` | 接收正式选择事实源并触发合并刷新。 |
| `TileInspectionService.gd` | `inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary` | 返回 Builder 的只读快照；顶层键为 `has_content/cell/selected_edge_id/terrain_name/height_level/allows_tile_building/allows_edge_building/entries`。 |
| `InspectionDisplayConfig.gd` | `resolve_display_name(fallback: String) -> String` / `resolve_function_description(fallback: String) -> String` | 使用非空自定义文本，否则回退到当前名称或内置说明。 |
| `TileInspectionModelBuilder.gd` | `inspect_cell(cell: Vector3i, selected_edge_id: String = "") -> Dictionary` | 聚合本格 occupant、全部相邻边实体、同格投影和元素运行时数据；先按对象级 `visible` 过滤，条目键含 `kind/name/category/state/icon/accent/description/show_icon/show_category/show_state/show_description/lines/has_source/source_cell/mirror_edge_id`。 |
| `TileInspectionModelBuilder.gd` | `_append_building_gameplay_lines(lines: Array[String], building: Building, config: InspectionDisplayConfig, shared_runtime_state: bool) -> void` | 让建筑实体与复制建筑复用同一套当前等级战斗、经济、对空及屏障运行时详情；按攻击类型输出箭塔攻速或激光最终 DPS，`shared_runtime_state` 仅改变共享耐久文案。 |
| `TileInspectorPanel.gd` | `display_model(model: Dictionary) -> void` | 非空时按字段开关自适应重建滚动条目并展开，空模型时收起。 |
| `TileInspectorPanel.gd` | `clear_inspection() -> void` | 清除当前只读快照及动态条目。 |

### 关键新信号

| 信号 | 签名 | 语义 |
|---|---|---|
| `LevelSelectView.level_selected` | `(level: LevelResource)` | 合法非空槽被点击；不直接装配关卡。 |
| `MainController.startup_level_load_resolved` | `(success: bool, reason: String)` | 候选 Main 的首次 LevelLoader 事务结束，供 AppFlow 提交或回滚。 |
| `MainController.return_to_level_select_requested` | `()` | 局内请求返回选关页；不退出 SceneTree。 |
| `RuntimeHud.restart_level_requested` | `()` | 来自 PauseMenu 或 WaveControlPanel 的统一重启请求。 |
| `RuntimeHud.exit_level_requested` | `()` | 来自 PauseMenu 或 WaveControlPanel 的统一退关请求。 |
| `RuntimeHud.modal_state_changed` | `(open: bool)` | 暂停/控制台任一开启状态，供 Main 锁定世界与相机输入。 |
| `RuntimeHud.wave_paths_preview_requested` | `(paths: Array)` | 把下一波唯一路径转发给 Main。 |
| `RuntimeHud.wave_paths_preview_cleared` | `()` | 请求 Main 清理世界路径预览。 |
| `WaveControlPanel.restart_level_requested` | `()` | 右侧重启按钮的高层请求。 |
| `WaveControlPanel.exit_level_requested` | `()` | 右侧退出当前关卡按钮的高层请求。 |
| `WaveControlPanel.paths_preview_requested` | `(paths: Array)` | 下一波悬停路径集合。 |
| `WaveControlPanel.paths_preview_cleared` | `()` | 下一波详情结束或被抑制。 |
| `PauseMenu.exit_level_requested` | `()` | 暂停菜单退出当前关卡；不表示退出程序。 |

## 约定事实源

- `project.godot` 的 `run/main_scene` 指向 `AppRoot.tscn`；AppFlow 存活期覆盖选关与全部单局 Main，内容根任一时刻只提交一个活动子界面。
- Catalog 的 `pages` 数组顺序是页面顺序；Page 的 `levels[0..5]` 是槽位顺序，GridContainer 三列使视觉顺序为从左到右、从上到下。null 不压缩、不补位。
- 正式局内波次操作只来自 `WaveControlPanel -> WaveManager`；旧 Timeline/Status 不得重新成为现役事实源。
- 路径预览只能按 `WaveControlPanel -> RuntimeHud -> Main -> PathHoverPreview` 转发；UI 不直接持有 PathManager。
- 重启保留当前 Main，通过 LevelLoader 完整重载；退出先清理 Main 局内状态，再由 AppFlow 释放 Main、恢复 1x 并重建选关。两者不可混用。
- `LevelThumbnail` 缓存只读绘制数据；不补齐稀疏地块、不创建 Grid/Tile/Path/Wave Manager、不写回 LevelResource。

## 已知限制 / 初版不做的部分
- 不做敌方据点相关 UI；右上只展示共享我方据点生命和当前场上敌人数。
- 已实现基础分页选关，但不含主菜单、关卡解锁、星级、通关进度或选关状态持久化。
- F1 `load` 与 Main 内 `LevelDebugPanel` 是开发入口，不改变正式选关目录，也不代表解锁流程。
- 旧 `LevelDebugPanel`、`M3DebugPanel`、`WaveStatusPanel`、`WaveTimelinePanel` 文件继续登记兼容；正式 `RuntimeHud.tscn` 不实例化 M3/Status/Timeline，LevelDebugPanel 位于 Main 的 HUD 兼容层而非正式 RuntimeHud。
- 下一波详情仍把同一波多个组聚合为一个条目；组级波内延迟/间隔保留在策划配置中，悬停不显示。
- 当前选关缩略图是只读程序化 2D 示意，不是局内小地图；不做迷雾或交互点选。
- 本轮全屏等分布局已通过 `level_select_test.gd` 三档分辨率专项及全量测试入口；真机仍需以 `AppRoot.tscn` 验收最终视觉占比。
