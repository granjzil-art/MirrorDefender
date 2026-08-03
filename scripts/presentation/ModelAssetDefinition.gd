@tool
## Shared data contract for an optional runtime 3D presentation asset.
##
## runtime_scale is applied on a wrapper node. Context-specific placement then
## grounds or fits the authored visual bounds without rewriting the source scene.
class_name ModelAssetDefinition
extends Resource

const BOUNDS_EPSILON: float = 0.00001

@export_group("Model")
@export var scene: PackedScene
@export var runtime_scale: Vector3 = Vector3.ONE

@export_group("Alignment Overrides")
## Optional bottom-center marker relative to the instantiated scene root.
## Empty uses the combined render-mesh AABB bottom center.
@export var ground_anchor_path: NodePath
## Optional authored minimum/maximum marker pair. Both must be configured
## together; empty paths use the combined render-mesh AABB.
@export var fit_min_anchor_path: NodePath
@export var fit_max_anchor_path: NodePath

var _cached_scene_id: int = 0
var _cached_bounds_valid: bool = false
var _cached_bounds: AABB


func is_configured() -> bool:
	return scene != null


func instantiate_model(instance_name: StringName = &"ModelAssetRoot") -> Node3D:
	var raw_instance := _instantiate_raw_model()
	return _wrap_raw_model(raw_instance, instance_name) if raw_instance != null else null


## Centers the authored bottom contact point on the gameplay origin while
## preserving authored size and runtime_scale.
func instantiate_grounded_model(instance_name: StringName = &"ModelAssetRoot") -> Node3D:
	var raw_instance := _instantiate_raw_model()
	if raw_instance == null:
		return null
	var anchor_result := _resolve_ground_anchor(raw_instance)
	if not bool(anchor_result.get("valid", false)):
		raw_instance.free()
		return null
	var runtime_root := _wrap_raw_model(raw_instance, instance_name)
	var alignment_root := runtime_root.get_node("ModelAlignment") as Node3D
	var anchor: Vector3 = anchor_result.get("point", Vector3.ZERO)
	alignment_root.position = -anchor
	return runtime_root


## Maps the complete authored visual bounds to one authoritative logical AABB.
## Fitted instances normalize their runtime wrapper to Vector3.ONE, so legacy
## scale values cannot make a terrain voxel or projectile exceed its gameplay
## dimensions.
func instantiate_fitted_model(
	instance_name: StringName,
	target_bounds: AABB
) -> Node3D:
	if not _is_valid_fit_bounds(target_bounds):
		return null
	var raw_instance := _instantiate_raw_model()
	if raw_instance == null:
		return null
	var source_result := _resolve_fit_bounds(raw_instance)
	if not bool(source_result.get("valid", false)):
		raw_instance.free()
		return null
	var source_bounds: AABB = source_result.get("bounds", AABB())
	if not _is_valid_fit_bounds(source_bounds):
		raw_instance.free()
		return null
	var runtime_root := _wrap_raw_model(raw_instance, instance_name)
	runtime_root.scale = Vector3.ONE
	var alignment_root := runtime_root.get_node("ModelAlignment") as Node3D
	var fit_scale := Vector3(
		target_bounds.size.x / source_bounds.size.x,
		target_bounds.size.y / source_bounds.size.y,
		target_bounds.size.z / source_bounds.size.z
	)
	alignment_root.scale = fit_scale
	alignment_root.position = target_bounds.position - source_bounds.position * fit_scale
	return runtime_root


## Read-only editor/runtime diagnostic. Returns
## {valid: bool, bounds: AABB}; bounds include authored node transforms but not
## runtime_scale or gameplay placement.
func get_authored_visual_bounds() -> Dictionary:
	var raw_instance := _instantiate_raw_model()
	if raw_instance == null:
		return {"valid": false, "bounds": AABB()}
	var result := _resolve_fit_bounds(raw_instance)
	raw_instance.free()
	return result


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
		raw_instance.free()
		return errors
	var duplicate_path := _find_duplicate_sibling_name(raw_instance)
	if not duplicate_path.is_empty():
		errors.append("模型场景存在同名兄弟节点：%s" % duplicate_path)
	if ground_anchor_path != NodePath(""):
		var ground_result := _resolve_marker_point(raw_instance, ground_anchor_path)
		if not bool(ground_result.get("valid", false)):
			errors.append("接地锚点路径无效：%s" % String(ground_anchor_path))
	var has_fit_min := fit_min_anchor_path != NodePath("")
	var has_fit_max := fit_max_anchor_path != NodePath("")
	if has_fit_min != has_fit_max:
		errors.append("拟合最小/最大锚点必须同时配置")
	var bounds_result := _resolve_fit_bounds(raw_instance)
	if not bool(bounds_result.get("valid", false)):
		errors.append("模型场景没有可用于对齐的有效可视包围盒")
	elif not _is_valid_fit_bounds(bounds_result.get("bounds", AABB())):
		errors.append("模型对齐包围盒三轴尺寸必须为有限正数")
	raw_instance.free()
	return errors


