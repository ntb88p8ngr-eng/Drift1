extends Node

const RaceAI = preload("res://scripts/world/race_ai.gd")
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
signal voice_received(peer_id: int, data: PackedByteArray)
signal peer_left(peer_id: int)
signal results_updated(results: Array)
signal return_to_lobby_requested
signal lan_lobbies_changed
signal upnp_finished(ok: bool, message: String)
signal graffiti_claimed(owner_id: int, cells: PackedInt32Array)
signal party_msg(from_id: int, msg: Dictionary)
signal join_status(text: String)   # short-code join: progress for the menu
signal code_result(ok: bool, text: String)   # an action code checked by the server

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
var _last_address := ""     # client: the address last joined (for a helpful error message)
var password := ""         # host: lobby password / client: password used to join
var cert_body := ""        # host: its certificate (base64 DER) for invite codes and LAN announcements

var _auth := {}            # peer_id -> {"hn": host nonce, "cn": client nonce}
var _fails := {}           # remote address -> [failed logins, locked until (msec)]
var _crypto := Crypto.new()

var _loaded := {}
var countdown_t0 := -1           # when this race's countdown began here (ticks ms), -1 = not yet
var _keepalive_last := 0
var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_port := 0

const Rendezvous = preload("res://scripts/autoload/rendezvous.gd")
const ServerList = preload("res://scripts/autoload/server_list.gd")
var server_list: Node
var dedicated := false      # this machine is a dedicated server (no player of its own)
var public_list := false    # shown in the public server list
var motd := ""              # dedicated server: message of the day (lobby chat, server list)
var server_codes := {}      # dedicated server: action codes CODE -> {credits, car}
var _redeemed := {}         # server: CODE -> [player names that used it]
var host_code := ""        # host: short code for internet play (no port forwarding needed)
var _rv: Node              # Rendezvous while hosting or joining by code
var _host_cands: Array = []
var _rv_udp: PacketPeerUDP  # joiner: socket the STUN request and the hole punching use
var _rv_local_port := 0
var _rv_join_id := ""
var _rv_state := ""         # joiner: "wait", "punch", "connect"
var _rv_deadline := 0
var _rv_resend := 0.0
var _rv_my_cands: Array = []
var _rv_queue: Array = []   # joiner: host addresses still to try
var _rv_cert := ""
var _rv_pw := ""
var _rv_seen_welcome := false


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
	server_list = ServerList.new()
	server_list.name = "ServerList"
	add_child(server_list)


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
func host_lobby(lobby_name: String, port: int, max_players: int, use_upnp: bool, lobby_password := "", p_dedicated := false, p_public := false) -> String:
	leave()
	dedicated = p_dedicated
	public_list = p_public
	var tls := _server_tls()
	if tls == null:
		return "Verschlüsselung konnte nicht eingerichtet werden (Zertifikat)."
	# what the internet sees of this port (for the short code), asked before ENet takes it over
	var seen: Array = []
	var probe := PacketPeerUDP.new()
	if probe.bind(port, "*") == OK:
		seen = Rendezvous.stun(probe)
		probe.close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, maxi(max_players - (0 if dedicated else 1), 1))
	if err != OK:
		peer = null
		return Game.t("Server konnte nicht gestartet werden – ist Port %d schon belegt?") % port
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
		"name": lobby_name if lobby_name.strip_edges() != "" else Game.t("%s's Lobby") % Game.settings["player_name"],
		"port": port,
		"max_players": max_players,
		"track": Game.settings["track"],
		"layout": str(Game.settings.get("layout", "normal")),
		"laps": int(Game.settings["laps"]),
		"graffiti_minutes": int(Game.settings.get("graffiti_minutes", 5)),
		"party": bool(Game.settings.get("party", false)),
		"party_games": int(Game.settings.get("party_games", 3)),
		"party_coins": int(Game.settings.get("party_coins", 5)),
		"party_coins_city": bool(Game.settings.get("party_coins_city", false)),
		"mode": Game.settings["mode"] if Game.settings["mode"] != "free" else "race",
		"time_of_day": Game.settings["time_of_day"],
		"weather": Game.settings["weather"],
		"day_cycle": int(Game.settings["day_cycle"]),
		"collisions": true,
		"bots": int(Game.settings.get("bots", 0)),
		"bot_level": int(Game.settings.get("bot_level", 1)),
		"host_id": 0 if dedicated else 1,
		"locked": password != "",
		"dedicated": dedicated,
	}
	players = {} if dedicated else {1: Game.local_player_info()}
	if dedicated:
		# no world on a dedicated server: nobody to drive bots or run party games
		lobby["bots"] = 0
		lobby["party"] = false
	_start_broadcast()
	_host_cands = Rendezvous.candidates(seen, port, global_ipv6_addresses(), get_local_addresses())
	_start_rendezvous(Rendezvous.make_code())
	if public_list:
		server_list.announce(_heartbeat)
	upnp_message = ""
	if use_upnp:
		_start_upnp(port)
	lobby_changed.emit()
	return ""


