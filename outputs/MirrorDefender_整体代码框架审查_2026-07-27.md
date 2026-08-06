# MirrorDefender · 整体代码框架审查

- 审查日期：2026-07-27
- 审查对象：当前工作区（包含尚未提交的 M6 批次 6 代码）
- 引擎基线：Godot 4.7.1 stable
- 审查原则：先阅读 `CONTRIBUTING.md`，按“健壮性 / 参数化 / 模块化 / 可拓展”四项硬要求检查
- 变更声明：本次未修改任何现有代码、场景、资源或设计文档；仅新增本审查报告

## 一、结论

当前框架不是“推倒重来”级别，底座质量明显高于一般原型：关卡资源校验、运行时资源隔离、策略接口、加载回滚、信号生命周期和自动测试都做得较扎实。

但若严格按 `CONTRIBUTING.md` 的硬标准判断，当前只能算**部分满足**，主要问题集中在：

1. 已存在两个可触发的运行时状态一致性问题；
2. 模块虽然按目录拆开，但跨模块仍大量强类型持有，未达到项目要求的松耦合边界；
3. 复制体系没有完成统一 `ICopyable` 契约，镜像链只有深度上限、没有总工作量预算；
4. 当前主场景能运行，16 套测试全部通过，但 Godot 4.7.1 实机加载仍产生 14 条脚本警告，测试入口不会因普通 warning 失败；
5. 设计基线、现役资源和系统文档存在多处事实源冲突。

### 四维评分

| 维度 | 评分 | 结论 |
|---|---:|---|
| 健壮性 | 6.5 / 10 | 有良好校验与回滚，但存在状态混装、延迟释放串扰和 warning 漏检 |
| 参数化 | 8.5 / 10 | 约 360 个导出字段、约 145 个分组，资源化充分；少量核心参数无范围约束，正式默认值文档不一致 |
| 模块化 | 5.5 / 10 | 目录和 Manager 边界清楚，但大量跨模块强类型引用、双向依赖和超长多职责脚本违反项目硬规范 |
| 可拓展 | 6.5 / 10 | Grid/Combat/Path/Tile 策略化较好；Mirror 复制扩展契约未完成，feature flag 语义不完整 |
| 文档健康度 | 5.5 / 10 | 实现文档丰富，但事实源层级、默认值和里程碑状态存在冲突 |

**综合：6.5 / 10。可继续迭代，但建议先做一轮“架构治理 + 健壮性修复”，再继续扩反射镜。**

---

## 二、我对游戏与当前阶段的理解

MirrorDefender 是斜俯视 3D 经典塔防：准备期布防，敌人按手工路径与波次推进，据点生命归零失败，完成固定波数并清场胜利。

核心卖点是“镜子作为地块边上的机制实体”：

- **复制镜**：沿生效侧法线扫描最近含可复制内容的格，将整格可复制内容镜像到对称位置；虚像默认不占格，可叠加、可再次被复制；建筑虚像没有独立 AI/索敌/时钟，只同步源攻击。
- **反射镜**：后续里程碑实现；激光按反射定律多次反射，背面可 PASS/BLOCK，建筑不挡光。

当前文档状态：M1～M5 已完成；当前 M6 是正式交互与 UI 大版本，六批已实现，批次 6 待验收；反射镜已顺延，尚未实现。

---

## 三、验证结果

### 3.1 自动测试

使用 Godot 4.7.1 控制台执行 `tests/run_all_tests.ps1`：

- **16 / 16 个测试套件通过**；
- 覆盖复制镜、飞行单位、路径与换路、关卡反射、资源与加载回滚、M6 六批 UI 等；
- 测试总入口最终输出：`All 16 test suites passed.`

测试基础是健康资产，但不能据此认定零 warning，见问题 P1-3。

### 3.2 主场景真机运行

通过 Godot 4.7.1 启动 `scenes/Main.tscn`：

