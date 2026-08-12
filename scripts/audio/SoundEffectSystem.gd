## Persistent SFX facade. It owns pooled 2D/3D players, automatically watches UI
## buttons, and translates stable gameplay signals into semantic sound cues.
class_name SoundEffectSystem
extends Node

const DEFAULT_LIBRARY: SoundEffectLibrary = preload("res://resources/audio/DefaultSoundEffects.tres")
const UI_PLAYER_COUNT: int = 4
const WORLD_PLAYER_COUNT: int = 12
const MIX_RATE: int = 44100

signal event_requested(event_id: StringName, world_position: Vector3, spatial: bool)

@export_group("Feature")
@export var feature_enabled: bool = true
@export var muted: bool = false
@export var automatic_ui_enabled: bool = true

var library: SoundEffectLibrary = DEFAULT_LIBRARY
var _fallback_streams: Dictionary = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer3D] = []
var _ui_cursor: int = 0
var _world_cursor: int = 0
var _last_played_msec: Dictionary = {}
var _random := RandomNumberGenerator.new()

var _building_manager: Node
var _combat_manager: Node
var _wave_manager: Node
var _mirror_manager: Node
var _watched_buildings: Dictionary = {}
var _watched_targets: Dictionary = {}
var _watched_enemies: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_random.randomize()
	_ensure_bus(&"SFX")
	_ensure_bus(&"UI")
	_create_player_pools()
	if automatic_ui_enabled:
		var tree := get_tree()
		if tree != null:
			if not tree.node_added.is_connected(_on_tree_node_added):
				tree.node_added.connect(_on_tree_node_added)
			register_ui_root(tree.root)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	unbind_gameplay()


func set_library(value: SoundEffectLibrary) -> void:
	library = value if value != null else DEFAULT_LIBRARY


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		stop_all()


func stop_all() -> void:
	for player in _ui_players:
		player.stop()
	for player in _world_players:
		player.stop()


func clear_rate_limits() -> void:
	_last_played_msec.clear()


func get_stream_for_event(event_id: StringName) -> AudioStream:
	if library == null or not library.supports(event_id):
		return null
	var assigned := library.get_stream(event_id)
	if assigned != null:
		return assigned
	if not _fallback_streams.has(event_id):
		_fallback_streams[event_id] = _synthesize_fallback(event_id)
	return _fallback_streams[event_id] as AudioStream


func play_ui(event_id: StringName = SoundEffectLibrary.UI_OPERATION) -> bool:
	return play_event(event_id, Vector3.ZERO, false, 0)


func play_world(event_id: StringName, world_position: Vector3, source: Object = null) -> bool:
	var source_id := source.get_instance_id() if source != null and is_instance_valid(source) else 0
	return play_event(event_id, world_position, true, source_id)


func play_event(
	event_id: StringName,
	world_position: Vector3 = Vector3.ZERO,
	spatial: bool = false,
	source_id: int = 0
) -> bool:
	if not feature_enabled or library == null or not library.supports(event_id):
		return false
	if not _passes_rate_limit(event_id, source_id):
		return false
	var stream := get_stream_for_event(event_id)
	if stream == null:
		return false
	event_requested.emit(event_id, world_position, spatial)
	if muted:
		return true
	var variation := maxf(0.0, library.get_pitch_variation(event_id))
	var pitch := 1.0 + _random.randf_range(-variation, variation)
	if spatial:
		var world_player := _take_world_player()
		world_player.global_position = world_position
		world_player.stream = stream
		world_player.volume_db = library.get_volume_db(event_id)
		world_player.pitch_scale = pitch
		world_player.play()
	else:
		var ui_player := _take_ui_player()
		ui_player.stream = stream
		ui_player.volume_db = library.get_volume_db(event_id)
		ui_player.pitch_scale = pitch
		ui_player.play()
	return true


func register_ui_root(root_node: Node) -> void:
	if root_node == null:
		return
	if root_node is BaseButton:
		_watch_button(root_node as BaseButton)
	elif root_node is Slider:
		_watch_slider(root_node as Slider)
	for child in root_node.get_children():
		register_ui_root(child)


