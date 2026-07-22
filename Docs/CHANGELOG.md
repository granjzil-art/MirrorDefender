# MirrorDefender · 变更日志（逐里程碑）

## M6 / UI · 批次 1 正式卡槽、单次放置与战术慢放 — 2026-07-22
**模块**：UI / Input / Camera / Building / Mirror / Resource / Level / Main / Tests / Docs。

- 新增模块化 `RuntimeHud` 与底部单行镜面卡槽：复制镜独立槽，默认 6 个建筑槽，携带箭塔/激光塔/屏障并显示 3 个空镜面；费用、资源/上限置灰、金色选中框和可选 `card_icon` 接口已接通。
- 新增 `RuntimeInteractionController` 作为正式交互事实源；成功、资源不足、建筑上限、非法地块、非法边和未命中均只执行一次尝试，随后清卡、清预览、清实体选择并回 `SELECT`，新放置实体不保持自动选中。
- 右键改为 GUI 分发前的全局取消；左键 UI 由控件消费，不穿透到世界。主场景默认隐藏旧 M3 建造面板，原 Manager 事务和玩法入口保持兼容。
- 新增 `GameTimeController`，固定 `暂停 0x > 战术慢放 0.1x > 快速 2x > 正常 1x`；选卡或选中实体建筑/边建筑/镜子自动慢放，右下按钮可关闭。CameraController 使用真实 delta 保持慢放期间镜头手感。
- LevelResource 新增 1～12 的 `building_card_slot_count`（默认 6）；M6 批次 1 回归新增 55 项（含三档 16:9 分辨率布局），完整入口扩展为 10 个测试套件。

## M6 / Docs · 固化操作与 UI 大版本事实源 — 2026-07-22
**模块**：Docs / UI Planning / Level Data / Tile Data / FX Data。

- 新增 M6 长期设计与开发计划，固定左侧波次时间轴、底部镜子/建筑卡槽、右侧信息区、右下经济与时间控制、暂停模态和 F1 控制台的整体布局。
- 固定左键肯定、右键取消、单卡单次尝试、默认 6 个建筑槽、独立镜子槽以及 `0x > 0.1x > 2x > 1x` 时间优先级；按 6 个独立批次拆分实现与验收。
- 里程碑重新映射为当前 M6“操作与 UI 大版本”；旧反射镜 M6 顺延待排期，历史计划文档保留追溯说明。
- 本次开发前基线一并纳入当前工作区关卡与效果调参：DemoLevel1 第三条手工路径/出生点、DemoLevel2 初始资源、TestLevel0 波次与据点配置、尖刺伤害/空中开关、黑洞容量/吞噬间隔/空中开关及关卡倒影资源默认项调整。

## Tile / Mirror · 黑洞容量、周期吞噬与装填深度 — 2026-07-21
**模块**：Tile / Combat / Mirror / Visual / Tests / Docs。

- `VoidTileEffect` 新增装填上限、逐点恢复秒数、吞噬检查间隔及空载/满载坑深；黑洞改为周期检查，每次选择格上当前生命最高的适用敌人，满载时停止吞噬。
- 每个真实空洞用独立 `VoidCapacityRuntime` 保存局内状态；直接/递归镜像按根源格共享容量和时钟，不改写关卡资源。
- TileRenderer 按装填比将坑底在空载/满载深度间插值，恢复时反向变深；源格和镜像快照同步重建。
- 地块、镜子与空中单位回归覆盖快速逃脱、最高生命优先、满载、恢复、独立源格、投影共享容量与深度。

## AI / Mirror · 修复重叠屏障摧毁后穿过石头虚影 — 2026-07-21
**模块**：AI / Path / Mirror / Tests / Docs。

- 保持同格普通屏障高于石头投影的攻击优先级；屏障摧毁并导致镜像帧末重建后，EnemyUnit 依据当前逻辑路径段重新解析下一格的新石头代理，不再要求单位世界坐标仍处于前一格中心。
- 无可达手工路径时敌人停止并攻击重建后的石头虚影；有可达路径时仍使用原最短路径规则。复制镜回归增至 101 项，覆盖“屏障优先→帧末投影换代→无路攻击石头”完整链路。

## AI · 修复全路径堵塞后失效石头引用报错 — 2026-07-21
**模块**：AI / Tile / Tests / Docs。

- `EnemyUnit` 的阻挡存活性入口改为先接收 `Variant` 再做 Object 有效性收窄，避免大石头在帧末释放后，其他持有旧无路攻击目标的敌人在进入函数前触发类型错误。
- 地块/换路回归增至 68 项，新增“石头被攻破并真正释放后，敌人清理失效目标并沿原路继续”的帧边界回归。

## AI / Tile / Mirror · 大石头无路攻击与共享源耐久 — 2026-07-21
**模块**：AI / Path / Tile / Mirror / Tests / Docs。

- 阻挡响应收敛为 `DIRECT_ATTACK` 与 `REROUTE_THEN_ATTACK`：普通屏障继续直接攻击，大石头仍在前一格选择最短手工路径，但无路时返回具体石头代理并复用敌人近战/远程攻击状态。
- `RockTileEffect` 新增可编辑最大耐久（正式资源默认 500）；TileManager 为每个真实石头创建独立运行时耐久节点，不污染共享资源或关卡配置。
- 大石头实体、直接虚像和递归虚像共享真实源耐久；任一入口击毁源石头后，元素/阻挡和关联投影消失，镜子保留，原格开放块建筑与边建筑。
- 地块元素回归扩展至 67 项，复制镜回归扩展至 94 项，覆盖独立逐格耐久、关卡重载、近战/远程无路攻击、递归伤害回传和镜子生命周期。

