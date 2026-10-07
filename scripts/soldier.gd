class_name Soldier
extends CharacterBody3D
## One line infantryman: a single-shot rifle, a bayonet, two legs and a personality. Nothing
## here takes an order as a command. The sergeant (match_manager.gd) publishes what the line
## is doing - where it stands, how far apart, whether he has called the volley or the charge
## or the fall-back - and each man decides, through his own traits, how much of that to follow.

signal fired(soldier: Soldier, target: Soldier, hit: bool)
signal damaged(soldier: Soldier, amount: float, source: String, attacker: Soldier)
signal died(soldier: Soldier, source: String, attacker: Soldier)
signal rallied(s: Soldier)
signal routed(soldier: Soldier)
signal fled(soldier: Soldier)
signal thrust(soldier: Soldier, landed: bool)

const MAX_HP := 100.0
const WALK := 1.7
const RUN := 4.6
const RELOAD := 20.0           # seconds: the fastest a man can shoot, one round every 20 s (owner, 2026-09-30)
const GRENADES := 1             # a Grenadier's hand grenades
const AMMO := 20               # rounds in the cartridge box, the loaded one included
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
var company := 0              # which company of his battalion

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
var ammo := AMMO               # rounds left, the one in the barrel included
## Has he been under fire yet: shot at, hit, a mate fallen near him, or a bayonet charge on him.
## A man who has not cannot run - raw troops break under fire, not at the sight of it.
var under_fire := false
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
var _bleed_t := 0.0
var _still_t := 0.0
var _round_co := []            # going round: [team, company] he set out to get behind
var _round_side := 0.0         # ... and which end of their line he goes round (-1 / +1)
var _round_wide := false       # ... and whether he is out wide yet
var grenades := 0               # Grenadiers carry a few (GRENADES)
var _grenade_cd := 0.0
var _kite_lock := 0.0          # after running back: this long standing his ground before he may run back again
var _about_face := false       # falling back with his back to the enemy (full walking pace, no shooting)
var _last_fire_t := -100.0       # a shot gives a man away: flash and a puff of smoke
var _sneak_t := 0.0             # how long he has stood still: a musket is aimed standing
var _aim_need := 1.6            # how long this shot takes to aim
var _high_spot := Vector3.INF   # the rise he is making for
var _high_hold := 0.0
var _jitter := Vector3.ZERO

# stats (kills is the career total in a campaign; kills_before is where this round started)
var kills_before := 0
var rounds := 0
var record_seed := 0
var shots := 0
var hits := 0
var kills := 0
var bayonet_kills := 0
var grenade_kills := 0
var _stunned := 0.0             # knocked down by a burst: this long before he is up and doing again
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
var _bar_bg: MeshInstance3D
var _core_mi: MeshInstance3D
var _smoke_t := 0.0
static var _white_mat: StandardMaterial3D = null
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
	# a trained marksman reloads in the 20 s floor; an even man ~24 s, a raw hand ~30 s
	reload_time = RELOAD * 1.2 / (0.8 + 0.4 * st.skill("accuracy"))
	ammo = AMMO
	grenades = GRENADES if soldier_type != null and soldier_type.label() == "Grenadier" else 0
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
	if wounded and manager.fx != null:
		# a wounded man bleeds as he goes
		_bleed_t -= delta
		if _bleed_t <= 0.0:
			_bleed_t = rng.randf_range(0.5, 1.4)
			manager.fx.drip(global_position)
	if _stunned > 0.0:
		# knocked flat by a burst: down on the ground, doing nothing, an easy mark
		_stunned -= delta
		velocity = Vector3.ZERO
		kneeling = true
		action = "stunned"
		_animate(delta)
		return
	decide_timer -= delta
	if decide_timer <= 0.0:
		decide_timer = DECISION_INTERVAL + rng.randf_range(0.0, 0.05)
		_decide()
	_move(delta)
	_animate(delta)


