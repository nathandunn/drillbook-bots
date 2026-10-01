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

# --- campaign: N rounds on different fields; the men who stand or run carry over
const CAMPAIGN_ROUNDS := 5
var campaign_active := false
var campaign_round := 0            # 1-based; 0 = not started
var campaign_wins := [0, 0]
var campaign_kills := [0, 0]
var campaign_rounds: Array[Dictionary] = []   # one summary per round fought
var campaign_rosters: Array = [[], []]        # survivors carried into the next round
var _pending_campaign_result: Dictionary = {}
var campaign_field := Field.START_FIELD   # 1..10 along the front; the winner pushes it toward the loser
var _last_fielded := ["", ""]    # the preset each side fought the last round with
var _ai_picks := ["", ""]
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
	add_child(field)
	_build_lighting()
	manager = MatchManager.new()
	manager.world = self
	manager.field = field
	manager.match_ended.connect(_on_match_ended)
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
		if args.has("companies"):
			var want := clampi(int(args["companies"]), 1, MatchManager.MAX_COMPANIES)
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
				var co := manager.new_company(t, c, f[0].strip_edges(), f[1].strip_edges() if f.size() > 1 else "Even",
					f[2].strip_edges() if f.size() > 2 else MatchManager.SLOTS[mini(c, 3)], per)
				if co.get("drill") == null:
					push_warning("no drill called %s" % f[0])
				cos2.append(co)
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
	add_child(cam)
	hud = Hud.new()
	add_child(hud)
	hud.setup(manager)
	hud.set_plan(Field.LAYOUT_ORDER.find(field.layout_name) + 1, field.layout_name)
	hud.mark_field(field.layout_name)
	hud.new_match_requested.connect(func():
		batch_left = 0
		batch_results.clear()
		if campaign_active:
			_abandon_campaign()
		else:
			_start_next())
	hud.batch_requested.connect(_run_batch)
	hud.campaign_requested.connect(_start_campaign)
	hud.next_round_requested.connect(_next_round)
	hud.campaign_abandoned.connect(_abandon_campaign)
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
	if args.has("campaign"):
		# --ui --campaign: a whole campaign, headless, rounds chained automatically
		_start_campaign()
		return
	if args.has("batch"):
		# --ui --batch=N: the Sim button's path, HUD and all, for a headless check of the panel
		_run_batch(maxi(int(args["batch"]), 1))
		return
	# nothing starts by itself: the setup panel asks what we are running
	hud.open_setup("What are we running? A campaign, or a single battle with these companies.")


func _setup_ui_scale() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var dpi := DisplayServer.screen_get_dpi()
	root.content_scale_factor = clampf(float(dpi) / 96.0, 1.0, 2.0)


## Speed up game time without coarsening physics: raise the tick rate to match.
func set_sim_speed(s: float) -> void:
	Engine.time_scale = s
	Engine.physics_ticks_per_second = int(round(60.0 * s))
	Engine.max_physics_steps_per_frame = maxi(8, int(s * 4.0))


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = not headless
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.72, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.75
	e.fog_enabled = true
	e.fog_light_color = Color(0.75, 0.8, 0.85)
	e.fog_density = 0.0004
	env.environment = e
	add_child(env)


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


func _on_match_ended(result: Dictionary) -> void:
	if batch_left > 0:
		batch_left -= 1
		batch_results.append(result)
		if headless:
			print("  battle %d: %s by %s in %ds (standing %d-%d)" % [result["match"], result["winner_name"], result["reason"], int(result["duration"]), result["alive"][0], result["alive"][1]])
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
	var keys := ["shots", "hits", "volleys", "charges", "fallbacks", "routed", "friendly", "thrusts", "thrust_hits"]
	var tot := {}
	for k in keys:
		tot[k] = [0, 0]
	var kills := [[0, 0], [0, 0]]
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
		var kt: float = float(kills[t][0] + kills[t][1])
		var dt: float = float(kills[1 - t][0] + kills[1 - t][1])
		txt += "%s per battle: %d shots at %d%%, %d volleys, %d charges, %d fall-backs, %d ran; killed %d by ball, %d by bayonet; %d friendly hits; kills %.1f, deaths %.1f, K/D %.2f.  " % [
			MatchManager.TEAM_NAMES[t], tot["shots"][t] / n, int(acc), tot["volleys"][t] / n, tot["charges"][t] / n,
			tot["fallbacks"][t] / n, tot["routed"][t] / n, kills[t][0] / n, kills[t][1] / n, tot["friendly"][t] / n,
			kt / n, dt / n, kt / maxf(dt, 1.0)]
	var battles := []
	for r in results:
		battles.append({"match": r["match"], "winner": r["winner"], "winner_name": r["winner_name"], "reason": r["reason"],
			"duration": r["duration"], "alive": r["alive"], "fighting": r["fighting"]})
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
	if hud != null:
		hud.set_plan(Field.LAYOUT_ORDER.find(layout) + 1, layout)
		hud.mark_field(layout)


