extends Node
## Online mode: lobbies hosted by the lobby creator (ENet server + player in one process),
## LAN lobby discovery via UDP broadcast and optional UPnP port forwarding.

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

const DEFAULT_PORT := 24570
const DISCOVERY_PORT := 24571
const GAME_TAG := "MidnightDrift"

var peer: ENetMultiplayerPeer
var players := {}          # peer_id(int) -> info Dictionary
var lobby := {}            # lobby settings, owned by the host
var is_online := false
var in_race := false
var results := {}          # peer_id -> result Dictionary (host)
var result_list: Array = []
var lan_lobbies := {}      # "ip:port" -> info Dictionary
var upnp_message := ""

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
func host_lobby(lobby_name: String, port: int, max_players: int, use_upnp: bool) -> String:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, maxi(max_players - 1, 1))
	if err != OK:
		peer = null
		return "Server konnte nicht gestartet werden – ist Port %d schon belegt?" % port
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
		"collisions": true,
		"host_id": 1,
	}
	players = {1: Game.local_player_info()}
	_start_broadcast()
	upnp_message = ""
	if use_upnp:
		_start_upnp(port)
	lobby_changed.emit()
	return ""


func join_lobby(address: String, port: int) -> String:
	leave()
	address = address.strip_edges()
	if address == "":
		return "Bitte eine IP-Adresse eingeben."
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return "Verbindung zu %s:%d konnte nicht aufgebaut werden." % [address, port]
	multiplayer.multiplayer_peer = peer
	is_online = true
	in_race = false
	return ""


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
				"mode": lobby.get("mode", "race"), "in_race": in_race,
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
			msg = "UPnP aktiv – Port %d offen. Öffentliche IP: %s" % [port, upnp.query_external_address()]
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
	elif ok and upnp:
		upnp.delete_port_mapping(port, "UDP")
	upnp_message = msg
	upnp_finished.emit(ok, msg)


func _remove_upnp() -> void:
	if _upnp:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = 0
