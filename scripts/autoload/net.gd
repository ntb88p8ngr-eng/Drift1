extends Node
## Online mode: lobbies hosted by the lobby creator (ENet server + player in one process),
## LAN lobby discovery via UDP broadcast and optional UPnP port forwarding.
##
## Security (LAN and internet, game to game – no server in between):
## - all traffic is DTLS-encrypted (ENet over DTLS). The host's self-signed certificate travels in the
##   invite code (or the LAN announcement) and is pinned by the client, so nobody can sit in between
## - joining needs the lobby password: challenge-response with HMAC-SHA256 over fresh nonces in both
##   directions (SceneMultiplayer authentication), the password itself is never sent; until a peer is
##   authenticated it can't call any RPC and nothing is relayed to/from it
## - repeated wrong passwords from one address are banned for a while
## - star topology: players only talk to the host, so they never learn each other's IP addresses;
##   no IP is shown anywhere in the lobby. The host's address travels only inside the invite code the
##   host hands out (direct connections always reveal the host's IP to those it invites).

signal lobby_changed
signal connected_ok
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal race_start_requested(config: Dictionary)
signal countdown_requested
signal chat_received(from_name: String, text: String)
signal remote_state(peer_id: int, state: Array)
signal peer_left(peer_id: int)
signal results_updated(results: Array)
signal return_to_lobby_requested
signal lan_lobbies_changed
signal upnp_finished(ok: bool, message: String)
signal graffiti_claimed(owner_id: int, cells: PackedInt32Array)

const DEFAULT_PORT := 24570
const DISCOVERY_PORT := 24571
const GAME_TAG := "MidnightDrift"
const INVITE_PREFIX := "MD1-"
const AUTH_TIMEOUT := 8.0
const BAN_AFTER := 5            # failed logins per address …
const BAN_TIME_MS := 120000     # … lock it out for 2 minutes
const HOST_CN := "midnight-drift-host"
const KEY_PATH := "user://net_host.key"
const CERT_PATH := "user://net_host.crt"

var peer: ENetMultiplayerPeer
var players := {}          # peer_id(int) -> info Dictionary
var lobby := {}            # lobby settings, owned by the host
var is_online := false
var in_race := false
var results := {}          # peer_id -> result Dictionary (host)
var result_list: Array = []
var lan_lobbies := {}      # "ip:port" -> info Dictionary
var upnp_message := ""
var public_ip := ""        # host: from UPnP or the manual lookup, for the invite code
var password := ""         # host: lobby password / client: password used to join
var cert_body := ""        # host: its certificate (base64 DER) for invite codes and LAN announcements

var _auth := {}            # peer_id -> {"hn": host nonce, "cn": client nonce}
var _fails := {}           # remote address -> [failed logins, locked until (msec)]
var _crypto := Crypto.new()

var _loaded := {}
var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_port := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _on_auth_packet
	sm.auth_timeout = AUTH_TIMEOUT
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(_on_peer_auth_failed)


func _exit_tree() -> void:
	leave()
	stop_lan_scan()
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


func is_host() -> bool:
	return is_online and multiplayer.multiplayer_peer != null and multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online else 1


# ---------------------------------------------------------------------------
# Hosting / joining
# ---------------------------------------------------------------------------
## Creates a lobby on this machine. Returns an error text or "" on success.
func host_lobby(lobby_name: String, port: int, max_players: int, use_upnp: bool, lobby_password := "") -> String:
	leave()
	var tls := _server_tls()
	if tls == null:
		return "Verschlüsselung konnte nicht eingerichtet werden (Zertifikat)."
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, maxi(max_players - 1, 1))
	if err != OK:
		peer = null
		return "Server konnte nicht gestartet werden – ist Port %d schon belegt?" % port
	err = peer.host.dtls_server_setup(tls)
	if err != OK:
		peer.close()
		peer = null
		return "Verschlüsselung (DTLS) konnte nicht gestartet werden."
	password = lobby_password.strip_edges()
	public_ip = ""
	_auth.clear()
	multiplayer.multiplayer_peer = peer
	is_online = true
	in_race = false
	lobby = {
		"name": lobby_name if lobby_name.strip_edges() != "" else "%s's Lobby" % Game.settings["player_name"],
		"port": port,
		"max_players": max_players,
		"track": Game.settings["track"],
		"laps": int(Game.settings["laps"]),
		"mode": Game.settings["mode"] if Game.settings["mode"] != "free" else "race",
		"time_of_day": Game.settings["time_of_day"],
		"weather": Game.settings["weather"],
		"day_cycle": int(Game.settings["day_cycle"]),
		"collisions": true,
		"host_id": 1,
		"locked": password != "",
	}
	players = {1: Game.local_player_info()}
	_start_broadcast()
	upnp_message = ""
	if use_upnp:
		_start_upnp(port)
	lobby_changed.emit()
	return ""


