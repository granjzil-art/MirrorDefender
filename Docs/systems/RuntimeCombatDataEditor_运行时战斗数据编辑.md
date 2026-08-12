# 运行时战斗数据编辑器

## 使用方式

- 从 Godot 编辑器运行游戏，按 `F2` 打开独立原生窗口。
- 建筑页选择建筑类型和等级。修改数值后，相同类型、相同等级的现有建筑会在原位置和朝向重建。
- 敌人页修改工作数据。已生成敌人保持出生快照；后续正式出怪和测试敌人读取新值。
- 测试敌人页选择类型、数量、间隔和当前关卡路径，可停止后续生成或清理全部测试敌人。
- “永久保存”或 `Ctrl+S` 写回原 `.tres`；“放弃修改”从磁盘重新加载。关闭脏窗口会显示保存、放弃、取消三选一。

正式导出版本不创建数据编辑窗口。

## 数据边界

```text
.tres（唯一持久源）
  -> RuntimeCombatDataEditSession 工作副本
       -> BuildingManager 类型覆盖 -> 当前建筑重建 / 后续建造升级
       -> WaveManager 敌人解析器   -> 后续正式出怪 / 测试出怪出生快照
  -> 永久保存：工作副本写回 .tres 后重新加载
  -> 放弃修改：直接重新加载 .tres
```

- 建筑工作数据仍是 `BuildingDefinition.levels[level]` 中唯一的 `BuildingLevelStats`，不存在 RuntimeStats 或 Override 存档。
- `BuildingManager.export_initial_placements()` 强制导出正式 Definition，运行时工作副本不会被嵌进 LevelResource。
- 脉冲最大反射数已进入逐级 `BuildingLevelStats.pulse_laser_reflect_max`；Definition 根字段仅作旧资源兼容。
- 投射物模型、建筑模型和敌人模型不在运行时编辑白名单中。
- 敌人 `base_damage` 已从运行时编辑白名单和窗口移除；漏怪惩罚由 `WaveManager.enemy_leak_health_penalty` 全局统一为 1。

## 建筑刷新事务

`Building.configure_runtime_level_data()` 和边建筑对应接口显式接收工作 `level_data`，不查询旧等级数据。`BuildingManager.rebuild_runtime_buildings()` 完成以下事务：

1. 用工作 Definition 和目标等级数据创建新实例。
2. 保留格子/物理边、位置、朝向、类型和等级。
3. 原子替换 Tile occupant 或 EdgeOccupancyRegistry。
4. 取消旧建筑拥有的普通投射物、导弹和脉冲光束，并重置持续光束。
5. 更新生命周期信号、镜子投影连接、选择引用和建筑产出汇总。

耐久、冷却、锁定目标与持续攻击状态按新建筑重新初始化。

## 敌人和测试批次

WaveManager 在每次正式或测试生成时深复制解析后的 EnemyDefinition。这样即使敌人投射物速度等字段在发射时读取 Definition，已出生单位仍不会随编辑变化。

测试敌人：

- 使用普通路径、绕路、地块效果、索敌、死亡奖励和统一的 1 点漏怪惩罚。
- 单独存入 `_test_units`，不进入 `_active_units` 和 `_unit_wave_indices`。
- 不阻塞波次完成或胜利；切关、配置错误和基地失败时清理。
- 独立清理时只移除测试敌人及其敌方投射物，不影响正式波次单位。

## 主要实现

- `scripts/combat/RuntimeCombatDataEditSession.gd`：资源发现、工作副本、白名单、保存和放弃。
- `scripts/ui/RuntimeCombatDataEditorWindow.gd`：原生窗口、动态参数表单和脏状态交互。
- `scripts/combat/RuntimeTestEnemySpawner.gd`：数量/间隔批次控制。
- `scripts/building/BuildingManager.gd`：有效 Definition 解析和原位重建。
- `scripts/wave/WaveManager.gd`：敌人出生快照和测试敌人隔离列表。
- `tests/runtime_combat_data_editor_test.gd`：保存回读、分级隔离、建筑重建、禁止模型编辑、敌人快照、波次隔离、奖励与基地伤害回归。
