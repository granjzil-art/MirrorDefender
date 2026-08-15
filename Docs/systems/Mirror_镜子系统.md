# 镜子系统 · Mirror（核心）

> 模块职责：管理复制镜、反射镜两类边建筑的放置、朝向、镜像几何与生效逻辑。
> 关键架构、函数索引和参数必须与实现同步维护。
> 状态：复制镜、镜面/虚像表现、投射物反射、逐步传播的持续激光与脉冲镭射分段反射均已实现并通过 Godot 4.7.1 回归。

---

## 一、通用边建筑规则

1. 镜子严格贴合地块边：六边形有 6 种边方向，四边形有 4 种边方向。
2. 一条规范化物理边只能存在一个实体边建筑。复制镜、反射镜、边屏障共享同一边占用表。
3. 只允许放在两个有效地块之间，且两侧地块都必须允许放置边建筑。
4. 放置时需要通过建筑附近敌人、对应种类独立上限与当前放置模式校验。默认金币模式扣除该 Definition 的 `placement_cost`；可选冷却模式改用对应种类的可用数量。
5. 镜子有正反两个生效面。`R` 只在两侧之间翻面，不改变所在物理边。
6. 镜面所在边的直线是所有镜像计算的对称轴；点、方向和攻击线均使用同一套线反射公式。
7. 镜子可被选中、翻面、升级和出售；两种镜子均为三级。升级改变其复制/反射攻击的伤害倍率与额外穿透，但镜子仍不参与耐久、主动攻击或路径阻挡。
8. 镜子本身永远不可复制，任何其他边建筑也不属于 M5 的整格复制内容。
9. 放置复制镜前必须将候选镜加入当前稳定迭代，检查它导致的全部直接/递归障碍投影；任一受影响出生点失去到原目标据点的最后可达路线时拒绝放置。
10. 正式默认 `placement_cooldown_enabled=false`：两种实体镜各自消耗 Definition 配置的金币费用，放置后无冷却；升级继续消耗金币，主动出售返还该运行时镜子实际累计支付的全部资源。开启兼容开关后才使用旧 `placement_cooldown_seconds` 和独立可用数量，并忽略放置金币费用。
11. `MirrorPlacementData` 可把实体镜子的种类、物理边、生效侧与当前等级保存为开局陈列；旧数据默认复制镜一级，数组顺序是重载时的镜链装配顺序。虚像始终由实体镜重新推导，禁止持久化。

### 1.1 放置经济与可选冷却

- 默认金币模式下，卡槽底部显示 Definition 中的实时费用；余额不足或该种类达到独立 cap 时只禁用该卡。放置成功才扣款，事务后边占用意外失败会全额回滚。
- `MainController.mirror_placement_cooldown_enabled=true` 时启用保留的冷却实现：开局加载初始陈列后，复制镜和反射镜各有 1 枚可用数量，并立即开始下一枚的累计周期；初始陈列不消耗数量。
- 冷却模式的波次实际行动按 1.0 倍回复；首波前和波间按 `mirror_preparation_cooldown_time_scale` 回复。终局、无波次或暂停时不推进，0.1x/2x 速度自然影响回复。
- 冷却模式可用数量为 0 时，卡槽显示下一枚的扫描；有库存时显示 `×数量`。某种镜子达到自己 cap 时只禁用该卡，另一种和后台库存累计不受影响。

### 1.2 三级升级、说明与出售

- `MirrorDefinition.upgrade_costs` 保存 1→2、2→3 两笔费用；两类默认均为 50。`level_damage_multipliers` 与 `level_penetration_bonuses` 分别按 1–3 级提供攻击修正。
- 复制镜把自身等级修正累计进 `MirrorCopyPayload`：多面复制镜的伤害倍率相乘、额外穿透相加，并作用于复制投射物、持续激光和脉冲镭射。反射镜在每次有效反射时把当前级修正加入投射物/激光路径。
- 每个实体镜只记录本局真实支付的建造和升级资源。金币模式放置会登记基础费用；冷却模式和关卡初始陈列的免费放置不登记基础费用；任何实际支付的升级费用都会登记。出售全额返还该累计值，避免免费镜产生金币套利；冷却模式另返还对应种类库存。
- `inspection_display.function_description` 基础描述与 `MirrorDefinition.upgrade_description` 升级描述是镜子卡悬停和实体“说明”按钮的唯一文本事实源。两行分别显示绿色“基础描述：”与黄色“升级：”标题，正文默认白色；`upgrade_description` 默认留空，不迁移旧等级文本。两字段均支持 `[color]`、`[highlight]`、`[b]` 白名单标记。悬停框和选中说明页均按实际换行自适应高度；选中实体镜时，`MirrorActionPanel` 保持左说明、上升级、右出售布局及 `-x/+x` 金色数字。

---

## 二、复制镜 · CopyMirror

### 2.1 严格机制定义

复制镜从当前生效侧相邻格开始，沿镜面法线背离镜子的方向逐格扫描，找到第一格包含“可复制内容”的地块。该地块是唯一源格；一面镜子复制源格内的全部地块绑定内容，并把它们投影到关于镜面轴对称的目标格。

