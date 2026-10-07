extends Node3D
## Entry point. Builds the field, wires the HUD, runs battles; supports a headless batch:
##   godot --headless --path . -- --sim=20 [--red=Regulars --blue=Shock] [--redtype=Marksman]
##         [--size=20] [--seed=1] [--cap=400]
## In the browser the same keys go on the query string: ?red=Shock&blue=Militia&size=12

var manager: MatchManager
var field: Field
var cam: CameraRig
var hud: Hud
var headless := false
var batch_left := 0
var batch_results: Array[Dictionary] = []
var _restart_timer := -1.0
var _base_seed := -1
var _sun: DirectionalLight3D = null

# --- campaign: a front of eleven fields drawn at random; armies of twelve companies of ten,
# four fighting at a time, no recruits; won by carrying the enemy's last field or by the enemy
# having nobody left
const FRONT_LEN := 11
const ARMY_COMPANIES := 12
var COMPANY_MEN := 10   # men a company in the campaign: 10 (40 a side) or 20 (80 a side), set at its start
const FIGHTING := 4
var MERGE_BELOW := 3   # a company with fewer men than this joins another (3 at 10 a company, 5 at 20)
const ROUND_CAP := 30
# Epic: the campaign's front of eleven fields, but fifty companies a side (the twelve on the Armies
# screen, over and over), up to ten of them in each battle; what is left of a company fights again later
const EPIC_COMPANIES := 50
const EPIC_PICK := 10
const EPIC_ROUND_CAP := 40
var epic := false
var _designs := [[], []]   # the twelve companies of the Armies screen, kept while an epic war is on
const ARMY_NAMES := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
var front: Array[String] = []
var armies := [[], []]   # per side: {name, drill, type, type_obj, men: [records], fights}
var campaign_active := false
var campaign_round := 0            # 1-based; 0 = not started
var campaign_wins := [0, 0]
var campaign_kills := [0, 0]
var campaign_rounds: Array[Dictionary] = []   # one summary per round fought
var campaign_rosters: Array = [[], []]        # survivors carried into the next round
var _pending_campaign_result: Dictionary = {}
var campaign_field := 6   # 1..11 along the front; the winner pushes it toward the loser
var _last_fielded := ["", ""]    # the preset each side fought the last round with
var _ai_picks := ["", ""]
var _fielded_last := [4, 4]
var _fall_back := {}
var war_units := {}            # "t:army company" -> what that company has done in the whole war           # after a loss: {"side", "lo", "hi"} - the fields the loser may fall back to    # companies each side sent into the last battle
var _ai_type_picks := ["", ""]
## the type that suits each personality, best first
const TYPE_FOR := {
	"Regulars": ["Even", "Ironside", "Marksman"],
	"Skirmishers": ["Marksman", "Runner", "Even"],
	"Shock": ["Grenadier", "Ironside", "Runner"],
	"Militia": ["Runner", "Even", "Grenadier"],
	"Veterans": ["Ironside", "Marksman", "Even"],
}

## The computer's doctrines: a personality and a type that go together. Each is scored
## against what the enemy last fielded (its traits, not its name - a home-made company is
## read the same way), the ground, and how the doctrine has fared in this campaign; the
## best is fielded most often, the runners-up now and then, so there is never one answer.
var _doctrine_record := [{}, {}]   # per side: doctrine name -> [wins, losses] this campaign
var _last_doctrine := ["", ""]


func _ready() -> void:
	field = Field.new()
	if DisplayServer.get_name() != "headless":
		field.layout_name = Field.ALL_FIELDS[randi() % Field.ALL_FIELDS.size()]   # a different field to open on
	add_child(field)
	_build_lighting()
	manager = MatchManager.new()
	manager.world = self
	manager.field = field
	manager.match_ended.connect(_on_match_ended)
	if DisplayServer.get_name() != "headless":
		var bfx := BattleFx.new()
		bfx.field = field
		add_child(bfx)
		manager.fx = bfx
	add_child(manager)

	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("lint"):
		# --lint=drills/x.drill : parse it, say what is wrong, run nothing
		var text := FileAccess.get_file_as_string(String(args["lint"]))
		var d := Drill.parse(text)
		if d.errors.is_empty():
			print("OK %s: %d sergeant rules, %d man rules" % [d.name, d.sergeant_rules.size(), d.man_rules.size()])
		else:
			for e in d.errors:
				print("ERROR ", e)
		get_tree().quit(0 if d.errors.is_empty() else 1)
		return
	headless = (DisplayServer.get_name() == "headless" or args.has("sim")) and not args.has("ui")
	manager.headless = headless
	if args.has("field") and Field.LAYOUTS.has(args["field"]):
		_rebuild_field(args["field"])
	# the battalions: --companies=4 --csize=10, --redbat="Light battalion"; --red / --redtype /
	# --redtraits apply to every company of that side; --size is men per company
	var per: int = clampi(int(args.get("csize", args.get("size", "10"))), 1, MatchManager.MAX_SIZE)
	for t in 2:
		var key: String = ["red", "blue"][t]
		manager.set_battalion(t, String(args.get(key + "bat", manager.battalion_names[t])), per)
		General.trace = args.has("trace")
		if args.has(key + "play"):
			# --redplay="Hammer and anvil" (default: the general's choice)
			manager.plays[t] = String(args[key + "play"]).replace("_", " ")
			# a play given on the command line stays fixed unless --redadapt=1
			manager.adapt[t] = String(args.get(key + "adapt", "0")) == "1"
			if not General.PLAYS.has(manager.plays[t]):
				push_warning("no play called %s; plays: %s" % [manager.plays[t], ", ".join(General.PLAYS)])
		if args.has("companies"):
			var want := clampi(int(args["companies"]), 1, MatchManager.EDIT_COMPANIES)
			var cos: Array = manager.companies[t]
			while cos.size() > want:
				cos.pop_back()
			while cos.size() < want:
				var src: Dictionary = cos[cos.size() % maxi(cos.size(), 1)]
				cos.append(manager.new_company(t, cos.size(), src["persona_name"], src["type_name"], "Reserve", per))
		for c in (manager.companies[t] as Array).size():
			manager.select_company(t, c)
			if args.has(key) and not manager.set_drill(t, String(args[key])):
				push_warning("no drill called %s; drills: %s" % [args[key], ", ".join(Drill.names())])
			if args.has(key + "traits"):
				# --redtraits=aggression:0.1,cover:1 - overrides on top of the preset
				manager.team_personalities[t] = manager.team_personalities[t].jittered(manager.rng, 0.0)
				for kv in String(args[key + "traits"]).split(","):
					var pair := kv.split(":")
					if pair.size() == 2:
						manager.team_personalities[t].set_trait(pair[0], float(pair[1]))
				manager.team_preset_names[t] = manager.team_personalities[t].label()
			if args.has(key + "type"):
				manager.team_types[t] = SoldierType.preset(args[key + "type"])
				manager.team_type_names[t] = String(args[key + "type"])
			manager.store_company(t)
		if args.has(key + "mix"):
			# --redmix="Drill/Type/Slot,Drill/Type/Slot,..." - one company per entry, `per` men each
			var cos2 := []
			var parts := String(args[key + "mix"]).split(",", false)
			for c in mini(parts.size(), MatchManager.MAX_COMPANIES):
				var f := parts[c].split("/")
				var third: String = f[2].strip_edges() if f.size() > 2 else ""
				var co := manager.new_company(t, c, f[0].strip_edges(), f[1].strip_edges() if f.size() > 1 else "Even",
					third if MatchManager.SLOTS.has(third) else MatchManager.SLOTS[mini(c, 3)], per)
				if MatchManager.RANKS.has(third):
					co["rank"] = third   # Drill/Type/Front|Line|Back|Held back
				if co.get("drill") == null:
					push_warning("no drill called %s" % f[0])
				cos2.append(co)
			MatchManager.form_ranks(cos2)
			manager.companies[t] = cos2
			manager.battalion_names[t] = "Mix"
		manager.select_company(t, 0)
	if args.has("seed"):
		_base_seed = int(args["seed"])

	if headless:
		manager.time_limit = float(args.get("cap", "400"))
		set_sim_speed(20.0)
		batch_left = maxi(int(args.get("sim", "5")), 1)
		print("Drillbook Bots headless sim: %d battles, Red %s [%s] (%d men) vs Blue %s [%s] (%d men)" % [batch_left,
			manager.battalion_label(0), manager._types_label(0), manager.side_total(0),
			manager.battalion_label(1), manager._types_label(1), manager.side_total(1)])
		_start_next()
		return

	if manager.time_limit <= 0.0:
		manager.time_limit = 420.0   # nothing runs forever on a screen either
	_setup_ui_scale()
	cam = CameraRig.new()
	cam.name = "CameraRig"
	cam.field = field
	add_child(cam)
	hud = Hud.new()
	add_child(hud)
	hud.game = self
	_init_armies()
	hud.setup(manager)
	hud.cam = cam
	hud.build_cam_pad()
	hud.mark_field(field.layout_name)
	# a single battle: the companies chosen on Choose Companies, fresh men every time
	hud.new_match_requested.connect(func():
		batch_left = 0
		batch_results.clear()
		if campaign_active:
			return
		_prepare_single()
		_start_next())
	hud.batch_requested.connect(_run_batch)
	hud.campaign_requested.connect(func(): _start_campaign())
	hud.epic_requested.connect(_start_epic)
	hud.next_round_requested.connect(_next_round)
	hud.simulate_requested.connect(_simulate)
	hud.simulate_rest_requested.connect(_simulate_rest)
	hud.retreat_requested.connect(func():
		# the player's side (the first not run by the computer) leaves the field
		for t in 2:
			if hud.commanders[t] != "computer":
				manager.retreat(t)
				return)
	hud.campaign_abandoned.connect(_abandon_campaign)
	hud.army_pick.connect(toggle_army_pick)
	hud.fall_back_to.connect(fall_back_to)
	if args.has("debug"):
		hud.enable_debug()
	if not headless:
		set_sim_speed(1.0)
	if args.has("shadows") and _sun != null:
		_sun.shadow_enabled = String(args["shadows"]) != "0"
	hud.field_chosen.connect(func(n: String):
		if campaign_active:
			return
		_rebuild_field(n)
		if cam != null:
			cam.refit())
	hud.speed_changed.connect(set_sim_speed)
	hud.pause_toggled.connect(func(p: bool): get_tree().paused = p)
	hud.fit_requested.connect(func(): cam.refit())
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		# --ui on a headless server: the HUD exists but nobody watches; run it fast and capped
		manager.time_limit = float(args.get("cap", "400"))
		set_sim_speed(20.0)
	if args.has("campaign") or args.has("epic"):
		# --ui --campaign (or --epic): a whole war, headless, rounds chained automatically
		if args.has("men"):
			set_company_men(int(args["men"]))
		_start_campaign(args.has("epic"))
		hud.results_overlay.visible = false
		_close_pick()
		_next_round()
		return
	if args.has("uitest"):
		# --ui --uitest: walk the Armies and Choose Companies screens the way a player would
		_ui_walk()
		return
	if args.has("batch"):
		# --ui --batch=N: the Sim button's path, HUD and all, for a headless check of the panel
		_run_batch(maxi(int(args["batch"]), 1))
		return
	# nothing starts by itself: the first screen asks what we are running
	hud.show_start()


