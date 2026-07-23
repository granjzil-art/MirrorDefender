@tool
## A reusable spawn location for one or more wave groups.
class_name SpawnPointDefinition
extends Resource

@export_group("Identity")
@export var spawn_id: StringName = &"north"
@export var display_name: String = "北侧入口"
## Zero means derive a stable display number from LevelResource serialization order.
@export_range(0, 999, 1) var display_number: int = 0

@export_group("Location")
@export var cell: Vector3i = Vector3i.ZERO

static func make_id_for_path(path: PathDefinition) -> StringName:
	if path == null:
		return &""
	return StringName("spawn_%s" % str(path.path_id))

static func make_display_name_for_path(path: PathDefinition) -> String:
	if path == null:
		return "未关联出生点"
	var path_name := path.display_name.strip_edges()
	return "%s 出生点" % (path_name if not path_name.is_empty() else str(path.path_id))

func sync_with_path(path: PathDefinition) -> void:
	if path == null:
		return
	spawn_id = make_id_for_path(path)
	display_name = make_display_name_for_path(path)
	if not path.cells.is_empty():
		cell = path.get_start_cell()
	emit_changed()


func get_marker_label(resolved_number: int) -> String:
	return "出生点 %d" % maxi(1, resolved_number)
