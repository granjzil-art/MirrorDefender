extends SceneTree

const RuntimeHudScript := preload("res://scripts/ui/RuntimeHud.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[TowerWaveTutorial] running")
	var levels: Array[LevelResource] = []
	for configuration: Dictionary in _level_configurations():
		var level := load(configuration["path"]) as LevelResource
		levels.append(level)
		_test_level_configuration(level, configuration)
	_test_duplicate_wave_validation(levels[0])
	await _test_reward_ui(levels[0], levels[1])
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[TowerWaveTutorial] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[TowerWaveTutorial] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_level_configuration(level: LevelResource, configuration: Dictionary) -> void:
	var label := String(configuration["label"])
	_expect(level != null, "%s resource loads" % label)
	if level == null:
		return
	var validation_errors := level.validate_runtime()
	_expect(
		validation_errors.is_empty(),
		"%s runtime and tutorial configuration validates: %s" % [label, validation_errors]
	)
	var expected_initial: Array = configuration["initial"]
	_expect(
		level.initial_building_placements.size() == expected_initial.size(),
		"%s keeps the requested number of initial towers" % label
	)
	for index in range(mini(level.initial_building_placements.size(), expected_initial.size())):
		var placement: BuildingPlacementData = level.initial_building_placements[index]
		var expected: Dictionary = expected_initial[index]
		_expect(
			_tower_file(placement.definition) == expected["tower"]
			and placement.cell == expected["cell"]
			and placement.facing_index == expected["facing"]
			and placement.level == 1,
			"%s initial tower %d preserves type, cell, facing, and level one" % [label, index + 1]
		)

	var rewards := _get_tower_rewards(level)
	var expected_rewards: Array = configuration["rewards"]
	_expect(rewards.size() == expected_rewards.size(), "%s has the requested delayed tower count" % label)
	var towers_per_completed_wave: Dictionary = {}
	for index in range(mini(rewards.size(), expected_rewards.size())):
		var event: TutorialEventDefinition = rewards[index]
		var expected: Dictionary = expected_rewards[index]
		towers_per_completed_wave[event.trigger_wave_number] = (
			int(towers_per_completed_wave.get(event.trigger_wave_number, 0)) + 1
		)
		_expect(
			event.trigger_kind == TutorialEventDefinition.TriggerKind.WAVE_COMPLETED
			and event.trigger_wave_number == expected["wave"]
			and _tower_file(event.automatic_tower_definition) == expected["tower"]
			and event.automatic_tower_cell == expected["cell"]
			and event.automatic_tower_facing_index == expected["facing"],
			"%s delayed tower %d matches wave, type, cell, and facing" % [label, index + 1]
		)
	_expect(
		towers_per_completed_wave.values().all(func(count: Variant) -> bool: return int(count) <= 1),
		"%s never delivers more than one tower after the same wave" % label
	)
	_expect(
		level.initial_building_placements.size() + rewards.size() == level.building_cap,
		"%s reserves exactly enough cap for every tutorial tower" % label
	)
	var final_layout := level.duplicate(true) as LevelResource
	for event: TutorialEventDefinition in rewards:
		var delayed_placement := BuildingPlacementData.new()
		delayed_placement.configure(
			event.automatic_tower_definition,
			event.automatic_tower_cell,
			event.automatic_tower_facing_index,
			-1,
			1
		)
		final_layout.initial_building_placements.append(delayed_placement)
	var final_layout_errors := final_layout.validate_runtime()
	_expect(
		final_layout_errors.is_empty(),
		"%s final tower layout remains legal after every delayed placement: %s" % [
			label,
			final_layout_errors,
		]
	)

	var expected_mirrors: Array = configuration["mirrors"]
	_expect(
		level.initial_mirror_placements.size() == expected_mirrors.size(),
		"%s mirror count remains unchanged" % label
	)
	for index in range(mini(level.initial_mirror_placements.size(), expected_mirrors.size())):
		var placement: MirrorPlacementData = level.initial_mirror_placements[index]
		var expected: Dictionary = expected_mirrors[index]
		_expect(
			placement.mirror_kind == expected["kind"]
			and placement.from_cell == expected["cell"]
			and placement.edge_index == expected["edge"]
			and placement.active_from_side
			and placement.level == expected["level"],
			"%s mirror %d preserves kind, edge, direction, cell, and level" % [label, index + 1]
		)

	var actual_schedule := RuntimeHudScript.build_tower_deployment_schedule(level)
	var expected_schedule: Dictionary = configuration["schedule"]
	for kind: Variant in expected_schedule:
		_expect(
			actual_schedule.get(kind, []) == expected_schedule[kind],
			"%s codex availability schedule matches tower kind %d" % [label, int(kind)]
		)


