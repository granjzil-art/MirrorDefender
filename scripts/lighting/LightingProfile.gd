@tool
## LightingProfile -- complete, reusable environment/light/display-case preset.
class_name LightingProfile
extends Resource

const ConfigValidator := preload("res://scripts/shared/ConfigurationValidator.gd")
const LightDefinitionScript := preload("res://scripts/lighting/LightDefinition.gd")
const DisplayCaseLightingDefinitionScript := preload("res://scripts/lighting/DisplayCaseLightingDefinition.gd")
const ReflectionProbeDefinitionScript := preload("res://scripts/lighting/ReflectionProbeDefinition.gd")

@export_group("Identity")
@export var profile_id: StringName = &"lighting_profile"
@export var display_name: String = "灯光方案"

@export_group("Environment")
@export var environment_template: Environment

@export_group("Lights")
@export var lights: Array[LightDefinitionScript] = []

@export_group("Display Case")
@export var display_case_lighting: DisplayCaseLightingDefinitionScript

@export_group("Reflection")
@export var reflection_probe: ReflectionProbeDefinitionScript

@export_group("Transition")
@export_range(0.0, 10.0, 0.05) var default_transition_duration: float = 0.6


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	ConfigValidator.require_text(errors, "灯光方案 ID", String(profile_id))
	ConfigValidator.require_text(errors, "灯光方案名称", display_name)
	if environment_template == null:
		errors.append("必须配置 Environment 模板")
	var used_ids: Dictionary = {}
	for index in range(lights.size()):
		var definition: LightDefinitionScript = lights[index]
		if definition == null:
			errors.append("灯光 %d 不能为空" % (index + 1))
			continue
		ConfigValidator.append_prefixed(errors, "灯光 %d" % (index + 1), definition.validate_configuration())
		if used_ids.has(definition.light_id):
			errors.append("灯光 ID 重复：%s" % String(definition.light_id))
		used_ids[definition.light_id] = true
	if display_case_lighting == null:
		errors.append("必须配置展示柜灯光参数")
	else:
		ConfigValidator.append_prefixed(errors, "展示柜", display_case_lighting.validate_configuration())
	if reflection_probe == null:
		errors.append("必须配置反射探针参数")
	else:
		ConfigValidator.append_prefixed(errors, "反射探针", reflection_probe.validate_configuration())
	return errors
