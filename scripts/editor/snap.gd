extends RefCounted
## World-editor snapping: a moved or placed object docks onto the objects around it – side by side
## (faces touching, edges lined up) or stacked on top – and/or onto a 1 m grid.

const DIST := 0.8          # how close (m) an edge has to come to catch
const REACH := 40.0        # objects further away than this are not looked at


## The world bounds of everything a node draws (empty AABB if nothing).
static func node_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var nodes: Array = [n]
	nodes.append_array(n.find_children("*", "VisualInstance3D", true, false))
	for c in nodes:
		if not (c is VisualInstance3D) or not (c as VisualInstance3D).is_visible_in_tree():
			continue
		var vi := c as VisualInstance3D
		var b: AABB = vi.global_transform * vi.get_aabb()
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


## How far to shift `moving` (already at its new place) so it docks onto one of `targets`:
## [x/z shift, height of the top it stands on or NAN]. Faces closer than DIST touch; with a side
## touching, the edges along it line up too when they are close.
static func dock(moving: AABB, targets: Array) -> Array:
	var best_x := DIST
	var best_z := DIST
	var dx := 0.0
	var dz := 0.0
	for t: AABB in targets:
		# side by side along x: the z ranges must meet
		if _overlap(moving.position.z, moving.end.z, t.position.z, t.end.z) > -DIST:
			for c in [t.position.x - moving.end.x, t.end.x - moving.position.x]:
				if absf(c) < best_x:
					best_x = absf(c)
					dx = c
		if _overlap(moving.position.x, moving.end.x, t.position.x, t.end.x) > -DIST:
			for c in [t.position.z - moving.end.z, t.end.z - moving.position.z]:
				if absf(c) < best_z:
					best_z = absf(c)
					dz = c
	# edges in line (front with front …) with the object it touches
	var docked := moving
	docked.position += Vector3(dx, 0, dz)
	var ax := DIST * 0.6
	var az := DIST * 0.6
	var lx := 0.0
	var lz := 0.0
	for t: AABB in targets:
		if dx != 0.0 and _overlap(docked.position.x, docked.end.x, t.position.x, t.end.x) > -0.05:
			for c in [t.position.z - docked.position.z, t.end.z - docked.end.z]:
				if absf(c) < az:
					az = absf(c)
					lz = c
		if dz != 0.0 and _overlap(docked.position.z, docked.end.z, t.position.z, t.end.z) > -0.05:
			for c in [t.position.x - docked.position.x, t.end.x - docked.end.x]:
				if absf(c) < ax:
					ax = absf(c)
					lx = c
	var shift := Vector3(dx + (lx if dx == 0.0 else 0.0), 0, dz + (lz if dz == 0.0 else 0.0))
	# stacked: the middle of the footprint over another object – it stands on that one's top
	var mid := moving.get_center() + shift
	var top := NAN
	for t: AABB in targets:
		if mid.x > t.position.x and mid.x < t.end.x and mid.z > t.position.z and mid.z < t.end.z:
			if is_nan(top) or t.end.y > top:
				top = t.end.y
	return [shift, top]


## Length of the overlap of two ranges (negative: the gap between them).
static func _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return minf(a1, b1) - maxf(a0, b0)


static func grid(p: Vector3, step := 1.0) -> Vector3:
	return Vector3(roundf(p.x / step) * step, p.y, roundf(p.z / step) * step)
