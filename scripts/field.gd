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
	"Suburb": [[-12.0, -10.0, 20.0, 14.0, 1.2], [14.0, 12.0, 18.0, 14.0, 1.0]],
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
	# built in code at battalion scale (see scaled_pieces): City, Suburb, River Crossing
	"City": [], "Suburb": [], "River Crossing": [],
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
## Every field there is: the front, then the close-quarters fields (single battles and Sim x10).
const ALL_FIELDS: Array[String] = ["Hedgerows", "Churchyard", "Sunken Road", "Woodland", "Open Plain",
	"Walled Farm", "Orchard", "Village", "Crossroads", "Ridge", "City", "Suburb", "River Crossing"]
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
	"City": "Blocks of roofless houses three metres high, narrow streets, rubble and barricades in every street, a church and a square in the middle. No range anywhere: the bayonet's ground.",
	"Suburb": "Rows of roofless houses with fenced gardens, hedges and trees, lanes between. Short sight lines, cover at every garden fence.",
	"River Crossing": "Two rivers across the field, each crossed only by one narrow bridge - one on each flank. Mills, walls, woods and rocks crowd both banks. Whoever holds a bridge holds the field.",
}

var layout_name := "Walled Farm"
var fort_side := -1          # a fort for this side (0 Red, 1 Blue) at its end of the field, -1 none
const FORT_HALF_W := 40.0    # the fort: a redoubt across most of the front ...
const FORT_FRONT := 38.0     # ... its front wall this far out from the side's edge
const FORT_BACK := 10.0      # ... its rear wall this far out (a gate in it)
const FORT_WALL_HP := 4      # cannon balls to breach one stretch of wall
const FORT_WALL_H := 3.2     # the curtain wall: too high to climb or to fire over from the ground
const RAMPART_H := 2.0       # the rampart behind it: a man standing on it fires over the parapet
const RAMPART_TOP := 3.0     # metres of flat walk behind the wall ...
const RAMPART_RAMP := 4.0    # ... and the slope (the steps) down into the fort
const FORT_GATE := 3.0       # the gates (front and back): narrow
var _terrain_mi: MeshInstance3D = null

var pieces: Array[Dictionary] = []   # {rect: Rect2 (x,z), h: float, kind: String, tall: bool}
var spots: Array[Dictionary] = []    # {pos: Vector3, piece: int, normal: Vector3}
var hills: Array = []


## The ground height at a point: read from a 1 m table of the domes (built once per field;
## asked over a million times a battle), exact outside it.
const HT_STEP := 1.0
const HT_X0 := -64.0
const HT_Z0 := -108.0
var _ht := PackedFloat32Array()
var _ht_w := 0
var _ht_h := 0


func height_at(x: float, z: float) -> float:
	if hills.is_empty() and fort_side < 0:
		return 0.0
	if _ht_w > 0:
		var fx := (x - HT_X0) / HT_STEP
		var fz := (z - HT_Z0) / HT_STEP
		var ix := floori(fx)
		var iz := floori(fz)
		if ix >= 0 and iz >= 0 and ix < _ht_w - 1 and iz < _ht_h - 1:
			var tx := fx - ix
			var tz := fz - iz
			var i0 := iz * _ht_w + ix
			var h0: float = lerpf(_ht[i0], _ht[i0 + 1], tx)
			var h1: float = lerpf(_ht[i0 + _ht_w], _ht[i0 + _ht_w + 1], tx)
			return lerpf(h0, h1, tz)
	return _height_exact(x, z)


func _build_height_table() -> void:
	_ht_w = int(-HT_X0 * 2.0 / HT_STEP) + 1
	_ht_h = int(-HT_Z0 * 2.0 / HT_STEP) + 1
	_ht.resize(_ht_w * _ht_h)
	for j in _ht_h:
		for i in _ht_w:
			_ht[j * _ht_w + i] = _height_exact(HT_X0 + i * HT_STEP, HT_Z0 + j * HT_STEP)


func _height_exact(x: float, z: float) -> float:
	var h := _rampart_at(x, z)
	for hl in hills:
		var dx: float = (x - hl[0]) / hl[2]
		var dz: float = (z - hl[1]) / hl[3]
		var r2: float = dx * dx + dz * dz
		if r2 < 1.0:
			var r := sqrt(r2)
			h += hl[4] * (0.5 + 0.5 * cos(PI * r))   # smooth dome: full height at the centre, nothing at the rim
	return h


## The fort's rampart: a walk RAMPART_H high along the inside of every wall, RAMPART_TOP wide,
## sloping down to the floor of the fort (the steps up) - and down to the ground at the gates.
func _rampart_at(x: float, z: float) -> float:
	if fort_side < 0:
		return 0.0
	var r := fort_area()
	if not r.has_point(Vector2(x, z)):
		return 0.0
	var dx := minf(x - r.position.x, r.end.x - x) - 0.5   # from the side walls' inner faces
	var dz := minf(z - r.position.y, r.end.y - z) - 0.5   # from the front and back walls'
	var gate := smoothstep(FORT_GATE * 0.5, FORT_GATE * 0.5 + 4.0, absf(x))   # down to the ground in a gateway
	return maxf(_bank(dz) * gate, _bank(dx))


