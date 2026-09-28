extends Node
## Underglow: switching the flasher off again must leave every tube steadily lit; the flash key
## strobes the tubes even without flashers installed.
## Run: godot --headless --path . res://tests/underglow_test.tscn

const Underglow = preload("res://scripts/car/underglow.gd")
const FULL: float = Underglow.TUBE_E * Underglow.SCALE   # tube energy of a steadily lit side at 1x
const DIMS := {"track": 0.78, "axle_f": -1.35, "axle_r": 1.35, "base": 0.15}


func _cfg(mode: int, flash: bool) -> Dictionary:
	var sides := {}
	for s in Underglow.SIDES:
		sides[s] = {"on": true, "color": "#33aaff", "flash": flash}
	return {"on": true, "mode": mode, "speed": 1.0, "sides": sides}


func _energies(ug) -> Array:
	var out := []
	for f in 40:
		ug._process(1.0 / 60.0)
		for s in ug._strips:
			out.append((s["mat"] as StandardMaterial3D).emission_energy_multiplier)
	return out


func _ready() -> void:
	var ug = Underglow.new()
	add_child(ug)
	var fails := 0
	ug.setup(_cfg(2, true), DIMS, true)
	var e: Array = _energies(ug)
	if e.min() > FULL * 0.3:
		print("FAIL: blink mode does not blink"); fails += 1
	# flasher off again: mode back to steady, and separately the side flag off
	for c in [_cfg(0, true), _cfg(3, false)]:
		ug.setup(c, DIMS, true)
		e = _energies(ug)
		if e.min() < FULL * 0.97:
			print("FAIL: still flashing after switching the flasher off (%s)" % str(c["mode"])); fails += 1
	if ug.get_child_count() != 4 * 2 + 6 + 4:   # 4 tubes, 4 ground decals, 1+1+2+2 lights, 4 corner glows
		print("FAIL: %d nodes left over after rebuilding" % ug.get_child_count()); fails += 1
	# manual flash without flashers
	ug.setup(_cfg(0, false), DIMS, true)
	ug.manual = true
	e = _energies(ug)
	if e.min() > FULL * 0.3 or e.max() < FULL * 0.97:
		print("FAIL: flash key does not strobe"); fails += 1
	ug.manual = false
	e = _energies(ug)
	if e.min() < FULL * 0.97:
		print("FAIL: still strobing after releasing the flash key"); fails += 1
	# brightness per side: front dimmed, right boosted
	var c2 := _cfg(0, false)
	c2["sides"]["front"]["bright"] = 0.3
	c2["sides"]["right"]["bright"] = 1.8
	ug.setup(c2, DIMS, true)
	ug._process(1.0 / 60.0)
	var by_side := {}
	for st in ug._strips:
		by_side[st["side"]] = [(st["mat"] as StandardMaterial3D).emission_energy_multiplier, (st["decal"] as Decal).emission_energy]
	# quadratic: 0.3 -> 0.09x, 1.8 -> 3.24x of the base (steady, 1x)
	if absf(by_side[0][0] - FULL * 0.09) > 0.005 or absf(by_side[3][0] - FULL * 3.24) > 0.005 or absf(by_side[1][0] - FULL) > 0.005 or by_side[0][1] >= by_side[1][1]:
		print("FAIL: per-side brightness not applied: %s" % str(by_side)); fails += 1
	# corners only where both neighbouring sides are lit
	var c3 := _cfg(0, false)
	c3["sides"]["left"]["on"] = false
	ug.setup(c3, DIMS, true)
	if ug._corners.size() != 2:
		print("FAIL: %d corner glows with the left side off (expected 2)" % ug._corners.size()); fails += 1
	ug._process(1.0 / 60.0)
	for c in ug._corners:
		if (c["decal"] as Decal).emission_energy >= Underglow.DECAL_E * Underglow.SCALE:
			print("FAIL: corner glow not dimmer than the sides"); fails += 1
	print("UNDERGLOW TEST %s" % ("OK" if fails == 0 else "FAILED"))
	get_tree().quit(1 if fails else 0)
