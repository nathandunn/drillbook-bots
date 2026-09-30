class_name Soldier
extends CharacterBody3D
## One line infantryman: a single-shot rifle, a bayonet, two legs and a personality. Nothing
## here takes an order as a command. The sergeant (match_manager.gd) publishes what the line
## is doing - where it stands, how far apart, whether he has called the volley or the charge
## or the fall-back - and each man decides, through his own traits, how much of that to follow.

signal fired(soldier: Soldier, target: Soldier, hit: bool)
signal damaged(soldier: Soldier, amount: float, source: String, attacker: Soldier)
signal died(soldier: Soldier, source: String, attacker: Soldier)
signal routed(soldier: Soldier)
signal fled(soldier: Soldier)
signal thrust(soldier: Soldier, landed: bool)

const MAX_HP := 100.0
const WALK := 1.7
const RUN := 4.6
const RELOAD := 9.0            # seconds, an even type; ~3 rounds a minute for a rifled musket
const MAX_RANGE := 100.0
const POINT_BLANK := 12.0
const STEEL_RANGE := 3.0        # an enemy this close is a bayonet matter; no one shoots with a blade coming in
const WOUND := 45.0
const BAYONET_REACH := 1.9
const BAYONET_COOLDOWN := 0.9
const BAYONET_DMG := 45.0
const DECISION_INTERVAL := 0.2
const STAMINA_MAX := 100.0
const RUN_DRAIN := 5.0
const WALK_DRAIN := 1.5
const REGEN := 5.0
const TIRED := 25.0
const LAYER_WORLD := 1
const LAYER_MEN := 2
const EYE_HEIGHT := 1.6
const MUZZLE := Vector3(0.28, 1.35, -0.9)

var team := 0
var team_color := Color.RED
var soldier_name := "man"
var personality: Personality
var soldier_type: SoldierType
var manager: MatchManager = null
var field: Field = null
var rng: RandomNumberGenerator
var slot := 0

# derived from the type
var walk_speed := WALK
var run_speed := RUN
var reload_time := RELOAD
var melee_mult := 1.0
var stamina_max := STAMINA_MAX
var regen_mult := 1.0

var hp := MAX_HP
var alive := true
var loaded := true
var reload_left := 0.0
var stamina := STAMINA_MAX
var wounded := false
var running := false
var is_routed := false
var gone := false             # ran off the field
var courage := 1.0
var fear := 0.0               # nearby deaths, decays
var kneeling := false
var in_melee := false
var charging := false
var kiting := 0.0             # fire-and-fall-back timer
var breath := 0.0             # seconds until a man who has just run can hold a rifle steady
var alone := 0.0              # 0 with mates at his elbow, 1 with nobody within ten metres
var _halt := 0.0              # stand still: the moment of firing and the first of the reload
var at_will := false          # this man has decided to fire without the sergeant
var drill: Drill = null       # the company's drill; null runs the engine on the dials alone
var _stand_fast := 0.0        # a drill has told him to stand: no rout while this runs
var _d_enemy: Soldier = null  # this tick's facts, for the drill's sensors and actions
var _d_enemy_d := INF
var _d_order: Dictionary = {}
var _d_follow := false
var _d_memory := {}

var action := "form"
var goal := Vector3.ZERO
var want_run := false
var target: Soldier = null
var face_point := Vector3.ZERO
var decide_timer := 0.0
var thrust_timer := 0.0
var _stuck := 0.0
var _detour := 0.0
var _detour_dir := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _fire_anim := 0.0
var _thrust_anim := 0.0
var _volley_seen := -1
var _cover_spot: Dictionary = {}
var _cover_hold := 0.0
var _jitter := Vector3.ZERO

# stats (kills is the career total in a campaign; kills_before is where this round started)
var kills_before := 0
var rounds := 0
var record_seed := 0
var shots := 0
var hits := 0
var kills := 0
var bayonet_kills := 0
var thrusts := 0
var thrust_hits := 0
var dmg_done := 0.0
var friendly_hits := 0

# body
var body_root: Node3D
var rifle: Node3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var leg_l: Node3D
var leg_r: Node3D
var label: Label3D
var _mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _gait := 0.0
var _flash_tween: Tween
var ragdoll: Ragdoll = null
var _bar_fg: MeshInstance3D
var _bar_quad: QuadMesh
var _smoke: CPUParticles3D


func _ready() -> void:
	collision_layer = LAYER_MEN
	collision_mask = LAYER_WORLD | LAYER_MEN
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.32
	sh.height = 1.8
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	apply_type()
	_build_body()
	_last_pos = global_position
	_jitter = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))


func apply_type() -> void:
	var st := soldier_type
	var run_m := 0.6 + 0.8 * st.skill("run")
	walk_speed = WALK * (0.8 + 0.4 * st.skill("run"))
	run_speed = RUN * run_m
	reload_time = RELOAD / (0.8 + 0.4 * st.skill("accuracy"))
	melee_mult = 0.55 + 0.9 * st.skill("melee")
	stamina_max = STAMINA_MAX * (0.6 + 0.8 * st.skill("stamina"))
	regen_mult = 0.6 + 0.8 * st.skill("stamina")
	stamina = stamina_max
	hp = MAX_HP
	courage = personality.get_trait("nerve")
	kills_before = kills


func p(t: String) -> float:
	return personality.get_trait(t)


func tired() -> bool:
	return stamina < TIRED


# ---------------------------------------------------------------- brain