## Mirror / Building · 镜面横向顺序、追踪转向与完整姿态镜像 — 2026-07-21
**模块**：Mirror / Building / Tests / Docs。

- 镜面 Shader 增加反射相机横向手性补偿：用反向屏幕 X 坐标采样同投影反射纹理，镜前右侧地块在镜中仍位于右侧，不改纵向顺序。
- BuildingDefinition 新增 `FIXED_FACING / TRACK_TARGET` 配置化朝向能力和视觉转向速度；箭塔追踪锁定目标但不改逻辑 `facing_index`，激光塔保持手动固定攻击朝向。
- 建筑投影不再只保留创建时姿态；每帧在原快照节点上同步源模型根变换、子节点、可见性和骨骼姿态，再作用全部镜轴的组合反射，避免重建闪烁。
- CopyMirror 回归增至 87 项，新增横向顺序校正、追踪朝向不污染逻辑方向、固定朝向手动旋转和投影节点不重建检查。

## Architecture · 批次 1 健壮性基线 — 2026-07-21
**模块**：Tests / Shared / Level / Grid / Building / Unit / Mirror / FX / Resource / Docs。

- 行为测试改用独立内存夹具，正式建筑、敌人、镜子、倒影和 M4 关卡只做加载/配置冒烟；新增单命令全量入口，并把 Godot 脚本错误、引擎错误和泄漏警告纳入失败条件。
- 新增共享 ConfigurationValidator；建筑全部等级、敌人、复制镜和关卡倒影提供完整配置校验，LevelResource 同步校验波次使用的敌人；ResourceManager 拒绝 NaN/Infinity 交易和产出。
- LevelLoader 在 TileManager 预检后仍拒绝装配时恢复旧网格；MirrorManager 重配会解除旧建筑攻击信号；LevelReflectionSurface 可安全重连依赖并实时响应定义变化。
- GridManager 通过注入只读高度查询执行最近地块顶面拾取，四边形/六边形斜视角不再穿过高地误选 Y=0 后方格；未改变玩法数值和正式资源内容。

## Mirror / Visual · 修复拉远视角后复制镜失去反射 — 2026-07-21
**模块**：Mirror / FX / Tests。

- 复制镜改用屏幕对齐平面反射：虚拟相机严格镜像主相机姿态与投影，反射纹理匹配主视口宽高比并由 Shader 通过 `SCREEN_UV` 采样，移除远距离会退化为清屏色的极端离轴视锥；`Far` 现在只承担正常远裁剪职责。
- 新增 `reflection_two_sided_visual`，默认让单个反射 Quad 根据主相机所在侧切换实体表面；镜面外推量参数化为 `reflection_surface_offset_ratio = 0.78`，镜体背板从反射相机剔除，消除远处深度遮挡和蓝色自遮挡，不改变玩法生效侧。
- 镜面刷新判定由单中心点扩展为中心与四角矩形采样；CopyMirror 回归扩展至 68 项，覆盖主相机姿态镜像、屏幕宽高比、反射层隔离、远距离反侧观察与玩法侧不变，并通过 Vulkan 实际画面对照。

## FX · 扩大倒影面高度偏移范围 — 2026-07-21
**模块**：FX / Tests。

- `vertical_offset` 的 Inspector 上限由 `2.0` 提高到 `20.0` 世界单位，步进仍为 `0.01`，默认值仍为 `0.18`，不会改变既有关卡表现。
- LevelReflection 回归增加导出范围检查，防止后续资源脚本意外收窄高度偏移能力。

## FX · 关卡下方实时水面倒影 — 2026-07-20
**模块**：FX / Main / Tests。

- 新增独立 `LevelReflectionSurface`：按四边形/六边形关卡包围盒自动生成水平反射面，共享当前 `World3D`，主相机位置关于水面实时对称并用离轴视锥渲染完整关卡，不使用固定投影。
- 新增 `LevelReflection.tres` 参数入口，提供水面高度、边缘范围、反射强度/亮度/柔化、Fresnel、雨滴波纹与纹理分辨率/刷新间隔；默认每帧 768px 最长边刷新。
- 反射面使用独立可见层且从全部反射相机剔除，不创建碰撞、占位或玩法注册；新增 26 项 Godot 4.7.1 回归，覆盖 HEX/SQUARE 尺寸、镜像视点、共享世界、递归隔离和零碰撞。

## Mirror / Path Editor · 投影稳定化、内容快照与四边形连续路径 — 2026-07-20
**模块**：Mirror / Tile / Path / Godot 关卡编辑器 / Tests。

- 同格透明虚影改为稳定渲染优先级且不写深度；重建时先隐藏已退役投影再延迟释放，消除新旧几何同帧叠加闪烁。
- 复制镜从完整地块快照改为地块内容快照：只复制建筑、石头、尖刺、空洞和既有虚影，不复制地表基底颜色/几何，元素仍保持严格镜轴对称。
- 路径页支持按住左键连续逐格记录；四边形同行/同列的遗漏中间格会自动补齐，旧关卡加载时自动迁移并提示保存。镜子回归扩展至 60 项，路径/出生点回归扩展至 30 项。

