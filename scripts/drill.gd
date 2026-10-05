class_name Drill
extends RefCounted
## A drill: a company's behaviour written as plain rules, parsed from `drills/*.drill`.
##
##   drill "Thin Red Line"
##   about "Two ranks, volley at sixty paces, never charge first."
##   type Even
##   dials nerve 0.95 discipline 0.95 cohesion 0.9 cover 0.1 patience 0.6 aggression 0.3
##
##   sergeant:
##     when enemy charging and enemy within 40 -> hold; volley at 30
##     otherwise -> advance slow
##   man:
##     when enemy within 3 -> bayonet
##     when volley called and loaded -> fire
##
## Rules are read top to bottom; the first whose condition holds - and whose action can be done
## - wins the tick. Anything no rule decides falls to the engine's own behaviour, driven by the
## dials, so a short drill is still a whole soldier. There is no eval: only the words below.

## ---- the vocabulary -------------------------------------------------------------------------
## Condition patterns: tokens, with #D distance (m; "paces"/"yards" accepted), #P percent,
## #S seconds, #X number, $W one word, $R the rest of the atom.
const CONDITIONS := [
	[["always"], "always"],
	[["spotted"], "spotted"],
	[["mates", "running"], "mates_running"],
	[["rank", "ahead", "engaged"], "rank_ahead_engaged"],
	[["front", "rank", "engaged"], "rank_ahead_engaged"],
	[["rank", "ahead", "firing"], "rank_ahead_firing"],
	[["rank", "behind", "firing"], "rank_behind_firing"],
	[["rear", "rank", "firing"], "rank_behind_firing"],
	[["enemy", "engaged", "elsewhere"], "enemy_engaged_elsewhere"],
	[["enemy", "engaged", "with", "a", "neighbour"], "enemy_engaged_elsewhere"],
	[["enemy", "engaged", "with", "a", "neighbor"], "enemy_engaged_elsewhere"],
	[["enemy", "broken", "nearby"], "enemy_broken_nearby"],
	[["enemy", "running", "nearby"], "enemy_broken_nearby"],
	[["neighbour", "charging"], "neighbour_charging"],
	[["neighbor", "charging"], "neighbour_charging"],
	[["neighbour", "falling", "back"], "neighbour_falling_back"],
	[["neighbor", "falling", "back"], "neighbour_falling_back"],
	[["neighbour", "engaged"], "neighbour_engaged"],
	[["neighbor", "engaged"], "neighbour_engaged"],
	[["neighbour", "broken"], "neighbour_broken"],
	[["neighbor", "broken"], "neighbour_broken"],
	[["enemy", "within", "#D"], "enemy_within"],
	[["enemy", "closer", "than", "#D"], "enemy_within"],
	[["enemy", "beyond", "#D"], "enemy_beyond"],
	[["enemy", "further", "than", "#D"], "enemy_beyond"],
	[["enemy", "charging"], "enemy_charging"],
	[["enemy", "in", "cover"], "enemy_in_cover"],
	[["enemy", "broken"], "enemy_broken"],
	[["enemy", "breaking"], "enemy_breaking"],
	[["enemy", "uphill"], "enemy_uphill"],
	[["enemy", "downhill"], "enemy_downhill"],
	[["enemy", "visible"], "enemy_visible"],
	[["enemy", "hidden"], "enemy_hidden"],
	[["enemy", "outnumbers", "us", "by", "#P"], "enemy_outnumbers"],
	[["enemy", "outnumbers", "us"], "enemy_outnumbers"],
	[["we", "outnumber", "enemy", "by", "#P"], "we_outnumber"],
	[["we", "outnumber", "them", "by", "#P"], "we_outnumber"],
	[["we", "outnumber", "enemy"], "we_outnumber"],
	[["we", "outnumber", "them"], "we_outnumber"],
	[["enemy", "loaded", "under", "#P"], "enemy_loaded_under"],
	[["enemy", "reloading"], "enemy_reloading"],
	[["enemy", "losses", "over", "#P"], "enemy_losses_over"],
	[["my", "losses", "over", "#P"], "losses_over"],
	[["our", "losses", "over", "#P"], "losses_over"],
	[["losses", "over", "#P"], "losses_over"],
	[["#P", "loaded"], "frac_loaded"],
	[["loaded"], "loaded"],
	[["out", "of", "ammo"], "out_of_ammo"],
	[["ammo", "under", "#X"], "ammo_under"],
	[["in", "cover"], "in_cover"],
	[["enemy", "in", "smoke"], "enemy_in_smoke"],
	[["in", "smoke"], "in_smoke"],
	[["smoke", "between", "us"], "smoke_between"],
	[["smoke", "between"], "smoke_between"],
	[["wind", "behind", "us"], "wind_behind"],
	[["wind", "at", "our", "backs"], "wind_behind"],
	[["kneeling"], "kneeling"],
	[["tired"], "tired"],
	[["winded"], "winded"],
	[["wounded"], "wounded"],
	[["courage", "under", "#X"], "courage_under"],
	[["alone"], "alone"],
	[["on", "high", "ground"], "high_ground"],
	[["volley", "called"], "volley_called"],
	[["mode", "is", "$W"], "mode_is"],
	[["charging"], "charging"],
	[["losing", "the", "exchange"], "losing_exchange"],
	[["winning", "the", "exchange"], "winning_exchange"],
	[["no", "harm", "for", "#S"], "no_harm_for"],
	[["time", "over", "#S"], "time_over"],
	[["round", "#X"], "round_is"],
	[["field", "is", "open"], "field_open"],
	[["field", "is", "thick"], "field_thick"],
	[["field", "is", "$R"], "field_is"],
	[["phase", "is", "$W"], "phase_is"],
	[["chance", "#P"], "chance"],
]

