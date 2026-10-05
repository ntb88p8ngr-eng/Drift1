extends Node
## Proximity voice chat online: the microphone is captured (AudioEffectCapture on a muted bus),
## brought down to 16 kHz mono, 8-bit μ-law (16 KB/s while talking) and sent only to the players
## whose cars are close by. Their voices come out of their cars (3D sound, fading out with distance,
## silent beyond RANGE). Push to talk (Game action "voice_talk", Caps Lock) or an open mic with a
## level gate – Optionen → Audio.

const RATE := 16000
const RANGE := 60.0            # m: further away nobody hears you (and nothing is sent)
const CHUNK := 640             # samples per packet (40 ms)
const GATE := 0.025            # open mic: level that counts as talking
const HOLD := 0.35             # s the open mic stays open after the voice drops

var world                      # world.gd
var talking := false           # sending right now (the HUD shows it)
var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _bus := -1
var _pending := PackedFloat32Array()
var _phase := 0.0              # resampling position between input samples
var _last := 0.0
var _open_hold := 0.0
var _voices := {}              # peer id -> [AudioStreamPlayer3D, playback, last heard (s)]
var _t := 0.0
var _label: Label


func _ready() -> void:
	Net.voice_received.connect(_on_voice)
	Net.peer_left.connect(_drop_peer)
	if bool(Game.settings.get("voice_chat", true)):
		_start_mic()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_label.position = Vector2(24, 40)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	layer.add_child(_label)


func _start_mic() -> void:
	_bus = AudioServer.get_bus_index("VoiceMic")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "VoiceMic")
		AudioServer.set_bus_mute(_bus, true)      # (only captured, never heard here)
		AudioServer.add_bus_effect(_bus, AudioEffectCapture.new())
	_capture = AudioServer.get_bus_effect(_bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "VoiceMic"
	add_child(_mic)
	_mic.play()


func _exit_tree() -> void:
	if _mic:
		_mic.stop()


func _process(delta: float) -> void:
	_t += delta
	if _mic == null and bool(Game.settings.get("voice_chat", true)):
		_start_mic()           # (switched on during the session)
	_capture_mic(delta)
	# voices not heard for a while: let their players go quiet (the buffer runs dry by itself)
	var names: Array = []
	for id in _voices:
		var v: Array = _voices[id]
		if _t - float(v[2]) < 0.4 and world and world.cars.has(id) and is_instance_valid(world.cars[id]):
			names.append(str(world.cars[id].player_name))
	var text := Game.t("🎤 Du sprichst") if talking else ""
	for n in names:
		text += ("\n" if text != "" else "") + "🔊 " + n
	_label.text = text


func _capture_mic(delta: float) -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buf := _capture.get_buffer(frames)
	var want := bool(Game.settings.get("voice_chat", true)) and world != null and world.local_car != null
	var mode := str(Game.settings.get("voice_mode", "ptt"))
	var gain := float(Game.settings.get("mic_gain", 1.0))
	# down to 16 kHz mono (linear interpolation between the input samples)
	var step := AudioServer.get_mix_rate() / float(RATE)
	var level := 0.0
	var out := PackedFloat32Array()
	for f in buf:
		var s: float = (f.x + f.y) * 0.5 * gain
		level = maxf(level, absf(s))
		while _phase < 1.0:
			out.append(lerpf(_last, s, _phase))
			_phase += step
		_phase -= 1.0
		_last = s
	var on := false
	if want:
		if mode == "open":
			if level > GATE:
				_open_hold = HOLD
			_open_hold -= delta
			on = _open_hold > 0.0
		else:
			on = Input.is_action_pressed("voice_talk")
	talking = on
	if not on:
		_pending.clear()
		return
	_pending.append_array(out)
	var targets := _near_peers()
	while _pending.size() >= CHUNK:
		var pkt := PackedByteArray()
		pkt.resize(CHUNK)
		for i in CHUNK:
			pkt[i] = _mulaw(_pending[i])
		_pending = _pending.slice(CHUNK)
		for id in targets:
			Net.send_voice(id, pkt)


## The players whose cars are within reach of the local car.
func _near_peers() -> Array:
	var out: Array = []
	var me = world.local_car
	for id in world.cars:
		var c = world.cars[id]
		if c == me or not is_instance_valid(c) or int(id) <= 0 or world._bot_ids.has(id):
			continue
		if (c.global_position as Vector3).distance_to(me.global_position) < RANGE + 10.0:
			out.append(int(id))
	return out


func _on_voice(peer_id: int, data: PackedByteArray) -> void:
	if world == null or not world.cars.has(peer_id) or not is_instance_valid(world.cars[peer_id]):
		return
	var car = world.cars[peer_id]
	if not _voices.has(peer_id) or not is_instance_valid(_voices[peer_id][0]):
		var p := AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.5
		p.stream = gen
		p.max_distance = RANGE
		p.unit_size = 8.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.6
		p.position = Vector3(0, 1.2, 0)
		car.add_child(p)
		p.play()
		_voices[peer_id] = [p, p.get_stream_playback(), _t]
	var v: Array = _voices[peer_id]
	var player: AudioStreamPlayer3D = v[0]
	player.volume_db = linear_to_db(maxf(float(Game.settings.get("voice_volume", 1.0)), 0.001)) + 4.0
	var pb := v[1] as AudioStreamGeneratorPlayback
	v[2] = _t
	if pb == null:
		return
	# a backlog (lag): drop it instead of talking ever later
	if pb.get_frames_available() < data.size():
		pb.clear_buffer()
	var frames := PackedVector2Array()
	frames.resize(data.size())
	for i in data.size():
		var s := _unmulaw(data[i])
		frames[i] = Vector2(s, s)
	pb.push_buffer(frames)


func _drop_peer(peer_id: int) -> void:
	if _voices.has(peer_id):
		var p = _voices[peer_id][0]
		if is_instance_valid(p):
			p.queue_free()
		_voices.erase(peer_id)


## μ-law (G.711) for one sample -1..1 -> byte, and back.
static func _mulaw(x: float) -> int:
	var s := clampf(x, -1.0, 1.0)
	var m := log(1.0 + 255.0 * absf(s)) / log(256.0)
	var q := int(round(m * 127.0))
	return (q | 128) if s < 0.0 else q


static func _unmulaw(b: int) -> float:
	var m := float(b & 127) / 127.0
	var v := (pow(256.0, m) - 1.0) / 255.0
	return -v if (b & 128) != 0 else v