func _setup_ui_scale() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var dpi := DisplayServer.screen_get_dpi()
	root.content_scale_factor = clampf(float(dpi) / 96.0, 1.0, 2.0)


## Speed up game time without coarsening physics: raise the tick rate to match.
func set_sim_speed(s: float) -> void:
	Engine.time_scale = s
	if OS.has_feature("web"):
		# a phone cannot keep 60 steps a second for 80 men: 30, and never more than two
		# catch-up steps a frame - a slow frame slows the battle rather than snowballing
		Engine.physics_ticks_per_second = int(round(30.0 * s))
		Engine.max_physics_steps_per_frame = maxi(2, int(s * 2.0))
	else:
		Engine.physics_ticks_per_second = int(round(60.0 * s))
		Engine.max_physics_steps_per_frame = maxi(8, int(s * 4.0))


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = not headless and not OS.has_feature("web")   # ?shadows=1 turns them on in a browser
	_sun = sun
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# a sky down to the horizon, and the country running out to meet it: the field is a patch
	# of a wider land, the haze swallowing it in the distance as the real world does
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.82)
	sky_mat.sky_horizon_color = Color(0.74, 0.8, 0.86)
	sky_mat.ground_horizon_color = Color(0.74, 0.8, 0.86)
	sky_mat.ground_bottom_color = Color(0.3, 0.4, 0.25)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.75
	e.fog_enabled = true
	e.fog_light_color = Color(0.74, 0.8, 0.86)
	e.fog_density = 0.0009
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	if not headless:
		var land := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(9000, 9000)
		land.mesh = pm
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.31, 0.44, 0.23)
		lm.roughness = 1.0
		land.material_override = lm
		land.position = Vector3(0, -0.06, 0)
		land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(land)


func _parse_args(list: PackedStringArray) -> Dictionary:
	var d := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		var q: String = str(JavaScriptBridge.eval("window.location.search", true))
		if q.begins_with("?"):
			for part in q.substr(1).split("&"):
				var kv2: PackedStringArray = String(part).split("=", true, 1)
				if kv2[0] != "":
					d[kv2[0]] = kv2[1].uri_decode() if kv2.size() > 1 else "1"
	return d


func _start_next() -> void:
	_restart_timer = -1.0
	if hud != null:
		hud.on_match_started()
	if cam != null:
		cam.refit()   # every battle and every round opens on the whole field, as Fit view
	var s := -1
	if _base_seed >= 0:
		s = _base_seed + manager.match_index
	manager.start_match(s)


func _run_batch(n: int) -> void:
	if campaign_active:
		_abandon_campaign()
	batch_left = n
	batch_results.clear()
	_prepare_single()
	set_sim_speed(8.0)
	if hud != null:
		hud._set_speed(4.0)
		hud.batch_progress(1, n)
	_start_next()


func _process(delta: float) -> void:
	if _restart_timer > 0.0:
		_restart_timer -= delta
		if _restart_timer <= 0.0:
			_start_next()


## Fight the next battle unseen, as fast as the machine allows, and go straight to the result.
var _simulating := false
var _speed_before := 1.0


func _simulate() -> void:
	batch_left = 0
	_simulating = true
	_speed_before = Engine.time_scale
	get_viewport().disable_3d = true   # nothing drawn: every frame goes to the fight
	if manager.fx != null:
		manager.fx.muted_sim = true
	hud.show_sim_cover(true)
	set_sim_speed(24.0)
	Engine.max_physics_steps_per_frame = 96
	if campaign_active:
		_next_round()
	else:
		_prepare_single()
		_start_next()


