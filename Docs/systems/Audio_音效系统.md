# 音效系统 · Audio

## 职责

为 UI 操作、建造、攻击、命中、死亡、胜利和失败提供统一的语义事件、混音、并发与替换入口。音效只消费既有公共信号，不参与伤害、资源、波次或暂停判定。

## 分类与听感

| 事件 ID | 默认听感 | 触发来源 |
|---|---|---|
| `ui_operation` | 短促双音点击 | 所有 `BaseButton.pressed`、滑条拖动完成 |
| `construction` | 低频落位 + 上扬晶体音 | 玩家付费建造、镜子放置、建筑升级 |
| `attack` | 快速下扫发射音 | 玩家投射物/脉冲发射、持续激光命中、敌人攻击 |
| `hit` | 噪声冲击 + 低频敲击 | 敌方目标扣血、敌人攻击建筑/基地 |
| `death` | 下坠消散音 | 敌人死亡、建筑被摧毁 |
| `victory` | 上行大调琶音 | `WaveManager.victory` |
| `defeat` | 下行低音序列 | `WaveManager.defeat` |

默认音色由运行时程序合成，因此项目在没有外部音频素材时也可立即试听。美术/音频制作只需在 `resources/audio/DefaultSoundEffects.tres` 的七个 `AudioStream` 插槽中替换 WAV/OGG；空插槽继续使用程序音。

## 关键参数

- `SoundEffectLibrary`：每类音效的资源、独立音量与随机音高范围。
- 播放池：4 个 UI 2D 播放器、12 个世界 3D 播放器；池满时循环复用，避免战斗中动态创建节点。
- 世界声最大距离：48 世界单位，`unit_size=5`，接入 `SFX` 总线；UI 接入 `UI` 总线，两者最终受现有 Master 音量控制。
- 防叠音：UI 25ms、攻击 70ms、命中 45ms、死亡 70ms、结算 1000ms；攻击与建造按来源节流，命中/死亡按全局节流。

## 关键架构

```text
UI BaseButton ───────────────┐
BuildingManager / MirrorManager ─┤
CombatManager / CombatTarget ├─> SoundEffects (autoload) ─> UI/SFX 播放池 ─> Master
EnemyUnit ───────────────────┤
WaveManager ─────────────────┘
```

`BuildingManager.building_constructed` 与 `MirrorManager.mirror_constructed` 只表示玩家成功建造，避免关卡初始陈列、重载和战斗数据热重建误播建造声。`Main._on_level_loaded()` 在装配完成后重新绑定音效系统，使初始建筑能参与开火音效，但不会触发建造音效。

## 公共接口

- `SoundEffects.play_ui(event_id)`：播放非空间 UI/结算音效。
- `SoundEffects.play_world(event_id, position, source)`：播放空间音效，`source` 用于攻击/建造节流。
- `SoundEffects.play_event(event_id, position, spatial, source_id)`：统一底层入口。
- `SoundEffects.bind_gameplay(building_manager, combat_manager, wave_manager, mirror_manager)`：绑定当前战局；重复调用会先解除旧战局。
- `SoundEffects.register_ui_root(node)`：递归接入运行时新建的按钮和滑条。
- `SoundEffects.set_library(library)`：运行时替换整套音效库。
- 按钮元数据 `sfx_disabled=true` 可静音单个按钮；`sfx_event=<StringName>` 可覆盖其事件 ID。

## 边界

- 程序音是可运行的基准素材，不写入磁盘，不增加二进制资源体积；正式素材替换不需要改代码。
- 高频持续伤害仍逐帧结算，但音效按节流间隔播放，不改变伤害次数。
- 当前只提供 SFX 与 UI，总线未加入 BGM、环境声、混响区域或动态音乐层。