const MAN_ACTIONS := [
	[["fire", "aimed"], "fire"],
	[["fire", "if", "loaded"], "fire"],
	[["fire", "at", "will"], "fire"],
	[["fire"], "fire"],
	[["hold", "fire"], "hold_fire"],
	[["bayonet"], "charge"],
	[["charge"], "charge"],
	[["reload", "kneeling"], "reload_kneel"],
	[["reload"], "reload"],
	[["take", "cover", "within", "#D"], "cover"],
	[["take", "cover"], "cover"],
	[["keep", "slot", "tight"], "slot_tight"],
	[["keep", "slot", "loose"], "slot_loose"],
	[["keep", "slot"], "slot"],
	[["back", "#D"], "back"],
	[["fall", "back", "#D"], "back"],
	[["advance"], "advance"],
	[["take", "the", "high", "ground", "within", "#D"], "high_ground"],
	[["take", "high", "ground", "within", "#D"], "high_ground"],
	[["take", "the", "high", "ground"], "high_ground"],
	[["take", "high", "ground"], "high_ground"],
	[["clear", "the", "smoke"], "clear_smoke"],
	[["step", "out", "of", "the", "smoke"], "clear_smoke"],
	[["step", "out", "of", "smoke"], "clear_smoke"],
	[["sneak", "#D"], "sneak"],
	[["sneak"], "sneak"],
	[["hold", "kneeling"], "hold_kneel"],
	[["hold"], "hold"],
	[["follow", "sergeant"], "follow"],
	[["stand", "fast"], "stand_fast"],
	[["run"], "run"],
	[["set", "phase", "$W"], "set_phase"],
]

const SERGEANT_ACTIONS := [
	[["advance", "slow"], "advance_slow"],
	[["advance", "fast"], "advance_fast"],
	[["advance"], "advance"],
	[["hold"], "hold"],
	[["charge"], "charge"],
	[["fall", "back", "#D"], "fallback"],
	[["fall", "back"], "fallback"],
	[["rally"], "rally"],
	[["press"], "press"],
	[["find", "cover"], "find_cover"],
	[["form", "tight"], "form_tight"],
	[["form", "open"], "form_open"],
	[["form", "skirmish"], "form_skirmish"],
	[["volley", "by", "halves"], "volley_halves"],
	[["fire", "by", "halves"], "volley_halves"],
	[["volley", "at", "#D"], "volley_at"],
	[["volley", "when", "#P", "loaded"], "volley_when"],
	[["volley"], "volley_now"],
	[["fire", "at", "will"], "at_will"],
	[["hold", "fire"], "hold_fire"],
	[["wheel", "left"], "wheel_left"],
	[["wheel", "right"], "wheel_right"],
	[["stand", "fast"], "stand_fast"],
	[["set", "phase", "$W"], "set_phase"],
]