func join_lobby(address: String, port: int, lobby_password: String, host_cert: String) -> String:
	leave()
	address = address.strip_edges()
	if address == "":
		return "Bitte eine IP-Adresse eingeben."
	var cert := X509Certificate.new()
	if host_cert == "" or cert.load_from_string(_pem(host_cert)) != OK:
		return "Ungültiger Einladungs-Code (Zertifikat fehlt)."
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return "Verbindung zu %s:%d konnte nicht aufgebaut werden." % [address, port]
	# encrypted before the first packet leaves (the host proves itself with the password, see _on_auth_packet)
	err = peer.host.dtls_client_setup(address, TLSOptions.client(cert, HOST_CN))
	if err != OK:
		peer.close()
		peer = null
		return "Verschlüsselung (DTLS) konnte nicht gestartet werden."
	password = lobby_password.strip_edges()
	_auth.clear()
	multiplayer.multiplayer_peer = peer
	is_online = true
	in_race = false
	return ""


## Joins with an invite code from the host (address, port and password in one string).
func join_invite(code: String) -> String:
	var inv := parse_invite(code)
	if inv.is_empty():
		return "Ungültiger Einladungs-Code."
	return join_lobby(inv["ip"], int(inv["port"]), inv["pw"], inv["cert"])


## Invite code for this lobby, "" while the public address is unknown.
func invite_code() -> String:
	if not is_host() or public_ip == "":
		return ""
	var raw := "%s|%d|%s" % [public_ip, int(lobby.get("port", DEFAULT_PORT)), password]
	return INVITE_PREFIX + _b64url(raw.to_utf8_buffer()) + "." + _b64url(Marshalls.base64_to_raw(cert_body))


static func parse_invite(code: String) -> Dictionary:
	code = code.strip_edges().replace("\n", "").replace(" ", "")
	if not code.begins_with(INVITE_PREFIX) or not code.contains("."):
		return {}
	var halves := code.substr(INVITE_PREFIX.length()).split(".", true, 1)
	var parts := _unb64url(halves[0]).get_string_from_utf8().split("|", true, 2)
	if parts.size() != 3 or not parts[1].is_valid_int():
		return {}
	var port := int(parts[1])
	var der := _unb64url(halves[1])
	if parts[0] == "" or port <= 0 or port > 65535 or der.size() < 200:
		return {}
	return {"ip": parts[0], "port": port, "pw": parts[2], "cert": Marshalls.raw_to_base64(der)}


static func _b64url(raw: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(raw).replace("+", "-").replace("/", "_").replace("=", "")


static func _unb64url(text: String) -> PackedByteArray:
	var b64 := text.replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	return Marshalls.base64_to_raw(b64)


## PEM text from a base64 DER certificate body.
static func _pem(body: String) -> String:
	var lines: Array = ["-----BEGIN CERTIFICATE-----"]
	var i := 0
	while i < body.length():
		lines.append(body.substr(i, 64))
		i += 64
	lines.append("-----END CERTIFICATE-----")
	return "\n".join(lines) + "\n"


## Host: asks a public "what is my IP" service (only when the player presses the button).
func lookup_public_ip() -> void:
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address():
			public_ip = ip
		else:
			upnp_message = "Öffentliche IP konnte nicht ermittelt werden."
		lobby_changed.emit())
	if req.request("https://api.ipify.org") != OK:
		req.queue_free()


