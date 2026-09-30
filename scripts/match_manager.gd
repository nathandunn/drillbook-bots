class_name MatchManager
extends Node
## Spawns the two companies, runs the sergeants, keeps the score. The sergeant of a side is
## simply the steadiest man still standing (highest discipline + nerve); what he "orders" is a
## blend of his own traits and the line's, and his men follow it only as far as their own
## traits take them - see soldier.gd.

signal match_started(match_index: int)
signal match_ended(result: Dictionary)

const MAX_SIZE := 20
const TEAM_NAMES := ["Red", "Blue"]
const TEAM_COLORS := [Color(0.8, 0.22, 0.2), Color(0.2, 0.35, 0.8)]
const SERGEANT_TICK := 0.5
const VOLLEY_COOLDOWN := 2.5

static var TEAM_SIZE := 20

var world: Node3D
var field: Field
var headless := false
var team_personalities: Array[Personality] = [Personality.preset("Regulars"), Personality.preset("Skirmishers")]
var team_preset_names: Array[String] = ["Regulars", "Skirmishers"]
var team_types: Array[SoldierType] = [SoldierType.preset("Even"), SoldierType.preset("Even")]
var team_type_names: Array[String] = ["Even", "Even"]
var team_sizes := [TEAM_SIZE, TEAM_SIZE]
var team_drills: Array = [null, null]        # Drill per side; null = the engine on the dials
var drill_phase := ["", ""]                   # "set phase X" / "phase is X", per company
var stand_fast_until := [-1.0, -1.0]
var rule_tally := [{}, {}]                    # rule line -> ticks it decided, this battle
var round_no := 0                             # campaign round, for "round N"
var _sgt_memory := [{}, {}]
var _plan: Dictionary = {}                    # this tick's sergeant plan from the drill
## Campaign rosters: per team, the men to field this round as records
## {name, seed, kills, rounds, recruit}. Empty means a fresh company of team_sizes[t].
var rosters: Array = [[], []]

var soldiers: Array[Soldier] = []
var orders: Array[Dictionary] = [{}, {}]
var sergeants: Array = [null, null]
var elapsed := 0.0
var time_limit := -1.0
var running := false
var match_index := 0
var rng := RandomNumberGenerator.new()
var stats := {}
var _tick := 0.0
var _spot_claims := {}   # "x,z" -> soldier
var _last_volley_t := [-100.0, -100.0]
var _volley_ids := [0, 0]
var _charge_since := [-1.0, -1.0]
var _exch := [[0.0, 0.0], [0.0, 0.0]]   # hits given, hits taken - lately (decays)
var _last_harm_t := 0.0                # when anyone last hit anyone
var _press_since := [-1.0, -1.0]
var _fallback_since := [-1.0, -1.0]
var _alive_cache: Array[Soldier] = []
var _cache_frame := -1
var _hist_frame := -1


## Put a side on a drill: its rules, and its dials as the personality everything else reads.
func set_drill(t: int, drill_name: String) -> bool:
	var d := Drill.named(drill_name)
	if d == null:
		return false
	team_drills[t] = d
	team_personalities[t] = d.personality()
	team_preset_names[t] = d.name
	return true


func home_z(team: int) -> float:
	return -(Field.HALF_Z - 6.0) if team == 0 else (Field.HALF_Z - 6.0)


func start_match(seed_value: int = -1) -> void:
	clear()
	match_index += 1
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	elapsed = 0.0
	stats = _fresh_stats()
	for t in 2:
		var roster: Array = rosters[t]
		var n: int = roster.size() if not roster.is_empty() else clampi(int(team_sizes[t]), 1, MAX_SIZE)
		var spacing := 1.0
		var order := _blank_order(t, n)
		order["spacing"] = spacing
		orders[t] = order
		for i in n:
			var rec: Dictionary = roster[i] if not roster.is_empty() else {}
			var s := Soldier.new()
			s.team = t
			s.team_color = TEAM_COLORS[t]
			s.soldier_name = rec.get("name", "%s %d" % [TEAM_NAMES[t][0], i + 1])
			# a man's own quirks come from his seed, so a veteran is the same man every round
			var prng := RandomNumberGenerator.new()
			prng.seed = int(rec.get("seed", rng.randi()))
			s.personality = team_personalities[t].jittered(prng, 0.1)
			s.drill = team_drills[t]
			s.soldier_type = team_types[t].jittered(prng, 0.02)
			s.kills = int(rec.get("kills", 0))
			s.rounds = int(rec.get("rounds", 0))
			s.record_seed = prng.seed
			s.manager = self
			s.field = field
			s.slot = i
			s.rng = RandomNumberGenerator.new()
			s.rng.seed = rng.randi()
			var x := (float(i) - float(n - 1) * 0.5) * spacing
			s.position = Vector3(x, field.height_at(x, home_z(t)), home_z(t))
			s.rotation.y = PI if t == 0 else 0.0
			s.fired.connect(_on_fired)
			s.damaged.connect(_on_damaged)
			s.died.connect(_on_died)
			s.routed.connect(_on_routed)
			s.fled.connect(_on_fled)
			s.thrust.connect(_on_thrust)
			world.add_child(s)
			soldiers.append(s)
		# face the enemy
		for s in soldiers:
			if s.team == t:
				s.rotation.y = 0.0 if t == 0 else PI
	running = true
	match_started.emit(match_index)


