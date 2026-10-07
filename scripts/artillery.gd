class_name Artillery
extends Node3D
## The guns: field pieces served by a company of the Gunner type (a gun for every five men).
## A gun is hauled forward with its company until something is in range, then it fires roundshot:
## a ball that skips along the ground through whoever stands in its path - and batters a fort's
## walls until they are breached. It needs two of its crew at it to fire, and loads slower with
## fewer than four.

const RANGE := 420.0          # roundshot: effective out to about 400 m
const RELOAD := 22.0          # seconds with a full crew of four
const HAUL := 0.8             # m/s, a gun manhandled forward
const CREW_NEAR := 4.0        # a man within this of the gun is serving it
const PER_GUN := 5            # men a gun

var manager: MatchManager
var field: Field
var guns: Array = []          # {team, company, node, barrel, pos, reload, slot, aim}


func clear() -> void:
	for g in guns:
		if is_instance_valid(g["node"]):
			(g["node"] as Node).queue_free()
	guns.clear()


static func is_gun_company(co: Dictionary) -> bool:
	return String(co.get("type_name", "")) == "Gunner"


## Place the guns of every Gunner company at its starting place.
func place(t: int, c: int, centre: Vector3, men: int) -> void:
	var n := maxi(1, int(round(float(men) / PER_GUN)))
	for i in n:
		var x := centre.x + (float(i) - float(n - 1) * 0.5) * 9.0
		var pos := Vector3(x, field.height_at(x, centre.z), centre.z)
		var node := _gun_mesh(t)
		add_child(node)
		node.global_position = pos
		node.rotation.y = 0.0 if t == 0 else PI
		guns.append({"team": t, "company": c, "node": node, "pos": pos, "reload": randf_range(2.0, 6.0), "slot": i, "of": n})


## Where crewman `slot` of company (t, c) should stand: beside one of its guns.
func crew_post(t: int, c: int, slot: int) -> Vector3:
	var mine := []
	for g in guns:
		if int(g["team"]) == t and int(g["company"]) == c:
			mine.append(g)
	if mine.is_empty():
		return Vector3.INF
	var g: Dictionary = mine[slot % mine.size()]
	var k := slot / mine.size()
	var back := -manager.toward(t)
	var side := (float(k % 2) * 2.0 - 1.0) * (1.2 + 0.4 * float(k / 2))
	return (g["pos"] as Vector3) + Vector3(side, 0, back * (1.5 + 0.5 * float(k / 2)))


func tick(delta: float) -> void:
	for g in guns:
		var t: int = g["team"]
		var c: int = g["company"]
		var crew := 0
		for m in manager.fighting_company(t, c):
			if m.global_position.distance_to(g["pos"]) < CREW_NEAR:
				crew += 1
		var target := _target(g)
		if target == Vector3.INF:
			_haul(g, delta, crew)
			continue
		var node: Node3D = g["node"]
		var to := target - (g["pos"] as Vector3)
		to.y = 0.0
		if to.length() > 0.1:
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-to.x, -to.z), clampf(delta * 2.0, 0.0, 1.0))
		if crew < 2:
			continue
		g["reload"] = float(g["reload"]) - delta * minf(float(crew) / 4.0, 1.0)
		if float(g["reload"]) <= 0.0:
			g["reload"] = RELOAD * randf_range(0.9, 1.15)
			_fire(g, target)


## Haul the gun toward where its company's line is going, while nothing is in range.
func _haul(g: Dictionary, delta: float, crew: int) -> void:
	if crew < 2:
		return
	var t: int = g["team"]
	var o: Dictionary = manager.orders[t][g["company"]]
	var n := int(g["of"])
	var want := Vector3(float(o.get("center_x", 0.0)) + (float(g["slot"]) - float(n - 1) * 0.5) * 9.0, 0, float(o.get("line_z", 0.0)))
	var pos: Vector3 = g["pos"]
	var d := Vector3(want.x - pos.x, 0, want.z - pos.z)
	if d.length() < 3.0:
		return
	var step := d.normalized() * minf(HAUL * delta * minf(float(crew) / 3.0, 1.0), d.length())
	var np := field.free_point(pos + step)
	np.y = field.height_at(np.x, np.z)
	g["pos"] = np
	(g["node"] as Node3D).global_position = np