func _physics_process(delta: float) -> void:
	if not alive or gone:
		return
	_tick_timers(delta)
	decide_timer -= delta
	if decide_timer <= 0.0:
		decide_timer = DECISION_INTERVAL + rng.randf_range(0.0, 0.05)
		_decide()
	_move(delta)
	_animate(delta)


func _tick_timers(delta: float) -> void:
	if not loaded:
		var r := 1.0
		if tired():
			r = 0.7
		if running:
			r = 0.0   # nobody reloads a muzzle-loader at the run
		elif kneeling:
			r *= 0.9
		reload_left -= delta * r
		if reload_left <= 0.0:
			loaded = true
	thrust_timer = maxf(thrust_timer - delta, 0.0)
	kiting = maxf(kiting - delta, 0.0)
	_halt = maxf(_halt - delta, 0.0)
	_cover_hold = maxf(_cover_hold - delta, 0.0)
	fear = maxf(fear - delta * 0.04, 0.0)
	breath = maxf(breath - delta, 0.0)
	if running and velocity.length() > 0.5:
		stamina = maxf(stamina - RUN_DRAIN * delta, 0.0)
		breath = 4.0
	elif velocity.length() > 0.2:
		stamina = maxf(stamina - WALK_DRAIN * delta, 0.0)
	else:
		stamina = minf(stamina + REGEN * regen_mult * (1.4 if kneeling else 1.0) * delta, stamina_max)
	# courage: nerve, less what the day has cost
	var losses: float = manager.loss_fraction(team)
	var hurt := 1.0 - hp / MAX_HP
	var outnumbered: float = clampf(1.0 - manager.strength_ratio(team), 0.0, 1.0)
	# ... and a man with nobody at his elbow feels every bit of it: loose order has its price
	courage = p("nerve") * 1.15 - losses * 0.75 - hurt * 0.3 - fear * 0.35 - outnumbered * 0.25 - alone * 0.2 + 0.05
	_stand_fast = maxf(_stand_fast - delta, 0.0)
	if not is_routed and courage < 0.1 and manager.elapsed > 3.0 and _stand_fast <= 0.0 and manager.stand_fast_until[team] < manager.elapsed:
		_rout()


func _rout() -> void:
	is_routed = true
	charging = false
	kneeling = false
	action = "rout"
	routed.emit(self)


func _decide() -> void:
	var order: Dictionary = manager.orders[team]
	var enemy := manager.nearest_enemy(self)
	var enemy_d := INF
	if enemy != null:
		enemy_d = global_position.distance_to(enemy.global_position)
	target = enemy
	var mates := 0
	for f in manager.fighting(team):
		if f != self and f.global_position.distance_to(global_position) < 6.0:
			mates += 1
			if mates >= 2:
				break
	alone = 1.0 if mates == 0 else (0.4 if mates == 1 else 0.0)
	want_run = false
	kneeling = false
	in_melee = enemy != null and enemy_d < STEEL_RANGE

	if is_routed:
		# run for the rear; a steadied man (courage back up) may stop and fight again
		if courage > 0.4 and rng.randf() < 0.3:
			is_routed = false
		else:
			goal = Vector3(global_position.x, 0, manager.home_z(team) * 1.15)
			want_run = true
			action = "rout"
			if absf(global_position.z) > Field.HALF_Z - 1.5:
				_flee()
			return

	# someone is on me with a bayonet: fight, whatever else I meant to do
	if in_melee:
		action = "melee"
		goal = enemy.global_position
		face_point = enemy.global_position
		_try_thrust(enemy)
		return

	# the drill first: the first rule that holds and can be done decides; "follow sergeant"
	# (or no rule at all) hands the tick to the engine below
	if drill != null and not drill.man_rules.is_empty():
		_d_enemy = enemy
		_d_enemy_d = enemy_d
		_d_order = order
		_d_follow = false
		if drill.run(drill.man_rules, _drill_sense, _drill_act, _d_memory, manager.elapsed, manager.rule_tally[team]) and not _d_follow:
			return

	# the charge: the sergeant's, or my own blood up
	var charge_order: bool = order["mode"] == "charge"
	if charge_order and (p("aggression") > 0.3 or p("discipline") > 0.6 or charging):
		charging = true
	elif enemy != null and enemy_d < 10.0 and p("aggression") > 0.8:
		charging = true
	elif enemy != null and enemy_d < 7.0 and not loaded and p("aggression") > 0.25:
		charging = true   # empty rifle, enemy on top of me: the bayonet is what's left
	if charging and (enemy == null or enemy_d > 45.0 or (not charge_order and enemy_d > 14.0 and p("aggression") < 0.8)):
		charging = false
	if charging and enemy != null:
		action = "charge"
		goal = enemy.global_position
		face_point = enemy.global_position
		want_run = not tired()
		# keep the charge together: a man out ahead of his mates by more than a few metres waits for them
		if p("discipline") > 0.3 and manager.ahead_of_line(self) > 6.0 and enemy_d > 8.0:
			want_run = false
		# a loaded man charging fires it off at point blank
		if loaded and enemy_d < POINT_BLANK and enemy_d >= STEEL_RANGE and _can_fire_at(enemy):
			_fire(enemy)
		return

	# the bayonet is coming: a man who would rather not be on the end of it gives ground before
	# it arrives - one shot if he has it, then ten metres back. Skirmishers do not stand a charge.
	if enemy != null and enemy.charging and enemy_d < 24.0 and p("aggression") < 0.4 and p("discipline") < 0.6 and p("nerve") < 0.7 \
		and not charging and kiting <= 0.0:
		if loaded and _can_fire_at(enemy) and velocity.length() < 0.5:
			_fire(enemy)
		kiting = 5.0
		return

	# firing
	if loaded and enemy != null and enemy_d <= MAX_RANGE and enemy_d >= STEEL_RANGE and _can_fire_at(enemy):
		var my_range := 75.0 - 50.0 * p("patience")
		var volley_now: bool = order["volley_id"] != _volley_seen and order["volley_age"] < 0.7
		var disciplined: bool = p("discipline") > 0.45 and order["mode"] != "at_will" and not order["alone"]
		var fire_now := false
		if volley_now and enemy_d <= my_range + 15.0:
			fire_now = rng.randf() < 0.5 + 0.5 * p("discipline")   # some men are slow on the word
			_volley_seen = order["volley_id"]
		elif enemy_d < POINT_BLANK:
			fire_now = true
		elif order.get("hold_fire", false):
			fire_now = false   # the drill says hold: nobody fires at will
		elif not disciplined and enemy_d <= my_range:
			fire_now = true
		elif disciplined and order["volley_age"] > 14.0 and enemy_d <= my_range and rng.randf() < 0.15:
			fire_now = true   # the volley is not coming; an old hand takes his shot
		if fire_now and velocity.length() > 0.5 and enemy_d > POINT_BLANK:
			_halt = 0.8   # stop, then shoot: the next decision finds him standing
			action = "aim"
			face_point = enemy.global_position
			return
		if fire_now:
			_fire(enemy)
			# fire and fall back: the man who would rather not be bayoneted
			if enemy_d < 22.0 and p("aggression") < 0.4 and p("nerve") < 0.7:
				kiting = 6.0
			return

	# where to stand
	if kiting > 0.0 and enemy != null:
		action = "kite"
		var away: Vector3 = (global_position - enemy.global_position).normalized()
		away.y = 0.0
		goal = field.free_point(global_position + away * 10.0)
		want_run = true
		face_point = enemy.global_position
		return

	if order["mode"] == "fallback" and (p("discipline") > 0.3 or courage < 0.5):
		goal = _slot_position(order, order["rally_z"])
		action = "fallback"
		want_run = p("nerve") < 0.5
		if enemy != null:
			face_point = enemy.global_position
		return

	# my place in the line, or a bit of cover near it if I'm that sort
	var slot_pos := _slot_position(order, order["line_z"])
	var spot := _pick_cover(slot_pos, enemy)
	if not spot.is_empty():
		goal = spot["pos"]
		action = "cover"
		if global_position.distance_to(goal) < 0.8:
			kneeling = true
	else:
		goal = slot_pos
		action = "form"
	if enemy != null:
		face_point = enemy.global_position
	else:
		face_point = global_position + Vector3(0, 0, -manager.home_z(team))
	# a standing man far from his place hurries; a disciplined one keeps the walk of the line
	var dist_to_goal := global_position.distance_to(goal)
	want_run = dist_to_goal > 6.0 and (p("discipline") < 0.5 or order["mode"] == "fallback") and not tired()


