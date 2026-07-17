# MirrorDefender · 变更日志（逐里程碑）

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