static func _bank(d: float) -> float:
	if d <= 0.0:
		return 0.0
	if d <= RAMPART_TOP:
		return RAMPART_H
	if d < RAMPART_TOP + RAMPART_RAMP:
		return RAMPART_H * (1.0 - (d - RAMPART_TOP) / RAMPART_RAMP)
	return 0.0


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
	if not hills.is_empty() or fort_side >= 0:
		_build_height_table()
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
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.33, 0.78)   # plainly blue, whatever the sky
	water_mat.roughness = 0.45
	water_mat.metallic_specular = 0.25
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.5, 0.38, 0.24)

	# ruins become their four walls (with a door in each flank) before anything is built
	var pieces_src: Array = []
	var fort_rect := fort_area()
	for p in scaled_pieces(layout_name):
		if fort_side >= 0:
			var pr := Rect2(float(p[0]) - float(p[2]) * 0.5, float(p[1]) - float(p[3]) * 0.5, float(p[2]), float(p[3]))
			if pr.intersects(fort_rect.grow(4.0)):
				continue   # cleared for the fort
		if p[5] == "ruin":
			pieces_src.append_array(_ruin_walls(p))
		else:
			pieces_src.append(p)
	if fort_side >= 0:
		pieces_src.append_array(_fort_walls())
	var fort_mat := StandardMaterial3D.new()
	fort_mat.albedo_color = Color(0.5, 0.45, 0.36)
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
			"fortwall":
				# kept out of the baked field mesh, so a breach can take it away
				var fb := _static_box(Vector3(pos.x, pos.y - 0.3, pos.z), Vector3(size.x, size.y + 0.6, size.z), fort_mat)
				fb.set_meta("nobake", true)
				fort_nodes[pieces.size()] = fb
				_fort_mat = fort_mat
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
			"water":
				# the river: impassable (an invisible bank-high collider), flat water on top
				var wb := _static_box(Vector3(p[0], base + 0.7, p[1]), Vector3(p[2], 1.4, p[3]), water_mat, false)
				var wm := MeshInstance3D.new()
				wm.mesh = _box_mesh(Vector3(p[2], 0.06, p[3]))
				wm.material_override = water_mat
				wm.position = Vector3(0, -0.66, 0)
				wb.add_child(wm)
			"deck":
				# a bridge deck: drawn and walked on, not a piece
				var dm := MeshInstance3D.new()
				dm.mesh = _box_mesh(Vector3(p[2], 0.12, p[3]))
				dm.material_override = deck_mat
				dm.position = Vector3(p[0], base + 0.06, p[1])
				add_child(dm)
				continue
		var rect := Rect2(p[0] - p[2] * 0.5, p[1] - p[3] * 0.5, p[2], p[3])
		var tall: bool = kind == "tree" or (kind != "water" and p[4] >= 1.4)
		pieces.append({"rect": rect, "h": float(p[4]), "kind": kind, "tall": tall, "hp": FORT_WALL_HP if kind == "fortwall" else 0,
			"fort": kind == "fortwall", "orig": rect, "box": [Vector3(pos.x, pos.y - 0.3, pos.z), Vector3(size.x, size.y + 0.6, size.z)]})
	for i in pieces.size():
		if pieces[i]["kind"] != "water":
			_make_spots(i, pieces[i]["rect"], pieces[i]["kind"])
	_bake_field()
	_build_buckets()
	_build_nav()


## The layout at battalion scale: every piece moved out to twice the distance (walls and fences
## drawn longer, ruins and rocks a little bigger), then the layout's own kinds of ground added.
static func scaled_pieces(layout: String) -> Array:
	match layout:
		"City":
			return _city_pieces()
		"Suburb":
			return _suburb_pieces()
		"River Crossing":
			return _river_pieces()
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


var fort_nodes := {}   # piece index -> its StaticBody3D (fort walls only)
var _fort_mat: Material = null


## A new battle on the same field: the fort's walls stand whole again.
func restore_fort() -> void:
	for i in pieces.size():
		var pc: Dictionary = pieces[i]
		if not pc.get("fort", false):
			continue
		if pc["kind"] == "fortwall" and int(pc["hp"]) == FORT_WALL_HP:
			continue
		pc["hp"] = FORT_WALL_HP
		if pc["kind"] == "breach":
			pc["kind"] = "fortwall"
			pc["rect"] = pc["orig"]
			var b: Array = pc["box"]
			var fb := _static_box(b[0], b[1], _fort_mat)
			fb.set_meta("nobake", true)
			fort_nodes[i] = fb
			_make_spots(i, pc["rect"], "fortwall")
			if _nav != null:
				var rr := (pc["rect"] as Rect2).grow(0.3)
				var c0 := _nav_cell(rr.position)
				var c1 := _nav_cell(rr.end)
				for a in range(c0.x, c1.x + 1):
					for bb in range(c0.y, c1.y + 1):
						_nav.set_point_solid(Vector2i(a, bb), true)
		elif fort_nodes.has(i):
			(fort_nodes[i] as Node3D).scale.y = 1.0


## The ground the fort stands on (x, z), or an empty rect.
func fort_area() -> Rect2:
	if fort_side < 0:
		return Rect2()
	var edge := -HALF_Z if fort_side == 0 else HALF_Z
	var inward := 1.0 if fort_side == 0 else -1.0
	var z_front := edge + inward * FORT_FRONT
	var z_back := edge + inward * FORT_BACK
	return Rect2(-FORT_HALF_W, minf(z_front, z_back), FORT_HALF_W * 2.0, absf(z_front - z_back))