# ---------------------------------------------------------------- the drill's words, for a man

func _drill_sense(id: String, args: Array) -> bool:
	var shared: Variant = manager.shared_sense(id, args, team, rng)
	if shared != null:
		return shared
	var e := _d_enemy
	var ed := _d_enemy_d
	match id:
		"enemy_within":
			return e != null and ed <= float(args[0])
		"enemy_beyond":
			return e == null or ed > float(args[0])
		"enemy_charging":
			return e != null and (e.charging or (String(manager.orders[1 - team].get("mode", "")) == "charge" and ed < 40.0))
		"enemy_in_cover":
			return e != null and (e.kneeling or e.action == "cover")
		"enemy_uphill":
			return e != null and e.global_position.y - global_position.y > 1.5
		"enemy_downhill", "high_ground":
			return e != null and global_position.y - e.global_position.y > 1.5
		"enemy_visible":
			return e != null and field.line_of_fire(global_position + Vector3(0, EYE_HEIGHT, 0), e.global_position + Vector3(0, 1.0, 0)) > 0.0
		"enemy_hidden":
			return e == null or field.line_of_fire(global_position + Vector3(0, EYE_HEIGHT, 0), e.global_position + Vector3(0, 1.0, 0)) <= 0.0
		"enemy_reloading":
			return e != null and not e.loaded
		"spotted":
			return e != null and is_spotted_by(e)
		"loaded":
			return loaded
		"in_cover":
			return not _cover_spot.is_empty() and global_position.distance_to(_cover_spot["pos"]) < 1.2
		"kneeling":
			return kneeling
		"tired":
			return tired()
		"winded":
			return breath > 0.0
		"wounded":
			return wounded
		"courage_under":
			return courage < float(args[0])
		"alone":
			return alone >= 1.0
		"volley_called":
			return float(_d_order.get("volley_age", 999.0)) < 0.7
		"mode_is":
			return String(_d_order.get("mode", "")) == _mode_word(String(args[0]))
		"charging":
			return charging
	return false


## Which way the man is looking (flat, unit length). The body is turned yaw + PI in `_move`.
func facing_dir() -> Vector3:
	var f: Vector3 = -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


## The drill word "spotted": this watcher has me inside a ~140 degree cone, within 90 m, on a
## clear line. A man behind cover, or one the watcher is not looking at, is not spotted.
func is_spotted_by(watcher: Soldier) -> bool:
	if watcher == null or not is_instance_valid(watcher):
		return false
	var to_me: Vector3 = global_position - watcher.global_position
	to_me.y = 0.0
	var d: float = to_me.length()
	if d < 0.01:
		return true
	if d > 90.0:
		return false
	if watcher.facing_dir().dot(to_me / d) < 0.34:
		return false
	return field.line_of_fire(watcher.global_position + Vector3(0, EYE_HEIGHT, 0), global_position + Vector3(0, 1.0, 0)) > 0.0


