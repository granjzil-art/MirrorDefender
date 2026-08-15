## Read-only world-space UI for the selected Building or active placement ghost.
## Targeting and trajectory previews never mutate placement or combat state.
class_name BuildingSelectionVisualizer
extends Node3D

const ProjectileTrajectoryPreviewScript := preload("res://scripts/building/ProjectileTrajectoryPreview.gd")

@export_group("Feature")
@export var feature_enabled: bool = true

@export_group("Targeting Range")
@export var targeting_fill_color: Color = Color(0.12, 0.52, 1.0, 0.16)
@export var targeting_border_color: Color = Color(0.20, 0.68, 1.0, 0.78)
@export_range(12, 180, 1) var targeting_circle_segments: int = 72
@export_range(0.0, 0.5, 0.001, "or_greater") var targeting_lift: float = 0.055

@export_group("Occupied Cells")
@export var occupied_cell_color: Color = Color(1.0, 0.86, 0.36, 0.34)
@export_range(0.0, 0.5, 0.001, "or_greater") var occupied_cell_lift: float = 0.075

@export_group("Projectile Trajectory Preview")
@export var projectile_preview_enabled: bool = true
@export var projectile_preview_color: Color = Color(1.0, 0.05, 0.05, 0.52)
@export_range(0.01, 0.5, 0.01, "or_greater") var projectile_preview_width: float = 0.10
@export_range(0.0, 0.5, 0.001, "or_greater") var projectile_preview_lift: float = 0.04
@export_range(1, 64, 1) var projectile_preview_max_segments_per_direction: int = 32
@export var projectile_multiplier_label_color: Color = Color(1.0, 0.05, 0.05, 1.0)
@export_range(0.0, 2.0, 0.01, "or_greater") var projectile_multiplier_label_height: float = 0.18
@export_range(0.0, 2.0, 0.01, "or_greater") var projectile_multiplier_label_stack_spacing: float = 0.22

var _grid: GridManager
var _building_manager: BuildingManager
var _selected_building: Building
var _preview_building: Building
var _range_fill: MeshInstance3D
var _range_border: MeshInstance3D
var _occupied_fill: MeshInstance3D
var _trajectory_preview: ProjectileTrajectoryPreview
var _projectile_reflection_resolver: Callable
var _projectile_blocker_resolver: Callable
var _projectile_copy_resolver: Callable
var _mirror_preview_trajectory_resolver: Callable
var _visualized_cells: Array[Vector3i] = []


func _ready() -> void:
	_range_fill = _create_mesh_instance(&"TargetingRangeFill", targeting_fill_color)
	_range_border = _create_mesh_instance(&"TargetingRangeBorder", targeting_border_color)
	_occupied_fill = _create_mesh_instance(&"OccupiedCellFill", occupied_cell_color)
	_trajectory_preview = ProjectileTrajectoryPreviewScript.new()
	_trajectory_preview.name = &"ProjectileTrajectoryPreview"
	add_child(_trajectory_preview)
	_rebuild_visuals()


func configure(grid_manager: GridManager, building_manager: BuildingManager) -> void:
	_disconnect_manager()
	_grid = grid_manager
	_building_manager = building_manager
	if _building_manager != null:
		_building_manager.building_selected.connect(_on_building_selected)
		_building_manager.preview_updated.connect(_on_preview_updated)
		_building_manager.preview_cleared.connect(_on_preview_cleared)
	_on_building_selected(
		_building_manager.get_selected_building() if _building_manager != null else null
	)
	_on_preview_updated(
		_building_manager.get_preview_building() if _building_manager != null else null
	)


func set_projectile_reflection_resolver(value: Callable) -> void:
	_projectile_reflection_resolver = value
	if _trajectory_preview != null:
		_trajectory_preview.set_reflection_resolver(value)
	_rebuild_visuals()


func set_projectile_blocker_resolver(value: Callable) -> void:
	_projectile_blocker_resolver = value
	if _trajectory_preview != null:
		_trajectory_preview.set_blocker_resolver(value)
	_rebuild_visuals()


## Supplies the live/preview copy payloads whose trajectories belong to the
## selected source Building. Mirror ownership stays outside this UI node.
func set_projectile_copy_resolver(value: Callable) -> void:
	_projectile_copy_resolver = value
	_rebuild_visuals()