- 主场景可启动；
- 无 Parser Error、无立即运行时错误；
- 产生 **14 条 GDScript warning**，包括枚举赋值、互不兼容三元表达式、变量遮蔽、疑似未初始化变量等。

### 3.3 工作区状态

当前工作区不是干净提交状态，包含 M6 批次 6 的大量修改和未跟踪文件。报告按“当前工作区”审查，而不是按 `HEAD` 审查。`git diff --check` 未发现空白错误，只有 LF/CRLF 转换提示。

---

## 四、健康结构

以下结构值得保留：

1. **关卡加载事务**：`scripts/level/LevelLoader.gd:29-62` 先只读校验，再应用 Grid/Tile，失败时回滚 Grid 并保留旧关卡。
2. **运行时资源隔离**：`scripts/tile/TileManager.gd:58-75,239-248` 克隆 `TileCellData`，避免占位、清障和高度状态污染 `.tres`。
3. **配置校验完整**：`scripts/level/LevelResource.gd:309-508` 覆盖网格、路径、端点、波次、引用与有限数。
4. **策略接口基础良好**：已有 `IGridShape`、`ITargetingStrategy`、`IAttackStrategy`、`IAutoRouteStrategy`、`TileEffect`。
5. **战斗注册清理较稳健**：`scripts/combat/CombatManager.gd:27-47,140-178` 处理失效实例、信号断开与重入清理。
6. **路径换路边界清晰**：手工路径优先，A* 只在同目标手工路网并集内运行，且有确定性排序。
7. **经济事务集中**：ResourceManager 统一余额、cap、消费、退款和非有限数防护。
8. **M6 UI 分层方向正确**：交互、时间、HUD、只读检视、波次模型和调试命令注册已拆分。

---

## 五、问题清单

### P0 / Critical

未发现默认配置下可稳定触发的致命崩溃或数据永久损坏问题。

### P1 / Major

#### P1-1 `T` 切换网格会形成“新 Grid + 旧 Tile/Path/Building”的混合状态

- 证据：`scripts/Main.gd:430-437`
- 对照：`scripts/tile/TileManager.gd:47-57`
- 触发：运行主场景按 `T`。
- 原因：Main 先直接改变 `grid.grid_shape`，再调用 `tile_manager.load_level(current_level)`；当前关卡的 `grid_shape` 与新 Grid 不一致时，TileManager 返回 `false`，Main 忽略结果且不回滚。
- 影响：拾取、地块、路径、占位、建筑和镜像可能开始按不同坐标系解释。
- 结论：真实健壮性缺陷，应优先修。

#### P1-2 延迟释放的旧地块障碍可能误删同格新障碍

- 证据：`scripts/tile/TileManager.gd:254-277,285-297`
- 触发：同一帧替换某格运行时障碍，同时旧投射物仍命中已 `queue_free()` 但尚未离树的旧障碍。
- 原因：旧障碍移出 Dictionary 后未断开信号；回调只检查“该格当前是否有障碍”，没有核对“发送者是否就是 Dictionary 中当前对象”。
- 影响：旧对象的 `depleted` / `durability_changed` 可能作用到新对象。
- 结论：典型延迟释放身份串扰，应优先修。

#### P1-3 主场景有 14 条 warning，但测试入口不会因此失败

- 实机警告位置：
  - `scripts/tile/TileCellData.gd:36,148,155`
  - `scripts/level/LevelResource.gd:505`
  - `scripts/grid/GridManager.gd:158,187,190`
  - `scripts/combat/PriorityTargetingStrategy.gd:18`
  - `scripts/mirror/MirrorManager.gd:576`
  - `scripts/unit/EnemyUnit.gd:73`
  - `scripts/ui/WaveTimelineModel.gd:40`
  - `scripts/ui/WaveTimelinePanel.gd:262`
  - `scripts/ui/TimeControlPanel.gd:79`
  - `scripts/tile/TileRenderer.gd:318`