static func _mode_word(w: String) -> String:
	match w:
		"fallback", "falling", "retreat", "retreating":
			return "fallback"
		"charging":
			return "charge"
		"advancing":
			return "advance"
		"holding":
			return "hold"
	return w


func _drill_act(id: String, args: Array) -> bool:
	var e := _d_enemy
	var ed := _d_enemy_d
	var order := _d_order
	if id != "charge" and not MODIFIERS_MAN.has(id):
		charging = false
	match id:
		"fire":
			if not loaded or e == null or ed > MAX_RANGE or ed < STEEL_RANGE or not _can_fire_at(e):
				return false
			face_point = e.global_position
			if velocity.length() > 0.5 and ed > POINT_BLANK:
				_halt = 0.8
				action = "aim"
				return true
			_volley_seen = int(order.get("volley_id", -1))
			_fire(e)
			return true
		"hold_fire":
			goal = _slot_position(order, order["line_z"])
			action = "form"
			if e != null:
				face_point = e.global_position
			return true
		"charge":
			if e == null or ed > 60.0:
				return false
			charging = true
			action = "charge"
			goal = e.global_position
			face_point = e.global_position
			want_run = not tired()
			if p("discipline") > 0.3 and manager.ahead_of_line(self) > 6.0 and ed > 8.0:
				want_run = false
			if loaded and ed < POINT_BLANK and ed >= STEEL_RANGE and _can_fire_at(e):
				_fire(e)
			return true
		"reload", "reload_kneel":
			if loaded:
				return false
			goal = global_position
			action = "reload"
			kneeling = id == "reload_kneel"
			if e != null:
				face_point = e.global_position
			return true
		"cover":
			var radius: float = float(args[0]) if not args.is_empty() else 12.0
			var threat := Vector3(0, 0, -signf(manager.home_z(team)))
			if e != null:
				threat = (e.global_position - global_position).normalized()
			var spot: Dictionary = _cover_spot if (not _cover_spot.is_empty() and _cover_hold > 0.0) else {}
			if spot.is_empty():
				for sp in field.spots_near(global_position, threat, radius):
					if manager.claim_spot(self, sp):
						spot = sp
						_cover_spot = sp
						_cover_hold = 6.0
						break
			if spot.is_empty():
				return false
			goal = spot["pos"]
			action = "cover"
			kneeling = global_position.distance_to(goal) < 0.8
			want_run = global_position.distance_to(goal) > 6.0 and not tired()
			if e != null:
				face_point = e.global_position
			return true
		"slot", "slot_tight", "slot_loose":
			var pos := _slot_position(order, order["line_z"])
			if id == "slot_tight":
				var n: int = order["count"]
				pos = field.free_point(field.clamp_point(Vector3(float(order["center_x"]) + (float(slot) - float(n - 1) * 0.5) * float(order["spacing"]), 0, float(order["line_z"]))))
			elif id == "slot_loose":
				pos = field.free_point(field.clamp_point(pos + Vector3(_jitter.x * 2.5, 0, _jitter.z * 1.5)))
			goal = pos
			action = "form"
			want_run = global_position.distance_to(goal) > 8.0 and not tired()
			face_point = e.global_position if e != null else global_position + Vector3(0, 0, -manager.home_z(team))
			return true
		"back":
			if e == null:
				return false
			var dist: float = float(args[0]) if not args.is_empty() else 10.0
			var away: Vector3 = global_position - e.global_position
			away.y = 0.0
			goal = field.free_point(global_position + away.normalized() * dist)
			action = "kite"
			want_run = true
			face_point = e.global_position
			kiting = dist / maxf(run_speed, 1.0)
			return true
		"advance":
			if e == null:
				return false
			var toward: Vector3 = e.global_position - global_position
			toward.y = 0.0
			goal = field.free_point(global_position + toward.normalized() * minf(6.0, maxf(ed - 3.0, 0.0)))
			action = "form"
			face_point = e.global_position
			return true
		"sneak":
			# Creep from cover to cover toward the enemy, walking, drifting toward his flank.
			# No cover ahead: a slow walk on the same slant. Never runs.
			if e == null:
				return false
			var to_e: Vector3 = e.global_position - global_position
			to_e.y = 0.0
			var dirn: Vector3 = to_e.normalized()
			var hop: float = float(args[0]) if not args.is_empty() else 16.0
			var spot: Dictionary = _cover_spot if (not _cover_spot.is_empty() and _cover_hold > 0.0) else {}
			if spot.is_empty():
				var side: float = signf(global_position.x - e.global_position.x)
				if side == 0.0:
					side = 1.0 if slot % 2 == 0 else -1.0
				var best_score := -INF
				for sp in field.spots_near(global_position, dirn, hop):
					var sp_pos: Vector3 = sp["pos"]
					var progress: float = ed - sp_pos.distance_to(e.global_position)
					if progress < 3.0:
						continue
					var lateral: float = (sp_pos.x - global_position.x) * side
					var score: float = progress + 0.35 * lateral
					if score > best_score and manager.claim_spot(self, sp):
						best_score = score
						spot = sp
				if not spot.is_empty():
					_cover_spot = spot
					_cover_hold = 3.0 + global_position.distance_to(spot["pos"]) * 0.6
			if not spot.is_empty():
				goal = spot["pos"]
				kneeling = global_position.distance_to(goal) < 0.8
			else:
				var side2: float = signf(global_position.x - e.global_position.x)
				if side2 == 0.0:
					side2 = 1.0 if slot % 2 == 0 else -1.0
				var slant: Vector3 = dirn.rotated(Vector3.UP, side2 * -0.6)
				goal = field.free_point(global_position + slant * minf(5.0, maxf(ed - 3.0, 0.0)))
				kneeling = false
			action = "cover"
			want_run = false
			face_point = e.global_position
			return true
		"hold", "hold_kneel":
			goal = global_position
			action = "form"
			kneeling = id == "hold_kneel"
			if e != null:
				face_point = e.global_position
			return true
		"follow":
			_d_follow = true
			return true
		"stand_fast":
			_stand_fast = 1.0
			return true
		"run":
			_rout()
			return true
		"set_phase":
			manager.drill_phase[team] = String(args[0])
			return true
	return false


