class_name MatchManager
extends Node
## Spawns the two battalions - several companies a side - runs a sergeant per company and a
## captain per side, keeps the score. A company's sergeant is its steadiest man still standing;
## what he "orders" is a blend of his own traits and his company's, and his men follow it only as
## far as their own traits take them - see soldier.gd. The captain only places companies,
## sends in the reserve and lets a rout in one company be felt by its neighbours.

signal match_started(match_index: int)
signal match_ended(result: Dictionary)

const MAX_SIZE := 20            # men in one company
const MAX_COMPANIES := 12      # a whole campaign army can go in at once
const EDIT_COMPANIES := 6      # what Edit Battalion builds for a single battle
const MAX_SIDE := 80            # men a side, all companies together
const CO_NAMES := ["A", "B", "C", "D", "E", "F"]
const SLOTS := ["Left", "Centre-left", "Centre-right", "Right", "Reserve"]
const SLOT_X := [37.5, 12.5, -12.5, -37.5, 0.0]   # from the side's own left (Red's left is +x)
const CAPTAIN_TICK := 1.0
## Battalion presets: [personality, type, slot] per company.
const BATTALIONS := {
	"Line battalion": [["Regulars", "Even", "Left"], ["Regulars", "Even", "Centre-left"], ["Regulars", "Even", "Centre-right"], ["Regulars", "Even", "Right"]],
	"Light battalion": [["Skirmishers", "Marksman", "Left"], ["Regulars", "Even", "Centre-left"], ["Regulars", "Even", "Centre-right"], ["Skirmishers", "Marksman", "Right"]],
	"Assault column": [["Regulars", "Even", "Left"], ["Shock", "Grenadier", "Centre-left"], ["Shock", "Grenadier", "Centre-right"], ["Regulars", "Even", "Right"]],
	"Mixed": [["Skirmishers", "Marksman", "Left"], ["Regulars", "Even", "Centre-left"], ["Regulars", "Even", "Centre-right"], ["Shock", "Grenadier", "Reserve"]],
	"Old guard": [["Veterans", "Ironside", "Left"], ["Veterans", "Ironside", "Centre-left"], ["Veterans", "Marksman", "Centre-right"], ["Skirmishers", "Marksman", "Right"]],
	"Your drills": [["Sniper", "Marksman", "Left"], ["Line", "Even", "Centre-left"], ["Linebreaker", "Grenadier", "Centre-right"], ["Ninjas", "Shinobi", "Right"]],
}
const BATTALION_HELP := {
	"Line battalion": "Four companies of regulars shoulder to shoulder across the front",
	"Light battalion": "Skirmishers on both flanks, a line in the centre",
	"Assault column": "Two storming companies in the centre, regulars holding the flanks",
	"Mixed": "A skirmish screen, two line companies, and a storming party in reserve",
	"Old guard": "Three companies of veterans and a screen of marksmen",
	"Your drills": "The owner's four drills, one company each: snipers on the left, Line and linebreakers in the centre, ninjas on the right",
}
const TEAM_NAMES := ["Red", "Blue"]
## How each company is told apart on the field: a pattern and an accent colour, by company index.
## pattern: sash | spots | stripes | bands | cross | chevron
const MARKS := [
	{"name": "white sash", "pattern": "sash", "color": Color(0.95, 0.95, 0.92)},
	{"name": "yellow spots", "pattern": "spots", "color": Color(0.98, 0.85, 0.2)},
	{"name": "black stripes", "pattern": "stripes", "color": Color(0.08, 0.08, 0.1)},
	{"name": "white sleeve bands", "pattern": "bands", "color": Color(0.95, 0.95, 0.92)},
	{"name": "gold cross-belts", "pattern": "cross", "color": Color(0.9, 0.7, 0.15)},
	{"name": "green chevrons", "pattern": "chevron", "color": Color(0.25, 0.75, 0.35)},
]


static func mark_for(c: int) -> Dictionary:
	return MARKS[c % MARKS.size()]


const TEAM_COLORS := [Color(0.8, 0.22, 0.2), Color(0.2, 0.35, 0.8)]
const SERGEANT_TICK := 0.5
const VOLLEY_COOLDOWN := 2.5

static var TEAM_SIZE := 20

var world: Node3D
var fx: BattleFx = null      # sound and blood; null in a headless run
var field: Field
var headless := false
var team_personalities: Array[Personality] = [Personality.preset("Regulars"), Personality.preset("Skirmishers")]
var team_preset_names: Array[String] = ["Regulars", "Skirmishers"]
var team_types: Array[SoldierType] = [SoldierType.preset("Even"), SoldierType.preset("Even")]
var team_type_names: Array[String] = ["Even", "Even"]
var team_sizes := [TEAM_SIZE, TEAM_SIZE]   # the SELECTED company's size, per side (see select_company)
## The battalions: per side, an Array of company dictionaries
## {name, size, persona: Personality, persona_name, type: SoldierType, type_name, slot}.
## team_personalities / team_types / team_sizes / *_names above are a view of the company the
## setup panel has selected (`sel`), so the one-company editor works unchanged on each company.
var companies: Array = [[], []]
var battalion_names := ["Your drills", "Line battalion"]
var sel := [0, 0]
var side_n := [0, 0]            # men fielded at the start, per side
var co_n := {}                  # ck -> men fielded at the start
var committed := {}             # ck -> x the reserve was sent to
var co_labels: Dictionary = {}  # ck -> Label3D over the company
var co_bars: Dictionary = {}    # ck -> [QuadMesh fill, starting men] - strength bar under the label
var team_drills: Array = [null, null]        # the SELECTED company's drill, per side (view, like team_personalities)
var drill_phase := {}                         # ck -> "set phase X" / "phase is X", per company
var stand_fast_until := {}                    # ck -> time the sergeant's "stand fast" runs to
var rule_tally := {}                          # ck -> {rule line -> ticks it decided}, this battle
var round_no := 0                             # campaign round, for "round N"
var _sgt_memory := {}                         # ck -> the drill's "for Ns" memory for that sergeant
var _plan: Dictionary = {}                    # this tick's sergeant plan from the drill
var plays := [General.CHOICE, General.CHOICE] # the play each side was given (or the general's choice)
var generals: Array = [null, null]            # General per side, this battle
var adapt := [true, true]                     # may the general change a given play during the battle
## Campaign rosters: per team, the men to field this round as records
## {name, seed, kills, rounds, recruit}. Empty means a fresh company of team_sizes[t].
var rosters: Array = [[], []]

var soldiers: Array[Soldier] = []
var orders: Array = [[], []]     # per side, one order dict per company
var sergeants: Dictionary = {}   # ck -> Soldier
var elapsed := 0.0
var time_limit := -1.0
var running := false
var match_index := 0
var rng := RandomNumberGenerator.new()
var stats := {}
var _tick := 0.0
var _spot_claims := {}   # "x,z" -> soldier
var _last_volley_t := {}   # ck -> time
var _volley_ids := {}
var _charge_since := {}
var _idle := {}
var _fired_at := {}          # ck -> when a man of the company last fired              # ck -> [since, shots, men]: a company doing nothing, and since when
var _exch := {}            # ck -> [hits given, hits taken] lately (decays)
var _last_harm_t := 0.0    # when anyone last hit anyone
const PURSUIT := 30.0       # seconds the winners may chase a broken enemy off the field
var pursuit_since := -1.0  # when one side broke (the pursuit), -1 before
var retreat_side := -1     # a side that has been ordered off the field
var retreat_since := 0.0
var _press_since := {}
var _fallback_since := {}
var _captain_tick := 0.0
var _fight_cache := [[], []]
var _fight_frame := -1
var _grid := {}
var _grid_frame := -1
var _alive_cache: Array[Soldier] = []
var _alive_n := [0, 0]
var _cache_frame := -1
var _hist_frame := -1


## Put the selected company of a side on a drill: its rules, and its dials as the personality
## everything else reads. The company itself is written by store_company.
func set_drill(t: int, drill_name: String) -> bool:
	var d := Drill.named(drill_name)
	if d == null:
		return false
	team_drills[t] = d
	team_personalities[t] = d.personality()
	team_preset_names[t] = d.name
	return true


## The rule tally of one company (created on first use).
func tally_for(t: int, c: int) -> Dictionary:
	var k := ck(t, c)
	if not rule_tally.has(k):
		rule_tally[k] = {}
	return rule_tally[k]


func _init() -> void:
	set_battalion(0, "Your drills")
	set_battalion(1, "Line battalion")


## A short name for what a side fielded: its preset if it still is one, else the companies.
func battalion_label(t: int) -> String:
	var cos: Array = companies[t]
	var spec: Array = BATTALIONS.get(battalion_names[t], [])
	if spec.size() == cos.size():
		var same := true
		for c in cos.size():
			var co: Dictionary = cos[c]
			if co["persona_name"] != spec[c][0] or co["type_name"] != spec[c][1] or co["slot"] != spec[c][2]:
				same = false
				break
		if same:
			return battalion_names[t]
	var parts := []
	for co in cos:
		parts.append(String(co["persona_name"]).substr(0, 4))
	return "/".join(parts)


static func ck(t: int, c: int) -> int:
	return t * MAX_COMPANIES + c


## A company fights by a drill; persona_name is the drill's name and persona its dials.
func new_company(t: int, c: int, persona_name: String, type_name: String, slot: String, size: int) -> Dictionary:
	var d := Drill.named(persona_name)
	return {"name": CO_NAMES[c] if c < CO_NAMES.size() else str(c + 1), "size": size,
		"drill": d, "persona": d.personality() if d != null else Personality.preset(persona_name),
		"persona_name": d.name if d != null else persona_name,
		"type": SoldierType.preset(type_name), "type_name": type_name, "slot": slot}