## Fight the rest of the battle on the field unseen, at full speed, straight to the result.
func _simulate_rest() -> void:
	if not manager.running or _simulating:
		return
	_simulating = true
	_speed_before = Engine.time_scale
	get_viewport().disable_3d = true
	if manager.fx != null:
		manager.fx.muted_sim = true
	hud.show_sim_cover(true)
	set_sim_speed(24.0)
	Engine.max_physics_steps_per_frame = 96


func _end_simulation() -> void:
	if not _simulating:
		return
	_simulating = false
	get_viewport().disable_3d = false
	if manager.fx != null:
		manager.fx.muted_sim = false
	hud.show_sim_cover(false)
	set_sim_speed(_speed_before)


func _on_match_ended(result: Dictionary) -> void:
	_end_simulation()
	if batch_left > 0:
		batch_left -= 1
		batch_results.append(result)
		if headless:
			print("  battle %d: %s by %s in %ds (standing %d-%d) plays: %s / %s" % [result["match"], result["winner_name"], result["reason"], int(result["duration"]), result["alive"][0], result["alive"][1], result["plays"][0], result["plays"][1]])
		if batch_left > 0:
			if hud != null:
				hud.batch_progress(batch_results.size() + 1, batch_results.size() + batch_left)
			_restart_timer = 0.05
			return
		var summary := _summarize(batch_results)
		if headless:
			print(summary["text"])
			print("SUMMARY " + JSON.stringify(summary["data"]))
			get_tree().quit()
			return
		hud.batch_progress(0, 0)
		hud.show_batch(summary)
		set_sim_speed(1.0)
		hud._set_speed(1.0)
		if DisplayServer.get_name() == "headless":
			print("batch panel: %s, %d rows" % [hud.results_title.text, hud.results_box.get_child_count()])
			get_tree().quit()
		return
	if hud != null and campaign_active:
		hud.set_status("Round %d over - %s" % [campaign_round, result["winner_name"]])
		_on_round_ended(result)
		return
	if hud != null:
		hud.set_status("Battle over - %s" % result["winner_name"])
		get_tree().create_timer(2.0).timeout.connect(func(): hud.show_result(result))
	elif headless:
		print(JSON.stringify(result))


## Per company over a batch: men fielded, stood / ran / fell, shots, hits, kills.
func _co_stats(results: Array[Dictionary]) -> Array:
	var out := [{}, {}]
	for r in results:
		for m in r["soldiers"]:
			var t: int = m["team"]
			var c: int = int(m.get("company", 0))
			if not out[t].has(c):
				out[t][c] = {"men": 0, "stood": 0, "ran": 0, "fell": 0, "shots": 0, "hits": 0, "kills": 0, "bayonet": 0}
			var st: Dictionary = out[t][c]
			st["men"] += 1
			if not m["alive"]:
				st["fell"] += 1
			elif m["routed"] or m["gone"]:
				st["ran"] += 1
			else:
				st["stood"] += 1
			st["shots"] += int(m["shots"])
			st["hits"] += int(m["hits"])
			st["kills"] += int(m["kills"])
			st["bayonet"] += int(m["bayonet_kills"])
	return out


func _summarize(results: Array[Dictionary]) -> Dictionary:
	var wins := [0, 0]
	var draws := 0
	var dur := 0.0
	var keys := ["shots", "hits", "volleys", "charges", "fallbacks", "routed", "rallied", "own_kills", "grenade_kills", "friendly", "thrusts", "thrust_hits"]
	var tot := {}
	for k in keys:
		tot[k] = [0, 0]
	var kills := [[0, 0, 0], [0, 0, 0]]
	for r in results:
		if r["winner"] >= 0:
			wins[r["winner"]] += 1
		else:
			draws += 1
		dur += r["duration"]
		var s: Dictionary = r["stats"]
		for t in 2:
			for k in keys:
				tot[k][t] += s[k][t]
			kills[t][0] += s["kills"][t][0]
			kills[t][1] += s["kills"][t][1]
			kills[t][2] += s["kills"][t][2] if (s["kills"][t] as Array).size() > 2 else 0
	# which rules decided, summed over the batch: per side, drill name -> {line -> ticks}
	var tally := [{}, {}]
	for r in results:
		for t in 2:
			var rt: Dictionary = r.get("tally", [{}, {}])[t]
			for dn in rt:
				var per: Dictionary = tally[t].get(dn, {})
				for k in rt[dn]:
					per[k] = int(per.get(k, 0)) + int(rt[dn][k])
				tally[t][dn] = per
	var n := maxi(results.size(), 1)
	var txt := "Batch of %d: Red (%s/%s) %d wins, Blue (%s/%s) %d wins, %d draws, avg %ds.  " % [
		results.size(), manager.battalion_label(0), manager._types_label(0), wins[0],
		manager.battalion_label(1), manager._types_label(1), wins[1], draws, int(dur / n)]
	for t in 2:
		var acc := float(tot["hits"][t]) / maxf(float(tot["shots"][t]), 1.0) * 100.0
		var kt: float = float(kills[t][0] + kills[t][1] + kills[t][2])
		var dt: float = float(kills[1 - t][0] + kills[1 - t][1] + kills[1 - t][2])
		txt += "%s per battle: %d shots at %d%%, %d volleys, %d charges, %d fall-backs, %d ran; killed %d by ball, %d by bayonet, %d by grenade; %d friendly hits; kills %.1f, deaths %.1f, K/D %.2f.  " % [
			MatchManager.TEAM_NAMES[t], tot["shots"][t] / n, int(acc), tot["volleys"][t] / n, tot["charges"][t] / n,
			tot["fallbacks"][t] / n, tot["routed"][t] / n, kills[t][0] / n, kills[t][1] / n, kills[t][2] / n, tot["friendly"][t] / n,
			kt / n, dt / n, kt / maxf(dt, 1.0)]
	var battles := []
	for r in results:
		battles.append({"match": r["match"], "winner": r["winner"], "winner_name": r["winner_name"], "reason": r["reason"],
			"duration": r["duration"], "alive": r["alive"], "fighting": r["fighting"], "plays": r.get("plays", [])})
	return {"text": txt, "data": {"matches": results.size(), "wins": wins, "draws": draws, "avg_duration": dur / n,
		"totals": tot, "kills": kills, "presets": [manager.battalion_label(0), manager.battalion_label(1)], "types": [manager._types_label(0), manager._types_label(1)],
		"sizes": manager.side_n.duplicate(), "battles": battles, "companies": manager._company_summary(), "co_stats": _co_stats(results), "tally": tally}}


# ---------------------------------------------------------------- campaign

func _rebuild_field(layout: String) -> void:
	if field != null:
		manager.clear()
		field.queue_free()
	field = Field.new()
	field.layout_name = layout
	add_child(field)
	manager.field = field
	if cam != null:
		cam.field = field
	if manager.fx != null:
		manager.fx.field = field
		manager.fx.clear()
	if hud != null:
		hud.mark_field(layout)


func _start_epic() -> void:
	_start_campaign(true)