func _start_campaign() -> void:
	batch_left = 0
	batch_results.clear()
	campaign_active = true
	campaign_round = 0
	campaign_wins = [0, 0]
	campaign_kills = [0, 0]
	campaign_rounds.clear()
	campaign_rosters = [[], []]
	manager.rosters = [[], []]
	campaign_field = Field.START_FIELD
	_last_fielded = ["", ""]
	_ai_picks = ["", ""]
	_ai_type_picks = ["", ""]
	_doctrine_record = [{}, {}]
	_last_doctrine = ["", ""]
	hud.campaign_started()
	# a computer commander opens with a pick of its own
	for t in 2:
		if hud.commanders[t] == "computer":
			_ai_pick(t, true)
	_next_round()


## Field the next round: survivors plus recruits to full strength, except the last round,
## which is fought with whoever is left.
func _next_round() -> void:
	if not campaign_active:
		return
	campaign_round += 1
	manager.round_no = campaign_round
	var layout: String = Field.LAYOUT_ORDER[campaign_field - 1]
	if field == null or field.layout_name != layout:
		_rebuild_field(layout)
	var last := campaign_round >= CAMPAIGN_ROUNDS
	for t in 2:
		var roster: Array = campaign_rosters[t].duplicate(true)
		if campaign_round > 1:
			_merge_broken(t, roster)
		if not last:
			# every company back to its size with recruits. A company with nobody left - wiped out, or
			# its handful merged into the next company along - is raised again from recruits, so every
			# company (and the drill it fights by) takes the field each round but the last.
			for c in (manager.companies[t] as Array).size():
				var co: Dictionary = manager.companies[t][c]
				var have := 0
				var next_no := 1
				for r in roster:
					if int(r.get("co", 0)) == c:
						have += 1
						next_no = maxi(next_no, int(r.get("no", 0)) + 1)
				while have < int(co["size"]):
					roster.append({"name": "%s%s %d" % [MatchManager.TEAM_NAMES[t][0], co["name"], next_no], "no": next_no, "co": c,
						"seed": randi(), "kills": 0, "rounds": 0, "recruit": true})
					next_no += 1
					have += 1
		manager.rosters[t] = roster
	hud.set_round(campaign_round, CAMPAIGN_ROUNDS, layout, [manager.rosters[0].size(), manager.rosters[1].size()], campaign_field)
	hud.set_plan(campaign_field, layout, campaign_round, CAMPAIGN_ROUNDS)
	_start_next()


## The computer's choice of personality for its side, applied to the manager for the coming
## round. Opening round: any of the five. After that: answer what the enemy fielded, unless
## the last round was won, in which case keep the winning choice 70 % of the time.
## A company cut down to a handful (fewer than 3 men, or under a quarter of its size) is broken
## up: whoever is left joins the nearest company along the line that still has men, and the
## broken company loses its men to the neighbour; it is raised again from recruits next round (not the last).
func _merge_broken(t: int, roster: Array) -> void:
	var cos: Array = manager.companies[t]
	var have := {}
	for r in roster:
		var c: int = int(r.get("co", 0))
		have[c] = int(have.get(c, 0)) + 1
	for c in cos.size():
		var n: int = int(have.get(c, 0))
		if n == 0 or (n >= 3 and n * 4 >= int(cos[c]["size"])):
			continue
		# the nearest company along the line (by slot) that is not itself broken
		var slot_i := MatchManager.SLOTS.find(String(cos[c]["slot"]))
		var best := -1
		var best_d := 99
		for o in cos.size():
			var on: int = int(have.get(o, 0))
			if o == c or on < 3 or on * 4 < int(cos[o]["size"]):
				continue
			var d: int = absi(MatchManager.SLOTS.find(String(cos[o]["slot"])) - slot_i)
			if d < best_d:
				best_d = d
				best = o
		if best < 0:
			continue   # nobody fit to take them in: they stay a (small) company of their own
		for r in roster:
			if int(r.get("co", 0)) == c:
				r["co"] = best
				r["merged_from"] = String(cos[c]["name"])
		have[best] = int(have.get(best, 0)) + n
		have[c] = 0


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
	manager.select_company(t, hud.selected_company(t) if hud != null else 0)
	if hud != null:
		hud._refresh_sliders(t)
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
	_rebuild_field("Walled Farm")
	hud.open_setup("Campaign abandoned. What next?")