## Fill a side from a battalion preset, `per` men a company (or, with keep_sizes, companies that
## already exist keep their size). The company being edited stays selected.
func set_battalion(t: int, bname: String, per: int = 10, keep_sizes := false) -> void:
	var spec: Array = BATTALIONS.get(bname, BATTALIONS["Line battalion"])
	var old: Array = companies[t] if t < companies.size() and companies[t] is Array else []
	var cos := []
	for c in spec.size():
		var row: Array = spec[c]
		var n: int = int(old[c]["size"]) if keep_sizes and c < old.size() else per
		cos.append(new_company(t, c, row[0], row[1], row[2], n))
	companies[t] = cos
	battalion_names[t] = bname
	select_company(t, clampi(sel[t], 0, cos.size() - 1))


## Load a company into the one-company view the editor works on.
func select_company(t: int, c: int) -> void:
	var cos: Array = companies[t]
	c = clampi(c, 0, cos.size() - 1)
	sel[t] = c
	var co: Dictionary = cos[c]
	team_personalities[t] = co["persona"]
	team_preset_names[t] = co["persona_name"]
	team_drills[t] = co.get("drill")
	team_types[t] = co["type"]
	team_type_names[t] = co["type_name"]
	team_sizes[t] = co["size"]


## Write the view back into the selected company.
func store_company(t: int) -> void:
	var co: Dictionary = companies[t][sel[t]]
	co["persona"] = team_personalities[t]
	co["persona_name"] = team_preset_names[t]
	co["drill"] = team_drills[t]
	co["type"] = team_types[t]
	co["type_name"] = team_type_names[t]
	co["size"] = clampi(int(team_sizes[t]), 1, MAX_SIZE)


func side_total(t: int) -> int:
	var n := 0
	for co in companies[t]:
		n += int(co["size"])
	return n


func add_company(t: int) -> void:
	var cos: Array = companies[t]
	if cos.size() >= EDIT_COMPANIES:
		return
	var src: Dictionary = cos[sel[t]]
	var co := new_company(t, cos.size(), src["persona_name"], src["type_name"], "Reserve", mini(int(src["size"]), MAX_SIDE - side_total(t)))
	co["persona"] = (src["persona"] as Personality).jittered(rng, 0.0)
	co["type"] = (src["type"] as SoldierType).copy()
	if int(co["size"]) < 1:
		return
	cos.append(co)
	select_company(t, cos.size() - 1)


func remove_company(t: int) -> void:
	var cos: Array = companies[t]
	if cos.size() <= 1:
		return
	cos.remove_at(sel[t])
	for c in cos.size():
		cos[c]["name"] = CO_NAMES[c]
	select_company(t, mini(sel[t], cos.size() - 1))


## Where a company stands across the front: its slot's x in the side's own frame.
func band_x(t: int, c: int) -> float:
	if c >= (companies[t] as Array).size():
		return 0.0   # (asked about a company of the last battle while the next is being chosen)
	var k := ck(t, c)
	if committed.has(k):
		return committed[k]
	if (companies[t][c] as Dictionary).has("band"):
		return float(companies[t][c]["band"]) * (1.0 if t == 0 else -1.0)
	var slot: String = companies[t][c]["slot"]
	var i := SLOTS.find(slot)
	return SLOT_X[maxi(i, 0)] * (1.0 if t == 0 else -1.0)


func is_reserve(t: int, c: int) -> bool:
	return String(companies[t][c]["slot"]) == "Reserve" and not committed.has(ck(t, c))


func toward(t: int) -> float:
	return signf(-home_z(t))


func home_z(team: int) -> float:
	return -(Field.HALF_Z - 6.0) if team == 0 else (Field.HALF_Z - 6.0)


func start_match(seed_value: int = -1) -> void:
	clear()
	if fx != null:
		fx.clear()
	match_index += 1
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	field.clear_smoke(rng)
	elapsed = 0.0
	pursuit_since = -1.0
	retreat_side = -1
	stats = _fresh_stats()
	for t in 2:
		store_company(t)
		var roster: Array = rosters[t]
		var cos: Array = companies[t]
		orders[t] = []
		side_n[t] = 0
		var per_slot := {}
		for c in cos.size():
			var co: Dictionary = cos[c]
			var k := ck(t, c)
			# this company's men: its campaign records, or a fresh company of its size
			var recs := []
			for r in roster:
				if int(r.get("co", 0)) == c:
					recs.append(r)
			var n: int = recs.size() if not roster.is_empty() else clampi(int(co["size"]), 1, MAX_SIZE)
			co_n[k] = n
			side_n[t] += n
			var order := _blank_order(t, n)
			var reserve: bool = String(co["slot"]) == "Reserve"
			var stack: int = int(per_slot.get(co["slot"], 0))
			per_slot[co["slot"]] = stack + 1
			var z0: float = home_z(t) + toward(t) * (0.0 if reserve else 22.0) - toward(t) * (8.0 * stack + float(co.get("depth", 0.0)))
			order["line_z"] = z0
			order["rally_z"] = z0
			order["center_x"] = band_x(t, c)
			order["spacing"] = 1.2
			orders[t].append(order)
			_last_volley_t[k] = -100.0
			_volley_ids[k] = 0
			_charge_since[k] = -1.0
			_press_since[k] = -1.0
			_fallback_since[k] = -1.0
			_exch[k] = [0.0, 0.0]
			drill_phase[k] = ""
			stand_fast_until[k] = -1.0
			rule_tally[k] = {}
			_sgt_memory[k] = {}
			if n == 0:
				continue
			for i in n:
				var rec: Dictionary = recs[i] if not roster.is_empty() else {}
				var s := Soldier.new()
				s.team = t
				s.company = c
				s.team_color = TEAM_COLORS[t]
				s.soldier_name = rec.get("name", "%s%s %d" % [TEAM_NAMES[t][0], co["name"], i + 1])
				# a man's own quirks come from his seed, so a veteran is the same man every round
				var prng := RandomNumberGenerator.new()
				prng.seed = int(rec.get("seed", rng.randi()))
				s.personality = (co["persona"] as Personality).jittered(prng, 0.1)
				s.drill = co.get("drill")
				s.soldier_type = (co["type"] as SoldierType).jittered(prng, 0.02)
				s.kills = int(rec.get("kills", 0))
				s.rounds = int(rec.get("rounds", 0))
				s.record_seed = prng.seed
				s.manager = self
				s.field = field
				s.slot = i
				s.rng = RandomNumberGenerator.new()
				s.rng.seed = rng.randi()
				var x: float = band_x(t, c) + (float(i) - float(n - 1) * 0.5) * 1.2
				s.position = Vector3(x, field.height_at(x, z0), z0)
				s.rotation.y = 0.0 if t == 0 else PI
				s.fired.connect(_on_fired)
				s.damaged.connect(_on_damaged)
				s.died.connect(_on_died)
				s.routed.connect(_on_routed)
				s.rallied.connect(func(_m): stats["rallied"][_m.team] += 1)
				s.fled.connect(_on_fled)
				s.thrust.connect(_on_thrust)
				world.add_child(s)
				soldiers.append(s)
			if not headless:
				var lab := Label3D.new()
				lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lab.no_depth_test = true
				lab.fixed_size = true
				lab.pixel_size = LABEL_PX
				lab.font_size = 16
				lab.outline_size = 3
				lab.modulate = TEAM_COLORS[t].lightened(0.45)
				lab.text = String(co["name"])
				lab.position = Vector3(band_x(t, c), z0 + 5.0, z0)
				lab.position = Vector3(band_x(t, c), field.height_at(band_x(t, c), z0) + 5.0, z0)
				world.add_child(lab)
				co_labels[k] = lab
				# strength bar under the letter: starts full, shrinks as the company loses men
				var fill := _bar_quad(lab, Color(0.1, 0.1, 0.1, 0.75), BAR_W + 0.002, BAR_H + 0.002, 0.0, 0)
				fill = _bar_quad(lab, TEAM_COLORS[t].lightened(0.35), BAR_W, BAR_H, 0.0, 1)
				co_bars[k] = [fill, maxi(int(co.get("full", n)), n)]   # against full strength, not today's
	running = true
	for t in 2:
		generals[t] = General.new(t, String(plays[t]), bool(adapt[t]))
		generals[t].begin(self)
	match_started.emit(match_index)


func _blank_order(t: int, n: int) -> Dictionary:
	return {"rush": false, "mode": "advance", "line_z": home_z(t), "rally_z": home_z(t), "center_x": 0.0, "spacing": 1.0,
		"count": n, "volley_id": 0, "volley_age": 999.0, "alone": false, "sergeant": "", "press": false, "seek_cover": false}


func clear() -> void:
	for k in co_labels:
		if is_instance_valid(co_labels[k]):
			co_labels[k].queue_free()
	co_labels.clear()
	co_bars.clear()
	committed.clear()
	sergeants.clear()
	for s in soldiers:
		if is_instance_valid(s):
			if s.ragdoll != null and is_instance_valid(s.ragdoll):
				s.ragdoll.queue_free()
			s.queue_free()
	soldiers.clear()
	_spot_claims.clear()
	_last_volley_t = {}
	_charge_since = {}
	_idle = {}
	_fired_at = {}
	_fallback_since = {}
	_exch = {}
	_last_harm_t = 0.0
	_press_since = {}
	_fight_frame = -1
	_grid_frame = -1
	drill_phase = {}
	stand_fast_until = {}
	rule_tally = {}
	_sgt_memory = {}
	running = false
	_cache_frame = -1


func _fresh_stats() -> Dictionary:
	return {
		"shots": [0, 0], "hits": [0, 0], "kills": [[0, 0, 0], [0, 0, 0]],   # kills[t] = [rifle, bayonet, grenade]
		"volleys": [0, 0], "charges": [0, 0], "fallbacks": [0, 0], "routed": [0, 0], "rallied": [0, 0], "own_kills": [0, 0], "grenade_kills": [0, 0], "fled": [0, 0],
		"friendly": [0, 0], "thrusts": [0, 0], "thrust_hits": [0, 0], "wounds": [0, 0],
	}


