@tool
## Serialized initial placement for one real physical mirror.
class_name MirrorPlacementData
extends Resource

enum MirrorKind {
	COPY,
	PROJECTILE_REFLECT,
}

@export_group("Identity")
@export var mirror_kind: MirrorKind = MirrorKind.COPY

@export_group("Placement")
@export var from_cell: Vector3i = Vector3i.ZERO
@export_range(0, 5, 1) var edge_index: int = 0
@export var active_from_side: bool = true
@export_range(1, 3, 1) var level: int = 1


func configure(
	p_from_cell: Vector3i,
	p_edge_index: int,
	p_active_from_side: bool,
	p_mirror_kind: MirrorKind = MirrorKind.COPY,
	p_level: int = 1
) -> void:
	from_cell = p_from_cell
	edge_index = maxi(0, p_edge_index)
	active_from_side = p_active_from_side
	mirror_kind = p_mirror_kind
	level = clampi(p_level, 1, 3)
	emit_changed()


func duplicate_placement() -> MirrorPlacementData:
	_migrate_legacy_level()
	var clone := MirrorPlacementData.new()
	clone.configure(from_cell, edge_index, active_from_side, mirror_kind, level)
	return clone


func validate_configuration() -> Array[String]:
	_migrate_legacy_level()
	var errors: Array[String] = []
	if mirror_kind < MirrorKind.COPY or mirror_kind > MirrorKind.PROJECTILE_REFLECT:
		errors.append("镜子类型无效")
	if edge_index < 0 or edge_index > 5:
		errors.append("镜子边方向必须位于 0 到 5 之间")
	if level < 1 or level > 3:
		errors.append("镜子等级必须位于 1 到 3 之间")
	return errors


## Mirrors serialized before upgrade support have no `level` field. During a
## live script reload Godot exposes that missing value as 0, so migrate only
## that legacy sentinel while preserving validation for every other bad value.
func _migrate_legacy_level() -> void:
	if level == 0:
		level = 1