func _tick_timers(delta: float) -> void:
	if not loaded and ammo > 0:
		var r := 1.0
		if tired():
			r = 0.7
		if running:
			r = 0.0   # nobody reloads a muzzle-loader at the run
		elif velocity.length() > 0.5:
			r *= 0.3  # ... and walking, he fumbles it: a man stops to load
		elif kneeling:
			r *= 0.9
		reload_left -= delta * r
		if reload_left <= 0.0:
			loaded = true
	_still_t = _still_t + delta if velocity.length() < 0.5 else 0.0
	_sneak_t = maxf(_sneak_t - delta, 0.0)
	thrust_timer = maxf(thrust_timer - delta, 0.0)
	kiting = maxf(kiting - delta, 0.0)
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	_kite_lock = maxf(_kite_lock - delta, 0.0)
	_halt = maxf(_halt - delta, 0.0)
	_cover_hold = maxf(_cover_hold - delta, 0.0)
	_high_hold = maxf(_high_hold - delta, 0.0)
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
	# men of his own side who have run count half: a mate running is bad, but it is not the
	# same as a mate killed - otherwise one jumpy man sets off the whole line
	var outnumbered: float = clampf(1.0 - manager.morale_ratio(team), 0.0, 1.0)
	# ... and a man with nobody at his elbow feels every bit of it: loose order has its price
	courage = p("nerve") * 1.15 - losses * 0.75 - hurt * 0.3 - fear * 0.35 - outnumbered * 0.25 - alone * 0.2 + 0.05
	_stand_fast = maxf(_stand_fast - delta, 0.0)
	if not is_routed and under_fire and courage < 0.1 and manager.elapsed > 3.0 and _stand_fast <= 0.0 and float(manager.stand_fast_until.get(MatchManager.ck(team, company), -1.0)) < manager.elapsed:
		_rout()


func _rout() -> void:
	if manager.fx != null:
		manager.fx.rout(global_position)
	is_routed = true
	charging = false
	kneeling = false
	action = "rout"
	routed.emit(self)


func _decide() -> void:
	var order: Dictionary = manager.orders[team][company]
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
		# a man who has broken runs for the rear and off the field, in reach of the enemy's rifles
		# and bayonets every step of the way - unless he steadies: well clear of the enemy, his
		# nerve coming back, and other men of his side about him (runners gathering together, or
		# a company still standing) - then he turns and comes back to his company
		if enemy_d > 40.0:
			fear = maxf(fear - 0.05, 0.0)   # out of the fire his heart slows (on top of the usual)
		if enemy_d > 40.0 and rng.randf() < 0.2:
			var near := 0
			for o in manager.alive_soldiers():
				if o != self and o.team == team and o.global_position.distance_to(global_position) < 8.0:
					near += 1
					if near >= 5:
						break
			# his own nerve, what has been done to him, and the men about him - not the day's
			# losses, which have already done their work
			var steady := p("nerve") - fear * 0.6 - (1.0 - hp / MAX_HP) * 0.4 + 0.08 * near \
				- clampf(1.0 - manager.morale_ratio(team), 0.0, 1.0) * 0.2
			if near >= 2 and steady > 0.35:
				is_routed = false
				fear = minf(fear, 0.2)
				_stand_fast = 6.0   # a moment's resolve before the next shock can break him again
				rallied.emit(self)
	if is_routed:
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

	# a grenade: men behind a wall or bunched together, 8 to 25 m off - light the fuse and throw
	if grenades > 0 and _grenade_cd <= 0.0 and enemy != null and not in_melee and enemy_d > 8.0 and enemy_d < 25.0:
		var bunch := 0
		for o in manager.fighting(1 - team):
			if o.global_position.distance_to(enemy.global_position) < 3.0:
				bunch += 1
		var walled := enemy.kneeling or String(enemy.action) == "cover"
		if (bunch >= 4 or walled) and manager.friends_near(self, enemy.global_position, 4.0) == 0:
			_throw_grenade(enemy.global_position)
			return

	# the drill first: the first rule that holds and can be done decides; "follow sergeant"
	# (or no rule at all) hands the tick to the engine below
	# (when the company has been ordered in with the bayonet, the order stands over a man's own
	# drill - nobody stays behind to load and fire, or kneel, while his company charges)
	var ordered_in: bool = order["mode"] == "charge" and not is_routed
	if drill != null and not drill.man_rules.is_empty() and not ordered_in:
		_d_enemy = enemy
		_d_enemy_d = enemy_d
		_d_order = order
		_d_follow = false
		if drill.run(drill.man_rules, _drill_sense, _drill_act, _d_memory, manager.elapsed, manager.tally_for(team, company)) and not _d_follow:
			return

	# the charge: the sergeant's, or my own blood up
	var charge_order: bool = ordered_in
	if charge_order:
		charging = true
	elif enemy != null and enemy_d < 10.0 and p("aggression") > 0.8:
		charging = true
	elif enemy != null and enemy_d < 7.0 and not loaded and p("aggression") > 0.25:
		charging = true   # empty rifle, enemy on top of me: the bayonet is what's left
	if charge_order and charging and enemy == null:
		# ordered in but nobody in sight of his own: go for the nearest of theirs the company knows of
		enemy = manager.nearest_enemy_any(self)
		enemy_d = global_position.distance_to(enemy.global_position) if enemy != null else INF
	if charging and (enemy == null or (enemy_d > 45.0 and not charge_order) or (not charge_order and enemy_d > 14.0 and p("aggression") < 0.8)):
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
	if loaded and enemy != null and enemy_d <= fire_range_to(enemy) and enemy_d >= STEEL_RANGE and _can_fire_at(enemy):
		var my_range := 75.0 - 50.0 * p("patience")
		var volley_now: bool = order["volley_id"] != _volley_seen and order["volley_age"] < 0.7 \
			and (int(order.get("volley_half", -1)) < 0 or slot % 2 == int(order["volley_half"]))   # by halves: his half's turn
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
		if fire_now and enemy_d > POINT_BLANK and not (_aimed() or (volley_now and velocity.length() < 0.5)):
			_halt = maxf(_halt, _aim_need - _still_t + 0.1)   # stop, bring it up, aim - then shoot
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
		if order.get("withdraw", false) and absf(global_position.z) > Field.HALF_Z - 1.5:
			_flee()   # shot out: off the field, back to the waggons
			return
		want_run = p("nerve") < 0.5
		# with the enemy well off he turns about and marches back; close to them he backs away
		# facing them, rifle ready - and that is slow (see _move)
		_about_face = enemy == null or global_position.distance_to(enemy.global_position) > 25.0
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
	if order.get("rush", false) and dist_to_goal > 2.0 and not tired():
		want_run = true   # the rush: run in before their first volley