- “最近”只比较法线射线上的格，不做扇形、全图距离或跨方向搜索。
- 普通空地、敌人和镜子不算可复制内容，扫描会继续向外。
- 若最近源格的内容消失或更近处出现内容，镜子动态重算源格与全部投影。
- 一面镜子只选择一个源格，但源格中可同时包含多项内容，必须整格复制，不能只挑其中一个对象。
- 目标格必须在地图内；超出地图时该镜子不生成投影。

### 2.2 M5 可复制内容

源格可包含：

- 实体格建筑：箭塔、激光塔、格屏障及后续实现复制契约的格建筑。
- 关卡地块元素：尖刺、空洞、大石头及后续实现复制契约的陷阱、障碍和机关。
- 既有投影：允许继续被另一面复制镜复制。

以下内容不可复制：

- 复制镜、反射镜、边屏障及所有其他边建筑。
- 敌人、出生点、路径编号、据点、纯地形颜色/高度等非玩法内容。
- 没有实现复制契约的运行时节点。

### 2.3 投影叠加与占位

- 默认 `projection_ignores_occupancy = true`：投影不写入 `TileCellData.occupant`，不占实体建筑格位。
- 同一格可以同时存在多个投影，也可以与实体建筑或地块元素重叠。
- 关闭开关后，目标格存在实体格建筑或先生成的投影时，该镜子的整组投影不生成；地块元素本身不视为实体占位。
- 投影不计入建筑上限、镜子上限，不消耗资源，也不能被独立选中、升级、旋转或删除。
- 源对象或依赖镜链失效时，对应投影立即移除。
- 放置预览用完整候选镜链判定连通性；封死路线时镜框和当前复制体统一使用 `invalid_preview_color` 高亮红色，预览信息返回 `valid=false` 与 `failure`。

### 2.4 递归复制

- 投影可再次作为源内容复制，镜子不可复制。
- `copy_chain_max` 默认 4，表示从实体源到最终投影允许的最大镜链深度。
- 每项投影记录镜子谱系；同一面镜子不能再次出现在自己的谱系中，用于阻断循环。
- 多面镜的计算必须稳定且与帧率无关；同一输入得到相同投影集合。

### 2.5 塔投影

- 无独立 AI、无独立索敌、无独立冷却和动画时钟。
- 原塔发起一次投射物或激光攻击时，所有有效投影在同一逻辑时刻复制该攻击。
- 攻击起点、目标点、固定朝向和激光线段通过投影的复合镜像变换获得。
- 投影不重新校正敌人，因此镜像位置没有敌人时允许打空。
- 投影无独立转向决策；实体建筑因目标追踪或手动逻辑朝向发生任何模型姿态变化时，既有投影在原节点上实时同步完整姿态。
- 投射物投影仍按原塔等级参数使用飞行速度、尺寸、伤害、空中目标开关、`projectile_penetration_count` 与 `projectile_model_asset`；箭塔普通索敌攻击只用开火瞬间的目标点确定镜像发射方向，复制弹从生成起沿该方向直线飞行、检测沿途目标，直到命中、被 Stuff 截断或耗尽 `attack_range`，不会在旧目标点提前销毁。`TARGET_OR_FACING` 的无目标攻击和 `FACING_ONLY` 的全部攻击均沿镜像后的逻辑方向使用相同直射规则。导弹塔投影沿用源级快照参数，从镜像起点走完同样绕圈表现，然后沿复合镜像后的攻击向量直飞、反射并爆炸；投影不独立索敌，因此不生成第二个 `aim.png` 目标标记。钉锤的四/八方向齐射按每枚投射物独立镜像，保持源建筑一次攻击的全部方向与穿透预算。所有模式都保留源场景 Transform 和运行时 Scale。
- 激光投影按镜像线段逐 tick 结算，继承原塔等级的持续伤害、状态、空中目标开关和传播速度。每个投影独立重算所在空间的反射、Stuff 与穿透截止，并以稳定 payload key 保留移动前沿；Stuff 改动导致的投影重建不会让光束重置或瞬间铺满。
- 镭射塔投影不维护独立冷却；源塔每次脉冲事件都把起点/朝向映射到虚像空间，再由 CombatManager 独立计算完整反射光路、Stuff 阻挡和分段伤害。

### 2.6 屏障投影

- 屏障投影在目标格参与路径阻挡和敌人攻击目标解析。
- 投影没有独立耐久池。敌人对投影造成的伤害转发到原屏障；原屏障死亡后全部关联投影消失。
- 最大耐久、回血、脱战时间、反伤比例、等级参数和 `affects_airborne` 均继承原屏障。
- 同格多个屏障投影按稳定顺序提供当前阻挡目标；前一投影失效后才能解析到下一项。

### 2.7 地块元素投影