# ---------------------------------------------------------------- queries the men use

func alive_soldiers() -> Array[Soldier]:
	var f := Engine.get_physics_frames()
	if f == _cache_frame:
		return _alive_cache
	_cache_frame = f
	_alive_cache = []
	_alive_n = [0, 0]
	for s in soldiers:
		if s.alive and not s.gone:
			_alive_cache.append(s)
			_alive_n[s.team] += 1
	return _alive_cache


## Men still in the fight: alive, on the field, and not running for the rear.
func fighting(team: int) -> Array[Soldier]:
	# asked for hundreds of times a frame with a battalion a side: worked out once per frame
	var f := Engine.get_physics_frames()
	if f != _fight_frame:
		_fight_frame = f
		var a: Array[Soldier] = []
		var b: Array[Soldier] = []
		for s in alive_soldiers():
			if not s.is_routed:
				if s.team == 0:
					a.append(s)
				else:
					b.append(s)
		_fight_cache = [a, b]
	return _fight_cache[team]


func fighting_company(team: int, c: int) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in fighting(team):
		if s.company == c:
			out.append(s)
	return out


## Losses of one company, against the men it fielded.
func company_losses(t: int, c: int) -> float:
	var n: int = int(co_n.get(ck(t, c), 0))
	if n == 0:
		return 1.0
	var a := 0
	for s in alive_soldiers():
		if s.team == t and s.company == c:
			a += 1
	return 1.0 - float(a) / float(n)


## Counted once a frame with the living (every man asks it for his courage, every frame).
func alive_count(team: int) -> int:
	alive_soldiers()
	return _alive_n[team]


func loss_fraction(team: int) -> float:
	var n: int = side_n[team]
	return 1.0 - float(alive_count(team)) / maxf(float(n), 1.0)


## Neighbour words: does another company of this side, standing within 45 m of this one,
## charge / fall back / have the enemy within 60 m / break (half or more of it routed or gone)?
const NEIGHBOUR_RANGE := 45.0
func neighbour_sense(id: String, t: int, c: int) -> bool:
	var mine: Dictionary = orders[t][c] if c < (orders[t] as Array).size() else {}
	var here: Vector3 = mine.get("centre", Vector3(band_x(t, c), 0, home_z(t)))
	for c2 in (orders[t] as Array).size():
		if c2 == c:
			continue
		var o: Dictionary = orders[t][c2]
		if not o.has("centre"):
			continue
		var there: Vector3 = o["centre"]
		if Vector2(there.x - here.x, there.z - here.z).length() > NEIGHBOUR_RANGE:
			continue
		var fighting_n := fighting_company(t, c2).size()
		match id:
			"neighbour_broken":
				if fighting_n * 2 <= int(co_n.get(ck(t, c2), 0)):
					return true
			"neighbour_charging":
				if fighting_n > 0 and String(o.get("mode", "")) == "charge":
					return true
			"neighbour_falling_back":
				if fighting_n > 0 and String(o.get("mode", "")) == "fallback":
					return true
			"neighbour_engaged":
				if fighting_n > 0 and float(o.get("nearest_d", INF)) <= 60.0:
					return true
	return false


## Rank words: the companies of my side in a rank ahead of mine (nearer the enemy) are in it -
## charging, fighting hand to hand or within 25 m - or are firing; or those behind me are firing.
func rank_sense(id: String, t: int, c: int) -> bool:
	var my_d := float(companies[t][c].get("depth", 0.0)) if c < (companies[t] as Array).size() else 0.0
	for c2 in (companies[t] as Array).size():
		if c2 == c or fighting_company(t, c2).is_empty() or is_reserve(t, c2):
			continue
		var d2 := float(companies[t][c2].get("depth", 0.0))
		var o: Dictionary = orders[t][c2]
		var fired_lately := elapsed - float(_fired_at.get(ck(t, c2), -100.0)) < 6.0
		match id:
			"rank_ahead_engaged":
				if d2 < my_d and (String(o.get("mode", "")) == "charge" or float(o.get("nearest_d", INF)) <= 25.0):
					return true
			"rank_ahead_firing":
				if d2 < my_d and fired_lately:
					return true
			"rank_behind_firing":
				if d2 > my_d and fired_lately:
					return true
	return false


## The enemy company nearest me is busy with another of my companies (closer to it than I am,
## within 25 m of it): its flank or back is mine to take.
func enemy_engaged_elsewhere(t: int, c: int) -> bool:
	var here: Vector3 = orders[t][c].get("centre", Vector3(band_x(t, c), 0, home_z(t)))
	var best := -1
	var best_d := INF
	for ec in (orders[1 - t] as Array).size():
		var eo: Dictionary = orders[1 - t][ec]
		if not eo.has("centre") or fighting_company(1 - t, ec).is_empty():
			continue
		var d := (eo["centre"] as Vector3).distance_to(here)
		if d < best_d:
			best_d = d
			best = ec
	if best < 0:
		return false
	var nd := float(orders[1 - t][best].get("nearest_d", INF))
	return nd <= 25.0 and best_d > nd + 10.0


## Men of theirs running within `r` metres of this company.
func enemy_broken_near(t: int, c: int, r: float) -> bool:
	var here: Vector3 = orders[t][c].get("centre", Vector3(band_x(t, c), 0, home_z(t)))
	var n := 0
	for s in alive_soldiers():
		if s.team != t and s.is_routed and not s.gone and s.global_position.distance_to(here) < r:
			n += 1
			if n >= 2:
				return true
	return false


## For a man's courage: like strength_ratio, but his own side's routed men count half.
func morale_ratio(team: int) -> float:
	var f := fighting(team).size()
	var mine := float(f) + 0.5 * float(alive_count(team) - f)
	return mine / maxf(float(fighting(1 - team).size()), 1.0)


func strength_ratio(team: int) -> float:
	var mine := fighting(team).size()
	var theirs := fighting(1 - team).size()
	return float(mine) / maxf(float(theirs), 1.0)


func nearest_enemy(s: Soldier) -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for o in alive_soldiers():
		if o.team == s.team:
			continue
		var d := o.global_position.distance_squared_to(s.global_position)
		# a man who has broken is a poorer target than one still fighting, unless he is close
		if o.is_routed:
			d *= 1.6
		if d >= best_d:
			continue
		# fog of war: a man not yet noticed - far off, still, hidden, stealthy - is not there
		var nr := o.notice_range()
		# ... and a man looking ahead does not see what is behind him: only close (a step, a
		# breath) or when it makes itself known (a shot, the clash of a fight, a man running)
		if nr < 250.0 and not s.in_melee and not s.is_routed and s.is_behind_me(o):
			nr = minf(nr, 6.0)
		if o.global_position.distance_squared_to(s.global_position) > nr * nr:
			continue
		best_d = d
		best = o
	return best


## How many of s's own side stand within r of a point (a grenade thrower checks his own men).
func friends_near(s: Soldier, at: Vector3, r: float) -> int:
	var n := 0
	for o in fighting(s.team):
		if o != s and o.global_position.distance_to(at) < r:
			n += 1
	return n


## A grenade bursts (a black-powder bomb: more noise and fright than slaughter): within 1.5 m
## some go down, out to 3 m a few; everyone within 9 m is shaken;
## a thick cloud of smoke; one loud bang.
func grenade_burst(at: Vector3, thrower: Soldier) -> void:
	for o in alive_soldiers():
		var d := o.global_position.distance_to(at)
		if d < 3.0 and rng.randf() < (0.3 if d < 1.5 else 0.08):
			o.take_damage(999.0, "grenade", thrower)
		elif d < 9.0:
			o.fear = minf(o.fear + 0.25 * (1.0 - d / 9.0) + 0.05, 0.6)
			o.under_fire = true
			if d < 5.0:
				o.stun(rng.randf_range(2.0, 4.0) * (1.0 - d / 6.0))   # knocked flat, ears ringing
	for i in 6:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 6.0)
		field.add_smoke(at + Vector3(0, 0.5, 0) - dir * 2.5 + dir * rng.randf_range(0.0, 2.0), dir, 2.5)
	if fx != null:
		fx.blast(at)