func _blank_order(t: int, n: int) -> Dictionary:
	return {"mode": "advance", "line_z": home_z(t), "rally_z": home_z(t), "center_x": 0.0, "spacing": 1.0,
		"count": n, "volley_id": 0, "volley_age": 999.0, "alone": false, "sergeant": "", "press": false, "seek_cover": false}


func clear() -> void:
	for s in soldiers:
		if is_instance_valid(s):
			if s.ragdoll != null and is_instance_valid(s.ragdoll):
				s.ragdoll.queue_free()
			s.queue_free()
	soldiers.clear()
	_spot_claims.clear()
	_last_volley_t = [-100.0, -100.0]
	_charge_since = [-1.0, -1.0]
	_fallback_since = [-1.0, -1.0]
	_exch = [[0.0, 0.0], [0.0, 0.0]]
	_last_harm_t = 0.0
	_press_since = [-1.0, -1.0]
	drill_phase = ["", ""]
	stand_fast_until = [-1.0, -1.0]
	rule_tally = [{}, {}]
	_sgt_memory = [{}, {}]
	running = false
	_cache_frame = -1


func _fresh_stats() -> Dictionary:
	return {
		"shots": [0, 0], "hits": [0, 0], "kills": [[0, 0], [0, 0]],   # kills[t] = [rifle, bayonet]
		"volleys": [0, 0], "charges": [0, 0], "fallbacks": [0, 0], "routed": [0, 0], "fled": [0, 0],
		"friendly": [0, 0], "thrusts": [0, 0], "thrust_hits": [0, 0], "wounds": [0, 0],
	}


# ---------------------------------------------------------------- queries the men use

func alive_soldiers() -> Array[Soldier]:
	var f := Engine.get_physics_frames()
	if f == _cache_frame:
		return _alive_cache
	_cache_frame = f
	_alive_cache = []
	for s in soldiers:
		if s.alive and not s.gone:
			_alive_cache.append(s)
	return _alive_cache


## Men still in the fight: alive, on the field, and not running for the rear.
func fighting(team: int) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s in alive_soldiers():
		if s.team == team and not s.is_routed:
			out.append(s)
	return out


func alive_count(team: int) -> int:
	var n := 0
	for s in alive_soldiers():
		if s.team == team:
			n += 1
	return n


func loss_fraction(team: int) -> float:
	var n: int = team_sizes[team]
	return 1.0 - float(alive_count(team)) / maxf(float(n), 1.0)


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
		if d < best_d:
			best_d = d
			best = o
	return best


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
	for o in alive_soldiers():
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
	var men := fighting(s.team)
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


# ---------------------------------------------------------------- the sergeants

func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed += delta
	for t in 2:
		orders[t]["volley_age"] = elapsed - _last_volley_t[t]
	_tick -= delta
	if _tick <= 0.0:
		_tick = SERGEANT_TICK
		for t in 2:
			_run_sergeant(t)
	# the fight is over when one side has nobody left standing on the field
	var f0 := fighting(0).size()
	var f1 := fighting(1).size()
	if f0 == 0 and f1 == 0:
		end_match("mutual rout")
	elif f0 == 0:
		end_match("Red broken")
	elif f1 == 0:
		end_match("Blue broken")
	elif time_limit > 0.0 and elapsed >= time_limit:
		end_match("time")
	elif elapsed > 120.0 and elapsed - _last_harm_t > 45.0:
		# nobody has hurt anybody for over a minute: the day is decided on harm done
		end_match("stalemate")


