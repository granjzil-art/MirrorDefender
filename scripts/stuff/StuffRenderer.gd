## StuffRenderer -- presentation-only renderer for independent Stuff instances.
class_name StuffRenderer
extends Node3D

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Fallback Geometry")
@export_range(0.05, 0.6, 0.01) var overlap_slot_radius_ratio: float = 0.16
@export_range(0.1, 0.9, 0.01) var obstacle_width_ratio: float = 0.52
@export_range(0.1, 1.5, 0.01) var obstacle_height_ratio: float = 0.66

var _grid: GridManager
var _stuff_manager: StuffManager
var _effect_visual_state_resolver: Callable
var _visuals: Dictionary = {}


func configure(grid_manager: GridManager, stuff_manager: StuffManager) -> void:
	_disconnect_manager()
	_grid = grid_manager
	_stuff_manager = stuff_manager
	if _stuff_manager != null:
		_stuff_manager.stuff_loaded.connect(_on_stuff_loaded)
		_stuff_manager.stuff_cleared.connect(_on_stuff_cleared)
		_stuff_manager.stuff_changed.connect(_on_stuff_changed)
		_stuff_manager.set_visual_snapshot_resolver(Callable(self, "create_stuff_visual_snapshot"))
	_rebuild_all()


func set_effect_visual_state_resolver(value: Callable) -> void:
	_effect_visual_state_resolver = value
	_rebuild_all()


func refresh_effect_visual(state_key: String = "", _source_cell: Vector3i = Vector3i.ZERO, _fill_ratio: float = 0.0) -> void:
	if _stuff_manager == null:
		return
	if state_key.begins_with("stuff:"):
		_rebuild_placement(StringName(state_key.trim_prefix("stuff:")))
	else:
		_rebuild_all()


## Returns a behaviorless local-space snapshot. MirrorProjection applies the
## source runtime transform and every reflection in the chain.
func create_stuff_visual_snapshot(placement_id: StringName) -> Node3D:
	var runtime := _stuff_manager.get_stuff(placement_id) if _stuff_manager != null else null
	return _build_visual(runtime) if runtime != null else null


## Behaviorless local visual used by the runtime authoring preview. The caller
## owns the returned node and applies validation overlays/world transform.
func create_preview_visual(runtime: StuffRuntime) -> Node3D:
	return _build_visual(runtime)


func _rebuild_all() -> void:
	_clear_visuals()
	if not feature_enabled or _stuff_manager == null:
		return
	for runtime in _stuff_manager.get_all_stuff():
		_add_runtime_visual(runtime)
	_stuff_manager.set_visual_snapshot_resolver(Callable(self, "create_stuff_visual_snapshot"))


func _rebuild_cell(cell: Vector3i) -> void:
	if _stuff_manager == null:
		return
	var valid_ids: Dictionary = {}
	for runtime in _stuff_manager.get_stuff_at(cell):
		valid_ids[runtime.placement_id] = true
		_rebuild_placement(runtime.placement_id)
	for raw_id in _visuals.keys():
		var placement_id: StringName = raw_id
		var visual: Node3D = _visuals[placement_id]
		if visual != null and is_instance_valid(visual) and visual.has_meta("stuff_cell") and visual.get_meta("stuff_cell") == cell and not valid_ids.has(placement_id):
			_remove_visual(placement_id)


func _rebuild_placement(placement_id: StringName) -> void:
	_remove_visual(placement_id)
	var runtime := _stuff_manager.get_stuff(placement_id) if _stuff_manager != null else null
	if runtime != null and feature_enabled:
		_add_runtime_visual(runtime)


func _add_runtime_visual(runtime: StuffRuntime) -> void:
	var visual := _build_visual(runtime)
	if visual == null:
		return
	visual.name = "StuffVisual_%s" % String(runtime.placement_id)
	visual.set_meta("stuff_cell", runtime.cell)
	add_child(visual)
	visual.global_transform = runtime.global_transform
	_visuals[runtime.placement_id] = visual


func _build_visual(runtime: StuffRuntime) -> Node3D:
	if runtime == null or runtime.definition == null or _grid == null:
		return null
	var root := Node3D.new()
	root.position = _get_slot_offset(runtime)
	var model_asset := runtime.definition.get_model_asset()
	if model_asset != null:
		var model := model_asset.instantiate_grounded_model(&"Model")
		if model != null:
			root.add_child(model)
			return root
	_add_fallback_visual(root, runtime)
	return root if root.get_child_count() > 0 else null


