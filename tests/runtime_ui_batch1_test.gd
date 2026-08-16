extends SceneTree

const TestDefinitionFactory := preload("res://tests/fixtures/TestDefinitionFactory.gd")
const RuntimeInteractionControllerScript := preload("res://scripts/ui/RuntimeInteractionController.gd")
const GameTimeControllerScript := preload("res://scripts/ui/GameTimeController.gd")
const BuildCardBarScript := preload("res://scripts/ui/BuildCardBar.gd")
const TowerCodexPanelScript := preload("res://scripts/ui/TowerCodexPanel.gd")
const RuntimeHudScript := preload("res://scripts/ui/RuntimeHud.gd")
const InspectionDisplayConfigScript := preload("res://scripts/shared/InspectionDisplayConfig.gd")

var _failures: int = 0
var _checks: int = 0
var _placement_results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[RuntimeUiBatch1] running")
	_test_level_and_asset_interfaces()
	var fixture := await _make_fixture()
	await _test_card_bar(fixture)
	await _test_one_shot_placement_and_time_priority(fixture)
	var host: Node = fixture["host"]
	host.queue_free()
	await process_frame
	Engine.time_scale = 1.0
	if _failures == 0:
		print("[RuntimeUiBatch1] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[RuntimeUiBatch1] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_level_and_asset_interfaces() -> void:
	_expect(InputMap.has_action("toggle_building_cards"), "InputMap exposes the F2 building-card toggle")
	var has_f2_binding := InputMap.action_get_events("toggle_building_cards").any(
		func(event: InputEvent) -> bool:
			return event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F2
	)
	_expect(has_f2_binding, "the building-card toggle is bound to physical F2")
	var level := LevelResource.new()
	_expect(level.building_card_slot_count == 6, "levels default to six building card slots")
	var level1 := load("res://resources/levels/Level1.tres") as LevelResource
	var level2 := load("res://resources/levels/Level2.tres") as LevelResource
	var level3 := load("res://resources/levels/Level3.tres") as LevelResource
	var level4 := load("res://resources/levels/Level4.tres") as LevelResource
	_expect(level1 != null and level1.building_card_slot_count == 4, "Level1 exposes four building card slots")
	_expect(level2 != null and level2.building_card_slot_count == 4, "Level2 exposes four building card slots")
	_expect(level3 != null and level3.building_card_slot_count == 4, "Level3 exposes four building card slots")
	_expect(level4 != null and level4.building_card_slot_count == 4, "Level4 exposes four building card slots")
	level.building_card_slot_count = 13
	_expect(
		level.validate_runtime().any(func(message: String) -> bool: return message.contains("卡槽")),
		"level validation rejects out-of-range card slot counts"
	)
	var building := TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	var mirror := TestDefinitionFactory.make_copy_mirror_definition()
	_expect(building.card_icon == null, "building definitions expose an optional card icon")
	_expect(building.full_card_art == null, "building definitions expose an optional complete-card artwork")
	_expect(mirror.card_icon == null, "copy mirror definitions expose an optional card icon")
	var production_arrow := load("res://resources/buildings/ArrowTower.tres") as BuildingDefinition
	var production_mace := load("res://resources/buildings/MaceTower.tres") as BuildingDefinition
	var production_copy := load("res://resources/mirrors/CopyMirror.tres") as CopyMirrorDefinition
	var production_reflector := load("res://resources/mirrors/ReflectMirror.tres") as ReflectMirrorDefinition
	_expect(
		production_arrow != null and production_arrow.full_card_art != null,
		"the production arrow tower configures a no-cost complete card face"
	)
	_expect(
		production_mace != null and production_mace.full_card_art != null,
		"the production mace configures the supplied at.png complete card face"
	)
	_expect(
		production_copy != null and production_reflector != null
		and production_copy.placement_cost > 0.0
		and production_reflector.placement_cost > 0.0,
		"production mirror definitions expose editable positive placement costs"
	)


func _test_card_bar(fixture: Dictionary) -> void:
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var mirror_manager: MirrorManager = fixture["mirror"]
	var card_bar := BuildCardBarScript.new()
	root.add_child(card_bar)
	await process_frame
	var cards: Array[BuildingDefinition] = [
		building_manager.arrow_tower,
		building_manager.laser_tower,
		building_manager.barrier,
	]
	var test_icon := _make_test_card_icon()
	building_manager.arrow_tower.card_icon = test_icon
	building_manager.arrow_tower.full_card_art = _make_test_full_card_art()
	building_manager.arrow_tower.inspection_display = InspectionDisplayConfigScript.new()
	building_manager.arrow_tower.inspection_display.function_description = "基础攻击建筑。"
	building_manager.arrow_tower.copy_enhancement_description = "复制强化效果。"
	building_manager.arrow_tower.reflection_enhancement_description = "反射强化效果。"
	mirror_manager.copy_mirror_definition.inspection_display = InspectionDisplayConfigScript.new()
	mirror_manager.copy_mirror_definition.inspection_display.function_description = "复制镜基础说明。"
	mirror_manager.copy_mirror_definition.upgrade_description = "复制镜升级效果。"
	mirror_manager.reflect_mirror_definition.inspection_display = InspectionDisplayConfigScript.new()
	mirror_manager.reflect_mirror_definition.inspection_display.function_description = "反射镜基础说明。"
	mirror_manager.reflect_mirror_definition.upgrade_description = "反射镜升级效果。"
	card_bar.configure(
		resource_manager,
		mirror_manager.copy_mirror_definition,
		cards,
		6,
		mirror_manager.reflect_mirror_definition,
		mirror_manager
	)
	await process_frame
	_expect(not card_bar.has_signal("cancel_requested"), "right-click cancellation is centralized in the runtime camera click classifier")
	_expect(card_bar.get_building_slot_count() == 6, "card bar respects the configured six-slot capacity")
	_expect(card_bar.get_filled_building_card_count() == 3, "default loadout fills arrow, laser, and barrier cards")
	_expect(card_bar.get_empty_building_card_count() == 3, "unused loadout positions render as three empty mirror slots")
	_expect(card_bar.is_mirror_card_available(), "dedicated mirror card is available outside building slots")
	_expect(card_bar.is_building_card_available(building_manager.arrow_tower), "affordable building card is available")
	_expect(
		card_bar.mirror_upper_color.get_luminance() > 0.88
		and card_bar.mirror_face_color.get_luminance() > 0.65
		and card_bar.mirror_lower_color.get_luminance() > 0.44,
		"procedural mirror palette stays in the bright silver range of the full-card reference"
	)
	_expect(
		card_bar.frame_color.is_equal_approx(Color("dea967")),
		"procedural card frames use the authored #DEA967 color"
	)
	var configured_cards_row := card_bar.get_node("Layout/Cards") as HBoxContainer
	var configured_mirror_cards_row := card_bar.get_node("Layout/MirrorCards") as HBoxContainer
	var arrow_card := configured_cards_row.get_node("BuildingCard1") as Button
	var mirror_surface := arrow_card.get_node_or_null("MirrorSurface") as ColorRect
	var mirror_material := mirror_surface.material as ShaderMaterial if mirror_surface != null else null
	_expect(mirror_surface != null, "filled cards own a generated mirror surface")
	_expect(
		mirror_material != null
		and mirror_material.shader != null
		and mirror_material.shader.code.contains("moving_sheen"),
		"generated card surfaces use the procedural mirror shader"
	)
	var artwork := arrow_card.get_node_or_null("Content/Artwork") as TextureRect
	_expect(
		artwork != null
		and artwork.texture == test_icon
		and artwork.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"card_icon is treated as centered building artwork instead of a complete card face"
	)
	_expect(
		(arrow_card.get_node("Content/Title") as Label).text == building_manager.arrow_tower.display_name,
		"card title remains data-driven above the supplied artwork"
	)
	_expect(
		(arrow_card.get_node("Content/Footer") as Label).text.begins_with("◆ "),
		"card cost remains data-driven below the supplied artwork"
	)
	var building_cost_color := (arrow_card.get_node("Content/Footer") as Label).get_theme_color("font_color")
	var copy_mirror_cost_color := (configured_mirror_cards_row.get_node("MirrorCard/Content/Footer") as Label).get_theme_color("font_color")
	var reflect_mirror_cost_color := (configured_mirror_cards_row.get_node("ReflectMirrorCard/Content/Footer") as Label).get_theme_color("font_color")
	_expect(
		copy_mirror_cost_color.is_equal_approx(building_cost_color)
		and reflect_mirror_cost_color.is_equal_approx(building_cost_color),
		"both mirror costs use the same yellow as procedural building costs"
	)
	var original_building_cap := resource_manager.building_cap
	resource_manager.building_cap = resource_manager.get_building_count()
	resource_manager._emit_limits_changed()
	_expect(
		(arrow_card.get_node("Content/Footer") as Label).text == "已达上限"
		and arrow_card.disabled,
		"procedural building cards show the mirror-style capacity message at the building cap"
	)
	resource_manager.building_cap = original_building_cap
	resource_manager._emit_limits_changed()
	_expect(
		(arrow_card.get_node("Content/Footer") as Label).text
		== "◆ %d" % ceili(building_manager.arrow_tower.get_level_stats(1).cost),
		"building card cost returns when capacity becomes available"
	)
	var copy_mirror_card := configured_mirror_cards_row.get_node("MirrorCard") as Button
	copy_mirror_card.mouse_entered.emit()
	await process_frame
	var description_panel := card_bar.get_node("CardDescriptionPanel") as PanelContainer
	var description_title := card_bar.get_node("CardDescriptionPanel/Content/Title") as Label
	var description_text := card_bar.get_node("CardDescriptionPanel/Content/Description") as RichTextLabel
	_expect(
		description_panel.visible
		and description_title.text == mirror_manager.copy_mirror_definition.get_resolved_inspection_display_name()
		and description_text.text == mirror_manager.copy_mirror_definition.get_formatted_inspection_description_bbcode()
		and description_text.get_parsed_text()
		== mirror_manager.copy_mirror_definition.get_formatted_inspection_description(),
		"copy-mirror card hover uses its shared two-row semantic description"
	)
	_expect(
		description_text.get_parsed_text().split("\n").size() == 2
		and description_text.get_parsed_text().contains("基础描述：")
		and description_text.get_parsed_text().contains("升级："),
		"mirror card descriptions contain only base and upgrade rows"
	)
	copy_mirror_card.mouse_exited.emit()
	var reflect_mirror_card := configured_mirror_cards_row.get_node("ReflectMirrorCard") as Button
	_expect(
		is_equal_approx(copy_mirror_card.position.y, reflect_mirror_card.position.y)
		and reflect_mirror_card.position.x >= copy_mirror_card.get_rect().end.x,
		"copy and reflect mirror cards are laid out side by side"
	)
	reflect_mirror_card.mouse_entered.emit()
	await process_frame
	_expect(
		description_panel.visible
		and description_title.text == mirror_manager.reflect_mirror_definition.get_resolved_inspection_display_name()
		and description_text.text == mirror_manager.reflect_mirror_definition.get_formatted_inspection_description_bbcode()
		and description_text.get_parsed_text()
		== mirror_manager.reflect_mirror_definition.get_formatted_inspection_description(),
		"reflect-mirror card hover uses its own editable two-row description"
	)
	_expect(
		card_bar.get_viewport_rect().has_point(description_panel.get_global_rect().position)
		and description_panel.get_global_rect().position.y >= reflect_mirror_card.get_global_rect().end.y,
		"top-left mirror descriptions stay on-screen below their cards"
	)
	reflect_mirror_card.mouse_exited.emit()
	arrow_card.mouse_entered.emit()
	await process_frame
	_expect(description_panel.visible, "hovering a building card opens its description panel")
	_expect(
		description_title.text == building_manager.arrow_tower.get_resolved_inspection_display_name()
		and description_text.text == building_manager.arrow_tower.get_formatted_inspection_description_bbcode()
		and description_text.get_parsed_text()
		== building_manager.arrow_tower.get_formatted_inspection_description(),
		"card hover and the selected-building info action share one formatted text source"
	)
	_expect(
		description_text.get_parsed_text().split("\n").size() == 3
		and description_text.get_parsed_text().contains("基础描述：")
		and description_text.get_parsed_text().contains("强化复制：")
		and description_text.get_parsed_text().contains("强化反射："),
		"tower card descriptions contain the three semantic rows"
	)
	_expect(
		description_title.get_theme_font_size("font_size") == 22
		and description_text.get_theme_font_size("normal_font_size") == 18
		and description_text.get_theme_constant("line_separation") == -2,
		"card descriptions use larger text with compact line spacing"
	)
	_expect(
		description_panel.size.y < card_bar.card_description_size.y
		and description_panel.size.is_equal_approx(description_panel.get_combined_minimum_size()),
		"short card descriptions shrink to their wrapped content height"
	)
	var hovered_card_rect := arrow_card.get_global_rect()
	var description_rect := description_panel.get_global_rect()
	_expect(
		absf(description_rect.get_center().x - hovered_card_rect.get_center().x) < 0.1
		and description_rect.end.y <= hovered_card_rect.position.y - card_bar.card_description_gap + 0.1,
		"the description panel is centered directly above its building slot"
	)
	arrow_card.mouse_exited.emit()
	_expect(not description_panel.visible, "leaving the building card closes its description panel")
	_expect(
		configured_cards_row.get_node_or_null("EmptyCard4/MirrorSurface") != null,
		"empty slots reuse the generated mirror treatment"
	)
	card_bar.set_selected_building(building_manager.arrow_tower)
	_expect(
		is_equal_approx(float(mirror_material.get_shader_parameter("selected_strength")), 1.0),
		"selected cards promote the generated mirror highlight"
	)
	card_bar.clear_selection()

	resource_manager.spend(resource_manager.main_resource, "test_empty_wallet")
	_expect(not card_bar.is_building_card_available(building_manager.arrow_tower), "resource shortage disables building cards")
	_expect(
		float(mirror_material.get_shader_parameter("disabled_strength")) > 0.0,
		"resource shortage desaturates the generated mirror surface"
	)
	_expect(not card_bar.is_mirror_card_available(), "coin-mode mirror cards follow the main-resource balance")
	resource_manager.gain(500.0, "test_restore_wallet")
	_expect(card_bar.is_building_card_available(building_manager.arrow_tower), "resource gain immediately restores card availability")
	_expect(card_bar.is_mirror_card_available(), "resource gain immediately restores an affordable mirror card")
	card_bar.set_card_visual_mode(BuildCardBarScript.CardVisualMode.FULL_ARTWORK)
	_expect(
		card_bar.get_card_visual_mode() == BuildCardBarScript.CardVisualMode.FULL_ARTWORK,
		"card bar switches to the alternate complete-artwork mode"
	)
	configured_cards_row = card_bar.get_node("Layout/Cards") as HBoxContainer
	configured_mirror_cards_row = card_bar.get_node("Layout/MirrorCards") as HBoxContainer
	var full_art_card := configured_cards_row.get_node("BuildingCard1") as Button
	var full_artwork := full_art_card.get_node_or_null("FullArtwork") as TextureRect
	_expect(
		full_artwork != null and full_artwork.texture is AtlasTexture,
		"complete artwork automatically trims transparent source padding"
	)
	full_art_card.mouse_entered.emit()
	await process_frame
	description_panel = card_bar.get_node("CardDescriptionPanel") as PanelContainer
	_expect(
		description_panel.visible
		and (card_bar.get_node("CardDescriptionPanel/Content/Description") as RichTextLabel).text
		== building_manager.arrow_tower.get_formatted_inspection_description_bbcode(),
		"complete-artwork building cards use the same hover description"
	)
	full_art_card.mouse_exited.emit()
	_expect(
		full_art_card.get_node_or_null("MirrorSurface") == null
		and full_art_card.get_node_or_null("InnerFrame") == null
		and full_art_card.get_node_or_null("Content/Title") == null,
		"complete-artwork cards hide the generated slot, frame and building title"
	)
	var live_cost := full_art_card.get_node_or_null("Cost") as Label
	_expect(
		live_cost != null
		and live_cost.text == "◆ %d" % ceili(building_manager.arrow_tower.get_level_stats(1).cost)
		and live_cost.position.y < card_bar.card_size.y * 0.5,
		"complete artwork overlays the live cost above the building"
	)
	resource_manager.building_cap = resource_manager.get_building_count()
	resource_manager._emit_limits_changed()
	_expect(
		live_cost != null and live_cost.text == "已达上限" and full_art_card.disabled,
		"complete-artwork building cards show the same capacity message"
	)
	resource_manager.building_cap = original_building_cap
	resource_manager._emit_limits_changed()
	var invisible_empty := configured_cards_row.get_node("EmptyCard4") as Control
	_expect(
		invisible_empty.get_child_count() == 0
		and invisible_empty.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"alternate-mode empty building slots are invisible and input-transparent"
	)
	_expect(
		configured_mirror_cards_row.get_node_or_null("MirrorCard/MirrorSurface") != null,
		"dedicated mirror cards retain their cooldown-capable procedural treatment"
	)
	var full_art_selections: Array[BuildingDefinition] = []
	card_bar.building_card_selected.connect(
		func(definition: BuildingDefinition) -> void: full_art_selections.append(definition)
	)
	full_art_card.pressed.emit()
	_expect(
		full_art_selections == [building_manager.arrow_tower],
		"the artwork itself remains the complete clickable building-card target"
	)
	card_bar.queue_free()
	await process_frame

	var hud_scene := load("res://scenes/ui/RuntimeHud.tscn") as PackedScene
	_expect(hud_scene != null, "runtime HUD scene loads as a modular component")
	if hud_scene != null:
		var hud := hud_scene.instantiate()
		root.add_child(hud)
		await process_frame
		_expect(hud.get_node_or_null("BuildCardBar") != null, "runtime HUD owns the formal card UI")
		var tower_codex := hud.get_node_or_null("TowerCodexPanel") as TowerCodexPanelScript
		_expect(tower_codex != null and tower_codex.visible, "the read-only tower codex is visible by default")
		var codex_definitions: Array[BuildingDefinition] = []
		var codex_names := PackedStringArray(["箭塔", "冰冻塔", "导弹塔", "镭射塔"])
		var codex_kinds: Array[BuildingDefinition.Kind] = [
			BuildingDefinition.Kind.ARROW_TOWER,
			BuildingDefinition.Kind.LASER_TOWER,
			BuildingDefinition.Kind.CROSSBOW_TOWER,
			BuildingDefinition.Kind.PULSE_LASER_TOWER,
		]
		for index in range(codex_names.size()):
			var codex_definition := TestDefinitionFactory.make_building_definition(codex_kinds[index])
			codex_definition.display_name = codex_names[index]
			codex_definition.card_icon = _make_test_card_icon()
			codex_definition.inspection_display = InspectionDisplayConfigScript.new()
			codex_definition.inspection_display.function_description = "%s基础说明。" % codex_names[index]
			codex_definition.copy_enhancement_description = "%s复制强化。" % codex_names[index]
			codex_definition.reflection_enhancement_description = "%s反射强化。" % codex_names[index]
			codex_definitions.append(codex_definition)
		if tower_codex != null:
			tower_codex.configure(codex_definitions)
		await process_frame
		var codex_cards := hud.get_node("TowerCodexPanel/Cards") as VBoxContainer
		_expect(
			tower_codex != null and tower_codex.get_definition_count() == 4
			and codex_cards.get_child_count() == 4,
			"the tower codex contains exactly four authored entries"
		)
		for index in range(codex_names.size()):
			var codex_card := codex_cards.get_node("TowerCard%d" % (index + 1)) as PanelContainer
			_expect(
				(codex_card.get_node("Content/Title") as Label).text == codex_names[index]
				and (codex_card.get_node("Content/Icon") as TextureRect).texture
				== codex_definitions[index].card_icon,
				"codex entry %d preserves the requested tower order, icon, and name" % (index + 1)
			)
			_expect(
				not codex_card.has_signal("pressed")
				and not codex_card.has_method("set_pressed")
				and codex_card.get_node_or_null("Content/Cost") == null
				and codex_card.get_node_or_null("Content/Footer") == null,
				"codex entry %d is read-only and contains no price" % (index + 1)
			)
			if index > 0:
				var previous_card := codex_cards.get_child(index - 1) as Control
				_expect(
					codex_card.position.y >= previous_card.get_rect().end.y,
					"codex entry %d is stacked below the previous entry" % (index + 1)
				)
		var hovered_codex_card := codex_cards.get_node("TowerCard3") as PanelContainer
		hovered_codex_card.mouse_entered.emit()
		await process_frame
		var codex_description := hud.get_node("TowerCodexPanel/DescriptionPanel") as PanelContainer
		_expect(
			codex_description.visible
			and (hud.get_node("TowerCodexPanel/DescriptionPanel/Content/Title") as Label).text == "导弹塔"
			and (hud.get_node("TowerCodexPanel/DescriptionPanel/Content/Description") as RichTextLabel).text
			== codex_definitions[2].get_formatted_inspection_description_bbcode(),
			"hovering a codex card shows its shared formatted tower description"
		)
		_expect(
			codex_description.get_global_rect().position.x
			>= hovered_codex_card.get_global_rect().end.x + tower_codex.description_gap - 0.1,
			"tower codex descriptions open to the right of their card"
		)
		hovered_codex_card.mouse_exited.emit()
		_expect(not codex_description.visible, "leaving a codex card closes its description")
		var formal_card_bar := hud.get_node("BuildCardBar") as BuildCardBarScript
		var formal_mirror_row := hud.get_node("BuildCardBar/Layout/MirrorCards") as HBoxContainer
		_expect(not hud.are_building_cards_visible(), "formal building cards default to closed")
		_expect(formal_mirror_row.visible, "mirror cards remain visible while building cards are closed")
		hud.toggle_building_cards()
		_expect(
			hud.are_building_cards_visible() and tower_codex.visible,
			"the formal toggle opens only the building-card row and leaves the codex visible"
		)
		hud.toggle_building_cards()
		_expect(
			not hud.are_building_cards_visible() and tower_codex.visible,
			"the formal toggle closes only the building-card row and leaves the codex visible"
		)
		var legacy_status := hud.get_node_or_null("BuildCardBar/Layout/Status") as Label
		_expect(legacy_status != null and not legacy_status.visible, "the fixed placement debug status stays hidden")
		_expect(
			RuntimeHudScript.resolve_placement_failure_message("地块已被占用") == "该格子不可放置！"
			and RuntimeHudScript.resolve_placement_failure_message("敌人路径只能放置屏障") == "该格子不可放置！"
			and RuntimeHudScript.resolve_placement_failure_message("Stuff 阻止建造") == "该格子不可放置！",
			"tile, enemy-path, and Stuff failures share the approved placement message"
		)
		_expect(
			RuntimeHudScript.resolve_placement_failure_message("已达到建筑上限") == "该类建筑已经达到上限！"
			and RuntimeHudScript.resolve_placement_failure_message("该障碍会堵死出生点到据点的全部可用路径") == "不能将敌人的路堵死！",
			"capacity and path-connectivity failures use their dedicated messages"
		)
		_expect(
			RuntimeHudScript.resolve_placement_failure_message("建筑系统依赖尚未注入").is_empty(),
			"unapproved placement failures remain silent"
		)
		var feedback := hud.get_node_or_null("ActionFeedback") as Label
		if feedback != null:
			_expect(
				feedback.get_theme_font_size("font_size") > legacy_status.get_theme_font_size("font_size")
				and feedback.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.46, 0.38, 1.0)),
				"floating feedback keeps the original error color and uses a larger font"
			)
			hud.feedback_hold_duration = 0.0
			hud.feedback_fade_duration = 0.05
			hud.show_upgrade_failure(Vector2(620.0, 360.0))
			_expect(
				feedback.visible and feedback.text == "金币不足！",
				"upgrade failures use the approved insufficient-coins message"
			)
			hud.show_placement_failure("地块已被占用", Vector2(520.0, 340.0))
			_expect(
				feedback.visible and feedback.text == "该格子不可放置！" and feedback.modulate.a == 1.0,
				"approved failure feedback appears immediately at full opacity"
			)
			_expect(
				feedback.get_rect().grow(24.0).has_point(Vector2(520.0, 340.0)),
				"failure feedback is positioned around the triggering click"
			)
			hud.show_adjustment_failure(false, Vector2(480.0, 320.0))
			_expect(
				feedback.visible and feedback.text == "该块不可放置" and feedback.modulate.a == 1.0,
				"invalid tile adjustment uses the requested click-position message"
			)
			hud.show_adjustment_failure(true, Vector2(560.0, 320.0))
			_expect(
				feedback.visible and feedback.text == "该边不可放置" and feedback.modulate.a == 1.0,
				"invalid edge adjustment uses the requested click-position message"
			)
			_expect(
				feedback.get_rect().grow(24.0).has_point(Vector2(560.0, 320.0)),
				"adjustment failure feedback follows the confirming click"
			)
			await create_timer(0.2, true, false, true).timeout
			await process_frame
			_expect(not feedback.visible, "failure feedback fades out and hides")
		var style_toggle := hud.get_node_or_null("CardStyleToggle") as Button
		_expect(style_toggle != null, "runtime HUD owns the top-left card-style toggle")
		_expect(
			style_toggle != null and style_toggle.text.contains("程序镜面"),
			"the style toggle defaults to the existing procedural implementation"
		)
		if style_toggle != null:
			style_toggle.pressed.emit()
			_expect(
				(hud.get_node("BuildCardBar") as BuildCardBarScript).get_card_visual_mode()
				== BuildCardBarScript.CardVisualMode.FULL_ARTWORK
				and style_toggle.text.contains("原画卡面"),
				"the top-left button switches the card bar to complete artwork"
			)
			style_toggle.pressed.emit()
		_expect(hud.get_node_or_null("TimeControlPanel/Controls/TacticalSlowButton") != null, "runtime HUD owns the automatic slow toggle")
		var debug_overlay := hud.get_node("DebugOverlayPanel") as Control
		_expect(
			style_toggle == null or not style_toggle.get_global_rect().intersects(debug_overlay.get_global_rect()),
			"the relocated debug overlay leaves the top-left style toggle unobstructed"
		)
		_expect(
			not formal_mirror_row.get_global_rect().intersects(debug_overlay.get_global_rect()),
			"the relocated debug overlay leaves both top-left mirror cards unobstructed"
		)
		var lighting_test_panel_rect := Rect2(16.0, 16.0, 774.0, 42.0)
		_expect(
			style_toggle == null or not style_toggle.get_global_rect().intersects(lighting_test_panel_rect),
			"the top-left style toggle stays below the runtime lighting test panel"
		)
		var original_window_size := root.size
		for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
			root.size = resolution
			await process_frame
			var cards_row := hud.get_node("BuildCardBar/Layout/Cards") as Control
			var mirror_cards_row := hud.get_node("BuildCardBar/Layout/MirrorCards") as Control
			var tower_codex_cards := hud.get_node("TowerCodexPanel/Cards") as Control
			var slow_button := hud.get_node("TimeControlPanel/Controls/TacticalSlowButton") as Control
			# canvas_items keeps the authored 1600x900 logical viewport while the
			# Window scales it to each physical 16:9 resolution.
			var viewport_rect := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
			_expect(
				hud.get_node_or_null("BuildCardBar/Layout/Frame") == null,
				"card bar has no outer frame slot at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				cards_row.get_parent() == hud.get_node("BuildCardBar/Layout"),
				"cards are direct layout children at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				cards_row.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"card row gaps do not intercept world input at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				viewport_rect.encloses(cards_row.get_global_rect()),
				"card row stays inside the %dx%d viewport" % [resolution.x, resolution.y]
			)
			_expect(
				viewport_rect.encloses(mirror_cards_row.get_global_rect())
				and mirror_cards_row.position.is_equal_approx(formal_card_bar.mirror_cards_position),
				"two mirror cards stay together at the authored top-left position at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				viewport_rect.encloses(tower_codex_cards.get_global_rect())
				and tower_codex_cards.position.is_equal_approx(tower_codex.codex_position)
				and not tower_codex_cards.get_global_rect().intersects(mirror_cards_row.get_global_rect()),
				"the four-card tower codex stays on the left below the mirror row at %dx%d" % [resolution.x, resolution.y]
			)
			_expect(
				not cards_row.get_global_rect().intersects(slow_button.get_global_rect()),
				"card row does not overlap the slow button at %dx%d" % [resolution.x, resolution.y]
			)
		root.size = original_window_size
		hud.queue_free()
		await process_frame


