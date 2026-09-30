class_name Field
extends Node3D
## A field 100 m long (z) by 56 m wide (x), built in code. Red forms at the north end (-z),
## Blue at the south (+z). The ground rolls: each layout has hills, and a hill hides what is
## behind it, slows the man climbing it and steadies the aim of the man on top of it. Cover
## is stone walls, rail fences, boulders, roofless ruins you can fight from inside, and trees;
## a low piece is fired over, a tall piece stops the ball.

const HALF_X := 56.0
const HALF_Z := 100.0
const LAYER_WORLD := 1
const LAYER_GROUND := 4   # terrain and rim: ragdolls only; the living ride height_at()
const GRID := 2.0   # metres between terrain vertices
const SCALE := 2.0  # the Volley Bots layouts below are drawn for a 56 x 100 field; this one is twice each way

## More of each layout's own ground, scattered by a fixed seed so a field is the same every
## time: a battalion needs ground for every company to fight over.
const EXTRA := {
	"Open Plain": {"boulder": 5, "tree": 4},
	"Walled Farm": {"wall": 7, "fence": 5, "ruin": 2, "boulder": 3, "tree": 6},
	"Woodland": {"tree": 42, "boulder": 7},
	"Village": {"ruin": 9, "wall": 6, "fence": 3, "tree": 4},
	"Hedgerows": {"fence": 14, "tree": 6, "boulder": 2},
	"Churchyard": {"wall": 6, "boulder": 4, "tree": 6, "ruin": 2},
	"Orchard": {"tree": 34, "wall": 3},
	"Crossroads": {"ruin": 4, "fence": 5, "boulder": 4, "wall": 4},
	"Ridge": {"boulder": 11, "tree": 5},
	"Sunken Road": {"fence": 6, "boulder": 5, "tree": 5, "ruin": 2},
}

## The hills of each layout: x, z, radius_x, radius_z, height (negative digs a hollow).
## A hill is a smooth dome; two side by side make a ridge.
const HILLS := {
	"Hedgerows": [[-12.0, -26.0, 24.0, 14.0, 4.0], [14.0, 18.0, 24.0, 14.0, 4.4], [0.0, -4.0, 16.0, 9.0, -2.2]],
	"Churchyard": [[0.0, 0.0, 24.0, 20.0, 5.0], [-20.0, -34.0, 16.0, 12.0, 3.0], [20.0, 34.0, 16.0, 12.0, 3.0]],
	"Sunken Road": [[0.0, 0.0, 40.0, 6.0, -3.0], [-14.0, -20.0, 20.0, 14.0, 4.0], [14.0, 20.0, 20.0, 14.0, 4.0]],
	"Woodland": [[-14.0, -12.0, 14.0, 12.0, 6.0], [12.0, 10.0, 14.0, 12.0, 6.4], [16.0, -30.0, 12.0, 10.0, 3.4], [-16.0, 30.0, 12.0, 10.0, 3.4]],
	"Open Plain": [[0.0, 2.0, 32.0, 14.0, 5.0], [-18.0, -30.0, 16.0, 12.0, 2.6], [18.0, 30.0, 16.0, 12.0, 2.6]],
	"Walled Farm": [[6.0, 4.0, 18.0, 14.0, 4.4], [-16.0, -26.0, 16.0, 12.0, 3.0], [-14.0, 26.0, 14.0, 10.0, 2.4]],
	"Orchard": [[0.0, -14.0, 32.0, 12.0, 3.4], [0.0, 14.0, 32.0, 12.0, 3.4], [0.0, 0.0, 22.0, 7.0, -1.6]],
	"Village": [[2.0, 2.0, 22.0, 18.0, 4.2], [-18.0, -28.0, 14.0, 12.0, 3.4], [18.0, 28.0, 14.0, 12.0, 3.4]],
	"Crossroads": [[-14.0, -14.0, 16.0, 14.0, 5.0], [14.0, 14.0, 16.0, 14.0, 5.0], [14.0, -14.0, 14.0, 12.0, -2.0], [-14.0, 14.0, 14.0, 12.0, -2.0]],
	"Ridge": [[-14.0, 12.0, 22.0, 14.0, 8.0], [14.0, 12.0, 22.0, 14.0, 8.0], [0.0, -26.0, 32.0, 11.0, 4.6]],
}