# ---------------------------------------------------------------- the drill's words, for a man

func _drill_sense(id: String, args: Array) -> bool:
	var shared: Variant = manager.shared_sense(id, args, team, company, rng)
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
			return e != null and (e.charging or (String(manager.orders[1 - team][e.company].get("mode", "")) == "charge" and ed < 40.0)) \
				and not field.water_between(global_position, e.global_position)   # not across a river
		"enemy_in_cover":
			return e != null and (e.kneeling or e.action == "cover")
		"in_smoke":
			return field.smoke_at(global_position.x, global_position.z) >= 2.0
		"enemy_in_smoke":
			return e != null and field.smoke_at(e.global_position.x, e.global_position.z) >= 2.0
		"smoke_between":
			return e != null and field.visibility(global_position + Vector3(0, EYE_HEIGHT, 0), e.global_position + Vector3(0, 1.0, 0)) < 0.5
		"wind_behind":
			var fwd := (e.global_position - global_position) if e != null else Vector3(0, 0, -signf(manager.home_z(team)))
			var f2 := Vector2(fwd.x, fwd.z).normalized()
			return field.wind.length() > 0.3 and field.wind.normalized().dot(f2) > 0.4
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
		"behind_enemy":
			return e != null and _behind_line_of(e)
		"loaded":
			return loaded
		"out_of_ammo":
			return ammo <= 0 and not loaded
		"ammo_under":
			return ammo < int(args[0])
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
			var half := int(_d_order.get("volley_half", -1))
			return float(_d_order.get("volley_age", 999.0)) < 0.7 and (half < 0 or slot % 2 == half)
		"mode_is":
			return String(_d_order.get("mode", "")) == _mode_word(String(args[0]))
		"charging":
			return charging
	return false


## The enemy is beyond my rifle (or not seen at all) while my company goes forward.
func _out_of_reach(e: Soldier, ed: float) -> bool:
	if String(manager.orders[team][company].get("mode", "")) != "advance":
		return false
	return e == null or ed > fire_range_to(e) + 10.0


## Am I behind the line of e's company - on the side of it toward their own rear?
func _behind_line_of(e: Soldier) -> bool:
	var ord: Dictionary = manager.orders[e.team][e.company]
	var cen: Vector3 = ord.get("centre", e.global_position)
	return (global_position.z - cen.z) * signf(manager.home_z(e.team)) > 4.0


