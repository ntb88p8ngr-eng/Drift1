extends Node
## Short-code rendezvous for internet play without port forwarding.
## Host and joiner meet on a public message relay (ntfy.sh) under a topic derived from a short code
## like "K7Q-M2X". Everything they post there is encrypted and authenticated with a key derived from
## the same code, so the relay (and anyone reading the topic) sees neither addresses nor names.
## They swap the addresses a STUN server saw them from (IPv6 and IPv4) and then send each other UDP
## packets at the same time: that opens the path through NATs and router firewalls (hole punching) –
## no port forwarding, no UPnP. The game itself then runs directly and DTLS-encrypted as before.
## MD_SIGNAL=file (tests): the relay is a folder in user:// instead of ntfy.sh.

signal received(msg: Dictionary)
signal opened          # the relay is ready (messages sent from now on reach the other side)

const ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"   # no 0/O, 1/I/L – easy to read out and type
const CODE_LEN := 6
const RELAY_HOST := "ntfy.sh"
const STUN_SERVERS := [["stun.l.google.com", 19302], ["stun1.l.google.com", 19302], ["stun.cloudflare.com", 3478]]
const STUN_COOKIE := 0x2112A442
const MAX_AGE_MS := 120000   # older relayed messages are ignored (no replays)

var code := ""
var is_open := false
var _topic := ""
var _key := PackedByteArray()
var _mac_key := PackedByteArray()
var _crypto := Crypto.new()
var _file_mode := false
var _file_dir := ""
var _file_seen := {}
var _poll_t := 0.0
var _ws: WebSocketPeer
var _retry_t := 0.0


# ---------------------------------------------------------------------------
# Codes
# ---------------------------------------------------------------------------
static func make_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(CODE_LEN)
	var out := ""
	for b in bytes:
		out += ALPHABET[int(b) % ALPHABET.length()]
	return out


## "k7q m2x" / "K7Q-M2X" -> "K7QM2X"; "" when it isn't a short code.
static func normalize(text: String) -> String:
	var t := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if t.length() != CODE_LEN:
		return ""
	for ch in t:
		if not ALPHABET.contains(ch):
			return ""
	return t


static func pretty(c: String) -> String:
	return c.substr(0, 3) + "-" + c.substr(3) if c.length() == CODE_LEN else c


# ---------------------------------------------------------------------------
# Relay
# ---------------------------------------------------------------------------
func start(p_code: String) -> void:
	code = p_code
	_topic = "mdrift-" + ("md1|topic|" + code).sha256_text().substr(0, 32)
	_key = ("md1|key|" + code).sha256_buffer()
	_mac_key = ("md1|mac|" + code).sha256_buffer()
	_file_mode = OS.get_environment("MD_SIGNAL") == "file"
	if _file_mode:
		_file_dir = OS.get_user_data_dir().path_join("md_signal").path_join(_topic)
		DirAccess.make_dir_recursive_absolute(_file_dir)
		for f in DirAccess.get_files_at(_file_dir):
			_file_seen[f] = true
		is_open = true
		opened.emit.call_deferred()
	else:
		_connect_ws()


func stop() -> void:
	if _ws:
		_ws.close()
	_ws = null
	is_open = false
	code = ""


func _connect_ws() -> void:
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url("wss://%s/%s/ws" % [RELAY_HOST, _topic]) != OK:
		_ws = null
		_retry_t = 3.0


func send(msg: Dictionary) -> void:
	if code == "":
		return
	msg["ts"] = Time.get_unix_time_from_system()
	var text := _seal(msg)
	if _file_mode:
		var f := FileAccess.open(_file_dir.path_join("%d_%d.msg" % [Time.get_ticks_usec(), randi()]), FileAccess.WRITE)
		if f:
			f.store_string(text)
			f.close()
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free())
	if req.request("https://%s/%s" % [RELAY_HOST, _topic], PackedStringArray(["Content-Type: text/plain"]), HTTPClient.METHOD_POST, text) != OK:
		req.queue_free()


func _process(delta: float) -> void:
	if code == "":
		return
	if _file_mode:
		_poll_t -= delta
		if _poll_t > 0.0:
			return
		_poll_t = 0.1
		var files := DirAccess.get_files_at(_file_dir)
		files.sort()
		for f in files:
			if _file_seen.has(f):
				continue
			_file_seen[f] = true
			_deliver(FileAccess.get_file_as_string(_file_dir.path_join(f)))
		return
	if _ws == null:
		_retry_t -= delta
		if _retry_t <= 0.0:
			_connect_ws()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not is_open:
				is_open = true
				opened.emit()
			while _ws.get_available_packet_count() > 0:
				var parsed = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if parsed is Dictionary and str(parsed.get("event", "")) == "message":
					_deliver(str(parsed.get("message", "")))
		WebSocketPeer.STATE_CLOSED:
			is_open = false
			_ws = null
			_retry_t = 2.0


func _deliver(text: String) -> void:
	var msg := _open(text)
	if msg.is_empty():
		return
	if absf(Time.get_unix_time_from_system() - float(msg.get("ts", 0.0))) * 1000.0 > MAX_AGE_MS:
		return
	received.emit(msg)


