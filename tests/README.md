# 自动化测试

健壮性基线测试直接使用 Godot 4.7.1 运行，不依赖第三方测试插件：

```powershell
& "E:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "E:\MirrorDefender副本" --script res://tests/robustness_baseline_test.gd
```

测试覆盖关卡预检与原子加载、运行时地块状态隔离、空几何、战斗和建筑生命周期、波次生成失败状态，以及当前 M4 示例关卡的时间线契约。任何断言失败都会以非零退出码结束。