- 测试入口：`tests/run_all_tests.ps1:44-47` 只把 `SCRIPT ERROR`、`ERROR:` 和泄漏 warning 判为失败。
- 影响：测试全绿，但不满足 M6 文档“无新增警告洪泛”和 Godot 4.7 严格类型目标。
- 备注：多数是类型/命名警告，不等同于当前已发生逻辑错误；但测试门禁存在明确盲区。

#### P1-4 镜像链只有深度限制，没有总 payload / 总节点 / 单次预算

- 证据：`scripts/mirror/MirrorManager.gd:368-452`
- 当前保护：`copy_chain_max`、单链不重复镜子、最大 pass 数。
- 缺口：没有总投影数、单格堆叠数、单次重建工作量或超预算降级策略。
- 风险：镜子数量和重叠复制内容增加时，组合路径可能让 payload 数量快速膨胀；每次重建还会创建大量 Projection、Mesh、Material、Label。
- 结论：反射镜加入前必须补复杂度预算，否则核心机制会成为性能热点。

#### P1-5 模块化没有满足项目“禁止跨模块硬持有引用”的严格标准

- 证据示例：
  - `scripts/mirror/MirrorManager.gd:25-28` 强持有 Tile/Resource/Combat/Building Manager；
  - `scripts/building/BuildingManager.gd:26-29` 强持有 Grid/Tile/Resource/Combat Manager；
  - `scripts/wave/WaveManager.gd:28-30` 强持有 Path/Combat/Resource Manager；
  - UI 多个 Panel/Service 直接持有具体 Manager 类型。
- 现状：依赖由 Main 显式注入，优于到处 `get_node()`；但它仍是具体类型依赖，不是信号/端口/只读接口。
- 双向耦合：MirrorManager 持有 BuildingManager，而 BuildingManager 又通过 Callable 回查 Mirror；Tile 与 Mirror 也存在类似反向查询。
- 结论：架构是“目录模块 + Composition Root”，不是 `CONTRIBUTING.md` 字面要求的松耦合模块。
- 决策缺口：需要先由项目明确“Composition Root 注入具体 Manager 是否允许”，否则规范和实现会持续互相打架。

#### P1-6 `ICopyable` 尚未实现，复制扩展仍由 MirrorManager 枚举具体来源

- 证据：`scripts/mirror/MirrorManager.gd:455-492`
- 文档自认：`Docs/systems/Mirror_镜子系统.md:185-192`、`Docs/systems/Building_建筑系统.md:230-234`。
- 现状：Building / TileEffect 提供方法约定与 payload，但没有统一 `ICopyable` 或注册表；代码库中也不存在 `class_name ICopyable`。
- 影响：新增可复制对象仍需修改 MirrorManager，违反“新增变种不改核心管理器”的目标。

#### P1-7 feature flag 不是完整的运行时开关

- 证据：`scripts/building/BuildingManager.gd:7-8`、`scripts/combat/CombatManager.gd:5-6`、`scripts/mirror/MirrorManager.gd:368-373`。
- 现状：部分 flag 只阻止新注册/新放置；已存在建筑、目标、投影和信号不一定停止或清理。
- 缺口：关闭时是否停算、清对象、断信号；重开时是否重建，没有统一契约。
- 影响：模块隔离测试、调试禁用、故障降级行为不可靠。

#### P1-8 敌人和投射物没有对象池，违反明确性能红线

- 证据：`scripts/wave/WaveManager.gd:238`、`scripts/combat/CombatManager.gd:104`
- 规范：`CONTRIBUTING.md:75` 要求大量单位使用对象池。
- 风险：高波次、快速倍率、短攻击间隔和复制攻击叠加时，Node/材质频繁创建与 `queue_free()` 会造成帧时间尖刺。

### P2 / Major-Minor 架构债

#### P2-1 核心脚本已经超过多职责阈值

