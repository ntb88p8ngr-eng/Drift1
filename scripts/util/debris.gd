extends RefCounted
## Loose pieces knocked off by a car (snapped lamp posts, hydrant tops, people's blocks): one-way –
## cars knock them about, they never push a car (their own layer, which no car scans; a body only
## takes a collision response from the layers in its own mask) – and never faster than a car could
## have thrown them (a post that spawned inside its still solid foot, or got wedged between a car
## and the ground, was shot off at hundreds of m/s and took the car with it).

const LAYER := 16
const MASK := 1 | 2 | 4 | 8 | 16
const MAX_V := 26.0
const MAX_W := 12.0


static func make(b: RigidBody3D) -> void:
	b.collision_layer = LAYER
	b.collision_mask = MASK
	b.linear_damp = 0.05
	b.angular_damp = 0.4


## Caps the speed of every body in `list` (drops the freed ones). Call from _physics_process.
static func calm(list: Array) -> void:
	for k in range(list.size() - 1, -1, -1):
		var b = list[k]
		if not is_instance_valid(b):
			list.remove_at(k)
			continue
		var rb := b as RigidBody3D
		var v := rb.linear_velocity
		if v.length_squared() > MAX_V * MAX_V:
			rb.linear_velocity = v.normalized() * MAX_V
		var w := rb.angular_velocity
		if w.length_squared() > MAX_W * MAX_W:
			rb.angular_velocity = w.normalized() * MAX_W