func _test_duplicate_wave_validation(level: LevelResource) -> void:
	var rewards := _get_tower_rewards(level)
	var duplicate := rewards[0].duplicate(true) as TutorialEventDefinition
	duplicate.event_id = &"duplicate_wave_tower"
	var tutorial := TutorialDefinition.new()
	tutorial.events.assign([rewards[0], duplicate])
	_expect(
		tutorial.validate_configuration(level.waves.size()).any(
			func(message: String) -> bool: return message.contains("最多只能自动投放一座塔")
		),
		"tutorial validation rejects two automatic towers after one wave"
	)


func _test_reward_ui(level1: LevelResource, level2: LevelResource) -> void:
	var hud_scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	var hud := hud_scene.instantiate() as RuntimeHud
	root.add_child(hud)
	await process_frame
	var codex_definitions: Array[BuildingDefinition] = [
		load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition,
		load("res://resources/buildings/LaserTower.tres") as BuildingDefinition,
		load("res://resources/buildings/CrossbowTower.tres") as BuildingDefinition,
		load("res://resources/buildings/PulseLaserTower.tres") as BuildingDefinition,
	]
	hud.tower_codex_panel.configure(codex_definitions)
	hud.apply_level_configuration(level2)
	await process_frame
	var cards := hud.get_node("TowerCodexPanel/Cards") as VBoxContainer
	_test_badges(hud, cards.get_node("TowerCard1") as Control, ["第五波"])
	_test_badges(hud, cards.get_node("TowerCard2") as Control, ["第一波"])
	_test_badges(hud, cards.get_node("TowerCard3") as Control, ["第一波", "第三波"])
	_test_badges(hud, cards.get_node("TowerCard4") as Control, ["第二波", "第七波"])

	var time_controller := GameTimeController.new()
	root.add_child(time_controller)
	await process_frame
	hud._time_controller = time_controller
	var event := _get_tower_rewards(level1)[0]
	var tower_host := Node3D.new()
	root.add_child(tower_host)
	var building := Building.new()
	building.definition = event.automatic_tower_definition
	building.cell = event.automatic_tower_cell
	building.facing_index = event.automatic_tower_facing_index
	tower_host.add_child(building)
	hud._on_automatic_tower_placed(event, building)
	_expect(hud.is_tower_reward_open(), "wave reward opens a mandatory modal")
	_expect(time_controller.is_paused(), "wave reward pauses gameplay")
	var popup := hud.get_node("TowerRewardPopup") as TowerRewardPopup
	_expect(
		(popup.get_node("Shade/Panel/Content/WaveTag/WaveLabel") as Label).text == "第一波结束",
		"reward modal identifies the completed wave"
	)
	_expect(
		(popup.get_node("Shade/Panel/Content/Body/Information/Description") as RichTextLabel).text
		== building.definition.get_formatted_inspection_description_bbcode()
		and (popup.get_node("Shade/Panel/Content/Body/IconPanel/Icon") as TextureRect).texture
		== building.definition.card_icon,
		"reward modal reuses the tower icon and formatted description"
	)
	popup.get_confirm_button().pressed.emit()
	await process_frame
	_expect(not hud.is_tower_reward_open(), "confirm closes the tower reward modal")
	_expect(not time_controller.is_paused(), "confirm restores gameplay playback")
	var pulse := building.get_node_or_null("TowerArrivalPulse") as TowerArrivalPulse
	_expect(
		pulse != null and is_equal_approx(pulse.duration_seconds, 5.0) and pulse.get_ring_count() == 2,
		"confirm starts a five-second two-ring arrival pulse under the new tower"
	)
	hud.queue_free()
	tower_host.queue_free()
	time_controller.queue_free()
	await process_frame