const MODIFIERS_MAN := ["stand_fast", "set_phase", "follow"]


## The slot in the line, offset by how loosely this man keeps station.
func _slot_position(order: Dictionary, line_z: float) -> Vector3:
	var n: int = order["count"]
	var spacing: float = order["spacing"]
	var x: float = order["center_x"] + (float(slot) - float(n - 1) * 0.5) * spacing
	var loose := (1.0 - p("cohesion")) * 2.2
	var pos := Vector3(x + _jitter.x * loose, 0, line_z + _jitter.z * loose * 0.6)
	return field.free_point(field.clamp_point(pos))


## A cover spot near the slot, if this man values cover more than his place in the line.
func _pick_cover(slot_pos: Vector3, enemy: Soldier) -> Dictionary:
	var want := p("cover") - 0.35 * p("discipline")
	if manager.orders[team].get("seek_cover", false):
		want = maxf(want, 0.5)   # the sergeant has seen the exchange; any wall will do
	if want < 0.2:
		return {}
	if not _cover_spot.is_empty() and _cover_hold > 0.0:
		return _cover_spot
	var threat_dir := Vector3(0, 0, -signf(manager.home_z(team)))
	if enemy != null:
		threat_dir = (enemy.global_position - slot_pos).normalized()
	var radius := 4.0 + 12.0 * want
	var cands := field.spots_near(slot_pos, threat_dir, radius)
	for s in cands:
		if manager.claim_spot(self, s):
			_cover_spot = s
			_cover_hold = 6.0
			return s
	_cover_spot = {}
	return {}


func _can_fire_at(enemy: Soldier) -> bool:
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var to := enemy.global_position + Vector3(0, 1.0, 0)
	if field.line_of_fire(from, to) <= 0.0:
		return false
	# a friend in the line of fire: a disciplined man holds, a careless one does not
	var friend := manager.friend_in_line(self, enemy)
	if friend != null and p("discipline") > 0.4:
		return false
	return true


func _fire(enemy: Soldier) -> void:
	loaded = false
	reload_left = reload_time
	_halt = 1.2
	shots += 1
	_fire_anim = 0.35
	face_point = enemy.global_position
	# the shot is flown, not rolled: an aim with a spread, a ball that falls, a body it
	# either meets or does not - and if not, whoever stands further down the line
	var from := global_position + Vector3(0, EYE_HEIGHT, 0)
	var top := Ballistics.KNEEL_H if enemy.kneeling else Ballistics.BODY_H
	var aim_h := 0.75 if enemy.kneeling else Ballistics.AIM_H
	var feet := enemy.global_position
	var aim := feet + Vector3(0, aim_h, 0)
	var to := enemy.global_position + Vector3(0, 1.0, 0)
	var d := from.distance_to(aim)
	var dir := (aim - from) / maxf(d, 0.01)
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir)
	# the spread: the man's own, opened up by battle and by everything else about the moment
	var sig := Ballistics.sigma_range(soldier_type.skill("accuracy")) * 0.001 * Ballistics.BATTLE
	var mv := velocity.length()
	if mv > 0.5:
		sig *= 2.0 if mv < 2.5 else 3.3   # firing on the move costs a lot; at the run, most of it
	if kneeling:
		sig *= 0.8                        # a knee and a wall to rest on
	if tired():
		sig *= 1.3
	elif breath > 0.0:
		sig *= 1.6                        # winded from a run
	if wounded:
		sig *= 1.25
	sig *= 1.0 + 0.8 * fear               # balls going past his ear
	if order_volley():
		sig *= 1.1                        # on the word, not on his own time
	sig *= clampf(1.0 - (from.y - aim.y) * 0.04, 0.8, 1.15)   # looking down on them steadies the aim
	var dev_h := Ballistics.gauss(rng) * sig
	var dev_v := Ballistics.gauss(rng) * sig + sig * 0.2   # frightened men shoot high
	# a moving target has to be led; nobody leads it exactly
	var tv := enemy.velocity
	tv.y = 0.0
	var lead_err := Ballistics.gauss(rng) * 0.5 * absf(tv.dot(right)) * Ballistics.time_to(d)
	var ball := func(x: float) -> Vector3:
		return from + dir * x + right * (dev_h * x + lead_err * x / maxf(d, 0.01)) + up * (dev_v * x) + Vector3.UP * Ballistics.rise(x)
	# at the target: does the ball meet the man?
	var at: Vector3 = ball.call(d)
	var ox := (at - aim).dot(right)
	var oy := at.y - feet.y
	var hit := absf(ox) < Ballistics.BODY_W * 0.5 and oy > 0.0 and oy < top
	var victim: Soldier = enemy
	var end_x := d
	if hit:
		# cover between: the wall, the fence rail or the crest takes some of what would have hit
		var cover_f := field.line_of_fire(from, to)
		if enemy.kneeling and cover_f < 1.0:
			cover_f *= 0.8
		if cover_f < 1.0 and d < 15.0:
			cover_f = lerpf(cover_f, 1.0, (15.0 - d) / 15.0 * 0.6)   # at a few paces a wall hides less
		if rng.randf() > cover_f:
			hit = false
	else:
		# a miss flies on: the first man whose body is where the ball is, friend or foe, takes it
		var best_x := INF
		var reach := d + 80.0
		# where does it come down?
		var x := d
		while x < reach:
			var p: Vector3 = ball.call(x)
			if p.y < field.height_at(p.x, p.z) or not field.in_bounds(p, -6.0):
				break
			x += 2.0
		end_x = x
		for o in manager.alive_soldiers():
			if o == self or o == enemy:
				continue
			var rel := o.global_position - from
			var ax := rel.dot(dir)
			if ax < 1.2 or ax > end_x or ax > best_x:
				continue
			var bp: Vector3 = ball.call(ax)
			var side := (o.global_position - bp).dot(right)
			var h := bp.y - o.global_position.y
			var o_top := Ballistics.KNEEL_H if o.kneeling else Ballistics.BODY_H
			if absf(side) < Ballistics.BODY_W * 0.5 and h > 0.0 and h < o_top:
				best_x = ax
				victim = o
				oy = h
				top = o_top
		if best_x < INF:
			hit = true
			end_x = best_x
			if victim.team == team:
				friendly_hits += 1
	if hit:
		# where it lands matters: the body and head kill, the legs mostly wound
		var upper := oy > top * 0.5
		var kill := rng.randf() < (0.62 if upper else 0.2)
		var dmg := MAX_HP if kill else WOUND
		victim.take_damage(dmg, "rifle", self)
		if victim.team != team:
			hits += 1
			dmg_done += dmg
	fired.emit(self, victim, hit)
	manager.volley_pressure(self, to, hit)
	_muzzle_flash_arc(ball, end_x)