## The pieces of each layout: x, z, size_x, size_z, height, kind. Kinds: wall, fence, boulder,
## tree, ruin (four walls, no roof, a door in each flank - you can see in and fight from inside).
const LAYOUTS := {
	"Walled Farm": [
		[-14.0, -22.0, 12.0, 0.6, 1.0, "wall"],
		[12.0, -18.0, 9.0, 0.6, 1.0, "wall"],
		[0.0, -8.0, 0.6, 10.0, 1.0, "wall"],
		[-18.0, 4.0, 10.0, 0.4, 1.1, "fence"],
		[16.0, 8.0, 0.4, 9.0, 1.1, "fence"],
		[-8.0, 20.0, 11.0, 0.6, 1.0, "wall"],
		[13.0, 24.0, 9.0, 0.6, 1.0, "wall"],
		[6.0, 2.0, 7.0, 5.0, 1.7, "ruin"],
		[-22.0, -10.0, 3.2, 2.8, 1.8, "boulder"],
		[22.0, 14.0, 3.4, 2.8, 1.7, "boulder"],
		[-6.0, -30.0, 1.0, 1.0, 5.0, "tree"],
		[20.0, -32.0, 1.0, 1.0, 5.0, "tree"],
		[-20.0, 30.0, 1.0, 1.0, 5.0, "tree"],
		[9.0, 34.0, 1.0, 1.0, 5.0, "tree"],
		[-11.0, 9.0, 1.0, 1.0, 5.0, "tree"],
	],
	"Open Plain": [
		[-16.0, -8.0, 3.6, 3.0, 1.9, "boulder"],
		[14.0, 8.0, 3.8, 3.0, 2.0, "boulder"],
		[2.0, -30.0, 1.0, 1.0, 5.0, "tree"],
		[-8.0, 30.0, 1.0, 1.0, 5.0, "tree"],
		[22.0, -1.0, 0.4, 8.0, 1.1, "fence"],
	],
	"Woodland": [
		[-18.0, -20.0, 1.0, 1.0, 5.0, "tree"], [-6.0, -16.0, 1.0, 1.0, 5.0, "tree"], [8.0, -22.0, 1.0, 1.0, 5.0, "tree"],
		[18.0, -12.0, 1.0, 1.0, 5.0, "tree"], [-12.0, -4.0, 1.0, 1.0, 5.0, "tree"], [3.0, -2.0, 1.0, 1.0, 5.0, "tree"],
		[15.0, 2.0, 1.0, 1.0, 5.0, "tree"], [-20.0, 8.0, 1.0, 1.0, 5.0, "tree"], [-4.0, 12.0, 1.0, 1.0, 5.0, "tree"],
		[10.0, 16.0, 1.0, 1.0, 5.0, "tree"], [22.0, 20.0, 1.0, 1.0, 5.0, "tree"], [-14.0, 24.0, 1.0, 1.0, 5.0, "tree"],
		[2.0, 28.0, 1.0, 1.0, 5.0, "tree"], [-9.0, -28.0, 1.0, 1.0, 5.0, "tree"], [17.0, 30.0, 1.0, 1.0, 5.0, "tree"],
		[-22.0, -2.0, 3.6, 3.0, 2.0, "boulder"], [6.0, 7.0, 4.0, 3.2, 2.2, "boulder"], [20.0, -30.0, 3.0, 2.6, 1.8, "boulder"],
		[-14.0, -12.0, 3.4, 2.8, 1.9, "boulder"], [12.0, 10.0, 3.0, 2.6, 1.8, "boulder"],
		[-3.0, 20.0, 8.0, 0.6, 1.0, "wall"],
	],
	"Village": [
		[-12.0, -6.0, 7.0, 5.0, 1.7, "ruin"], [8.0, -10.0, 6.0, 5.0, 1.7, "ruin"], [14.0, 6.0, 7.0, 5.0, 1.7, "ruin"],
		[-6.0, 10.0, 6.0, 5.0, 1.7, "ruin"], [0.0, -24.0, 6.0, 4.5, 1.7, "ruin"], [2.0, 24.0, 6.0, 4.5, 1.7, "ruin"],
		[-20.0, -14.0, 10.0, 0.6, 1.0, "wall"], [20.0, 16.0, 10.0, 0.6, 1.0, "wall"],
		[-1.0, 0.0, 0.6, 9.0, 1.0, "wall"], [-18.0, 18.0, 0.4, 8.0, 1.1, "fence"], [18.0, -20.0, 0.4, 8.0, 1.1, "fence"],
		[-22.0, 30.0, 1.0, 1.0, 5.0, "tree"], [22.0, -32.0, 1.0, 1.0, 5.0, "tree"],
	],
	"Hedgerows": [
		[-16.0, -20.0, 14.0, 0.4, 1.1, "fence"], [12.0, -12.0, 14.0, 0.4, 1.1, "fence"],
		[-10.0, -2.0, 16.0, 0.4, 1.1, "fence"], [14.0, 6.0, 12.0, 0.4, 1.1, "fence"],
		[-14.0, 14.0, 14.0, 0.4, 1.1, "fence"], [10.0, 22.0, 14.0, 0.4, 1.1, "fence"],
		[-22.0, 6.0, 1.0, 1.0, 5.0, "tree"], [22.0, -22.0, 1.0, 1.0, 5.0, "tree"], [0.0, 30.0, 1.0, 1.0, 5.0, "tree"],
		[4.0, -30.0, 3.2, 2.8, 1.8, "boulder"], [-4.0, 8.0, 3.0, 2.6, 1.8, "boulder"],
	],
	"Churchyard": [
		[0.0, 0.0, 8.0, 11.0, 1.9, "ruin"],
		[-9.0, -9.0, 12.0, 0.6, 1.0, "wall"], [9.0, -9.0, 12.0, 0.6, 1.0, "wall"],
		[-9.0, 9.0, 12.0, 0.6, 1.0, "wall"], [9.0, 9.0, 12.0, 0.6, 1.0, "wall"],
		[-15.0, 0.0, 0.6, 12.0, 1.0, "wall"], [15.0, 0.0, 0.6, 12.0, 1.0, "wall"],
		[-20.0, -24.0, 1.0, 1.0, 5.0, "tree"], [20.0, 24.0, 1.0, 1.0, 5.0, "tree"],
		[-22.0, 20.0, 3.4, 2.8, 1.9, "boulder"], [22.0, -20.0, 3.4, 2.8, 1.9, "boulder"],
	],
	"Orchard": [
		[-18.0, -18.0, 1.0, 1.0, 5.0, "tree"], [-6.0, -18.0, 1.0, 1.0, 5.0, "tree"], [6.0, -18.0, 1.0, 1.0, 5.0, "tree"], [18.0, -18.0, 1.0, 1.0, 5.0, "tree"],
		[-12.0, -6.0, 1.0, 1.0, 5.0, "tree"], [0.0, -6.0, 1.0, 1.0, 5.0, "tree"], [12.0, -6.0, 1.0, 1.0, 5.0, "tree"],
		[-18.0, 6.0, 1.0, 1.0, 5.0, "tree"], [-6.0, 6.0, 1.0, 1.0, 5.0, "tree"], [6.0, 6.0, 1.0, 1.0, 5.0, "tree"], [18.0, 6.0, 1.0, 1.0, 5.0, "tree"],
		[-12.0, 18.0, 1.0, 1.0, 5.0, "tree"], [0.0, 18.0, 1.0, 1.0, 5.0, "tree"], [12.0, 18.0, 1.0, 1.0, 5.0, "tree"],
		[-22.0, 0.0, 0.6, 10.0, 1.0, "wall"], [22.0, 0.0, 0.6, 10.0, 1.0, "wall"],
		[0.0, -30.0, 6.0, 4.5, 1.7, "ruin"],
	],
	"Crossroads": [
		[0.0, 0.0, 0.6, 30.0, 1.0, "wall"], [0.0, 0.0, 30.0, 0.6, 1.0, "wall"],
		[10.0, -10.0, 6.5, 5.0, 1.7, "ruin"], [-10.0, 10.0, 6.5, 5.0, 1.7, "ruin"],
		[-18.0, -20.0, 0.4, 10.0, 1.1, "fence"], [18.0, 20.0, 0.4, 10.0, 1.1, "fence"],
		[-20.0, 26.0, 1.0, 1.0, 5.0, "tree"], [20.0, -26.0, 1.0, 1.0, 5.0, "tree"],
		[-14.0, 14.0, 3.4, 2.8, 1.9, "boulder"], [14.0, -14.0, 3.4, 2.8, 1.9, "boulder"],
	],
	"Ridge": [
		[-16.0, 12.0, 18.0, 0.6, 1.0, "wall"], [14.0, 12.0, 18.0, 0.6, 1.0, "wall"],
		[-8.0, -2.0, 3.8, 3.0, 2.0, "boulder"], [10.0, -4.0, 3.4, 2.8, 1.9, "boulder"], [0.0, 22.0, 3.4, 2.8, 1.9, "boulder"],
		[-18.0, -26.0, 3.2, 2.8, 1.8, "boulder"], [16.0, -28.0, 3.6, 3.0, 1.9, "boulder"],
		[22.0, 16.0, 1.0, 1.0, 5.0, "tree"], [-22.0, -10.0, 1.0, 1.0, 5.0, "tree"], [4.0, -36.0, 1.0, 1.0, 5.0, "tree"], [-4.0, 34.0, 1.0, 1.0, 5.0, "tree"],
	],
	"Sunken Road": [
		[-14.0, -3.0, 24.0, 0.6, 1.0, "wall"], [16.0, -3.0, 16.0, 0.6, 1.0, "wall"],
		[-16.0, 3.0, 16.0, 0.6, 1.0, "wall"], [14.0, 3.0, 24.0, 0.6, 1.0, "wall"],
		[-10.0, -24.0, 10.0, 0.4, 1.1, "fence"], [10.0, 24.0, 10.0, 0.4, 1.1, "fence"],
		[-22.0, -16.0, 3.2, 2.8, 1.8, "boulder"], [22.0, 16.0, 3.2, 2.8, 1.8, "boulder"],
		[4.0, -34.0, 1.0, 1.0, 5.0, "tree"], [-4.0, 34.0, 1.0, 1.0, 5.0, "tree"], [24.0, -30.0, 1.0, 1.0, 5.0, "tree"],
	],
}
## The front: ten fields in a line. A campaign opens on field 5; each round's winner pushes the
## fight one field into the loser's country (Red toward 10, Blue toward 1).
const LAYOUT_ORDER: Array[String] = ["Hedgerows", "Churchyard", "Sunken Road", "Woodland", "Open Plain",
	"Walled Farm", "Orchard", "Village", "Crossroads", "Ridge"]
