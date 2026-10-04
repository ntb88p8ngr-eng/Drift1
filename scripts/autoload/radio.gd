extends Node
## The car radio's engine (autoload "Radio"): internet radio stations (MP3 Icecast streams, rock presets
## on FM1 and more on FM2), cassettes, volume and power. The radio's face (radio_widget.gd) and its display
## (radio_display.gd) only read this state and call the functions below – it plays on across the menu and
## the races.
##
## Streams: HTTPClient reads the MP3 bytes (and the ICY song titles in between), they are cut at frame
## boundaries into chunks of a few seconds, each chunk becomes an AudioStreamMP3. Two players take turns;
## every chunk starts with the last frames of the one before, the next player starts on those and the two
## crossfade there, so the cuts are not heard (the first frames of a cut decode badly – they stay muted).
##
## The presets (FM1 / FM2, 6 each) can be set in Optionen → Audio from all stations there are (catalog()),
## own stations added there by their stream address (MP3) – Game.settings "radio_slots" / "radio_custom".
## Tapes: TAPES (found in the game, kept in the garage's cabinet) and every folder user://cassettes/<name>/
## with .mp3 / .ogg files in it (an own tape, always there). A tape with files plays those, one after another.

signal changed            # power, band, station, mode, tape, status
signal title_changed      # the song now playing (ICY StreamTitle / the tape's file)
signal flashed            # a short message for the display (flash_text)

const STATIONS := [
	[   # FM1: rock
		{"ps": "RP ROCK", "name": "Radio Paradise – Rock Mix", "freq": "98.5", "url": "https://stream.radioparadise.com/rock-128"},
		{"ps": "METAL", "name": "SomaFM – Metal Detector", "freq": "101.3", "url": "https://ice2.somafm.com/metal-128-mp3"},
		{"ps": "80S ROCK", "name": "SomaFM – Underground 80s", "freq": "89.7", "url": "https://ice2.somafm.com/u80s-128-mp3"},
		{"ps": "70S ROCK", "name": "SomaFM – Left Coast 70s", "freq": "94.1", "url": "https://ice2.somafm.com/seventies-128-mp3"},
		{"ps": "INDIE", "name": "SomaFM – BAGeL Radio", "freq": "104.6", "url": "https://ice2.somafm.com/bagel-128-mp3"},
		{"ps": "ALT ROCK", "name": "SomaFM – Digitalis", "freq": "106.2", "url": "https://ice2.somafm.com/digitalis-128-mp3"},
	],
	[   # FM2: the rest
		{"ps": "RP MAIN", "name": "Radio Paradise – Main Mix", "freq": "93.3", "url": "https://stream.radioparadise.com/mp3-128"},
		{"ps": "RP MELLO", "name": "Radio Paradise – Mellow Mix", "freq": "95.8", "url": "https://stream.radioparadise.com/mellow-128"},
		{"ps": "COUNTRY", "name": "SomaFM – Boot Liquor", "freq": "88.4", "url": "https://ice2.somafm.com/bootliquor-128-mp3"},
		{"ps": "COVERS", "name": "SomaFM – Covers", "freq": "91.6", "url": "https://ice2.somafm.com/covers-128-mp3"},
		{"ps": "FOLK", "name": "SomaFM – Folk Forward", "freq": "100.1", "url": "https://ice2.somafm.com/folkfwd-128-mp3"},
		{"ps": "AGENT", "name": "SomaFM – Secret Agent", "freq": "107.4", "url": "https://ice2.somafm.com/secretagent-128-mp3"},
	],
]

## More stations to pick for the presets (Optionen → Audio), besides the ones above and the own ones.
const MORE := [
	{"ps": "INDIE POP", "name": "SomaFM – Indie Pop Rocks!", "freq": "92.4", "url": "https://ice2.somafm.com/indiepop-128-mp3"},
	{"ps": "POPTRON", "name": "SomaFM – PopTron", "freq": "97.1", "url": "https://ice2.somafm.com/poptron-128-mp3"},
	{"ps": "GROOVE", "name": "SomaFM – Groove Salad", "freq": "99.6", "url": "https://ice2.somafm.com/groovesalad-128-mp3"},
	{"ps": "7 SOUL", "name": "SomaFM – Seven Inch Soul", "freq": "102.7", "url": "https://ice2.somafm.com/7soul-128-mp3"},
	{"ps": "JAZZ", "name": "SomaFM – Sonic Universe", "freq": "103.9", "url": "https://ice2.somafm.com/sonicuniverse-128-mp3"},
	{"ps": "THE TRIP", "name": "SomaFM – The Trip", "freq": "105.5", "url": "https://ice2.somafm.com/thetrip-128-mp3"},
	{"ps": "LUSH", "name": "SomaFM – Lush", "freq": "90.2", "url": "https://ice2.somafm.com/lush-128-mp3"},
	{"ps": "DRONE", "name": "SomaFM – Drone Zone", "freq": "87.9", "url": "https://ice2.somafm.com/dronezone-128-mp3"},
]