## Tile / Path / Editor · 路径基底色与地块内容分层 — 2026-07-20
**模块**：Tile / Path / Level / Mirror / Godot 关卡编辑器 / Tests。

- `LevelResource` 新增 `path_terrain_color`，默认 `#FFB93B`；`TileRenderer` 与编辑器画布从全部手工路径构建格并集，任一路径经过的格都使用该基底色。
- 建筑占位和石头/尖刺/空洞不再改写基底色；`SurfaceKind.ELEMENT` 保留路径或高度基底，仅用 `visual_color` / `visual_scene` 显示独立内容。
- 镜像地块快照复用同一基底色解析；新增 18 项 Godot 4.7.1 回归，覆盖路径重叠、三档高度元素、建筑占位、镜像快照和编辑器一致性。

## CameraInput / Editor · XC 俯仰与更大滚轮倍率 — 2026-07-20
**模块**：CameraInput / Main / Godot 关卡编辑器 / Tests。

- 删除 `cam_zoom_in/out` 键盘缩放动作，新增 `cam_pitch_lower/raise`：X 将俯仰降至最低 18°，C 将俯仰提高至最高 82°，默认 50°，速度 55°/秒；鼠标滚轮成为唯一缩放输入。
- 运行时相机最近距离由 5.0 降至 2.0，关卡编辑器最大画布倍率由 180 提高至 300；编辑器同步改为 XC 调俯仰、滚轮缩放，重置视角会恢复默认俯仰。
- 新增 CameraInput 回归，覆盖动作替换、俯仰限位、俯仰不改变缩放、滚轮最大倍率、gimbal 距离和编辑器参数。

## Mirror / Visual · 提高复制镜默认高度 — 2026-07-20
**模块**：Mirror / Tests。

- `mirror_height_ratio` 默认值由 0.72 格提高到 1.20 格；镜框、生效面、离轴反射视锥、顶部生效侧标识及操作按钮锚点统一使用该参数，不改变镜子玩法、造价或占位规则。
- 复制镜回归扩展至 55 项，覆盖默认高度与网格尺寸的参数化关系。

## Mirror / Visual · 实时生效面与严格真实虚像 — 2026-07-20
**模块**：Mirror / Building / Tile / UI / Main / Tests。

- 复制镜生效面新增共享 `World3D` 的实时平面反射：反射相机关于镜轴生成虚拟视点，以镜面矩形构造离轴视锥；背面保持深色镜背，镜面层从反射相机剔除以阻断无限递归。
- `MirrorManager` 仅刷新主相机视锥内且朝向相机的正面，并参数化分辨率、预览分辨率、刷新间隔及每帧上限；镜面显示完整关卡世界而非单独建筑贴图。
- 移除虚像按 `copy_kind` 生成的圆柱/方块/圆盘替代体和垂直错层。建筑复用当前真实视觉快照；尖刺、空洞和岩石复用 `TileRenderer` 的完整地表、侧壁、颜色和元素几何，再按完整镜链做严格仿射反射。
- 虚像默认不改变位置或尺寸；透明度提高并增加保留源主色的强调色、Fresnel 轮廓、同心标识和悬停标签/HUD，重叠内容可以区分但几何仍严格重合。
- 复制镜回归由 42 项扩展至 54 项，新增完整地块快照、递归快照、无错层精确变换、单正面翻转、共享世界反射面和离轴视锥验证；Godot 4.7.1 主场景无解析、着色器或运行时错误。

## M5 · 最近整格复制镜与非占位虚像 — 2026-07-20
**模块**：Mirror / Grid / Building / Combat / Tile / Path / Resource / UI / Main / Tests。

- 新增可放置、翻面、选择和删除的复制镜边建筑；复制镜与边屏障共享 `EdgeOccupancyRegistry`，统一执行内部边、双侧地块权限、邻近敌人、资源和镜子上限校验。
- 复制规则收敛为“沿生效侧法线寻找最近非空格并复制整格内容”。格建筑、尖刺、空洞、岩石和已有虚像进入统一 payload；镜子/其它边建筑/敌人不复制，镜链默认 4 层并用谱系阻断循环。
- 虚像使用独立覆盖层，默认不占 TileCellData 且允许同格叠加/落在不可建造格；严格占位由配置开关控制。箭塔/激光塔同步原件攻击且不索敌，屏障共享原件耐久，地块效果接入既有伤害、死亡、导航与空中适用性查询。
- M3DebugPanel 新增复制镜模式和镜子计数；放置预览显示生效侧、最近源格、目标格、整格类型与青蓝虚像，MirrorActionPanel 提供悬浮删除/翻面。
- 新增 42 项 Godot 4.7.1 回归断言，覆盖 HEX/SQUARE 镜像格对、预览、整格复制、占位开关、同步投射物/激光、屏障承伤、三类地块效果、递归镜链和外部删除释放。

## Unit / Tile / Building · 飞行敌人与空中效果开关 — 2026-07-20
**模块**：Unit / Combat / Tile / Path / Building / Tests。

- EnemyDefinition 新增 `is_airborne` 和 `flight_height`，EnemyUnit 将分类与离地高度应用到手工路径；新增可被波次编辑器自动发现的 `Flyer.tres` 飞行侦察兵。
- TileEffect 与 BuildingLevelStats 新增 `affects_airborne`；尖刺/空洞分发、岩石阻挡与换路、箭塔索敌、激光贯穿、地块/边屏障均通过统一目标分类过滤。新参数默认 true，不改写旧资源玩法。
- 新增 26 项 Godot 4.7 回归断言，覆盖飞行高度、地块伤害/死亡/导航、单体/激光攻击、块/边屏障阻挡与反伤的开关双态行为。