const START_FIELD := 5
const LAYOUT_HELP := {
	"Open Plain": "A long low swell across the middle and two big rocks. Dead ground behind the swell; the crest is the fight.",
	"Walled Farm": "Stone walls and fences on a rise, a roofless farmhouse in the middle. Cover for whoever gets to it first.",
	"Woodland": "Trees, two knolls and big rocks. Lines break up; skirmishers and the bayonet do well.",
	"Village": "Six roofless houses on a rise, walls between. Short sight lines; fighting from doorways and corners.",
	"Sunken Road": "A road in a cut across the middle, walls either side, hills behind. Whoever holds the road fires from cover.",
	"Hedgerows": "Six fence rows staggered over rolling ground. Every line finds a hedge; nobody keeps a straight line for long.",
	"Churchyard": "A roofless church on a knoll, ringed by low walls. A fortress for whoever gets inside first.",
	"Orchard": "Trees in rows on two gentle rises with a hollow between, walls at the flanks. Cover everywhere, none of it good.",
	"Crossroads": "Two walls crossing the middle, a ruin and a knoll on each diagonal, hollows between. Four quarters, each a fight of its own.",
	"Ridge": "A five-metre ridge across Blue's half with a broken wall on the crest; rocks below it. The high line holds the fire.",
}

var layout_name := "Walled Farm"