func _add_fallback_visual(root: Node3D, runtime: StuffRuntime) -> void:
	var definition := runtime.definition
	var color := definition.fallback_color
	var size := _grid.cell_size
	match definition.fallback_visual_kind:
		StuffDefinition.FallbackVisualKind.GENERIC_OBSTACLE:
			var box := BoxMesh.new()
			box.size = Vector3(size * obstacle_width_ratio, size * obstacle_height_ratio, size * obstacle_width_ratio)
			_add_mesh(root, box, color, Vector3.UP * box.size.y * 0.5)
		StuffDefinition.FallbackVisualKind.SPIKES:
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var cone := CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = size * 0.085
					cone.height = size * 0.30
					cone.radial_segments = 8
					_add_mesh(root, cone, color, Vector3(x * size * 0.16, cone.height * 0.5, z * size * 0.16))
		StuffDefinition.FallbackVisualKind.HOLE:
			var effect := runtime.get_effect() as VoidTileEffect
			var fill_ratio := _get_fill_ratio(runtime.get_effect_state_key())
			var empty_depth := effect.empty_depth_ratio if effect != null else 0.30
			var full_depth := effect.full_depth_ratio if effect != null else 0.03
			var depth := lerpf(empty_depth, full_depth, fill_ratio) * size
			var hole := CylinderMesh.new()
			hole.top_radius = size * 0.30
			hole.bottom_radius = size * 0.18
			hole.height = maxf(size * 0.02, depth)
			hole.radial_segments = maxi(8, _grid.edge_count() * 2)
			_add_mesh(root, hole, color.lightened(fill_ratio * 0.16), Vector3.DOWN * hole.height * 0.5)
		StuffDefinition.FallbackVisualKind.ROCK:
			var rock := SphereMesh.new()
			rock.radius = size * 0.34
			rock.height = size * 0.70
			rock.radial_segments = maxi(8, _grid.edge_count() * 2)
			rock.rings = 5
			_add_mesh(root, rock, color, Vector3.UP * rock.height * 0.45)
		StuffDefinition.FallbackVisualKind.TREE:
			var trunk := CylinderMesh.new()
			trunk.top_radius = size * 0.07
			trunk.bottom_radius = size * 0.09
			trunk.height = size * 0.45
			trunk.radial_segments = 8
			_add_mesh(root, trunk, color.darkened(0.35), Vector3.UP * trunk.height * 0.5)
			var crown := SphereMesh.new()
			crown.radius = size * 0.25
			crown.height = size * 0.50
			_add_mesh(root, crown, color, Vector3.UP * size * 0.62)


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, local_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = local_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	parent.add_child(instance)


func _get_slot_offset(runtime: StuffRuntime) -> Vector3:
	if _stuff_manager == null:
		return Vector3.ZERO
	var cell_items := _stuff_manager.get_stuff_at(runtime.cell)
	if cell_items.size() <= 1:
		return Vector3.ZERO
	var index := cell_items.find(runtime)
	if index < 0:
		return Vector3.ZERO
	var angle := TAU * float(index) / float(cell_items.size())
	return Vector3(cos(angle), 0.0, sin(angle)) * _grid.cell_size * overlap_slot_radius_ratio


func _get_fill_ratio(state_key: String) -> float:
	if not _effect_visual_state_resolver.is_valid():
		return 0.0
	var resolved: Variant = _effect_visual_state_resolver.call(state_key)
	return clampf(float(resolved), 0.0, 1.0) if resolved is float or resolved is int else 0.0


func _remove_visual(placement_id: StringName) -> void:
	if not _visuals.has(placement_id):
		return
	var visual: Node3D = _visuals[placement_id]
	_visuals.erase(placement_id)
	if visual != null and is_instance_valid(visual):
		visual.free()


func _clear_visuals() -> void:
	for raw_id in _visuals.keys():
		_remove_visual(raw_id)
	_visuals.clear()


func _disconnect_manager() -> void:
	if _stuff_manager == null:
		return
	if _stuff_manager.stuff_loaded.is_connected(_on_stuff_loaded):
		_stuff_manager.stuff_loaded.disconnect(_on_stuff_loaded)
	if _stuff_manager.stuff_cleared.is_connected(_on_stuff_cleared):
		_stuff_manager.stuff_cleared.disconnect(_on_stuff_cleared)
	if _stuff_manager.stuff_changed.is_connected(_on_stuff_changed):
		_stuff_manager.stuff_changed.disconnect(_on_stuff_changed)


func _on_stuff_loaded(_level: LevelResource) -> void:
	_rebuild_all()


func _on_stuff_cleared() -> void:
	_clear_visuals()


func _on_stuff_changed(cell: Vector3i) -> void:
	_rebuild_cell(cell)
