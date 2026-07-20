# 自动化测试

健壮性基线测试直接使用 Godot 4.7.1 运行，不依赖第三方测试插件：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/robustness_baseline_test.gd
```

测试覆盖关卡预检与原子加载、运行时地块状态隔离、空几何、战斗和建筑生命周期、波次生成失败状态，以及当前 M4 示例关卡的时间线契约。任何断言失败都会以非零退出码结束。

关卡几何标签、任意内部边屏障、双向/单向阻挡和远程敌人射程边界回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/directional_edge_barrier_test.gd
```

路径/出生点 1:1 命名、旧资源关联识别与波次自动绑定回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/path_spawn_pairing_test.gd
```

关卡地块元素、共享边建筑权限、HEX/SQUARE 手工路径换路、运行时换路信号/继续移动、高速跨格效果与路径资源不变性回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/tile_elements_and_rerouting_test.gd
```

飞行敌人分类/离地表现，以及尖刺、空洞、岩石换路、单体塔、激光和屏障的 `affects_airborne` 回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/airborne_effects_test.gd
```

M5 复制镜双网格几何、最近整格复制、放置预览、非占位叠加/严格占位开关、塔攻击同步、屏障共享耐久、地块覆盖效果、递归镜链与共享物理边占用回归测试：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/copy_mirror_test.gd
```