## Supplies the transient source/payload pair owned by copy-mirror placement.
func set_mirror_preview_trajectory_resolver(value: Callable) -> void:
	_mirror_preview_trajectory_resolver = value
	_rebuild_visuals()


func refresh() -> void:
	_rebuild_visuals()


func has_targeting_range_visual() -> bool:
	return _range_fill != null and _range_fill.visible


func has_projectile_trajectory_visual() -> bool:
	return _trajectory_preview != null and _trajectory_preview.has_visual()


func debug_get_projectile_trajectory_segments() -> Array[Dictionary]:
	if _trajectory_preview == null:
		return []
	return _trajectory_preview.debug_get_segments()


func debug_get_projectile_trajectory_width() -> float:
	return _trajectory_preview.debug_get_visual_width() if _trajectory_preview != null else 0.0


func debug_get_projectile_multiplier_labels() -> Array[Dictionary]:
	if _trajectory_preview == null:
		return []
	return _trajectory_preview.debug_get_multiplier_labels()


func get_visualized_occupied_cells() -> Array[Vector3i]:
	return _visualized_cells.duplicate()


func _on_building_selected(building: Building) -> void:
	_disconnect_selected_building()
	_selected_building = building
	if _selected_building != null and is_instance_valid(_selected_building):
		_selected_building.level_changed.connect(_on_building_level_changed)
		_selected_building.facing_changed.connect(_on_building_facing_changed)
	_rebuild_visuals()


func _on_preview_updated(building: Building) -> void:
	_disconnect_preview_building()
	_preview_building = building
	if _preview_building != null and is_instance_valid(_preview_building):
		_preview_building.level_changed.connect(_on_building_level_changed)
		_preview_building.facing_changed.connect(_on_building_facing_changed)
	_rebuild_visuals()


func _on_preview_cleared() -> void:
	_disconnect_preview_building()
	_rebuild_visuals()


func _on_building_level_changed(
	_building: Building,
	_level: int,
	_stats: BuildingLevelStats
) -> void:
	_rebuild_visuals()


func _on_building_facing_changed(
	_building: Building,
	_facing_index: int,
	_facing_slots: int
) -> void:
	_rebuild_visuals()


func _rebuild_visuals() -> void:
	if _range_fill == null or _range_border == null or _occupied_fill == null:
		return
	_clear_visuals()
	if (
		not feature_enabled
		or _grid == null
	):
		return
	if _selected_building != null and is_instance_valid(_selected_building):
		_rebuild_occupied_cells(_selected_building.get_occupied_cells())
	var active_preview_building := _preview_building
	if active_preview_building == null or not is_instance_valid(active_preview_building):
		active_preview_building = _selected_building
	if (
		active_preview_building != null
		and is_instance_valid(active_preview_building)
		and active_preview_building.uses_targeting_range()
	):
		_rebuild_targeting_circle(
			active_preview_building.global_position,
			active_preview_building.get_targeting_range_world()
		)
	if _trajectory_preview != null:
		_trajectory_preview.configure_style(
			projectile_preview_enabled,
			projectile_preview_color,
			projectile_preview_width,
			projectile_preview_lift,
			projectile_preview_max_segments_per_direction,
			projectile_multiplier_label_color,
			projectile_multiplier_label_height,
			projectile_multiplier_label_stack_spacing
		)
		_trajectory_preview.set_reflection_resolver(_projectile_reflection_resolver)
		_trajectory_preview.set_blocker_resolver(_projectile_blocker_resolver)
		var trajectory_building := active_preview_building
		var copy_payloads: Array[MirrorCopyPayload] = []
		var show_multiplier_labels := trajectory_building != null
		if trajectory_building != null and _projectile_copy_resolver.is_valid():
			var raw_payloads: Variant = _projectile_copy_resolver.call(trajectory_building)
			if raw_payloads is Array:
				for raw_payload in raw_payloads:
					if raw_payload is MirrorCopyPayload:
						copy_payloads.append(raw_payload)
		elif _mirror_preview_trajectory_resolver.is_valid():
			var raw_preview: Variant = _mirror_preview_trajectory_resolver.call()
			if raw_preview is Dictionary:
				var raw_building: Variant = raw_preview.get("building", null)
				if raw_building is Building and is_instance_valid(raw_building):
					trajectory_building = raw_building as Building
					show_multiplier_labels = false
					var raw_payloads: Variant = raw_preview.get("payloads", [])
					if raw_payloads is Array:
						for raw_payload in raw_payloads:
							if raw_payload is MirrorCopyPayload:
								copy_payloads.append(raw_payload)
		_trajectory_preview.rebuild(
			trajectory_building,
			copy_payloads,
			show_multiplier_labels
		)