func _start_campaign(epic_war := false) -> void:
	if epic and not epic_war:
		_end_epic_armies()
	epic = epic_war
	batch_left = 0
	batch_results.clear()
	campaign_active = true
	campaign_round = 0
	campaign_wins = [0, 0]
	campaign_kills = [0, 0]
	war_units = {}
	campaign_rounds.clear()
	campaign_rosters = [[], []]
	manager.rosters = [[], []]
	# the front: eleven of the thirteen fields, in a random order, the fight opening in the middle
	var pool: Array = Field.ALL_FIELDS.duplicate()
	pool.shuffle()
	front = []
	for i in FRONT_LEN:
		front.append(String(pool[i]))
	campaign_field = (FRONT_LEN + 1) / 2
	_last_fielded = ["", ""]
	_fielded_last = [4, 4]
	_fall_back = {}
	_ai_picks = ["", ""]
	_ai_type_picks = ["", ""]
	_doctrine_record = [{}, {}]
	_last_doctrine = ["", ""]
	# the armies as set up on the Armies screen, every man fresh; whoever was chosen last goes
	# in first unless changed (the first four if nobody was)
	_refresh_men_all()
	for t in 2:
		if hud.commanders[t] == "computer" and Quartermaster.ready():
			_ai_raise(t)
	if epic:
		_build_epic_armies()
	for t in 2:
		if _fielded(t) == 0 or epic:
			_default_picks(t, EPIC_PICK if epic else FIGHTING)
	hud.front = front
	hud.campaign_started(epic)
	if epic:
		_fielded_last = [EPIC_PICK, EPIC_PICK]
	for t in 2:
		# a computer commander chooses its own companies (blind) and opens with a pick of its own
		if hud.commanders[t] == "computer":
			if Quartermaster.ready():
				_ai_plan(t)
				continue
			if epic:
				_default_picks(t, _computer_count(t))
				_prepare_battle(t)   # in an epic its companies keep the drills they were given
				continue
			_default_picks(t, FIGHTING)
			_prepare_battle(t)
			_ai_pick(t, true)
			_sync_from_manager(t)
	_rebuild_field(front[campaign_field - 1])
	hud.set_round(1, front[campaign_field - 1], [_army_men(0), _army_men(1)], campaign_field)
	if cam != null:
		cam.refit()
	hud.show_pick()


## Fifty companies a side from the twelve on the Armies screen, repeated: A1..L1, A2..L2, ...
func _build_epic_armies() -> void:
	for t in 2:
		_designs[t] = (armies[t] as Array).duplicate(true)
		var src: Array = _designs[t]
		var out := []
		for i in EPIC_COMPANIES:
			var d: Dictionary = src[i % src.size()]
			var nm := "%s%d" % [d["name"], i / src.size() + 1]
			var men := []
			for k in COMPANY_MEN:
				men.append({"name": "%s%s %d" % [MatchManager.TEAM_NAMES[t][0], nm, k + 1], "seed": randi(), "kills": 0, "rounds": 0})
			out.append({"name": nm, "drill": d["drill"], "type": d["type"], "type_obj": (d["type_obj"] as SoldierType).copy(),
				"men": men, "fights": false, "rank": String(d.get("rank", "Auto")), "slot": d.get("slot", "")})
		armies[t] = out


## After an epic war: the Armies screen's twelve companies again.
func _end_epic_armies() -> void:
	for t in 2:
		if not (_designs[t] as Array).is_empty():
			armies[t] = _designs[t]
			_designs[t] = []
	epic = false


func pick_limit() -> int:
	return EPIC_PICK if epic and campaign_active else 999


func _army_men(t: int) -> int:
	var n := 0
	for a in armies[t]:
		n += (a["men"] as Array).size()
	return n


## A side's army as the HUD shows it: name, drill, type, men, fights next.
func army_view(t: int) -> Array:
	var out := []
	for a in armies[t]:
		out.append({"name": a["name"], "drill": a["drill"], "type": a["type"], "men": (a["men"] as Array).size(), "fights": a["fights"], "slot": a.get("slot", "")})
	return out


## Edits made on the Armies screen (drill, type) go back to the army companies they belong to.
func _sync_from_manager(t: int) -> void:
	manager.store_company(t)
	for co in manager.companies[t]:
		if not (co as Dictionary).has("army_i"):
			continue
		var a: Dictionary = armies[t][int(co["army_i"])]
		a["drill"] = String(co["persona_name"])
		a["type"] = String(co["type_name"])
		a["type_obj"] = (co["type"] as SoldierType).copy()
		if co.get("slot_set", false):
			a["slot"] = String(co["slot"])


## The n (four unless said) with the most men left are put forward.
func _default_picks(t: int, n: int = FIGHTING) -> void:
	var ar: Array = armies[t]
	var idx := []
	for i in ar.size():
		if (ar[i]["men"] as Array).size() > 0:
			idx.append(i)
	idx.sort_custom(func(a, b):
		var na: int = (ar[a]["men"] as Array).size()
		var nb: int = (ar[b]["men"] as Array).size()
		return na > nb or (na == nb and a < b))   # level on men: the first in the list
	for i in ar.size():
		ar[i]["fights"] = idx.find(i) >= 0 and idx.find(i) < n


func _fielded(t: int) -> int:
	var n := 0
	for a in armies[t]:
		if a["fights"] and (a["men"] as Array).size() > 0:
			n += 1
	return n


## How many companies a computer army sends in - its own guess, made without seeing yours:
## about what the enemy brought last time, give or take one; nearly everything when it is
## fighting on its own last fields; a little more when it is the weaker army.
func _computer_count(t: int) -> int:
	var avail := 0
	for a in armies[t]:
		if (a["men"] as Array).size() > 0:
			avail += 1
	if avail <= 1:
		return avail
	var n: int = int(_fielded_last[1 - t]) + randi_range(-1, 1)
	if epic:
		# about what the enemy brought last time; more if it is falling behind in men
		if _army_men(t) < _army_men(1 - t) * 0.8:
			n += 2
		return clampi(n, mini(4, avail), mini(avail, EPIC_PICK))
	var behind := campaign_field <= 2 if t == 0 else campaign_field >= FRONT_LEN - 1
	if behind:
		n = maxi(n, avail - randi_range(0, 1))   # a last stand: nearly everyone
	if _army_men(t) < _army_men(1 - t) * 0.7:
		n += 1
	return clampi(n, mini(2, avail), avail)


## The HUD's army picker: put a company forward or stand it down (any number, at least one).
func toggle_army_pick(t: int, i: int) -> void:
	var ar: Array = armies[t]
	if ar[i]["fights"]:
		if _fielded(t) > 1:   # the last company in cannot stand down
			ar[i]["fights"] = false
	elif not (ar[i]["men"] as Array).is_empty() and _fielded(t) < pick_limit():
		ar[i]["fights"] = true
	if hud != null:
		hud.refresh_pick()


## Choose Companies' quick picks: everyone who can stand, or the freshest four.
func pick_all(t: int) -> void:
	if epic and campaign_active:
		_default_picks(t, EPIC_PICK)
		if hud != null:
			hud.refresh_pick()
		return
	for a in armies[t]:
		a["fights"] = (a["men"] as Array).size() > 0
	if hud != null:
		hud.refresh_pick()


func pick_freshest(t: int) -> void:
	_default_picks(t, EPIC_PICK if epic and campaign_active else FIGHTING)
	if hud != null:
		hud.refresh_pick()


