# 自动化测试

测试直接使用 Godot 4.7.1 运行，不依赖第三方测试插件。Windows 下统一入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_all_tests.ps1
```

可通过 `-GodotBinary <path>` 或环境变量 `GODOT_BIN` 指定 Godot。入口会运行全部 11 个套件，并同时检查非零退出码、`SCRIPT ERROR`、引擎 `ERROR` 和泄漏警告，避免脚本错误被测试自己的 `quit(0)` 遮蔽。

M6 批次 1 的正式卡槽、单卡单次放置、成功/资源/上限/非法格/非法边退出语义，以及 `暂停 > 战术慢放 > 2x > 1x` 时间优先级回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_ui_batch1_test.gd
```

M6 批次 2 的地块只读模型、实体/虚像/根源/耐久/朝向/元素动态状态、右侧滚动面板、选择/取消/慢放语义和三档分辨率布局回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/runtime_ui_batch2_test.gd
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