var pieces: Array[Dictionary] = []   # {rect: Rect2 (x,z), h: float, kind: String, tall: bool}
var spots: Array[Dictionary] = []    # {pos: Vector3, piece: int, normal: Vector3}
var hills: Array = []


## The ground height at a point: the sum of the layout's domes.
func height_at(x: float, z: float) -> float:
	var h := 0.0
	for hl in hills:
		var dx: float = (x - hl[0]) / hl[2]
		var dz: float = (z - hl[1]) / hl[3]
		var r2: float = dx * dx + dz * dz
		if r2 < 1.0:
			var r := sqrt(r2)
			h += hl[4] * (0.5 + 0.5 * cos(PI * r))   # smooth dome: full height at the centre, nothing at the rim
	return h


## Where a point sits on the ground.
func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


## The climb ahead in a direction: metres up per metre travelled (negative downhill).
func slope(p: Vector3, dir: Vector3) -> float:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length_squared() < 0.001:
		return 0.0
	d = d.normalized()
	return height_at(p.x + d.x, p.z + d.z) - height_at(p.x, p.z)


func _ready() -> void:
	hills = []
	for h in HILLS.get(layout_name, []):
		hills.append([h[0] * SCALE, h[1] * SCALE, h[2] * SCALE, h[3] * SCALE, h[4] * 1.25])
	_build_terrain()

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.55, 0.53, 0.48)
	var fence_mat := StandardMaterial3D.new()
	fence_mat.albedo_color = Color(0.45, 0.32, 0.18)
	var ruin_mat := StandardMaterial3D.new()
	ruin_mat.albedo_color = Color(0.62, 0.52, 0.42)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.45, 0.45, 0.47)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.25, 0.14)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.2, 0.4, 0.16)

	# ruins become their four walls (with a door in each flank) before anything is built
	var pieces_src: Array = []
	for p in scaled_pieces(layout_name):
		if p[5] == "ruin":
			pieces_src.append_array(_ruin_walls(p))
		else:
			pieces_src.append(p)
	for i in pieces_src.size():
		var p: Array = pieces_src[i]
		var kind: String = p[5]
		var size := Vector3(p[2], p[4], p[3])
		var base := height_at(p[0], p[1])
		var pos := Vector3(p[0], base + p[4] * 0.5, p[1])
		match kind:
			"wall":
				_static_box(Vector3(pos.x, pos.y - 0.3, pos.z), Vector3(size.x, size.y + 0.6, size.z), wall_mat)   # sunk a little so it meets a slope
			"ruinwall":
				_static_box(Vector3(pos.x, pos.y - 0.3, pos.z), Vector3(size.x, size.y + 0.6, size.z), ruin_mat)
			"fence":
				# two rails and posts, one collider
				var body := _static_box(pos, size, fence_mat, false)
				var along_x: bool = p[2] > p[3]
				var length: float = maxf(p[2], p[3])
				for rail_y in [0.45, 0.95]:
					var r := MeshInstance3D.new()
					r.mesh = _box_mesh(Vector3(length, 0.1, 0.1) if along_x else Vector3(0.1, 0.1, length))
					r.material_override = fence_mat
					r.position = Vector3(0, rail_y - p[4] * 0.5, 0)
					body.add_child(r)
				var n := int(length / 2.0)
				for k in range(n + 1):
					var post := MeshInstance3D.new()
					post.mesh = _box_mesh(Vector3(0.14, 1.4, 0.14))
					post.material_override = fence_mat
					var off := -length * 0.5 + k * (length / n)
					var px := off if along_x else 0.0
					var pz := 0.0 if along_x else off
					# each post stands on its own bit of ground
					var gy := height_at(p[0] + px, p[1] + pz) - base
					post.position = Vector3(px, 0.4 - p[4] * 0.5 + gy, pz)
					body.add_child(post)
			"boulder":
				var body := _static_box(pos, size, rock_mat, false)
				var m := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = maxf(size.x, size.z) * 0.62
				sm.height = size.y * 1.5
				m.mesh = sm
				m.material_override = rock_mat
				m.position = Vector3(0, -size.y * 0.15, 0)
				body.add_child(m)
				# a second lump so it reads as rock, not a ball
				var m2 := MeshInstance3D.new()
				var sm2 := SphereMesh.new()
				sm2.radius = maxf(size.x, size.z) * 0.4
				sm2.height = size.y * 1.1
				m2.mesh = sm2
				m2.material_override = rock_mat
				m2.position = Vector3(size.x * 0.3, -size.y * 0.2, -size.z * 0.25)
				body.add_child(m2)
			"tree":
				var body := _static_box(Vector3(p[0], base + 1.5, p[1]), Vector3(0.6, 3.0, 0.6), trunk_mat)
				var crown := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 2.4
				sm.height = 4.0
				crown.mesh = sm
				crown.material_override = leaf_mat
				crown.position = Vector3(0, 3.2, 0)
				body.add_child(crown)
		var rect := Rect2(p[0] - p[2] * 0.5, p[1] - p[3] * 0.5, p[2], p[3])
		var tall: bool = kind == "tree" or p[4] >= 1.4
		pieces.append({"rect": rect, "h": float(p[4]), "kind": kind, "tall": tall})
	for i in pieces.size():
		_make_spots(i, pieces[i]["rect"], pieces[i]["kind"])


