extends Node
## Offroad lift (party parkour): set_lift(m) must raise the body by m on the same wheels, and
## set_lift(0) bring it back down. Run: godot --headless --path . res://tests/lift_test.tscn
const Car = preload("res://scripts/car/car.gd")
func _ready() -> void:
	Game.persist = false
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	var car := Car.new()
	car.car_id = "r34"
	car.paint = Game.get_paint("red")
	car.input_enabled = false
	car.ai_fn = func() -> Array: return [0.0, 0.0, 0.0, true]
	add_child(car)
	car.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)))
	for f in 240:
		await get_tree().physics_frame
	var y0 := car.global_position.y
	var wp0: float = car.wheels[0]["pivot"].global_position.y
	car.set_lift(0.32)
	for f in 240:
		await get_tree().physics_frame
	var y1 := car.global_position.y
	var wp1: float = car.wheels[0]["pivot"].global_position.y
	car.set_lift(0.0)
	for f in 240:
		await get_tree().physics_frame
	var y2 := car.global_position.y
	print("LIFT origin %.3f -> %.3f -> %.3f   wheel centre %.3f -> %.3f" % [y0, y1, y2, wp0, wp1])
	var ok := absf(y1 - y0 - 0.32) < 0.03 and absf(wp1 - wp0) < 0.03 and absf(y2 - y0) < 0.03
	print("LIFT TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