## Cassettes that can be found. `stream` = what the tape plays when user://cassettes/<id>/ holds no files.
const TAPES := {
	"garage_mix": {"title": "Garage Mix", "color": Color(0.85, 0.12, 0.1), "stream": "https://ice2.somafm.com/u80s-128-mp3"},
	"night_run": {"title": "Night Run", "color": Color(0.12, 0.3, 0.85), "stream": "https://ice2.somafm.com/metal-128-mp3"},
	"desert_tape": {"title": "Desert Tape", "color": Color(0.9, 0.6, 0.15), "stream": "https://ice2.somafm.com/bootliquor-128-mp3"},
	"hell_mix": {"title": "Green Hell", "color": Color(0.15, 0.7, 0.3), "stream": "https://stream.radioparadise.com/rock-128"},
	"harbor_tape": {"title": "Harbor Lights", "color": Color(0.1, 0.7, 0.75), "stream": "https://ice2.somafm.com/covers-128-mp3"},
	"tokyo_tape": {"title": "Tokyo Tape", "color": Color(0.95, 0.3, 0.7), "stream": "https://ice2.somafm.com/seventies-128-mp3"},
}
const TAPE_DIR := "user://cassettes/"

const OVERLAP_FRAMES := 10      # each chunk starts with this many frames of the chunk before (~0.26 s)
const FADE_FROM := 0.08         # the crossfade in the overlap: muted for the badly decoded first frames ...
const FADE_LEN := 0.12          # ... then over this long
const FIRST_CHUNK := 2.0        # s: the first chunk is short (sound quickly) ...
const CHUNK := 6.0              # ... the rest longer
const START_BUFFER := 2.0       # s buffered before the first chunk plays

var on := false
var volume := 0.5
var band := 0
var preset := [0, 0]
var mode := "radio"             # "radio" / "tape"
var tape := ""                  # the tape in the slot ("" = none)
var api := true                 # A.P.I.: song titles scroll by on their own
var tape_paused := false
var show_freq := false          # TUNE: the display shows the frequency instead of the station name
var status := ""                # "" / "TUNING" / "NO SIGNAL" / "PLAY"
var title := ""
var flash_text := ""
var flash_until := 0.0

var _stations: Array = STATIONS
var _players: Array[AudioStreamPlayer] = []
var _sfx: AudioStreamPlayer
var _cur := -1                  # index of the player playing now
var _cur_len := 0.0
var _next_started := false
var _xf := -1.0                 # time since the next player started (crossfade), < 0 = none
var _queue: Array = []          # [{stream, len, overlap}]
var _save_at := -1.0

# the HTTP stream
var _http: HTTPClient
var _url := ""
var _phase := 0                 # 0 off, 1 connecting, 2 waiting for the answer, 3 reading
var _redirects := 0
var _retry_at := -1.0
var _last_data := 0.0
var _metaint := 0
var _until_meta := 0
var _meta_left := -1
var _meta := PackedByteArray()
var _audio := PackedByteArray() # not yet split into frames
var _frames: Array[PackedByteArray] = []   # complete frames of the chunk being gathered
var _frames_dur := 0.0
var _tail: Array[PackedByteArray] = []     # the last frames of the chunk before
var _frame_dur := 0.026
var _chunks_made := 0

# tape files
var _tape_files: PackedStringArray = []
var _tape_track := 0