## The battle battalion from the army: the companies put forward (the freshest four if none
## are), each with its own men as the campaign roster. Past four, they form a second line
## behind the first, slot by slot.
func _prepare_battle(t: int) -> void:
	var ar: Array = armies[t]
	var picked := []
	for i in ar.size():
		if ar[i]["fights"] and (ar[i]["men"] as Array).size() > 0:
			picked.append(i)
	if picked.is_empty():
		var rest := []
		for i in ar.size():
			if picked.find(i) < 0 and (ar[i]["men"] as Array).size() > 0:
				rest.append(i)
		rest.sort_custom(func(a, b): return (ar[a]["men"] as Array).size() > (ar[b]["men"] as Array).size())
		for i in rest:
			if picked.size() < FIGHTING:
				picked.append(i)
	for i in ar.size():
		ar[i]["fights"] = picked.find(i) >= 0
	if picked.is_empty():
		return
	var slots := ["Left", "Centre-left", "Centre-right", "Right"]
	var cos := []
	var roster := []
	for c in picked.size():
		var a: Dictionary = ar[picked[c]]
		var co := manager.new_company(t, c, a["drill"], a["type"], slots[c % slots.size()], (a["men"] as Array).size())
		co["full"] = COMPANY_MEN   # its strength bar measures what is left of the full company

		co["name"] = a["name"]
		co["type"] = (a["type_obj"] as SoldierType).copy()
		co["type_name"] = a["type"]
		co["army_i"] = picked[c]
		co["rank"] = String(a.get("rank", "Auto"))
		cos.append(co)
		for m in a["men"]:
			var rec: Dictionary = (m as Dictionary).duplicate()
			rec["co"] = c
			roster.append(rec)
	MatchManager.form_ranks(cos)
	manager.companies[t] = cos
	manager.battalion_names[t] = "Army"
	manager.rosters[t] = roster
	manager.select_company(t, 0)


## Field the next battle: the companies put forward, with the men they have left.
func _next_round() -> void:
	if not campaign_active:
		return
	campaign_round += 1
	manager.round_no = campaign_round
	var layout: String = front[campaign_field - 1]
	if field == null or field.layout_name != layout:
		_rebuild_field(layout)
	for t in 2:
		_prepare_battle(t)
		_fielded_last[t] = _fielded(t)
	hud.set_round(campaign_round, layout, [_army_men(0), _army_men(1)], campaign_field)
	_start_next()


## A company cut to fewer than three is broken up: its men join the
## standing company with the most room. Returns what happened, for the round panel.
func _merge_army(t: int) -> Array:
	var ar: Array = armies[t]
	var notes := []
	for i in ar.size():
		var n: int = (ar[i]["men"] as Array).size()
		if n == 0 or n >= MERGE_BELOW:
			continue
		var best := -1
		var best_room := 0
		for o in ar.size():
			var on: int = (ar[o]["men"] as Array).size()
			if o == i or on < MERGE_BELOW:
				continue
			var room: int = COMPANY_MEN - on
			if room >= n and room > best_room:
				best = o
				best_room = room
		if best < 0:
			continue   # nobody has room: they stay a small company of their own
		(ar[best]["men"] as Array).append_array(ar[i]["men"])
		ar[i]["men"] = []
		ar[i]["fights"] = false
		notes.append("%s %s's %d joined %s" % [MatchManager.TEAM_NAMES[t], ar[i]["name"], n, ar[best]["name"]])
	return notes


## What the computer reads the enemy (side 1 - t) to be: {drill: share} - half his whole army,
## half what he sent into the last battle (once there has been one).
func _enemy_profile(t: int) -> Dictionary:
	var e := 1 - t
	var army := {}
	var tot := 0.0
	for a in armies[e]:
		var n := float(maxi((a["men"] as Array).size(), 1))
		army[a["drill"]] = float(army.get(a["drill"], 0.0)) + n
		tot += n
	for k in army:
		army[k] = army[k] / maxf(tot, 1.0)
	if campaign_round == 0 or (manager.companies[e] as Array).is_empty():
		return army
	var last := {}
	var lt := 0.0
	for co in manager.companies[e]:
		var n := float(int(co.get("size", 1)))
		last[co["persona_name"]] = float(last.get(co["persona_name"], 0.0)) + n
		lt += n
	var out := {}
	for k in army:
		out[k] = 0.5 * float(army[k])
	for k in last:
		out[k] = float(out.get(k, 0.0)) + 0.5 * float(last[k]) / maxf(lt, 1.0)
	return out


var _ai_reason := ["", ""]


## A computer side raises its army for the war: the candidate army that does best against what
## the enemy has, over the fields the war will be fought on - a mix unless one drill is clearly
## better. Its twelve companies take that army's drills and types.
func _ai_raise(t: int) -> void:
	var fields := []
	for f in front:
		if not fields.has(f):
			fields.append(f)
	var r := Quartermaster.raise_army(_enemy_profile(t), fields)
	if String(r[0]) == "":
		return
	var cos := Quartermaster.companies_for(String(r[0]), (armies[t] as Array).size())
	for i in (armies[t] as Array).size():
		var a: Dictionary = armies[t][i]
		a["drill"] = cos[i][0]
		a["type"] = cos[i][1]
		a["type_obj"] = SoldierType.preset(cos[i][1])
		a["rank"] = "Auto"
	_ai_reason[t] = "raised %s: %s" % [r[0], r[1]]


## A computer side's companies for the next battle: how many (its blind guess), which army shape
## suits this field against what it expects, and which of its companies make that shape - in a
## campaign it may also retrain them; in an epic it uses the companies it has.
func _ai_plan(t: int) -> void:
	var n := _computer_count(t)
	var fld: String = front[campaign_field - 1] if not front.is_empty() else field.layout_name
	var enemy := _enemy_profile(t)
	var ar: Array = armies[t]
	var allowed := []
	if epic:
		# only shapes it can still make from the companies it has left
		var have := {}
		for a in ar:
			if (a["men"] as Array).size() > 0:
				have["%s/%s" % [a["drill"], a["type"]]] = true
		for tn in Quartermaster.templates():
			var ok := true
			for k in Quartermaster.templates()[tn]:
				if not have.has(k):
					ok = false
			if ok:
				allowed.append(tn)
		if allowed.is_empty():
			_default_picks(t, n)
			_prepare_battle(t)
			return
	var choice := Quartermaster.pick(enemy, fld, randf(), allowed)
	if choice.is_empty():
		_default_picks(t, n)
		_prepare_battle(t)
		return
	var want := Quartermaster.companies_for(String(choice[1]), n)
	for a in ar:
		a["fights"] = false
	if epic:
		# the freshest company of each drill wanted, then the freshest of any to make up the number
		var order := range(ar.size())
		order.sort_custom(func(i, j): return (ar[i]["men"] as Array).size() > (ar[j]["men"] as Array).size())
		var taken := 0
		for w in want:
			for i in order:
				var a: Dictionary = ar[i]
				if not a["fights"] and (a["men"] as Array).size() > 0 and a["drill"] == w[0] and a["type"] == w[1]:
					a["fights"] = true
					taken += 1
					break
		for i in order:
			if taken >= n:
				break
			if not ar[i]["fights"] and (ar[i]["men"] as Array).size() > 0:
				ar[i]["fights"] = true
				taken += 1
	else:
		_default_picks(t, n)
		var k := 0
		for a in ar:
			if a["fights"] and k < want.size():
				a["drill"] = want[k][0]
				a["type"] = want[k][1]
				a["type_obj"] = SoldierType.preset(want[k][1])
				k += 1
	_prepare_battle(t)
	_ai_picks[t] = manager.battalion_label(t)
	_ai_type_picks[t] = manager._types_label(t)
	_last_doctrine[t] = String(choice[1])
	_ai_reason[t] = "%s on %s (%d%% expected)" % [choice[1], fld, int(float(choice[0]) * 100)]
	if DisplayServer.get_name() == "headless":
		print("  computer (%s): %s" % [MatchManager.TEAM_NAMES[t], _ai_reason[t]])


