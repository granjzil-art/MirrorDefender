# Mirror 塔防 · 协作规范（长期约束 · 严格执行）

> 本文件是项目的长期开发规范，用户已确认采纳并要求严格执行。任何代码/文档提交都必须遵守。
> 状态：生效中 · v1.2 · 2026-07-16

---

## 〇、引擎版本（硬性）
- **本项目使用 Godot 4.7**。所有 GDScript、场景(.tscn)、资源(.tres)、project.godot 一律按 **Godot 4.7** 规范书写。
- 场景文件不写已废弃的 `load_steps`；`ext_resource` 用 `path=`（uid 交引擎自动补）。
- 编写有类型返回值的函数（含 override）必须有显式 `return`（4.7 收紧）。
- 输入判断用 InputMap action 或按钮/键类型常量，不依赖 device id（4.7 mouse/keyboard device id 已改为常量）。
- **返回 Variant 的全局数学函数一律用带类型专用版**（硬规范，防 `INFERENCE_ON_VARIANT` 被当 error 中断加载）：`round→roundf/roundi`、`abs→absf/absi`、`floor→floorf/floori`、`ceil→ceilf/ceili`、`min→minf/mini`、`max→maxf/maxi`、`clamp→clampf/clampi`、`sign→signf/signi`、`snapped→snappedf/snappedi`。从 `Dictionary` 取值参与 `:=` 推断时，先落成带显式类型的局部变量（如 `var p: Vector3 = dict.pos`）。
- 官方升级指南与类参考已放在项目根 `Godot Engine 4.7 doc/`，写新 API 前以此为准。
- **每里程碑收尾必做真机验证**：本机无 Godot 时通过 Godot MCP `run_project → get_debug_output` 跑一次目标场景，确认 `errors: []`、无 Parser Error 后才算通过。静态自检查不出类型系统级编译错误。

---

## 一、四条硬性边界

### 1. 可拓展
- 会变的东西一律走**接口/策略**：地块形状(`ITileShape`)、镜子效果(`IMirrorEffect`)、可复制对象(`ICopyable`)、索敌(`ITargetingStrategy`)、攻击(`IAttackStrategy`)。
- 网格坐标封装，六边形/正方形/未来三角形只替换 Grid 层。
- 数据与逻辑分离。

### 2. 参数化
- 所有可调效果参数用 `@export` 暴露，**运行时可调**。
- 用 `@export_group` 分组、`@export_range` 限范围。
- **配置优先在编辑器内完成（硬规范）**：如无必要，不做外部配置表；直接在 Godot 检视面板 @export 配置。仅当数据量大到编辑器不便时才用数据资源(.tres)。

### 3. 模块化
- 目录即模块：`/systems/*`、`/units`、`/buildings`、`/ui`。
- 模块间用**信号/事件总线**通信，禁止跨模块硬持有引用。
- 每模块可 feature flag 开关。

### 4. 持续维护文档（每改代码即改文档）—— 系统文档即"项目实现文档"
- 每个系统一份文档，位于 `Docs/systems/`，结构：职责/分类/关键参数/关键架构/函数索引/已知限制。
- **改了代码的提交必须带上对应文档改动**，否则视为未完成。
- **实现文档标准（硬性，供人机快速检索定位）**：里程碑/功能实现后，对应文档的「关键架构 + 函数索引」必须同步到**实现级别**，包含：
  1. **文件构成表**：每个脚本文件 → `class_name` / 基类 / 角色（一句话）。**新增任何脚本文件都必须在此登记**（防遗漏，如 M1 曾漏记 GridRenderer/Main）。
  2. **函数索引带签名**：关键函数写明 `(参数: 类型) -> 返回类型` 与一句话职责；返回 Dictionary 的要写清键结构。
  3. **模块调用关系 / 数据流**：谁通过信号/接口调用谁，其它模块该从哪个入口访问本模块。
  4. **约定事实源**：坐标系、边/键规则、枚举等跨模块必读约定，落到文档而非只在代码注释里。
- 验收(DoD)时逐条自检上述 4 点；未同步实现文档 = 里程碑未完成。

---

## 二、设计评估四步流程（固化工作流，不跳步）
1. **理解对齐**：复述理解、列逻辑缺口/踩坑点/不明确处 → 提问，**不擅自改方案**。
2. **方案选型**：多解列优劣表 → 请拍板。
3. **执行计划 + 验收标准**：拆任务、定"怎样算做完"。
4. **验收交付**：按标准自检，告知【用法入口 / 文件结构 / 参数位置】。

## 三、代码与命名
- 类 `PascalCase`；变量/函数 `snake_case`；信号 `snake_case` 过去式(`unit_died`)；常量 `UPPER_CASE`。
- 一脚本一职责，>300 行考虑拆分。
- 无魔法数字，进 `@export` 或 `GameConfig`。

## 四、调试可视化（Gizmo）
- 核心系统提供可开关调试绘制：网格坐标、路径、索敌范围、镜面对称轴、激光反射路径。
- 全局 `DebugDraw` 开关统一控制。

## 五、数值外置与场景约定
- 平衡数值优先 @export；量大再走数据资源。
- KayKit 模型封装为 Prefab(.tscn)，逻辑挂根节点，美术可换不影响逻辑。
- 命名前缀：`Tile_`/`Bld_`/`Unit_`/`FX_`/`UI_`/`Mirror_`。

## 六、变更留痕
- `Docs/CHANGELOG.md`：每次功能落地追加一行（日期/模块/改动/影响面）。
- `Docs/DECISIONS.md`：重大方案决策记录（决策/理由/否决的备选）。

## 七、性能红线（镜子相关）
- 激光反射次数上限 `reflect_max`（默认 8）。
- 镜像可再被镜像；用 `copy_chain_max` 预留截断链式膨胀（详见设计基线与 Mirror 系统文档）。
- 大量单位用对象池。
- 激光光路每帧重算但走射线步进 + 上限。

## 八、Definition of Done（提交自检）
- [ ] 功能按验收标准可跑
- [ ] 新增参数已 @export 且分组
- [ ] 对应系统文档已更新
- [ ] CHANGELOG 已追加
- [ ] 无跨模块硬引用、无魔法数字
- [ ] 调试可视化可开关

## 九、协作节奏
- 一次一个模块，走完四步再进下一个。
- 先灰盒验证好玩，再套 KayKit 美术。
- **用户负责设计决策，助手负责实现与提案**：手感/数值/主题取向由用户拍板；纯工程实现直接做。

## 十、版本管理与提交（硬性）
- 项目 Git 远端：`origin = https://github.com/granjzil-art/MirrorDefender.git`，默认集成分支为 `main`。
- **每个功能或缺陷修复完成验收后必须自动提交并推送**；提交必须包含实现代码、对应系统文档和 `Docs/CHANGELOG.md`，不可积压到后续功能。
- 提交前依次执行：`git status` → `git diff --check` → 与本功能相关文件的 `git add` → `git commit` → `git push origin main`。远端领先时先 `git pull --rebase origin main`，不得用强推覆盖历史。
- 一项已验收功能/修复对应一个语义完整的提交。提交信息格式：`[模块] 动作摘要`，例如 `[Grid] 修复运行时网格渲染器注入`。
- 禁止提交 `.godot/`、`.workbuddy/`、`Godot Engine 4.7 doc/`、导出产物、运行时截图、密钥和机器本地配置。`HexTileset/` 是当前未接入工程的备用本地资产，正式引用前不提交；接入后以可追溯来源或 Git LFS 管理。第三方资产的压缩原包（`.zip`/`.rar`）不提交。