## Is `other` behind me - outside what a man looking ahead can see (about 100 degrees either side)?
func is_behind_me(other: Soldier) -> bool:
	var to_o := other.global_position - global_position
	to_o.y = 0.0
	if to_o.length() < 0.01:
		return false
	return facing_dir().dot(to_o.normalized()) < -0.17


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
	if d > minf(90.0, notice_range()):
		return false
	if watcher.facing_dir().dot(to_me / d) < 0.34:
		return false
	var eye := watcher.global_position + Vector3(0, EYE_HEIGHT, 0)
	var me := global_position + Vector3(0, 1.0, 0)
	if field.visibility(eye, me) < 0.3:
		return false   # lost in the smoke
	return field.line_of_fire(eye, me) > 0.0


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
	# out of range with the company going forward, a man does not stop to kneel, load or tuck in
	# behind the nearest rock - he goes with the line until there is something to shoot at
	if id in ["hold", "hold_kneel", "reload_kneel", "cover", "high_ground"] and _out_of_reach(e, ed):
		return false
	var order := _d_order
	if id != "charge" and not MODIFIERS_MAN.has(id):
		charging = false
	match id:
		"fire":
			if not loaded or e == null or ed > fire_range_to(e) or ed < STEEL_RANGE or not _can_fire_at(e):
				return false
			face_point = e.global_position
			if ed > POINT_BLANK and not _aimed():
				_halt = maxf(_halt, _aim_need - _still_t + 0.1)
				action = "aim"
				goal = global_position
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
			if loaded or ammo <= 0:
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
			# one clean run back - then stand, load and fire, and only then see whether to go back
			# again (no dithering back and forth every second)
			if kiting > 0.0 and action == "kite":
				return true
			if _kite_lock > 0.0:
				return false
			var dist: float = float(args[0]) if not args.is_empty() else 10.0
			var away: Vector3 = global_position - e.global_position
			away.y = 0.0
			goal = field.free_point(global_position + away.normalized() * dist)
			action = "kite"
			want_run = true
			face_point = e.global_position
			kiting = dist / maxf(run_speed, 1.0)
			_kite_lock = kiting + 6.0
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
		"go_round":
			# Out round the end of the enemy's line - wide, walking, keeping low - and in behind it,
			# where the men are all looking the other way. Then the drill's "behind the enemy" rule
			# sends him in. He keeps to the company he set out for and the side he chose, and does not
			# turn back once he is out wide (no going back and forth).
			if e == null:
				return false
			if _round_co.size() == 2 and not manager.fighting_company(int(_round_co[0]), int(_round_co[1])).is_empty():
				e = manager.fighting_company(int(_round_co[0]), int(_round_co[1]))[0]
			else:
				_round_co = [e.team, e.company]
				_round_side = 0.0
				_round_wide = false
			var ord: Dictionary = manager.orders[e.team][e.company]
			var cen: Vector3 = ord.get("centre", e.global_position)
			var back := signf(manager.home_z(e.team))            # the way to the enemy's rear
			var half_w := maxf(8.0, float(ord.get("count", 10)) * float(ord.get("spacing", 1.0)) * 0.7)
			if _round_side == 0.0:
				_round_side = signf(global_position.x - cen.x)
				if _round_side == 0.0:
					_round_side = 1.0 if slot % 2 == 0 else -1.0
			var side := _round_side
			var dist: float = float(args[0]) if not args.is_empty() else 15.0
			var dx := (global_position.x - cen.x) * side
			if dx > half_w + 24.0:
				_round_wide = true
			elif dx < half_w * 0.5 and not _behind_line_of(e):
				_round_wide = false   # pushed back in somehow: out again
			var g: Vector3
			if _behind_line_of(e):
				g = Vector3(cen.x, 0, cen.z + back * dist)        # in behind: close on the middle of their back
			elif not _round_wide:
				g = Vector3(cen.x + side * (half_w + 30.0), 0, global_position.z)   # out wide first
			else:
				g = Vector3(cen.x + side * (half_w + 28.0), 0, cen.z + back * dist)  # past the end, round behind
			g += Vector3(float(slot % 5) * 2.5 - 5.0, 0, float(slot / 5) * 2.5)   # spread out, not a knot
			g.x = clampf(g.x, -Field.HALF_X + 2.0, Field.HALF_X - 2.0)
			g.z = clampf(g.z, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
			goal = field.free_point(g)
			action = "cover"
			kneeling = false
			want_run = false
			_sneak_t = 0.8
			face_point = goal
			return true
		"sneak":
			# Creep from cover to cover toward the enemy, walking, drifting toward his flank.
			# No cover ahead: a slow walk on the same slant. Never runs.
			if e == null:
				return false
			_sneak_t = 0.8
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
		"clear_smoke":
			# out of the cloud: the clearest ground within a few paces, not backward, upwind first
			if field.smoke_at(global_position.x, global_position.z) < 1.0:
				return false
			var best_p := Vector3.INF
			var best_v := field.smoke_at(global_position.x, global_position.z) - 0.5
			var toward_e := (e.global_position - global_position).normalized() if e != null else Vector3(0, 0, -signf(manager.home_z(team)))
			for k in 8:
				var a := TAU * float(k) / 8.0
				var dv := Vector3(cos(a), 0, sin(a))
				if dv.dot(toward_e) < -0.3:
					continue   # not backward
				var q := field.clamp_point(global_position + dv * 7.0)
				var v := field.smoke_at(q.x, q.z) - 0.3 * Vector2(dv.x, dv.z).dot(-field.wind.normalized())
				if v < best_v:
					best_v = v
					best_p = q
			if best_p == Vector3.INF:
				return false
			goal = field.free_point(best_p)
			action = "form"
			want_run = false
			if e != null:
				face_point = e.global_position
			return true
		"high_ground":
			# make for the highest rise within reach that still looks at the enemy - kneel there
			if e == null:
				return false
			var reach: float = float(args[0]) if not args.is_empty() else 25.0
			if _high_spot == Vector3.INF or _high_hold <= 0.0:
				_high_spot = field.high_spot(global_position, e.global_position, reach, slot)
				_high_hold = 8.0
			if _high_spot == Vector3.INF:
				return false
			goal = _high_spot
			action = "form"
			kneeling = global_position.distance_to(goal) < 1.0
			want_run = global_position.distance_to(goal) > 10.0 and not tired() and ed > 50.0
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
			manager.drill_phase[MatchManager.ck(team, company)] = String(args[0])
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
	if manager.orders[team][company].get("seek_cover", false):
		want = maxf(want, 0.5)   # the sergeant has seen the exchange; any wall will do
	elif enemy != null and global_position.distance_to(enemy.global_position) < fire_range_to(enemy) + 20.0:
		# in reach of their rifles: a wall or a rock within a few steps of his place is taken,
		# by anyone - standing in the open beside cover is no plan
		want = maxf(want, 0.25)
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
	# he has to be able to make the man out: not lost in the smoke, not unnoticed
	var d := from.distance_to(to)
	if d > 12.0 and field.visibility(from, to) < 0.12:
		return false
	if d > enemy.notice_range():
		return false
	# a friend in the line of fire: a disciplined man holds, a careless one does not
	var friend := manager.friend_in_line(self, enemy)
	if friend != null and (p("discipline") > 0.4 or friend.global_position.distance_to(global_position) < 5.0):
		return false   # (nobody, however careless, fires through the back of a mate at arm's length)
	# ... or one of ours beyond him, where a miss would fly on (men of ours behind their line):
	# a careful man holds his fire, a careless one shoots anyway
	if p("discipline") > 0.3 and manager.friend_beyond(self, enemy, 90.0) != null:
		return false
	return true


## A hand grenade: thrown (a second and a half to land and burn down the fuse), then a burst -
## the men right by it go down, the ones near are shaken, and the smoke hangs thick.
func stun(t: float) -> void:
	if t > 0.2:
		_stunned = maxf(_stunned, t)
		charging = false


func _throw_grenade(at: Vector3) -> void:
	grenades -= 1
	_grenade_cd = 6.0
	_halt = 1.2
	_fire_anim = 0.35
	face_point = at
	var err := Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5)) * (at.distance_to(global_position) / 20.0)
	var land := at + err
	land.y = field.height_at(land.x, land.z)
	var thrower := self
	if manager.fx != null:
		manager.fx.grenade_flight(global_position + Vector3(0, 1.7, 0), land + Vector3(0, 0.1, 0), 1.5)
	get_tree().create_timer(1.5, false).timeout.connect(func():
		if is_instance_valid(manager) and manager.running:
			manager.grenade_burst(land, thrower if is_instance_valid(thrower) else null))