func bind_gameplay(
	building_manager: Node,
	combat_manager: Node,
	wave_manager: Node,
	mirror_manager: Node = null
) -> void:
	unbind_gameplay()
	_building_manager = building_manager
	_combat_manager = combat_manager
	_wave_manager = wave_manager
	_mirror_manager = mirror_manager

	_connect_if(_building_manager, &"building_constructed", _on_building_constructed)
	_connect_if(_building_manager, &"building_upgraded", _on_building_upgraded)
	_connect_if(_building_manager, &"building_destroyed", _on_building_destroyed)
	_connect_if(_building_manager, &"building_runtime_rebuilt", _on_building_runtime_rebuilt)
	if _building_manager != null and _building_manager.has_method("get_buildings"):
		for building in _building_manager.call("get_buildings"):
			_watch_building(building as Node)

	_connect_if(_combat_manager, &"projectile_spawned", _on_projectile_spawned)
	_connect_if(_combat_manager, &"pulse_laser_spawned", _on_pulse_laser_spawned)
	_connect_if(_combat_manager, &"target_registered", _on_target_registered)
	if _combat_manager != null and _combat_manager.has_method("get_targets"):
		for target in _combat_manager.call("get_targets"):
			_watch_target(target as Node)

	_connect_if(_wave_manager, &"enemy_spawned", _on_enemy_spawned)
	_connect_if(_wave_manager, &"test_enemy_spawned", _on_enemy_spawned)
	_connect_if(_wave_manager, &"victory", _on_victory)
	_connect_if(_wave_manager, &"defeat", _on_defeat)
	_connect_if(_mirror_manager, &"mirror_constructed", _on_mirror_constructed)


func unbind_gameplay() -> void:
	_disconnect_if(_building_manager, &"building_constructed", _on_building_constructed)
	_disconnect_if(_building_manager, &"building_upgraded", _on_building_upgraded)
	_disconnect_if(_building_manager, &"building_destroyed", _on_building_destroyed)
	_disconnect_if(_building_manager, &"building_runtime_rebuilt", _on_building_runtime_rebuilt)
	_disconnect_if(_combat_manager, &"projectile_spawned", _on_projectile_spawned)
	_disconnect_if(_combat_manager, &"pulse_laser_spawned", _on_pulse_laser_spawned)
	_disconnect_if(_combat_manager, &"target_registered", _on_target_registered)
	_disconnect_if(_wave_manager, &"enemy_spawned", _on_enemy_spawned)
	_disconnect_if(_wave_manager, &"test_enemy_spawned", _on_enemy_spawned)
	_disconnect_if(_wave_manager, &"victory", _on_victory)
	_disconnect_if(_wave_manager, &"defeat", _on_defeat)
	_disconnect_if(_mirror_manager, &"mirror_constructed", _on_mirror_constructed)
	_disconnect_watched_nodes()
	_building_manager = null
	_combat_manager = null
	_wave_manager = null
	_mirror_manager = null


func _on_tree_node_added(node: Node) -> void:
	if node is BaseButton:
		_watch_button(node as BaseButton)
	elif node is Slider:
		_watch_slider(node as Slider)


func _watch_button(button: BaseButton) -> void:
	if button == null:
		return
	var callback := _on_ui_button_pressed.bind(button)
	if button.pressed.is_connected(callback):
		return
	button.pressed.connect(callback)


func _on_ui_button_pressed(button: BaseButton) -> void:
	if button == null or bool(button.get_meta(&"sfx_disabled", false)):
		return
	var event_id := StringName(str(button.get_meta(&"sfx_event", SoundEffectLibrary.UI_OPERATION)))
	play_ui(event_id)


func _watch_slider(slider: Slider) -> void:
	if slider == null:
		return
	var callback := _on_ui_slider_drag_ended.bind(slider)
	if slider.drag_ended.is_connected(callback):
		return
	slider.drag_ended.connect(callback)


func _on_ui_slider_drag_ended(value_changed: bool, slider: Slider) -> void:
	if not value_changed or slider == null or bool(slider.get_meta(&"sfx_disabled", false)):
		return
	play_ui()


func _on_building_constructed(building: Node) -> void:
	_watch_building(building)
	play_world(SoundEffectLibrary.CONSTRUCTION, _node_world_position(building), building)


func _on_building_upgraded(building: Node, _previous_level: int, _new_level: int) -> void:
	play_world(SoundEffectLibrary.CONSTRUCTION, _node_world_position(building), building)


func _on_building_destroyed(building: Node, _attacker: Node) -> void:
	play_world(SoundEffectLibrary.DEATH, _node_world_position(building), building)


func _on_building_runtime_rebuilt(_previous: Node, current: Node) -> void:
	_watch_building(current)


func _on_mirror_constructed(mirror: Node) -> void:
	play_world(SoundEffectLibrary.CONSTRUCTION, _node_world_position(mirror), mirror)


func _watch_building(building: Node) -> void:
	if building == null or not is_instance_valid(building):
		return
	var instance_id := building.get_instance_id()
	if _watched_buildings.has(instance_id):
		return
	_watched_buildings[instance_id] = weakref(building)
	_connect_if(building, &"attack_performed", _on_building_attack_performed)


func _on_building_attack_performed(
	building: Node,
	target: Node,
	_damage: float,
	continuous: bool
) -> void:
	if continuous:
		play_world(SoundEffectLibrary.ATTACK, _node_world_position(building), building)
		play_world(SoundEffectLibrary.HIT, _node_world_position(target), null)