var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_players[0].finished.connect(_on_player_finished.bind(0))
	_players[1].finished.connect(_on_player_finished.bind(1))
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_load_stations()
	var st: Dictionary = Game.settings.get("radio", {}) if Game.settings.get("radio") is Dictionary else {}
	on = bool(st.get("on", false))
	volume = clampf(float(st.get("volume", 0.5)), 0.0, 1.0)
	band = clampi(int(st.get("band", 0)), 0, _stations.size() - 1)
	var pr = st.get("preset", [0, 0])
	if pr is Array and pr.size() >= 2:
		preset = [clampi(int(pr[0]), 0, 5), clampi(int(pr[1]), 0, 5)]
	mode = "tape" if str(st.get("mode", "radio")) == "tape" else "radio"
	tape = str(st.get("tape", ""))
	if tape != "" and not tapes().has(tape):
		tape = ""
	if tape == "":
		mode = "radio"
	api = bool(st.get("api", true))
	# no sound and no network for the dedicated server / headless tests
	if DisplayServer.get_name() == "headless":
		on = false
	if on:
		_start_source.call_deferred()


# ---------------------------------------------------------------------------
# What the radio's buttons do
# ---------------------------------------------------------------------------
func power(state: bool) -> void:
	if state == on:
		return
	on = state
	if on:
		_start_source()
	else:
		_stop_all()
		status = ""
		title = ""
	_store()


func toggle_power() -> void:
	power(not on)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	flash("VOL %2d" % roundi(volume * 30.0), 1.4)
	_store()


func pick_preset(i: int) -> void:
	if not on:
		power(true)
	i = clampi(i, 0, stations().size() - 1)
	if mode == "radio" and preset[band] == i and status != "NO SIGNAL":
		flash(station().get("name", ""), 2.5)
		return
	preset[band] = i
	mode = "radio"
	_start_source()
	_store()


func next_band() -> void:
	if not on:
		power(true)
		return
	if mode == "tape":
		mode = "radio"
	else:
		band = (band + 1) % _stations.size()
	flash("FM%d" % (band + 1), 1.0)
	_start_source()
	_store()


## UP / DN: the next / previous station (tape: the next / previous track).
func seek(dir: int) -> void:
	if not on:
		return
	if mode == "tape":
		if _tape_files.size() > 0:
			_tape_track = posmod(_tape_track + dir, _tape_files.size())
			_play_tape_file()
			flash("TRK %02d" % (_tape_track + 1), 1.2)
		else:
			flash("FF" if dir > 0 else "REW", 0.8)
		return
	preset[band] = posmod(int(preset[band]) + dir, stations().size())
	status = "TUNING"
	_start_source()
	_store()


func tape_button() -> void:
	if not on:
		power(true)
	if tape == "":
		flash("NO TAPE", 1.5)
		return
	if mode != "tape":
		mode = "tape"
		tape_paused = false
		_start_source()
	else:
		tape_paused = not tape_paused
		if _tape_files.size() > 0:
			for p in _players:
				p.stream_paused = tape_paused
		elif tape_paused:
			_stop_stream()
		else:
			_start_source()
		status = "PAUSE" if tape_paused else "PLAY"
		changed.emit()
	_store()


func insert_tape(id: String) -> void:
	if not tapes().has(id):
		return
	tape = id
	mode = "tape"
	tape_paused = false
	if not on:
		on = true
	_start_source()
	_store()


func eject() -> void:
	if tape == "":
		flash("NO TAPE", 1.2)
		return
	tape = ""
	if mode == "tape":
		mode = "radio"
		if on:
			_start_source()
	_store()
	changed.emit()


func toggle_api() -> void:
	api = not api
	flash("API ON" if api else "API OFF", 1.2)
	_store()


func toggle_freq() -> void:
	show_freq = not show_freq
	changed.emit()


func flash(text: String, secs := 1.5) -> void:
	flash_text = text
	flash_until = _clock + secs
	flashed.emit()


func flash_left() -> float:
	return flash_until - _clock