## The fort's walls: a curtain wall FORT_WALL_H high and a metre thick - too high to climb or to
## fire over from the ground; the garrison fires over it from the rampart behind (_rampart_at).
## The front in four stretches with a narrow gate between the middle two, a side wall each end,
## the rear with a narrow gate. Each stretch takes FORT_WALL_HP cannon balls to breach.
func _fort_walls() -> Array:
	var r := fort_area()
	var h := FORT_WALL_H
	var t := 1.0
	var out := []
	var front_z := r.position.y if fort_side == 1 else r.end.y
	var back_z := r.end.y if fort_side == 1 else r.position.y
	var g := FORT_GATE * 0.5
	# the front: four stretches, the gate between the middle two
	for span in [[-FORT_HALF_W, -FORT_HALF_W * 0.5], [-FORT_HALF_W * 0.5, -g], [g, FORT_HALF_W * 0.5], [FORT_HALF_W * 0.5, FORT_HALF_W]]:
		out.append([(span[0] + span[1]) * 0.5, front_z, span[1] - span[0] - 0.2, t, h, "fortwall"])
	for side in [-1.0, 1.0]:
		out.append([side * (FORT_HALF_W - t * 0.5), r.get_center().y, t, r.size.y, h, "fortwall"])
	# the back: a narrow gate in the middle
	for span in [[-FORT_HALF_W, -g], [g, FORT_HALF_W]]:
		out.append([(span[0] + span[1]) * 0.5, back_z, span[1] - span[0], t, h, "fortwall"])
	return out


## A cannon ball has struck piece i. A fort wall loses a little; on the last hit it is breached -
## gone, and the ground behind it open.
func strike_piece(i: int) -> bool:
	if i < 0 or i >= pieces.size() or pieces[i]["kind"] != "fortwall":
		return false
	pieces[i]["hp"] = int(pieces[i]["hp"]) - 1
	if int(pieces[i]["hp"]) > 0:
		var nd: Node3D = fort_nodes.get(i)
		if nd != null:
			nd.scale.y = 0.6 + 0.4 * float(pieces[i]["hp"]) / FORT_WALL_HP   # knocked lower each time
		return false
	var old: Rect2 = pieces[i]["rect"]
	pieces[i]["rect"] = Rect2(9999.0, 9999.0, 0.0, 0.0)
	pieces[i]["kind"] = "breach"
	var keep: Array[Dictionary] = []
	for sp in spots:
		if int(sp["piece"]) != i:
			keep.append(sp)
	spots = keep
	if _nav != null:
		var rr := old.grow(0.3)
		var c0 := _nav_cell(rr.position)
		var c1 := _nav_cell(rr.end)
		for a in range(c0.x, c1.x + 1):
			for b in range(c0.y, c1.y + 1):
				_nav.set_point_solid(Vector2i(a, b), false)
	var nd2: Node = fort_nodes.get(i)
	if nd2 != null:
		nd2.queue_free()
		fort_nodes.erase(i)
	return true