- 尖刺投影：敌人进入或停留在投影格时，执行与源尖刺相同的持续伤害；多项尖刺投影按独立效果叠加。
- 空洞投影：敌人仅在源空洞的周期检查时刻仍在投影格上才可能被吞噬；真实格、直接投影和递归投影共享根源格的容量、恢复和吞噬检查时钟。
- 大石头投影：目标格加入动态寻路阻挡层；敌人在阻碍前一格对应路径段先触发既有换路逻辑，无可用路径时攻击该投影。同格普通屏障保持更高的直接攻击优先级；屏障摧毁导致投影重建后，敌人必须重新解析新石头代理，不得穿过。投影没有独立耐久，直接/递归投影的伤害都转发给真实源石头；源石头耐久归零后全部关联投影消失，实体镜子保留。
- 所有地块效果继承源资源参数与 `affects_airborne`。空中敌人是否受影响完全由源效果开关决定。
- 投影不修改关卡原始 `TileCellData`，而通过独立覆盖层参与效果、导航和阻挡查询。
- 源 Stuff 启用 `blocks_ballistics` 时，直接/递归投影也使用同一根源存活状态和统一球形半径参与弹道阻挡；根源摧毁后投影不再阻挡。

### 2.8 放置预览

选择复制镜并悬停合法边时，必须同时显示：

- 镜子本体虚影和当前生效侧。
- 当前扫描得到的源格与目标格。
- 源格内将被复制的内容种类列表。
- 每项投影在目标格的青蓝色半透明虚影。

没有找到源格或目标格越界时仍允许放置镜子，但预览必须显示明确警告。按 `R` 翻面后预览立即重算。

### 2.9 视觉规范

- 复制镜的玩法生效侧仍是唯一事实源，决定最近源格和投影方向，不再额外生成顶部朝向标记。默认仅在表现层启用双观察侧镜面：同一个反射 Quad 根据主相机所在侧贴到朝向观察者的实体表面，因此拉远视角跨过镜面无限平面时不会退回镜体底色，也不会增加第二个反射视口。可用 `reflection_two_sided_visual` 恢复仅生效侧可见。
- 镜面相机的位置与朝向由主相机关于镜面轴严格反射得到，并复制主相机投影和宽高比；反射相机重建为右手基底后会交换屏幕 X 手性，因此镜面 Shader 用 `vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y)` 做一次精确横向补偿。补偿后镜前右侧地块在镜中仍显示为右侧，不改纵向顺序。镜面和实体背板位于独立可见层，反射相机排除该层以同时阻断镜中镜递归与镜体自遮挡。镜面 Camera3D 不继承主相机最终视口 DOF，反射纹理由主视口统一虚化一次。
- 实际镜面刷新由 `MirrorManager` 轮询调度；镜面中心或任一矩形角点处于主相机视锥时均可刷新，并限制刷新间隔与每帧上限。放置预览使用独立低分辨率。
- 建筑投影创建 `Building._visual_root` 的无行为快照，之后每帧同步源的视觉根变换、子 `Node3D` 姿态、可见性和 `Skeleton3D` 骨骼姿态，不重建投影节点。地块元素投影通过 `TileRenderer.create_tile_content_visual_snapshot()` 只复用石头、尖刺、空洞等地块内容几何。地表顶面、侧壁、高度色、路径色和路面色均属于目标关卡基底，不被复制。
- 所有视觉快照按 payload 的完整镜链做严格仿射反射。不得用圆盘、圆柱、方块等独立几何替代地块/建筑，也不得用位移、缩放或垂直错层拆开重叠虚像。
- 正常投影逐表面保留源模型的材质类型、RGB、纹理与 Shader，只通过 `GeometryInstance3D.transparency` 应用统一可调透明度；禁止用白模材质、统一染色或发光覆盖源资产。封路无效预览可临时叠加红色提示层。同格多项投影继续通过不同强调色的同心标识环和悬停标签区分，标识不参与玩法也不替代源几何。
- 同格透明投影按稳定的叠放序号分配 `render_priority`，且不写入深度缓冲；重建时先隐藏旧投影再延迟释放，避免新旧几何在同一帧闪烁。
- 悬停投影格时 HUD 与世界标签显示同格虚像数量、类型、序号和复制链深度。
- 投影不播放独立待机或攻击动画；攻击表现由原件事件同步驱动。

---

## 三、投射物反射镜 · ReflectMirror（已实现）

