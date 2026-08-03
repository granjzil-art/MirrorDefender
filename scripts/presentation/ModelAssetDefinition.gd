@tool
## Shared data contract for an optional runtime 3D presentation asset.
##
## runtime_scale is applied on a wrapper node. The instantiated scene keeps its
## authored position, rotation, and scale unchanged beneath that wrapper.
class_name ModelAssetDefinition
extends Resource

@export_group("Model")
@export var scene: PackedScene
@export var runtime_scale: Vector3 = Vector3.ONE


func is_configured() -> bool:
	return scene != null


func instantiate_model(instance_name: StringName = &"ModelAssetRoot") -> Node3D:
	if scene == null or not scene.can_instantiate():
		return null
	var raw_instance: Node = scene.instantiate()
	if raw_instance == null:
		return null
	if not raw_instance is Node3D:
		raw_instance.free()
		return null
	if not _find_duplicate_sibling_name(raw_instance).is_empty():
		raw_instance.free()
		return null
	var runtime_root := Node3D.new()
	runtime_root.name = instance_name
	runtime_root.scale = runtime_scale
	runtime_root.add_child(raw_instance)
	return runtime_root


func validate_configuration() -> Array[String]:
	var errors: Array[String] = []
	if (
		not is_finite(runtime_scale.x)
		or not is_finite(runtime_scale.y)
		or not is_finite(runtime_scale.z)
		or runtime_scale.x <= 0.0
		or runtime_scale.y <= 0.0
		or runtime_scale.z <= 0.0
	):
		errors.append("运行时模型缩放必须为有限正数")
	if scene == null:
		return errors
	if not scene.can_instantiate():
		errors.append("模型场景无法实例化")
		return errors
	var raw_instance: Node = scene.instantiate()
	if raw_instance == null:
		errors.append("模型场景实例化结果为空")
		return errors
	if not raw_instance is Node3D:
		errors.append("模型场景根节点必须继承 Node3D")
	var duplicate_path := _find_duplicate_sibling_name(raw_instance)
	if not duplicate_path.is_empty():
		errors.append("模型场景存在同名兄弟节点：%s" % duplicate_path)
	raw_instance.free()
	return errors


func _find_duplicate_sibling_name(parent: Node) -> String:
	var child_names: Dictionary = {}
	for child in parent.get_children():
		var child_name := String(child.name)
		if child_names.has(child_name):
			return "%s/%s" % [String(parent.get_path()), child_name]
		child_names[child_name] = true
		var nested_duplicate := _find_duplicate_sibling_name(child)
		if not nested_duplicate.is_empty():
			return nested_duplicate
	return ""