## The nearest piece of fort wall on the segment a-b (x, z), or -1.
func fort_wall_on(a: Vector2, b: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in _pieces_on_segment(a, b):
		if pieces[i]["kind"] != "fortwall":
			continue
		var r: Rect2 = pieces[i]["rect"]
		if _segment_hits_rect(a, b, r):
			var d := a.distance_to(r.get_center())
			if d < best_d:
				best_d = d
				best = i
	return best


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
	_terrain_mi = mi

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
	for i in _pieces_at(Vector2(p.x, p.z)):
		var r: Rect2 = pieces[i]["rect"].grow(pad)
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false


## Push a point out of any piece it sits in.
func free_point(p: Vector3, pad: float = 0.6) -> Vector3:
	for i in _pieces_in(Rect2(p.x - 12.0, p.z - 12.0, 24.0, 24.0)):
		var r: Rect2 = pieces[i]["rect"].grow(pad)
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
	for pi in _pieces_on_segment(a, b):
		var pc: Dictionary = pieces[pi]
		if pc["kind"] == "water":
			continue   # a ball flies over a river
		var r: Rect2 = pc["rect"]
		if not _segment_hits_rect(a, b, r):
			continue
		var near_target := _rect_distance(r, b) < 2.2
		if pc["kind"] == "fortwall":
			# where the line crosses the wall, is it above the parapet?
			var cc := r.get_center()
			var tt := 0.5
			if r.size.x >= r.size.y:
				tt = (cc.y - a.y) / (b.y - a.y) if absf(b.y - a.y) > 0.001 else 0.5
			else:
				tt = (cc.x - a.x) / (b.x - a.x) if absf(b.x - a.x) > 0.001 else 0.5
			tt = clampf(tt, 0.0, 1.0)
			var top: float = height_at(cc.x, cc.y) + float(pc["h"])
			var y := lerpf(from.y, to.y, tt)
			if y > top + 0.05:
				if near_target:
					best = minf(best, 0.35)   # a man on the rampart: head and shoulders over the parapet
				continue
			# the line to his head clears it: only his head shows
			var yh := lerpf(from.y, to.y + 0.7, tt)
			if near_target and yh > top + 0.05:
				best = minf(best, 0.2)
				continue
			return 0.0
		if pc["tall"]:
			if near_target:
				best = minf(best, 0.3)
			else:
				return 0.0
		elif near_target:
			best = minf(best, 0.45)
	# the ground: walk the line and see whether a hill (or a rampart) gets in the way
	if not hills.is_empty() or fort_side >= 0:
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


# ---------------------------------------------------------------- the close-quarters fields

## Adds a piece if it overlaps nothing in `out` (grown by `gap`) and stays out of `keep_clear`.
static func _try_add(out: Array, q: Array, gap: float, keep_clear: Array = []) -> bool:
	var rect := Rect2(float(q[0]) - float(q[2]) * 0.5, float(q[1]) - float(q[3]) * 0.5, float(q[2]), float(q[3]))
	for k in keep_clear:
		if (k as Rect2).intersects(rect):
			return false
	var grown := rect.grow(gap)
	for o in out:
		var ro := Rect2(float(o[0]) - float(o[2]) * 0.5, float(o[1]) - float(o[3]) * 0.5, float(o[2]), float(o[3]))
		if grown.intersects(ro):
			return false
	out.append(q)
	return true


## City: blocks of roofless houses (3.2 m - nobody sees over them) on a street grid; a church and
## a square in the middle; rubble and barricades staggered down every street so no street is a
## shooting gallery. The ends of the field are left open for forming up.
static func _city_pieces() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash("City")
	var out := []
	var xb := [[-54.0, -35.0], [-25.0, -5.0], [5.0, 25.0], [35.0, 54.0]]
	var zb := [[-64.0, -47.0], [-39.0, -21.0], [-13.0, 13.0], [21.0, 39.0], [47.0, 64.0]]
	for bi in xb.size():
		for bj in zb.size():
			var x0: float = xb[bi][0]
			var x1: float = xb[bi][1]
			var z0: float = zb[bj][0]
			var z1: float = zb[bj][1]
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			if bj == 2 and bi == 1:
				out.append([cx, cz, 14.0, 20.0, 3.4, "ruin"])   # the church
				continue
			if bj == 2 and bi == 2:
				# the square: a fountain, trees, a low wall at each end
				out.append([cx, cz, 3.0, 3.0, 1.0, "wall"])
				for t in [[-6.0, -8.0], [6.0, -8.0], [-6.0, 8.0], [6.0, 8.0]]:
					out.append([cx + t[0], cz + t[1], 1.0, 1.0, 5.0, "tree"])
				out.append([cx, z0 + 0.5, 12.0, 0.6, 1.0, "wall"])
				out.append([cx, z1 - 0.5, 12.0, 0.6, 1.0, "wall"])
				continue
			# two houses side by side with an alley between; now and then one is a heap of rubble
			var w := (x1 - x0 - 2.0) * 0.5
			for side in [-1.0, 1.0]:
				var hx: float = cx + float(side) * (w * 0.5 + 1.0)
				if r.randf() < 0.18:
					out.append([hx, cz, w * 0.6, 0.6, 1.0, "wall"])
					out.append([hx + r.randf_range(-2.0, 2.0), cz + r.randf_range(-4.0, 4.0), 3.2, 2.8, 1.9, "boulder"])
				else:
					out.append([hx, cz, w, z1 - z0, 3.2, "ruin"])
	# the streets: rubble (tall) and barricades (low), staggered so a street bends the line of sight
	for sx in [-30.0, 0.0, 30.0]:
		for zz in [-56.0, -30.0, -4.0, 20.0, 44.0]:
			var off := r.randf_range(-2.0, 2.0)
			if r.randf() < 0.5:
				out.append([sx + off, zz + r.randf_range(-4.0, 4.0), 3.0, 2.6, 1.9, "boulder"])
			else:
				out.append([sx + off * 0.5, zz + r.randf_range(-4.0, 4.0), 5.0, 0.6, 1.0, "wall"])
	for sz in [-43.0, -17.0, 17.0, 43.0]:
		for xx in [-44.0, -15.0, 15.0, 44.0]:
			if r.randf() < 0.6:
				out.append([xx + r.randf_range(-3.0, 3.0), sz + r.randf_range(-1.0, 1.0), 2.8, 2.4, 1.9, "boulder"])
	return out


## Suburb: rows of roofless houses (2.6 m) along lanes, each with a fenced back garden, side
## hedges and trees.
static func _suburb_pieces() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash("Suburb")
	var out := []
	for rz in [-56.0, -34.0, -12.0, 12.0, 34.0, 56.0]:
		var back: float = 1.0 if rz < 0.0 else -1.0   # gardens toward the middle of the field
		for hx in [-44.0, -22.0, 0.0, 22.0, 44.0]:
			if r.randf() < 0.15:
				continue
			var x: float = hx + r.randf_range(-3.0, 3.0)
			var z: float = rz + r.randf_range(-1.5, 1.5)
			out.append([x, z, 8.0, 7.0, 2.6, "ruin"])
			# the back garden: a fence across the bottom, a hedge down one side, a tree
			out.append([x, z + back * 9.0, 14.0, 0.4, 1.1, "fence"])
			if r.randf() < 0.6:
				var hs: float = 1.0 if r.randf() < 0.5 else -1.0
				out.append([x + hs * 7.5, z + back * 5.5, 0.4, 6.0, 1.1, "fence"])
			if r.randf() < 0.7:
				out.append([x + r.randf_range(-4.0, 4.0), z + back * 6.0, 1.0, 1.0, 5.0, "tree"])
	# odd trees and walls on the lanes
	for n in 14:
		for attempt in 20:
			var q := [r.randf_range(-50.0, 50.0), r.randf_range(-62.0, 62.0), 1.0, 1.0, 5.0, "tree"]
			if r.randf() < 0.35:
				q = [q[0], q[1], r.randf_range(5.0, 9.0), 0.6, 1.0, "wall"]
			if _try_add(out, q, 2.0):
				break
	return out


## River Crossing: two rivers across the field, eight metres wide, each with one bridge (on
## opposite flanks); stone parapets on the bridges; a mill at each bridgehead; woods, walls,
## rocks and ruins crowding both banks and the island between. The road to each bridge is kept
## clear enough to march down.
static func _river_pieces() -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash("River Crossing")
	var out := []
	var rivers := [[-26.0, 22.0], [26.0, -22.0]]   # [z, bridge x]
	var keep := []
	for rv in rivers:
		var rz: float = rv[0]
		var bx: float = rv[1]
		var gap := 6.0
		var left_w: float = (bx - gap * 0.5) - (-HALF_X - 2.0)
		var right_w: float = (HALF_X + 2.0) - (bx + gap * 0.5)
		out.append([-HALF_X - 2.0 + left_w * 0.5, rz, left_w, 8.0, 1.0, "water"])
		out.append([HALF_X + 2.0 - right_w * 0.5, rz, right_w, 8.0, 1.0, "water"])
		out.append([bx, rz, gap + 0.8, 8.0, 0.1, "deck"])
		out.append([bx - gap * 0.5 - 0.2, rz, 0.4, 7.6, 0.9, "wall"])   # parapets
		out.append([bx + gap * 0.5 + 0.2, rz, 0.4, 7.6, 0.9, "wall"])
		# a mill beside each bridgehead, one on each bank
		out.append([bx + 11.0, rz - 12.0, 8.0, 7.0, 2.8, "ruin"])
		out.append([bx - 11.0, rz + 12.0, 8.0, 7.0, 2.8, "ruin"])
		keep.append(Rect2(bx - 7.0, rz - 18.0, 14.0, 36.0))   # the bridge road
	# crowd everything else
	var kinds := [["tree", 46], ["boulder", 16], ["wall", 14], ["fence", 8], ["ruin", 6]]
	for kd in kinds:
		for n in int(kd[1]):
			for attempt in 40:
				var x := r.randf_range(-52.0, 52.0)
				var z := r.randf_range(-62.0, 62.0)
				if absf(absf(z) - 26.0) < 6.5:
					continue   # not in the river or on its very edge
				var q: Array
				match String(kd[0]):
					"tree":
						q = [x, z, 1.0, 1.0, 5.0, "tree"]
					"boulder":
						q = [x, z, r.randf_range(3.0, 4.0), r.randf_range(2.6, 3.2), r.randf_range(1.8, 2.1), "boulder"]
					"wall":
						var l := r.randf_range(7.0, 12.0)
						q = [x, z, l, 0.6, 1.0, "wall"] if r.randf() < 0.6 else [x, z, 0.6, l, 1.0, "wall"]
					"fence":
						var l2 := r.randf_range(7.0, 12.0)
						q = [x, z, l2, 0.4, 1.1, "fence"] if r.randf() < 0.6 else [x, z, 0.4, l2, 1.1, "fence"]
					_:
						q = [x, z, r.randf_range(6.0, 7.5), r.randf_range(4.5, 5.5), 2.6, "ruin"]
				if _try_add(out, q, 2.2, keep):
					break
	return out


# ---------------------------------------------------------------- finding a way round

const NAV_CELL := 2.0
var _nav: AStarGrid2D
var _nav_w := 0
var _nav_h := 0


## A walking grid over the field: a cell is closed if any piece (grown a little) touches it.
## Only asked when the straight way is blocked.
func _build_nav() -> void:
	_nav_w = int(HALF_X * 2.0 / NAV_CELL)
	_nav_h = int(HALF_Z * 2.0 / NAV_CELL)
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, _nav_w, _nav_h)
	_nav.cell_size = Vector2(NAV_CELL, NAV_CELL)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_nav.update()
	for pc in pieces:
		var rr: Rect2 = (pc["rect"] as Rect2).grow(0.3)
		var c0 := _nav_cell(rr.position)
		var c1 := _nav_cell(rr.end)
		for i in range(c0.x, c1.x + 1):
			for j in range(c0.y, c1.y + 1):
				var cr := Rect2(-HALF_X + i * NAV_CELL, -HALF_Z + j * NAV_CELL, NAV_CELL, NAV_CELL)
				if cr.intersects(rr):
					_nav.set_point_solid(Vector2i(i, j))