## Path / Tile · 动态换路只排除导航阻碍 — 2026-07-20
**模块**：Path / Tile / Level / Unit / Tests。

- 按最终玩法规则收敛候选判定：只有 `enemy_traversal=BLOCKED` 的导航障碍会使手工路径后缀不可用；空洞与尖刺均可被选中，敌人进格后再正常结算死亡/伤害。
- 移除会与唯一规则冲突的 `TileEffect.safe_for_reroute` 参数及旧资源字段，`can_use_for_reroute()` 现在只是“未阻断导航”的稳定查询。
- `M4DemoLevel` 的空洞恢复到路径 3 后缀 `(1, 0, -1)`；换路回归扩展至 50 项断言，覆盖“最短路径含空洞仍可选”及敌人进入后正常掉落死亡。

## Level / Path · 修正 M4 换路示例与运行时验收 — 2026-07-20
**模块**：Level / Tile / Path / Unit / Tests。

- `M4DemoLevel` 原路径 3 后缀经过空洞 `(1, 0, -1)`，因此即使在石头前与主路相交/相邻也会按规则被整条淘汰；空洞已移到非候选路径格 `(0, -1, 1)`，保留“换路不主动走空洞”的玩法契约。
- 换路回归扩展至 48 项断言；运行时现在明确验证 `rerouted` 仅发射一次、目标为最短相邻路径且换路后继续移动，不再把“原地等待”误判为换路成功。

## Tile Editor · 修复画布热重载后接口失效 — 2026-07-20
**模块**：Tile / Godot 编辑器工具 / Tests。

- 编辑器画布不再直接依赖运行时 `TileDefinition.VisualKind` 全局枚举，避免 Godot 脚本热重载时因全局类注册顺序导致画布脚本仅部分加载。
- `TileDefinition` / `TileCellData` 新增稳定的 `get_visual_tag()` 展示契约；尖刺、空洞、大石头继续使用原颜色与灰盒图形，不改玩法和数值。
- 编辑器回归扩展至 24 项断言，显式验证画布在 tool 脚本加载后提供 `set_level` 与 `reset_view`。

## Tile / Path · 关卡地块元素与手工路径换路 — 2026-07-19
**模块**：Tile / Level / Path / Unit / Combat / Building / Wave / Main / Godot 编辑器工具 / Tests。

- 新增数据驱动 `TileDefinition` / `TileEffect`：尖刺按占格时间造成可配 DPS，空洞进格即死并可配掉落倍率，大石头作为永久不可攻击导航阻碍；三者默认禁止块建筑、允许边建筑。
- 关卡编辑器改为自动发现 `resources/tiles/*.tres`，新增三种连续画笔、Inspector 类型选择与可辨识灰盒；类型涂刷保留高度，高度刷仍不改类型。
- 新增 `PathRoutePlanner`：敌人仅在大石头前一格触发，从相交/相邻的其他手工路径选择剩余边数最短且不含石头/空洞的后缀；无路原地等待，支持六边形/正方形，不修改初始路径资源。
- EnemyUnit 增加逐格进入与按移动时长的停留分发，高速移动不会跳过空洞；建筑屏障仍停步攻击，不参与地形换路。
- 新增 45 项 Godot 4.7 回归断言，覆盖旧地块兼容、共享边双侧权限、元素空渲染批次、HEX/SQUARE 最短路、无路等待、尖刺帧率无关、高速空洞与资源不变性。

## Path / Level Editor · 路径与出生点 1:1 命名 — 2026-07-19
**模块**：Path / Level / Godot 编辑器工具 / Tests。

- 新建路径记录首格时，会以 `path_N -> spawn_path_N`、“路径 N -> 路径 N 出生点”的规则建立 1:1 出生点；路径改名、改 ID 或改起点时会同步出生点。
- 路径页和波次页统一显示 `display_name [ID]`，不再将子资源所属的关卡 `.tres` 文件名显示为可选路径。
- 波次仅选择路径，出生点自动绑定且只读；旧关卡可通过现有波次引用或唯一起点格继续识别对应关系。
- 新增 22 项 Godot 4.7 回归断言，覆盖命名派生、旧数据唯一/歧义查找、子资源标签、连续改 ID、新建 1:1 及波次切换。

## Building · 边障任意内部边放置与默认双向阻挡 — 2026-07-19
**模块**：Building / Grid / Path / Unit / UI / Tests。

- 边障取消“必须属于敌人路径”和出生点/据点相邻边限制，现在可放在任意两个有效地块之间的共享边；地图外圈无邻格边、重复占位边和敌人占据边仍拒绝。
- `BuildingDefinition.blocks_both_directions` 默认开启，路径正反穿越同一物理边均会被阻挡；关闭后保留原有单向变种能力。双向灰盒在边两侧显示标记，HUD 使用 `↔`。
- Definition 按 `BARRIER/EDGE_BARRIER` 身份稳定解析放置面，避免 Godot 重存 `.tres` 省略字段后改变建筑类型。
- Godot 4.7 回归测试扩展至 58 项，覆盖六边形/正方形非路径边放置、外圈拒绝、默认双向和可选单向规则。