## What the gun fires at: a standing stretch of the enemy's fort in range, else the enemy company
## with the most men inside its range (nearer counts for more). INF: nothing in range.
func _target(g: Dictionary) -> Vector3:
	var t: int = g["team"]
	var pos: Vector3 = g["pos"]
	var breached := 0
	for pc in field.pieces:
		if pc["kind"] == "breach":
			breached += 1
	if field.fort_side == 1 - t and breached < 2:   # two breaches open the way in; then the men
		var best := Vector3.INF
		var best_d := INF
		for i in field.pieces.size():
			var pc: Dictionary = field.pieces[i]
			if pc["kind"] != "fortwall":
				continue
			var cc: Vector2 = (pc["rect"] as Rect2).get_center()
			var p := Vector3(cc.x, 0, cc.y)
			var d := p.distance_to(Vector3(pos.x, 0, pos.z))
			# the front of the fort first: the wall facing us
			if d < RANGE and d < best_d:
				best_d = d
				best = p
		if best != Vector3.INF:
			return Vector3(best.x, field.height_at(best.x, best.z), best.z)
	var best_s := 0.0
	var aim := Vector3.INF
	for c in (manager.companies[1 - t] as Array).size():
		var men := manager.fighting_company(1 - t, c)
		if men.size() < 2:
			continue
		var cen := Vector3.ZERO
		for m in men:
			cen += m.global_position
		cen /= men.size()
		var d := cen.distance_to(pos)
		if d > RANGE or d < 25.0:
			continue
		var s := float(men.size()) * (1.5 - d / RANGE)
		if s > best_s:
			best_s = s
			aim = cen
	return aim


## A round: smoke and a boom at the muzzle; the ball flies, strikes a wall in its path (and does it
## harm) or skips on along the ground through the men in its way, up to three, for 80 m past the aim.
func _fire(g: Dictionary, target: Vector3) -> void:
	var t: int = g["team"]
	var from: Vector3 = g["pos"] + Vector3(0, 1.0, 0)
	var dir := target - from
	dir.y = 0.0
	var d := dir.length()
	dir = dir / maxf(d, 0.01)
	var side := Vector3(-dir.z, 0, dir.x)
	var aim := target + side * randfn(0.0, 0.012 * d) + dir * randfn(0.0, 0.035 * d)
	var end := aim + dir * 80.0
	field.add_smoke(from, dir, 6.0)
	field.add_smoke(from + dir * 3.0, dir, 4.0)
	if manager.fx != null:
		manager.fx.cannon(from, aim)
	var crewman: Soldier = null
	for m in manager.fighting_company(t, g["company"]):
		crewman = m
		break
	# the fort first: a wall in the way stops the ball
	var wall := field.fort_wall_on(Vector2(from.x, from.z), Vector2(end.x, end.z))
	var stop_at := INF
	if wall >= 0:
		var wc: Vector2 = (field.pieces[wall]["rect"] as Rect2).get_center()
		stop_at = Vector2(from.x, from.z).distance_to(wc)
		field.strike_piece(wall)
		manager.stats["wall_hits"][t] += 1
		manager._last_harm_t = manager.elapsed   # (battering a wall is not a stalemate)
	# then the men in its path (on the ground from where it first strikes, a few metres short of the aim)
	var hit := []
	for s in manager.alive_soldiers():
		var rel := s.global_position - from
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < 10.0 or along > d + 80.0 or along > stop_at:
			continue
		var off := (rel - dir * along).length()
		if off < 0.9:
			hit.append([along, s])
		elif off < 5.0:
			s.suppression = minf(s.suppression + 0.25 * (1.0 - off / 5.0), 1.0)
			s.under_fire = true
	hit.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for h in hit:
		if n >= 3:
			break
		if randf() < 0.75:
			(h[1] as Soldier).take_damage(999.0, "cannon", crewman)
			n += 1


func _gun_mesh(t: int) -> Node3D:
	var root := Node3D.new()
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.42, 0.33, 0.18)
	bronze.metallic = 0.6
	bronze.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.24, 0.13).lerp(MatchManager.TEAM_COLORS[t], 0.15)
	var trail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.5, 0.3, 2.6)
	trail.mesh = tm
	trail.material_override = wood
	trail.position = Vector3(0, 0.45, 0.6)
	trail.rotation.x = -0.25
	root.add_child(trail)
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.11
	bm.bottom_radius = 0.16
	bm.height = 1.9
	barrel.mesh = bm
	barrel.material_override = bronze
	barrel.rotation.x = -PI * 0.5 + 0.05
	barrel.position = Vector3(0, 0.95, -0.4)
	root.add_child(barrel)
	for sx in [-0.55, 0.55]:
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.65
		wm.bottom_radius = 0.65
		wm.height = 0.1
		wheel.mesh = wm
		wheel.material_override = wood
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(sx, 0.65, 0)
		root.add_child(wheel)
	return root