1. 反射镜是独立镜子种类，与复制镜共享边权限、物理边占用、镜框/实时镜面、预览、翻面、选中、升级和出售流程；两者使用相互独立的数量上限与冷却/库存状态。
2. 我方实体塔与复制塔投射物从生效侧命中有限镜面矩形时，按 `r = d - 2(d·n)n` 反射；切向分量保持、法线分量反号。背面保持穿过。
3. 首次反射前实体塔普通追踪弹继续追踪原目标，复制塔普通投射物保持固定镜像终点；两者首次反射后变为直线弹道。导弹只在绕圈结束后进入镜面查询：反射只改向、不引爆；有标记的实体导弹下一帧仍可继续向原目标转向，无目标和投影导弹保持反射后直飞。
4. 可经过任意多面反射镜；`max_reflections_per_frame` 只是防止极高速单帧循环的工作预算，不是生命周期反射次数上限，未完成距离会在下一帧继续。
5. 投射物当前等级 `attack_range` 是从发射到销毁的累计总路径长度上限；入射段、所有反射段及防止重复命中的微小偏移都计入该预算。
6. 镜面碰撞范围严格使用完整地块边宽度与 `mirror_height_ratio` 高度，不把无限平面当作镜子。复制镜不会反射投射物，反射镜不会参与复制链，也不能被复制。
7. `MirrorManager` 同时聚合外部模块提供的有限反射面。当前亚克力展示柜四侧板注册为内向单面反射体；实体反射镜与柜板同时命中时只使用线段上最近者。顶板不参与。
8. 建筑旋转弹道预览通过 Callable 只读复用 `MirrorManager.trace_projectile_reflection`；投射物、持续激光和脉冲镭射均按同一公式、最近有限交点和防重入偏移显示完整剩余射程，但不注册攻击、不查询敌人、不触发镜子玩法事件或伤害。复制镜仍不参与弹道反射，其投影只独立显示变换后的规划光路。
9. 脉冲镭射在发射时同步计算整条路径。初始段为红，反射后按橙、黄、绿、青、蓝、紫推进，超过紫后循环回红；每段独立结算一次伤害，全部光段与防重入偏移共享一个 `attack_range` 总预算。
10. 每次实体反射镜命中额外返回其当前等级的 `damage_multiplier` 与 `penetration_bonus`，由投射物、持续激光和脉冲镭射按各自路径累计规则消费。

---

## 四、参数表（均需 `@export` 或资源字段）

| 参数 | 当前正式资源值 | 归属 | 说明 |
|---|---:|---|---|
| `copy_mirror_cap` / `reflect_mirror_cap` | 5 / 10 | LevelResource / ResourceManager | 复制镜与反射镜的独立实体上限，投影不计数 |
| `placement_cost` | 复制镜 100 / 反射镜 50 | CopyMirrorDefinition / ReflectMirrorDefinition | 默认金币模式的单次放置费用 |
| `upgrade_costs` | `[50, 50]` | MirrorDefinition | 1→2 与 2→3 的升级费用；升级成功才登记到累计投入 |
| `level_damage_multipliers` | 复制镜 `[1.0,1.1,1.2]` / 反射镜 `[1.1,1.2,1.2]` | MirrorDefinition | 每级复制/反射攻击伤害倍率 |
| `level_penetration_bonuses` | 复制镜 `[0,1,2]` / 反射镜 `[1,2,4]` | MirrorDefinition | 每级复制/反射攻击额外穿透 |
| `mirror_placement_cooldown_enabled` | false | MainController | 开启时忽略放置费用并恢复旧冷却/库存模式 |
| `placement_cooldown_seconds` | 15.0 秒 | CopyMirrorDefinition / ReflectMirrorDefinition | 该种镜子每累加 1 枚可用数量所需的独立周期；两类可分别配置 |
| `mirror_preparation_cooldown_time_scale` | 0.5 | MainController | 首波前与波间准备阶段的冷却回复倍率；波内固定 1.0 |
| `card_icon` | 空 | CopyMirrorDefinition | M6 独立复制镜卡片图；为空时使用“镜”字灰盒。 |
| `inspection_display.function_description` / `upgrade_description` | 各自独立，升级默认空 | MirrorDefinition | 镜子卡悬停/实体说明共用的基础描述与升级描述。 |
| `mirror_height_ratio` | 2.00 格 | CopyMirrorDefinition | 镜框、实时镜面和操作锚点共用高度 |
| `projection_ignores_occupancy` | true | CopyMirrorDefinition | 投影是否忽略实体/投影占位并允许叠加 |
| `copy_chain_max` | 6 | CopyMirrorDefinition | 最大镜链深度 |
| `reflection_enabled` | true | CopyMirrorDefinition | 是否启用复制镜生效面的实时世界反射 |
| `reflection_two_sided_visual` | false | CopyMirrorDefinition | 是否让同一反射面根据观察者所在侧切换实体表面；当前资源只显示玩法生效侧 |
| `reflection_surface_offset_ratio` | 1.00 | CopyMirrorDefinition | 镜面相对镜体厚度的外推比例；大于半厚度以避免远距离深度遮挡 |
| `reflection_resolution` | 512 | CopyMirrorDefinition | 正式镜面的水平渲染分辨率 |
| `reflection_preview_resolution` | 256 | CopyMirrorDefinition | 放置预览镜面的水平渲染分辨率 |
| `reflection_update_interval_frames` | 2 | CopyMirrorDefinition | 同一调度轮次的帧间隔 |
| `reflection_max_updates_per_frame` | 2 | CopyMirrorDefinition | 每次调度最多刷新的可见镜面数 |
| `mirror_reflectivity` | 1.00 | CopyMirrorDefinition | 反射画面相对镜面底色的混合比例 |
| `mirror_surface_tint` | 淡蓝白 | CopyMirrorDefinition | 生效面反射画面的色调 |
| `mirror_back_face_color` | 中性灰 | CopyMirrorDefinition | 镜体背面底色；生效方向只由镜面本身与放置预览表达，不再生成顶部蓝色标记 |
| `projection_alpha` | 0.76 | CopyMirrorDefinition | 源模型材质与纹理不变时的最终虚像不透明度；1 为不透明，越低越透明 |
| `projection_tint` | 青蓝 | CopyMirrorDefinition | 仅用于重叠标识环、标签和投影攻击线的强调色，不染色模型 |
| `invalid_preview_color` | 红色 | CopyMirrorDefinition | 复制障碍会堵死目标路线时的镜体/投影预览颜色 |
| `projection_emission_energy` | 2.8 | CopyMirrorDefinition | 标识环、标签和投影攻击线的发光强度，不修改源模型材质 |