func join_lobby(address: String, port: int, lobby_password: String, host_cert: String, local_port := 0) -> String:
	leave()
	var ap := split_address(address, port)
	address = str(ap[0])
	port = int(ap[1])
	_last_address = address
	if address == "":
		return "Bitte eine IP-Adresse eingeben."
	var cert := X509Certificate.new()
	if host_cert == "" or cert.load_from_string(_pem(host_cert)) != OK:
		return "Ungültiger Einladungs-Code (Zertifikat fehlt)."
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 0, 0, 0, local_port)
	if err != OK:
		peer = null
		return Game.t("Verbindung zu %s:%d konnte nicht aufgebaut werden.") % [address, port]
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


## Host: finds the address the other players can reach (only when the player presses the button):
## IPv6 first (many connections have only IPv6, or IPv4 just behind the provider's shared NAT), then
## a public IPv4. For IPv6 the PC's stable address is preferred over the temporary privacy address
## the lookup sees – the router's port opening (e.g. FritzBox) applies to the stable one.
func lookup_public_ip() -> void:
	_lookup("https://api6.ipify.org", func(ip: String) -> bool:
		if not ip.contains(":"):
			return false
		public_ip = preferred_ipv6(ip)
		return true, func():
			_lookup("https://api.ipify.org", func(ip4: String) -> bool:
				if not is_public_ipv4(ip4):
					return false
				public_ip = ip4
				return true, func():
					# no service reachable: maybe still a global IPv6 on this PC
					var own := global_ipv6_addresses()
					if not own.is_empty():
						public_ip = own[0]
					else:
						upnp_message = "Öffentliche IP konnte nicht ermittelt werden."
					lobby_changed.emit()))


func _lookup(url: String, accept: Callable, on_fail: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address() and bool(accept.call(ip)):
			lobby_changed.emit()
		else:
			on_fail.call())
	if req.request(url) != OK:
		req.queue_free()
		on_fail.call()


## Global IPv6 addresses of this PC (no link-local fe80::, no private fc00::/7).
func global_ipv6_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := str(a).split("%")[0]
		if not s.contains(":"):
			continue
		var first := s.split(":")[0].to_lower()
		if first.length() == 4 and (first.begins_with("2") or first.begins_with("3")):
			out.append(s)
	return out


## For the address the lookup saw (often Windows' temporary privacy address): another global address
## of this PC in the same /64 network – the stable one the router's port opening is made for.
func preferred_ipv6(seen: String) -> String:
	var prefix := _prefix64(seen)
	for a in global_ipv6_addresses():
		if a != seen and _prefix64(a) == prefix:
			return a
	return seen


## The first four groups (the /64 network) of an IPv6 address, "::" shorthand expanded.
static func _prefix64(ip: String) -> String:
	var groups := expand_ipv6(ip)
	return ":".join(groups.slice(0, 4))


static func expand_ipv6(ip: String) -> PackedStringArray:
	var s := ip.split("%")[0].to_lower()
	var head := s
	var tail := ""
	if s.contains("::"):
		var ht := s.split("::", true, 1)
		head = ht[0]
		tail = ht[1]
	var hg: PackedStringArray = head.split(":", false) if head != "" else PackedStringArray()
	var tg: PackedStringArray = tail.split(":", false) if tail != "" else PackedStringArray()
	var out := PackedStringArray()
	for g in hg:
		out.append(g.lpad(4, "0"))
	for k in 8 - hg.size() - tg.size():
		out.append("0000")
	for g in tg:
		out.append(g.lpad(4, "0"))
	return out