## The computer's picks for a whole battalion: a doctrine per company, answering the enemy
## battalion's average temper, never the same doctrine for every company.
func _ai_pick(t: int, opening: bool) -> String:
	var e := Personality.preset("Balanced")
	var ecos: Array = manager.companies[1 - t]
	for tr in Personality.TRAITS:
		var m := 0.0
		for co in ecos:
			m += (co["persona"] as Personality).get_trait(tr)
		e.set_trait(tr, m / maxf(ecos.size(), 1))
	var used := {}
	var names := []
	for c in (manager.companies[t] as Array).size():
		manager.select_company(t, c)
		var d := _ai_pick_company(t, opening, e, used)
		used[d] = int(used.get(d, 0)) + 1
		names.append(d)
		manager.store_company(t)
	manager.select_company(t, 0)
	_ai_picks[t] = manager.battalion_label(t)
	_ai_type_picks[t] = manager._types_label(t)
	_last_doctrine[t] = ", ".join(names)
	return _ai_picks[t]


func _ai_pick_company(t: int, opening: bool, e: Personality, used: Dictionary) -> String:
	var e_aggr := e.get_trait("aggression")
	var e_cover := e.get_trait("cover")
	var e_nerve := e.get_trait("nerve")
	var e_disc := e.get_trait("discipline")
	var e_coh := e.get_trait("cohesion")
	var layout: String = field.layout_name if field != null else "Walled Farm"
	var pieces: int = Field.scaled_pieces(layout).size() / 2   # battalion scale: about twice the old counts
	var open_ground: bool = pieces <= 6
	var thick_ground: bool = pieces >= 10
	var scored := []
	for d in _doctrines():
		var sc := 0.0
		if opening:
			sc = randf() * 2.0   # nothing known yet: any doctrine, with a slight lean to the ground
		else:
			var dp: String = d["p"]
			var storm: bool = dp == "Shock"
			var line: bool = dp == "Regulars" or dp == "Veterans"
			var skirm: bool = dp == "Skirmishers"
			# men behind walls who will not come out: go and get them, or out-shoot them from walls of your own
			if e_cover > 0.6 and e_aggr < 0.45:
				sc += 2.5 if storm else (1.0 if skirm else -2.0)
			# men coming on with the bayonet: stand, volley, and let them come
			if e_aggr > 0.7:
				sc += 2.0 if line else (-1.5 if skirm else -0.5)
			# shaky men break under volleys, and under a charge
			if e_nerve < 0.4:
				sc += 1.5 if line else (1.0 if storm else 0.0)
			# a loose, undisciplined enemy is meat for a charge
			if e_disc < 0.4 or e_coh < 0.3:
				sc += 1.0 if storm else 0.0
			# a steady, patient line is best worried from cover, not charged
			if e_disc > 0.7 and e_aggr < 0.6 and e_cover < 0.5:
				sc += 1.5 if skirm else (-1.0 if storm else 0.0)
		# the ground
		if open_ground:
			sc += 1.0 if d["p"] != "Skirmishers" else -1.5
		if thick_ground:
			sc += 1.0 if d["p"] == "Skirmishers" else (-1.0 if d["p"] == "Shock" else 0.0)
		# what this campaign has taught
		var rec: Array = _doctrine_record[t].get(d["name"], [0, 0])
		sc += 1.5 * rec[0] - 2.0 * rec[1]
		# a battalion is a mix: each company already on a doctrine makes it less likely again
		sc -= 1.2 * int(used.get(d["name"], 0))
		sc += randf() * 0.6
		scored.append([sc, d])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	# the best most of the time; the second and third often enough to be a real choice
	var r := randf()
	var d: Dictionary = scored[0][1] if r < 0.6 else (scored[1][1] if r < 0.88 else scored[2][1])
	var pick: String = d["p"]
	var tpick: String = d["t"]
	pick = d["name"]
	manager.set_drill(t, pick)
	manager.team_types[t] = SoldierType.preset(tpick)
	manager.team_type_names[t] = tpick
	return d["name"]


## The computer's choices: every drill in the book, read by its dials (which preset it is
## nearest) and the type it asks for.
func _doctrines() -> Array:
	var out := []
	for n in Drill.names():
		var d := Drill.named(n)
		out.append({"name": d.name, "p": d.personality().label(), "t": d.type_name})
	return out


func _abandon_campaign() -> void:
	campaign_active = false
	campaign_round = 0
	manager.rosters = [[], []]
	hud.campaign_ended()
	if epic:
		_end_epic_armies()
	_refresh_men_all()
	_rebuild_field(Field.ALL_FIELDS[randi() % Field.ALL_FIELDS.size()])
	hud.open_setup("Campaign abandoned. The armies are whole again - what next?")


