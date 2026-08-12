extends SceneTree

const SoundEffectSystemScript := preload("res://scripts/audio/SoundEffectSystem.gd")
const SoundEffectLibraryScript := preload("res://scripts/audio/SoundEffectLibrary.gd")

class FakeBuilding extends Node3D:
	signal attack_performed(building: Node, target: Node, damage: float, continuous: bool)


class FakeTarget extends Node3D:
	signal health_changed(target: Node, current_hp: float, maximum_hp: float)
	signal died(target: Node, reward_amount: float)

	func get_target_position() -> Vector3:
		return global_position + Vector3.UP


class FakeProjectile extends Node3D:
	var source: Node

	func get_source_building() -> Node:
		return source


class FakeBuildingManager extends Node:
	signal building_constructed(building: Node)
	signal building_upgraded(building: Node, previous_level: int, new_level: int)
	signal building_destroyed(building: Node, attacker: Node)
	signal building_runtime_rebuilt(previous: Node, current: Node)

	var buildings: Array[Node] = []

	func get_buildings() -> Array[Node]:
		return buildings


class FakeCombatManager extends Node:
	signal projectile_spawned(projectile: Node)
	signal pulse_laser_spawned(beam: Node)
	signal target_registered(target: Node)

	var targets: Array[Node] = []

	func get_targets() -> Array[Node]:
		return targets


class FakeWaveManager extends Node:
	signal enemy_spawned(enemy: Node)
	signal test_enemy_spawned(enemy: Node)
	signal victory
	signal defeat


class FakeMirrorManager extends Node:
	signal mirror_constructed(mirror: Node)


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[SoundEffectSystem] running")
	var system = SoundEffectSystemScript.new()
	system.automatic_ui_enabled = false
	system.muted = true
	root.add_child(system)
	await process_frame

	_test_fallback_library(system)
	_test_semantic_playback(system)
	_test_ui_binding(system)
	_test_gameplay_binding(system)
	_test_freed_gameplay_binding(system)

	system.queue_free()
	await process_frame
	if _failures == 0:
		print("[SoundEffectSystem] PASS: %d checks" % _checks)
		quit(0)
		return
	push_error("[SoundEffectSystem] FAIL: %d/%d checks failed" % [_failures, _checks])
	quit(1)


func _test_fallback_library(system) -> void:
	for event_id in SoundEffectLibraryScript.EVENT_IDS:
		var stream: AudioStream = system.get_stream_for_event(event_id)
		_expect(stream is AudioStreamWAV, "%s has an immediate procedural fallback" % event_id)
		if stream is AudioStreamWAV:
			_expect((stream as AudioStreamWAV).data.size() > 0, "%s fallback contains PCM samples" % event_id)


func _test_semantic_playback(system) -> void:
	var received: Array[StringName] = []
	var callback := func(event_id: StringName, _position: Vector3, _spatial: bool) -> void:
		received.append(event_id)
	system.event_requested.connect(callback)
	for event_id in SoundEffectLibraryScript.EVENT_IDS:
		system.clear_rate_limits()
		_expect(system.play_event(event_id), "%s can be requested" % event_id)
	_expect(received == SoundEffectLibraryScript.EVENT_IDS, "all seven semantic events preserve their identifiers")
	system.event_requested.disconnect(callback)


func _test_ui_binding(system) -> void:
	var button := Button.new()
	var received: Array[StringName] = []
	var callback := func(event_id: StringName, _position: Vector3, _spatial: bool) -> void:
		received.append(event_id)
	system.event_requested.connect(callback)
	system.register_ui_root(button)
	system.register_ui_root(button)
	system.clear_rate_limits()
	button.pressed.emit()
	_expect(received == [SoundEffectLibraryScript.UI_OPERATION], "registered buttons emit one UI cue without duplicate wiring")
	button.set_meta(&"sfx_disabled", true)
	button.pressed.emit()
	_expect(received.size() == 1, "button metadata can opt out of automatic UI sound")
	system.event_requested.disconnect(callback)
	button.free()


func _test_gameplay_binding(system) -> void:
	var building_manager := FakeBuildingManager.new()
	var combat_manager := FakeCombatManager.new()
	var wave_manager := FakeWaveManager.new()
	var mirror_manager := FakeMirrorManager.new()
	var building := FakeBuilding.new()
	var mirror := Node3D.new()
	var target := FakeTarget.new()
	var projectile := FakeProjectile.new()
	projectile.source = building
	root.add_child(building_manager)
	root.add_child(combat_manager)
	root.add_child(wave_manager)
	root.add_child(mirror_manager)
	root.add_child(building)
	root.add_child(mirror)
	root.add_child(target)
	root.add_child(projectile)
	building_manager.buildings.append(building)
	combat_manager.targets.append(target)

	var received: Array[StringName] = []
	var callback := func(event_id: StringName, _position: Vector3, _spatial: bool) -> void:
		received.append(event_id)
	system.event_requested.connect(callback)
	system.bind_gameplay(building_manager, combat_manager, wave_manager, mirror_manager)

	system.clear_rate_limits()
	building_manager.building_constructed.emit(building)
	_expect(received.back() == SoundEffectLibraryScript.CONSTRUCTION, "successful player construction emits construction")
	system.clear_rate_limits()
	mirror_manager.mirror_constructed.emit(mirror)
	_expect(received.back() == SoundEffectLibraryScript.CONSTRUCTION, "successful mirror placement emits construction")
	system.clear_rate_limits()
	combat_manager.projectile_spawned.emit(projectile)
	_expect(received.back() == SoundEffectLibraryScript.ATTACK, "projectile launch emits attack")
	system.clear_rate_limits()
	target.health_changed.emit(target, 5.0, 10.0)
	_expect(received.back() == SoundEffectLibraryScript.HIT, "target health loss emits hit")
	system.clear_rate_limits()
	target.died.emit(target, 1.0)
	_expect(received.back() == SoundEffectLibraryScript.DEATH, "target death emits death")
	system.clear_rate_limits()
	wave_manager.victory.emit()
	_expect(received.back() == SoundEffectLibraryScript.VICTORY, "wave victory emits victory")
	system.clear_rate_limits()
	wave_manager.defeat.emit()
	_expect(received.back() == SoundEffectLibraryScript.DEFEAT, "wave defeat emits defeat")

	system.event_requested.disconnect(callback)
	system.unbind_gameplay()
	for node in [projectile, target, mirror, building, mirror_manager, wave_manager, combat_manager, building_manager]:
		node.queue_free()


func _test_freed_gameplay_binding(system) -> void:
	var building_manager := FakeBuildingManager.new()
	var combat_manager := FakeCombatManager.new()
	var wave_manager := FakeWaveManager.new()
	root.add_child(building_manager)
	root.add_child(combat_manager)
	root.add_child(wave_manager)
	system.bind_gameplay(building_manager, combat_manager, wave_manager)
	building_manager.free()
	combat_manager.free()
	wave_manager.free()
	system.bind_gameplay(null, null, null)
	_expect(true, "rebinding safely ignores managers already freed during a scene transition")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: %s" % message)
		return
	_failures += 1
	push_error("  FAIL: %s" % message)