## True for an IPv4 others can reach (not private, not the provider's shared NAT range 100.64/10).
static func is_public_ipv4(ip: String) -> bool:
	if not ip.is_valid_ip_address() or ip.contains(":"):
		return false
	var o := ip.split(".")
	var a := int(o[0])
	var b := int(o[1])
	if a == 10 or a == 127 or a == 0 or a >= 224:
		return false
	if a == 172 and b >= 16 and b <= 31:
		return false
	if a == 192 and b == 168:
		return false
	if a == 169 and b == 254:
		return false
	if a == 100 and b >= 64 and b <= 127:
		return false
	return true


## Address and port from what a player typed: "1.2.3.4", "1.2.3.4:7777", "2001:db8::1",
## "[2001:db8::1]:7777" (IPv6 in brackets when a port follows).
static func split_address(text: String, port: int) -> Array:
	var t := text.strip_edges()
	if t.begins_with("["):
		var close := t.find("]")
		if close > 0:
			var rest := t.substr(close + 1)
			if rest.begins_with(":") and rest.substr(1).is_valid_int():
				port = int(rest.substr(1))
			return [t.substr(1, close - 1), port]
	if t.count(":") == 1:
		var hp := t.split(":")
		if hp[1].is_valid_int():
			return [hp[0], int(hp[1])]
	return [t, port]


## What the public server list shows (no address – joining goes through the short code).
func _heartbeat() -> Dictionary:
	if not is_host() or host_code == "":
		return {}
	return {"game": GAME_TAG, "v": Game.VERSION, "name": lobby.get("name", "Server"), "code": host_code,
		"players": players.size(), "max": lobby.get("max_players", 8), "track": lobby.get("track", "ridge"),
		"mode": lobby.get("mode", "race"), "locked": password != "", "dedicated": dedicated, "in_race": in_race, "motd": motd}


func leave() -> void:
	if server_list:
		server_list.stop_announce()
	dedicated = false
	_stop_rendezvous()
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


# ---------------------------------------------------------------------------
# Short code (rendezvous + hole punching, see rendezvous.gd)
# ---------------------------------------------------------------------------
func _start_rendezvous(c: String) -> void:
	_rv = Rendezvous.new()
	_rv.name = "Rendezvous"
	add_child(_rv)
	_rv.received.connect(_on_rv_message)
	_rv.opened.connect(_on_rv_opened)
	_rv.start(c)
	if is_host():
		host_code = c


func _stop_rendezvous() -> void:
	if _rv:
		_rv.stop()
		_rv.queue_free()
	_rv = null
	host_code = ""
	_rv_state = ""
	_rv_queue.clear()
	if _rv_udp:
		_rv_udp.close()
	_rv_udp = null


## Joins the lobby with this short code: asks STUN, meets the host on the relay, punches, connects.
func join_code(text: String, lobby_password := "") -> String:
	var c := Rendezvous.normalize(text)
	if c == "":
		return "Ungültiger Code."
	leave()
	_rv_udp = PacketPeerUDP.new()
	_rv_local_port = 0
	for k in 8:
		var lp := randi_range(30000, 60000)
		if _rv_udp.bind(lp, "*") == OK:
			_rv_local_port = lp
			break
	if _rv_local_port == 0:
		return "Kein freier Netzwerk-Port gefunden."
	join_status.emit("Suche Host …")
	var seen := Rendezvous.stun(_rv_udp)
	_rv_my_cands = Rendezvous.candidates(seen, _rv_local_port, global_ipv6_addresses(), get_local_addresses())
	_rv_join_id = _crypto.generate_random_bytes(8).hex_encode()
	_rv_pw = lobby_password.strip_edges()
	_rv_state = "wait"
	_rv_seen_welcome = false
	_rv_deadline = Time.get_ticks_msec() + 25000
	_rv_resend = 0.0
	_start_rendezvous(c)
	return ""


func _on_rv_opened() -> void:
	_rv_resend = 0.0