## After a battle: the dead are gone for good, the living go back to their companies, battered
## companies merge, the front moves one field toward the loser. The war is won by winning on
## the enemy's last field, or when the enemy has nobody left.
func _on_round_ended(result: Dictionary) -> void:
	_add_war_units(result)
	var w: int = result["winner"]
	if w >= 0:
		campaign_wins[w] += 1
	var st: Dictionary = result["stats"]
	var counts := [{"stood": 0, "ran": 0, "fell": 0}, {"stood": 0, "ran": 0, "fell": 0}]
	var men_before := [_army_men(0), _army_men(1)]
	var back := [{}, {}]   # army company -> the men who came back
	for t in 2:
		for co in manager.companies[t]:
			back[t][int(co["army_i"])] = []
	for m in result["soldiers"]:
		var t: int = m["team"]
		if not m["alive"]:
			counts[t]["fell"] += 1
			continue
		if m["routed"] or m["gone"]:
			counts[t]["ran"] += 1
		else:
			counts[t]["stood"] += 1
		var c: int = int(m.get("company", 0))
		if c >= (manager.companies[t] as Array).size():
			continue
		var ai: int = int(manager.companies[t][c]["army_i"])
		(back[t][ai] as Array).append({"name": m["name"], "seed": m["seed"], "kills": m["career_kills"], "rounds": int(m["rounds"]) + 1})
	var merges := []
	for t in 2:
		for ai in back[t]:
			armies[t][ai]["men"] = back[t][ai]
		merges.append_array(_merge_army(t))
		campaign_kills[t] += st["kills"][t][0] + st["kills"][t][1] + st["kills"][t][2]
	var men_after := [_army_men(0), _army_men(1)]
	var layout: String = front[campaign_field - 1]
	var fought_on := campaign_field
	# the war: carried to the enemy's last field, or one side has nobody left
	var over := false
	var cw := -1
	var why := ""
	if w == 0 and campaign_field == FRONT_LEN:
		over = true
		cw = 0
		why = "Red carries the last field - Blue's country is taken"
	elif w == 1 and campaign_field == 1:
		over = true
		cw = 1
		why = "Blue carries the last field - Red's country is taken"
	elif men_after[0] == 0 or men_after[1] == 0:
		over = true
		if men_after[0] == 0 and men_after[1] == 0:
			cw = w if w >= 0 else (0 if campaign_kills[0] >= campaign_kills[1] else 1)
			why = "both armies are spent"
		else:
			cw = 0 if men_after[1] == 0 else 1
			why = "%s has nobody left to fight" % MatchManager.TEAM_NAMES[1 - cw]
	elif campaign_round >= (EPIC_ROUND_CAP if epic else ROUND_CAP):
		over = true
		var mid := (FRONT_LEN + 1) / 2
		cw = 0 if campaign_field > mid else (1 if campaign_field < mid else (0 if men_after[0] >= men_after[1] else 1))
		why = "after %d battles the war is called for whoever holds more of the front" % (EPIC_ROUND_CAP if epic else ROUND_CAP)
	_fall_back = {}
	if not over:
		if w == 0:
			campaign_field += 1
		elif w == 1:
			campaign_field -= 1
		# a beaten human side may give up more ground to choose where it stands next:
		# any field from the one it was pushed to back to its own last field
		if w >= 0 and hud.commanders[1 - w] != "computer":
			var lo := 1 if w == 1 else campaign_field
			var hi := campaign_field if w == 1 else FRONT_LEN
			if hi > lo:
				_fall_back = {"side": 1 - w, "lo": lo, "hi": hi}
	campaign_rounds.append({"round": campaign_round, "field": "%d. %s" % [fought_on, layout], "winner": w, "winner_name": result["winner_name"],
		"reason": result["reason"], "duration": result["duration"], "counts": counts,
		"fielded": [result["presets"][0], result["presets"][1]]})
	_last_fielded = [result["presets"][0], result["presets"][1]]
	for t in 2:
		for dn in String(_last_doctrine[t]).split(", ", false):
			var rec: Array = _doctrine_record[t].get(dn, [0, 0])
			if w == t:
				rec[0] += 1
			elif w == 1 - t:
				rec[1] += 1
			_doctrine_record[t][dn] = rec
	_ai_picks = ["", ""]
	_ai_type_picks = ["", ""]
	if not over:
		# the next battle: the freshest four put forward; the computer picks its drills
		# a human side keeps the number it fielded (four if it has not chosen); the
		# freshest companies of that number go forward, and a computer side matches it
		var want := [FIGHTING, FIGHTING]
		for t in 2:
			if hud.commanders[t] != "computer":
				want[t] = mini(maxi(int(_fielded_last[t]), 1), pick_limit())
		for t in 2:
			if hud.commanders[t] != "computer" or hud.commanders[1 - t] == "computer":
				_default_picks(t, want[t])
				_prepare_battle(t)
		for t in 2:
			if hud.commanders[t] == "computer" and hud.commanders[1 - t] != "computer":
				if Quartermaster.ready():
					_ai_plan(t)
					continue
				_default_picks(t, _computer_count(t))   # its own guess, made blind
				_prepare_battle(t)
		for t in 2:
			if hud.commanders[t] == "computer" and not epic and not Quartermaster.ready():
				_ai_pick(t, false)
				_sync_from_manager(t)
	var next_layout: String = front[campaign_field - 1]
	var summary := {"round": campaign_round, "field": layout, "field_no": fought_on,
		"next_field": next_layout, "next_field_no": campaign_field, "front": front.duplicate(), "wins": campaign_wins.duplicate(),
		"kills": campaign_kills.duplicate(), "history": campaign_rounds.duplicate(true), "counts": counts,
		"men_before": men_before, "men_after": men_after, "men_full": (EPIC_COMPANIES if epic else ARMY_COMPANIES) * COMPANY_MEN,
		"armies": [army_view(0), army_view(1)], "merges": merges, "over": over, "campaign_winner": cw, "why": why,
		"fall_back": _fall_back.duplicate(), "war_units": war_unit_rows(), "result": result, "ai_picks": _ai_picks.duplicate(), "ai_type_picks": _ai_type_picks.duplicate(), "ai_doctrines": _last_doctrine.duplicate(), "epic": epic,
		"men_start": EPIC_COMPANIES * COMPANY_MEN if epic else ARMY_COMPANIES * COMPANY_MEN}
	if not over:
		# the next battlefield goes up now, so it can be surveyed before the companies are chosen
		_rebuild_field(next_layout)
		hud.set_round(campaign_round + 1, next_layout, men_after, campaign_field)
		if cam != null:
			cam.refit()
	else:
		campaign_active = false
		hud.campaign_ended()
		if epic:
			_end_epic_armies()
		_refresh_men_all()   # the war is over: the armies stand at full strength for whatever is next
	get_tree().create_timer(2.0).timeout.connect(func(): hud.show_round(summary))
	if DisplayServer.get_name() == "headless":
		print("round %d on %d. %s: %s v %s -> %s (%s) fell %d/%d ran %d/%d; armies %d/%d men; front %d -> %d%s%s" % [campaign_round, fought_on, layout,
			result["presets"][0], result["presets"][1], result["winner_name"], result["reason"],
			counts[0]["fell"], counts[1]["fell"], counts[0]["ran"], counts[1]["ran"], men_after[0], men_after[1], fought_on, campaign_field,
			(" merges: " + "; ".join(merges)) if not merges.is_empty() else "", (" | OVER: %s wins - %s" % [MatchManager.TEAM_NAMES[cw], why]) if over else ""])
		get_tree().create_timer(2.5).timeout.connect(func():
			print("round panel: %s, %d rows" % [hud.results_title.text, hud.results_box.get_child_count()])
			if over:
				print("campaign: wins %s kills %s winner %d (%s)" % [str(campaign_wins), str(campaign_kills), cw, why])
				get_tree().quit()
			else:
				if OS.get_cmdline_user_args().has("--testpicks"):
					# exercise the picker: Red puts every company in, and falls back as far as it may
					for i in (armies[0] as Array).size():
						if not armies[0][i]["fights"] and (armies[0][i]["men"] as Array).size() > 0:
							toggle_army_pick(0, i)
					if not _fall_back.is_empty() and int(_fall_back["side"]) == 0:
						fall_back_to(int(_fall_back["lo"]))
						print("  Red falls back to field %d" % campaign_field)
					print("  fielding %d v %d" % [_fielded(0), _fielded(1)])
				hud.results_overlay.visible = false
				_next_round())


## The beaten side falls back further than it was pushed: the next battle is on field no,
## and all the ground between is given up.
func fall_back_to(no: int) -> void:
	if not campaign_active or _fall_back.is_empty():
		return
	no = clampi(no, int(_fall_back["lo"]), int(_fall_back["hi"]))
	if no == campaign_field:
		return
	campaign_field = no
	var layout: String = front[campaign_field - 1]
	_rebuild_field(layout)
	for t in 2:
		if hud.commanders[t] == "computer":
			if Quartermaster.ready():
				_ai_plan(t)   # the ground has changed: the computer thinks again
				continue
			_sync_from_manager(t)
			_ai_pick(t, false)   # the ground has changed: the computer thinks again
			_sync_from_manager(t)
	hud.set_round(campaign_round + 1, layout, [_army_men(0), _army_men(1)], campaign_field)
	hud.refresh_pick()
	if cam != null:
		cam.refit()


# ---------------------------------------------------------------- the armies (Armies screen)

## Both armies from the battalions set up at start (A-D, repeated to twelve), every man fresh.
func _init_armies() -> void:
	for t in 2:
		manager.store_company(t)
		var src: Array = manager.companies[t]
		armies[t] = []
		for i in ARMY_COMPANIES:
			var s: Dictionary = src[i % src.size()]
			armies[t].append({"name": ARMY_NAMES[i], "drill": String(s["persona_name"]), "type": String(s["type_name"]),
				"type_obj": (s["type"] as SoldierType).copy(), "men": _fresh_men(t, i), "fights": i < FIGHTING})


func _fresh_men(t: int, i: int) -> Array:
	var men := []
	for k in COMPANY_MEN:
		men.append({"name": "%s%s %d" % [MatchManager.TEAM_NAMES[t][0], ARMY_NAMES[i % ARMY_NAMES.size()], k + 1], "seed": randi(), "kills": 0, "rounds": 0})
	return men


## Every company back to full strength with new men (a new war, or a single battle after one).
func _refresh_men_all() -> void:
	for t in 2:
		for i in (armies[t] as Array).size():
			armies[t][i]["men"] = _fresh_men(t, i)


## Men in a company, for every company of both armies: 10 (40 a side in four) or 20.
func set_company_men(n: int) -> void:
	if campaign_active:
		return
	COMPANY_MEN = n
	MERGE_BELOW = 3 if COMPANY_MEN <= 10 else 5
	_refresh_men_all()