func _nav_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + HALF_X) / NAV_CELL), 0, _nav_w - 1), clampi(floori((p.y + HALF_Z) / NAV_CELL), 0, _nav_h - 1))


func _nav_centre(c: Vector2i) -> Vector2:
	return Vector2(-HALF_X + (c.x + 0.5) * NAV_CELL, -HALF_Z + (c.y + 0.5) * NAV_CELL)


func _nav_free(c: Vector2i) -> Vector2i:
	if not _nav.is_point_solid(c):
		return c
	for rad in range(1, 6):
		for i in range(-rad, rad + 1):
			for j in range(-rad, rad + 1):
				if absi(i) != rad and absi(j) != rad:
					continue
				var q := Vector2i(c.x + i, c.y + j)
				if q.x < 0 or q.y < 0 or q.x >= _nav_w or q.y >= _nav_h:
					continue
				if not _nav.is_point_solid(q):
					return q
	return c


## Can a man walk straight from a to b without meeting a piece?
func walk_clear(a: Vector2, b: Vector2) -> bool:
	for i in _pieces_on_segment(a, b):
		if _segment_hits_rect(a, b, (pieces[i]["rect"] as Rect2).grow(0.35)):
			return false
	return true


## Where to walk next on the way from `from` to `to`: `to` itself if the way is straight,
## otherwise the furthest point along the grid path that can be walked to straight.
func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if _nav == null or walk_clear(a, b):
		return to
	var ca := _nav_free(_nav_cell(a))
	var cb := _nav_cell(b)
	if _nav.is_point_solid(cb):
		# the goal is in the river (or a house): look for dry ground beyond it, the way he is
		# going, before settling for the nearest - which may be the bank he is standing on
		var d := (b - a).normalized()
		var found := false
		for k in range(1, 15):
			var q := _nav_cell(b + d * float(k))
			if not _nav.is_point_solid(q):
				cb = q
				found = true
				break
		if not found:
			cb = _nav_free(cb)
	if ca == cb:
		return to
	var path := _nav.get_id_path(ca, cb)
	if path.size() < 2:
		return to
	var best := _nav_centre(path[1])
	for k in range(1, mini(path.size(), 18)):
		var pk := _nav_centre(path[k])
		if walk_clear(a, pk):
			best = pk
		else:
			break
	return Vector3(best.x, height_at(best.x, best.y), best.y)