## Is this shot on the sergeant's word?
func order_volley() -> bool:
	var o: Dictionary = manager.orders[team]
	return float(o.get("volley_age", 999.0)) < 0.7


func _try_thrust(enemy: Soldier) -> void:
	if thrust_timer > 0.0:
		return
	thrust_timer = BAYONET_COOLDOWN / (0.7 + 0.5 * soldier_type.skill("melee"))
	thrusts += 1
	_thrust_anim = 0.3
	var p_hit := 0.6 * melee_mult / (0.5 + 0.6 * enemy.melee_mult)
	if charging and running:
		p_hit *= 1.3   # the weight of the charge behind the first thrust
	if not enemy.loaded and enemy.action != "melee" and enemy.action != "charge":
		p_hit *= 1.25  # caught with the ramrod in the barrel
	if enemy.kneeling:
		p_hit *= 1.2   # a man on his knee behind a wall has no room to parry
	if enemy.is_routed or enemy.action == "rout":
		p_hit *= 1.5
	if tired():
		p_hit *= 0.75
	var landed := rng.randf() < clampf(p_hit, 0.08, 0.95)
	if landed:
		thrust_hits += 1
		var dmg := BAYONET_DMG * melee_mult * rng.randf_range(0.8, 1.3)
		dmg_done += dmg
		enemy.take_damage(dmg, "bayonet", self)
	thrust.emit(self, landed)


func take_damage(amount: float, source: String, attacker: Soldier) -> void:
	if not alive:
		return
	hp -= amount
	damaged.emit(self, amount, source, attacker)
	_flash()
	if hp <= 0.0:
		_die(source, attacker)
		return
	wounded = true
	walk_speed *= 0.7
	run_speed *= 0.7
	fear = minf(fear + 0.15, 0.6)


func notice_death(where: Vector3) -> void:
	var d := global_position.distance_to(where)
	if d < 6.0:
		fear = minf(fear + 0.12 * (1.0 - d / 6.0) + 0.04, 0.6)


func _die(source: String, attacker: Soldier) -> void:
	alive = false
	hp = 0.0
	if attacker != null and attacker.team != team:
		attacker.kills += 1
		if source == "bayonet":
			attacker.bayonet_kills += 1
	died.emit(self, source, attacker)
	_spawn_ragdoll(attacker)


func _flee() -> void:
	gone = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	fled.emit(self)


# ---------------------------------------------------------------- movement