func click_sound(heavy := false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_sfx.stream = _clunk if heavy else _click
	_sfx.volume_db = -10.0 if heavy else -16.0
	_sfx.play()


# ---------------------------------------------------------------------------
# Lists
# ---------------------------------------------------------------------------
func stations() -> Array:
	return _stations[band]


func station() -> Dictionary:
	var l := stations()
	return l[clampi(int(preset[band]), 0, l.size() - 1)] if l.size() > 0 else {}


## All tapes there are: id -> {title, color, stream, files}. The found ones are Game.settings["cassettes"].
func tapes() -> Dictionary:
	var out := {}
	for id in TAPES:
		var d: Dictionary = TAPES[id].duplicate()
		d["files"] = _files_in(TAPE_DIR + id)
		out[id] = d
	var dir := DirAccess.open(TAPE_DIR)
	if dir:
		for sub in dir.get_directories():
			if out.has(sub):
				continue
			var files := _files_in(TAPE_DIR + sub)
			if files.size() > 0:
				out[sub] = {"title": sub.capitalize(), "color": Color(0.92, 0.92, 0.88), "stream": "", "files": files, "own": true}
	return out


## The tapes in the cabinet: the found ones and the own ones.
func owned_tapes() -> Array:
	var all := tapes()
	var out: Array = []
	for id in all:
		if bool(all[id].get("own", false)) or (Game.settings.get("cassettes", []) as Array).has(id):
			out.append(id)
	return out


## A tape was found (for later: pick-ups on the maps).
func find_tape(id: String) -> bool:
	var have: Array = Game.settings.get("cassettes", [])
	if have.has(id) or not TAPES.has(id):
		return false
	have.append(id)
	Game.settings["cassettes"] = have
	Game.save_settings()
	return true


func tape_title(id := "") -> String:
	if id == "":
		id = tape
	var t: Dictionary = tapes().get(id, {})
	return str(t.get("title", id))


func _files_in(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(path)
	if d == null:
		return out
	for f in d.get_files():
		var e := f.get_extension().to_lower()
		if e == "mp3" or e == "ogg":
			out.append(path.path_join(f))
	out.sort()
	return out


func _load_stations() -> void:
	var slots = Game.settings.get("radio_slots", [])
	var bands: Array = []
	for b in STATIONS.size():
		var l: Array = []
		for i in 6:
			var st: Dictionary = STATIONS[b][i]
			if slots is Array and b < slots.size() and slots[b] is Array and i < (slots[b] as Array).size():
				var found := station_by_url(str(slots[b][i]))
				if not found.is_empty():
					st = found
			l.append(st)
		bands.append(l)
	_stations = bands


## Every station: the built-in ones and the own ones.
func catalog() -> Array:
	var out: Array = []
	for b in STATIONS:
		out.append_array(b)
	out.append_array(MORE)
	for c in Game.settings.get("radio_custom", []):
		if c is Dictionary and str(c.get("url", "")) != "":
			out.append(c)
	return out


func station_by_url(url: String) -> Dictionary:
	for c in catalog():
		if str(c.get("url", "")) == url:
			return c
	return {}


## Preset `i` (0..5) of `b` (0 = FM1, 1 = FM2) set to the station with that address.
func set_slot(b: int, i: int, url: String) -> void:
	var slots: Array = []
	for bb in STATIONS.size():
		var l: Array = []
		for ii in 6:
			l.append(str(_stations[bb][ii].get("url", "")))
		slots.append(l)
	slots[b][i] = url
	Game.settings["radio_slots"] = slots
	Game.save_settings()
	var playing := on and mode == "radio" and band == b and int(preset[b]) == i
	_load_stations()
	if playing:
		_start_source()
	changed.emit()


func reset_slots() -> void:
	Game.settings["radio_slots"] = []
	Game.save_settings()
	_load_stations()
	if on and mode == "radio":
		_start_source()
	changed.emit()


## An own station by its stream address (MP3, http / https). Returns an error text, "" when added.
func add_custom(name: String, url: String) -> String:
	url = url.strip_edges()
	name = name.strip_edges()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return "Die Adresse muss mit http:// oder https:// beginnen."
	if not station_by_url(url).is_empty():
		return "Diesen Sender gibt es schon."
	if name == "":
		name = url.get_slice("/", 2)
	var list: Array = Game.settings.get("radio_custom", [])
	list.append({"ps": name.to_upper().left(8), "name": name, "url": url,
		"freq": "%.1f" % (87.6 + float(absi(hash(url)) % 200) * 0.1), "own": true})
	Game.settings["radio_custom"] = list
	Game.save_settings()
	return ""


func remove_custom(url: String) -> void:
	var list: Array = Game.settings.get("radio_custom", [])
	Game.settings["radio_custom"] = list.filter(func(c): return str(c.get("url", "")) != url)
	# presets that played it fall back to the built-in station
	var slots = Game.settings.get("radio_slots", [])
	if slots is Array:
		for b in slots.size():
			if slots[b] is Array:
				for i in (slots[b] as Array).size():
					if str(slots[b][i]) == url:
						slots[b][i] = str(STATIONS[b][i]["url"]) if b < STATIONS.size() else ""
		Game.settings["radio_slots"] = slots
	Game.save_settings()
	_load_stations()
	changed.emit()


func _store() -> void:
	Game.settings["radio"] = {"on": on, "volume": volume, "band": band, "preset": preset.duplicate(), "mode": mode,
		"tape": tape, "api": api}
	_save_at = _clock + 0.8
	changed.emit()


# ---------------------------------------------------------------------------
# Playing
# ---------------------------------------------------------------------------
func _start_source() -> void:
	_stop_all()
	title = ""
	if not on or DisplayServer.get_name() == "headless":
		changed.emit()
		return
	if mode == "tape" and tape != "":
		var t: Dictionary = tapes().get(tape, {})
		_tape_files = t.get("files", PackedStringArray())
		if _tape_files.size() > 0:
			_tape_track = clampi(_tape_track, 0, _tape_files.size() - 1)
			if not tape_paused:
				# the tape's mechanism first
				get_tree().create_timer(0.9).timeout.connect(func():
					if on and mode == "tape" and _tape_files.size() > 0 and not _players[0].playing:
						_play_tape_file())
			status = "PAUSE" if tape_paused else "PLAY"
		elif str(t.get("stream", "")) != "" and not tape_paused:
			_open(str(t["stream"]))
	else:
		mode = "radio"
		var s := station()
		if s.has("url"):
			_open(str(s["url"]))
	changed.emit()


func _play_tape_file() -> void:
	_stop_players()
	var path := _tape_files[_tape_track]
	var st: AudioStream = null
	if path.get_extension().to_lower() == "ogg":
		st = AudioStreamOggVorbis.load_from_file(path)
	else:
		var mp := AudioStreamMP3.new()
		mp.data = FileAccess.get_file_as_bytes(path)
		st = mp
	if st == null:
		flash("TAPE ERR", 1.5)
		return
	_players[0].stream = st
	_players[0].volume_db = _db(volume)
	_players[0].play()
	_cur = 0
	_cur_len = 0.0
	title = path.get_file().get_basename().replace("_", " ")
	status = "PLAY"
	title_changed.emit()
	changed.emit()


func _on_player_finished(i: int) -> void:
	if mode == "tape" and _tape_files.size() > 0 and i == 0 and on and not tape_paused:
		_tape_track = (_tape_track + 1) % _tape_files.size()
		_play_tape_file()


func _stop_all() -> void:
	_stop_stream()
	_stop_players()
	_tape_files = PackedStringArray()


func _stop_players() -> void:
	for p in _players:
		p.stop()
		p.stream = null
		p.stream_paused = false
	_cur = -1
	_xf = -1.0
	_next_started = false
	_queue.clear()


func _stop_stream() -> void:
	if _http:
		_http.close()
	_http = null
	_phase = 0
	_retry_at = -1.0
	_stop_players()
	_audio.clear()
	_frames.clear()
	_tail.clear()
	_frames_dur = 0.0
	_chunks_made = 0


func _open(url: String) -> void:
	_stop_stream()
	_url = url
	_redirects = 0
	status = "TUNING"
	_connect()


func _connect() -> void:
	var u := _parse_url(_url)
	if u.is_empty():
		status = "NO SIGNAL"
		changed.emit()
		return
	_http = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if u["tls"] else null
	if _http.connect_to_host(u["host"], u["port"], tls) != OK:
		_fail()
		return
	_phase = 1
	_last_data = _clock
	_metaint = 0
	_until_meta = 0
	_meta_left = -1
	_meta.clear()


func _parse_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	if hostport.contains(":"):
		port = int(hostport.get_slice(":", 1))
		hostport = hostport.get_slice(":", 0)
	return {"tls": tls, "host": hostport, "port": port, "path": path}


func _fail() -> void:
	if _http:
		_http.close()
	_http = null
	_phase = 0
	status = "NO SIGNAL"
	_retry_at = _clock + 5.0
	changed.emit()


func _poll_http() -> void:
	if _http == null:
		return
	_http.poll()
	var s := _http.get_status()
	match _phase:
		1:
			if s == HTTPClient.STATUS_CONNECTED:
				var u := _parse_url(_url)
				var err := _http.request(HTTPClient.METHOD_GET, u["path"], ["Icy-MetaData: 1", "User-Agent: MidnightDrift/1.0", "Accept: */*"])
				if err != OK:
					_fail()
					return
				_phase = 2
			elif s in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
				_fail()
			elif _clock - _last_data > 10.0:
				_fail()
		2:
			if s == HTTPClient.STATUS_BODY or (s == HTTPClient.STATUS_CONNECTED and _http.has_response()):
				var code := _http.get_response_code()
				var headers := _http.get_response_headers_as_dictionary()
				var h := {}
				for k in headers:
					h[str(k).to_lower()] = str(headers[k])
				if code in [301, 302, 303, 307, 308] and h.has("location") and _redirects < 5:
					_redirects += 1
					var loc: String = h["location"]
					if loc.begins_with("/"):
						var u := _parse_url(_url)
						loc = ("https://" if u["tls"] else "http://") + str(u["host"]) + ("" if u["port"] in [80, 443] else ":%d" % u["port"]) + loc
					_http.close()
					_url = loc
					_connect()
					return
				if code != 200:
					_fail()
					return
				_metaint = int(h.get("icy-metaint", "0"))
				_until_meta = _metaint
				_phase = 3
				_last_data = _clock
			elif s in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED]:
				_fail()
			elif _clock - _last_data > 10.0:
				_fail()
		3:
			if s != HTTPClient.STATUS_BODY:
				_fail()
				return
			# take what is there, but not forever in one frame
			for i in 8:
				var chunk := _http.read_response_body_chunk()
				if chunk.is_empty():
					break
				_last_data = _clock
				_take(chunk)
				_http.poll()
			if _clock - _last_data > 8.0:
				_fail()


## Splits the body into audio and ICY metadata.
func _take(chunk: PackedByteArray) -> void:
	if _metaint <= 0:
		_audio.append_array(chunk)
	else:
		var i := 0
		var n := chunk.size()
		while i < n:
			if _meta_left < 0:
				if _until_meta > 0:
					var take := mini(_until_meta, n - i)
					_audio.append_array(chunk.slice(i, i + take))
					i += take
					_until_meta -= take
				else:
					_meta_left = chunk[i] * 16
					_meta.clear()
					i += 1
					if _meta_left == 0:
						_meta_left = -1
						_until_meta = _metaint
			else:
				var take := mini(_meta_left, n - i)
				_meta.append_array(chunk.slice(i, i + take))
				i += take
				_meta_left -= take
				if _meta_left <= 0:
					_meta_left = -1
					_until_meta = _metaint
					_read_meta()
	_split_frames()


func _read_meta() -> void:
	var text := _meta.get_string_from_utf8()
	if text == "":
		text = _meta.get_string_from_ascii()
	var at := text.find("StreamTitle='")
	if at < 0:
		return
	var rest := text.substr(at + 13)
	var end := rest.find("';")
	var t := (rest if end < 0 else rest.substr(0, end)).strip_edges()
	if t != title:
		title = t
		title_changed.emit()


const _BR1 := [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
const _BR2 := [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
const _SR := [44100, 48000, 32000, 0]


## Length (bytes) and duration of the MP3 frame at `i`, or [0, 0] if no frame header is there.
func _frame_at(i: int) -> Array:
	var b0 := _audio[i]
	var b1 := _audio[i + 1]
	var b2 := _audio[i + 2]
	if b0 != 0xFF or (b1 & 0xE0) != 0xE0:
		return [0, 0.0]
	var ver := (b1 >> 3) & 3
	var layer := (b1 >> 1) & 3
	var bri := b2 >> 4
	var sri := (b2 >> 2) & 3
	if ver == 1 or layer != 1 or bri == 0 or bri == 15 or sri == 3:
		return [0, 0.0]
	var sr: int = _SR[sri]
	if ver == 2:
		sr /= 2
	elif ver == 0:
		sr /= 4
	var pad := (b2 >> 1) & 1
	if ver == 3:
		return [144000 * int(_BR1[bri]) / sr + pad, 1152.0 / sr]
	return [72000 * int(_BR2[bri]) / sr + pad, 576.0 / sr]


func _split_frames() -> void:
	var i := 0
	var n := _audio.size()
	while i + 4 <= n:
		var f := _frame_at(i)
		var flen: int = f[0]
		if flen <= 4:
			i += 1          # not in step: look for the next frame header
			continue
		if i + flen > n:
			break
		# in step if the next frame follows right after (or the data ends there)
		if i + flen + 2 <= n and (_audio[i + flen] != 0xFF or (_audio[i + flen + 1] & 0xE0) != 0xE0):
			i += 1
			continue
		_frames.append(_audio.slice(i, i + flen))
		_frame_dur = f[1]
		_frames_dur += f[1]
		i += flen
		if _frames_dur >= (FIRST_CHUNK if _chunks_made == 0 else CHUNK):
			_make_chunk()
	if i > 0:
		_audio = _audio.slice(i)


func _make_chunk() -> void:
	var bytes := PackedByteArray()
	for f in _tail:
		bytes.append_array(f)
	for f in _frames:
		bytes.append_array(f)
	var st := AudioStreamMP3.new()
	st.data = bytes
	var overlap := _tail.size() * _frame_dur
	_queue.append({"stream": st, "len": (_tail.size() + _frames.size()) * _frame_dur, "overlap": overlap})
	_tail = _frames.slice(maxi(_frames.size() - OVERLAP_FRAMES, 0))
	_frames = []
	_frames_dur = 0.0
	_chunks_made += 1


func _queued_secs() -> float:
	var t := 0.0
	for q in _queue:
		t += float(q["len"]) - float(q["overlap"])
	return t


func _start_chunk(pi: int, q: Dictionary, from := 0.0, vol := 1.0) -> void:
	var p := _players[pi]
	p.stream = q["stream"]
	p.volume_db = _db(volume * vol)
	p.play(from)
	_cur_len = float(q["len"])


func _drive_stream(delta: float) -> void:
	if mode == "tape" and _tape_files.size() > 0:
		return
	var cur_playing := _cur >= 0 and _players[_cur].playing
	if not cur_playing and _xf < 0.0:
		# nothing (or no more) playing: start with enough in the buffer
		if _queue.size() > 0 and (_queued_secs() >= START_BUFFER or (_chunks_made > 0 and _phase != 3)):
			var q: Dictionary = _queue.pop_front()
			_cur = 0 if _cur < 0 else _cur
			_start_chunk(_cur, q, float(q["overlap"]))
			_next_started = false
			if status != "PLAY":
				status = "PLAY"
				changed.emit()
		elif _cur >= 0 and _phase == 3 and status == "PLAY":
			status = "TUNING"       # ran dry
			changed.emit()
		return
	if _xf >= 0.0:
		# the crossfade into the next chunk
		_xf += delta
		var a := clampf((_xf - FADE_FROM) / FADE_LEN, 0.0, 1.0)
		var nxt := 1 - _cur
		_players[nxt].volume_db = _db(volume * a)
		_players[_cur].volume_db = _db(volume * (1.0 - a))
		if a >= 1.0:
			_players[_cur].stop()
			_cur = nxt
			_xf = -1.0
		return
	if _queue.size() > 0:
		var q: Dictionary = _queue[0]
		var pos := _players[_cur].get_playback_position()
		if pos >= _cur_len - float(q["overlap"]) - 0.01:
			_queue.pop_front()
			_start_chunk(1 - _cur, q, 0.0, 0.0)
			_xf = 0.0


func _apply_volume() -> void:
	if _xf >= 0.0:
		return
	for p in _players:
		p.volume_db = _db(volume)


func _db(v: float) -> float:
	# a gentle curve, and the radio a bit under the game's sounds
	return linear_to_db(maxf(v * v * 0.8, 0.00001))


func _process(delta: float) -> void:
	_clock += delta
	if _save_at > 0.0 and _clock >= _save_at:
		_save_at = -1.0
		Game.save_settings()
	if not on:
		return
	if _retry_at > 0.0 and _clock >= _retry_at:
		_retry_at = -1.0
		_connect()
	_poll_http()
	_drive_stream(delta)


# ---------------------------------------------------------------------------
# Little sounds of the buttons and the tape mechanism (made here, no files)
# ---------------------------------------------------------------------------
var _click := _make_click(0.018, 5200.0, 0.0)
var _clunk := _make_click(0.16, 900.0, 1.0)


static func _make_click(secs: float, tone: float, thump: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(secs * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * (40.0 if thump > 0.0 else 260.0))
		var v := rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * tone * t) * 0.5
		if thump > 0.0:
			v = v * 0.35 + sin(TAU * 70.0 * t) * thump * exp(-t * 25.0)
			# a second click as the tape seats
			if t > 0.09:
				v += rng.randf_range(-1.0, 1.0) * exp(-(t - 0.09) * 200.0) * 0.6
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