## Level / Building / Unit · 关卡几何标签与有向路径边屏障 — 2026-07-19
**模块**：Level / Grid / Path / Building / Unit / Combat / UI / Godot 编辑器工具 / Tests。

- `grid_shape` 现在派生稳定的 `hex/square` 关卡标签；HEX 普通建筑/边建筑为 6/6 向，SQUARE 为 8/4 向，关卡编辑器与运行时 HUD 均显示标签。
- 新增三级 `EdgeBarrier.tres` 与 `PATH_EDGE` 放置规则：只可从路径前进格一侧选中真实路径边，按边中点对齐，物理边唯一占位；删除、升级、退款、耐久、脱战回血和反伤复用现有建筑事务。
- 边屏障只阻挡精确匹配 `from_cell -> to_cell` 的近战/远程敌人；其他路径与反向穿越同一物理边不受影响。远程敌人仍按配置射程停步发射。
- EnemyUnit 改为求折线路径与攻击范围圆的首次交点，修复弓箭手在弯道或浮点边界停住却不射箭；攻击失败不再错误进入冷却。
- 新增 Godot 4.7 回归测试，50 项断言覆盖双网格、方向隔离、物理边占位、外部释放、完整屏障生命周期、近战攻击和弓箭手发射。

## Combat 修复 · 目标清理信号重入越界 — 2026-07-19
**模块**：Combat / UI / Tests。

- CombatManager 清理失效目标时改为遍历稳定快照，避免 `unregister_target -> target_removed -> M3DebugPanel.get_targets -> _cleanup_targets` 同步重入修改活动数组并造成索引越界。
- 新增双目标同时离树、监听者在 `target_removed` 中同步查询的回归测试；注册、回调和候选均只清理一次，不改变战斗规则或数值。

## 工程 · 健壮性基线 — 2026-07-19
**模块**：Level / Tile / Grid / Path / Wave / Combat / Building / Godot 编辑器工具 / Tests。

- LevelResource 新增运行时完整预检；LevelLoader 在改变 Grid/Tile 前拒绝非法资源，加载失败保留当前关卡。TileManager 将序列化 TileCellData 克隆成独立运行时状态，多个运行实例不再共享占用、清障或高度修改。
- GridRenderer 与 PathManager 对空几何不再结束零顶点 ImmediateMesh；WaveManager 新增 `CONFIG_ERROR`，依赖或生成失败不会消耗出怪计数、触发假胜利或误发波次开始事件。
- CombatManager 与 BuildingManager 的注册/移除改为幂等生命周期事务；目标或建筑被外部释放时同步清理信号、字典、地块占位、建筑上限和产出。
- 关卡编辑器增加未保存提示、网格重建确认、网格重建撤销/重做、非法关卡保存二次确认，以及敌人资源空引用过滤和稳定排序。
- 新增可由 Godot 4.7.1 直接运行的持久化健壮性测试，37 项断言覆盖上述边界及 M4DemoLevel 的校验、弓箭手和全局延迟契约；本批不改变玩法和数值。

## Building / Unit · 路径屏障与敌人攻击 — 2026-07-19
**模块**：Building / Tile / Path / Unit / AI / Combat / Wave / UI / Main。

- 新增三级屏障 BuildingDefinition：每级独立配置耐久、脱战延迟、回血速度和反伤比例；升级保留已有损伤，战斗摧毁无退款并释放路径，主动删除仍按等级退款。
- BuildingManager 缓存关卡路径与保护格；普通塔禁止占路，屏障可占可建造或灰色不可建造路径路面，但拒绝未清障格、出生点、据点、已有占用和敌人当前所在格。
- EnemyDefinition 新增攻击伤害、攻速、射程和敌方投射物参数；所有 EnemyUnit 在屏障进入射程后停止移动，屏障消失后继续原固定路径。
- 新增 EnemyAttackStrategy、EnemyProjectile 和 Archer.tres；M4DemoLevel 第二波第 10 秒加入弓箭手组，用真实飞行投射物测试远程攻击。
- 灰盒建筑面板新增“屏障”模式，HUD 显示耐久、脱战回血与反伤；Godot 4.7 自动验收覆盖路径放置规则、三级增血、近战/远程停步、投射物命中、反伤、回血和摧毁释放。

## M4 · 关卡编辑显示、路径防误改与全局波次时间轴 — 2026-07-19
**模块**：Level / Tile / Path / Wave / UI / Godot 编辑器工具。

- 关卡编辑器现在会显示未序列化的默认地块，并在修改高度/类型时按需写入 TileCellData，修复 `M4DemoLevel` 在编辑器中地形缺失但运行时正常的问题。
- 加载关卡默认关闭路径记录；路径画布实时拒绝非相邻落点，M4 校验会报告具体断点坐标并检查路径终点等于据点，避免查看关卡时误写路径。
- 波次规则改为只手动点击一次“开始第一波”；全部出怪组的 `start_delay` 统一解释为相对首次点击的全局延迟，后续波次自动开始且允许跨波重叠。
- EnemyUnit 在加入场景树前使用共享的 Main 局部坐标设置出生位置，消除 Godot 4.7 的 `!is_inside_tree()` 全局变换错误，同时保留定义参数先于灰盒外观初始化。
- Godot 4.7 自动验收覆盖稀疏地块显示/实体化、路径无误改、原始 M4Demo 校验，以及第二波无需再次点击在 8 秒自动开始。

## M4 · 单位、手动路径、波次与固定路径 AI — 2026-07-17
**模块**：Level / Path / Unit / Wave / AI / Combat / Resource / UI / Godot 编辑器工具。