func _move(delta: float) -> void:
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	var speed := 0.0
	var dir := Vector3.ZERO
	var stop_at := 0.35 if action != "melee" and action != "charge" else BAYONET_REACH - 0.4
	if _halt > 0.0 and action != "melee" and action != "rout":
		dist = 0.0
	if dist > stop_at:
		dir = to_goal / dist
		running = want_run and not tired()
		speed = run_speed if running else walk_speed
		if dist < 2.0 and not running:
			speed *= clampf(dist / 1.5, 0.4, 1.0)
	else:
		running = false
	# unstick: a man wedged on a wall or a comrade wanders sideways for a moment
	if _detour > 0.0:
		_detour -= delta
		dir = _detour_dir
		speed = maxf(speed, walk_speed)
	elif speed > 0.0:
		if global_position.distance_to(_last_pos) < 0.02 * (speed / WALK):
			_stuck += delta
		else:
			_stuck = 0.0
		if _stuck > 0.7:
			_stuck = 0.0
			_detour = rng.randf_range(0.4, 0.9)
			var side := Vector3(-dir.z, 0, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
			_detour_dir = (side * 0.9 + dir * 0.3).normalized()
	_last_pos = global_position
	# keep a shoulder's width from the next man rather than shove through him
	var push := manager.separation(self)
	# the hill: a climb slows a man, a descent hurries him a little
	if speed > 0.0:
		var climb := field.slope(global_position, dir)
		speed *= clampf(1.0 - climb * 0.8, 0.6, 1.12)
	velocity = dir * speed + push * 1.2
	velocity.y = 0.0
	move_and_slide()
	global_position.y = field.height_at(global_position.x, global_position.z)
	# facing
	var face := face_point - global_position
	face.y = 0.0
	if action == "rout" or action == "kite" or (action == "fallback" and want_run):
		face = dir if dir.length() > 0.1 else face
	elif dir.length() > 0.1 and (action == "form" or action == "charge" or action == "cover") and dist > 1.5:
		face = dir
	if face.length() > 0.05:
		var yaw := atan2(face.x, face.z)
		rotation.y = lerp_angle(rotation.y, yaw + PI, clampf(delta * 8.0, 0.0, 1.0))


# ---------------------------------------------------------------- body

func _build_body() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = team_color
	_dark_mat = StandardMaterial3D.new()
	_dark_mat.albedo_color = Color(0.22, 0.2, 0.2)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.95, 0.85, 0.7)
	var trouser := StandardMaterial3D.new()
	trouser.albedo_color = Color(0.35, 0.36, 0.45) if team == 1 else Color(0.5, 0.5, 0.52)

	var torso := MeshInstance3D.new()
	torso.mesh = _box(Vector3(0.5, 0.65, 0.3))
	torso.material_override = _mat
	torso.position = Vector3(0, 1.15, 0)
	body_root.add_child(torso)
	var head := MeshInstance3D.new()
	head.mesh = _box(Vector3(0.28, 0.28, 0.28))
	head.material_override = _eye_mat
	head.position = Vector3(0, 1.66, 0)
	body_root.add_child(head)
	var cap := MeshInstance3D.new()
	cap.mesh = _box(Vector3(0.32, 0.16, 0.34))
	cap.material_override = _dark_mat
	cap.position = Vector3(0, 1.86, -0.02)
	body_root.add_child(cap)
	var peak := MeshInstance3D.new()
	peak.mesh = _box(Vector3(0.3, 0.03, 0.12))
	peak.material_override = _dark_mat
	peak.position = Vector3(0, 1.79, -0.2)
	body_root.add_child(peak)
	arm_l = MeshInstance3D.new()
	arm_l.mesh = _box(Vector3(0.14, 0.6, 0.14))
	arm_l.material_override = _mat
	arm_l.position = Vector3(-0.34, 1.2, 0)
	body_root.add_child(arm_l)
	arm_r = MeshInstance3D.new()
	arm_r.mesh = _box(Vector3(0.14, 0.6, 0.14))
	arm_r.material_override = _mat
	arm_r.position = Vector3(0.34, 1.2, 0)
	body_root.add_child(arm_r)
	leg_l = _leg(trouser, -0.14)
	leg_r = _leg(trouser, 0.14)
	# the rifle: stock, barrel, bayonet
	rifle = Node3D.new()
	rifle.position = Vector3(0.22, 1.3, -0.25)
	body_root.add_child(rifle)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.26, 0.14)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.72, 0.75)
	steel.metallic = 0.6
	var stock := MeshInstance3D.new()
	stock.mesh = _box(Vector3(0.07, 0.09, 0.9))
	stock.material_override = wood
	stock.position = Vector3(0, -0.02, -0.15)
	rifle.add_child(stock)
	var barrel := MeshInstance3D.new()
	barrel.mesh = _box(Vector3(0.035, 0.035, 1.1))
	barrel.material_override = steel
	barrel.position = Vector3(0, 0.04, -0.4)
	rifle.add_child(barrel)
	var bayonet := MeshInstance3D.new()
	bayonet.mesh = _box(Vector3(0.02, 0.02, 0.42))
	bayonet.material_override = steel
	bayonet.position = Vector3(0, 0.04, -1.15)
	rifle.add_child(bayonet)
	_smoke = CPUParticles3D.new()
	_smoke.emitting = false
	_smoke.one_shot = true
	_smoke.amount = 14
	_smoke.lifetime = 1.4
	_smoke.explosiveness = 0.9
	_smoke.direction = Vector3(0, 0.4, -1)
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 1.5
	_smoke.initial_velocity_max = 3.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.scale_amount_min = 0.35
	_smoke.scale_amount_max = 0.8
	_smoke.damping_min = 2.0
	_smoke.damping_max = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	_smoke.mesh = sm
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.9, 0.9, 0.86, 0.6)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke.material_override = smoke_mat
	_smoke.position = Vector3(0, 0.04, -1.0)
	rifle.add_child(_smoke)

	label = Label3D.new()
	label.text = soldier_name if rounds == 0 else "%s *%d" % [soldier_name, rounds]   # *n: rounds survived
	label.font_size = 26
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.35, 0)
	label.modulate = Color(1, 1, 1, 0.85)
	add_child(label)
	# hp bar
	var bar_bg := MeshInstance3D.new()
	var bgq := QuadMesh.new()
	bgq.size = Vector2(0.9, 0.1)
	bar_bg.mesh = bgq
	bar_bg.material_override = _bar_material(Color(0.1, 0.1, 0.1, 0.8), 1)
	bar_bg.position = Vector3(0, 2.12, 0)
	add_child(bar_bg)
	_bar_fg = MeshInstance3D.new()
	_bar_quad = QuadMesh.new()
	_bar_quad.size = Vector2(0.88, 0.08)
	_bar_fg.mesh = _bar_quad
	_bar_fg.material_override = _bar_material(Color(0.3, 0.9, 0.3, 0.95), 2)
	_bar_fg.position = Vector3(0, 2.12, 0.001)
	add_child(_bar_fg)