- `scripts/mirror/MirrorManager.gd`：约 733 行；同时承担放置、经济、复制图、投影节点、反射调度、跨模块查询和攻击转发。
- `scripts/building/Building.gd`：约 619 行；同时承担战斗、耐久、表现、动画快照和复制协议。
- `scripts/Main.gd`：约 560 行；除装配外还承担输入、拾取、选择、遗留 HUD、调试摘要和网格热切换。
- `scripts/level/LevelResource.gd`：约 509 行；数据模型和所有运行时校验聚合在一起。
- 对照：`CONTRIBUTING.md:56` 规定超过 300 行考虑拆分。

#### P2-2 Main 仍保留大量已隐藏的旧 HUD/调试逻辑

- 证据：`scripts/Main.gd:270-425`
- 这些代码仍直接理解建筑种类、耐久、波次、镜子和投影信息，虽界面被隐藏，但继续增加 Main 的跨系统知识与维护成本。

#### P2-3 发布边界没有隔离调试控制面

- `scripts/Main.gd:46-47` 默认 `debug_console_enabled = true`；
- `scripts/Main.gd:197-213` 即使 UI 关闭也仍装配 RuntimeDebugBindings；
- `project.godot:23-25` 无条件 Autoload MCPRuntimeProbe。
- 当前开发阶段可接受，但发布构建前应由 debug build / feature tag 控制，而不是仅隐藏 UI。

#### P2-4 MCP Autoload 违反项目 Godot 4.7 专用数学函数规范

- `addons/godot_mcp/runtime/mcp_runtime_probe.gd:178,180` 使用普通 `max()`，而项目规范要求整数场景使用 `maxi()`。
- 因该脚本由 `project.godot` 自动加载，它属于实际运行路径，不应视为“工具目录可忽略”。

#### P2-5 持久化设置未拒绝 NaN / Infinity

- 证据：`scripts/ui/RuntimeSettings.gd:15-24,42-49`
- `clampf(float(value))` 不是完整的类型和有限数校验；损坏或手工编辑的 `user://settings.cfg` 可能把非有限值传入音量或 UI scale。

#### P2-6 参数化整体很好，但少量核心参数没有 Inspector 范围

15 个直接 `@export var float/int` 未使用 `@export_range`，集中在：

- `scripts/grid/GridRenderer.gd:13-14`
- `scripts/grid/GridManager.gd:20,35`
- `scripts/camera/CameraController.gd:18,21,24,27-36`

这些参数中存在最小/最大互相约束、负值无意义等情况，应至少在配置校验或 setter 中形成统一约束。

#### P2-7 场景仍有明确禁止的 `load_steps`

- `scenes/ui/DebugConsole.tscn:1`
- 违反 `CONTRIBUTING.md:10`。

#### P2-8 自动测试没有枚举验证全部正式关卡资源

- `tests/robustness_baseline_test.gd:325-333` 只完整验证 `M4DemoLevel.tres`。
- 其它 `resources/levels/*.tres` 的断链、过期字段和路径问题可能无法在总测试中暴露。

#### P2-9 测试脚本可移植性较弱

- `tests/run_all_tests.ps1:8-16` 内置机器特定 Godot 路径；
- 当前机器首次直接运行还被 PowerShell 执行策略拦截，需要进程级 `ExecutionPolicy Bypass`。
- 已支持 `GODOT_BIN`，但默认入口仍不够“一键跨环境”。

---

## 六、文档与事实源问题

### D1 `copy_chain_max` 默认值冲突

- GDD / 设计基线：默认 4（`Docs/00...:35,84`；`Docs/01...:26,81`）；
- 脚本默认：4（`scripts/mirror/CopyMirrorDefinition.gd:23`）；
- 正式资源与 Mirror 系统参数表：6（`resources/mirrors/CopyMirror.tres:16`；`Docs/systems/Mirror_镜子系统.md:137`）。

如果 6 是正式调参，应补 DECISIONS/CHANGELOG 并改写“默认”的含义；否则应统一回 4。

### D2 双观察侧默认语义冲突