func leave() -> void:
	_stop_broadcast()
	_remove_upnp()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer = null
	players.clear()
	lobby.clear()
	results.clear()
	result_list.clear()
	_loaded.clear()
	_auth.clear()
	is_online = false
	in_race = false


func get_local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	return out


# ---------------------------------------------------------------------------
# Encryption & authentication
# ---------------------------------------------------------------------------
## The host's DTLS key and self-signed certificate (created once, kept in user://).
func _server_tls() -> TLSOptions:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if not (FileAccess.file_exists(KEY_PATH) and FileAccess.file_exists(CERT_PATH)
			and key.load(KEY_PATH) == OK and cert.load(CERT_PATH) == OK):
		key = _crypto.generate_rsa(2048)
		cert = _crypto.generate_self_signed_certificate(key, "CN=%s,O=Midnight Drift,C=DE" % HOST_CN,
			"20240101000000", "20440101000000")
		if key == null or cert == null:
			return null
		key.save(KEY_PATH)
		cert.save(CERT_PATH)
	var pem := cert.save_to_string()
	cert_body = ""
	for line in pem.split("\n"):
		if not line.begins_with("-----"):
			cert_body += line.strip_edges()
	return TLSOptions.server(key, cert)


func _mac(label: String, a: PackedByteArray, b: PackedByteArray) -> PackedByteArray:
	var k := ("MidnightDrift-lobby|" + password).sha256_buffer()
	var msg := label.to_utf8_buffer()
	msg.append_array(a)
	msg.append_array(b)
	return _crypto.hmac_digest(HashingContext.HASH_SHA256, k, msg)


func _send_auth(id: int, msg: Array) -> void:
	(multiplayer as SceneMultiplayer).send_auth(id, var_to_bytes(msg))


func _remote_address(id: int) -> String:
	if peer == null:
		return ""
	var pp := peer.get_peer(id)
	return pp.get_remote_address() if pp else ""


func _on_peer_authenticating(id: int) -> void:
	if not multiplayer.is_server():
		return   # the client waits for the host's challenge
	var addr := _remote_address(id)
	var f: Array = _fails.get(addr, [0, 0])
	if int(f[1]) > Time.get_ticks_msec():
		(multiplayer as SceneMultiplayer).disconnect_peer(id)
		return
	var hn := _crypto.generate_random_bytes(16)
	_auth[id] = {"hn": hn}
	_send_auth(id, ["chal", hn])


func _on_auth_packet(id: int, data: PackedByteArray) -> void:
	var msg = bytes_to_var(data) if data.size() <= 512 else null
	if not (msg is Array) or (msg as Array).is_empty():
		_auth_fail(id)
		return
	var kind := str(msg[0])
	var sm := multiplayer as SceneMultiplayer
	if multiplayer.is_server():
		# client answers: its nonce + proof that it knows the password
		if kind != "resp" or msg.size() != 3 or not _auth.has(id) or not (msg[1] is PackedByteArray) or not (msg[2] is PackedByteArray):
			_auth_fail(id)
			return
		var hn: PackedByteArray = _auth[id]["hn"]
		var cn: PackedByteArray = msg[1]
		if cn.size() != 16 or not _crypto.constant_time_compare(_mac("c", hn, cn), msg[2]):
			_auth_fail(id)
			return
		_fails.erase(_remote_address(id))
		_send_auth(id, ["ok", _mac("h", hn, cn)])
		_auth.erase(id)
		sm.complete_auth(id)
	else:
		if kind == "chal" and msg.size() == 2 and msg[1] is PackedByteArray and (msg[1] as PackedByteArray).size() == 16:
			var cn := _crypto.generate_random_bytes(16)
			_auth[id] = {"hn": msg[1], "cn": cn}
			_send_auth(id, ["resp", cn, _mac("c", msg[1], cn)])
		elif kind == "ok" and msg.size() == 2 and _auth.has(id) and msg[1] is PackedByteArray:
			# the host must know the password too (no fake lobbies)
			if _crypto.constant_time_compare(_mac("h", _auth[id]["hn"], _auth[id]["cn"]), msg[1]):
				_auth.erase(id)
				sm.complete_auth(id)
			else:
				leave()
				connection_failed.emit("Der Host konnte sich nicht ausweisen – Verbindung abgebrochen.")
		elif kind == "bad":
			leave()
			connection_failed.emit("Falsches Lobby-Passwort.")
		else:
			_auth_fail(id)