正式镜子资源的费用、保留冷却与关键 Mirror Visual 数值由 `mirror_placement_cooldown_test.gd` 直接加载校验；修改 `MirrorDefinition` 的导出字段结构时必须按 `CONTRIBUTING.md` 的 `@tool Resource` 迁移规则执行，避免编辑器热重载把旧 Inspector/UndoRedo 值写入相邻字段。
| `projection_rim_alpha` | 0.42 | CopyMirrorDefinition | 仅用于封路无效预览的红色边缘提示强度 |
| `projection_ring_spacing_ratio` | 0.045 格 | CopyMirrorDefinition | 同格虚像标识环的半径间隔，不移动源几何 |
| `projection_ring_thickness_ratio` | 0.022 格 | CopyMirrorDefinition | 标识环粗细 |
| `mirror_side_default` | from | CopyMirrorDefinition | 新镜子默认生效侧 |
| `collision_epsilon_ratio` | 0.002 格 | ReflectMirrorDefinition | 反射点沿新方向推进的防重入距离；计入总路径。 |
| `max_reflections_per_frame` | 8 | ReflectMirrorDefinition | 单帧最多处理的反射次数；不是投射物生命周期上限。 |
| `projectile_reflection_enabled` | true | AcrylicDisplayCaseDefinition | 是否让关卡边缘四侧板加入统一投射物反射查询。 |
| `collision_epsilon_ratio` | 0.002 格 | AcrylicDisplayCaseDefinition | 柜板反射后的防重入偏移；与镜子一样计入总路程。 |
| `max_reflections_per_frame` | 8 | AcrylicDisplayCaseDefinition | 柜板高速多次反射的单帧工作预算。 |

---

## 五、关键架构

```text
EdgeOccupancyRegistry
  └─ 统一登记实体边建筑，供 BuildingManager / MirrorManager 查询

MirrorManager
  ├─ 放置、翻面、升级、出售、选择与预览
  ├─ 沿法线扫描最近源格
  ├─ 固定点迭代生成有限镜链
  └─ 向战斗、阻挡、导航、地块效果暴露只读投影查询

Placement connectivity
  -> MirrorManager.get_prospective_blocked_cells(extra_source, candidate_mirror, target)
  -> 当前镜 + 候选镜 + 可选未登记建筑源的完整递归图
  -> PathPlacementConnectivityGuard 只消费障碍格集，MirrorManager 不持有路网

CopyMirror
  ├─ edge_id / from_cell / to_cell / active_side / level / invested_resource
  └─ MirrorReflectionView（共享世界屏幕对齐反射，单视口按观察侧切换镜面）

MirrorProjection
  ├─ payload / lineage / composed_transform
  ├─ Building 真实视觉快照 / TileRenderer 地块内容快照
  ├─ 不写入地块 occupant
  └─ 屏障/石头共享源伤害转发与玩法代理
```

模块协作规则：

- GridManager 负责四/六边形的边法线射线与镜像格对，Mirror 不读取具体坐标布局。
- CopyMirror的实体边位置通过GridManager采样物理边中点坡高；连续斜坡上与边贴合，断崖仍取两侧较高表面。
- BuildingManager 只通过注入的边占用表和投影阻挡查询协作。
- TileManager 与 TileEffectSystem 只通过注入的投影覆盖查询协作，不持有 Mirror 节点。
- 塔只发出“原件攻击事件”；MirrorManager 负责生成同步投影攻击，塔不直接依赖镜子模块。
- 投影内部以稳定 MirrorCopyPayload 描述来源和变换；当前 MirrorManager 仍显式识别 Building 与 TileEffect，统一 `ICopyable`/注册表属于架构治理批次 5，不能把现状描述为已完全开放扩展。
- Main 只注入主相机和 `TileRenderer.create_tile_content_visual_snapshot` Callable；MirrorManager 不持有 TileRenderer 具体类型。

### 实现文件