func _send_join() -> void:
	if _rv and _rv.is_open:
		_rv.send({"t": "join", "id": _rv_join_id, "c": _rv_my_cands})


func _on_rv_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"join":
			if not is_host() or peer == null:
				return
			var cands := _clean_cands(msg.get("c", []))
			_rv.send({"t": "welcome", "to": str(msg.get("id", "")), "c": _host_cands, "cert": cert_body,
				"locked": password != "", "name": str(lobby.get("name", "Lobby"))})
			_host_punch(cands)
		"welcome":
			if _rv_state != "wait" or str(msg.get("to", "")) != _rv_join_id or _rv_seen_welcome:
				return
			_rv_seen_welcome = true
			if bool(msg.get("locked", false)) and _rv_pw == "":
				_fail_join("Die Lobby hat ein Passwort – bitte im Feld „Passwort“ eintragen.")
				return
			_rv_cert = str(msg.get("cert", ""))
			join_status.emit("Host gefunden – verbinde …")
			_client_punch(_clean_cands(msg.get("c", [])))


static func _clean_cands(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for c in raw:
		if c is Array and c.size() == 2 and str(c[0]).is_valid_ip_address() and int(c[1]) > 0 and int(c[1]) < 65536:
			out.append([str(c[0]), int(c[1])])
		if out.size() >= 12:
			break
	return out


## Host: packets from the game port to every address of the joiner – opens the NAT / firewall for it.
func _host_punch(cands: Array) -> void:
	for k in 12:
		if peer == null or not is_host():
			return
		for c in cands:
			peer.host.socket_send(str(c[0]), int(c[1]), "mdpunch".to_utf8_buffer())
		await get_tree().create_timer(0.15).timeout


## Joiner: packets to every address of the host (same port the game will use); the address a host
## packet arrives from is tried first.
func _client_punch(cands: Array) -> void:
	_rv_state = "punch"
	var answered: Array = []
	var t_end := Time.get_ticks_msec() + 1800
	while Time.get_ticks_msec() < t_end and _rv_udp:
		for c in cands:
			_rv_udp.set_dest_address(str(c[0]), int(c[1]))
			_rv_udp.put_packet("mdpunch".to_utf8_buffer())
		await get_tree().create_timer(0.1).timeout
		while _rv_udp and _rv_udp.get_available_packet_count() > 0:
			_rv_udp.get_packet()
			var from := [_rv_udp.get_packet_ip(), _rv_udp.get_packet_port()]
			if not answered.has(from):
				answered.append(from)
	if _rv_udp == null:
		return
	_rv_udp.close()
	_rv_udp = null
	var order: Array = []
	for a in answered:
		for c in cands:
			if str(c[0]) == str(a[0]) and not order.has(c):
				order.append(c)
	for c in cands:
		if not order.has(c):
			order.append(c)
	_rv_queue = order
	_rv_state = "connect"
	_try_next_candidate()


func _try_next_candidate() -> void:
	if _rv_queue.is_empty():
		_fail_join("Keine Verbindung zum Host möglich. Beide Router blockieren direkte Verbindungen – der Host kann es mit einer Portfreigabe versuchen.")
		return
	var c: Array = _rv_queue.pop_front()
	var rest := _rv_queue.duplicate()
	var cert := _rv_cert
	var pw := _rv_pw
	var lp := _rv_local_port
	# join_lobby() resets the session state: keep what the next attempt needs
	var err := join_lobby(str(c[0]), int(c[1]), pw, cert, lp)
	_rv_queue = rest
	_rv_cert = cert
	_rv_pw = pw
	_rv_local_port = lp
	if err != "":
		_try_next_candidate()
		return
	# fail over quickly to the next address
	var sp := peer.get_peer(1) if peer else null
	if sp:
		sp.set_timeout(8, 2500, 4500)


func _fail_join(text: String) -> void:
	_stop_rendezvous()
	connection_failed.emit(text)


func _process_rendezvous(delta: float) -> void:
	if _rv_state == "wait":
		if Time.get_ticks_msec() > _rv_deadline:
			_fail_join("Kein Host mit diesem Code gefunden (oder keine Internetverbindung).")
			return
		_rv_resend -= delta
		if _rv_resend <= 0.0 and _rv and _rv.is_open:
			_rv_resend = 3.0
			_send_join()


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
## Connection timeout once a peer is in: generous, because loading a map (terrain, shader compile)
## can block the game for several seconds on a slow machine (ENet: limit, min ms, max ms).
const PLAY_TIMEOUT := [32, 30000, 60000]


func _on_peer_connected(id: int) -> void:
	_relax_timeout(id)


func _relax_timeout(id: int) -> void:
	var ep := peer as ENetMultiplayerPeer
	if ep == null:
		return
	var p := ep.get_peer(id)
	if p:
		p.set_timeout(PLAY_TIMEOUT[0], PLAY_TIMEOUT[1], PLAY_TIMEOUT[2])


## Keeps the connection alive during long loading steps (called from Game.load_tick): services ENet
## so pings are answered even while the world is built and no frame is drawn.
func keepalive() -> void:
	if peer == null or Time.get_ticks_msec() - _keepalive_last < 100:
		return
	_keepalive_last = Time.get_ticks_msec()
	peer.poll()


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var who: String = players[id].get("name", "Spieler")
		players.erase(id)
		chat_received.emit("Lobby", Game.t("%s hat die Lobby verlassen.") % who)
	peer_left.emit(id)
	if is_host():
		_loaded.erase(id)
		_broadcast_lobby()
		_check_all_loaded()
	lobby_changed.emit()


func _on_connected_to_server() -> void:
	_rv_queue.clear()
	# the short fail-over timeout of the join attempt must not stay: it dropped players while loading
	_relax_timeout(1)
	_register.rpc_id(1, Game.local_player_info())
	connected_ok.emit()


func _on_connection_failed() -> void:
	if not _rv_queue.is_empty():
		_try_next_candidate()
		return
	leave()
	var msg := "Verbindung fehlgeschlagen – Host nicht erreichbar (IP/Port/Firewall prüfen)."
	if _last_address.contains(":"):
		msg = "Keine Verbindung zur IPv6-Adresse des Hosts. Hat dein Internet IPv6? Beim Host: IPv6-Portfreigabe (UDP) im Router für die feste IPv6 des PCs und Windows-Firewall prüfen."
	connection_failed.emit(msg)


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
		_kicked.rpc_id(id, Game.t("Versionskonflikt: Host hat %s, du hast %s.") % [Game.VERSION, info.get("version", "?")])
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
	_chat_all("Lobby", Game.t("%s ist beigetreten.") % info["name"])


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
# Action codes: checked by the server (its codes never leave it), the reward comes back
# ---------------------------------------------------------------------------
func request_code(code: String) -> void:
	if is_online and not is_host():
		_request_code.rpc_id(1, code)


@rpc("any_peer", "call_remote", "reliable")
func _request_code(code: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	code = code.strip_edges().to_upper().replace(" ", "").substr(0, 32)
	var codes: Dictionary = server_codes if dedicated else Game.settings.get("admin_codes", {})
	if not codes.has(code):
		_code_reply.rpc_id(id, false, "Unbekannter Code", {})
		return
	var who := str(players.get(id, {}).get("name", "?"))
	var used: Array = _redeemed.get(code, [])
	if used.has(who):
		_code_reply.rpc_id(id, false, "Code wurde schon eingelöst", {})
		return
	used.append(who)
	_redeemed[code] = used
	_code_reply.rpc_id(id, true, "", codes[code])


@rpc("authority", "call_remote", "reliable")
func _code_reply(ok: bool, text: String, reward: Dictionary) -> void:
	if ok:
		var r: Array = Game.apply_code_reward("", reward)
		code_result.emit(true, str(r[1]))
	else:
		code_result.emit(false, text)


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
		"layout": str(lobby.get("layout", "normal")),
		"laps": int(lobby.get("laps", 3)),
		"graffiti_minutes": int(lobby.get("graffiti_minutes", 5)),
		"party": bool(lobby.get("party", false)),
		"party_games": clampi(int(lobby.get("party_games", 3)), 1, 20),
		"party_coins": clampi(int(lobby.get("party_coins", 5)), 1, 20),
		"party_coins_city": bool(lobby.get("party_coins_city", false)),
		"mode": lobby.get("mode", "race"),
		"time_of_day": lobby.get("time_of_day", "dusk"),
		"weather": lobby.get("weather", "dry"),
		"day_cycle": int(lobby.get("day_cycle", 0)),
		"weather_seed": randi() % 100000,
		"collisions": bool(lobby.get("collisions", true)),
		"online": true,
		"players": players.duplicate(true),
	}
	# AI opponents (races only): the same roster for everybody, the host drives them
	if str(config["mode"]) == "race" and int(lobby.get("bots", 0)) > 0:
		config["bots"] = RaceAI.make_roster(clampi(int(lobby.get("bots", 0)), 0, 7), int(config["weather_seed"]), RaceAI.player_tuning())
		config["bot_level"] = clampi(int(lobby.get("bot_level", 1)), 0, 3)
	_start_race.rpc(config)
	return ""


@rpc("authority", "call_local", "reliable")
func _start_race(config: Dictionary) -> void:
	in_race = true
	results.clear()
	result_list.clear()
	_loaded.clear()
	countdown_t0 = -1
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
	# remembered: a world still loading picks it up when it is ready (and catches up)
	countdown_t0 = Time.get_ticks_msec()
	countdown_requested.emit()


## Host: the state of an AI opponent, to everybody (they see it like a remote player).
func send_bot_state(id: int, state: Array) -> void:
	if is_online and is_host() and multiplayer.multiplayer_peer != null:
		_bot_state.rpc(id, state)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _bot_state(id: int, state: Array) -> void:
	if id >= 1000:
		remote_state.emit(id, state)


## Host: an AI opponent crossed the finish line.
func report_bot_result(id: int, result: Dictionary) -> void:
	if is_online and is_host():
		_store_result(id, result)


func send_state(state: Array) -> void:
	if is_online and multiplayer.multiplayer_peer != null:
		_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _state(state: Array) -> void:
	remote_state.emit(multiplayer.get_remote_sender_id(), state)


## Voice chat: a piece of the local player's voice (μ-law, 16 kHz) to one player close by.
func send_voice(peer_id: int, data: PackedByteArray) -> void:
	if is_online and multiplayer.multiplayer_peer != null:
		_voice.rpc_id(peer_id, data)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice(data: PackedByteArray) -> void:
	if data.size() > 4096:
		return
	voice_received.emit(multiplayer.get_remote_sender_id(), data)


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


## Party mode: requests to the host (coin claims, minigame results) and the host's decisions for
## everybody (minigame start, final ranking). The host is the referee.
func party_to_host(msg: Dictionary) -> void:
	if not is_online:
		return
	if is_host():
		party_msg.emit(1, msg)
	else:
		_party_up.rpc_id(1, msg)


func party_broadcast(msg: Dictionary) -> void:
	if not is_host():
		return
	_party_down.rpc(msg)
	party_msg.emit(1, msg)


@rpc("any_peer", "call_remote", "reliable")
func _party_up(msg: Dictionary) -> void:
	if not is_host() or msg.size() > 8:
		return
	var t := str(msg.get("t", ""))
	if t != "claim" and t != "res" and t != "pick":
		return
	party_msg.emit(multiplayer.get_remote_sender_id(), msg)


@rpc("authority", "call_remote", "reliable")
func _party_down(msg: Dictionary) -> void:
	party_msg.emit(1, msg)


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
	elif id < 1000:
		return
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
	_process_rendezvous(delta)
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
			msg = Game.t("UPnP aktiv – Port %d offen.") % port
		else:
			msg = Game.t("UPnP: Portfreigabe fehlgeschlagen (Code %d). Port %d/UDP ggf. manuell freigeben.") % [r, port]
	else:
		msg = Game.t("Kein UPnP-Router gefunden – für Internet-Spiele Port %d/UDP im Router freigeben.") % port
	call_deferred("_upnp_done", ok, msg, upnp if ok else null, port)


func _upnp_done(ok: bool, msg: String, upnp: UPNP, port: int) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	if ok and is_host():
		_upnp = upnp
		_upnp_port = port
		var ext := upnp.query_external_address()
		# behind DS-Lite / carrier NAT the router only has a shared, unreachable IPv4 – not for the code
		if is_public_ipv4(ext) and not public_ip.contains(":"):
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