func _fire(enemy: Soldier) -> void:
	# nobody fires into a melee where his own men are: a man not in it himself takes the
	# nearest enemy who is standing clear, or keeps his round
	if enemy.in_melee and not in_melee:
		var alt: Soldier = manager.nearest_clear_enemy(self)
		if alt == null or not _can_fire_at(alt):
			return
		enemy = alt
	enemy.under_fire = true   # being aimed at and fired on is being under fire
	_last_fire_t = manager.elapsed
	field.add_smoke(global_position + Vector3(0, EYE_HEIGHT, 0), enemy.global_position - global_position, 1.0)
	if manager.fx != null:
		manager.fx.shot(global_position)
	loaded = false
	ammo = maxi(ammo - 1, 0)
	reload_left = reload_time
	_halt = 2.0                              # he stands to bite the next cartridge
	_aim_need = rng.randf_range(1.2, 2.2)   # and the next shot will be aimed again
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
	if d < 5.0:
		sig *= 4.0                        # too close: no room to bring the musket up and lay it
	if order_volley():
		sig *= 1.1                        # on the word, not on his own time
	sig *= clampf(1.0 - (from.y - aim.y) * 0.04, 0.8, 1.15)   # looking down on them steadies the aim
	sig *= 1.0 + 1.2 * (1.0 - field.visibility(from, aim))     # aiming into the smoke at the shapes in it
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
	var o: Dictionary = manager.orders[team][company]
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
		p_hit *= 1.2
	if enemy._stunned > 0.0:
		p_hit *= 2.0   # down and dazed   # a man on his knee behind a wall has no room to parry
	if enemy.is_routed or enemy.action == "rout":
		p_hit *= 1.5
	if tired():
		p_hit *= 0.75
	# from behind: he cannot parry what he cannot see - and if he never knew I was there, it is
	# over before he turns
	var from_behind := enemy.is_behind_me(self)
	var unaware := from_behind and enemy.target != self and not enemy.in_melee
	if from_behind:
		p_hit *= 1.8
	if unaware:
		p_hit = maxf(p_hit, 0.92)
	var landed := rng.randf() < clampf(p_hit, 0.08, 0.97)
	if not landed and manager.fx != null and rng.randf() < 0.5:
		manager.fx.clash(global_position)   # parried: steel on steel
	if landed:
		thrust_hits += 1
		var dmg := BAYONET_DMG * melee_mult * rng.randf_range(0.8, 1.3)
		if from_behind:
			dmg *= 2.2 if unaware else 1.5
			# a blade in the back: the men about him feel it - the enemy is behind the line
			for o in manager.fighting(enemy.team):
				if o != enemy and o.global_position.distance_to(enemy.global_position) < 10.0:
					o.fear = minf(o.fear + 0.12, 0.6)
					o.under_fire = true
		dmg_done += dmg
		enemy.take_damage(dmg, "bayonet", self)
	thrust.emit(self, landed)