# ---------------------------------------------------------------- pieces by place

## Every piece listed in the 8 m cells its rect (grown a metre) touches, so a line of fire, a
## walk or a point only looks at the pieces near it - a City has some three hundred.
const BUCKET := 8.0
const BK_X0 := -64.0
const BK_Z0 := -108.0
var _bk_w := 0
var _bk_h := 0
var _buckets: Array = []
var _stamp := PackedInt32Array()
var _stamp_n := 0


func _build_buckets() -> void:
	_bk_w = int(-BK_X0 * 2.0 / BUCKET)
	_bk_h = int(-BK_Z0 * 2.0 / BUCKET)
	_buckets = []
	for k in _bk_w * _bk_h:
		_buckets.append(PackedInt32Array())
	for i in pieces.size():
		var r: Rect2 = (pieces[i]["rect"] as Rect2).grow(1.0)
		var i0 := clampi(floori((r.position.x - BK_X0) / BUCKET), 0, _bk_w - 1)
		var i1 := clampi(floori((r.end.x - BK_X0) / BUCKET), 0, _bk_w - 1)
		var j0 := clampi(floori((r.position.y - BK_Z0) / BUCKET), 0, _bk_h - 1)
		var j1 := clampi(floori((r.end.y - BK_Z0) / BUCKET), 0, _bk_h - 1)
		for j in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				var cell: PackedInt32Array = _buckets[j * _bk_w + ii]
				cell.append(i)
				_buckets[j * _bk_w + ii] = cell   # packed arrays are values: write it back
	_stamp.resize(pieces.size())
	_stamp.fill(0)
	_stamp_n = 0


func _pieces_at(p: Vector2) -> PackedInt32Array:
	if _bk_w == 0:
		return PackedInt32Array(range(pieces.size()))
	var i := clampi(floori((p.x - BK_X0) / BUCKET), 0, _bk_w - 1)
	var j := clampi(floori((p.y - BK_Z0) / BUCKET), 0, _bk_h - 1)
	return _buckets[j * _bk_w + i]


