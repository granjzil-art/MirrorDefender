## Pure read-only projection from authored wave resources to stable UI dictionaries.
class_name WaveTimelineModel
extends RefCounted


func build(level: LevelResource) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if level == null:
		return entries
	for wave_index in range(level.waves.size()):
		var wave: WaveDefinition = level.waves[wave_index]
		if wave == null:
			continue
		entries.append(_build_wave_entry(level, wave, wave_index))
	return entries


func _build_wave_entry(level: LevelResource, wave: WaveDefinition, wave_index: int) -> Dictionary:
	var groups: Array[Dictionary] = []
	var paths: Array[PathDefinition] = []
	var path_keys: Dictionary = {}
	var enemy_totals_by_key: Dictionary = {}
	var enemy_order: Array[String] = []
	var scheduled_time: float = INF
	var primary_icon: Texture2D
	for group_index in range(wave.spawn_groups.size()):
		var group: SpawnGroupDefinition = wave.spawn_groups[group_index]
		if group == null:
			continue
		scheduled_time = minf(scheduled_time, maxf(0.0, group.start_delay))
		var enemy_name := "未配置敌人"
		var enemy_key := "missing_%d" % group_index
		var enemy_icon: Texture2D
		if group.enemy != null:
			enemy_name = group.enemy.display_name
			enemy_key = String(group.enemy.enemy_id)
			if enemy_key.is_empty():
				enemy_key = "enemy_%d" % group.enemy.get_instance_id()
			enemy_icon = group.enemy.ui_icon
			if primary_icon == null and enemy_icon != null:
				primary_icon = enemy_icon
		if not enemy_totals_by_key.has(enemy_key):
			enemy_order.append(enemy_key)
			enemy_totals_by_key[enemy_key] = {
				"name": enemy_name,
				"count": 0,
				"icon": enemy_icon,
			}
		var total: Dictionary = enemy_totals_by_key[enemy_key]
		total["count"] = int(total["count"]) + group.count
		enemy_totals_by_key[enemy_key] = total

		var path_name := "未配置路径"
		var path_id := ""
		if group.path != null:
			path_name = group.path.display_name
			path_id = String(group.path.path_id)
			var unique_key := path_id
			if unique_key.is_empty():
				unique_key = "path_%d" % group.path.get_instance_id()
			if not path_keys.has(unique_key):
				path_keys[unique_key] = true
				paths.append(group.path)
		var spawn := level.resolve_group_spawn_point(group)
		var target_base := level.resolve_path_target_base(group.path)
		groups.append({
			"group_number": group_index + 1,
			"enemy_name": enemy_name,
			"enemy_icon": enemy_icon,
			"count": group.count,
			"interval": group.interval,
			"start_delay": group.start_delay,
			"spawn_name": spawn.display_name if spawn != null else "未配置出生点",
			"spawn_label": level.get_spawn_marker_label(spawn) if spawn != null else "未配置出生点",
			"spawn_number": level.get_spawn_display_number(spawn) if spawn != null else 0,
			"base_name": target_base.display_name if target_base != null else "未配置据点",
			"base_label": level.get_base_marker_label(target_base) if target_base != null else "未配置据点",
			"base_number": level.get_base_display_number(target_base) if target_base != null else 0,
			"path_name": path_name,
			"path_id": path_id,
		})

	if is_inf(scheduled_time):
		scheduled_time = 0.0
	var enemy_totals: Array[Dictionary] = []
	for enemy_key in enemy_order:
		enemy_totals.append(enemy_totals_by_key[enemy_key])
	var display_name := wave.display_name.strip_edges()
	if display_name.is_empty():
		display_name = "第 %d 波" % (wave_index + 1)
	return {
		"wave_index": wave_index,
		"wave_number": wave_index + 1,
		"display_name": display_name,
		"scheduled_time": scheduled_time,
		"groups": groups,
		"enemy_totals": enemy_totals,
		"paths": paths,
		"primary_icon": primary_icon,
		"summary": _build_summary(display_name, enemy_totals, groups),
	}


func _build_summary(
	display_name: String,
	enemy_totals: Array[Dictionary],
	groups: Array[Dictionary]
) -> String:
	var lines: Array[String] = [display_name]
	var composition: Array[String] = []
	for total in enemy_totals:
		composition.append("%s × %d" % [String(total["name"]), int(total["count"])])
	lines.append("敌人：%s" % ("、".join(composition) if not composition.is_empty() else "无"))
	for group in groups:
		var spawn_text := "出生点%d" % int(group["spawn_number"]) if int(group["spawn_number"]) > 0 else "未配置出生点"
		var base_text := "据点%d" % int(group["base_number"]) if int(group["base_number"]) > 0 else "未配置据点"
		lines.append("组%d：%s ×%d | %s → %s" % [
			int(group["group_number"]),
			String(group["enemy_name"]),
			int(group["count"]),
			spawn_text,
			base_text,
		])
	return "\n".join(lines)