func _leg(mat: Material, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0.82, 0)
	body_root.add_child(pivot)
	var m := MeshInstance3D.new()
	m.mesh = _box(Vector3(0.18, 0.8, 0.18))
	m.material_override = mat
	m.position = Vector3(0, -0.4, 0)
	pivot.add_child(m)
	var boot := MeshInstance3D.new()
	boot.mesh = _box(Vector3(0.2, 0.1, 0.3))
	boot.material_override = _dark_mat
	boot.position = Vector3(0, -0.78, -0.05)
	pivot.add_child(boot)
	return pivot


func _bar_material(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = prio
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _animate(delta: float) -> void:
	var v := velocity.length()
	if v > 0.2:
		_gait += delta * (10.0 if running else 6.0)
		var a := (0.6 if running else 0.35) * sin(_gait)
		leg_l.rotation.x = a
		leg_r.rotation.x = -a
	else:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, delta * 8.0)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, delta * 8.0)
	# kneel: drop the body, fold the legs
	var kneel_y := -0.55 if kneeling else 0.0
	body_root.position.y = lerpf(body_root.position.y, kneel_y, delta * 6.0)
	if kneeling:
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.4, delta * 6.0)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 1.3, delta * 6.0)
	# the rifle: level when aiming or charging, upright when reloading
	var rx := 0.0
	var rz := rifle.position.z
	if _fire_anim > 0.0:
		_fire_anim -= delta
		rx = 0.15 * (_fire_anim / 0.35)
		rz = -0.12
	elif _thrust_anim > 0.0:
		_thrust_anim -= delta
		rz = -0.25 - 0.5 * sin(_thrust_anim / 0.3 * PI)
	elif not loaded and not running:
		rx = 1.35   # ramrod work
		rz = -0.15
	elif action == "charge" or action == "melee":
		rx = -0.1
		rz = -0.35
	elif action == "form" or action == "fallback" or action == "rout":
		rx = 0.9 if v > 0.2 else 0.05   # at the shoulder on the march
		rz = -0.25
	else:
		rx = 0.05
		rz = -0.25
	rifle.rotation.x = lerpf(rifle.rotation.x, rx, delta * 10.0)
	rifle.position.z = lerpf(rifle.position.z, rz, delta * 10.0)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, -1.2 if rx < 0.5 else -0.4, delta * 8.0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -1.3 if rx < 0.5 else -1.6, delta * 8.0)
	_bar_quad.size.x = 0.88 * clampf(hp / MAX_HP, 0.0, 1.0)
	_bar_fg.position.x = -(0.88 - _bar_quad.size.x) * 0.5
	(_bar_fg.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.9, 0.3, 0.95).lerp(Color(0.95, 0.3, 0.2, 0.95), 1.0 - hp / MAX_HP)
	if is_routed:
		label.modulate = Color(1.0, 0.85, 0.3, 0.9)


## The smoke, and the ball's flight drawn as a faint arc from the muzzle to where it ended.
func _muzzle_flash_arc(ball: Callable, end_x: float) -> void:
	if manager.headless:
		return
	_smoke.restart()
	_smoke.emitting = true
	var tr := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.6, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var n := maxi(int(end_x / 6.0), 3)
	for k in range(n + 1):
		var x := 1.2 + (end_x - 1.2) * float(k) / n
		im.surface_add_vertex(ball.call(x))
	im.surface_end()
	tr.mesh = im
	get_parent().add_child(tr)
	var tw := get_tree().create_tween()
	tw.tween_property(tr, "transparency", 1.0, 0.25)
	tw.tween_callback(tr.queue_free)


func _muzzle_flash(from: Vector3, to: Vector3) -> void:
	if manager.headless:
		return
	_smoke.restart()
	_smoke.emitting = true
	# a brief tracer so the eye can follow the shot
	var tr := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.6, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from + (to - from).normalized() * 1.2)
	im.surface_add_vertex(to)
	im.surface_end()
	tr.mesh = im
	get_parent().add_child(tr)
	var tw := get_tree().create_tween()
	tw.tween_property(tr, "transparency", 1.0, 0.18)
	tw.tween_callback(tr.queue_free)


func _flash() -> void:
	if manager.headless:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_mat.albedo_color = Color(1, 1, 1)
	_flash_tween = get_tree().create_tween()
	_flash_tween.tween_property(_mat, "albedo_color", team_color, 0.25)


func _spawn_ragdoll(attacker: Soldier) -> void:
	collision_layer = 0
	collision_mask = 0
	label.visible = false
	_bar_fg.visible = false
	if manager.headless:
		body_root.visible = false
		return
	body_root.visible = false
	ragdoll = Ragdoll.new()
	ragdoll.field = field
	get_parent().add_child(ragdoll)
	ragdoll.build(body_root.global_transform, _mat, _dark_mat, _eye_mat)
	var shove := Vector3(0, 1.5, 0)
	if attacker != null:
		var d := global_position - attacker.global_position
		d.y = 0.0
		shove += d.normalized() * 4.0
	else:
		shove += Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
	ragdoll.shove(shove)
