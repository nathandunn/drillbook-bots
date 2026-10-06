class_name General
extends RefCounted
## The general: one plan - a "play" - for the whole side, laid over the companies' own drills.
## The drills still decide how each company fights (when to fire, find cover, fix bayonets); the
## play decides what the army does TOGETHER: go forward as one line, wait, swing the flanks
## round, and - in every play but "Drill book" - when one company goes in with the bayonet,
## the companies near it go in too.
##
## A side can be given a play by the player, or left to "General's choice": the general picks a
## play from what he can see of the two armies and changes it when the battle turns, and says why.

const CHOICE := "General's choice"
const PLAYS := ["General's choice", "General advance", "Hammer and anvil", "Hold and receive",
	"Feint and draw", "All-out charge", "Drill book"]
const HELP := {
	"General's choice": "The general picks the play from what he can see of both armies, and changes it when the battle turns. What he is thinking is shown at the top of the screen.",
	"General advance": "The whole line goes forward together, dressed on the slowest company - nobody runs ahead or falls back alone. When one company charges, every company near the enemy charges with it.",
	"Hammer and anvil": "The centre goes forward to firing range and stands (the anvil) while the companies on the flanks swing wide round the enemy's ends (the hammer). When the flanks are round, everyone goes in at once.",
	"Hold and receive": "Stand on the start line and shoot. Nobody goes forward until the enemy comes within 25 metres or starts to break - then the whole line charges together.",
	"Feint and draw": "The two companies nearest the centre go forward, fire, and fall back to the line. The rest wait. When the enemy follows them in to 40 metres of the line, everyone charges.",
	"All-out charge": "Everyone goes forward at the double and the whole army charges from 60 metres, all at once.",
	"Drill book": "No plan for the army: every company follows its own drill and nothing else (as before the general).",
}
const SHORT := {
	"General advance": "the line goes forward together",
	"Hammer and anvil": "centre holds, flanks swing round",
	"Hold and receive": "stand and shoot, charge together when they close",
	"Feint and draw": "centre goes forward and falls back to draw them on",
	"All-out charge": "everyone goes in at once",
	"Drill book": "every company by its own drill",
}

var t := 0
var chosen := CHOICE          # what the side was given
var play := "General advance" # what it is doing now
var thought := ""             # why, in the general's words
var phase := ""               # within the play: "swing" / "strike", "lure" / "strike"...
var strike := false           # the whole line goes in
var strike_t := -100.0
var since := 0.0              # when the play was taken up
var slowest := -INF           # the least advanced line (metres toward the enemy), for dressing
var start_line := {}          # c -> line_z at the start (for Hold and receive, Feint and draw)
var flank := {}               # c -> -1 / +1 for a hammer company, absent for the anvil
var lure := {}                # c -> true for the feinting companies
var lure_back := {}           # c -> true once a lure company has turned back
var in_range_since := {}      # c -> when a lure company first came in range
var enemy_edge := [0.0, 0.0]  # the enemy line's left and right ends (x)
var _last_check := -100.0
static var trace := false     # --trace: print the general's decisions (headless study)


func _init(side: int, given: String) -> void:
	t = side
	chosen = given if PLAYS.has(given) else CHOICE


func is_auto() -> bool:
	return chosen == CHOICE


## The line shown on the screen.
func label() -> String:
	var who: String = MatchManager.TEAM_NAMES[t]
	var p := "%s general: %s" % [who, play]
	if chosen != CHOICE:
		p = "%s plan: %s" % [who, play]
	var what: String = SHORT.get(play, "")
	if strike and play != "Drill book":
		what = "everyone in - charge!"
	elif phase != "":
		what = phase
	var s := p + (" - " + what if what != "" else "")
	if thought != "":
		s += "  (%s)" % thought
	return s


# ---------------------------------------------------------------- the start

func begin(m: MatchManager) -> void:
	start_line.clear()
	flank.clear()
	lure.clear()
	lure_back.clear()
	in_range_since.clear()
	strike = false
	strike_t = -100.0
	since = 0.0
	_last_check = -100.0
	for c in (m.orders[t] as Array).size():
		start_line[c] = float(m.orders[t][c].get("line_z", m.home_z(t)))
	if is_auto():
		var pick := _first_choice(m)
		_take(m, pick[0], pick[1])
	else:
		_take(m, chosen, "")
	_assign_roles(m)