## JSON -> AES-256-CBC (random IV) -> HMAC-SHA256 over IV + ciphertext -> base64.
func _seal(msg: Dictionary) -> String:
	var plain := JSON.stringify(msg).to_utf8_buffer()
	var pad := 16 - plain.size() % 16
	for i in pad:
		plain.append(pad)
	var iv := _crypto.generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _key, iv)
	var ct := aes.update(plain)
	aes.finish()
	var body := iv.duplicate()
	body.append_array(ct)
	var out := _crypto.hmac_digest(HashingContext.HASH_SHA256, _mac_key, body)
	out.append_array(body)
	return Marshalls.raw_to_base64(out)


func _open(text: String) -> Dictionary:
	var raw := Marshalls.base64_to_raw(text.strip_edges())
	if raw.size() < 32 + 16 + 16 or (raw.size() - 48) % 16 != 0:
		return {}
	var mac := raw.slice(0, 32)
	var body := raw.slice(32)
	if _crypto.hmac_digest(HashingContext.HASH_SHA256, _mac_key, body) != mac:
		return {}
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, _key, body.slice(0, 16))
	var plain := aes.update(body.slice(16))
	aes.finish()
	var pad := int(plain[plain.size() - 1])
	if pad < 1 or pad > 16:
		return {}
	var parsed = JSON.parse_string(plain.slice(0, plain.size() - pad).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# STUN + candidates
# ---------------------------------------------------------------------------
## Asks the STUN servers (over IPv4 and IPv6) which public address+port they see `udp` from.
## Blocks for up to `timeout_ms`. Returns [[ip, port], ...] without duplicates.
static func stun(udp: PacketPeerUDP, timeout_ms := 900) -> Array:
	var out: Array = []
	var txids := {}
	var sent := 0
	for srv in STUN_SERVERS:
		var addrs := IP.resolve_hostname_addresses(str(srv[0]), IP.TYPE_ANY)
		var have4 := false
		var have6 := false
		for a in addrs:
			var v6 := str(a).contains(":")
			if (v6 and have6) or (not v6 and have4):
				continue
			var tx := Crypto.new().generate_random_bytes(12)
			var req := PackedByteArray([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])
			req.append_array(tx)
			udp.set_dest_address(str(a), int(srv[1]))
			if udp.put_packet(req) == OK:
				txids[tx.hex_encode()] = tx
				sent += 1
			if v6:
				have6 = true
			else:
				have4 = true
	if sent == 0:
		return out
	var t_end := Time.get_ticks_msec() + timeout_ms
	var answers := 0
	while Time.get_ticks_msec() < t_end and answers < sent:
		while udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet()
			var r := parse_stun(pkt, txids)
			if not r.is_empty():
				answers += 1
				if not out.has(r):
					out.append(r)
		OS.delay_msec(15)
	return out


## Binding success response -> [ip, port] (XOR-MAPPED-ADDRESS, or MAPPED-ADDRESS), [] otherwise.
static func parse_stun(pkt: PackedByteArray, txids: Dictionary) -> Array:
	if pkt.size() < 20 or pkt[0] != 0x01 or pkt[1] != 0x01:
		return []
	if pkt[4] != 0x21 or pkt[5] != 0x12 or pkt[6] != 0xA4 or pkt[7] != 0x42:
		return []
	var tx := pkt.slice(8, 20)
	if not txids.is_empty() and not txids.has(tx.hex_encode()):
		return []
	var i := 20
	var mapped: Array = []
	while i + 4 <= pkt.size():
		var at := (pkt[i] << 8) | pkt[i + 1]
		var ln := (pkt[i + 2] << 8) | pkt[i + 3]
		var v := pkt.slice(i + 4, i + 4 + ln)
		if (at == 0x0020 or at == 0x0001) and v.size() >= 8:
			var xor := at == 0x0020
			var fam := v[1]
			var port := (v[2] << 8) | v[3]
			var mask := PackedByteArray([0x21, 0x12, 0xA4, 0x42])
			mask.append_array(tx)
			if xor:
				port ^= 0x2112
			if fam == 0x01:
				var ip := PackedStringArray()
				for k in 4:
					ip.append(str(v[4 + k] ^ (mask[k] if xor else 0)))
				mapped = [".".join(ip), port]
			elif fam == 0x02 and v.size() >= 20:
				var groups := PackedStringArray()
				for k in 8:
					var hi: int = v[4 + k * 2] ^ (mask[k * 2] if xor else 0)
					var lo: int = v[5 + k * 2] ^ (mask[k * 2 + 1] if xor else 0)
					groups.append("%x" % ((hi << 8) | lo))
				mapped = [":".join(groups), port]
			if xor and not mapped.is_empty():
				return mapped
		i += 4 + ((ln + 3) & ~3)
	return mapped


## Where the others can try to reach a socket on `port`: what STUN saw (the router's public side),
## this PC's global IPv6 addresses and its LAN IPv4 addresses (same network). IPv6 first.
static func candidates(stun_seen: Array, port: int, v6_addrs: Array, lan_v4: Array) -> Array:
	var out: Array = []
	for s in stun_seen:
		if str(s[0]).contains(":"):
			out.append([str(s[0]), int(s[1])])
	for a in v6_addrs:
		var c := [str(a), port]
		if not out.has(c):
			out.append(c)
	for s in stun_seen:
		if not str(s[0]).contains(":"):
			out.append([str(s[0]), int(s[1])])
	for a in lan_v4:
		var c2 := [str(a), port]
		if not out.has(c2):
			out.append(c2)
	if OS.get_environment("MD_SIGNAL") == "file":
		out.append(["127.0.0.1", port])   # tests on one machine
	return out.slice(0, 12)