- DECISIONS 和脚本默认：`reflection_two_sided_visual = true`；
- 正式资源和 Mirror 系统参数表：false。

资源调参本身合法，但当前事实源没有明确记录“正式资源为何覆盖默认”。

### D3 M6 完成状态冲突

- `Docs/07_M6...:3`：六批已实现，批次 6 待验收；
- `Docs/systems/UI_界面系统.md` 多处直接写“批次 6 已实现/已完成”。

本次实机仍有 14 条 warning，因此不建议把批次 6 标为已验收。

### D4 反射镜里程碑编号过期

- 当前决策已把反射镜顺延；
- `Docs/systems/_INDEX.md:9` 和 `Docs/systems/Mirror_镜子系统.md:122,156-158,244-246` 仍写“反射镜 M6”。

### D5 UI 系统文档混入旧原型

- `Docs/systems/UI_界面系统.md:23-30,43-49,119-127` 仍保留顶部资源栏、图例、小地图、Hint 和旧架构图；
- 与当前 M6 的左时间轴、底卡槽、右上全局、右中检视、右下经济时间布局冲突。

### D6 设计基线宣称唯一事实源，但未吸收后续增量决策

- `Docs/01_设计基线_已确认.md:3` 宣称“唯一事实源”；
- 多据点、限定 A*、正式 HUD、M6 路线调整等只在 DECISIONS / 07 文档。

建议明确：`01` 是初版冻结基线，`DECISIONS` 是之后的增量事实源；否则“唯一”表述不成立。

### D7 GDD 宣称 5 种资源产出，当前实现/系统文档只覆盖 3 种

- 设计：击杀、占领、生产建筑、时间增长、破坏地块；
- 当前 Resource 文档：时间、建筑、敌人掉落。

需要确认占领产出和清障产出是未实现、已取消，还是漏文档。

### D8 系统索引不完整

- `Docs/systems/_INDEX.md` 未登记 `TileElement_关卡地块元素.md`；
- GDD 的“15 个模块”也未反映后续 EdgeBarrier、Debug、TileElement 的独立化。

---

## 七、建议处理顺序（不代表已执行）

### 第一批：先清真实健壮性问题

1. 修复 `T` 切换网格的非原子状态；
2. 修复 TileObstacle 延迟释放的对象身份校验与信号断开；
3. 清理 14 条主场景 warning，并让测试入口把普通 warning 纳入失败条件；
4. 增加上述两个缺陷的定向回归测试。

### 第二批：定义模块边界，再拆代码

1. 先拍板“Composition Root 注入具体 Manager 是否允许”；
2. 明确跨模块端口：只读查询、命令、事件三类；
3. 优先拆 `Main.gd` 和 `MirrorManager.gd`；
4. 清理隐藏旧 HUD/调试逻辑。

### 第三批：补核心扩展契约

1. 落地统一 `ICopyable` / 注册表；
2. 给 feature flag 定义统一关闭、清理、恢复契约；
3. 给镜像重建增加总 payload、单格堆叠和单次工作量预算；
4. 落实 Enemy/Projectile 对象池；
5. 反射镜开始前补 `IMirrorEffect` 或等价策略边界。

### 第四批：统一事实源

1. 统一 `copy_chain_max` 与双观察侧正式值；
2. 明确 M6 批次 6 验收状态；
3. 更新反射镜里程碑编号与 systems 索引；
4. 清理 UI 旧原型段落；
5. 明确 5 种资源产出的去留。

---

## 八、最终判断

- **健壮性**：有成熟底座，但当前仍有两个应该先修的真实状态一致性问题。
- **参数化**：总体达标，是现有框架最健康的一项。
- **模块化**：目录拆分达标，依赖隔离不达标；这是当前最大的结构性债务。
- **可拓展**：一般系统较好，Mirror 核心扩展契约和性能预算未完成。
- **是否可以直接继续做反射镜**：不建议。先完成第一批健壮性修复，并拍板模块依赖边界，再进入反射镜实现更稳。
