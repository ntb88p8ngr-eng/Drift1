extends Node
## Public server list (Online → Serverliste). Hosts and dedicated servers that choose to be public
## post a small heartbeat to a topic on the public relay (ntfy.sh, also used for the short codes):
## name, players, track, mode, password yes/no and the short code to join – never an IP address.
## The list reads the heartbeats of the last two minutes. MD_SIGNAL=file (tests): a folder instead.

signal changed

const RELAY := "https://ntfy.sh/"
const TOPIC := "midnightdrift-servers-v1"
const BEAT := 40.0                # seconds between heartbeats
const MAX_AGE := 120              # seconds a heartbeat counts

var servers := {}                 # short code -> info (newest heartbeat)
var fetching := false
var last_error := ""
var _beat_t := 0.0
var _info_fn: Callable            # returns the heartbeat to post, or {} (not public)
var _file_mode := false


func _ready() -> void:
	_file_mode = OS.get_environment("MD_SIGNAL") == "file"


## Starts / stops the heartbeat; `info_fn` is asked for the current state every time.
func announce(info_fn: Callable) -> void:
	_info_fn = info_fn
	_beat_t = 0.5


func stop_announce() -> void:
	_info_fn = Callable()


func _process(delta: float) -> void:
	if not _info_fn.is_valid():
		return
	_beat_t -= delta
	if _beat_t > 0.0:
		return
	_beat_t = BEAT
	var info: Dictionary = _info_fn.call()
	if info.is_empty():
		return
	info["t"] = int(Time.get_unix_time_from_system())
	_post(JSON.stringify(info))


func _post(body: String) -> void:
	if _file_mode:
		var dir := "user://server_list"
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("%d.json" % Time.get_ticks_usec()), FileAccess.WRITE)
		if f:
			f.store_string(body)
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	if req.request(RELAY + TOPIC, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()


## Reads the current list (emits `changed` when done).
func refresh() -> void:
	if fetching:
		return
	fetching = true
	last_error = ""
	if _file_mode:
		var now := int(Time.get_unix_time_from_system())
		var dir := DirAccess.open("user://server_list")
		if dir:
			for fn in dir.get_files():
				_take(FileAccess.get_file_as_string("user://server_list".path_join(fn)), now)
		fetching = false
		changed.emit()
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		fetching = false
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			last_error = "Serverliste nicht erreichbar (keine Internetverbindung?)"
			changed.emit()
			return
		var now := int(Time.get_unix_time_from_system())
		servers.clear()
		for line in body.get_string_from_utf8().split("\n", false):
			var m = JSON.parse_string(line)
			if m is Dictionary and str(m.get("event", "")) == "message":
				_take(str(m.get("message", "")), now)
		changed.emit())
	if req.request(RELAY + TOPIC + "/json?poll=1&since=%ds" % MAX_AGE) != OK:
		req.queue_free()
		fetching = false


## One heartbeat into the list (checked: everything must look like ours).
func _take(text: String, now: int) -> void:
	var d = JSON.parse_string(text)
	if not (d is Dictionary):
		return
	if str(d.get("game", "")) != Net.GAME_TAG:
		return
	var code := Net.Rendezvous.normalize(str(d.get("code", "")))
	if code == "" or now - int(d.get("t", 0)) > MAX_AGE:
		return
	var info := {
		"code": code, "name": str(d.get("name", "Server")).substr(0, 40), "players": clampi(int(d.get("players", 0)), 0, 64),
		"max": clampi(int(d.get("max", 8)), 1, 64), "track": str(d.get("track", "")), "mode": str(d.get("mode", "")),
		"locked": bool(d.get("locked", false)), "dedicated": bool(d.get("dedicated", false)), "in_race": bool(d.get("in_race", false)),
		"v": str(d.get("v", "")), "motd": str(d.get("motd", "")).substr(0, 120), "t": int(d.get("t", 0)),
	}
	if not servers.has(code) or int(servers[code]["t"]) <= info["t"]:
		servers[code] = info