- LevelResource 新增据点、路径、出生点、波次、准备期和自动开波字段，并提供编辑器与运行时共用的 M4 配置校验；新增 M4DemoLevel 两波示例资源。
- 新增 EnemyDefinition、EnemyUnit、BaseCore、PathManager、WaveManager 和 WaveStatusPanel：敌人沿带高度的手动路径行进，到据点扣血；击杀按敌人定义掉落资源，抵达据点不掉落；所有波次清场判胜、据点归零判负。
- 原地块编辑器升级为关卡编辑器，保留地块页并新增路径和波次页；路径、出生点、据点和出怪组统一保存到同一份 LevelResource。
- Godot 4.7 真机验收：M4DemoLevel 路径解析与配置校验通过；完整两波清场后进入胜利并获得 69 资源；敌人抵达据点会扣血且据点格不可放置建筑。

## M3 优化 · 建筑悬浮操作与逐级退款 — 2026-07-17
**模块**：Building / Resource / UI / Main。

- 选择模式点击有建筑地块后，在建筑上方显示删除、升级、旋转三个悬浮按钮；空地不显示，满级仅升级置灰，旋转沿用既有离散朝向且免费。
- BuildingLevelStats 新增逐级 `refund_amount`；删除当前建筑按其当前等级精确返还资源，并原子释放占格、建筑数量和当前建筑产出。
- 默认退款约为累计建造与升级投入的 50%：箭塔 1/2/3 级为 38/88/163，激光塔为 60/140/250；所有数值可在塔资源 Levels 的 Economy 分组中直接修改。

## M3 优化 · 投射物、三级参数、放置预览与资源拆分 — 2026-07-17
**模块**：Building / Combat / Resource / Level / UI / CameraInput / Main。

- 箭塔从发射即瞬伤改为标准投射物：索敌范围与攻击范围独立，投射物按逐级速度飞行并保持短直线尺寸，只在命中存活目标时结算伤害。
- 建筑改为初始 1 级、上限 3 级；每级独立配置费用、产出、全部战斗/投射物参数、等级伤害因子和可选美术场景，未配美术时用逐级颜色灰盒区分。
- 建造模式新增可旋转的半透明塔虚影；不可放置或非建造模式显示地块、障碍与占位建筑信息。M3 面板新增升级按钮与总每秒产出显示。
- 资源模型拆分为关卡基础产出与建筑逐级产出；敌人死亡掉落仅保留 `grant_enemy_drop(amount)` 接口，正式数值和死亡连接留到 M4。
- Godot 4.7 真机验收：三级参数切换、费用与产出同步、满级无扣费、索敌/射程分离、投射物飞行期间不扣血、命中结算、有效/无效格预览均通过。

## M3 · 建筑、索敌战斗与资源经济 — 2026-07-17
**模块**：Building / Combat / Resource / Tile / Level / UI / CameraInput / Main。

- 新增数据驱动的箭塔与激光塔、BuildingManager 放置事务和 TileManager 运行时占用接口；资源、建筑上限与不可建造格会阻止放置，R 在 HEX/SQUARE 中按世界固定 6/8 档旋转。
- 新增 ITargetingStrategy / IAttackStrategy、七种索敌优先级、统一伤害公式、CombatTarget/CombatManager；箭塔按冷却瞬伤，激光固定方向穿透全部目标并按 delta 持续伤害，建筑不挡光。
- 新增 ResourceManager：关卡驱动单资源、建筑/镜子 cap，以及击杀、占领格、生产建筑、时间增长、清障五种独立产出开关；新增 M3 灰盒建造/靶标面板。
- Godot 4.7 真机验收：箭塔瞬伤/击杀掉落、激光双目标持续伤害、上限原子阻止、五类产出总额、HEX 6 向与 SQUARE 8 向及镜头无关性均通过；修复已释放锁定目标的类型句柄后无新增运行时错误。

## Level · 运行时调试选关与正式加载接口 — 2026-07-17
**模块**：Level / UI / Main / Grid / Tile。

- 新增 LevelLoader 作为运行时唯一关卡装配入口：支持加载初始 LevelResource、按 `res://` 路径加载 `.tres`、统一重配 Grid 与 Tile，并广播成功/失败信号。
- 新增可关闭的 LevelDebugPanel：运行时右上角显示当前关卡，可打开资源选择器切换自定义关卡；后续正式选关 UI 直接复用 LevelLoader 公共 API，不依赖调试面板。
- Main 改为依赖注入与初始加载编排，切关后清空旧格/边选择；真机验证 CustomLevel 切换后 Grid 参数、Tile 数量和面板状态与资源一致。

## Tile 修复 · 不可建造路面运行时灰色 — 2026-07-17
**模块**：TileRenderer。

- 运行时不可建造路面使用可配置的 `blocked_color` 灰色覆盖高度色；可建造地块与可破坏障碍地块继续使用低绿、中黄、高红的高度分层颜色。

## Tile · 高度分层运行时着色与高度刷 — 2026-07-17
**模块**：Tile / Level / Godot 编辑器工具。

- LevelResource 的下/中/上高度色默认调整为绿/黄/红，并新增统一的高度色插值方法；TileRenderer 通过 TileManager 读取该颜色，以顶点色批量渲染运行时地形与编辑器预览一致。
- 地块编辑器新增独立高度刷：按关卡高度档选择目标值并左键连续涂刷，只更新 TileCellData 的 `height_level`，不修改地块类型、障碍或清障状态。