func _test_one_shot_placement_and_time_priority(fixture: Dictionary) -> void:
	var resource_manager: ResourceManager = fixture["resource"]
	var building_manager: BuildingManager = fixture["building"]
	var mirror_manager: MirrorManager = fixture["mirror"]
	var grid: GridManager = fixture["grid"]
	var interaction := RuntimeInteractionControllerScript.new()
	fixture["host"].add_child(interaction)
	interaction.configure(building_manager, mirror_manager)
	interaction.placement_resolved.connect(_on_placement_resolved)
	var time_controller := GameTimeControllerScript.new()
	fixture["host"].add_child(time_controller)
	await process_frame
	time_controller.configure(interaction, building_manager, mirror_manager)

	_expect(interaction.select_building_card(building_manager.arrow_tower), "an available building card enters placement mode")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "selecting a card activates default tactical slow")
	time_controller.set_fast_enabled(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "tactical slow overrides the remembered 2x request")
	_expect(
		building_manager.update_preview(Vector3i(0, 0, 0), building_manager.arrow_tower),
		"building placement mode creates a rotatable preview"
	)
	var preview_before := building_manager.get_preview_facing_index()
	var main := MainController.new()
	var test_hud := RuntimeHud.new()
	var test_stuff_editor := RuntimeStuffEditorController.new()
	main.building_manager = building_manager
	main.runtime_interaction = interaction
	main.mirror_manager = mirror_manager
	main.runtime_hud = test_hud
	main.runtime_stuff_editor = test_stuff_editor
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	_expect(
		main._handle_building_rotation_wheel(wheel_up)
		and building_manager.get_preview_facing_index() == posmod(preview_before + 1, 36),
		"wheel up rotates the active placement preview instead of zooming"
	)
	preview_before = building_manager.get_preview_facing_index()
	_expect(main._rotate_active_building_target(), "the first R action rotates the active placement preview")
	main._selected_rotation_repeat.configure(0.1, 0.1, 4)
	main._selected_rotation_repeat.press()
	Input.action_press("rotate_facing")
	main._update_selected_rotation_repeat(0.31)
	Input.action_release("rotate_facing")
	main._update_selected_rotation_repeat(0.1)
	var preview_facing := building_manager.get_preview_facing_index()
	_expect(
		preview_facing == posmod(preview_before + 4, 36),
		"holding R continuously advances the building placement preview"
	)
	_expect(not main._selected_rotation_repeat.is_active(), "releasing R stops preview rotation immediately")

	var first_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(first_result.success, "valid tile placement succeeds")
	var first_building := building_manager.get_building(Vector3i(0, 0, 0))
	_expect(
		first_building != null and first_building.facing_index == preview_facing,
		"confirmed building preserves the continuously rotated preview facing"
	)
	_expect(building_manager.get_selected_building() == null, "newly placed building is not auto-selected by the formal interaction")
	building_manager.select_building(first_building)
	var placed_facing_before := first_building.facing_index
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	_expect(
		main._handle_building_rotation_wheel(wheel_down)
		and first_building.facing_index == placed_facing_before
		and building_manager.get_preview_building() != null
		and building_manager.get_preview_building().facing_index == posmod(
			placed_facing_before - 1,
			first_building.get_facing_slot_count()
		),
		"selected-building wheel rotation changes only its adjustment candidate"
	)
	main._confirm_pending_adjustment(Vector2.ZERO)
	_expect(
		first_building.facing_index == posmod(
			placed_facing_before - 1,
			first_building.get_facing_slot_count()
		)
		and building_manager.get_selected_building() == null,
		"a separate confirmation applies selected-building rotation and exits selection"
	)
	_expect(
		not main._handle_building_rotation_wheel(wheel_down),
		"wheel input falls back to camera zoom after building selection is cleared"
	)
	test_hud.free()
	test_stuff_editor.free()
	main.free()
	_expect(interaction.is_select_mode(), "successful placement consumes the card and returns to select")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 2.0), "successful placement restores the remembered fast scale")
	_expect(_placement_results.size() == 1, "one successful click emits exactly one placement result")

	time_controller.set_fast_enabled(false)
	resource_manager.main_resource = 0.0
	interaction.select_building_card(building_manager.arrow_tower)
	var resource_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(1, 0, 0)},
		{"hit": false}
	)
	_expect(not resource_result.success and resource_result.reason.contains("资源"), "resource failure reports its concrete reason")
	_expect(interaction.is_select_mode(), "resource failure also consumes the selected card")
	_expect(_placement_results.size() == 2, "resource failure emits exactly one placement result")

	resource_manager.main_resource = 500.0
	resource_manager.building_cap = resource_manager.get_building_count()
	interaction.select_building_card(building_manager.arrow_tower)
	var cap_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(1, 0, 0)},
		{"hit": false}
	)
	_expect(not cap_result.success and cap_result.reason.contains("上限"), "building cap failure reports its concrete reason")
	_expect(interaction.is_select_mode(), "cap failure consumes the selected card")
	_expect(_placement_results.size() == 3, "cap failure emits exactly one placement result")

	resource_manager.building_cap = 20
	interaction.select_building_card(building_manager.arrow_tower)
	var occupied_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(not occupied_result.success and occupied_result.reason.contains("占用"), "invalid occupied tile reports placement rejection")
	_expect(interaction.is_select_mode(), "invalid tile consumes the selected card")
	_expect(_placement_results.size() == 4, "invalid tile emits exactly one placement result")

	interaction.select_copy_mirror_card()
	_expect(interaction.get_mirror_placement_edge_index() == 0, "mirror placement starts on the first edge of the hovered tile")
	var mirror_input_main := MainController.new()
	mirror_input_main.grid = grid
	mirror_input_main.runtime_interaction = interaction
	_expect(
		mirror_input_main._handle_building_rotation_wheel(wheel_up)
		and interaction.get_mirror_placement_edge_index() == 1,
		"wheel up rotates a placing mirror to the next tile edge instead of zooming"
	)
	_expect(
		mirror_input_main._handle_building_rotation_wheel(wheel_down)
		and interaction.get_mirror_placement_edge_index() == 0,
		"wheel down rotates a placing mirror to the previous tile edge instead of zooming"
	)
	mirror_input_main.free()
	var mirror_target_cell := Vector3i(0, 1, 0)
	var resolved_mirror_edge := interaction.resolve_mirror_placement_edge_pick(
		{"hit": true, "cell": mirror_target_cell},
		grid
	)
	_expect(
		resolved_mirror_edge.hit and resolved_mirror_edge.edge_index == 0,
		"mirror placement resolves an edge from the selected tile instead of mouse-edge proximity"
	)
	for expected_edge_index in range(1, grid.edge_count()):
		interaction.rotate_mirror_placement_edge(grid.edge_count())
		resolved_mirror_edge = interaction.resolve_mirror_placement_edge_pick(
			{"hit": true, "cell": mirror_target_cell},
			grid
		)
		_expect(
			resolved_mirror_edge.edge_index == expected_edge_index,
			"R advances mirror placement to tile edge %d" % expected_edge_index
		)
	interaction.rotate_mirror_placement_edge(grid.edge_count())
	resolved_mirror_edge = interaction.resolve_mirror_placement_edge_pick(
		{"hit": true, "cell": mirror_target_cell},
		grid
	)
	_expect(resolved_mirror_edge.edge_index == 0, "mirror placement wraps after every tile edge")
	_expect(
		mirror_manager.update_preview(
			resolved_mirror_edge.cell,
			resolved_mirror_edge.edge_index,
			true
		),
		"tile-based mirror placement creates a preview on the resolved edge"
	)
	_expect(
		mirror_manager.get_preview_mirror().get_active_cell() == mirror_target_cell,
		"mirror preview gameplay side faces the selected tile"
	)
	mirror_manager.clear_preview()
	var missing_edge_result := interaction.handle_primary(
		{"hit": true, "cell": mirror_target_cell},
		{"hit": false}
	)
	_expect(not missing_edge_result.success and missing_edge_result.reason.contains("地格"), "missing tile is a concrete failed mirror attempt")
	_expect(interaction.is_select_mode(), "invalid edge consumes the selected mirror card")
	_expect(_placement_results.size() == 5, "invalid edge emits exactly one placement result")

	interaction.select_reflect_mirror_card()
	resolved_mirror_edge = interaction.resolve_mirror_placement_edge_pick(
		{"hit": true, "cell": mirror_target_cell},
		grid
	)
	_expect(
		mirror_manager.update_reflect_preview(
			resolved_mirror_edge.cell,
			resolved_mirror_edge.edge_index,
			true
		),
		"reflect-mirror placement uses the same selected-tile edge slot"
	)
	_expect(mirror_manager.get_preview_mirror() is ReflectMirror, "selected-tile preview preserves the reflect-mirror kind")
	_expect(
		mirror_manager.get_preview_mirror().get_active_cell() == mirror_target_cell,
		"reflect-mirror preview gameplay side also faces the selected tile"
	)
	interaction.cancel_to_select(true)

	var edge_index := grid.find_edge_index(Vector3i(0, 1, 0), Vector3i(1, 1, 0))
	interaction.select_copy_mirror_card()
	var mirror_result := interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 1, 0)},
		{
			"hit": true,
			"cell": Vector3i(0, 1, 0),
			"edge_index": edge_index,
			"id": grid.canonical_edge_id(Vector3i(0, 1, 0), edge_index),
		}
	)
	_expect(mirror_result.success, "valid edge places the dedicated copy mirror")
	var placed_mirror := mirror_manager.get_mirrors().back() as CopyMirror
	_expect(placed_mirror.get_active_cell() == Vector3i(0, 1, 0), "placed mirror gameplay side faces its selected tile")
	_expect(interaction.is_select_mode() and mirror_manager.get_selected_mirror() == null, "mirror placement also returns to unselected select mode")
	_expect(_placement_results.size() == 6, "mirror success emits exactly one placement result")
	mirror_manager.select_mirror(placed_mirror)
	var selected_mirror_edge_before := placed_mirror.edge_index
	var selected_mirror_active_cell := placed_mirror.get_active_cell()
	var selected_mirror_input_main := MainController.new()
	selected_mirror_input_main.grid = grid
	selected_mirror_input_main.runtime_interaction = interaction
	selected_mirror_input_main.mirror_manager = mirror_manager
	_expect(
		selected_mirror_input_main._handle_building_rotation_wheel(wheel_up)
		and placed_mirror.edge_index == selected_mirror_edge_before
		and mirror_manager.get_preview_mirror() != null
		and mirror_manager.get_preview_mirror().edge_index == wrapi(
			selected_mirror_edge_before + 1,
			0,
			grid.edge_count()
		),
		"selected-mirror wheel rotation changes only its edge adjustment candidate"
	)
	_expect(
		placed_mirror.get_active_cell() == selected_mirror_active_cell,
		"unconfirmed selected-mirror rotation keeps the original active face and edge"
	)
	selected_mirror_input_main._confirm_pending_adjustment(Vector2.ZERO)
	_expect(
		placed_mirror.edge_index == wrapi(selected_mirror_edge_before + 1, 0, grid.edge_count())
		and placed_mirror.get_active_cell() == selected_mirror_active_cell
		and mirror_manager.get_selected_mirror() == null,
		"separate mirror confirmation applies rotation, preserves its anchor, and exits selection"
	)
	selected_mirror_input_main.free()

	interaction.handle_primary(
		{"hit": true, "cell": Vector3i(0, 0, 0)},
		{"hit": false}
	)
	_expect(building_manager.get_selected_building() != null, "select mode can select an existing real building")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "selecting a real building activates tactical slow")
	interaction.cancel_to_select(true)
	_expect(building_manager.get_selected_building() == null, "right-click contract clears real building selection")
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "cancelling real selection restores normal time")

	interaction.select_building_card(building_manager.arrow_tower)
	time_controller.set_tactical_slow_enabled(false)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "slow toggle disables automatic tactical scaling")
	time_controller.set_playback_scale(4.0)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 4.0), "4x applies while automatic slow is disabled")
	time_controller.set_tactical_slow_enabled(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "re-enabling slow overrides the remembered 4x request")
	time_controller.set_paused(true)
	_expect(is_zero_approx(time_controller.get_effective_scale()), "pause has priority over tactical slow")
	time_controller.set_paused(false)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 0.1), "leaving pause restores the active tactical context")
	interaction.cancel_to_select(true)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 4.0), "leaving tactical context restores the remembered 4x request")
	time_controller.set_playback_scale(1.0)
	_expect(is_equal_approx(time_controller.get_effective_scale(), 1.0), "clearing every context restores 1x")