## The layout at battalion scale: every piece moved out to twice the distance (walls and fences
## drawn longer, ruins and rocks a little bigger), then the layout's own kinds of ground added.
static func scaled_pieces(layout: String) -> Array:
	var out := []
	for p in LAYOUTS.get(layout, LAYOUTS["Walled Farm"]):
		var q: Array = p.duplicate()
		q[0] = float(q[0]) * SCALE
		q[1] = float(q[1]) * SCALE
		match String(q[5]):
			"wall", "fence":
				if float(q[2]) > float(q[3]):
					q[2] = float(q[2]) * 1.7
				else:
					q[3] = float(q[3]) * 1.7
			"ruin":
				q[2] = float(q[2]) * 1.25
				q[3] = float(q[3]) * 1.25
			"boulder":
				q[2] = float(q[2]) * 1.2
				q[3] = float(q[3]) * 1.2
		out.append(q)
	var r := RandomNumberGenerator.new()
	r.seed = hash(layout)
	var extra: Dictionary = EXTRA.get(layout, {})
	for kind in extra:
		for n in int(extra[kind]):
			for attempt in 30:
				var x := r.randf_range(-HALF_X + 6.0, HALF_X - 6.0)
				var z := r.randf_range(-HALF_Z + 32.0, HALF_Z - 32.0)
				var q: Array = []
				match String(kind):
					"wall":
						var l := r.randf_range(8.0, 14.0)
						q = [x, z, l, 0.6, 1.0, "wall"] if r.randf() < 0.7 else [x, z, 0.6, l, 1.0, "wall"]
					"fence":
						var l := r.randf_range(8.0, 14.0)
						q = [x, z, l, 0.4, 1.1, "fence"] if r.randf() < 0.7 else [x, z, 0.4, l, 1.1, "fence"]
					"ruin":
						q = [x, z, r.randf_range(6.0, 7.5), r.randf_range(4.5, 5.5), 1.7, "ruin"]
					"boulder":
						q = [x, z, r.randf_range(3.0, 4.0), r.randf_range(2.6, 3.2), r.randf_range(1.8, 2.1), "boulder"]
					_:
						q = [x, z, 1.0, 1.0, 5.0, "tree"]
				var rect := Rect2(float(q[0]) - float(q[2]) * 0.5, float(q[1]) - float(q[3]) * 0.5, float(q[2]), float(q[3])).grow(3.0)
				var clear := true
				for o in out:
					var ro := Rect2(float(o[0]) - float(o[2]) * 0.5, float(o[1]) - float(o[3]) * 0.5, float(o[2]), float(o[3]))
					if rect.intersects(ro):
						clear = false
						break
				if clear:
					out.append(q)
					break
	return out


