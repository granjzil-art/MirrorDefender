@tool
## Editable stats and greybox presentation for one M4 enemy type.
class_name EnemyDefinition
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")

enum ReflectionPattern {
	NONE,
	FRONT,
	LEFT_RIGHT,
	FOUR_SIDES,
}

@export_group("Identity")
@export var enemy_id: StringName = &"grunt"
@export var display_name: String = "步兵"

@export_group("Stats")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.1, 100.0, 0.1, "or_greater") var move_speed: float = 1.5
@export_range(0.0, 100000.0, 0.1, "or_greater") var armor: float = 0.0
## Legacy serialized value. WaveManager applies one shared leak penalty instead.
@export_range(1.0, 100000.0, 1.0, "or_greater") var base_damage: float = 10.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var reward: float = 5.0
@export_range(0.05, 5.0, 0.05, "or_greater") var hit_radius: float = 0.28

@export_group("Movement")
@export var is_airborne: bool = false
## Added to every authored path point when is_airborne is enabled.
@export_range(0.0, 10.0, 0.05, "or_greater") var flight_height: float = 0.8
@export var is_elite: bool = false
## Zero keeps the normal continuous movement behavior. Positive values alternate
## between this much actual path movement time and movement_pause_duration.
@export_range(0.0, 60.0, 0.05, "or_greater") var movement_active_duration: float = 0.0
@export_range(0.0, 60.0, 0.05, "or_greater") var movement_pause_duration: float = 0.0

@export_group("Support Aura")
## Measured in grid cells. Zero disables the aura. The caster never buffs itself;
## overlapping auras use only the strongest bonus.
@export_range(0.0, 20.0, 0.05, "or_greater") var armor_aura_radius: float = 0.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var armor_aura_bonus: float = 0.0

@export_group("Projectile Reflection")
@export var reflection_pattern: ReflectionPattern = ReflectionPattern.NONE
## Side length and height are measured in grid cells. The four patterns use
## vertical finite surfaces only; there is no top or bottom reflective face.
@export_range(0.1, 5.0, 0.05, "or_greater") var reflection_side_length: float = 1.0
@export_range(0.1, 5.0, 0.05, "or_greater") var reflection_height: float = 2.0
## Every configured side owns this much independent durability.
@export_range(1.0, 100000.0, 1.0, "or_greater") var reflection_max_durability: float = 100.0
## Optional mirror model, instantiated separately from the enemy body model.
## Empty uses the programmatic reflective panel fallback.
@export var reflection_model_asset: ModelAssetDefinition

@export_group("Attack")
@export_range(0.0, 100000.0, 0.1, "or_greater") var attack_damage: float = 10.0
@export_range(0.01, 100.0, 0.01, "or_greater") var attacks_per_second: float = 1.0
## Measured in grid cells and converted to world distance when the unit spawns.
@export_range(0.1, 100.0, 0.1, "or_greater") var attack_range: float = 0.65
## Zero performs an immediate melee hit; positive values spawn a projectile.
@export_range(0.0, 100.0, 0.1, "or_greater") var projectile_speed: float = 0.0
@export_range(0.1, 5.0, 0.05, "or_greater") var projectile_length: float = 0.55
@export_range(0.02, 2.0, 0.01, "or_greater") var projectile_width: float = 0.08
@export var projectile_model_asset: ModelAssetDefinition

@export_group("Presentation")
@export var ui_icon: Texture2D
@export var model_asset: ModelAssetDefinition
@export var body_color: Color = Color(0.84, 0.20, 0.24, 1.0)
@export_range(0.1, 3.0, 0.05, "or_greater") var body_height: float = 0.8
@export var attack_color: Color = Color(1.0, 0.36, 0.18, 1.0)

@export_group("Hit Feedback")
@export var hit_particle_color: Color = Color(1.0, 0.035, 0.055, 1.0)
@export_range(0.0, 32.0, 0.1) var hit_particle_brightness: float = 4.0
@export_range(0.005, 1.0, 0.005) var hit_particle_size: float = 0.055
## Zero disables the effect for this enemy type.
@export_range(0, 128, 1) var hit_particle_count: int = 12