func _make_fixture() -> Dictionary:
	var host := Node3D.new()
	root.add_child(host)
	var grid := GridManager.new()
	host.add_child(grid)
	var tile_manager := TileManager.new()
	host.add_child(tile_manager)
	tile_manager.set_grid(grid)
	var resource_manager := ResourceManager.new()
	host.add_child(resource_manager)
	var combat_manager := CombatManager.new()
	host.add_child(combat_manager)
	var registry := EdgeOccupancyRegistry.new()
	var building_manager := BuildingManager.new()
	host.add_child(building_manager)
	building_manager.arrow_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.ARROW_TOWER)
	building_manager.laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.LASER_TOWER)
	building_manager.pulse_laser_tower = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.PULSE_LASER_TOWER)
	building_manager.barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.BARRIER)
	building_manager.edge_barrier = TestDefinitionFactory.make_building_definition(BuildingDefinition.Kind.EDGE_BARRIER)
	building_manager.set_edge_occupancy_registry(registry)
	building_manager.configure(grid, tile_manager, resource_manager, combat_manager)
	var mirror_manager := MirrorManager.new()
	host.add_child(mirror_manager)
	mirror_manager.copy_mirror_definition = TestDefinitionFactory.make_copy_mirror_definition()
	mirror_manager.copy_mirror_definition.placement_cost = 40.0
	mirror_manager.reflect_mirror_definition = TestDefinitionFactory.make_reflect_mirror_definition()
	mirror_manager.reflect_mirror_definition.placement_cost = 60.0
	mirror_manager.configure(grid, tile_manager, resource_manager, combat_manager, building_manager, registry)
	var loader := LevelLoader.new()
	host.add_child(loader)
	loader.configure(grid, tile_manager)
	var level := _make_level()
	resource_manager.apply_level_configuration(level)
	_expect(loader.load_level(level, "memory://runtime-ui"), "runtime UI fixture level loads")
	await process_frame
	return {
		"host": host,
		"grid": grid,
		"tile": tile_manager,
		"resource": resource_manager,
		"combat": combat_manager,
		"building": building_manager,
		"mirror": mirror_manager,
	}


func _make_test_card_icon() -> Texture2D:
	var image := Image.create(12, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.84, 0.58, 0.26, 1.0))
	return ImageTexture.create_from_image(image)


func _make_test_full_card_art() -> Texture2D:
	var image := Image.create(40, 60, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(10, 6, 20, 48), Color(0.74, 0.64, 0.52, 1.0))
	return ImageTexture.create_from_image(image)


func _make_level() -> LevelResource:
	var level := LevelResource.new()
	level.grid_shape = GridManager.Shape.SQUARE
	level.grid_cell_size = 1.0
	level.grid_size = Vector2i(4, 3)
	level.initial_resource = 500
	level.building_cap = 20
	level.copy_mirror_cap = 5
	level.reflect_mirror_cap = 10
	level.base_resource_per_second = 0.0
	level.base_cell = Vector3i(3, 2, 0)
	return level


func _on_placement_resolved(success: bool, reason: String) -> void:
	_placement_results.append({"success": success, "reason": reason})


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