## Tile Editor 修复 · 关卡资源 placeholder — 2026-07-17
**模块**：Tile / Level / Godot 编辑器工具。

- 为 LevelResource、TileCellData 与 TilePreset 添加 `@tool`；加载关卡改用 `CACHE_MODE_REPLACE_DEEP` 刷新资源树。编辑器现在可执行加载关卡中的 `get_tile()`、地块状态判断和预制构建，不再因 placeholder Resource 重复报错。

## Tile Editor · 连续画笔与斜俯视预览 — 2026-07-17
**模块**：Tile / Level / Godot 编辑器工具。

- 地块编辑器调色板可点击选择画笔，画布支持左键连续涂刷并对鼠标路径采样，保留原有拖放单格覆盖；重复经过同一格不会重复写入布局。
- LevelResource 新增持久化的下/中/上高度色；编辑画布按高度插值上色、绘制台阶墙面，并以障碍/路面标记保留玩法类型辨识。
- 编辑画布改为可观察高度差的斜俯视投影：获得焦点后 WASD 平移、QE 旋转、XC 或滚轮缩放；工具栏可一键复位视角。

## Tile 修复 · 空批次网格重建 — 2026-07-17
**模块**：TileRenderer。

- 空地块类型批次或清空全部障碍后，TileRenderer 不再对零顶点 `ImmediateMesh` 调用 `surface_end()`；对应实例改为 `mesh = null`，消除 Godot 的“surface can't be created”错误。

## M2 · 地块系统与地块编辑器 — 2026-07-17
**模块**：Tile / Level / Grid / Main / Godot 编辑器工具。

- 新增 `TileCellData`、`TilePreset`、`TileManager` 与 `TileRenderer`：支持可建造、可破坏障碍、不可建造路面三类地块，离散高度、运行时占用预留、清障转可建造和地形灰盒渲染。
- 新增 `LevelResource` 与 `M2DemoLevel.tres`：关卡资源保存网格、高度和按 `cell` 去重的布局；Main 先通过 GridManager 应用资源配置，再加载 TileManager。
- 新增并默认启用 `Mirror Tile Editor` 主屏插件：三份 `.tres` 调色板可拖入六边形/正方形画布，支持单格类型/高度/清障、关卡新建、加载与保存。
- GridManager 新增 `neighbor_across_edge()` 和 `apply_configuration()`，供台阶崖壁计算与 LevelResource 装配使用。
- Godot MCP 验收：M2 场景真机加载 127 格地块、道路/障碍/高度有效；调用清障后 `is_destructible=false`、`can_place=true`；编辑器验证调色板覆盖同格不产生重复记录、改单格/清障有效，写出的 `.tres` 可回读。

## 工程：Git 版本管理与自动提交规范 — 2026-07-17
**模块**：工程协作。

- 初始化 Git 仓库并关联 `origin` 至 GitHub 的 `granjzil-art/MirrorDefender`，本地 `main` 跟踪远端 `main`。
- CONTRIBUTING 新增版本管理硬规范：每个已验收功能或修复必须连同实现文档与变更日志自动提交、推送；明确提交格式、冲突处理和禁止提交的本地状态/压缩原包。

## M1 真机修复：网格渲染器依赖注入 — 2026-07-17
**模块**：Grid / Main 场景装配。

- 真机截图定位 `GridRenderer.grid` 在运行时为 `null`：场景文件中的 `NodePath` 未解析为自定义类型导出引用，导致网格线框从未构建。
- 新增公开 `GridRenderer.set_grid(grid: GridManager)`，由 `Main._ready()` 在子节点就绪后注入；方法负责订阅 `grid_changed` 并立即重建线框。
- Godot MCP 真机验收：六边形初始网格可见；注入 `toggle_grid_shape` 后正方形网格可见；`get_debug_output` 无 Parser Error 和运行时错误。

## M1 修正：网格边映射与拾取验证 — 2026-07-16
**模块**：Grid / CameraInput / Main 场景装配。

- 修正六边形与正方形的角点起始顺序，使 `edge_index`、边外法线与 `neighbor_across_edge()` 的方向严格一致；为后续镜子生效侧、跨边取格和镜像几何建立正确基础。
- 由 Main 通过 `GridRenderer.set_grid()` 完成网格注入，方法负责订阅 `GridManager.grid_changed` 和首次重建；移除 Main 对下划线私有方法的跨模块调用。
- 左键 `place_select` 现在锁定当前格/边并在 HUD 显示，补齐 M1 的点击拾取验收入口。
- 同步更新 Grid、CameraInput 实现文档；修正 CONTRIBUTING 中与设计基线冲突的“镜像不可再被镜像”旧规则。

## BUG 修复：4.7 GDScript 类型推断报错（M1 首次真机运行）— 2026-07-16
**背景**：通过 Godot MCP 首次在真引擎（4.7.1 stable）运行 `Main.tscn`，捕获到之前纯静态自检无法发现的编译期 Parser Error。

**根因（系统性问题，非单点）**：Godot 4 的一批全局数学函数（`round`/`floor`/`ceil`/`abs`/`min`/`max`/`clamp`/`sign`/`snapped` 等）返回类型为 `Variant`；4.7 工程默认把 `INFERENCE_ON_VARIANT` 警告**当成 error**。凡 `var x := round(...)` 或把其结果赋给带类型变量，都会中断脚本加载。此外从 `Dictionary` 用 `.key` 取值也是 `Variant`，`:=` 同样无法推断。