func _auth_fail(id: int) -> void:
	if multiplayer.is_server():
		var addr := _remote_address(id)
		var f: Array = _fails.get(addr, [0, 0])
		f[0] = int(f[0]) + 1
		if int(f[0]) >= BAN_AFTER:
			f = [0, Time.get_ticks_msec() + BAN_TIME_MS]
		_fails[addr] = f
		_auth.erase(id)
		_send_auth(id, ["bad"])
		_disconnect_later(id)
	else:
		leave()
		connection_failed.emit("Anmeldung an der Lobby fehlgeschlagen.")


func _on_peer_auth_failed(id: int) -> void:
	_auth.erase(id)
	if not multiplayer.is_server() and is_online:
		leave()
		connection_failed.emit("Anmeldung fehlgeschlagen (Zeitüberschreitung oder falsches Passwort).")


# ---------------------------------------------------------------------------
# Multiplayer callbacks
# ---------------------------------------------------------------------------
func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var who: String = players[id].get("name", "Spieler")
		players.erase(id)
		chat_received.emit("Lobby", "%s hat die Lobby verlassen." % who)
	peer_left.emit(id)
	if is_host():
		_loaded.erase(id)
		_broadcast_lobby()
		_check_all_loaded()
	lobby_changed.emit()


func _on_connected_to_server() -> void:
	_register.rpc_id(1, Game.local_player_info())
	connected_ok.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("Verbindung fehlgeschlagen – Host nicht erreichbar (IP/Port/Firewall prüfen).")


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit("Die Verbindung zum Host wurde getrennt.")


# ---------------------------------------------------------------------------
# Lobby RPCs
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if str(info.get("version", "")) != Game.VERSION:
		_kicked.rpc_id(id, "Versionskonflikt: Host hat %s, du hast %s." % [Game.VERSION, info.get("version", "?")])
		_disconnect_later(id)
		return
	if in_race:
		_kicked.rpc_id(id, "In dieser Lobby läuft gerade ein Rennen – bitte gleich nochmal versuchen.")
		_disconnect_later(id)
		return
	info["ready"] = false
	info["name"] = str(info.get("name", "Driver")).substr(0, 20)
	players[id] = info
	_broadcast_lobby()
	_chat_all("Lobby", "%s ist beigetreten." % info["name"])


func _disconnect_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if peer:
		peer.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	leave()
	disconnected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(new_players: Dictionary, new_lobby: Dictionary) -> void:
	players = new_players
	lobby = new_lobby
	lobby_changed.emit()


func _broadcast_lobby() -> void:
	if not is_host():
		return
	_sync_lobby.rpc(players, lobby)
	lobby_changed.emit()