## Quick fill: an army patterned on a battalion preset (its four companies, repeated).
func fill_army(t: int, bname: String) -> void:
	var spec: Array = MatchManager.BATTALIONS.get(bname, [])
	if spec.is_empty():
		return
	for i in (armies[t] as Array).size():
		var e: Array = spec[i % spec.size()]
		set_company(t, i, String(e[0]), String(e[1]))


## One company's drill and type (type by preset name; "" leaves it as it is).
func set_company(t: int, i: int, drill_name: String, type_name: String) -> void:
	var a: Dictionary = armies[t][i]
	if drill_name != "":
		a["drill"] = drill_name
	if type_name != "":
		a["type_obj"] = SoldierType.preset(type_name)
		a["type"] = type_name if type_name != "Random" else (a["type_obj"] as SoldierType).label()


func set_company_rank(t: int, i: int, rank: String) -> void:
	armies[t][i]["rank"] = rank


func copy_to_all(t: int, i: int) -> void:
	var src: Dictionary = armies[t][i]
	for a in armies[t]:
		if a == src:
			continue
		a["drill"] = src["drill"]
		a["type"] = src["type"]
		a["type_obj"] = (src["type_obj"] as SoldierType).copy()


## A single battle (or a Sim): the chosen companies of each side, at full strength.
func _prepare_single() -> void:
	for t in 2:
		for i in (armies[t] as Array).size():
			if (armies[t][i]["men"] as Array).size() < COMPANY_MEN:
				armies[t][i]["men"] = _fresh_men(t, i)
		_prepare_battle(t)


func _close_pick() -> void:
	if hud != null:
		hud.close_pick()



func _ui_walk() -> void:
	hud.show_start()
	await _shot("start")
	hud.open_setup("test")
	hud.refresh_setup()
	fill_army(0, "Your drills")
	hud._sel[0] = 2
	hud._fill_editor(0)
	set_company(0, 2, "Hammer", "Brawler")
	hud._finetune[0] = true
	hud._fill_editor(0)
	hud._on_type_slider2(0, "accuracy", 0.6)
	copy_to_all(1, 0)
	set_company_men(20)
	hud.refresh_setup()
	await _shot("setup")
	print("setup: red C = %s / %s, blue all %s, men %d" % [armies[0][2]["drill"], armies[0][2]["type"], armies[1][5]["drill"], (armies[0][0]["men"] as Array).size()])
	hud.show_pick()
	pick_all(0)
	toggle_army_pick(1, 0)
	toggle_army_pick(1, 6)
	hud.field_chosen.emit("Ridge")
	await _shot("pick")
	print("pick: %d v %d on %s, overlay %s" % [_fielded(0), _fielded(1), field.layout_name, hud._pick_overlay.visible])
	await get_tree().create_timer(0.5).timeout
	hud.new_match_requested.emit()
	print("battle: %d v %d men in %d v %d companies" % [manager.side_total(0), manager.side_total(1), (manager.companies[0] as Array).size(), (manager.companies[1] as Array).size()])
	await get_tree().create_timer(1.0).timeout
	await _shot("battle")
	manager.time_limit = 75.0
	await get_tree().create_timer(55.0).timeout
	cam.zoom_view(0.45)
	await _shot("battle2")
	await manager.match_ended
	await get_tree().create_timer(2.5).timeout
	print("result panel rows %d" % hud.results_box.get_child_count())
	await _shot("result")
	var t0 := Time.get_ticks_msec()
	hud.simulate_requested.emit()
	await manager.match_ended
	print("simulated battle: %.1f s real for %d s of battle; 3d drawn again %s" % [(Time.get_ticks_msec() - t0) / 1000.0, int(manager.elapsed), not get_viewport().disable_3d])
	await get_tree().create_timer(1.0).timeout
	hud.show_pick()
	hud.campaign_requested.emit()
	print("campaign pick open %s, title %s" % [hud._pick_overlay.visible, hud._pick_title.text])
	hud.next_round_requested.emit()
	print("campaign battle 1: %d v %d companies" % [(manager.companies[0] as Array).size(), (manager.companies[1] as Array).size()])
	await get_tree().create_timer(4.0).timeout
	hud.retreat_requested.emit()   # Red gives up the field
	print("retreat: side %d" % manager.retreat_side)
	await manager.match_ended
	print("retreat ended at %d s" % int(manager.elapsed))
	await get_tree().create_timer(2.5).timeout
	print("round panel: %s" % hud.results_title.text)
	await _shot("round")
	hud.show_pick()
	await _shot("pick2")
	print("pick 2: %s" % hud._pick_title.text)
	hud.open_setup("")
	print("setup in campaign: %s" % hud._setup_camp_btn.text)
	hud.campaign_abandoned.emit()
	print("abandoned; men %d" % (armies[0][0]["men"] as Array).size())
	hud.epic_requested.emit()
	await get_tree().create_timer(0.5).timeout
	hud.show_pick()
	toggle_army_pick(0, 20)   # an eleventh is refused
	await _shot("epic_pick")
	print("epic: %d companies a side, %d v %d picked; title %s" % [(armies[0] as Array).size(), _fielded(0), _fielded(1), hud._pick_title.text])
	hud.next_round_requested.emit()
	print("epic battle 1: %d v %d companies, %d v %d men" % [(manager.companies[0] as Array).size(), (manager.companies[1] as Array).size(), manager.side_total(0), manager.side_total(1)])
	await get_tree().create_timer(3.0).timeout
	await _shot("epic_battle")
	hud.campaign_abandoned.emit()
	print("epic abandoned; army back to %d companies" % (armies[0] as Array).size())
	get_tree().quit()



## --shots=dir: save what the screen shows (under a real or virtual display).
func _shot(tag: String) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	for k in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, tag])


## The war's books, company by company: every battle's men, shots, thrusts, kills and losses
## added to the army company they belong to.
func _add_war_units(result: Dictionary) -> void:
	var seen := {}
	for m in result["soldiers"]:
		var t: int = m["team"]
		var c: int = int(m.get("company", 0))
		if c >= (manager.companies[t] as Array).size():
			continue
		var co: Dictionary = manager.companies[t][c]
		var key := "%d:%d" % [t, int(co.get("army_i", c))]
		if not war_units.has(key):
			war_units[key] = {"team": t, "name": co["name"], "drill": co["persona_name"], "type": co["type_name"], "battles": 0,
				"men": 0, "fell": 0, "ran": 0, "shots": 0, "hits": 0, "thrusts": 0, "thrust_hits": 0, "kills": 0, "bkills": 0}
		var u: Dictionary = war_units[key]
		u["drill"] = co["persona_name"]
		u["type"] = co["type_name"]
		if not seen.has(key):
			seen[key] = true
			u["battles"] += 1
		u["men"] += 1
		if not m["alive"]:
			u["fell"] += 1
		elif m["routed"] or m["gone"]:
			u["ran"] += 1
		u["shots"] += int(m["shots"])
		u["hits"] += int(m["hits"])
		u["thrusts"] += int(m.get("thrusts", 0))
		u["thrust_hits"] += int(m.get("thrust_hits", 0))
		u["kills"] += int(m["kills"])
		u["bkills"] += int(m["bayonet_kills"])
		u["gkills"] = int(u.get("gkills", 0)) + int(m.get("grenade_kills", 0))


func war_unit_rows() -> Array:
	var keys := war_units.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b) if String(a).length() == String(b).length() else String(a).length() < String(b).length())
	var out := []
	for k in keys:
		out.append((war_units[k] as Dictionary).duplicate())
	return out