func _instantiate_raw_model() -> Node3D:
	if scene == null or not scene.can_instantiate():
		return null
	var raw_instance: Node = scene.instantiate()
	if raw_instance == null or not raw_instance is Node3D:
		if raw_instance != null:
			raw_instance.free()
		return null
	if not _find_duplicate_sibling_name(raw_instance).is_empty():
		raw_instance.free()
		return null
	return raw_instance as Node3D


func _wrap_raw_model(raw_instance: Node3D, instance_name: StringName) -> Node3D:
	var runtime_root := Node3D.new()
	runtime_root.name = instance_name
	runtime_root.scale = runtime_scale
	var alignment_root := Node3D.new()
	alignment_root.name = "ModelAlignment"
	runtime_root.add_child(alignment_root)
	alignment_root.add_child(raw_instance)
	return runtime_root


func _resolve_ground_anchor(raw_instance: Node3D) -> Dictionary:
	if ground_anchor_path != NodePath(""):
		return _resolve_marker_point(raw_instance, ground_anchor_path)
	var bounds_result := _get_auto_visual_bounds(raw_instance)
	if not bool(bounds_result.get("valid", false)):
		return {"valid": false, "point": Vector3.ZERO}
	var bounds: AABB = bounds_result.get("bounds", AABB())
	return {
		"valid": true,
		"point": Vector3(
			bounds.position.x + bounds.size.x * 0.5,
			bounds.position.y,
			bounds.position.z + bounds.size.z * 0.5
		),
	}


func _resolve_fit_bounds(raw_instance: Node3D) -> Dictionary:
	var has_fit_min := fit_min_anchor_path != NodePath("")
	var has_fit_max := fit_max_anchor_path != NodePath("")
	if not has_fit_min and not has_fit_max:
		return _get_auto_visual_bounds(raw_instance)
	if has_fit_min != has_fit_max:
		return {"valid": false, "bounds": AABB()}
	var minimum_result := _resolve_marker_point(raw_instance, fit_min_anchor_path)
	var maximum_result := _resolve_marker_point(raw_instance, fit_max_anchor_path)
	if not bool(minimum_result.get("valid", false)) or not bool(maximum_result.get("valid", false)):
		return {"valid": false, "bounds": AABB()}
	var first: Vector3 = minimum_result.get("point", Vector3.ZERO)
	var second: Vector3 = maximum_result.get("point", Vector3.ZERO)
	var minimum := first.min(second)
	var maximum := first.max(second)
	return {"valid": true, "bounds": AABB(minimum, maximum - minimum)}


func _resolve_marker_point(raw_instance: Node3D, path: NodePath) -> Dictionary:
	var marker := raw_instance.get_node_or_null(path) as Node3D
	if marker == null:
		return {"valid": false, "point": Vector3.ZERO}
	var chain: Array[Node3D] = []
	var current: Node = marker
	while current != null:
		if current is Node3D:
			chain.push_front(current as Node3D)
		if current == raw_instance:
			break
		current = current.get_parent()
	if current != raw_instance:
		return {"valid": false, "point": Vector3.ZERO}
	var combined := Transform3D.IDENTITY
	for node in chain:
		combined = combined * node.transform
	return {"valid": true, "point": combined.origin}


func _get_auto_visual_bounds(raw_instance: Node3D) -> Dictionary:
	var scene_id := scene.get_instance_id() if scene != null else 0
	if _cached_bounds_valid and _cached_scene_id == scene_id:
		return {"valid": true, "bounds": _cached_bounds}
	var state := {"valid": false, "bounds": AABB()}
	_collect_visual_bounds(raw_instance, Transform3D.IDENTITY, state)
	_cached_scene_id = scene_id
	_cached_bounds_valid = bool(state.get("valid", false))
	_cached_bounds = state.get("bounds", AABB())
	return {"valid": _cached_bounds_valid, "bounds": _cached_bounds}


func _collect_visual_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if not bool(node.get_meta("exclude_from_model_bounds", false)):
		var local_bounds := AABB()
		var has_local_bounds := false
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			local_bounds = (node as MeshInstance3D).get_aabb()
			has_local_bounds = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			local_bounds = (node as MultiMeshInstance3D).get_aabb()
			has_local_bounds = true
		if has_local_bounds:
			var transformed_bounds := current_transform * local_bounds
			if bool(state.get("valid", false)):
				var existing: AABB = state.get("bounds", AABB())
				state["bounds"] = existing.merge(transformed_bounds)
			else:
				state["valid"] = true
				state["bounds"] = transformed_bounds
	for child in node.get_children():
		_collect_visual_bounds(child, current_transform, state)


func _is_valid_fit_bounds(bounds: AABB) -> bool:
	return (
		bounds.position.is_finite()
		and bounds.size.is_finite()
		and bounds.size.x > BOUNDS_EPSILON
		and bounds.size.y > BOUNDS_EPSILON
		and bounds.size.z > BOUNDS_EPSILON
	)


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