func set_ready(value: bool) -> void:
	if is_host():
		players[1]["ready"] = value
		_broadcast_lobby()
	else:
		_set_ready.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _set_ready(value: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		players[id]["ready"] = value
		_broadcast_lobby()


## Sends changed car/paint/name to the host.
func update_local_info() -> void:
	if not is_online:
		return
	var info := Game.local_player_info()
	var me := local_id()
	if players.has(me):
		info["ready"] = players[me].get("ready", false)
	if is_host():
		players[1] = info
		_broadcast_lobby()
	else:
		_update_info.rpc_id(1, info)


@rpc("any_peer", "call_remote", "reliable")
func _update_info(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		info["name"] = str(info.get("name", "Driver")).substr(0, 20)
		players[id] = info
		_broadcast_lobby()


func host_set_option(key: String, value) -> void:
	if not is_host():
		return
	lobby[key] = value
	for id in players.keys():
		if id != 1:
			players[id]["ready"] = false
	_broadcast_lobby()


func all_ready() -> bool:
	for id in players.keys():
		if id != 1 and not players[id].get("ready", false):
			return false
	return true


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 200)
	if text == "" or not is_online:
		return
	_chat.rpc(text)
	chat_received.emit(Game.settings["player_name"], text)


@rpc("any_peer", "call_remote", "reliable")
func _chat(text: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var who := "?"
	if players.has(id):
		who = players[id].get("name", "?")
	chat_received.emit(who, text.substr(0, 200))


func _chat_all(from_name: String, text: String) -> void:
	_system_chat.rpc(from_name, text)
	chat_received.emit(from_name, text)


@rpc("authority", "call_remote", "reliable")
func _system_chat(from_name: String, text: String) -> void:
	chat_received.emit(from_name, text)


# ---------------------------------------------------------------------------
# Race flow
# ---------------------------------------------------------------------------
func host_start_race() -> String:
	if not is_host():
		return "Nur der Host kann starten."
	if not all_ready():
		return "Noch nicht alle Spieler sind bereit."
	var config := {
		"track": lobby.get("track", "ridge"),
		"laps": int(lobby.get("laps", 3)),
		"mode": lobby.get("mode", "race"),
		"time_of_day": lobby.get("time_of_day", "dusk"),
		"weather": lobby.get("weather", "dry"),
		"day_cycle": int(lobby.get("day_cycle", 0)),
		"weather_seed": randi() % 100000,
		"collisions": bool(lobby.get("collisions", true)),
		"online": true,
		"players": players.duplicate(true),
	}
	_start_race.rpc(config)
	return ""


@rpc("authority", "call_local", "reliable")
func _start_race(config: Dictionary) -> void:
	in_race = true
	results.clear()
	result_list.clear()
	_loaded.clear()
	race_start_requested.emit(config)


## Called by the world once the track is built on this machine.
func notify_loaded() -> void:
	if not is_online:
		return
	if is_host():
		_mark_loaded(1)
	else:
		_client_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_loaded() -> void:
	if is_host():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	_loaded[id] = true
	_check_all_loaded()


func _check_all_loaded() -> void:
	if not is_host() or not in_race or _loaded.is_empty() or _loaded.has(-1):
		return
	for id in players.keys():
		if not _loaded.has(id):
			return
	force_countdown()


## Host: start the countdown for everyone (also used as timeout fallback).
func force_countdown() -> void:
	if is_host() and in_race:
		_loaded.clear()
		_loaded[-1] = true  # marker so the countdown fires only once
		_begin_countdown.rpc()


@rpc("authority", "call_local", "reliable")
func _begin_countdown() -> void:
	countdown_requested.emit()


func send_state(state: Array) -> void:
	if is_online and multiplayer.multiplayer_peer != null:
		_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _state(state: Array) -> void:
	remote_state.emit(multiplayer.get_remote_sender_id(), state)


## Graffiti mode: cells the local player sprayed. The host applies claims in arrival order and
## broadcasts them, so everybody ends up with the same owners.
func send_graffiti(cells: PackedInt32Array) -> void:
	if not is_online or cells.is_empty():
		return
	if is_host():
		graffiti_claimed.emit(1, cells)
		_graffiti_sync.rpc(1, cells)
	else:
		_graffiti_claim.rpc_id(1, cells)


@rpc("any_peer", "call_remote", "reliable")
func _graffiti_claim(cells: PackedInt32Array) -> void:
	if not is_host() or cells.size() > 256:
		return
	var id := multiplayer.get_remote_sender_id()
	graffiti_claimed.emit(id, cells)
	_graffiti_sync.rpc(id, cells)


@rpc("authority", "call_remote", "reliable")
func _graffiti_sync(owner_id: int, cells: PackedInt32Array) -> void:
	graffiti_claimed.emit(owner_id, cells)


func report_result(result: Dictionary) -> void:
	if not is_online:
		return
	if is_host():
		_store_result(1, result)
	else:
		_report_result.rpc_id(1, result)


@rpc("any_peer", "call_remote", "reliable")
func _report_result(result: Dictionary) -> void:
	if is_host():
		_store_result(multiplayer.get_remote_sender_id(), result)


func _store_result(id: int, result: Dictionary) -> void:
	result["id"] = id
	if players.has(id):
		result["name"] = players[id].get("name", "?")
		result["car"] = players[id].get("car", "r34")
	results[id] = result
	var arr: Array = results.values()
	_sync_results.rpc(arr)
	_apply_results(arr)


@rpc("authority", "call_remote", "reliable")
func _sync_results(arr: Array) -> void:
	_apply_results(arr)


func _apply_results(arr: Array) -> void:
	result_list = arr
	results_updated.emit(arr)


func host_return_to_lobby() -> void:
	if not is_host():
		return
	for id in players.keys():
		players[id]["ready"] = false
	_return_lobby.rpc()
	_sync_lobby.rpc(players, lobby)


@rpc("authority", "call_local", "reliable")
func _return_lobby() -> void:
	in_race = false
	return_to_lobby_requested.emit()


# ---------------------------------------------------------------------------
# LAN discovery
# ---------------------------------------------------------------------------
func _start_broadcast() -> void:
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0


func _stop_broadcast() -> void:
	if _broadcaster:
		_broadcaster.close()
	_broadcaster = null


func start_lan_scan() -> void:
	stop_lan_scan()
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		_listener = null
		push_warning("LAN-Suche: Port %d konnte nicht gebunden werden" % DISCOVERY_PORT)
	lan_lobbies.clear()
	lan_lobbies_changed.emit()


func stop_lan_scan() -> void:
	if _listener:
		_listener.close()
	_listener = null


func _process(delta: float) -> void:
	if _broadcaster and is_host():
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = 1.0
			var info := {
				"game": GAME_TAG, "v": Game.VERSION, "name": lobby.get("name", "Lobby"),
				"port": lobby.get("port", DEFAULT_PORT), "players": players.size(),
				"max": lobby.get("max_players", 8), "track": lobby.get("track", "ridge"),
				"mode": lobby.get("mode", "race"), "in_race": in_race, "locked": password != "", "cert": cert_body,
			}
			_broadcaster.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var parsed = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary and parsed.get("game", "") == GAME_TAG:
				parsed["ip"] = ip
				parsed["seen"] = Time.get_ticks_msec()
				lan_lobbies["%s:%d" % [ip, int(parsed.get("port", DEFAULT_PORT))]] = parsed
				changed = true
		var now := Time.get_ticks_msec()
		for key in lan_lobbies.keys():
			if now - int(lan_lobbies[key]["seen"]) > 4000:
				lan_lobbies.erase(key)
				changed = true
		if changed:
			lan_lobbies_changed.emit()


# ---------------------------------------------------------------------------
# UPnP (self hosting over the internet without manual port forwarding)
# ---------------------------------------------------------------------------
func _start_upnp(port: int) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	upnp_message = "UPnP: Suche Router …"
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker.bind(port))


func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var err: int = upnp.discover(2000, 2, "InternetGatewayDevice")
	var ok := false
	var msg := ""
	if err == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() != null and upnp.get_gateway().is_valid_gateway():
		var r: int = upnp.add_port_mapping(port, port, "Midnight Drift", "UDP")
		if r == UPNP.UPNP_RESULT_SUCCESS:
			ok = true
			msg = "UPnP aktiv – Port %d offen." % port
		else:
			msg = "UPnP: Portfreigabe fehlgeschlagen (Code %d). Port %d/UDP ggf. manuell freigeben." % [r, port]
	else:
		msg = "Kein UPnP-Router gefunden – für Internet-Spiele Port %d/UDP im Router freigeben." % port
	call_deferred("_upnp_done", ok, msg, upnp if ok else null, port)


func _upnp_done(ok: bool, msg: String, upnp: UPNP, port: int) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	if ok and is_host():
		_upnp = upnp
		_upnp_port = port
		var ext := upnp.query_external_address()
		if ext.is_valid_ip_address():
			public_ip = ext
	elif ok and upnp:
		upnp.delete_port_mapping(port, "UDP")
	upnp_message = msg
	upnp_finished.emit(ok, msg)


func _remove_upnp() -> void:
	if _upnp:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = 0