func take_damage(amount: float, source: String, attacker: Soldier) -> void:
	if not alive:
		return
	# a musket ball or a bayonet puts a man down: nobody fights on with one in him
	if source == "rifle" or source == "bayonet" or source == "grenade":
		amount = maxf(amount, hp)
	hp -= amount
	under_fire = true
	damaged.emit(self, amount, source, attacker)
	if manager.fx != null:
		var from_dir := (global_position - attacker.global_position) if attacker != null else Vector3.FORWARD
		manager.fx.hit(global_position + Vector3(0, 1.2, 0), from_dir, hp <= 0.0, source == "bayonet")
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
	if d < 15.0:
		under_fire = true
	if d < 6.0:
		fear = minf(fear + 0.12 * (1.0 - d / 6.0) + 0.04, 0.6)


func _die(source: String, attacker: Soldier) -> void:
	alive = false
	hp = 0.0
	if attacker != null and attacker.team != team:
		attacker.kills += 1
		if source == "bayonet":
			attacker.bayonet_kills += 1
		elif source == "grenade":
			attacker.grenade_kills += 1
	died.emit(self, source, attacker)
	_spawn_ragdoll(attacker)
	if manager.fx != null:
		# when he has come to rest, the pool under him
		get_tree().create_timer(1.3).timeout.connect(func():
			if manager.fx != null and is_instance_valid(self):
				manager.fx.pool(ragdoll.torso_position() if ragdoll != null and is_instance_valid(ragdoll) else global_position))


func _flee() -> void:
	gone = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	fled.emit(self)