## After a campaign round: bank the result, keep the men who stood or ran, drop the dead.
func _on_round_ended(result: Dictionary) -> void:
	var w: int = result["winner"]
	if w >= 0:
		campaign_wins[w] += 1
	var st: Dictionary = result["stats"]
	var survivors := [[], []]
	var counts := [{"stood": 0, "ran": 0, "fell": 0}, {"stood": 0, "ran": 0, "fell": 0}]
	for m in result["soldiers"]:
		var t: int = m["team"]
		if not m["alive"]:
			counts[t]["fell"] += 1
			continue
		if m["routed"] or m["gone"]:
			counts[t]["ran"] += 1
		else:
			counts[t]["stood"] += 1
		var no := int(String(m["name"]).get_slice(" ", 1)) if String(m["name"]).contains(" ") else 0
		survivors[t].append({"name": m["name"], "no": no, "co": int(m.get("company", 0)), "seed": m["seed"], "kills": m["career_kills"],
			"rounds": int(m["rounds"]) + 1, "recruit": false})
	for t in 2:
		campaign_kills[t] += st["kills"][t][0] + st["kills"][t][1]
		campaign_rosters[t] = survivors[t]
	var layout: String = Field.LAYOUT_ORDER[campaign_field - 1]
	# the front moves: the winner pushes the fight one field into the loser's country
	var fought_on := campaign_field
	if w == 0:
		campaign_field = mini(campaign_field + 1, Field.LAYOUT_ORDER.size())
	elif w == 1:
		campaign_field = maxi(campaign_field - 1, 1)
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
	for t in 2:
		if hud.commanders[t] == "computer":
			_ai_pick(t, false)
	var over: bool = campaign_round >= CAMPAIGN_ROUNDS or (survivors[0] as Array).is_empty() or (survivors[1] as Array).is_empty()
	var next_layout: String = Field.LAYOUT_ORDER[campaign_field - 1]
	var summary := {"round": campaign_round, "rounds": CAMPAIGN_ROUNDS, "field": layout,
		"next_field": next_layout, "next_field_no": campaign_field, "wins": campaign_wins.duplicate(),
		"kills": campaign_kills.duplicate(), "history": campaign_rounds.duplicate(true), "counts": counts,
		"next_sizes": [survivors[0].size(), survivors[1].size()], "last_next": campaign_round + 1 >= CAMPAIGN_ROUNDS,
		"team_sizes": [manager.side_total(0), manager.side_total(1)], "over": over, "result": result, "ai_picks": _ai_picks.duplicate(),
		"ai_type_picks": _ai_type_picks.duplicate(), "ai_doctrines": _last_doctrine.duplicate()}
	if not over:
		# the next battlefield goes up now, so it can be surveyed before personalities are chosen
		_rebuild_field(next_layout)
		hud.set_plan(campaign_field, next_layout, campaign_round + 1, CAMPAIGN_ROUNDS)
		if cam != null:
			cam.refit()
	if over:
		var cw := -1
		if campaign_wins[0] != campaign_wins[1]:
			cw = 0 if campaign_wins[0] > campaign_wins[1] else 1
		elif campaign_kills[0] != campaign_kills[1]:
			cw = 0 if campaign_kills[0] > campaign_kills[1] else 1
		summary["campaign_winner"] = cw
		campaign_active = false
		hud.campaign_ended()
	get_tree().create_timer(2.0).timeout.connect(func(): hud.show_round(summary))
	if DisplayServer.get_name() == "headless":
		print("round %d on %s: %s v %s -> %s (%s) stood %d/%d ran %d/%d fell %d/%d -> next %s, computer picks %s" % [campaign_round, layout,
			result["presets"][0], result["presets"][1], result["winner_name"], result["reason"],
			counts[0]["stood"], counts[1]["stood"], counts[0]["ran"], counts[1]["ran"], counts[0]["fell"], counts[1]["fell"], str(summary["next_sizes"]), str(_ai_picks) + " " + str(_ai_type_picks)])
		get_tree().create_timer(2.5).timeout.connect(func():
			print("round panel: %s, %d rows" % [hud.results_title.text, hud.results_box.get_child_count()])
			if over:
				print("campaign: wins %s kills %s winner %d" % [str(campaign_wins), str(campaign_kills), summary["campaign_winner"]])
				get_tree().quit()
			else:
				hud.results_overlay.visible = false
				_next_round())
