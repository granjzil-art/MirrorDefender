# 自动化测试

测试直接使用 Godot 4.7.1 运行，不依赖第三方测试插件。Windows 下统一入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_all_tests.ps1
```

七类语义音效的程序回退素材、UI 接入、玩法信号映射与静音测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/sound_effect_system_test.gd
```

可通过 `-GodotBinary <path>` 或环境变量 `GODOT_BIN` 指定 Godot。入口会运行全部 57 个套件，并同时检查非零退出码、`SCRIPT ERROR`、引擎 `ERROR` 和泄漏警告，避免脚本错误被测试自己的 `quit(0)` 遮蔽。

导弹塔正式资源、箭塔/导弹塔对空优先、目标标记跟随、无碰撞绕圈、追踪/朝向飞行、对空范围爆炸、反射、Stuff 引爆、拖尾与拆塔后续飞回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/missile_tower_test.gd
```

持续激光塔的正式参数、主轴与双平移流动噪声正弦光丝、可调颜色/宽度/发光、移动逻辑终点、阻挡消失后续长、反射光路、有限穿透、寒冷、2/3 级终点爆发与冻结回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/laser_tower_status_test.gd
```

持续激光主轴、双正弦光丝、噪声幅度和终点衔接的手动 Forward+ 截图：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --path "E:\MirrorDefender副本" --script res://tests/continuous_laser_visual_capture.gd
```

输出：`outputs/laser_visual/continuous_laser_wave_preview.png`。

正式敌人原模型与寒冷状态深蓝表面 Shader 的手动 Forward+ 对照截图：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --path "E:\MirrorDefender副本" --script res://tests/cold_surface_visual_capture.gd
```

输出：`outputs/laser_visual/cold_surface_shader_preview.png`。

脉冲镭射塔的独立类型/正式资源、无目标周期开火、保持入口单次伤害、反射分段多次命中、共享总射程、七色循环和 Stuff 截断回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/pulse_laser_tower_test.gd
```

Stuff 统一球形对追踪弹、方向穿透弹、复制弹、敌方弹、旧持续激光与弹道预览的统一阻挡回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/ballistic_stuff_blocking_test.gd
```

箭塔/导弹塔/钉锤放置蓝色索敌圈，以及攻击建筑放置/调整弹道、旋转即时刷新、反射共享射程、钉锤多方向、持续激光完整规划光路与真实光束宽度回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/projectile_trajectory_preview_test.gd
```

体素 Terrain / Stuff 关卡编辑器的旧Tile单向导入、独立刷子、同格多Stuff、S1斜坡、连续斜坡共享边与体素层自动规约、网格重建分页边界、合法分割布局与隐藏零尺寸画布生命周期回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/terrain_stuff_editor_test.gd
```

体素 Terrain 与独立 Stuff 运行时、加载回滚、多 Stuff 权限/效果、旧关卡只读迁移和复制镜整格复制回归：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/terrain_runtime_test.gd
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/stuff_runtime_test.gd
```

M6 批次 1 的程序化镜面卡槽、透明建筑主体层、动态标题/费用与选中/不可用状态，单卡单次放置、成功/资源/上限/非法格/非法边退出语义，以及 `暂停 > 战术慢放 > 2x > 1x` 时间优先级回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_ui_batch1_test.gd
```

双模式卡槽 Forward+ 手动渲染捕获（输出 `outputs/ui/procedural_build_cards.png` 和 `outputs/ui/full_art_build_cards.png`）：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --path "E:\MirrorDefender副本" --script res://tests/build_card_visual_capture.gd
```

M6 批次 2 的地块只读模型、实体/虚像/根源/耐久/朝向/元素动态状态、右侧滚动面板、选择/取消/慢放语义和三档分辨率布局回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_ui_batch2_test.gd
```

M6 批次 3 的全局信息信号、资源滚动/独立弹字、时间优先级、暂停模态、设置持久化、关卡深重载和三档分辨率回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_ui_batch3_test.gd
```

右侧详情的对象级/字段级显示开关、默认兼容、可编辑名称和功能说明、自适应紧凑排版及全部正式定义配置回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_inspection_configuration_test.gd
```

行为测试使用 `tests/fixtures/` 中的内存配置，不读取策划可调的正式平衡值；正式 `.tres` 只做类型、加载和 `validate_configuration()` 冒烟检查。

健壮性测试覆盖配置校验、关卡预检与装配失败回滚、运行时地块状态隔离、高度感知拾取、空几何、战斗/建筑生命周期和波次生成失败状态：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/robustness_baseline_test.gd
```

关卡几何标签、任意内部边屏障、双向/单向阻挡和远程敌人射程边界回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/directional_edge_barrier_test.gd
```

路径/出生点 1:1 命名、旧资源关联识别与波次自动绑定回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/path_spawn_pairing_test.gd
```

关卡地块元素、逐格石头耐久/清障建筑权限、共享边建筑权限、HEX/SQUARE 手工路径换路、无路近战/远程攻击、已释放阻挡目标清理、高速跨格效果与路径资源不变性回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/tile_elements_and_rerouting_test.gd
```

飞行敌人分类/离地表现，以及尖刺、空洞、岩石换路、单体塔、激光和屏障的 `affects_airborne` 回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/airborne_effects_test.gd
```

M5 复制镜双网格几何、最近整格复制、放置预览、非占位叠加/严格占位开关、塔攻击同步、屏障/石头共享源耐久、同格屏障优先与摧毁后石头重解析、地块覆盖效果、递归镜链与共享物理边占用回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/copy_mirror_test.gd
```

`tests/fixtures/TestDefinitionFactory.gd` 提供稳定的建筑与复制镜行为夹具；`RejectingTileManager.gd` 只用于模拟预检后装配仍失败的回滚路径。二者都不是正式玩法资源。