# ---------------------------------------------------------------- movement

var _wp := Vector3.ZERO
var _wp_goal := Vector3(INF, 0, INF)
var _wp_t := 0.0


func _move(delta: float) -> void:
	# the way round: walk to a waypoint when the straight line to the goal meets a wall, a house
	# or a river (a bridge is the only way over); asked again every 0.4 s or when the goal moves
	var target := goal
	if action != "melee" and global_position.distance_to(goal) > 1.2:
		_wp_t -= delta
		if _wp_t <= 0.0 or _wp_goal.distance_to(goal) > 1.5 or global_position.distance_to(_wp) < 0.8:
			_wp_t = 0.4
			_wp_goal = goal
			_wp = field.next_waypoint(global_position, goal)
		target = _wp
	var to_goal := target - global_position
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
		# backing away while still facing the enemy - rifle up, feeling for the ground behind him -
		# goes at a quarter of the pace. Turning round to walk or run off is full pace, but then
		# he is not shooting.
		if not _faces_way(dir):
			var fp := face_point - global_position
			fp.y = 0.0
			if fp.length() > 0.5 and dir.dot(fp.normalized()) < -0.3:
				speed *= 0.25
	velocity = dir * speed + push * 1.2
	velocity.y = 0.0
	move_and_slide()
	global_position.y = field.height_at(global_position.x, global_position.z)
	# facing
	var face := face_point - global_position
	face.y = 0.0
	if _faces_way(dir):
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
	if soldier_type != null and soldier_type.label() == "Shinobi":
		# dressed to hide: a dark green, with only a touch of his side's colour to tell friend from foe
		_mat.albedo_color = Color(0.16, 0.3, 0.14).lerp(team_color, 0.22)
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
	_add_markings(torso, cap)
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

	# one mesh for each moving part, under one shared vertex-coloured material: ~22 draws a man
	# become 6 (the web renderer draws every mesh separately)
	var mk := company % MatchManager.MARKS.size()
	_core_mi = MeshBaker.bake_into(body_root, [arm_l, arm_r, leg_l, leg_r, rifle], "core/%d/%d" % [team, mk])
	MeshBaker.bake_into(arm_l, [], "arm/%d/%d" % [team, mk])
	MeshBaker.bake_into(arm_r, [], "arm/%d/%d" % [team, mk])
	MeshBaker.bake_into(leg_l, [], "leg/%d" % team)
	MeshBaker.bake_into(leg_r, [], "leg/%d" % team)
	MeshBaker.bake_into(rifle, [_smoke], "rifle")
	_smoke.visible = false

	label = Label3D.new()
	label.text = soldier_name if rounds == 0 else "%s *%d" % [soldier_name, rounds]   # *n: rounds survived
	label.font_size = 24
	label.pixel_size = 0.0045
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.35, 0)
	label.modulate = Color(1, 1, 1, 0.7)
	label.visible = false   # no name tag over each man; the company label above says who they are
	add_child(label)
	# hp bar
	var bar_bg := MeshInstance3D.new()
	_bar_bg = bar_bg
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


## Stripes, spots and the rest, by company, so the units can be told apart at a glance.
func _add_markings(torso: Node3D, cap: MeshInstance3D) -> void:
	var mk: Dictionary = MatchManager.mark_for(company)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = mk["color"]
	var cap_band := MeshInstance3D.new()          # every company wears its colour round the cap
	cap_band.mesh = _box(Vector3(0.34, 0.05, 0.36))
	cap_band.material_override = mm
	cap_band.position = Vector3(0, -0.05, 0)
	cap.add_child(cap_band)
	for side in [-1.0, 1.0]:                      # front (-z) and back (+z)
		var z: float = 0.155 * side
		match String(mk["pattern"]):
			"sash":
				_mark(torso, mm, Vector3(0.52, 0.1, 0.02), Vector3(0, 0.02, z))
			"spots":
				for p in [Vector2(-0.13, 0.17), Vector2(0.13, 0.17), Vector2(0, 0.0), Vector2(-0.13, -0.17), Vector2(0.13, -0.17)]:
					_mark(torso, mm, Vector3(0.09, 0.09, 0.02), Vector3(p.x, p.y, z), true)
			"stripes":
				for x in [-0.15, 0.0, 0.15]:
					_mark(torso, mm, Vector3(0.05, 0.62, 0.02), Vector3(x, 0, z))
			"bands":
				_mark(torso, mm, Vector3(0.52, 0.06, 0.02), Vector3(0, 0.12, z))
				_mark(torso, mm, Vector3(0.52, 0.06, 0.02), Vector3(0, -0.12, z))
			"cross":
				for a in [0.62, -0.62]:
					var b := _mark(torso, mm, Vector3(0.07, 0.8, 0.02), Vector3(0, 0, z))
					b.rotation.z = a
			"chevron":
				for a in [0.6, -0.6]:
					for dy in [0.1, -0.06]:
						var b := _mark(torso, mm, Vector3(0.3, 0.06, 0.02), Vector3(-0.1 * signf(a), dy, z))
						b.rotation.z = a
	if String(mk["pattern"]) == "bands" or String(mk["pattern"]) == "stripes":
		for arm in [arm_l, arm_r]:               # a band round each sleeve too
			_mark(arm, mm, Vector3(0.16, 0.08, 0.16), Vector3(0, 0.1, 0))