func _take(m: MatchManager, p: String, why: String) -> void:
	if p != play or since == 0.0:
		since = m.elapsed
	play = p
	thought = why
	if trace:
		print("    %5.1fs %s general: %s (%s)" % [m.elapsed, MatchManager.TEAM_NAMES[t], p, why])
	phase = ""
	if p == "Hammer and anvil":
		phase = "flanks swinging round"
	elif p == "Feint and draw":
		phase = "centre going forward to draw them"
	elif p == "Hold and receive":
		phase = "standing to receive them"
	_assign_roles(m)


## Which companies are the hammer (the outer quarter at each end) and which are the lure (the two
## nearest the centre).
func _assign_roles(m: MatchManager) -> void:
	flank.clear()
	lure.clear()
	var line := []
	for c in (m.companies[t] as Array).size():
		if m.is_reserve(t, c) or m.fighting_company(t, c).is_empty():
			continue
		line.append([m.band_x(t, c), c])
	if line.is_empty():
		return
	line.sort_custom(func(a, b): return a[0] < b[0])
	var n := line.size()
	if n >= 3:
		var w := maxi(1, int(round(n / 4.0)))
		for i in w:
			flank[line[i][1]] = -1
			flank[line[n - 1 - i][1]] = 1
	var by_mid := line.duplicate()
	by_mid.sort_custom(func(a, b): return absf(a[0]) < absf(b[0]))
	for i in mini(2, maxi(1, n - 2)):
		lure[by_mid[i][1]] = true


# ---------------------------------------------------------------- what the general sees

static func _shooter(type_name: String) -> bool:
	return type_name in ["Marksman", "Scout"]


static func _bayonet(type_name: String) -> bool:
	return type_name in ["Brawler", "Grenadier", "Ironside", "Shinobi"]


func _make_up(m: MatchManager, side: int) -> Dictionary:
	var men := 0
	var shoot := 0
	var steel := 0
	for c in (m.companies[side] as Array).size():
		var n := m.fighting_company(side, c).size()
		var ty := String(m.companies[side][c].get("type_name", "Even"))
		men += n
		if _shooter(ty):
			shoot += n
		elif _bayonet(ty):
			steel += n
	var tot := maxf(men, 1)
	return {"men": men, "shoot": shoot / tot, "steel": steel / tot}


func _first_choice(m: MatchManager) -> Array:
	var us := _make_up(m, t)
	var them := _make_up(m, 1 - t)
	var ratio := float(us["men"]) / maxf(float(them["men"]), 1.0)
	# (from the play lab, 2026-10-05: an army all of marksmen does best pressing in together and
	# finishing with the bayonet, and one all of bayonets going forward as one line; standing to
	# receive lost for both. Mixed armies did best with this general choosing and changing.)
	if us["shoot"] >= 0.8:
		return ["All-out charge", "every man of ours is a marksman - press in shooting and finish with the bayonet"]
	if us["steel"] >= 0.8:
		return ["General advance", "all bayonets - go forward as one line and close"]
	if ratio >= 1.25:
		return ["Hammer and anvil", "we have %.1f men to their 1 - enough to go round them" % ratio]
	if us["shoot"] >= 0.5 and them["shoot"] < 0.4:
		return ["Hold and receive", "we out-shoot them - let them come to us"]
	if us["shoot"] < 0.35 and them["shoot"] >= 0.5:
		return ["All-out charge", "they out-shoot us - close before they can"]
	if us["steel"] >= 0.5 and them["steel"] < 0.3:
		return ["General advance", "we have the bayonets - go forward together and close"]
	return ["General advance", "evenly matched - go forward together"]


## Every second: dress the line, see whether the play's moment has come, and - for an auto
## general - whether the play still fits.
func tick(m: MatchManager) -> void:
	var tw := m.toward(t)
	slowest = INF
	for c in (m.companies[t] as Array).size():
		if m.is_reserve(t, c) or m.fighting_company(t, c).is_empty() or flank.has(c) or lure.has(c) and play == "Feint and draw":
			continue
		if String(m.companies[t][c].get("type_name", "")) == "Shinobi":
			continue   # ninjas keep their own road
		var o: Dictionary = m.orders[t][c]
		# a rank further back is measured from where it should stand: its depth behind the front
		var z := float(o.get("line_z", 0.0)) * tw + float(m.companies[t][c].get("depth", 0.0))
		slowest = minf(slowest, z)
	if slowest == INF:
		slowest = -INF
	# the enemy line's ends
	var lo := INF
	var hi := -INF
	for e in m.fighting(1 - t):
		lo = minf(lo, e.global_position.x)
		hi = maxf(hi, e.global_position.x)
	if lo < INF:
		enemy_edge = [lo, hi]
	if strike and m.elapsed - strike_t > 35.0:
		strike = false   # the rush has spent itself; back to the play
	_watch_moment(m)
	if is_auto() and m.elapsed - _last_check >= 3.0:
		_last_check = m.elapsed
		_rethink(m)