func _rebuild_targeting_circle(center: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	var segment_count := maxi(12, targeting_circle_segments)
	var resolved_center := center
	resolved_center.y += targeting_lift
	var fill_mesh := ImmediateMesh.new()
	fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segment_count):
		var angle_a := TAU * float(index) / float(segment_count)
		var angle_b := TAU * float(index + 1) / float(segment_count)
		fill_mesh.surface_add_vertex(resolved_center)
		fill_mesh.surface_add_vertex(
			resolved_center + Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		)
		fill_mesh.surface_add_vertex(
			resolved_center + Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		)
	fill_mesh.surface_end()
	_range_fill.mesh = fill_mesh
	_range_fill.visible = true
	var border_mesh := ImmediateMesh.new()
	border_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(segment_count):
		var angle_a := TAU * float(index) / float(segment_count)
		var angle_b := TAU * float(index + 1) / float(segment_count)
		border_mesh.surface_add_vertex(
			resolved_center + Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		)
		border_mesh.surface_add_vertex(
			resolved_center + Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		)
	border_mesh.surface_end()
	_range_border.mesh = border_mesh
	_range_border.visible = true


func _rebuild_occupied_cells(cells: Array[Vector3i]) -> void:
	_visualized_cells.assign(cells)
	if cells.is_empty():
		return
	var mesh := ImmediateMesh.new()
	var has_geometry := false
	for cell in cells:
		var corners := _grid.get_corners(cell)
		if corners.size() < 3:
			continue
		if not has_geometry:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_geometry = true
		var center := _grid.cell_to_world(cell)
		center.y = _grid.sample_cell_surface_height(cell, center) + occupied_cell_lift
		for index in range(corners.size()):
			var a: Vector3 = corners[index]
			var b: Vector3 = corners[(index + 1) % corners.size()]
			a.y = _grid.sample_cell_surface_height(cell, a) + occupied_cell_lift
			b.y = _grid.sample_cell_surface_height(cell, b) + occupied_cell_lift
			mesh.surface_add_vertex(center)
			mesh.surface_add_vertex(a)
			mesh.surface_add_vertex(b)
	if not has_geometry:
		return
	mesh.surface_end()
	_occupied_fill.mesh = mesh
	_occupied_fill.visible = true


func _clear_visuals() -> void:
	_visualized_cells.clear()
	for instance in [_range_fill, _range_border, _occupied_fill]:
		if instance != null:
			instance.mesh = null
			instance.visible = false
	if _trajectory_preview != null:
		_trajectory_preview.clear()


func _create_mesh_instance(node_name: StringName, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.visible = false
	instance.material_override = _make_ui_material(color)
	add_child(instance)
	return instance


func _make_ui_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 10
	material.albedo_color = color
	return material


func _disconnect_selected_building() -> void:
	_disconnect_building_signals(_selected_building)
	_selected_building = null


func _disconnect_preview_building() -> void:
	_disconnect_building_signals(_preview_building)
	_preview_building = null


func _disconnect_building_signals(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if building.level_changed.is_connected(_on_building_level_changed):
		building.level_changed.disconnect(_on_building_level_changed)
	if building.facing_changed.is_connected(_on_building_facing_changed):
		building.facing_changed.disconnect(_on_building_facing_changed)


func _disconnect_manager() -> void:
	if (
		_building_manager != null
		and _building_manager.building_selected.is_connected(_on_building_selected)
	):
		_building_manager.building_selected.disconnect(_on_building_selected)
	if (
		_building_manager != null
		and _building_manager.preview_updated.is_connected(_on_preview_updated)
	):
		_building_manager.preview_updated.disconnect(_on_preview_updated)
	if (
		_building_manager != null
		and _building_manager.preview_cleared.is_connected(_on_preview_cleared)
	):
		_building_manager.preview_cleared.disconnect(_on_preview_cleared)
	_disconnect_selected_building()
	_disconnect_preview_building()


func _exit_tree() -> void:
	_disconnect_manager()