## Actions that modify but do not end the evaluation (the next rule is still read).
const MODIFIERS := ["stand_fast", "set_phase", "form_tight", "form_open", "form_skirmish", "find_cover", "wheel_left", "wheel_right"]

const PACE := 0.75
const YARD := 0.9144

var name := ""
var about := ""
var type_name := "Even"
var dials := {}
var sergeant_rules: Array = []   # {cond, actions: Array[{id, args}], line, text}
var man_rules: Array = []
var errors: Array[String] = []
var source := ""


## ---- parsing --------------------------------------------------------------------------------

static func parse(text: String) -> Drill:
	var d := Drill.new()
	d.source = text
	var block := ""
	var lines := text.split("\n")
	for i in lines.size():
		var raw: String = lines[i]
		var line := raw.strip_edges()
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash).strip_edges()
		if line == "":
			continue
		var ln := i + 1
		var low := line.to_lower()
		if low.begins_with("drill "):
			d.name = _quoted(line.substr(6))
		elif low.begins_with("about "):
			d.about = _quoted(line.substr(6))
		elif low.begins_with("type "):
			d.type_name = line.substr(5).strip_edges().capitalize()
			if not SoldierType.PRESETS.has(d.type_name):
				d.errors.append("line %d: no such type '%s' (Even, Marksman, Grenadier, Runner, Ironside, Brawler, Scout, Shinobi)" % [ln, d.type_name])
		elif low.begins_with("dials "):
			var parts := low.substr(6).split(" ", false)
			var k := 0
			while k + 1 < parts.size():
				var tr: String = parts[k]
				if not Personality.TRAITS.has(tr):
					d.errors.append("line %d: '%s' is not a dial (%s)" % [ln, tr, ", ".join(Personality.TRAITS)])
				else:
					d.dials[tr] = clampf(float(parts[k + 1]), 0.0, 1.0)
				k += 2
		elif low == "sergeant:" or low == "company:":
			block = "sergeant"
		elif low == "man:" or low == "men:" or low == "each man:":
			block = "man"
		elif low.begins_with("when ") or low.begins_with("otherwise"):
			if block == "":
				d.errors.append("line %d: a rule before 'sergeant:' or 'man:'" % ln)
				continue
			var rule := d._parse_rule(low, ln, block)
			if not rule.is_empty():
				rule["text"] = line
				(d.sergeant_rules if block == "sergeant" else d.man_rules).append(rule)
		else:
			d.errors.append("line %d: can't read '%s'" % [ln, line])
	if d.name == "":
		d.errors.append("the drill has no name (drill \"...\")")
	return d


static func _quoted(s: String) -> String:
	s = s.strip_edges()
	if s.begins_with("\"") and s.ends_with("\"") and s.length() >= 2:
		return s.substr(1, s.length() - 2)
	return s


func _parse_rule(low: String, ln: int, block: String) -> Dictionary:
	var arrow := low.find("->")
	if arrow < 0:
		errors.append("line %d: a rule needs '->' between the condition and what to do" % ln)
		return {}
	var cond_s := low.substr(0, arrow).strip_edges()
	var act_s := low.substr(arrow + 2).strip_edges()
	var cond: Variant = true
	if cond_s.begins_with("when "):
		var toks := _tokenize(cond_s.substr(5))
		var pos := [0]
		cond = _parse_or(toks, pos, ln)
		if pos[0] < toks.size():
			errors.append("line %d: can't read the condition from '%s'" % [ln, " ".join(toks.slice(pos[0]))])
	var actions: Array = []
	for part in act_s.split(";", false):
		var toks := _tokenize(part)
		if not toks.is_empty() and toks[0] == "then":
			toks = toks.slice(1)
		if toks.is_empty():
			continue
		var table: Array = SERGEANT_ACTIONS if block == "sergeant" else MAN_ACTIONS
		var m := _match(toks, table)
		if m.is_empty():
			errors.append("line %d: '%s' is not something a %s can do" % [ln, " ".join(toks), "sergeant" if block == "sergeant" else "man"])
			continue
		actions.append(m)
	if actions.is_empty():
		return {}
	return {"cond": cond, "actions": actions, "line": ln}