## The line's mind. Traits are the sergeant's own blended half-and-half with his men's mean,
## so a company of cowards with one iron sergeant still holds better than one without him.
func _run_sergeant(t: int) -> void:
	var men := fighting(t)
	var order := orders[t]
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
	if sergeants[t] != sgt:
		sergeants[t] = sgt
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
	var enemy_centre := Vector3.ZERO
	var nearest_d := INF
	for e in enemies:
		enemy_centre += e.global_position
		nearest_d = minf(nearest_d, e.global_position.distance_to(centre))
	if not enemies.is_empty():
		enemy_centre /= enemies.size()
	var toward := signf(-home_z(t))   # +1 for red (marching +z), -1 for blue
	var loaded_frac := 0.0
	var in_range := 0
	var engage: float = 68.0 - 42.0 * float(mix["patience"])
	# can the line see the enemy at all? A hill between them and there is nothing to hold for
	var seen := true
	if not enemies.is_empty() and not field.hills.is_empty():
		seen = false
		var eye := Vector3(0, Soldier.EYE_HEIGHT, 0)
		for e in enemies:
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
	for m in men:
		if m.loaded:
			loaded_frac += 1.0
		if not enemies.is_empty() and m.global_position.distance_to(enemy_centre) <= engage:
			in_range += 1
	loaded_frac /= men.size()

	order["spacing"] = 0.8 + (1.0 - mix["cohesion"]) * 3.0
	# the line's centre creeps toward the enemy's, a sergeant with cohesion keeps it together
	order["center_x"] = lerpf(order["center_x"], clampf(enemy_centre.x if not enemies.is_empty() else 0.0, -18.0, 18.0), 0.06)

	var mean_courage := 0.0
	for m in men:
		mean_courage += m.courage
	mean_courage /= men.size()
	var losses := loss_fraction(t)

	# --- the exchange: a sergeant can count. Taking two balls for every one he gives while
	# the enemy sits behind walls is a firefight lost, and standing in it is not a plan.
	_exch[t][0] *= 0.98
	_exch[t][1] *= 0.98
	var given: float = _exch[t][0]
	var taken: float = _exch[t][1]
	var losing_fire: bool = not enemies.is_empty() and taken >= 2.0 * given + 2.0 and nearest_d < engage + 15.0
	# ... and if nobody has hurt anybody for a while, somebody has to go and find the enemy
	var stalled: bool = not enemies.is_empty() and elapsed > 30.0 and elapsed - _last_harm_t > 25.0 and nearest_d > 22.0
	var pressing: bool = _press_since[t] >= 0.0
	if pressing and (nearest_d < 22.0 or enemies.is_empty()):
		_press_since[t] = -1.0
		pressing = false
	if stalled and not pressing and mix["aggression"] >= 0.15:
		_press_since[t] = elapsed
		pressing = true

	# --- the drill: the sergeant's rules make a plan; whatever the plan leaves out, the engine decides
	_plan = {}
	var drill: Drill = team_drills[t]
	if drill != null and not drill.sergeant_rules.is_empty():
		var ctx := {"t": t, "men": men, "enemies": enemies, "nearest_d": nearest_d, "losses": losses,
			"loaded_frac": loaded_frac, "courage": mean_courage, "seen": seen, "centre": centre,
			"enemy_centre": enemy_centre}
		drill.run(drill.sergeant_rules, func(id: String, args: Array) -> bool: return _sgt_sense(id, args, ctx),
			func(id: String, args: Array) -> bool: return _sgt_act(id, args, ctx), _sgt_memory[t], elapsed, rule_tally[t])
		if _plan.get("press", false) and not pressing:
			_press_since[t] = elapsed
			pressing = true

	# --- mode
	var mode: String = order["mode"]
	if _plan.has("mode"):
		mode = _plan_mode(t, mode, centre, toward, enemies)
	elif mode == "charge":
		# the charge runs until the enemy is broken off or the blood cools
		if enemies.is_empty() or nearest_d > 40.0 or (elapsed - _charge_since[t] > 25.0 and nearest_d > 6.0):
			mode = "advance"
	elif mode == "fallback":
		var rallied := absf(centre.z - order["rally_z"]) < 6.0
		if rallied and (loaded_frac > 0.6 or elapsed - _fallback_since[t] > 20.0):
			mode = "hold"
	if not _plan.has("mode") and mode != "charge" and mode != "fallback":
		# fall back: losses or a bad exchange, and a sergeant with the nerve to admit it
		var break_point: float = 0.25 + 0.5 * float(mix["nerve"])
		if losses > break_point and mean_courage < 0.45 and mix["aggression"] < 0.75 and nearest_d < 40.0:
			mode = "fallback"
			order["rally_z"] = clampf(centre.z - toward * 22.0, -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
			_fallback_since[t] = elapsed
			stats["fallbacks"][t] += 1
		else:
			# the charge: close enough, and either the volley is just gone or the fight is going our way
			var charge_range: float = 12.0 + 32.0 * float(mix["aggression"])
			var just_volleyed: bool = elapsed - float(_last_volley_t[t]) < 4.0
			var ratio := strength_ratio(t)
			if losing_fire:
				# the bayonet decides what the rifle cannot: a sergeant with any blood in him
				# closes, and a shy one either finds a wall of his own or gets out of range
				charge_range += 20.0
			if not enemies.is_empty() and nearest_d < charge_range and mix["aggression"] > (0.2 if losing_fire else 0.35) \
				and (just_volleyed or loaded_frac < 0.35 or mix["aggression"] > 0.85 or losing_fire) \
				and ratio > (0.4 if losing_fire else 0.5 + (1.0 - mix["aggression"]) * 0.6):
				mode = "charge"
				_charge_since[t] = elapsed
				_press_since[t] = -1.0
				stats["charges"][t] += 1
			elif losing_fire and mix["aggression"] <= 0.2 and mix["cover"] < 0.5:
				mode = "fallback"
				order["rally_z"] = clampf(centre.z - toward * 25.0, -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
				_fallback_since[t] = elapsed
				stats["fallbacks"][t] += 1
			elif losing_fire and mix["aggression"] > 0.2:
				mode = "advance"
				if not pressing:
					_press_since[t] = elapsed
					pressing = true
			elif not enemies.is_empty() and nearest_d <= engage and not pressing:
				mode = "hold"
			else:
				mode = "advance"
	order["mode"] = mode
	order["press"] = pressing and mode == "advance"
	order["seek_cover"] = losing_fire or _plan.get("seek_cover", false)
	order["hold_fire"] = _plan.get("hold_fire", false)
	if _plan.has("spacing"):
		order["spacing"] = _plan["spacing"]
	if _plan.has("wheel"):
		order["center_x"] = clampf(float(order["center_x"]) + float(_plan["wheel"]) * toward * 1.5, -20.0, 20.0)
	if mode == "charge":
		# a line coming on with the bayonet is a fearful thing before it ever arrives
		for e in enemies:
			var close := 0
			for m in men:
				if m.charging and m.global_position.distance_to(e.global_position) < 15.0:
					close += 1
			if close >= 3:
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
			var target_z: float = order["line_z"] + toward * step
			# a cover-minded sergeant halts the line on a wall he can reach before the enemy does
			# - unless the line is pressing in, when walls are for after the volley at twenty paces
			if mix["cover"] > 0.45 and not pressing:
				var wall_z := _cover_row_ahead(t, order["line_z"], engage, enemy_centre)
				if not is_nan(wall_z) and (target_z - wall_z) * toward > 0.0:
					target_z = wall_z
			order["line_z"] = clampf(target_z, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
		"hold":
			# keep the range: if the enemy pulls back out of reach, follow at the walk
			if _plan.get("rally", false):
				pass   # stand exactly here
			elif not enemies.is_empty() and (nearest_d > engage + 8.0 or pressing) and not _plan.has("mode"):
				order["line_z"] += toward * 1.0 * SERGEANT_TICK
			# ... and a hot-blooded sergeant still edges in
			elif mix["aggression"] > 0.6 and nearest_d > 20.0:
				order["line_z"] += toward * 0.5 * SERGEANT_TICK
		"fallback":
			order["line_z"] = order["rally_z"]
		"charge":
			order["line_z"] = centre.z

	# --- the volley: enough men loaded and in range, and it's been a moment since the last
	if mode != "charge" and mode != "fallback" and not enemies.is_empty() and not _plan.get("hold_fire", false):
		var ready := 0
		var reach: float = float(_plan.get("volley_at", engage + 10.0))
		for m in men:
			if m.loaded and m.global_position.distance_to(enemy_centre) <= reach:
				ready += 1
		var need: float = float(_plan.get("volley_need", 0.45 + 0.4 * float(mix["discipline"])))
		var cooldown: float = VOLLEY_COOLDOWN + 4.0 * mix["patience"]
		if _plan.get("volley_now", false) and float(ready) / men.size() >= 0.3 and elapsed - _last_volley_t[t] > 1.5:
			_call_volley(t)
		elif float(ready) / men.size() >= need and elapsed - _last_volley_t[t] > cooldown:
			_call_volley(t)
		elif _plan.get("at_will", false) or (not _plan.has("volley_at") and not _plan.has("volley_need") and mix["discipline"] < 0.35):
			order["mode"] = "at_will" if mode == "hold" else mode


# ---------------------------------------------------------------- the drill's words, for a sergeant

## Sensors every drill word shares, man or sergeant; null if the id is not one of them.
func shared_sense(id: String, args: Array, t: int, r: RandomNumberGenerator) -> Variant:
	match id:
		"always":
			return true
		"losing_exchange":
			return _exch[t][1] >= 2.0 * _exch[t][0] + 2.0
		"winning_exchange":
			return _exch[t][0] >= 2.0 * _exch[t][1] + 2.0
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
			return String(drill_phase[t]) == String(args[0])
		"chance":
			return r.randf() < float(args[0])
		"losses_over":
			return loss_fraction(t) > float(args[0])
		"enemy_losses_over":
			return loss_fraction(1 - t) > float(args[0])
		"enemy_outnumbers":
			return strength_ratio(t) < 1.0 - (float(args[0]) if not args.is_empty() else 0.0) - 0.001
		"we_outnumber":
			return strength_ratio(t) > 1.0 + (float(args[0]) if not args.is_empty() else 0.0) + 0.001
		"enemy_broken":
			var alive_e := alive_count(1 - t)
			return alive_e == 0 or float(fighting(1 - t).size()) / float(alive_e) < 0.5
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
	var shared: Variant = shared_sense(id, args, t, rng)
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
			return String(orders[1 - t].get("mode", "")) == "charge" and nd < 50.0
		"enemy_in_cover":
			var k := 0
			for e in enemies:
				if e.kneeling or e.action == "cover":
					k += 1
			return not enemies.is_empty() and float(k) / enemies.size() >= 0.4
		"enemy_uphill":
			return (c["enemy_centre"] as Vector3).y - (c["centre"] as Vector3).y > 1.5
		"enemy_downhill", "high_ground":
			return (c["centre"] as Vector3).y - (c["enemy_centre"] as Vector3).y > 1.5
		"enemy_visible":
			return c["seen"]
		"enemy_hidden":
			return not c["seen"]
		"enemy_reloading":
			return shared_sense("enemy_loaded_under", [0.5], t, rng)
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
		"alone":
			return men.size() <= 2
		"volley_called":
			return float(orders[t].get("volley_age", 999.0)) < 0.7
		"mode_is":
			return String(orders[t].get("mode", "")) == Soldier._mode_word(String(args[0]))
		"charging":
			return String(orders[t].get("mode", "")) == "charge"
	return false


func _sgt_act(id: String, args: Array, c: Dictionary) -> bool:
	var t: int = c["t"]
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
			stand_fast_until[t] = elapsed + SERGEANT_TICK + 0.1
			return true
		"set_phase":
			drill_phase[t] = String(args[0])
			return true
	return false


## The mode the plan asks for, with the bookkeeping a change of mode needs.
func _plan_mode(t: int, current: String, centre: Vector3, toward: float, enemies: Array) -> String:
	var want: String = _plan["mode"]
	if want == "charge" and current != "charge":
		_charge_since[t] = elapsed
		_press_since[t] = -1.0
		stats["charges"][t] += 1
	elif want == "fallback" and current != "fallback":
		orders[t]["rally_z"] = clampf(centre.z - toward * float(_plan.get("fall_dist", 22.0)), -Field.HALF_Z + 4.0, Field.HALF_Z - 4.0)
		_fallback_since[t] = elapsed
		stats["fallbacks"][t] += 1
	return want


## The z of the nearest low wall or fence row between the line and the engagement distance,
## on the near side of it; NAN if there is none.
func _cover_row_ahead(t: int, line_z: float, engage: float, enemy_centre: Vector3) -> float:
	var toward := signf(-home_z(t))
	var best := NAN
	var best_d := INF
	for pc in field.pieces:
		if pc["tall"]:
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


func _call_volley(t: int) -> void:
	_last_volley_t[t] = elapsed
	_volley_ids[t] += 1
	orders[t]["volley_id"] = _volley_ids[t]
	orders[t]["volley_age"] = 0.0
	stats["volleys"][t] += 1


# ---------------------------------------------------------------- events

## The shock of a volley: balls arriving together frighten the men around the mark, hit or
## miss, far more than the same balls one at a time. Only shots fired on the word count.
func volley_pressure(shooter: Soldier, mark: Vector3, hit: bool) -> void:
	var o: Dictionary = orders[shooter.team]
	if float(o.get("volley_age", 999.0)) > 1.2:
		return
	for s in alive_soldiers():
		if s.team == shooter.team:
			continue
		var d := s.global_position.distance_to(mark)
		if d < 5.0:
			s.fear = minf(s.fear + (0.05 if hit else 0.025) * (1.0 - d / 5.0) + 0.01, 0.6)


func _on_fired(s: Soldier, victim: Soldier, hit: bool) -> void:
	stats["shots"][s.team] += 1
	if hit and victim.team != s.team:
		stats["hits"][s.team] += 1
		_exch[s.team][0] += 1.0
		_exch[victim.team][1] += 1.0
		_last_harm_t = elapsed
	elif hit:
		stats["friendly"][s.team] += 1


func _on_damaged(s: Soldier, amount: float, _source: String, _attacker: Soldier) -> void:
	if amount < Soldier.MAX_HP and s.alive:
		stats["wounds"][s.team] += 1


func _on_died(s: Soldier, source: String, attacker: Soldier) -> void:
	if attacker != null and attacker.team != s.team:
		stats["kills"][attacker.team][1 if source == "bayonet" else 0] += 1
	for o in alive_soldiers():
		if o.team == s.team:
			o.notice_death(s.global_position)
	for k in _spot_claims.keys():
		if _spot_claims[k] == s:
			_spot_claims.erase(k)


func _on_routed(s: Soldier) -> void:
	stats["routed"][s.team] += 1


func _on_fled(s: Soldier) -> void:
	stats["fled"][s.team] += 1


func _on_thrust(s: Soldier, landed: bool) -> void:
	stats["thrusts"][s.team] += 1
	if landed:
		stats["thrust_hits"][s.team] += 1


func end_match(reason: String) -> void:
	if not running:
		return
	running = false
	var f := [fighting(0).size(), fighting(1).size()]
	var a := [alive_count(0), alive_count(1)]
	var winner := -1
	if f[0] > 0 and f[1] == 0:
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
		var s0: int = stats["kills"][0][0] + stats["kills"][0][1]
		var s1: int = stats["kills"][1][0] + stats["kills"][1][1]
		if absf(g[0] - g[1]) > 4.0:
			winner = 0 if g[0] > g[1] else 1
			reason += ", " + ("Red" if winner == 0 else "Blue") + " holds the ground"
		elif s0 != s1:
			winner = 0 if s0 > s1 else 1
	var per := []
	for s in soldiers:
		per.append({"name": s.soldier_name, "team": s.team, "alive": s.alive, "routed": s.is_routed, "gone": s.gone,
			"seed": s.record_seed, "rounds": s.rounds, "career_kills": s.kills,
			"shots": s.shots, "hits": s.hits, "kills": s.kills - s.kills_before, "bayonet_kills": s.bayonet_kills,
			"thrusts": s.thrusts, "thrust_hits": s.thrust_hits, "dmg": s.dmg_done, "hp": s.hp,
			"persona": s.personality.label(), "type": s.soldier_type.label()})
	var result := {"match": match_index, "winner": winner, "winner_name": TEAM_NAMES[winner] if winner >= 0 else "Draw",
		"reason": reason, "duration": elapsed, "alive": a, "fighting": f, "stats": stats.duplicate(true),
		"sizes": team_sizes.duplicate(), "soldiers": per,
		"presets": team_preset_names.duplicate(), "types": team_type_names.duplicate(), "tally": rule_tally.duplicate(true)}
	match_ended.emit(result)