func _on_projectile_spawned(projectile: Node) -> void:
	var source: Node = null
	if projectile != null and projectile.has_method("get_source_building"):
		source = projectile.call("get_source_building") as Node
	play_world(
		SoundEffectLibrary.ATTACK,
		_node_world_position(source if source != null else projectile),
		source if source != null else projectile
	)


func _on_pulse_laser_spawned(beam: Node) -> void:
	_on_projectile_spawned(beam)


func _on_target_registered(target: Node) -> void:
	_watch_target(target)


func _watch_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var instance_id := target.get_instance_id()
	if _watched_targets.has(instance_id):
		return
	_watched_targets[instance_id] = weakref(target)
	_connect_if(target, &"health_changed", _on_target_health_changed)
	_connect_if(target, &"died", _on_target_died)


func _on_target_health_changed(target: Node, current_hp: float, maximum_hp: float) -> void:
	if current_hp < maximum_hp:
		play_world(SoundEffectLibrary.HIT, _node_world_position(target), null)


func _on_target_died(target: Node, _reward_amount: float) -> void:
	play_world(SoundEffectLibrary.DEATH, _node_world_position(target), target)


func _on_enemy_spawned(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var instance_id := enemy.get_instance_id()
	if _watched_enemies.has(instance_id):
		return
	_watched_enemies[instance_id] = weakref(enemy)
	_connect_if(enemy, &"attack_performed", _on_enemy_attack_performed)
	_connect_if(enemy, &"projectile_spawned", _on_enemy_projectile_spawned)


func _on_enemy_attack_performed(
	enemy: Node,
	target: Node,
	_applied_damage: float,
	ranged: bool
) -> void:
	if not ranged:
		play_world(SoundEffectLibrary.ATTACK, _node_world_position(enemy), enemy)
	play_world(SoundEffectLibrary.HIT, _node_world_position(target), null)


func _on_enemy_projectile_spawned(enemy: Node, _projectile: Node) -> void:
	play_world(SoundEffectLibrary.ATTACK, _node_world_position(enemy), enemy)


func _on_victory() -> void:
	play_ui(SoundEffectLibrary.VICTORY)


func _on_defeat() -> void:
	play_ui(SoundEffectLibrary.DEFEAT)


func _connect_if(emitter: Variant, signal_name: StringName, callback: Callable) -> void:
	if (
		emitter != null
		and is_instance_valid(emitter)
		and emitter.has_signal(signal_name)
		and not emitter.is_connected(signal_name, callback)
	):
		emitter.connect(signal_name, callback)


func _disconnect_if(emitter: Variant, signal_name: StringName, callback: Callable) -> void:
	if (
		emitter != null
		and is_instance_valid(emitter)
		and emitter.has_signal(signal_name)
		and emitter.is_connected(signal_name, callback)
	):
		emitter.disconnect(signal_name, callback)


func _disconnect_watched_nodes() -> void:
	for reference in _watched_buildings.values():
		var building := (reference as WeakRef).get_ref() as Node
		_disconnect_if(building, &"attack_performed", _on_building_attack_performed)
	for reference in _watched_targets.values():
		var target := (reference as WeakRef).get_ref() as Node
		_disconnect_if(target, &"health_changed", _on_target_health_changed)
		_disconnect_if(target, &"died", _on_target_died)
	for reference in _watched_enemies.values():
		var enemy := (reference as WeakRef).get_ref() as Node
		_disconnect_if(enemy, &"attack_performed", _on_enemy_attack_performed)
		_disconnect_if(enemy, &"projectile_spawned", _on_enemy_projectile_spawned)
	_watched_buildings.clear()
	_watched_targets.clear()
	_watched_enemies.clear()


func _node_world_position(node: Node) -> Vector3:
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	if node.has_method("get_target_position"):
		var target_position: Variant = node.call("get_target_position")
		if target_position is Vector3:
			return target_position
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


func _passes_rate_limit(event_id: StringName, source_id: int) -> bool:
	var interval := _minimum_interval_msec(event_id)
	if interval <= 0:
		return true
	var resolved_source := source_id if event_id in [SoundEffectLibrary.ATTACK, SoundEffectLibrary.CONSTRUCTION] else 0
	var key := "%s:%d" % [event_id, resolved_source]
	var now := Time.get_ticks_msec()
	var previous := int(_last_played_msec.get(key, -interval - 1))
	if now - previous < interval:
		return false
	_last_played_msec[key] = now
	return true


func _minimum_interval_msec(event_id: StringName) -> int:
	match event_id:
		SoundEffectLibrary.UI_OPERATION:
			return 25
		SoundEffectLibrary.CONSTRUCTION:
			return 80
		SoundEffectLibrary.ATTACK:
			return 70
		SoundEffectLibrary.HIT:
			return 45
		SoundEffectLibrary.DEATH:
			return 70
		SoundEffectLibrary.VICTORY, SoundEffectLibrary.DEFEAT:
			return 1000
		_:
			return 0


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _create_player_pools() -> void:
	for index in range(UI_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "UiPlayer%02d" % (index + 1)
		player.bus = &"UI"
		add_child(player)
		_ui_players.append(player)
	for index in range(WORLD_PLAYER_COUNT):
		var player := AudioStreamPlayer3D.new()
		player.name = "WorldPlayer%02d" % (index + 1)
		player.bus = &"SFX"
		player.unit_size = 5.0
		player.max_distance = 48.0
		player.panning_strength = 1.2
		add_child(player)
		_world_players.append(player)


func _take_ui_player() -> AudioStreamPlayer:
	for player in _ui_players:
		if not player.playing:
			return player
	var player := _ui_players[_ui_cursor % _ui_players.size()]
	_ui_cursor += 1
	return player


func _take_world_player() -> AudioStreamPlayer3D:
	for player in _world_players:
		if not player.playing:
			return player
	var player := _world_players[_world_cursor % _world_players.size()]
	_world_cursor += 1
	return player


func _synthesize_fallback(event_id: StringName) -> AudioStreamWAV:
	var duration := _fallback_duration(event_id)
	var frame_count := maxi(1, roundi(duration * MIX_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 2)
	for frame in range(frame_count):
		var time := float(frame) / float(MIX_RATE)
		var sample := _fallback_sample(event_id, time, duration, frame)
		pcm.encode_s16(frame * 2, roundi(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	return stream


func _fallback_duration(event_id: StringName) -> float:
	match event_id:
		SoundEffectLibrary.UI_OPERATION:
			return 0.075
		SoundEffectLibrary.CONSTRUCTION:
			return 0.42
		SoundEffectLibrary.ATTACK:
			return 0.13
		SoundEffectLibrary.HIT:
			return 0.11
		SoundEffectLibrary.DEATH:
			return 0.46
		SoundEffectLibrary.VICTORY:
			return 0.88
		SoundEffectLibrary.DEFEAT:
			return 0.92
		_:
			return 0.1


func _fallback_sample(event_id: StringName, time: float, duration: float, frame: int) -> float:
	var progress := clampf(time / maxf(duration, 0.0001), 0.0, 1.0)
	var fade := pow(1.0 - progress, 1.7)
	match event_id:
		SoundEffectLibrary.UI_OPERATION:
			var frequency := 760.0 if time < 0.032 else 1080.0
			return sin(TAU * frequency * time) * fade * 0.32
		SoundEffectLibrary.CONSTRUCTION:
			var impact := sin(TAU * 92.0 * time) * exp(-time * 11.0) * 0.55
			var sparkle := sin(TAU * (330.0 + 520.0 * progress) * time) * fade * 0.22
			var noise := _deterministic_noise(frame) * exp(-time * 24.0) * 0.2
			return impact + sparkle + noise
		SoundEffectLibrary.ATTACK:
			var frequency := lerpf(1180.0, 420.0, progress)
			return (sin(TAU * frequency * time) * 0.46 + _deterministic_noise(frame) * 0.08) * fade
		SoundEffectLibrary.HIT:
			var thump := sin(TAU * 138.0 * time) * 0.42
			return (thump + _deterministic_noise(frame) * 0.38) * pow(1.0 - progress, 2.8)
		SoundEffectLibrary.DEATH:
			var frequency := lerpf(310.0, 72.0, progress)
			return (sin(TAU * frequency * time) * 0.42 + _deterministic_noise(frame) * 0.14) * fade
		SoundEffectLibrary.VICTORY:
			return _sequence_sample(time, duration, [523.25, 659.25, 783.99, 1046.50, 1318.51], 0.16, 0.38)
		SoundEffectLibrary.DEFEAT:
			return _sequence_sample(time, duration, [392.0, 349.23, 293.66, 196.0], 0.21, 0.42)
		_:
			return 0.0


func _sequence_sample(
	time: float,
	duration: float,
	frequencies: Array,
	note_duration: float,
	amplitude: float
) -> float:
	var note_index := mini(int(time / note_duration), frequencies.size() - 1)
	var local_time := time - float(note_index) * note_duration
	var note_fade := pow(1.0 - clampf(local_time / note_duration, 0.0, 1.0), 0.65)
	var ending_fade := clampf((duration - time) / 0.12, 0.0, 1.0)
	var frequency := float(frequencies[note_index])
	return (
		sin(TAU * frequency * local_time)
		+ sin(TAU * frequency * 2.0 * local_time) * 0.22
	) * amplitude * note_fade * ending_fade


func _deterministic_noise(index: int) -> float:
	var value := (index * 1103515245 + 12345) & 0x7fffffff
	return float(value % 65536) / 32767.5 - 1.0