## The nearest enemy still in the fight, noticed or not (where the company knows them to be).
func nearest_enemy_any(s: Soldier) -> Soldier:
	var best: Soldier = null
	var best_d := INF
	for o in fighting(1 - s.team):
		var d := o.global_position.distance_squared_to(s.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## The nearest enemy within rifle range who is not locked in a melee.
func nearest_clear_enemy(s: Soldier) -> Soldier:
	var best: Soldier = null
	var best_d := Soldier.MAX_RANGE * Soldier.MAX_RANGE
	for o in fighting(1 - s.team):
		if o.in_melee:
			continue
		var d := o.global_position.distance_squared_to(s.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## A friend near the path a miss at `enemy` would fly on along - beyond the target, out to `reach` m.
func friend_beyond(s: Soldier, enemy: Soldier, reach: float) -> Soldier:
	var a := s.global_position
	var ab := enemy.global_position - a
	ab.y = 0.0
	var len := ab.length()
	if len < 0.5:
		return null
	var dir := ab / len
	for o in alive_soldiers():
		if o.team != s.team or o == s:
			continue
		var ao := o.global_position - a
		ao.y = 0.0
		var along := ao.dot(dir)
		if along <= len or along > len + reach:
			continue
		# the spread of a miss widens with the distance past the target
		if (ao - dir * along).length() < 1.5 + 0.15 * (along - len):
			return o
	return null


## A friend standing within a shoulder of the line of fire, closer than the target.
func friend_in_line(s: Soldier, enemy: Soldier) -> Soldier:
	var a := s.global_position
	var b := enemy.global_position
	var ab := b - a
	ab.y = 0.0
	var len := ab.length()
	if len < 0.5:
		return null
	var dir := ab / len
	for o in alive_soldiers():
		if o == s or o.team != s.team:
			continue
		var ao := o.global_position - a
		ao.y = 0.0
		var along := ao.dot(dir)
		if along < 0.6 or along > len - 0.5:
			continue
		var side := (ao - dir * along).length()
		if side < 0.55 and not o.kneeling:
			return o
		if side < 0.3:
			return o
	return null


## The first man - either side - standing near the ball's path beyond the target.
func stray_victim(s: Soldier, from: Vector3, to: Vector3) -> Soldier:
	var dir := to - from
	dir.y = 0.0
	var len := dir.length()
	if len < 0.5:
		return null
	dir /= len
	var best: Soldier = null
	var best_along := INF
	for o in alive_soldiers():
		if o == s:
			continue
		var ao := o.global_position - from
		ao.y = 0.0
		var along := ao.dot(dir)
		if along < len + 0.5 or along > Soldier.MAX_RANGE + 40.0:
			continue
		var side := (ao - dir * along).length()
		if side < 0.7 and along < best_along:
			best_along = along
			best = o
	return best


## Push away from men standing too close (both sides), so a line keeps its interval and a
## melee is a scrum rather than a stack.
func separation(s: Soldier) -> Vector3:
	var push := Vector3.ZERO
	var p := s.global_position
	# a 4 m grid, rebuilt once a frame: a man only looks at the nine cells round him
	var f := Engine.get_physics_frames()
	if f != _grid_frame:
		_grid_frame = f
		_grid = {}
		for o in alive_soldiers():
			var key := Vector2i(floori(o.global_position.x / 4.0), floori(o.global_position.z / 4.0))
			if not _grid.has(key):
				_grid[key] = []
			_grid[key].append(o)
	var cx := floori(p.x / 4.0)
	var cz := floori(p.z / 4.0)
	var near := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			near.append_array(_grid.get(Vector2i(cx + dx, cz + dz), []))
	for o: Soldier in near:
		if o == s:
			continue
		var d := p - o.global_position
		d.y = 0.0
		var l := d.length()
		if l < 0.75 and l > 0.001:
			push += d / l * (0.75 - l) * 2.5
	return push


## How far this man is ahead (toward the enemy) of the mean of his fighting mates.
func ahead_of_line(s: Soldier) -> float:
	var men := fighting_company(s.team, s.company)
	if men.size() < 2:
		return 0.0
	var z := 0.0
	for m in men:
		z += m.global_position.z
	z /= men.size()
	return (s.global_position.z - z) * signf(-home_z(s.team))


func claim_spot(s: Soldier, spot: Dictionary) -> bool:
	var key := "%.1f,%.1f" % [(spot["pos"] as Vector3).x, (spot["pos"] as Vector3).z]
	var holder = _spot_claims.get(key)
	if holder == null or not is_instance_valid(holder) or not holder.alive or holder.gone or holder == s:
		# drop this man's old claim
		for k in _spot_claims.keys():
			if _spot_claims[k] == s:
				_spot_claims.erase(k)
		_spot_claims[key] = s
		return true
	return false


# ---------------------------------------------------------------- the company labels

const LABEL_PX := 0.0008      # company label: world units per font pixel, at fixed screen size
const BAR_W := 0.028          # strength bar, same fixed-size units as the label
const BAR_H := 0.0035
const BAR_Y := -0.013         # below the letter


## A flat billboard quad that keeps its size on screen, drawn over everything, as a child of `lab`.
func _bar_quad(lab: Node3D, col: Color, w: float, h: float, x: float, prio: int) -> QuadMesh:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	q.center_offset = Vector3(x, BAR_Y, 0)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.no_depth_test = true
	m.render_priority = prio
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lab.add_child(mi)
	return q


const MODE_GLYPH := {"advance": "»", "hold": "=", "at_will": "=", "charge": "»»", "fallback": "«"}


func _process(_delta: float) -> void:
	if not running or co_labels.is_empty():
		return
	for t in 2:
		# what the side sounds like: drums while it marches up, talk in the ranks while the enemy is far off
		var side_cen := Vector3.ZERO
		var side_n := 0
		var marching := false
		var near_d := INF
		for c in (companies[t] as Array).size():
			var k := ck(t, c)
			if not co_labels.has(k):
				continue
			var lab: Label3D = co_labels[k]
			var men := fighting_company(t, c)
			if men.is_empty():
				lab.visible = false
				continue
			var cen := Vector3.ZERO
			var top := -INF
			for m in men:
				cen += m.global_position
				top = maxf(top, m.global_position.y)
			cen /= men.size()
			side_cen += cen
			side_n += 1
			near_d = minf(near_d, float(orders[t][c].get("nearest_d", INF)))
			if String(orders[t][c].get("mode", "")) == "advance" and not is_reserve(t, c):
				marching = true
			lab.visible = true
			lab.position = Vector3(cen.x, top + 4.0, cen.z)
			var mode: String = orders[t][c].get("mode", "")
			var glyph: String = "·" if is_reserve(t, c) else MODE_GLYPH.get(mode, "")
			lab.text = "%s %s %s" % [companies[t][c]["name"], String(companies[t][c]["type_name"]), glyph]
			if co_bars.has(k):
				var q: QuadMesh = co_bars[k][0]
				var frac: float = clampf(float(men.size()) / maxf(float(co_bars[k][1]), 1.0), 0.0, 1.0)
				q.size.x = BAR_W * frac
				q.center_offset = Vector3(-BAR_W * (1.0 - frac) * 0.5, BAR_Y, 0)
		if fx != null:
			# the drums beat the advance until the first shot; then it is the guns' turn
			var shooting: bool = not stats.is_empty() and int(stats["shots"][0]) + int(stats["shots"][1]) > 0
			fx.side_state(t, side_cen / maxf(side_n, 1), side_n > 0 and marching and near_d > 45.0 and not shooting,
				side_n > 0 and near_d > 90.0)


# ---------------------------------------------------------------- the sergeants

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	field.tick_smoke(delta)
	for t in 2:
		for c in (orders[t] as Array).size():
			orders[t][c]["volley_age"] = elapsed - float(_last_volley_t.get(ck(t, c), -100.0))
	_tick -= delta
	if _tick <= 0.0:
		_tick = SERGEANT_TICK
		for t in 2:
			for c in (orders[t] as Array).size():
				_run_sergeant(t, c)
	_captain_tick -= delta
	if _captain_tick <= 0.0:
		_captain_tick = CAPTAIN_TICK
		for t in 2:
			_run_captain(t)
	# the fight is over when one side has nobody left standing on the field
	var f0 := fighting(0).size()
	var f1 := fighting(1).size()
	if retreat_side >= 0 and (alive_count(retreat_side) == 0 or elapsed - retreat_since >= PURSUIT):
		end_match("%s retreats from the field" % TEAM_NAMES[retreat_side], 1 - retreat_side)
		return
	if f0 > 0 and f1 > 0:
		pursuit_since = -1.0   # (the broken side has rallied: the battle is on again)
	if f0 == 0 and f1 == 0:
		end_match("mutual rout")
	elif f0 == 0 or f1 == 0:
		# one side has broken. The battle is won, but its men are still running for the back of
		# the field, and the winners go after them: the pursuit lasts until the last of them is
		# off the field (or killed), or PURSUIT seconds
		var lost := 0 if f0 == 0 else 1
		if pursuit_since < 0.0:
			pursuit_since = elapsed
		var running_n := alive_count(lost)
		if running_n == 0 or elapsed - pursuit_since >= PURSUIT:
			end_match("%s broken" % TEAM_NAMES[lost])
	elif time_limit > 0.0 and elapsed >= time_limit:
		end_match("time")
	elif elapsed > 120.0 and elapsed - _last_harm_t > 45.0:
		# nobody has hurt anybody for over a minute: the day is decided on harm done
		end_match("stalemate")


## The line's mind. Traits are the sergeant's own blended half-and-half with his men's mean,
## so a company of cowards with one iron sergeant still holds better than one without him.
func _run_sergeant(t: int, c: int) -> void:
	var k := ck(t, c)
	var men := fighting_company(t, c)
	var order: Dictionary = orders[t][c]
	order["count"] = maxi(men.size(), 1)
	order["alone"] = men.size() <= 2
	if men.is_empty():
		return
	# pick the sergeant and hand out slots left-to-right by current x, so the line doesn't cross
	var sgt: Soldier = null
	var best := -1.0
	for m in men:
		var v := m.p("discipline") + m.p("nerve")
		if v > best:
			best = v
			sgt = m
	if sergeants.get(k) != sgt:
		sergeants[k] = sgt
		order["sergeant"] = sgt.soldier_name
	var sorted := men.duplicate()
	sorted.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	for i in sorted.size():
		sorted[i].slot = i
	var mix := {}
	for tr in Personality.TRAITS:
		var mean := 0.0
		for m in men:
			mean += m.p(tr)
		mean /= men.size()
		mix[tr] = 0.5 * sgt.p(tr) + 0.5 * mean
	var enemies := fighting(1 - t)
	if enemies.is_empty():
		enemies = []
		for s in alive_soldiers():
			if s.team != t:
				enemies.append(s)
	var centre := Vector3.ZERO
	for m in men:
		centre += m.global_position
	centre /= men.size()
	# the enemy this company faces: the ten men of theirs nearest to it, not the whole battalion
	var by_d := []
	for e in enemies:
		by_d.append([e.global_position.distance_squared_to(centre), e])
	by_d.sort_custom(func(a, b): return a[0] < b[0])
	var near_e := []
	for i in mini(10, by_d.size()):
		near_e.append(by_d[i][1])
	var enemy_centre := Vector3.ZERO
	var nearest_d := INF
	for e in near_e:
		enemy_centre += e.global_position
		nearest_d = minf(nearest_d, e.global_position.distance_to(centre))
	if not near_e.is_empty():
		enemy_centre /= near_e.size()
	var toward := signf(-home_z(t))   # +1 for red (marching +z), -1 for blue
	var loaded_frac := 0.0
	var in_range := 0
	var engage: float = 68.0 - 42.0 * float(mix["patience"])
	# can the line see the enemy at all? A hill between them and there is nothing to hold for
	var seen := true
	if not near_e.is_empty() and not field.hills.is_empty() and nearest_d < Soldier.MAX_RANGE + 10.0:
		seen = false
		var eye := Vector3(0, Soldier.EYE_HEIGHT, 0)
		for e in near_e:
			if field.line_of_fire(sgt.global_position + eye, e.global_position + Vector3(0, 1.0, 0)) > 0.0:
				seen = true
				break
		if not seen:
			for m in men:
				if m == sgt:
					continue
				if field.line_of_fire(m.global_position + eye, enemy_centre + Vector3(0, 1.0, 0)) > 0.0:
					seen = true
					break
	if not seen:
		nearest_d = INF   # out of sight is out of range: the line goes and finds them
	# how far they are on foot: across a river it is the way round by the bridge - the rifle
	# reaches over the water, the bayonet does not
	var reach_d := nearest_d
	if not near_e.is_empty() and nearest_d < INF:
		reach_d = field.walk_distance(centre, (near_e[0] as Soldier).global_position)
		for e in near_e:
			if not field.water_between(centre, e.global_position):
				reach_d = minf(reach_d, e.global_position.distance_to(centre))
	for m in men:
		if m.loaded:
			loaded_frac += 1.0
		if not enemies.is_empty() and m.global_position.distance_to(enemy_centre) <= engage:
			in_range += 1
	loaded_frac /= men.size()

	order["spacing"] = 0.8 + (1.0 - mix["cohesion"]) * 3.0
	# the line's centre creeps toward the enemy's, a sergeant with cohesion keeps it together
	# ... within its own stretch of the front: the captain gives each company a band
	var bx := band_x(t, c)
	order["center_x"] = lerpf(order["center_x"], clampf(enemy_centre.x if not near_e.is_empty() else bx, bx - 15.0, bx + 15.0), 0.06)

	var mean_courage := 0.0
	for m in men:
		mean_courage += m.courage
	mean_courage /= men.size()
	var losses := loss_fraction(t)
	# what the neighbours read of this company: where it is and how close the enemy is
	order["centre"] = centre
	order["seen"] = seen
	order["nearest_d"] = nearest_d
	order["reach_d"] = reach_d

	# --- the exchange: a sergeant can count. Taking two balls for every one he gives while
	# the enemy sits behind walls is a firefight lost, and standing in it is not a plan.
	_exch[k][0] *= 0.98
	_exch[k][1] *= 0.98
	var given: float = _exch[k][0]
	var taken: float = _exch[k][1]
	var losing_fire: bool = not enemies.is_empty() and taken >= 2.0 * given + 2.0 and nearest_d < engage + 15.0
	# ... and if nobody has hurt anybody for a while, somebody has to go and find the enemy
	var stalled: bool = not enemies.is_empty() and elapsed > 30.0 and elapsed - _last_harm_t > 25.0 and nearest_d > 22.0
	var pressing: bool = _press_since[k] >= 0.0
	if pressing and (nearest_d < 22.0 or enemies.is_empty()):
		_press_since[k] = -1.0
		pressing = false
	if stalled and not pressing and mix["aggression"] >= 0.15:
		_press_since[k] = elapsed
		pressing = true

	# --- the reserve stands where it was put until the captain sends it in, or the enemy comes to it
	if is_reserve(t, c):
		if nearest_d <= engage:
			committed[k] = clampf(centre.x, -Field.HALF_X + 10.0, Field.HALF_X - 10.0)
		else:
			order["mode"] = "hold"
			return

	# --- the drill: the sergeant's rules make a plan; whatever the plan leaves out, the engine decides
	_plan = {}
	var drill: Drill = companies[t][c].get("drill")
	if drill != null and not drill.sergeant_rules.is_empty():
		var ctx := {"t": t, "co": c, "men": men, "enemies": near_e, "nearest_d": nearest_d, "losses": company_losses(t, c),
			"loaded_frac": loaded_frac, "courage": mean_courage, "seen": seen, "centre": centre,
			"enemy_centre": enemy_centre}
		drill.run(drill.sergeant_rules, func(id: String, args: Array) -> bool: return _sgt_sense(id, args, ctx),
			func(id: String, args: Array) -> bool: return _sgt_act(id, args, ctx), _sgt_memory[k], elapsed, tally_for(t, c))
		if _plan.get("press", false) and not pressing:
			_press_since[k] = elapsed
			pressing = true

	# --- mode
	var mode: String = order["mode"]
	if _plan.has("mode"):
		mode = _plan_mode(t, c, mode, centre, toward, enemies)
	elif mode == "charge":
		# the charge runs until the enemy is broken off or the blood cools
		if enemies.is_empty() or reach_d > 40.0 or (elapsed - _charge_since[k] > 25.0 and reach_d > 6.0):
			mode = "advance"
	elif mode == "fallback":
		var rallied := absf(centre.z - order["rally_z"]) < 6.0
		if rallied and (loaded_frac > 0.6 or elapsed - _fallback_since[k] > 20.0):
			mode = "hold"
	if not _plan.has("mode") and mode != "charge" and mode != "fallback":
		# fall back: losses or a bad exchange, and a sergeant with the nerve to admit it
		var break_point: float = 0.25 + 0.5 * float(mix["nerve"])
		if losses > break_point and mean_courage < 0.45 and mix["aggression"] < 0.75 and nearest_d < 40.0:
			mode = "fallback"
			order["rally_z"] = clampf(centre.z - toward * 22.0, -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
			_fallback_since[k] = elapsed
			stats["fallbacks"][t] += 1
		else:
			# the charge: close enough, and either the volley is just gone or the fight is going our way
			var charge_range: float = 12.0 + 32.0 * float(mix["aggression"])
			var just_volleyed: bool = elapsed - float(_last_volley_t[k]) < 4.0
			var ratio := strength_ratio(t)
			if losing_fire:
				# the bayonet decides what the rifle cannot: a sergeant with any blood in him
				# closes, and a shy one either finds a wall of his own or gets out of range
				charge_range += 20.0
			if not enemies.is_empty() and reach_d < charge_range and mix["aggression"] > (0.2 if losing_fire else 0.35) \
				and (just_volleyed or loaded_frac < 0.35 or mix["aggression"] > 0.85 or losing_fire) \
				and ratio > (0.4 if losing_fire else 0.5 + (1.0 - mix["aggression"]) * 0.6):
				mode = "charge"
				_charge_since[k] = elapsed
				_press_since[k] = -1.0
				stats["charges"][t] += 1
				if fx != null:
					fx.charge(centre)
			elif losing_fire and mix["aggression"] <= 0.2 and mix["cover"] < 0.5:
				mode = "fallback"
				order["rally_z"] = clampf(centre.z - toward * 25.0, -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
				_fallback_since[k] = elapsed
				stats["fallbacks"][t] += 1
			elif losing_fire and mix["aggression"] > 0.2:
				mode = "advance"
				if not pressing:
					_press_since[k] = elapsed
					pressing = true
			elif not enemies.is_empty() and nearest_d <= engage and not pressing:
				mode = "hold"
			else:
				mode = "advance"
	# --- the cartridge boxes: a company mostly shot out cannot stand and trade fire - it fixes
	# bayonets and goes in while it is still strong enough, or goes back out of range
	var empty := 0
	for m in men:
		if m.ammo <= 0 and not m.loaded:
			empty += 1
	order["shot_out"] = empty * 2 >= men.size()
	order["withdraw"] = false
	if retreat_side == t:
		# the retreat is ordered: off the back of the field, every company
		if mode != "fallback":
			_fallback_since[k] = elapsed
		mode = "fallback"
		order["withdraw"] = true
		order["shot_out"] = true   # (no play overrides it)
		order["rally_z"] = home_z(t) * 1.15
	elif empty * 2 >= men.size() and not enemies.is_empty() and mode != "charge":
		# assault only when it can carry: close and not outnumbered, or bayonet men still strong,
		# or the enemy breaking; otherwise a company with nothing to shoot leaves the field
		var ratio := strength_ratio(t)
		var steel := General._bayonet(String(companies[t][c].get("type_name", "")))
		var breaking := enemy_broken_near(t, c, 60.0)
		if breaking or (reach_d < 60.0 and ratio >= 0.75) or (steel and reach_d < 120.0 and ratio >= 0.6):
			mode = "charge"
			_charge_since[k] = elapsed
			stats["charges"][t] += 1
			if fx != null:
				fx.charge(centre)
		else:
			if mode != "fallback":
				_fallback_since[k] = elapsed
				stats["fallbacks"][t] += 1
			mode = "fallback"
			order["withdraw"] = true
			order["rally_z"] = home_z(t) * 1.15   # off the back of the field
	# --- the captain's eye: a whole company standing about - not firing, not hit, nobody near -
	# for forty seconds is sent forward, whatever its drill had it doing
	var fired := 0
	for m in men:
		fired += m.shots
	var idl: Array = _idle.get(k, [elapsed, fired, men.size()])
	if fired != int(idl[1]) or men.size() != int(idl[2]) or nearest_d < 45.0 or mode == "charge" or is_reserve(t, c):
		idl = [elapsed, fired, men.size()]
	_idle[k] = idl
	order["sent_up"] = false
	var idle_limit := 40.0
	if generals[t] != null and String((generals[t] as General).play) in ["Hold and receive", "Feint and draw"]:
		idle_limit = 90.0   # waiting is the plan
	if elapsed - float(idl[0]) > idle_limit and (mode == "fallback" or mode == "hold"):
		mode = "advance"
		order["sent_up"] = true
	# --- the general's play, over the drill: go together, wait, swing round, all in at once
	if generals[t] != null:
		var before := mode
		mode = (generals[t] as General).mode_for(self, c, mode, order)
		if mode == "charge" and before != "charge" and String(order["mode"]) != "charge":
			_charge_since[k] = elapsed
			_press_since[k] = -1.0
			stats["charges"][t] += 1
			if fx != null:
				fx.charge(centre)
		elif mode == "fallback" and before != "fallback" and String(order["mode"]) != "fallback":
			_fallback_since[k] = elapsed
			stats["fallbacks"][t] += 1
	order["mode"] = mode
	order["press"] = pressing and mode == "advance"
	# the rush: the enemy is close (inside 90 m) and the companies facing us have not fired a shot yet
	var rush := false
	if mode == "advance" and nearest_d < 90.0 and nearest_d > 15.0:
		rush = true
		for e in near_e:
			if _fired_at.has(ck((e as Soldier).team, (e as Soldier).company)):
				rush = false
				break
	order["rush"] = rush
	order["seek_cover"] = losing_fire or _plan.get("seek_cover", false)
	order["hold_fire"] = _plan.get("hold_fire", false)
	if _plan.has("spacing"):
		order["spacing"] = _plan["spacing"]
	if _plan.has("wheel"):
		order["center_x"] = clampf(float(order["center_x"]) + float(_plan["wheel"]) * toward * 1.5, bx - 20.0, bx + 20.0)
	if mode == "charge":
		# a line coming on with the bayonet is a fearful thing before it ever arrives
		for e in enemies:
			var close := 0
			for m in men:
				if m.charging and m.global_position.distance_to(e.global_position) < 15.0:
					close += 1
			if close >= 3:
				e.under_fire = true
				# ... and loose order cannot receive one: a man with nobody at his elbow
				# feels three bayonets as thirty
				var loose: float = 1.0 + 2.5 * e.alone
				e.fear = minf(e.fear + 0.03 * (1.0 - 0.5 * e.p("nerve")) * loose, 0.6 + 0.35 * e.alone)

	# --- where the line stands
	match mode:
		"advance":
			var step: float = 1.4 * SERGEANT_TICK * (0.6 + 0.8 * float(mix["aggression"]))
			if _plan.has("speed"):
				step = 1.4 * SERGEANT_TICK * float(_plan["speed"])
			# close and they have not fired yet: run the last of the ground before their first volley
			if order["rush"]:
				step *= 2.5
			var target_z: float = order["line_z"] + toward * step
			# a sergeant halts the line on a wall he can reach before the enemy does, once it is
			# a wall to fire from (any sergeant, near the enemy; a cover-minded one sooner)
			# - unless the line is pressing in, when walls are for after the volley at twenty paces
			if (mix["cover"] > 0.45 or nearest_d < engage + 60.0) and not pressing:
				var wall_z := _cover_row_ahead(t, order["line_z"], engage, enemy_centre)
				if not is_nan(wall_z) and (target_z - wall_z) * toward > 0.0:
					target_z = wall_z
			order["line_z"] = clampf(target_z, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
		"hold":
			# keep the range: if the enemy pulls back out of reach, follow at the walk
			if _plan.get("rally", false):
				pass   # stand exactly here
			elif not seen and not enemies.is_empty():
				# a hill between us and them: holding behind it is hiding, not holding - up to the crest
				order["line_z"] += toward * 1.2 * SERGEANT_TICK
			elif not enemies.is_empty() and (nearest_d > engage + 8.0 or pressing) and not _plan.has("mode"):
				order["line_z"] += toward * 1.0 * SERGEANT_TICK
			# ... and a hot-blooded sergeant still edges in
			elif mix["aggression"] > 0.6 and nearest_d > 20.0:
				order["line_z"] += toward * 0.5 * SERGEANT_TICK
		"fallback":
			order["line_z"] = order["rally_z"]
		"charge":
			# going in with the bayonet: the men run at whoever is near; while the enemy is still
			# out of reach the line itself keeps coming on, ten metres ahead of where it is
			if enemies.is_empty() or reach_d > 40.0:
				order["line_z"] = clampf(centre.z + toward * 10.0, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
			else:
				order["line_z"] = centre.z

	if generals[t] != null:
		(generals[t] as General).place(self, c, order)

	# --- the order of battle: a rear rank keeps behind the front rank while the front rank stands
	var my_depth := float(companies[t][c].get("depth", 0.0))
	if my_depth > 0.0 and mode != "charge" and mode != "fallback":
		var lead := INF
		for c2 in (companies[t] as Array).size():
			if c2 == c or is_reserve(t, c2) or fighting_company(t, c2).is_empty():
				continue
			if float(companies[t][c2].get("depth", 0.0)) < my_depth and (orders[t][c2] as Dictionary).has("centre"):
				var z2: float = (orders[t][c2]["centre"] as Vector3).z * toward
				lead = minf(lead, z2) if lead < INF else z2
		if lead < INF:
			var cap: float = (lead - (my_depth - 0.0) * 0.8) * toward
			if (float(order["line_z"]) - cap) * toward > 0.0:
				order["line_z"] = cap

	# --- the volley: enough men loaded and in range, and it's been a moment since the last
	if mode != "charge" and mode != "fallback" and not enemies.is_empty() and not _plan.get("hold_fire", false):
		var ready := 0
		var reach: float = float(_plan.get("volley_at", engage + 10.0))
		for m in men:
			if m.loaded and m.global_position.distance_to(enemy_centre) <= reach:
				ready += 1
		var need: float = float(_plan.get("volley_need", 0.45 + 0.4 * float(mix["discipline"])))
		var cooldown: float = VOLLEY_COOLDOWN + 4.0 * mix["patience"]
		if _plan.get("by_halves", false):
			# by halves: each half fires on its own word, so half the line is always loaded
			need *= 0.5
			cooldown *= 0.5
		order["by_halves"] = _plan.get("by_halves", false)
		if _plan.get("volley_now", false) and float(ready) / men.size() >= 0.3 and elapsed - _last_volley_t[k] > 1.5:
			_call_volley(t, c)
		elif float(ready) / men.size() >= need and elapsed - _last_volley_t[k] > cooldown:
			_call_volley(t, c)
		elif _plan.get("at_will", false) or (not _plan.has("volley_at") and not _plan.has("volley_need") and mix["discipline"] < 0.35):
			order["mode"] = "at_will" if mode == "hold" else mode


# ---------------------------------------------------------------- the drill's words, for a sergeant

## Sensors every drill word shares, man or sergeant; null if the id is not one of them.
## `c` is the asking company: the exchange, the phase and "my losses" are that company's own.
func shared_sense(id: String, args: Array, t: int, c: int, r: RandomNumberGenerator) -> Variant:
	var k := ck(t, c)
	match id:
		"always":
			return true
		"losing_exchange":
			return _exch[k][1] >= 2.0 * _exch[k][0] + 2.0
		"winning_exchange":
			return _exch[k][0] >= 2.0 * _exch[k][1] + 2.0
		"no_harm_for":
			return elapsed - _last_harm_t > float(args[0])
		"time_over":
			return elapsed > float(args[0])
		"round_is":
			return round_no == int(args[0])
		"field_open":
			return field != null and field.pieces.size() <= 8
		"field_thick":
			return field != null and field.pieces.size() >= 14
		"field_is":
			return field != null and field.layout_name.to_lower() == String(args[0]).to_lower()
		"phase_is":
			return String(drill_phase.get(k, "")) == String(args[0])
		"chance":
			return r.randf() < float(args[0])
		"losses_over":
			return company_losses(t, c) > float(args[0])
		"enemy_losses_over":
			return loss_fraction(1 - t) > float(args[0])
		"enemy_outnumbers":
			return strength_ratio(t) < 1.0 - (float(args[0]) if not args.is_empty() else 0.0) - 0.001
		"we_outnumber":
			return strength_ratio(t) > 1.0 + (float(args[0]) if not args.is_empty() else 0.0) + 0.001
		"enemy_broken":
			var alive_e := alive_count(1 - t)
			return alive_e == 0 or float(fighting(1 - t).size()) / float(alive_e) < 0.5
		"neighbour_charging", "neighbour_falling_back", "neighbour_engaged", "neighbour_broken":
			return neighbour_sense(id, t, c)
		"rank_ahead_engaged", "rank_ahead_firing", "rank_behind_firing":
			return rank_sense(id, t, c)
		"enemy_engaged_elsewhere":
			return enemy_engaged_elsewhere(t, c)
		"enemy_broken_nearby":
			return enemy_broken_near(t, c, 50.0)
		"mates_running":
			# two in five of my own side are routed: the line is going
			var own_n := 0
			var own_r := 0
			for s in alive_soldiers():
				if s.team == t:
					own_n += 1
					if s.is_routed:
						own_r += 1
			return own_n > 0 and float(own_r) / float(own_n) >= 0.4
		"enemy_breaking":
			var n := 0
			var r_n := 0
			for s in alive_soldiers():
				if s.team != t:
					n += 1
					if s.is_routed:
						r_n += 1
			return n > 0 and float(r_n) / float(n) >= 0.2
		"enemy_loaded_under":
			var n := 0
			var l := 0
			for s in fighting(1 - t):
				n += 1
				if s.loaded:
					l += 1
			return n > 0 and float(l) / float(n) < float(args[0])
		"frac_loaded":
			var n := 0
			var l := 0
			for s in fighting(t):
				n += 1
				if s.loaded:
					l += 1
			return n > 0 and float(l) / float(n) >= float(args[0])
	return null


func _sgt_sense(id: String, args: Array, c: Dictionary) -> bool:
	var t: int = c["t"]
	var co: int = c["co"]
	var shared: Variant = shared_sense(id, args, t, co, rng)
	if shared != null:
		return shared
	var men: Array = c["men"]
	var enemies: Array = c["enemies"]
	var nd: float = c["nearest_d"]
	match id:
		"enemy_within":
			return nd <= float(args[0])
		"enemy_beyond":
			return nd > float(args[0])
		"enemy_charging":
			# any company of theirs among the men this company faces has gone in with the bayonet
			if nd >= 50.0:
				return false
			for e in enemies:
				if (e.charging or String(orders[1 - t][e.company].get("mode", "")) == "charge") \
						and not field.water_between(e.global_position, c["centre"]):
					return true   # a charge with a river in front of it is no charge at all
			return false
		"enemy_in_cover":
			var k := 0
			for e in enemies:
				if e.kneeling or e.action == "cover":
					k += 1
			return not enemies.is_empty() and float(k) / enemies.size() >= 0.4
		"in_smoke":
			var cc: Vector3 = c["centre"]
			return field.smoke_at(cc.x, cc.z) >= 2.0
		"enemy_in_smoke":
			var ec: Vector3 = c["enemy_centre"]
			return not enemies.is_empty() and field.smoke_at(ec.x, ec.z) >= 2.0
		"smoke_between":
			return not enemies.is_empty() and field.visibility((c["centre"] as Vector3) + Vector3(0, 1.6, 0), (c["enemy_centre"] as Vector3) + Vector3(0, 1.0, 0)) < 0.5
		"wind_behind":
			var fwd: Vector3 = (c["enemy_centre"] as Vector3) - (c["centre"] as Vector3) if not enemies.is_empty() else Vector3(0, 0, -signf(home_z(t)))
			return field.wind.length() > 0.3 and field.wind.normalized().dot(Vector2(fwd.x, fwd.z).normalized()) > 0.4
		"enemy_uphill":
			return (c["enemy_centre"] as Vector3).y - (c["centre"] as Vector3).y > 1.5
		"enemy_downhill", "high_ground":
			return (c["centre"] as Vector3).y - (c["enemy_centre"] as Vector3).y > 1.5
		"enemy_visible":
			return c["seen"]
		"enemy_hidden":
			return not c["seen"]
		"enemy_reloading":
			# the enemy this company faces (its ten nearest men), half or more of them empty
			var n_e := 0
			var l_e := 0
			for e in enemies:
				if e.is_routed:
					continue
				n_e += 1
				if e.loaded:
					l_e += 1
			return n_e > 0 and float(l_e) / float(n_e) < 0.5
		"spotted":
			# a company is spotted when a third of the enemy men within 90 m are looking its way
			if not bool(c["seen"]):
				return false
			var cen: Vector3 = c["centre"]
			var near_n := 0
			var facing_n := 0
			for en in enemies:
				var to_c: Vector3 = cen - en.global_position
				to_c.y = 0.0
				var dc: float = to_c.length()
				if dc > 90.0 or dc < 0.01:
					continue
				near_n += 1
				if en.facing_dir().dot(to_c / dc) > 0.34:
					facing_n += 1
			return near_n > 0 and float(facing_n) / float(near_n) >= 0.3
		"loaded":
			return float(c["loaded_frac"]) >= 0.5
		"in_cover", "kneeling":
			var k := 0
			for m in men:
				if m.kneeling:
					k += 1
			return float(k) / maxf(men.size(), 1) >= 0.5
		"tired", "winded", "wounded":
			var k := 0
			for m in men:
				if (id == "tired" and m.tired()) or (id == "winded" and m.breath > 0.0) or (id == "wounded" and m.wounded):
					k += 1
			return float(k) / maxf(men.size(), 1) >= (0.3 if id == "wounded" else 0.5)
		"courage_under":
			return float(c["courage"]) < float(args[0])
		"out_of_ammo", "ammo_under":
			# the company: half its men empty (out of ammo), or its mean rounds left under N
			var k := 0
			var rounds := 0.0
			for m in men:
				rounds += m.ammo
				if m.ammo <= 0 and not m.loaded:
					k += 1
			if id == "out_of_ammo":
				return float(k) / maxf(men.size(), 1) >= 0.5
			return rounds / maxf(men.size(), 1) < float(args[0])
		"alone":
			return men.size() <= 2
		"volley_called":
			return float(orders[t][co].get("volley_age", 999.0)) < 0.7
		"mode_is":
			return String(orders[t][co].get("mode", "")) == Soldier._mode_word(String(args[0]))
		"charging":
			return String(orders[t][co].get("mode", "")) == "charge"
	return false


func _sgt_act(id: String, args: Array, c: Dictionary) -> bool:
	var t: int = c["t"]
	var k := ck(t, int(c["co"]))
	var enemies: Array = c["enemies"]
	match id:
		"advance", "advance_slow", "advance_fast":
			_plan["mode"] = "advance"
			_plan["speed"] = 0.6 if id == "advance_slow" else (1.6 if id == "advance_fast" else 1.0)
			return true
		"hold":
			_plan["mode"] = "hold"
			return true
		"rally":
			_plan["mode"] = "hold"
			_plan["rally"] = true
			return true
		"charge":
			if enemies.is_empty():
				return false
			_plan["mode"] = "charge"
			return true
		"fallback":
			_plan["mode"] = "fallback"
			_plan["fall_dist"] = float(args[0]) if not args.is_empty() else 22.0
			return true
		"press":
			_plan["mode"] = "advance"
			_plan["press"] = true
			return true
		"find_cover":
			_plan["seek_cover"] = true
			return true
		"form_tight":
			_plan["spacing"] = 0.8
			return true
		"form_open":
			_plan["spacing"] = 2.2
			return true
		"form_skirmish":
			_plan["spacing"] = 4.0
			return true
		"volley_halves":
			_plan["by_halves"] = true
			return true
		"volley_at":
			_plan["volley_at"] = float(args[0])
			return true
		"volley_when":
			_plan["volley_need"] = float(args[0])
			return true
		"volley_now":
			_plan["volley_now"] = true
			return true
		"at_will":
			_plan["at_will"] = true
			return true
		"hold_fire":
			_plan["hold_fire"] = true
			return true
		"wheel_left":
			_plan["wheel"] = 1.0
			return true
		"wheel_right":
			_plan["wheel"] = -1.0
			return true
		"stand_fast":
			stand_fast_until[k] = elapsed + SERGEANT_TICK + 0.1
			return true
		"set_phase":
			drill_phase[k] = String(args[0])
			return true
	return false


## The mode the plan asks for, with the bookkeeping a change of mode needs.
func _plan_mode(t: int, c: int, current: String, centre: Vector3, toward: float, enemies: Array) -> String:
	var k := ck(t, c)
	var want: String = _plan["mode"]
	if want == "charge" and current != "charge":
		_charge_since[k] = elapsed
		_press_since[k] = -1.0
		stats["charges"][t] += 1
		if fx != null:
			fx.charge(centre)
	elif want == "fallback" and current != "fallback":
		orders[t][c]["rally_z"] = clampf(centre.z - toward * float(_plan.get("fall_dist", 22.0)), -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
		_fallback_since[k] = elapsed
		stats["fallbacks"][t] += 1
	return want


## The z of the nearest low wall or fence row between the line and the engagement distance,
## on the near side of it; NAN if there is none.
func _cover_row_ahead(t: int, line_z: float, engage: float, enemy_centre: Vector3) -> float:
	var toward := signf(-home_z(t))
	var best := NAN
	var best_d := INF
	for pc in field.pieces:
		if pc["tall"] or pc["kind"] == "water":
			continue
		var r: Rect2 = pc["rect"]
		if r.size.x < 4.0:
			continue   # only long rows can hold a line
		var z := r.get_center().y - toward * (r.size.y * 0.5 + 0.9)
		var ahead := (z - line_z) * toward
		if ahead < -1.0:
			continue
		if absf(enemy_centre.z - z) < 12.0:
			continue   # the enemy is already on it
		if absf(enemy_centre.z - z) > engage + 6.0:
			continue   # too far back to fire from; the line would stand there for nothing
		if ahead < best_d:
			best_d = ahead
			best = z
	return best


func _call_volley(t: int, c: int) -> void:
	var k := ck(t, c)
	_last_volley_t[k] = elapsed
	_volley_ids[k] = int(_volley_ids.get(k, 0)) + 1
	orders[t][c]["volley_id"] = _volley_ids[k]
	orders[t][c]["volley_half"] = (_volley_ids[k] % 2) if orders[t][c].get("by_halves", false) else -1
	orders[t][c]["volley_age"] = 0.0
	stats["volleys"][t] += 1
	if fx != null:
		# the sergeant's word, then the crash of it
		var at: Vector3 = orders[t][c].get("centre", Vector3(band_x(t, c), 0, home_z(t)))
		fx.sergeant(at)
		get_tree().create_timer(0.35).timeout.connect(func(): if fx != null: fx.volley(at))


# ---------------------------------------------------------------- events

## The shock of a volley: balls arriving together frighten the men around the mark, hit or
## miss, far more than the same balls one at a time. Only shots fired on the word count.
func volley_pressure(shooter: Soldier, mark: Vector3, hit: bool) -> void:
	var o: Dictionary = orders[shooter.team][shooter.company]
	if float(o.get("volley_age", 999.0)) > 1.2:
		return
	for s in alive_soldiers():
		if s.team == shooter.team:
			continue
		var d := s.global_position.distance_to(mark)
		if d < 5.0:
			s.under_fire = true
			s.fear = minf(s.fear + (0.05 if hit else 0.025) * (1.0 - d / 5.0) + 0.01, 0.6)


func _on_fired(s: Soldier, victim: Soldier, hit: bool) -> void:
	stats["shots"][s.team] += 1
	_fired_at[ck(s.team, s.company)] = elapsed
	if hit and victim.team != s.team:
		stats["hits"][s.team] += 1
		_exch[ck(s.team, s.company)][0] += 1.0
		_exch[ck(victim.team, victim.company)][1] += 1.0
		_last_harm_t = elapsed
	elif hit:
		stats["friendly"][s.team] += 1


func _on_damaged(s: Soldier, amount: float, _source: String, _attacker: Soldier) -> void:
	if amount < Soldier.MAX_HP and s.alive:
		stats["wounds"][s.team] += 1


func _on_died(s: Soldier, source: String, attacker: Soldier) -> void:
	if attacker != null and attacker.team != s.team:
		stats["kills"][attacker.team][1 if source == "bayonet" else (2 if source == "grenade" else 0)] += 1
		if source == "grenade":
			stats["grenade_kills"][attacker.team] += 1
	elif attacker != null:
		stats["own_kills"][s.team] += 1   # a stray ball from his own side
	for o in alive_soldiers():
		if o.team == s.team:
			o.notice_death(s.global_position)
	for k in _spot_claims.keys():
		if _spot_claims[k] == s:
			_spot_claims.erase(k)


func _on_routed(s: Soldier) -> void:
	stats["routed"][s.team] += 1
	# a rout is felt by the next company along: men of other companies within 40 m see it go
	for o in fighting(s.team):
		if o.company != s.company and o.global_position.distance_to(s.global_position) < 40.0:
			o.fear = minf(o.fear + 0.05 * (1.0 - 0.5 * o.p("nerve")), 0.6)


## The captain: every second, sends the reserve where the line is going worst - or where it is
## going best, if he has the blood for it - and keeps the company labels over their men.
func _run_captain(t: int) -> void:
	if generals[t] != null:
		(generals[t] as General).tick(self)
	var cos: Array = companies[t]
	var agg := 0.0
	for co in cos:
		agg += (co["persona"] as Personality).get_trait("aggression")
	agg /= maxf(cos.size(), 1)
	for c in cos.size():
		if not is_reserve(t, c) or fighting_company(t, c).is_empty():
			continue
		# the worst-off company in the line, and the best
		var worst := -1
		var worst_l := 0.0
		for o in cos.size():
			if o == c or is_reserve(t, o):
				continue
			var l := company_losses(t, o)
			if fighting_company(t, o).is_empty():
				l = 1.0
			if l > worst_l:
				worst_l = l
				worst = o
		var trigger := 0.45 - 0.25 * agg   # an eager captain sends it in sooner
		# the enemy is running: the held-back company goes after them
		var run_x := 0.0
		var run_n := 0
		for e in alive_soldiers():
			if e.team != t and e.is_routed and not e.gone:
				run_x += e.global_position.x
				run_n += 1
		if run_n >= 4:
			committed[ck(t, c)] = clampf(run_x / run_n, -Field.HALF_X + 8.0, Field.HALF_X - 8.0)
			continue
		# the enemy is locked in hand-to-hand with our line: go in now, while they are busy, not after
		var busy_x := 0.0
		var busy_n := 0
		for e in alive_soldiers():
			if e.team != t and e.in_melee and not e.is_routed:
				busy_x += e.global_position.x
				busy_n += 1
		if busy_n >= 6:
			committed[ck(t, c)] = clampf(busy_x / busy_n, -Field.HALF_X + 8.0, Field.HALF_X - 8.0)
			continue
		if worst >= 0 and worst_l >= trigger:
			committed[ck(t, c)] = band_x(t, worst)
		elif elapsed > 90.0 and agg > 0.6 and strength_ratio(t) > 1.3:
			committed[ck(t, c)] = 0.0   # the day is going our way: finish it


func _on_fled(s: Soldier) -> void:
	stats["fled"][s.team] += 1


func _on_thrust(s: Soldier, landed: bool) -> void:
	stats["thrusts"][s.team] += 1
	if landed:
		stats["thrust_hits"][s.team] += 1


## Which rule decided how often, per side, by drill: [{drill name: {line: ticks}}, ...].
## Companies on the same drill add together.
func _tally_summary() -> Array:
	var out := [{}, {}]
	for t in 2:
		for c in (companies[t] as Array).size():
			var d: Drill = companies[t][c].get("drill")
			if d == null:
				continue
			var per: Dictionary = out[t].get(d.name, {})
			var tl: Dictionary = rule_tally.get(ck(t, c), {})
			for ln in tl:
				per[ln] = int(per.get(ln, 0)) + int(tl[ln])
			out[t][d.name] = per
	return out


func _types_label(t: int) -> String:
	var parts := []
	for co in companies[t]:
		parts.append(String(co["type_name"]).substr(0, 4))
	return "/".join(parts)


## Each side's companies as fielded: for the results panels.
func _company_summary() -> Array:
	var out := [[], []]
	for t in 2:
		for c in (companies[t] as Array).size():
			var co: Dictionary = companies[t][c]
			out[t].append({"name": co["name"], "persona": co["persona_name"], "type": co["type_name"], "slot": co["slot"],
				"size": int(co_n.get(ck(t, c), co["size"]))})
	return out


## A side gives up the field: every company marches off the back of it, and the enemy has
## PURSUIT seconds to do what damage he can before the battle (and the ground) is his.
func retreat(t: int) -> void:
	if running and retreat_side < 0:
		retreat_side = t
		retreat_since = elapsed
		if fx != null:
			fx.bugle()


func end_match(reason: String, forced_winner: int = -1) -> void:
	if not running:
		return
	running = false
	var f := [fighting(0).size(), fighting(1).size()]
	var a := [alive_count(0), alive_count(1)]
	var winner := -1
	if forced_winner >= 0:
		winner = forced_winner
	elif f[0] > 0 and f[1] == 0:
		winner = 0
	elif f[1] > 0 and f[0] == 0:
		winner = 1
	elif reason == "time" or reason == "stalemate":
		# on the clock, the ground decides: the side whose line stands further into the
		# enemy's country holds the field. A company that only ever gives ground has lost it.
		# Harm done breaks a tie.
		var g := [0.0, 0.0]
		for t in 2:
			var men := fighting(t)
			for m in men:
				g[t] += m.global_position.z * signf(-home_z(t))   # metres past the centre line, toward the enemy
			g[t] = g[t] / maxf(float(men.size()), 1.0)
		var s0: int = stats["kills"][0][0] + stats["kills"][0][1] + stats["kills"][0][2]
		var s1: int = stats["kills"][1][0] + stats["kills"][1][1] + stats["kills"][1][2]
		if absf(g[0] - g[1]) > 4.0:
			winner = 0 if g[0] > g[1] else 1
			reason += ", " + ("Red" if winner == 0 else "Blue") + " holds the ground"
		elif s0 != s1:
			winner = 0 if s0 > s1 else 1
	var per := []
	for s in soldiers:
		per.append({"name": s.soldier_name, "team": s.team, "alive": s.alive, "routed": s.is_routed, "gone": s.gone,
			"seed": s.record_seed, "rounds": s.rounds, "career_kills": s.kills,
			"shots": s.shots, "hits": s.hits, "kills": s.kills - s.kills_before, "bayonet_kills": s.bayonet_kills, "grenade_kills": s.grenade_kills,
			"thrusts": s.thrusts, "thrust_hits": s.thrust_hits, "dmg": s.dmg_done, "hp": s.hp,
			"persona": s.personality.label(), "type": s.soldier_type.label(), "company": s.company})
	var result := {"match": match_index, "winner": winner, "winner_name": TEAM_NAMES[winner] if winner >= 0 else "Draw",
		"reason": reason, "duration": elapsed, "alive": a, "fighting": f, "stats": stats.duplicate(true),
		"sizes": side_n.duplicate(), "soldiers": per, "companies": _company_summary(),
		"presets": [battalion_label(0), battalion_label(1)], "types": [_types_label(0), _types_label(1)],
		"tally": _tally_summary(),
		"plays": [generals[0].play if generals[0] != null else "", generals[1].play if generals[1] != null else ""]}
	match_ended.emit(result)


## The order of battle: every company takes a rank - Front, Line or Back (or is Held back by the
## captain) - by its own choice or, left to "Auto", by its type: bayonet men in front, shooters
## behind, the rest between. Each rank spreads across the whole front (up to eight abreast, more
## stack behind), the ranks ten metres apart. Four or fewer companies all in one rank keep the
## old left / centre / right slots.
const RANKS := ["Auto", "Front", "Line", "Back", "Held back"]
const RANK_DEPTH := {"Front": 0.0, "Line": 10.0, "Back": 20.0, "Held back": 0.0}


static func default_rank(type_name: String) -> String:
	match type_name:
		"Brawler", "Grenadier", "Ironside", "Shinobi":
			return "Front"
		"Marksman", "Scout":
			return "Back"
	return "Line"


static func form_ranks(cos: Array) -> void:
	var groups := {}
	for co in cos:
		var r: String = String(co.get("rank", "Auto"))
		if r == "" or r == "Auto" or not RANKS.has(r):
			r = default_rank(String(co.get("type_name", "Even")))
		co["rank"] = r
		if r == "Held back":
			co["slot"] = "Reserve"
			co.erase("band")
			co["depth"] = 0.0
			continue
		if not groups.has(r):
			groups[r] = []
		groups[r].append(co)
	if groups.size() <= 1 and cos.size() <= 4:
		for co in cos:
			co["depth"] = 0.0
		return   # one rank of four or fewer: the old left-to-right slots
	# a chequerboard: each rank spreads over the whole front, and a rear rank stands behind the GAPS of the
	# rank ahead, not behind its men - so the shooters at the back have a clear line past the bayonets
	var order: Array = []
	for r in ["Front", "Line", "Back"]:
		if groups.has(r):
			order.append(r)
	var nr := order.size()
	for ri in nr:
		var r: String = order[ri]
		var g: Array = groups[r]
		var across := mini(g.size(), 8)
		var shift := (float(ri) - float(nr - 1) * 0.5) / float(nr)
		for i in g.size():
			var i_line := i % across
			g[i]["band"] = 45.0 - clampf((float(i_line) + 0.5 + shift) / float(across), 0.03, 0.97) * 90.0
			g[i]["slot"] = "%s %d" % [r, i_line]
			g[i]["depth"] = float(RANK_DEPTH[r])


## Kept for older callers: the order of battle by type.
static func spread_front(cos: Array) -> void:
	form_ranks(cos)
