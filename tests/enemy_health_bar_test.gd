extends SceneTree

const EnemyHealthBarScript := preload("res://scripts/ui/EnemyHealthBar3D.gd")
const EnemyHitParticlesScript := preload("res://scripts/fx/EnemyHitParticles.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[EnemyHealthBar] running")
	_test_absolute_hp_sizing()
	await _test_damage_presentation()
	await _test_enemy_integration()
	if _failures == 0:
		print("[EnemyHealthBar] PASS: %d checks" % _checks)
		quit(0)
	else:
		push_error("[EnemyHealthBar] FAIL: %d/%d checks failed" % [_failures, _checks])
		quit(1)


func _test_absolute_hp_sizing() -> void:
	var low_width := EnemyHealthBarScript.calculate_width_for_hp(10.0)
	var regular_width := EnemyHealthBarScript.calculate_width_for_hp(100.0)
	var elite_width := EnemyHealthBarScript.calculate_width_for_hp(200.0)
	var extreme_width := EnemyHealthBarScript.calculate_width_for_hp(100000.0)
	_expect(is_equal_approx(low_width, EnemyHealthBarScript.MINIMUM_WIDTH), "small HP bars use the minimum length")
	_expect(regular_width < elite_width, "bar length grows with absolute maximum HP")
	_expect(is_equal_approx(elite_width, 2.0 * regular_width), "unclamped bar length is linearly proportional to absolute HP")
	_expect(is_equal_approx(extreme_width, EnemyHealthBarScript.MAXIMUM_WIDTH), "large HP bars use the maximum length")


func _test_damage_presentation() -> void:
	var bar := EnemyHealthBarScript.new()
	bar.configure(100.0, 100.0, 1.0)
	root.add_child(bar)
	await process_frame
	bar.update_health(70.0, 100.0)
	_expect(is_equal_approx(bar.get_current_ratio(), 0.7), "remaining red length follows current HP")
	_expect(
		is_equal_approx(bar.get_marker_local_x(), -bar.get_bar_width() * 0.5 + bar.get_bar_width() * 0.7),
		"marker stays on the red remaining-health edge"
	)
	_expect(bar.get_active_flash_count() == 1, "one damage settlement creates one white flash segment")
	bar.update_health(55.0, 100.0)
	_expect(bar.get_active_flash_count() == 2, "overlapping damage settlements keep independent flashes")
	bar._process(EnemyHealthBarScript.FLASH_DURATION + 0.01)
	_expect(bar.get_active_flash_count() == 0, "flash segments disappear to reveal grey lost health")
	bar.queue_free()
	await process_frame


func _test_enemy_integration() -> void:
	var definition := EnemyDefinition.new()
	definition.max_hp = 100.0
	definition.hit_particle_color = Color(0.82, 0.06, 0.11, 0.9)
	definition.hit_particle_brightness = 6.5
	definition.hit_particle_size = 0.085
	definition.hit_particle_count = 7
	var enemy := EnemyUnit.new()
	enemy.configure_unit(definition, PackedVector3Array([Vector3.ZERO]))
	root.add_child(enemy)
	await process_frame
	var bar := enemy.get_node_or_null("EnemyHealthBar3D")
	_expect(bar != null, "every EnemyUnit builds the replacement health bar")
	var has_legacy_label := false
	for child in enemy.get_children():
		if child is Label3D:
			has_legacy_label = true
	_expect(not has_legacy_label, "enemy health bar replaces the legacy numeric debug label")
	enemy.take_damage(25.0)
	_expect(
		bar != null and is_equal_approx(float(bar.call("get_current_ratio")), 0.75),
		"EnemyUnit damage signals update the remaining-health segment"
	)
	_expect(
		bar != null and int(bar.call("get_active_flash_count")) == 1,
		"EnemyUnit damage settlements trigger the white flash feedback"
	)
	var burst := _find_hit_burst()
	_expect(burst != null, "EnemyUnit damage settlements spawn a hit-particle burst")
	_expect(
		burst != null and burst.amount == definition.hit_particle_count,
		"hit-particle burst uses the configured particle count"
	)
	if burst != null:
		var quad := burst.draw_pass_1 as QuadMesh
		var material := quad.material as StandardMaterial3D if quad != null else null
		_expect(
			quad != null and is_equal_approx(quad.size.x, definition.hit_particle_size),
			"hit-particle burst uses the configured particle size"
		)
		_expect(
			material != null
			and material.albedo_color.is_equal_approx(definition.hit_particle_color)
			and is_equal_approx(
				material.emission_energy_multiplier,
				definition.hit_particle_brightness
			),
			"hit-particle burst uses the configured color and brightness"
		)
		burst.queue_free()
	await process_frame
	enemy.take_damage(enemy.current_hp)
	await process_frame
	_expect(not is_instance_valid(enemy), "lethal damage removes the defeated EnemyUnit")
	var lethal_burst := _find_hit_burst()
	_expect(
		lethal_burst != null and lethal_burst.get_parent() == root,
		"lethal-hit particles survive their defeated EnemyUnit under the world root"
	)
	if lethal_burst != null:
		lethal_burst.queue_free()
	await process_frame


func _find_hit_burst() -> GPUParticles3D:
	for child in root.get_children():
		if (
			child is GPUParticles3D
			and not child.is_queued_for_deletion()
			and child.get_script() == EnemyHitParticlesScript
		):
			return child as GPUParticles3D
	return null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