## Serialized compatibility for old EnemyDefinition resources.
@export_storage var visual_scene: PackedScene


func get_model_asset() -> ModelAssetDefinition:
	if model_asset != null:
		return model_asset
	if visual_scene == null:
		return null
	var legacy_asset := ModelAssetDefinition.new()
	legacy_asset.scene = visual_scene
	return legacy_asset


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "敌人 ID", String(enemy_id))
	ConfigValidator.require_text(errors, "敌人显示名", display_name)
	ConfigValidator.require_number(errors, "最大生命", max_hp, 0.0, INF, false)
	ConfigValidator.require_number(errors, "移动速度", move_speed, 0.0, INF, false)
	ConfigValidator.require_number(errors, "护甲", armor, 0.0)
	ConfigValidator.require_number(errors, "据点伤害", base_damage, 0.0, INF, false)
	ConfigValidator.require_number(errors, "死亡资源", reward, 0.0)
	ConfigValidator.require_number(errors, "受击半径", hit_radius, 0.0, INF, false)
	ConfigValidator.require_number(errors, "飞行高度", flight_height, 0.0)
	ConfigValidator.require_number(errors, "攻击伤害", attack_damage, 0.0)
	ConfigValidator.require_number(errors, "每秒攻击次数", attacks_per_second, 0.0, INF, false)
	ConfigValidator.require_number(errors, "攻击射程", attack_range, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物速度", projectile_speed, 0.0)
	ConfigValidator.require_number(errors, "投射物长度", projectile_length, 0.0, INF, false)
	ConfigValidator.require_number(errors, "投射物宽度", projectile_width, 0.0, INF, false)
	ConfigValidator.require_number(errors, "模型高度", body_height, 0.0, INF, false)
	ConfigValidator.require_color(errors, "敌人颜色", body_color)
	ConfigValidator.require_color(errors, "攻击颜色", attack_color)
	ConfigValidator.require_color(errors, "受击粒子颜色", hit_particle_color)
	ConfigValidator.require_number(errors, "受击粒子亮度", hit_particle_brightness, 0.0, 32.0)
	ConfigValidator.require_number(errors, "受击粒子大小", hit_particle_size, 0.005, 1.0)
	ConfigValidator.require_integer_range(errors, "受击粒子数量", hit_particle_count, 0, 128)
	ConfigValidator.require_number(errors, "精英移动时长", movement_active_duration, 0.0)
	ConfigValidator.require_number(errors, "精英停顿时长", movement_pause_duration, 0.0)
	ConfigValidator.require_number(errors, "护甲光环范围", armor_aura_radius, 0.0)
	ConfigValidator.require_number(errors, "护甲光环加成", armor_aura_bonus, 0.0)
	ConfigValidator.require_integer_range(
		errors,
		"反射面模式",
		reflection_pattern,
		ReflectionPattern.NONE,
		ReflectionPattern.FOUR_SIDES
	)
	ConfigValidator.require_number(errors, "反射体边长", reflection_side_length, 0.0, INF, false)
	ConfigValidator.require_number(errors, "反射体高度", reflection_height, 0.0, INF, false)
	ConfigValidator.require_number(errors, "反射面耐久", reflection_max_durability, 0.0, INF, false)
	var effective_model_asset := get_model_asset()
	if effective_model_asset != null:
		ConfigValidator.append_prefixed(errors, "敌人模型", effective_model_asset.validate_configuration())
	if projectile_model_asset != null:
		ConfigValidator.append_prefixed(errors, "敌人投射物模型", projectile_model_asset.validate_configuration())
	if reflection_model_asset != null:
		ConfigValidator.append_prefixed(errors, "敌人反射面模型", reflection_model_asset.validate_configuration())
	return errors