static func _tokenize(s: String) -> Array:
	var out := []
	var cur := ""
	for ch in s:
		if ch == "(" or ch == ")":
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(ch)
		elif ch == " " or ch == "\t" or ch == ",":
			if cur != "":
				out.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func _parse_or(toks: Array, pos: Array, ln: int) -> Variant:
	var left: Variant = _parse_and(toks, pos, ln)
	while pos[0] < toks.size() and toks[pos[0]] == "or":
		pos[0] += 1
		left = ["or", left, _parse_and(toks, pos, ln)]
	return left


func _parse_and(toks: Array, pos: Array, ln: int) -> Variant:
	var left: Variant = _parse_not(toks, pos, ln)
	while pos[0] < toks.size() and toks[pos[0]] == "and":
		pos[0] += 1
		left = ["and", left, _parse_not(toks, pos, ln)]
	return left


func _parse_not(toks: Array, pos: Array, ln: int) -> Variant:
	if pos[0] < toks.size() and toks[pos[0]] == "not":
		pos[0] += 1
		return ["not", _parse_not(toks, pos, ln)]
	if pos[0] < toks.size() and toks[pos[0]] == "(":
		pos[0] += 1
		var inner: Variant = _parse_or(toks, pos, ln)
		if pos[0] < toks.size() and toks[pos[0]] == ")":
			pos[0] += 1
		else:
			errors.append("line %d: a '(' without its ')'" % ln)
		return inner
	# an atom: the words up to and/or/)
	var atom := []
	while pos[0] < toks.size() and not ["and", "or", ")"].has(toks[pos[0]]):
		atom.append(toks[pos[0]])
		pos[0] += 1
	if atom.is_empty():
		errors.append("line %d: a condition is missing" % ln)
		return false
	# "... for 10s": the condition must have held that long
	var held := -1.0
	if atom.size() >= 3 and atom[atom.size() - 2] == "for" and _is_seconds(atom[atom.size() - 1]) and atom[0] != "no":
		held = _num(atom[atom.size() - 1])
		atom = atom.slice(0, atom.size() - 2)
	var m := _match(atom, CONDITIONS)
	if m.is_empty():
		errors.append("line %d: don't know the condition '%s'" % [ln, " ".join(atom)])
		return false
	if held >= 0.0:
		return ["for", m, held, "%d:%s" % [ln, " ".join(atom)]]
	return m


static func _is_seconds(tok: String) -> bool:
	return tok.ends_with("s") and tok.substr(0, tok.length() - 1).is_valid_float()


static func _num(tok: String) -> float:
	var t := tok
	for suf in ["m", "s", "%"]:
		if t.ends_with(suf):
			t = t.substr(0, t.length() - 1)
	return float(t)


