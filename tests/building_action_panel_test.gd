extends SceneTree

const BuildingActionPanelScript := preload("res://scripts/ui/BuildingActionPanel.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[BuildingActionPanel] running")
	var host := Control.new()
	root.add_child(host)
	var panel: BuildingActionPanel = BuildingActionPanelScript.new()
	host.add_child(panel)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	camera.position = Vector3(0.0, 8.0, 8.0)
	camera.look_at(Vector3.ZERO)
	await process_frame

	var downgrade_button := panel.get_node_or_null("DowngradeButton") as Button
	var upgrade_button := panel.get_node_or_null("UpgradeButton") as Button
	var downgrade_refund_label := panel.get_node_or_null("DowngradeRefundLabel") as Label
	var upgrade_cost_label := panel.get_node_or_null("UpgradeCostLabel") as Label
	_expect(downgrade_button != null and upgrade_button != null, "the two tower contextual actions exist")
	_expect(
		downgrade_refund_label != null and upgrade_cost_label != null,
		"downgrade and upgrade actions own economy labels"
	)
	_expect(
		panel.get_node_or_null("InfoButton") == null
		and panel.get_node_or_null("InfoPage") == null
		and panel.get_node_or_null("SellButton") == null
		and panel.get_node_or_null("SellRefundLabel") == null,
		"tower selection removes explanation and demolition controls"
	)
	_expect(panel.get_node_or_null("RotateButton") == null, "the old rotate action is absent")
	_expect(bool(panel.get_meta(&"allows_camera_orbit", false)), "right-drag camera orbit may start over the contextual actions")
	_expect(panel.process_priority > 0, "the contextual actions update after the default-priority camera controller")
	if downgrade_button != null and upgrade_button != null:
		_expect(
			downgrade_button.position.x < upgrade_button.position.x
			and is_equal_approx(downgrade_button.position.y, upgrade_button.position.y),
			"tower downgrade is on the left and upgrade is on the right"
		)
		_expect(downgrade_button.size == upgrade_button.size, "both tower action controls have the same size")
		var downgrade_icon := downgrade_button.get_node_or_null("Icon") as TextureRect
		var upgrade_icon := upgrade_button.get_node_or_null("Icon") as TextureRect
		_expect(
			downgrade_icon != null and downgrade_icon.texture != null,
			"the downgrade action uses the supplied down-arrow icon"
		)
		_expect(upgrade_icon != null and upgrade_icon.texture.resource_path.ends_with("upgrade.png"), "the upgrade action uses the supplied icon")

	var building := Building.new()
	var definition := BuildingDefinition.new()
	definition.display_name = "测试塔"
	var level_one := BuildingLevelStats.new()
	level_one.cost = 80.0
	var level_two := BuildingLevelStats.new()
	level_two.cost = 60.0
	var level_three := BuildingLevelStats.new()
	level_three.cost = 70.0
	definition.levels = [level_one, level_two, level_three]
	var grid := GridManager.new()
	host.add_child(grid)
	host.add_child(building)
	building.configure(definition, Vector3i.ZERO, grid, null, null)
	_expect(building.level == 1, "tower action fixture applies level one")
	var resource_manager := ResourceManager.new()
	resource_manager.main_resource = 300.0
	host.add_child(resource_manager)
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager._resource_manager = resource_manager
	panel.configure(building_manager, camera)
	building_manager.select_building(building)
	await process_frame
	_expect(upgrade_button.visible and upgrade_cost_label.visible and upgrade_cost_label.text == "-60", "upgrade displays the next-level cost above its action")
	_expect(
		not downgrade_button.visible and not downgrade_refund_label.visible,
		"level-one tower hides downgrade and its refund"
	)
	_expect(building_manager.upgrade_selected(), "tower upgrades from level one to level two")
	_expect(
		building.level == 2
		and is_equal_approx(resource_manager.main_resource, 240.0)
		and downgrade_button.visible
		and downgrade_refund_label.visible
		and downgrade_refund_label.text == "+60"
		and upgrade_cost_label.text == "-70",
		"level-two tower exposes the paid tier as its downgrade refund"
	)
	_expect(
		upgrade_cost_label.get_theme_color("font_color").is_equal_approx(
			downgrade_refund_label.get_theme_color("font_color")
		),
		"upgrade cost and downgrade refund use one gold color"
	)
	_expect(
		upgrade_cost_label.position.y < upgrade_button.position.y
		and downgrade_refund_label.position.y < downgrade_button.position.y,
		"both tower economy amounts render above their actions"
	)
	_expect(building_manager.upgrade_selected(), "tower upgrades from level two to level three")
	_expect(
		building.level == 3
		and is_equal_approx(resource_manager.main_resource, 170.0)
		and not upgrade_button.visible
		and not upgrade_cost_label.visible
		and downgrade_refund_label.text == "+70",
		"maximum-level tower hides upgrade and offers the current tier refund"
	)
	panel._on_downgrade_pressed()
	_expect(
		building.level == 2
		and is_equal_approx(resource_manager.main_resource, 240.0)
		and upgrade_button.visible
		and downgrade_refund_label.text == "+60",
		"tower downgrade returns the level-three payment and keeps the tower selected"
	)
	panel._on_downgrade_pressed()
	_expect(
		building.level == 1
		and is_equal_approx(resource_manager.main_resource, 300.0)
		and not downgrade_button.visible
		and not downgrade_refund_label.visible
		and not building_manager.downgrade_selected(),
		"tower can return to level one but cannot downgrade below it"
	)
	panel._update_projection()
	var expected_position := camera.unproject_position(building.get_action_anchor()) + panel.screen_offset
	_expect(panel.position.is_equal_approx(expected_position), "the panel origin matches the selected building projection")
	camera.position += Vector3(1.5, 0.0, 0.0)
	camera.look_at(Vector3.ZERO)
	panel._update_projection()
	expected_position = camera.unproject_position(building.get_action_anchor()) + panel.screen_offset
	_expect(panel.position.is_equal_approx(expected_position), "camera movement keeps every action at its fixed building-relative offset")
	building_manager.select_building(null)
	host.free()
	await process_frame
	if _failures == 0:
		print("[BuildingActionPanel] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[BuildingActionPanel] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("[BuildingActionPanel] FAIL: %s" % message)