## A ruin: four walls 0.5 m thick, no roof, and a 1.8 m doorway in the middle of each flank
## (the east and west walls), so either side can get in and the fight inside is in the open air.
static func _ruin_walls(p: Array) -> Array:
	var x: float = p[0]
	var z: float = p[1]
	var sx: float = p[2]
	var sz: float = p[3]
	var h: float = p[4]
	var t := 0.5
	var door := 1.8
	var out := []
	# north and south walls, full width
	out.append([x, z - sz * 0.5 + t * 0.5, sx, t, h, "ruinwall"])
	out.append([x, z + sz * 0.5 - t * 0.5, sx, t, h, "ruinwall"])
	# east and west walls, split around a doorway
	var seg := (sz - door) * 0.5
	for side in [-1.0, 1.0]:
		var wx: float = x + float(side) * (sx * 0.5 - t * 0.5)
		out.append([wx, z - sz * 0.5 + seg * 0.5, t, seg, h, "ruinwall"])
		out.append([wx, z + sz * 0.5 - seg * 0.5, t, seg, h, "ruinwall"])
	return out


## The ground: a mesh over the hills, and a heightmap collider so ragdolls lie on the slope.
func _build_terrain() -> void:
	var nx := int((HALF_X * 2 + 8) / GRID) + 1
	var nz := int((HALF_Z * 2 + 8) / GRID) + 1
	var x0 := -(nx - 1) * GRID * 0.5
	var z0 := -(nz - 1) * GRID * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var grass_a := Color(0.33, 0.46, 0.24)
	var grass_b := Color(0.36, 0.5, 0.26)
	for j in nz:
		for i in nx:
			heights[j * nx + i] = height_at(x0 + i * GRID, z0 + j * GRID)
	var vert := func(i: int, j: int) -> void:
		var x := x0 + i * GRID
		var z := z0 + j * GRID
		var y: float = heights[j * nx + i]
		# normal from the neighbours
		var hl: float = heights[j * nx + maxi(i - 1, 0)]
		var hr: float = heights[j * nx + mini(i + 1, nx - 1)]
		var hd: float = heights[maxi(j - 1, 0) * nx + i]
		var hu: float = heights[mini(j + 1, nz - 1) * nx + i]
		st.set_normal(Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized())
		# lighter strips every 11 m so movement reads, a worn track across the middle, paler on the tops
		var band: bool = int(floor((z + 2.0) / 11.0)) % 2 == 0
		var c := grass_a if band else grass_b
		if absf(z + 1.0) < 1.5:
			c = Color(0.5, 0.42, 0.28)
		# higher ground is paler and drier; a hollow is darker and greener
		c = c.lightened(clampf(y * 0.05, 0.0, 0.3)) if y >= 0.0 else c.darkened(clampf(-y * 0.12, 0.0, 0.3))
		if y > 0.5:
			c = c.lerp(Color(0.55, 0.5, 0.3), clampf((y - 0.5) * 0.08, 0.0, 0.45))
		# contour bands every metre, so the relief reads from any height
		var band_i := int(floor(y + 100.0))
		if band_i % 2 == 1:
			c = c.darkened(0.1)
		st.set_color(c)
		st.add_vertex(Vector3(x, y, z))
	for j in nz - 1:
		for i in nx - 1:
			vert.call(i, j)
			vert.call(i + 1, j)
			vert.call(i, j + 1)
			vert.call(i + 1, j)
			vert.call(i + 1, j + 1)
			vert.call(i, j + 1)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = LAYER_GROUND   # the ground is for ragdolls; the men ride height_at() and never touch it
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = nx
	hm.map_depth = nz
	hm.map_data = heights
	cs.shape = hm
	cs.scale = Vector3(GRID, 1.0, GRID)
	body.add_child(cs)
	add_child(body)

	_build_rim(nx, nz, x0, z0, heights)

	# deployment lines at each end, laid on the ground
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.85, 0.8)
	for zz in [-HALF_Z + 6.0, HALF_Z - 6.0]:
		for k in range(-int(HALF_X / 2.0), int(HALF_X / 2.0) + 1):
			var l := MeshInstance3D.new()
			l.mesh = _box_mesh(Vector3(2.0, 0.04, 0.15))
			l.material_override = line_mat
			var lx := k * 2.0
			l.position = Vector3(lx, height_at(lx, zz) + 0.03, zz)
			add_child(l)