## Match tokens against a pattern table; the first pattern that consumes every token wins.
static func _match(toks: Array, table: Array) -> Dictionary:
	for entry in table:
		var pat: Array = entry[0]
		var args := []
		var i := 0
		var ok := true
		for p in pat:
			if i >= toks.size():
				ok = false
				break
			var tok: String = toks[i]
			if p == "#D":
				if not _num_ok(tok):
					ok = false
					break
				var v := _num(tok)
				i += 1
				if i < toks.size() and (toks[i] == "paces" or toks[i] == "pace"):
					v *= PACE
					i += 1
				elif i < toks.size() and (toks[i] == "yards" or toks[i] == "yard" or toks[i] == "yd"):
					v *= YARD
					i += 1
				elif i < toks.size() and (toks[i] == "m" or toks[i] == "metres" or toks[i] == "meters"):
					i += 1
				args.append(v)
			elif p == "#P":
				if not _num_ok(tok):
					ok = false
					break
				var v := _num(tok)
				if tok.ends_with("%") or v > 1.0:
					v /= 100.0
				args.append(v)
				i += 1
				if i < toks.size() and toks[i] == "percent":
					i += 1
			elif p == "#S" or p == "#X":
				if not _num_ok(tok):
					ok = false
					break
				args.append(_num(tok))
				i += 1
				if p == "#S" and i < toks.size() and (toks[i] == "seconds" or toks[i] == "second" or toks[i] == "sec"):
					i += 1
			elif p == "$W":
				args.append(tok)
				i += 1
			elif p == "$R":
				args.append(" ".join(toks.slice(i)))
				i = toks.size()
			else:
				if tok != p:
					ok = false
					break
				i += 1
		if ok and i == toks.size():
			return {"id": entry[1], "args": args}
	return {}


static func _num_ok(tok: String) -> bool:
	var t := tok
	for suf in ["m", "s", "%"]:
		if t.ends_with(suf):
			t = t.substr(0, t.length() - 1)
	return t.is_valid_float()


## ---- evaluation ------------------------------------------------------------------------------

## The dials as a personality, for everything in the engine that reads a trait.
func personality() -> Personality:
	var p := Personality.preset("Balanced")
	for k in dials:
		p.set_trait(k, dials[k])
	return p


## Run a rule block. `sense` answers a condition id + args; `act` tries an action and says
## whether it could be done. Returns true if some rule decided the tick.
func run(rules: Array, sense: Callable, act: Callable, memory: Dictionary, now: float, tally: Dictionary = {}) -> bool:
	for r in rules:
		if not _eval(r["cond"], sense, memory, now):
			continue
		var decided := false
		var any := false
		for a in r["actions"]:
			var done: bool = act.call(a["id"], a["args"])
			if done:
				any = true
				if not MODIFIERS.has(a["id"]):
					decided = true
		if any:
			tally[r["line"]] = int(tally.get(r["line"], 0)) + 1
		if decided:
			return true
	return false


func _eval(c: Variant, sense: Callable, memory: Dictionary, now: float) -> bool:
	if c is bool:
		return c
	if c is Dictionary:
		return sense.call(c["id"], c["args"])
	var op: String = c[0]
	match op:
		"and":
			return _eval(c[1], sense, memory, now) and _eval(c[2], sense, memory, now)
		"or":
			return _eval(c[1], sense, memory, now) or _eval(c[2], sense, memory, now)
		"not":
			return not _eval(c[1], sense, memory, now)
		"for":
			var key: String = c[3]
			if _eval(c[1], sense, memory, now):
				if not memory.has(key):
					memory[key] = now
				return now - float(memory[key]) >= float(c[2])
			memory.erase(key)
			return false
	return false


## ---- the library ----------------------------------------------------------------------------

static var _library: Dictionary = {}
static var _order: Array[String] = []


static func library() -> Dictionary:
	if _library.is_empty():
		_load_library()
	return _library


static func names() -> Array[String]:
	if _library.is_empty():
		_load_library()
	return _order


static func named(n: String) -> Drill:
	var lib := library()
	return lib.get(n, null)


static func _load_library() -> void:
	var dir := DirAccess.open("res://drills")
	if dir == null:
		push_error("no res://drills directory")
		return
	var files: Array[String] = []
	for f in dir.get_files():
		# exported packs list the originals with a .remap/.import suffix sometimes; plain text is kept as is
		if f.ends_with(".drill"):
			files.append(f)
	files.sort()
	for f in files:
		var text := FileAccess.get_file_as_string("res://drills/" + f)
		var d := Drill.parse(text)
		if not d.errors.is_empty():
			push_warning("%s: %s" % [f, "; ".join(d.errors)])
		_library[d.name] = d
		_order.append(d.name)
