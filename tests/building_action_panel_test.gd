extends SceneTree

const BuildingActionPanelScript := preload("res://scripts/ui/BuildingActionPanel.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

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

	var info_button := panel.get_node_or_null("InfoButton") as Button
	var upgrade_button := panel.get_node_or_null("UpgradeButton") as Button
	var sell_button := panel.get_node_or_null("SellButton") as Button
	var upgrade_cost_label := panel.get_node_or_null("UpgradeCostLabel") as Label
	var sell_refund_label := panel.get_node_or_null("SellRefundLabel") as Label
	_expect(info_button != null and upgrade_button != null and sell_button != null, "the three contextual actions exist")
	_expect(upgrade_cost_label != null and sell_refund_label != null, "upgrade and sell actions own economy labels")
	_expect(panel.get_node_or_null("RotateButton") == null, "the old rotate action is absent")
	_expect(bool(panel.get_meta(&"allows_camera_orbit", false)), "right-drag camera orbit may start over the contextual actions")
	_expect(panel.process_priority > 0, "the contextual actions update after the default-priority camera controller")
	if info_button != null and upgrade_button != null and sell_button != null:
		_expect(info_button.position.x < upgrade_button.position.x, "the explanation action is on the left")
		_expect(upgrade_button.position.x > info_button.position.x, "the upgrade action is on the right")
		_expect(sell_button.position.y < info_button.position.y and sell_button.position.y < upgrade_button.position.y, "the sell action is above the side actions")
		_expect(
			info_button.size == upgrade_button.size and upgrade_button.size == sell_button.size,
			"all three action controls have exactly the same size: %s / %s / %s" % [info_button.size, upgrade_button.size, sell_button.size]
		)
		var info_icon := info_button.get_node_or_null("Icon") as TextureRect
		var upgrade_icon := upgrade_button.get_node_or_null("Icon") as TextureRect
		var sell_icon := sell_button.get_node_or_null("Icon") as TextureRect
		_expect(info_icon != null and info_icon.texture.resource_path.ends_with("exclamation-mark.png"), "the explanation action uses the supplied icon")
		_expect(upgrade_icon != null and upgrade_icon.texture.resource_path.ends_with("upgrade.png"), "the upgrade action uses the supplied icon")
		var sell_atlas := sell_icon.texture as AtlasTexture if sell_icon != null else null
		_expect(sell_atlas != null and sell_atlas.atlas.resource_path.ends_with("dollar.png"), "the sell action uses the supplied icon")
		_expect(sell_atlas != null and sell_atlas.region.size == Vector2(406.0, 406.0), "the sell icon transparent inset is cropped for equal visible size")

	var building := Building.new()
	var definition := BuildingDefinition.new()
	definition.display_name = "测试塔"
	definition.inspection_display = InspectionDisplayConfigScript.new()
	definition.inspection_display.function_description = "这段文本可在每个建筑定义中独立编辑。"
	definition.copy_enhancement_description = "复制镜强化说明"
	definition.reflection_enhancement_description = "反射镜强化说明"
	var level_one := BuildingLevelStats.new()
	level_one.cost = 80.0
	var level_two := BuildingLevelStats.new()
	level_two.cost = 60.0
	var level_three := BuildingLevelStats.new()
	level_three.cost = 70.0
	definition.levels = [level_one, level_two, level_three]
	building.definition = definition
	building.level = 1
	host.add_child(building)
	panel._selected_building = building
	panel._camera = camera
	panel._refresh_action_state()
	_expect(upgrade_button.visible and upgrade_cost_label.visible and upgrade_cost_label.text == "-60", "upgrade displays the next-level cost above its action")
	_expect(sell_button.visible and sell_refund_label.visible and sell_refund_label.text == "+80", "sell displays the current cumulative refund above its action")
	_expect(
		upgrade_cost_label.get_theme_color("font_color").is_equal_approx(sell_refund_label.get_theme_color("font_color")),
		"upgrade and sell amounts use one gold color"
	)
	_expect(upgrade_cost_label.position.y < upgrade_button.position.y and sell_refund_label.position.y < sell_button.position.y, "both economy amounts render above their actions")
	building.level = 3
	panel._refresh_action_state()
	_expect(not upgrade_button.visible and not upgrade_cost_label.visible, "the upgrade action and cost disappear at maximum level")
	_expect(sell_refund_label.text == "+210", "maximum-level sell refund includes every paid level cost")
	building.level = 1
	panel._refresh_action_state()
	panel._update_projection()
	var expected_position := camera.unproject_position(building.get_action_anchor()) + panel.screen_offset
	_expect(panel.position.is_equal_approx(expected_position), "the panel origin matches the selected building projection")
	camera.position += Vector3(1.5, 0.0, 0.0)
	camera.look_at(Vector3.ZERO)
	panel._update_projection()
	expected_position = camera.unproject_position(building.get_action_anchor()) + panel.screen_offset
	_expect(panel.position.is_equal_approx(expected_position), "camera movement keeps every action at its fixed building-relative offset")
	panel._on_info_pressed()
	await process_frame
	var info_page := panel.get_node_or_null("InfoPage") as PanelContainer
	var title := panel.find_child("InfoTitle", true, false) as Label
	var description := panel.find_child("InfoDescription", true, false) as RichTextLabel
	_expect(info_page != null and info_page.visible, "the explanation action expands the information page")
	_expect(title != null and title.text == "测试塔", "the information page starts with the selected building name")
	_expect(
		description != null
		and description.text == definition.get_formatted_inspection_description_bbcode()
		and description.get_parsed_text() == definition.get_formatted_inspection_description(),
		"the information page renders the shared colored labels and white authored text"
	)
	_expect(
		description.get_parsed_text().split("\n").size() == 3
		and description.get_parsed_text().contains("基础描述：")
		and description.get_parsed_text().contains("强化复制：")
		and description.get_parsed_text().contains("强化反射：")
		and not description.get_parsed_text().contains("1级："),
		"tower explanations use exactly three semantic colored-heading rows"
	)
	_expect(
		title.get_theme_font_size("font_size") == 22
		and description.get_theme_font_size("normal_font_size") == 18
		and description.get_theme_constant("line_separation") == -2,
		"the information page uses larger type and tighter line spacing"
	)
	_expect(
		info_page.size.y < 300.0
		and is_equal_approx(info_page.position.y + info_page.size.y, -150.0),
		"short building text shrinks the page while its bottom stays above the actions"
	)
	panel._on_info_pressed()
	_expect(info_page != null and not info_page.visible, "pressing the explanation action again collapses the information page")

	panel._selected_building = null
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