func _watch_moment(m: MatchManager) -> void:
	if play == "Drill book" or strike:
		return
	var routed := 0
	for e in m.alive_soldiers():
		if e.team != t and e.is_routed:
			routed += 1
	var enemy_n := maxf(float(m.fighting(1 - t).size()), 1.0)
	var go := ""
	# one company goes in: the others go with it (every play)
	for c in (m.companies[t] as Array).size():
		if m.fighting_company(t, c).is_empty() or m.is_reserve(t, c):
			continue
		var o: Dictionary = m.orders[t][c]
		if String(o.get("mode", "")) == "charge" and float(o.get("reach_d", INF)) < 30.0 and not lure.has(c):
			if String(m.companies[t][c].get("type_name", "")) != "Shinobi":
				go = "company %s is in with the bayonet - all go in" % m.companies[t][c]["name"]
				break
	if go == "" and routed >= maxi(4, int(enemy_n * 0.2)):
		go = "they are breaking - after them"
	if go == "":
		match play:
			"Hammer and anvil":
				var round_n := 0
				for c in flank:
					var o: Dictionary = m.orders[t][c]
					if float(o.get("reach_d", INF)) < 35.0:
						round_n += 1
				if round_n >= maxi(1, flank.size() / 2) or m.elapsed - since > 80.0:
					go = "the flanks are round - all go in"
			"Hold and receive":
				for c in (m.companies[t] as Array).size():
					if not m.fighting_company(t, c).is_empty() and float(m.orders[t][c].get("reach_d", INF)) < 25.0:
						go = "they are on us - meet them with the bayonet"
						break
			"Feint and draw":
				for c in (m.companies[t] as Array).size():
					if lure.has(c) or m.fighting_company(t, c).is_empty():
						continue
					if float(m.orders[t][c].get("reach_d", INF)) < 40.0:
						go = "they have followed us in - all charge"
						break
			"All-out charge":
				for c in (m.companies[t] as Array).size():
					if not m.fighting_company(t, c).is_empty() and float(m.orders[t][c].get("reach_d", INF)) < 60.0:
						go = "in range - charge!"
						break
	if go != "":
		if trace:
			print("    %5.1fs %s general: STRIKE - %s" % [m.elapsed, MatchManager.TEAM_NAMES[t], go])
		strike = true
		strike_t = m.elapsed
		phase = ""
		if not is_auto():
			thought = go
		else:
			thought = go


## An auto general weighs the battle every few seconds and changes the play when it no longer fits
## (not more often than every 15 seconds).
func _rethink(m: MatchManager) -> void:
	if strike or m.elapsed - since < 15.0:
		return
	var given := 0.0
	var taken := 0.0
	for c in (m.companies[t] as Array).size():
		var x: Array = m._exch.get(MatchManager.ck(t, c), [0.0, 0.0])
		given += float(x[0])
		taken += float(x[1])
	var ratio := m.strength_ratio(t)
	var quiet := m.elapsed - m._last_harm_t
	var want := ""
	var why := ""
	if ratio > 1.6 and play != "Hammer and anvil" and play != "All-out charge":
		want = "Hammer and anvil"
		why = "we are %.1f to 1 now - go round and finish them" % ratio
	elif taken > 2.0 * given + 3.0 and play in ["Hold and receive", "Feint and draw"] and ratio > 0.7:
		want = "General advance"
		why = "losing the firefight (%d hits taken to %d given) - go forward together and close" % [int(taken), int(given)]
	elif taken > 2.5 * given + 4.0 and play == "General advance" and ratio > 1.0 and _make_up(m, t)["steel"] >= 0.4:
		want = "All-out charge"
		why = "still losing the firefight (%d hits taken to %d given) - everyone in with the bayonet" % [int(taken), int(given)]
	elif ratio < 0.6 and play != "Hold and receive" and _make_up(m, t)["shoot"] > 0.2 and _make_up(m, t)["shoot"] < 0.8:
		want = "Hold and receive"
		why = "too few of us left to attack - hold what we have"
	elif play == "Hold and receive" and quiet > 25.0 and m.elapsed > 40.0:
		want = "General advance"
		why = "they won't come to us - go and get them"
	elif play == "Feint and draw" and m.elapsed - since > 70.0:
		want = "General advance"
		why = "they didn't take the bait - go forward together"
	if want != "":
		_take(m, want, why)