**修复（全项目 8+ 处，统一改为带类型专用版）**：
- `round→roundf/roundi`、`abs→absf/absi`、`min→mini/minf`、`max→maxi/maxf`。
- `GridManager.gd`：`pick_edge`/`pick_cell` 里从 `Dictionary` 取 `g.pos` 先落成带类型局部变量 `var hit_pos: Vector3`；`var d := ...` → `var d: float`；`cell_size = max(...)` → `maxf`。
- `HexGridShape.gd`：`_cube_round` 全改 `roundf/absf`；`distance` 用 `absi`；`enumerate_cells` 用 `maxi/mini`。
- `SquareGridShape.gd`：`world_to_cell` 用 `roundi`；`distance` 用 `absi`。
- `IGridShape.gd`：`_quantize_key` 用 `roundi`。

**验证**：MCP 真机重跑 `Main.tscn` → 无 Parser Error、无运行时错误、`errors: []`，引擎正常启动。

**教训沉淀**：本机无 Godot 可执行文件时，静态自检查不出类型系统级错误。已把 Godot MCP「run→get_debug_output」纳入每里程碑收尾的必做验证；并在 CONTRIBUTING 增加「返回 Variant 的全局函数一律用带类型专用版」硬规范。

## 引擎版本迁移：4.3 → 4.7 — 2026-07-16
**背景**：用户实际使用 Godot 4.7，工程需按 4.7 规范书写。已核对官方 4.3→4.4→4.5→4.6→4.7 全部升级指南。

**核对结论**：M1 用到的所有 GDScript API（`ImmediateMesh`/`StandardMaterial3D`/`Camera3D.project_ray_*`/`Input.get_action_strength`/`Vector3i`/信号/`@export`/`class_name`）在 4.7 **零破坏性变更**（升级指南均标 GDScript ✔️）。

**实际改动**
- `scenes/Main.tscn`：去掉 `load_steps=`（4.6 起该属性 deprecated，应被忽略）。`ext_resource` 保留 `path=` 引用（4.7 合法；`uid` 为可选辅助，交由引擎首次打开自动补齐）。
- `project.godot`：显式声明 `rendering/renderer/rendering_method="forward_plus"`，与 `config/features` 一致。未显式写 `rendering_device/driver.windows` → 沿用引擎内置默认 `vulkan`（比新建模板的 D3D12 在多数 Windows 机更稳）。

**主动规避的 4.7 隐患（复核通过）**
- 4.7 GDScript 收紧：重写有类型返回的父方法必须显式 `return` → 全部 7 个脚本扫描通过，`IGridShape` 虚方法及子类 override 均有显式 return。
- 4.7 输入设备 ID 变更（mouse/keyboard 从 0 改为常量）→ 本项目按钮判断用 `MOUSE_BUTTON_WHEEL_*` 类型与 InputMap action，不依赖 device id，安全。

**关于 `.uid` 文件**：未手动生成（手写 `uid://` 有格式冲突风险）。Godot 4.7 首次打开工程会自动为每个脚本生成 `.uid`，并可用 `项目 > 工具 > 升级项目文件` 一键统一格式。

**后续规范**：所有新代码/场景一律按 Godot 4.7 书写。

## M1 · 网格与相机地基 — 2026-07-16
**范围**：Grid 抽象层（六边形 flat-top + 正方形）、边(Edge)一等公民、拾取、gimbal 相机、网格线框与格/边高亮、主场景装配。

**新增文件**
- `project.godot`（含 InputMap：WASD/QE/XC/R/T/左键/右键）、`icon.svg`、`.gitignore`
- `scripts/grid/IGridShape.gd` — 网格形状接口（可拓展基类）
- `scripts/grid/HexGridShape.gd` — 六边形（立方体坐标，flat-top）
- `scripts/grid/SquareGridShape.gd` — 正方形（行列坐标）
- `scripts/grid/GridManager.gd` — 唯一对外入口 + 拾取（pick_cell/pick_edge）
- `scripts/grid/GridRenderer.gd` — 线框 + 格/边高亮（点线面色块）
- `scripts/camera/CameraController.gd` — gimbal 斜俯视相机
- `scripts/Main.gd` + `scenes/Main.tscn` — M1 验收入口

**对齐的设计文档**：`systems/Grid_网格系统.md`、`systems/CameraInput_相机与输入.md`（函数索引已补）。

**验收对照（06 文档 §M1）**
- ✅ 能生成两种网格地图（T 键运行时切换 HEX/SQUARE）
- ✅ 相机可自由观察（WASD 平移 / QE 旋转 / XC+滚轮 缩放，斜俯视）
- ✅ 点击可拾取到具体格子与具体边（HUD 实时显示 cell 坐标、edge_index、canonical_edge_id）

**关键实现决策**
- Godot 4 无 interface → 用 `class_name` 基类 + 虚方法约定实现「形状走接口」。
- 拾取用「射线打 y=0 平面 + world_to_cell 数学反算」，不给每格建碰撞体（性能 + 可拓展）。
- `canonical_edge_id` = 边两端点世界坐标量化(1e-3)后排序拼接 → 相邻两格共享边得同一键，为 M5/M6「一条边至多一面镜」奠基。

**未做/留待后续**：地块高度（M2）、镜子挂载（M5/M6）。当前所有格 y=0。