## A glass rim round the edge of the ground, so a body thrown by a volley stops at the edge
## of the world rather than sliding off it. Faint enough to see through; it rises with the
## ground under it, so a hill that runs off the edge is walled too.
func _build_rim(nx: int, nz: int, x0: float, z0: float, heights: PackedFloat32Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.88, 1.0, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.85, 0.93, 1.0, 0.45)
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var x1 := x0 + (nx - 1) * GRID
	var z1 := z0 + (nz - 1) * GRID
	const RISE := 1.6
	const T := 0.3
	# four sides: each a strip of panels following the ground height along that edge
	var sides := [
		[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x0, z1), Vector2(x1, z1)],
		[Vector2(x0, z0), Vector2(x0, z1)], [Vector2(x1, z0), Vector2(x1, z1)],
	]
	var seg := 4.0
	for sd in sides:
		var a: Vector2 = sd[0]
		var b: Vector2 = sd[1]
		var length := a.distance_to(b)
		var n := int(ceil(length / seg))
		var along_x: bool = absf(b.x - a.x) > 0.01
		for k in n:
			var t0 := float(k) / n
			var t1 := float(k + 1) / n
			var pa := a.lerp(b, t0)
			var pb := a.lerp(b, t1)
			var mid := (pa + pb) * 0.5
			var g := maxf(height_at(pa.x, pa.y), maxf(height_at(pb.x, pb.y), height_at(mid.x, mid.y)))
			var h := g + RISE + 1.0   # from a metre below the ground to RISE above it
			var size := Vector3(pa.distance_to(pb) + 0.02 if along_x else T, h, T if along_x else pa.distance_to(pb) + 0.02)
			var body := StaticBody3D.new()
			body.collision_layer = LAYER_GROUND
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = size
			cs.shape = sh
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.mesh = _box_mesh(size)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mi)
			# a brighter lip along the top so the rim reads as an edge
			var lip := MeshInstance3D.new()
			lip.mesh = _box_mesh(Vector3(size.x, 0.06, size.z))
			lip.material_override = edge_mat
			lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lip.position = Vector3(0, h * 0.5, 0)
			body.add_child(lip)
			body.position = Vector3(mid.x, -1.0 + h * 0.5, mid.y)
			add_child(body)
	# and a floor under everything, in case anything ever gets past the ground
	var net := StaticBody3D.new()
	net.collision_layer = LAYER_GROUND
	net.collision_mask = 0
	var ncs := CollisionShape3D.new()
	var nsh := BoxShape3D.new()
	nsh.size = Vector3(x1 - x0 + 4.0, 1.0, z1 - z0 + 4.0)
	ncs.shape = nsh
	net.add_child(ncs)
	net.position = Vector3(0, -4.0, 0)
	add_child(net)