# ---------------------------------------------------------------- what it means for one company

## Called for each company after its drill has chosen a mode: the play's say. Returns the mode.
func mode_for(m: MatchManager, c: int, mode: String, order: Dictionary) -> String:
	if play == "Drill book":
		return mode
	var reach := float(order.get("reach_d", INF))
	var losses := m.company_losses(t, c)
	var ty := String(m.companies[t][c].get("type_name", ""))
	if strike and reach < 90.0 and losses < 0.6:
		# the line goes in with the bayonet; the marksmen behind close up and shoot it in
		if _shooter(ty) and reach > 12.0:
			order["press"] = true
			return "advance" if reach > 35.0 else "hold"
		return "charge"
	var ninja := ty == "Shinobi"
	if ninja:
		return mode
	# nobody goes back alone while the army is going forward
	if mode == "fallback" and losses < 0.35 and play != "Feint and draw":
		mode = "hold"
	match play:
		"Hammer and anvil":
			if not flank.has(c):
				# the anvil: forward to firing range, then stand and fire - no charging off alone
				if mode == "charge" and reach > 15.0:
					mode = "hold"
			else:
				if mode == "charge" or mode == "hold":
					mode = "advance"   # the hammer keeps going round
		"Hold and receive":
			if mode == "charge" and reach > 20.0:
				mode = "hold"
			elif mode == "advance":
				mode = "hold"
		"Feint and draw":
			if lure.has(c):
				if not in_range_since.has(c) and reach < 70.0:
					in_range_since[c] = m.elapsed
				if lure_back.get(c, false) or (in_range_since.has(c) and m.elapsed - float(in_range_since[c]) > 12.0):
					lure_back[c] = true
					var back := float(start_line.get(c, m.home_z(t))) - m.toward(t) * 6.0
					if (float(order.get("line_z", 0.0)) - back) * m.toward(t) > 3.0:
						order["rally_z"] = back
						mode = "fallback"
					else:
						mode = "hold"
				elif mode == "charge":
					mode = "hold"
			else:
				if mode == "charge" and reach > 15.0:
					mode = "hold"
				elif mode == "advance":
					mode = "hold"
		"All-out charge":
			if mode == "hold" or mode == "fallback":
				mode = "advance"
	return mode


## After the line's place has been set: dress it, hold it, or swing it. Changes `order` in place.
func place(m: MatchManager, c: int, order: Dictionary) -> void:
	if play == "Drill book" or strike:
		return
	var tw := m.toward(t)
	var mode := String(order.get("mode", ""))
	if mode == "charge":
		return
	if String(m.companies[t][c].get("type_name", "")) == "Shinobi":
		return
	var depth := float(m.companies[t][c].get("depth", 0.0))
	var z := float(order.get("line_z", 0.0)) * tw + depth
	match play:
		"General advance":
			if slowest > -INF and z > slowest + 8.0:
				order["line_z"] = (slowest + 8.0 - depth) * tw   # wait for the line
		"Hammer and anvil":
			if flank.has(c):
				# swing out past the enemy's end, then come on round it
				var side_x: float = enemy_edge[1] + 15.0 if int(flank[c]) > 0 else enemy_edge[0] - 15.0
				side_x = clampf(side_x, -Field.HALF_X + 6.0, Field.HALF_X - 6.0)
				order["center_x"] = lerpf(float(order.get("center_x", 0.0)), side_x, 0.25)
				order["line_z"] = clampf(float(order["line_z"]) + tw * 0.6, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
			elif slowest > -INF and z > slowest + 8.0:
				order["line_z"] = (slowest + 8.0 - depth) * tw
		"Hold and receive":
			var s0 := float(start_line.get(c, order["line_z"])) * tw
			if z - depth > s0 + 4.0:
				order["line_z"] = (s0 + 4.0) * tw
		"Feint and draw":
			if not lure.has(c):
				var s0 := float(start_line.get(c, order["line_z"])) * tw
				if z - depth > s0 + 4.0:
					order["line_z"] = (s0 + 4.0) * tw
		"All-out charge":
			order["line_z"] = clampf(float(order["line_z"]) + tw * 0.7, -Field.HALF_Z + 3.0, Field.HALF_Z - 3.0)
			order["press"] = true
