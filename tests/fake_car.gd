extends Node
## Minimal stand-in for car.gd so car_audio.gd can be rendered offline (tests/audio_test.gd).

signal shifted(up: bool, boost: float)
signal blow_off(amount: float)
signal wall_hit(strength: float)
signal backfire(strength: float)

var car_id := "r34"
var burble := 1
var redline := 8000.0
var idle_rpm := 900.0
var rpm := 900.0
var throttle := 0.0
var boost := 0.0
var total_slip := 0.0
var speed := 0.0
var line_lock := false
var controls_locked := false
var nitro_active := false
var turbo_gain := 0.45
var surface_name := "asphalt"