| 文件 | class_name / 基类 | 职责 |
|---|---|---|
| `scripts/shared/EdgeOccupancyRegistry.gd` | `EdgeOccupancyRegistry` / `RefCounted` | 镜子、边屏障共用的规范化物理边占用表。 |
| `scripts/mirror/MirrorDefinition.gd` | `MirrorDefinition` / `Resource` | 所有实体镜共享的身份、放置/升级经济、三级战斗修正、基础/升级两行语义说明、放置方向和实时镜面表现契约。 |
| `scripts/mirror/CopyMirrorDefinition.gd` | `CopyMirrorDefinition` / `MirrorDefinition` | 复制链深、占位开关与虚像表现参数，并复用镜子基础配置校验。 |
| `scripts/mirror/CopyMirror.gd` | `CopyMirror` / `Node3D` | 实体镜面边节点、生效侧、等级、累计真实投入和程序化表现。 |
| `scripts/mirror/ReflectMirrorDefinition.gd` | `ReflectMirrorDefinition` / `MirrorDefinition` | 投射物反射防重入偏移和单帧工作预算。 |
| `scripts/mirror/ReflectMirror.gd` | `ReflectMirror` / `CopyMirror` | 复用实体镜表现但只向弹道查询注册为反射镜。 |
| `scripts/mirror/MirrorPlacementData.gd` | `MirrorPlacementData` / `Resource` | 一个开局实体镜子的种类、起始格、边方向、生效侧与等级。 |
| `scripts/mirror/MirrorReflectionView.gd` | `MirrorReflectionView` / `Node3D` | 生效面的共享世界 SubViewport、屏幕对齐反射与反射相机横向手性补偿。 |
| `scripts/mirror/MirrorCopyPayload.gd` | `MirrorCopyPayload` / `RefCounted` | 稳定来源、镜子谱系和复合反射变换。 |
| `scripts/mirror/MirrorProjection.gd` | `MirrorProjection` / `Node3D` | 真实源内容快照、源模型实时姿态同步、稳定透明渲染顺序、严格反射、屏障与地块效果代理。 |
| `scripts/mirror/MirrorProjectionProjectile.gd` | `MirrorProjectionProjectile` / `Node3D` | 不追踪的固定镜像落点或从起点直射投射物。 |
| `scripts/mirror/MirrorManager.gd` | `MirrorManager` / `Node3D` | M5 唯一入口，管理放置、升级、出售、预览、固定点镜链和跨模块查询。 |
| `scripts/tile/TileObstacleRuntime.gd` | `TileObstacleRuntime` / `Node3D` | 镜像石头最终转发到的真实逐格耐久源。 |
| `scripts/ui/MirrorActionPanel.gd` | `MirrorActionPanel` / `Control` | 跟随选中镜子，以建筑一致布局显示说明、升级、出售和经济数字。 |
| `resources/mirrors/CopyMirror.tres` | `CopyMirrorDefinition` | 默认 M5 参数资源。 |
| `scripts/building/Building.gd` | `Building` / `Node3D` | `create_copy_visual_snapshot` 创建无行为建筑视觉，`sync_copy_visual_snapshot` 向既有快照同步完整实时姿态。 |
| `scripts/tile/TileRenderer.gd` | `TileRenderer` / `Node3D` | `create_tile_content_visual_snapshot` 沿正常渲染几何路径生成不含基底的石头/尖刺/空洞快照。 |
| `tests/copy_mirror_test.gd` | `SceneTree` | 整格复制、虚像攻击、屏障/Stuff 共享根源、递归镜链与复制镭射回归。 |
| `tests/reflect_mirror_test.gd` | `SceneTree` | 严格反射角、背面穿过、多镜反射、实体/复制投射物与脉冲镭射总路程回归。 |
| `tests/mirror_placement_cooldown_test.gd` | `SceneTree` | 默认金币放置、失败事务、实际投入全退、独立 5/10 cap，以及开关后的两类独立冷却、库存、阶段倍率、卡片扫描、正式资源与初始装配回归。 |
| `tests/mirror_upgrade_test.gd` | `SceneTree` | 49 项三级配置、复制链/反射攻击修正、升级经济、两行语义说明/升级/出售 UI、满级状态、退款和等级持久化回归。 |
| `tests/mirror_ui_visual_capture.gd` | `SceneTree` | 手工 Forward+ 截取镜子卡悬停两行说明与选中镜子三图标布局。 |

## 六、函数索引