func _test_badges(hud: RuntimeHud, card: Control, expected_labels: Array[String]) -> void:
	var stack := hud.get_node(
		"TowerCodexPanel/DeploymentWaveLayer/%sWaves" % card.name
	) as VBoxContainer
	_expect(stack.get_child_count() == expected_labels.size(), "codex stacks one read-only strip per tower delivery")
	_expect(
		stack.get_global_rect().position.x
		>= card.get_global_rect().end.x + hud.tower_codex_panel.deployment_badge_gap - 0.1
		and not stack.get_global_rect().intersects(card.get_global_rect()),
		"codex delivery strips stay in a separate column to the right of the card"
	)
	for index in range(mini(stack.get_child_count(), expected_labels.size())):
		var badge := stack.get_child(index) as PanelContainer
		var label := badge.get_node("Label") as Label
		_expect(
			label.text == expected_labels[index]
			and badge.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"codex delivery strip displays the authored Chinese wave label and is non-clickable"
		)


func _get_tower_rewards(level: LevelResource) -> Array[TutorialEventDefinition]:
	var rewards: Array[TutorialEventDefinition] = []
	if level == null or level.tutorial == null:
		return rewards
	for event: TutorialEventDefinition in level.tutorial.events:
		if event != null and event.automatic_tower_enabled:
			rewards.append(event)
	rewards.sort_custom(
		func(a: TutorialEventDefinition, b: TutorialEventDefinition) -> bool:
			return a.trigger_wave_number < b.trigger_wave_number
	)
	return rewards


func _tower_file(definition: BuildingDefinition) -> String:
	return definition.resource_path.get_file() if definition != null else ""


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("[TowerWaveTutorial] %s" % message)