## Firing positions along each face of a piece: a man's width back from it, one every 1.3 m.
func _make_spots(idx: int, rect: Rect2, kind: String) -> void:
	var faces: Array = []
	if kind == "tree" or kind == "boulder":
		# corners around a small piece; both sides matter
		for n in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
			var c := Vector3(rect.get_center().x, 0, rect.get_center().y)
			faces.append({"pos": c + n * (maxf(rect.size.x, rect.size.y) * 0.5 + 0.9), "normal": n})
		for f in faces:
			spots.append({"pos": ground(f["pos"]), "piece": idx, "normal": f["normal"]})
		return
	var along_x := rect.size.x >= rect.size.y
	var length: float = rect.size.x if along_x else rect.size.y
	var n_spots := maxi(int(length / 1.3), 1)
	for k in range(n_spots):
		var off := -length * 0.5 + (k + 0.5) * (length / n_spots)
		for side in [-1.0, 1.0]:
			var normal := Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)
			var c := rect.get_center()
			var pos := Vector3(c.x + (off if along_x else 0.0), 0.0, c.y + (0.0 if along_x else off))
			pos += normal * ((rect.size.y if along_x else rect.size.x) * 0.5 + 0.9)
			if blocked(pos, 0.2):
				continue   # a ruin's inner corner, or a wall hard against another
			spots.append({"pos": ground(pos), "piece": idx, "normal": normal})


func in_bounds(p: Vector3, margin: float = 0.8) -> bool:
	return absf(p.x) < HALF_X - margin and absf(p.z) < HALF_Z - margin


func clamp_point(p: Vector3, margin: float = 0.8) -> Vector3:
	return Vector3(clampf(p.x, -HALF_X + margin, HALF_X - margin), p.y, clampf(p.z, -HALF_Z + margin, HALF_Z - margin))


## Is the point inside (or hard against) a piece? Used to keep men out of walls.
func blocked(p: Vector3, pad: float = 0.5) -> bool:
	for pc in pieces:
		var r: Rect2 = pc["rect"].grow(pad)
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false


## Push a point out of any piece it sits in.
func free_point(p: Vector3, pad: float = 0.6) -> Vector3:
	for pc in pieces:
		var r: Rect2 = pc["rect"].grow(pad)
		if r.has_point(Vector2(p.x, p.z)):
			var c := r.get_center()
			var d := Vector2(p.x, p.z) - c
			if absf(d.x) / r.size.x > absf(d.y) / r.size.y:
				p.x = c.x + signf(d.x if d.x != 0.0 else 1.0) * (r.size.x * 0.5 + 0.05)
			else:
				p.z = c.y + signf(d.y if d.y != 0.0 else 1.0) * (r.size.y * 0.5 + 0.05)
	return clamp_point(p)


## The line of fire from `from` to `to` (both at their true heights): 1.0 clear; 0.0 if a tall
## piece or the ground stands in the way; otherwise the cover the target gets from a low piece
## within 2.2 m of him (0.45), a tall piece's edge (0.3), or a crest he is just behind (0.5) -
## the shooter aims at what shows above it.
func line_of_fire(from: Vector3, to: Vector3) -> float:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var best := 1.0
	for pc in pieces:
		var r: Rect2 = pc["rect"]
		if not _segment_hits_rect(a, b, r):
			continue
		var near_target := _rect_distance(r, b) < 2.2
		if pc["tall"]:
			if near_target:
				best = minf(best, 0.3)
			else:
				return 0.0
		elif near_target:
			best = minf(best, 0.45)
	# the ground: walk the line and see whether a hill gets in the way
	if not hills.is_empty():
		var d := from.distance_to(to)
		var steps := maxi(int(d / 2.0), 1)
		for k in range(1, steps):
			var t := float(k) / steps
			var p := from.lerp(to, t)
			var clear := p.y - height_at(p.x, p.z)
			if clear < 0.0:
				return 0.0
			# a crest within the last few metres of the target hides all but his head and shoulders
			if clear < 0.8 and (1.0 - t) * d < 5.0:
				best = minf(best, 0.5)
	return best


## Cover spots within `radius` of a point that face the threat, nearest first.
func spots_near(p: Vector3, threat_dir: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in spots:
		var sp: Vector3 = s["pos"]
		if sp.distance_to(p) > radius:
			continue
		# the piece must be between the man and the threat: its normal points away from the threat
		if (s["normal"] as Vector3).dot(threat_dir) > -0.3:
			continue
		out.append(s)
	out.sort_custom(func(x, y): return (x["pos"] as Vector3).distance_squared_to(p) < (y["pos"] as Vector3).distance_squared_to(p))
	return out


static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(r.position.x - p.x, maxf(0.0, p.x - r.end.x))
	var dy := maxf(r.position.y - p.y, maxf(0.0, p.y - r.end.y))
	return sqrt(dx * dx + dy * dy)


static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	# Liang-Barsky clip
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true


func _static_box(pos: Vector3, size: Vector3, mat: Material, with_mesh: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	if with_mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(size)
		mi.material_override = mat
		body.add_child(mi)
	body.position = pos
	add_child(body)
	return body


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