| 入口 | 签名 | 职责 |
|---|---|---|
| `GridManager.get_mirror_cell_pair` | `(from_cell, edge_index, active_from_side, distance_from_edge) -> Dictionary` | 在 Grid 内封装四/六边形法线源格/目标格对。 |
| `MirrorManager.place_copy_mirror` | `(from_cell, edge_index, active_from_side = null) -> CopyMirror` | 完成校验、共享边登记、消耗 1 枚复制镜库存并重建投影。 |
| `MirrorManager.place_reflect_mirror` | `(from_cell: Vector3i, edge_index: int, active_from_side: Variant = null) -> ReflectMirror` | 按同一物理边规则放置投射物反射镜并消耗其独立库存；不参与复制连通性计算。 |
| `MirrorManager.upgrade_mirror` | `(mirror: CopyMirror) -> bool` | 原子扣除下一等级费用、登记累计投入、提升等级并立即重建复制/反射效果。 |
| `MirrorManager.remove_mirror` | `(mirror: CopyMirror) -> bool` | 主动出售实体镜、释放该种类 cap并返还其真实累计投入；冷却模式另返还同种镜子 1 枚库存。 |
| `MirrorManager.export_initial_placements` | `() -> Array[MirrorPlacementData]` | 按实体镜 `placement_order` 导出种类、边、生效侧与等级，不包含投影。 |
| `MirrorManager.load_initial_placements` | `(placements: Array) -> Array[String]` | 按数组顺序免建造费恢复实体镜等级、登记共享边并计入镜子 cap。 |
| `MirrorManager.validate_placement` | `(from_cell: Vector3i, edge_index: int, check_runtime_availability: bool = true, mirror_kind: MirrorPlacementData.MirrorKind = COPY) -> Dictionary` | 按具体镜子 Definition 返回边界、权限、占用、敌人、金币/冷却和独立数量上限校验结果。 |
| `MirrorManager.set_placement_cooldown_enabled` | `(value: bool) -> void` | 在金币无冷却与保留的独立冷却/库存模式之间切换。 |
| `MirrorManager.set_cooldown_time_scale_resolver` | `(value: Callable) -> void` | 注入波次阶段倍率，保持镜子模块不直接依赖 WaveManager。 |
| `MirrorManager.advance_placement_cooldowns` | `(delta: float) -> void` | 使用已缩放帧时间和阶段倍率推进两种独立周期；一次大 delta 可累计多枚。 |
| `MirrorManager.reset_placement_cooldowns` | `() -> void` | 关卡初始陈列/切关时把两种库存重置为各 1 枚，并开始下一周期。 |
| `MirrorManager.get_available_mirror_count` | `(mirror_kind) -> int` | 返回对应种类当前可连续放置的库存数量。 |
| `MirrorManager.is_mirror_kind_ready` / `get_placement_cooldown_ready_ratio` | `(mirror_kind) -> bool` / `(mirror_kind) -> float` | 以库存判定可放置；库存为 0 时为卡片扫描提供下一枚的恢复进度。 |
| `MirrorDefinition.get_formatted_inspection_description` | `() -> String` | 返回镜子卡悬停与实体说明共用的基础/升级两行纯文本。 |
| `MirrorDefinition.get_formatted_inspection_description_bbcode` | `() -> String` | 返回绿/黄标题与默认白色正文组成的两行 BBCode。 |
| `CopyMirrorDefinition.validate_configuration` | `() -> Array[String]` | 校验身份、放置/升级经济、三级战斗修正、链深、镜面预算、颜色与全部虚像表现范围。 |
| `MirrorManager.rebuild_now` | `() -> void` | 从实体来源计算稳定有限镜链并重建投影覆盖层。 |
| `MirrorManager.refresh_world_transforms` | `() -> void` | Terrain变化后重采样实体/预览镜的物理边坡高，再重建投影；不改变镜面陈列顺序。 |
| `MirrorManager.get_projected_effects` | `(cell) -> Array[TileEffect]` | 向 TileEffectSystem 提供同格可叠加效果。 |
| `MirrorManager.get_projected_effect_bindings` | `(cell: Vector3i) -> Array[Dictionary]` | 返回 `{effect, source_cell, state_key}` 列表，使有状态地块投影归并到真实根源。 |
| `MirrorManager.blocks_enemy_navigation` | `(cell, target = null) -> bool` | 向 TileManager 提供投影岩石阻断。 |
| `MirrorManager.resolve_projected_blocker` | `(cell, target = null) -> Node` | 向 BuildingManager 提供投影屏障代理。 |
| `MirrorManager.resolve_projected_navigation_blocker` | `(cell, target = null) -> Node` | 向 TileManager 提供可攻击的投影石头代理，保持石头“先换路”与屏障“直接攻击”的入口分离。 |
| `MirrorManager.update_preview` / `flip_preview` | `(from_cell, edge_index) -> bool` / `() -> bool` | 构建镜面、源格/目标格信息和投影虚影，翻面后重算。 |
| `MirrorManager.update_reflect_preview` | `(from_cell: Vector3i, edge_index: int) -> bool` | 创建真实反射镜模型预览并显示当前投射物生效侧。 |
| `MirrorManager.register_projectile_reflection_provider` | `(owner: Object, resolver: Callable) -> bool` | 注册镜子模块外的有限反射面查询，以弱 owner 管理生命周期。 |
| `MirrorManager.unregister_projectile_reflection_provider` | `(owner: Object) -> void` | 注销指定模块的外部反射查询。 |
| `MirrorManager.get_projectile_reflection_provider_count` | `() -> int` | 清理失效提供者并返回当前外部查询数量。 |
| `MirrorManager.trace_projectile_reflection` | `(start: Vector3, end: Vector3) -> Dictionary` | 比较实体反射镜与外部提供者并返回最近有限交点；键为 `{hit, position, normal, distance, mirror, reflector, surface_id, epsilon, max_reflections_per_frame, damage_multiplier, penetration_bonus}`。 |
| `MirrorManager.trace_ballistic_blocker` | `(start: Vector3, end: Vector3, excluded: Object = null) -> Dictionary` | 比较实体与投影 Stuff 的统一球形交点，返回最近吸收体。 |
| `MirrorManager._on_copy_attack_triggered` | `(building: Building, attack_kind: StringName, world_start: Vector3, world_end: Vector3, damage: float) -> void` | 把实体攻击复合镜像到每个投影；`missile/directional_missile` 分支创建镜像朝向的独立爆炸导弹。 |
| `MirrorManager.projections_rebuilt` | `(count: int)` | 镜面/投影几何重建完成；Main 用它刷新已选建筑的只读弹道预览，使镜子放置、翻面和移除不会留下旧路径。 |
| `MirrorManager.get_prospective_blocked_cells` | `(extra_source: Variant = null, candidate_mirror: Variant = null, target: Node = null) -> Dictionary` | 返回完整稳定递归图中对指定导航档案有效的屏障/石头投影格集。 |
| `MirrorManager.set_path_connectivity_validator` | `(value: Callable) -> void` | 注入 Path 模块的候选放置校验；实体登记和库存消耗前复核。 |
| `MirrorManager.get_preview_mirror` / `get_preview_projections` | `() -> CopyMirror` / `() -> Array[MirrorProjection]` | 返回当前可见预览对象，供表现验收与自动化回归读取。 |
| `MirrorManager.set_reflection_camera` | `(camera: Camera3D) -> void` | 注入主相机并为已有/预览镜面建立共享世界反射。 |
| `MirrorManager.set_tile_visual_snapshot_resolver` | `(resolver: Callable) -> void` | 注入不含地形基底的地块内容快照工厂，保持 Mirror/Tile 模块边界。 |
| `MirrorManager.set_inspected_cell` | `(cell: Variant = null) -> void` | 切换同格虚像悬停标签，不移动任何虚像几何。 |
| `MirrorCopyPayload.copy_through` | `(mirror_id, target_cell, axis_start, axis_end, mirror_damage_multiplier = 1.0, mirror_penetration_bonus = 0) -> MirrorCopyPayload` | 追加谱系与镜像轴，并累计该镜等级的伤害倍率与穿透加成。 |
| `MirrorCopyPayload.transform_point` | `(point) -> Vector3` | 按谱系顺序应用复合镜像，供同步攻击使用。 |
| `MirrorCopyPayload.get_composed_transform` / `transform_transform` | `() -> Transform3D` / `(source_transform: Transform3D) -> Transform3D` | 把点反射谱系组合为仿射变换，并严格作用到源视觉姿态。 |
| `Building.create_copy_visual_snapshot` | `() -> Node3D` | 复制当前真实视觉，剥离标签、音频、脚本和独立动画节点。 |
| `Building.sync_copy_visual_snapshot` | `(snapshot: Node3D) -> bool` | 把当前子节点与骨骼姿态同步到既有无行为快照，不启动独立动画时钟。 |
| `MirrorProjection.sync_source_visual_pose` | `() -> bool` | 不重建投影，先同步源模型姿态，再将 payload 的全部镜轴组合变换作用于视觉根。 |
| `MirrorProjectionProjectile.configure` | `(combat_manager: CombatManager, source_building: Building, start: Vector3, end: Vector3, speed: float, damage: float, visual_length: float, visual_width: float, color: Color, model_asset: ModelAssetDefinition = null, maximum_distance: float = -1.0, reflection_resolver: Callable = Callable(), ballistic_from_start: bool = false, penetration_count: int = 0) -> void` | 配置固定镜像终点或从起点直射；`ballistic_from_start=true` 时从生成起沿途命中，最后一个参数沿用源建筑额外穿透预算。 |
| `MirrorProjection.take_structure_damage` | `(amount: float, attacker: Node = null) -> float` | 把屏障或石头投影承伤转发到 payload 的真实根源耐久。 |
| `TileRenderer.create_tile_content_visual_snapshot` | `(cell: Vector3i) -> Node3D` | 复用正常地块内容几何函数，只生成障碍与元素快照，不含地表基底。 |
| `MirrorReflectionView.request_refresh` | `() -> bool` | 镜面矩形进入视锥时按当前观察侧更新实体表面与反射相机，并请求 SubViewport 单帧刷新。 |
| `CopyMirror.get_reflection_viewport` | `() -> SubViewport` | 返回屏幕对齐反射目标，供调试与回归检查宽高比。 |
| `CopyMirror.refresh_visual` | `() -> void` | Definition 表现参数变化时重建镜框、镜面目标与当前生效面。 |
| `CopyMirror.refresh_world_transform` | `() -> void` | 只重采样共享边中点高度，保留生效侧和镜面运行时状态。 |
| `EdgeOccupancyRegistry.try_register` / `unregister` | `(edge_id, occupant) -> bool` / `(edge_id, expected = null) -> bool` | 原子登记/释放物理边。 |

## 七、已知限制

- 当前反射镜作用于我方实体/复制塔投射物、持续激光和脉冲镭射；敌方投射物仍不反射。持续激光的反射段只在传播前沿到达后出现。
- 最近源格仅沿镜面法线离散扫描，不支持任意角度射线穿格。
- 投影攻击忠实复制原攻击，允许因镜像空间无目标而打空。
- 屏幕对齐方案不提供任意形状镜面的逐像素斜裁面；当前复制镜均为矩形边建筑，镜面外区域由实体 Quad 自身裁切。
- 为阻止递归和镜体自遮挡，所有反射相机不渲染镜面与镜体背板；镜中不会出现其它镜子的反射画面或蓝色背板，也不会出现无限镜廊。
- 反射相机当前不继承任何主相机 CameraAttributes；未来若主相机加入独立曝光参数，需要选择性复制曝光字段并继续排除 DOF。