func _mark(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, round_spot := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if round_spot:
		var sp := SphereMesh.new()
		sp.radius = size.x * 0.5
		sp.height = size.x
		sp.radial_segments = 8
		sp.rings = 4
		m.mesh = sp
		m.scale = Vector3(1, 1, 0.3)
	else:
		m.mesh = _box(size)
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


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
	# the health bar only once he is hurt; the smoke only while there is smoke
	var hurt_now := hp < MAX_HP
	if _bar_bg.visible != hurt_now:
		_bar_bg.visible = hurt_now
		_bar_fg.visible = hurt_now
	if _smoke_t > 0.0:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke.visible = false
	_bar_quad.size.x = 0.88 * clampf(hp / MAX_HP, 0.0, 1.0)
	_bar_fg.position.x = -(0.88 - _bar_quad.size.x) * 0.5
	(_bar_fg.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.9, 0.3, 0.95).lerp(Color(0.95, 0.3, 0.2, 0.95), 1.0 - hp / MAX_HP)
	if is_routed:
		label.modulate = Color(1.0, 0.85, 0.3, 0.9)


## The smoke, and the ball's flight drawn as a faint arc from the muzzle to where it ended.
func _muzzle_flash_arc(ball: Callable, end_x: float) -> void:
	if manager.headless:
		return
	_smoke.visible = true
	_smoke_t = 1.6
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
	_smoke.visible = true
	_smoke_t = 1.6
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
	# the hit: the body flashes white for a moment
	if _white_mat == null:
		_white_mat = StandardMaterial3D.new()
		_white_mat.albedo_color = Color(1, 1, 1)
	if _core_mi != null:
		_core_mi.material_override = _white_mat
		_flash_tween = get_tree().create_tween()
		_flash_tween.tween_interval(0.18)
		_flash_tween.tween_callback(func():
			if is_instance_valid(_core_mi):
				_core_mi.material_override = null)


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


## How far he will fire at this man. The ball falls as it flies (Ballistics); from above, it has
## further to fall before it meets the ground, so its dangerous stretch reaches further out - about
## a sixth more range for every metre he stands above his mark, to half again on a big ridge.
## Firing uphill costs nothing here: the crest already hides the men behind it.
func fire_range_to(e: Soldier) -> float:
	var dh := global_position.y - e.global_position.y
	return MAX_RANGE * clampf(1.0 + 0.16 * dh, 1.0, 1.5)


## Has he stood still long enough to have aimed?
## Does he face the way he is going (turned about to walk or run off), rather than the enemy?
func _faces_way(dir: Vector3) -> bool:
	if dir.length() < 0.1:
		return false
	return action == "rout" or action == "kite" or (action == "fallback" and (want_run or _about_face))


func _aimed() -> bool:
	return _still_t >= _aim_need


## How far off an enemy can pick him out at all. A man standing in the open is seen at any
## rifle range; stealth, kneeling, cover and creeping shrink it; a man who has just fired, or
## who is running, gives himself away.
func notice_range() -> float:
	var s := soldier_type.skill("stealth")
	var r := 220.0 * (1.3 - s)
	if kneeling or action == "cover" or _sneak_t > 0.0:
		r *= 0.55
	if running:
		r *= 1.25
	if manager != null and manager.elapsed - _last_fire_t < 6.0:
		r = maxf(r, 250.0)
	if is_routed or in_melee:
		r = maxf(r, 250.0)
	return r
