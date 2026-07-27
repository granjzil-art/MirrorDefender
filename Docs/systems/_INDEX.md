# 系统文档索引

> 每个系统单独维护一份文档（用户硬性要求）。改代码即改对应文档。
> 文档统一结构：职责 / 分类 / 关键参数 / 关键架构 / 函数索引 / 已知限制。
> **总入口：[`../00_MirrorDefender_初版游戏设计案.md`](../00_MirrorDefender_初版游戏设计案.md)（GDD 总纲）**

| 系统 | 文档 | 初版范围 |
|---|---|---|
| 镜子（核心） | [Mirror_镜子系统.md](Mirror_镜子系统.md) | M5 复制镜已实现；M6 反射镜待实现 |
| 网格 | [Grid_网格系统.md](Grid_网格系统.md) | 六边形 + 正方形 |
| 地块 | [Tile_地块系统.md](Tile_地块系统.md) | 地表 + 尖刺/空洞/岩石元素 + 编辑器 + 高度档 |
| 建筑 | [Building_建筑系统.md](Building_建筑系统.md) | 箭塔 + 激光塔 + 地块/边屏障 |
| 路径边屏障 | [EdgeBarrier_路径边屏障.md](EdgeBarrier_路径边屏障.md) | 任意内部共享边放置 + 默认双向阻挡 |
| 单位 | [Unit_单位系统.md](Unit_单位系统.md) | 敌方单位（不可镜像） |
| 资源 | [Resource_资源系统.md](Resource_资源系统.md) | 单一主资源 + 上限 |
| 波次 | [Wave_波次系统.md](Wave_波次系统.md) | 逐波手动释放 + 可重叠 + 波内归一延迟 + 胜负/Debug 边界 |
| 索敌战斗 | [Combat_索敌与战斗.md](Combat_索敌与战斗.md) | 固定伤害×因子 |
| 路径 | [Path_路径系统.md](Path_路径系统.md) | 手动指定路径 |
| 相机输入 | [CameraInput_相机与输入.md](CameraInput_相机与输入.md) | WASD/QE/XC/滚轮 + 每关 1～6 镜头预设 |
| UI/HUD | [UI_界面系统.md](UI_界面系统.md) | 持久 AppFlow 选关 + 正式 HUD + 右侧波次/重启/退出三按钮 |
| 调试控制台 | [Debug_调试控制台.md](Debug_调试控制台.md) | F1 模态、八类开关与命令注册表 |
| AI | [AI_敌方AI系统.md](AI_敌方AI系统.md) | 手工路径移动 + 受阻时在手工路径间换路 |
| 关卡存档 | [Level_关卡与存档.md](Level_关卡与存档.md) | LevelLoader 原子装配 + Catalog/Page 六槽分页选关 + 六机位；无解锁/进度存档 |
| 表现音效 | [FX_表现与音效.md](FX_表现与音效.md) | 反射/倒影/命中 |

跨系统配置校验由 `scripts/shared/ConfigurationValidator.gd` 提供无副作用的文本、数值范围、颜色和嵌套错误工具；各资源仍在所属系统文档登记自身 `validate_configuration()` 契约。