## Pieces listed in any cell a rect touches, each once, in piece order.
func _pieces_in(r: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _bk_w == 0:
		return PackedInt32Array(range(pieces.size()))
	_stamp_n += 1
	var i0 := clampi(floori((r.position.x - BK_X0) / BUCKET), 0, _bk_w - 1)
	var i1 := clampi(floori((r.end.x - BK_X0) / BUCKET), 0, _bk_w - 1)
	var j0 := clampi(floori((r.position.y - BK_Z0) / BUCKET), 0, _bk_h - 1)
	var j1 := clampi(floori((r.end.y - BK_Z0) / BUCKET), 0, _bk_h - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			for pi in _buckets[j * _bk_w + i]:
				if _stamp[pi] != _stamp_n:
					_stamp[pi] = _stamp_n
					out.append(pi)
	out.sort()
	return out


## Pieces listed in the cells a segment passes through (a grid walk), each once.
func _pieces_on_segment(a: Vector2, b: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	if _bk_w == 0:
		return PackedInt32Array(range(pieces.size()))
	_stamp_n += 1
	var x0 := (a.x - BK_X0) / BUCKET
	var y0 := (a.y - BK_Z0) / BUCKET
	var x1 := (b.x - BK_X0) / BUCKET
	var y1 := (b.y - BK_Z0) / BUCKET
	var ix := floori(x0)
	var iy := floori(y0)
	var ex := floori(x1)
	var ey := floori(y1)
	var dx := x1 - x0
	var dy := y1 - y0
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var tdx := absf(1.0 / dx) if dx != 0.0 else INF
	var tdy := absf(1.0 / dy) if dy != 0.0 else INF
	var tmx := ((float(ix + 1) - x0) if dx > 0.0 else (x0 - float(ix))) * tdx if dx != 0.0 else INF
	var tmy := ((float(iy + 1) - y0) if dy > 0.0 else (y0 - float(iy))) * tdy if dy != 0.0 else INF
	for guard in 200:
		if ix >= 0 and iy >= 0 and ix < _bk_w and iy < _bk_h:
			for pi in _buckets[iy * _bk_w + ix]:
				if _stamp[pi] != _stamp_n:
					_stamp[pi] = _stamp_n
					out.append(pi)
		if ix == ex and iy == ey:
			break
		if tmx < tmy:
			tmx += tdx
			ix += sx
		else:
			tmy += tdy
			iy += sy
	return out


## Every wall, fence rail and post, rock, tree, river, bridge, rim panel and deployment mark is
## its own mesh as built - several hundred on a built-up field, each a draw call on the web.
## Merge them: one opaque mesh (colours as vertex colours) and one for the glass rim. The
## colliders stay as they are.
func _bake_field() -> void:
	var parts := MeshBaker.collect(self, [_terrain_mi])
	var opaque := []
	var glass := []
	for p in parts:
		var c: Color = p[2]
		if c.a < 0.99:
			glass.append(p)
		else:
			opaque.append(p)
	var doomed := []
	_field_meshes(self, doomed)
	if not opaque.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = MeshBaker.build(opaque)
		add_child(mi)
	if not glass.is_empty():
		var gm := MeshBaker.build(glass)
		var gmat := StandardMaterial3D.new()
		gmat.vertex_color_use_as_albedo = true
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.surface_set_material(0, gmat)
		var gi := MeshInstance3D.new()
		gi.mesh = gm
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gi)
	for d in doomed:
		(d as MeshInstance3D).mesh = null
		if (d as Node).get_child_count() == 0:
			(d as Node).queue_free()


func _field_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c == _terrain_mi or c.has_meta("nobake"):
			continue
		_field_meshes(c, out)
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			out.append(c)


## The best rise within reach of p for a man who wants to shoot at the enemy at e: the highest
## ground that is no closer to the enemy than 40 m less than now, can see him, and stands a
## metre or more above where the man is. Men of one company spread along the crest by slot.
## Vector3.INF when there is no such rise (flat ground: stay put).
func high_spot(p: Vector3, e: Vector3, reach: float, slot: int) -> Vector3:
	if hills.is_empty():
		return Vector3.INF
	var here := height_at(p.x, p.z)
	var ed := Vector2(p.x - e.x, p.z - e.z).length()
	var best := Vector3.INF
	var best_s := -INF
	var step := 3.0
	var n := int(reach / step)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var q := Vector3(p.x + i * step, 0, p.z + j * step)
			var dd := Vector2(i * step, j * step).length()
			if dd > reach or not in_bounds(q, 2.0):
				continue
			q.y = height_at(q.x, q.z)
			if q.y < here + 1.0:
				continue
			var qe := Vector2(q.x - e.x, q.z - e.z).length()
			if qe < ed - 40.0 or qe < 35.0:
				continue
			if line_of_fire(q + Vector3(0, 1.6, 0), e + Vector3(0, 1.0, 0)) <= 0.0:
				continue
			var sc := q.y * 2.0 - dd * 0.12
			if sc > best_s:
				best_s = sc
				best = q
	if best == Vector3.INF:
		return best
	# spread along the crest, across the line of fire, by slot
	var across := Vector3(-(e.z - best.z), 0, e.x - best.x).normalized()
	var off := float((slot % 9) - 4) * 2.0
	var spread := best + across * off
	if in_bounds(spread, 2.0) and height_at(spread.x, spread.z) > here + 0.5:
		best = spread
	best = free_point(clamp_point(best))
	best.y = height_at(best.x, best.z)
	return best


## Is there river between a and b (a bridge deck is not a piece, so the way over it is clear)?
func water_between(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for i in _pieces_on_segment(a2, b2):
		if pieces[i]["kind"] == "water" and _segment_hits_rect(a2, b2, pieces[i]["rect"]):
			return true
	return false


## How far a man must walk from a to b: straight, unless a river is in the way, when it is the
## length of the way round by the bridge.
func walk_distance(a: Vector3, b: Vector3) -> float:
	var straight := Vector2(a.x - b.x, a.z - b.z).length()
	if _nav == null or not water_between(a, b):
		return straight
	var ca := _nav_free(_nav_cell(Vector2(a.x, a.z)))
	var cb := _nav_free(_nav_cell(Vector2(b.x, b.z)))
	var path := _nav.get_point_path(ca, cb)
	if path.size() < 2:
		return INF
	var d := 0.0
	for k in range(1, path.size()):
		d += path[k - 1].distance_to(path[k])
	return maxf(d, straight)


# ---------------------------------------------------------------- powder smoke

## Black powder makes a white cloud with every shot; a volley makes a bank of it. It hangs about
## three metres high, drifts on the wind and thins over half a minute or so. Kept as a grid of
## 4 m cells (density 1 = one shot's worth): a line of sight through it is dimmed, a man in it
## cannot be picked out, and a man aiming through it aims worse.
const SMOKE_CELL := 4.0
const SMOKE_HALF_LIFE := 22.0
var smoke := PackedFloat32Array()
var _sm_w := 0
var _sm_h := 0
var wind := Vector2.ZERO        # m/s, a new breeze each battle
var _sm_acc := 0.0
var smoke_rev := 0
var _sm_clear := true          # no smoke anywhere: every line is clear              # bumped when the cloud changes, for whoever draws it


func clear_smoke(rng: RandomNumberGenerator = null) -> void:
	_sm_w = int(ceil((HALF_X * 2.0 + 24.0) / SMOKE_CELL))
	_sm_h = int(ceil((HALF_Z * 2.0 + 24.0) / SMOKE_CELL))
	smoke = PackedFloat32Array()
	smoke.resize(_sm_w * _sm_h)
	var a := (rng.randf() if rng != null else randf()) * TAU
	var spd := (rng.randf_range(0.1, 1.6) if rng != null else 1.0)
	wind = Vector2(cos(a), sin(a)) * spd


func _sm_idx(x: float, z: float) -> int:
	var i := int(floor((x + HALF_X + 12.0) / SMOKE_CELL))
	var j := int(floor((z + HALF_Z + 12.0) / SMOKE_CELL))
	if i < 0 or j < 0 or i >= _sm_w or j >= _sm_h:
		return -1
	return j * _sm_w + i


## A shot's worth of smoke, a couple of metres in front of the muzzle.
func add_smoke(muzzle: Vector3, dir: Vector3, amount: float = 1.0) -> void:
	if smoke.is_empty():
		clear_smoke()
	var p := muzzle + Vector3(dir.x, 0, dir.z).normalized() * 2.5
	var k := _sm_idx(p.x, p.z)
	if k >= 0:
		smoke[k] = minf(smoke[k] + amount, 12.0)
		_sm_clear = false


## In still air the smoke hangs; a breeze carries it off. About 40 s calm, 25 s in a fresh breeze.
func smoke_half_life() -> float:
	return 18.0 + 30.0 / (1.0 + 2.0 * wind.length())


func smoke_at(x: float, z: float) -> float:
	if smoke.is_empty():
		return 0.0
	var k := _sm_idx(x, z)
	return smoke[k] if k >= 0 else 0.0


## Once a second: thin it, drift it downwind, let it spread a little.
func tick_smoke(delta: float) -> void:
	if smoke.is_empty():
		return
	_sm_acc += delta
	if _sm_acc < 1.0:
		return
	var dt := _sm_acc
	_sm_acc = 0.0
	var keep := pow(0.5, dt / smoke_half_life())
	var out := PackedFloat32Array()
	out.resize(smoke.size())
	# semi-Lagrangian drift: each cell takes what was upwind of it
	var sx := -wind.x * dt / SMOKE_CELL
	var sz := -wind.y * dt / SMOKE_CELL
	var any := false
	for j in _sm_h:
		for i in _sm_w:
			var fx := float(i) + sx
			var fz := float(j) + sz
			var i0 := int(floor(fx))
			var j0 := int(floor(fz))
			var tx := fx - i0
			var tz := fz - j0
			var v := 0.0
			for dj in 2:
				for di in 2:
					var ii := i0 + di
					var jj := j0 + dj
					if ii < 0 or jj < 0 or ii >= _sm_w or jj >= _sm_h:
						continue
					var w := (tx if di == 1 else 1.0 - tx) * (tz if dj == 1 else 1.0 - tz)
					v += smoke[jj * _sm_w + ii] * w
			v *= keep
			if v < 0.02:
				v = 0.0
			else:
				any = true
			out[j * _sm_w + i] = v
	# spread: a little to the neighbours
	if any:
		var spread := PackedFloat32Array(out)
		for j in range(1, _sm_h - 1):
			for i in range(1, _sm_w - 1):
				var k := j * _sm_w + i
				var nb := out[k - 1] + out[k + 1] + out[k - _sm_w] + out[k + _sm_w]
				spread[k] = out[k] * 0.8 + nb * 0.05
		out = spread
	smoke = out
	_sm_clear = not any
	smoke_rev += 1


## How much of a man can be made out from a to b through the smoke: 1 clear, toward 0 in a bank of it.
func visibility(a: Vector3, b: Vector3) -> float:
	if smoke.is_empty() or _sm_clear:
		return 1.0
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(int(d / SMOKE_CELL), 1)
	var sum := 0.0
	for k in range(0, steps + 1):
		var t := float(k) / steps
		sum += smoke_at(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
	sum *= d / float(steps + 1) / SMOKE_CELL   # cell-lengths of smoke the line passes through
	return exp(-0.22 * sum)


func smoke_size() -> Vector2i:
	return Vector2i(_sm_w, _sm_h)


func smoke_cell_centre(i: int, j: int) -> Vector2:
	return Vector2(-HALF_X - 12.0 + (i + 0.5) * SMOKE_CELL, -HALF_Z - 12.0 + (j + 0.5) * SMOKE_CELL)