func _level_configurations() -> Array[Dictionary]:
	return [
		{
			"label": "Level1",
			"path": "res://resources/levels/Level1.tres",
			"initial": [
				{"tower": "ArrowTower.tres", "cell": Vector3i(6, 10, 0), "facing": 34},
			],
			"rewards": [
				{"wave": 1, "tower": "LaserTower.tres", "cell": Vector3i(6, 2, 0), "facing": 4},
				{"wave": 3, "tower": "CrossbowTower.tres", "cell": Vector3i(3, 13, 0), "facing": 30},
				{"wave": 6, "tower": "PulseLaserTower.tres", "cell": Vector3i(5, 10, 0), "facing": 0},
			],
			"mirrors": [
				{"kind": 0, "cell": Vector3i(7, 11, 0), "edge": 0, "level": 2},
				{"kind": 0, "cell": Vector3i(6, 7, 0), "edge": 3, "level": 1},
				{"kind": 0, "cell": Vector3i(6, 2, 0), "edge": 2, "level": 1},
				{"kind": 1, "cell": Vector3i(7, 9, 0), "edge": 0, "level": 1},
			],
			"schedule": {
				BuildingDefinition.Kind.ARROW_TOWER: [1],
				BuildingDefinition.Kind.LASER_TOWER: [2],
				BuildingDefinition.Kind.CROSSBOW_TOWER: [4],
				BuildingDefinition.Kind.PULSE_LASER_TOWER: [7],
			},
		},
		{
			"label": "Level2",
			"path": "res://resources/levels/Level2.tres",
			"initial": [
				{"tower": "CrossbowTower.tres", "cell": Vector3i(3, 3, 0), "facing": 7},
				{"tower": "LaserTower.tres", "cell": Vector3i(8, 3, 0), "facing": 7},
			],
			"rewards": [
				{"wave": 1, "tower": "PulseLaserTower.tres", "cell": Vector3i(3, 2, 0), "facing": 8},
				{"wave": 2, "tower": "CrossbowTower.tres", "cell": Vector3i(11, 3, 0), "facing": 15},
				{"wave": 4, "tower": "ArrowTower.tres", "cell": Vector3i(7, 3, 0), "facing": 9},
				{"wave": 6, "tower": "PulseLaserTower.tres", "cell": Vector3i(11, 2, 0), "facing": 10},
			],
			"mirrors": [
				{"kind": 0, "cell": Vector3i(3, 3, 0), "edge": 2, "level": 1},
				{"kind": 0, "cell": Vector3i(2, 3, 0), "edge": 3, "level": 1},
			],
			"schedule": {
				BuildingDefinition.Kind.ARROW_TOWER: [5],
				BuildingDefinition.Kind.LASER_TOWER: [1],
				BuildingDefinition.Kind.CROSSBOW_TOWER: [1, 3],
				BuildingDefinition.Kind.PULSE_LASER_TOWER: [2, 7],
			},
		},
		{
			"label": "Level3",
			"path": "res://resources/levels/Level3.tres",
			"initial": [
				{"tower": "ArrowTower.tres", "cell": Vector3i(10, 4, 0), "facing": 9},
				{"tower": "CrossbowTower.tres", "cell": Vector3i(12, 4, 0), "facing": 2},
				{"tower": "PulseLaserTower.tres", "cell": Vector3i(9, 13, 0), "facing": 27},
			],
			"rewards": [
				{"wave": 1, "tower": "LaserTower.tres", "cell": Vector3i(6, 5, 0), "facing": 0},
				{"wave": 3, "tower": "ArrowTower.tres", "cell": Vector3i(10, 6, 0), "facing": 32},
				{"wave": 6, "tower": "CrossbowTower.tres", "cell": Vector3i(8, 7, 0), "facing": 33},
			],
			"mirrors": [
				{"kind": 1, "cell": Vector3i(12, 4, 0), "edge": 0, "level": 1},
				{"kind": 0, "cell": Vector3i(5, 6, 0), "edge": 1, "level": 1},
				{"kind": 0, "cell": Vector3i(9, 13, 0), "edge": 0, "level": 1},
				{"kind": 0, "cell": Vector3i(12, 7, 0), "edge": 1, "level": 1},
			],
			"schedule": {
				BuildingDefinition.Kind.ARROW_TOWER: [1, 4],
				BuildingDefinition.Kind.LASER_TOWER: [2],
				BuildingDefinition.Kind.CROSSBOW_TOWER: [1, 7],
				BuildingDefinition.Kind.PULSE_LASER_TOWER: [1],
			},
		},
		{
			"label": "Level4",
			"path": "res://resources/levels/Level4.tres",
			"initial": [
				{"tower": "LaserTower.tres", "cell": Vector3i(11, 13, 0), "facing": 12},
				{"tower": "ArrowTower.tres", "cell": Vector3i(11, 9, 0), "facing": 31},
				{"tower": "PulseLaserTower.tres", "cell": Vector3i(13, 8, 0), "facing": 21},
			],
			"rewards": [
				{"wave": 1, "tower": "CrossbowTower.tres", "cell": Vector3i(5, 9, 0), "facing": 5},
				{"wave": 4, "tower": "ArrowTower.tres", "cell": Vector3i(11, 10, 0), "facing": 15},
				{"wave": 8, "tower": "CrossbowTower.tres", "cell": Vector3i(14, 8, 0), "facing": 12},
			],
			"mirrors": [
				{"kind": 1, "cell": Vector3i(10, 15, 0), "edge": 1, "level": 1},
				{"kind": 0, "cell": Vector3i(6, 7, 0), "edge": 1, "level": 1},
				{"kind": 0, "cell": Vector3i(9, 10, 0), "edge": 2, "level": 1},
				{"kind": 1, "cell": Vector3i(8, 5, 0), "edge": 2, "level": 1},
			],
			"schedule": {
				BuildingDefinition.Kind.ARROW_TOWER: [1, 5],
				BuildingDefinition.Kind.LASER_TOWER: [1],
				BuildingDefinition.Kind.CROSSBOW_TOWER: [2, 9],
				BuildingDefinition.Kind.PULSE_LASER_TOWER: [1],
			},
		},
	]
