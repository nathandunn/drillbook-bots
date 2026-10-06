class_name Quartermaster
extends RefCounted
## The computer's quartermaster: which army to raise, and which companies to send into each
## battle - read off a table of fought battles (data/ai_table.json, made by tools/batch/
## doctrine_gen.py + doctrine_an.py): a set of candidate armies ("templates"), each fought against
## an army of every drill on every field, both sides under their generals.
##
## The enemy is read as a mix of drills (what his army is made of, and what he sent last time),
## and each template is scored as its win rate against each of those drills on this field,
## weighted by the mix. The best is taken most of the time - the next best now and then, so the
## computer is not a clockwork.

const TABLE := "res://data/ai_table.json"

static var _table: Dictionary = {}
static var _loaded := false


static func table() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(TABLE):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
			if j is Dictionary:
				_table = j
	return _table


static func ready() -> bool:
	return not (table().get("templates", {}) as Dictionary).is_empty()


## {template name: {"Drill/Type": companies}}
static func templates() -> Dictionary:
	return table().get("templates", {})


static func is_mixed(tname: String) -> bool:
	return (templates().get(tname, {}) as Dictionary).size() > 1


## Win rate of template `tname` against an army of drill `opp` on `field`, smoothed toward the
## same match-up over every field, and that toward the template's rate against everybody.
static func rate(tname: String, opp: String, field: String) -> float:
	var w: Dictionary = table().get("wins", {}).get(tname, {})
	var all_w := 0.0
	var all_n := 0.0
	for o in w:
		for f in w[o]:
			all_w += float(w[o][f][0])
			all_n += float(w[o][f][1])
	var base := (all_w + 1.0) / (all_n + 2.0)
	if not w.has(opp):
		return base
	var ow := 0.0
	var on := 0.0
	for f in w[opp]:
		ow += float(w[opp][f][0])
		on += float(w[opp][f][1])
	var opp_rate := (ow + 3.0 * base) / (on + 3.0)
	var cell: Array = w[opp].get(field, [0, 0])
	return (float(cell[0]) + 4.0 * opp_rate) / (float(cell[1]) + 4.0)


## Expected win rate of a template against an enemy read as {drill: share}, on a field.
static func score(tname: String, enemy: Dictionary, field: String) -> float:
	var tot := 0.0
	var s := 0.0
	for d in enemy:
		s += float(enemy[d]) * rate(tname, String(d), field)
		tot += float(enemy[d])
	return s / maxf(tot, 0.0001)


## Templates best first for these fields (averaged): [[score, name], ...].
static func ranked(enemy: Dictionary, fields: Array) -> Array:
	var out := []
	for tn in templates():
		var s := 0.0
		for f in fields:
			s += score(tn, enemy, String(f))
		out.append([s / maxf(fields.size(), 1), tn])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


## The army to raise for a war on these fields: a mixed army unless a single drill looks
## clearly better (by 5 points). Returns the template name and why.
static func raise_army(enemy: Dictionary, fields: Array) -> Array:
	var r := ranked(enemy, fields)
	if r.is_empty():
		return ["", ""]
	var best_mix: Array = []
	var best_pure: Array = []
	for e in r:
		if is_mixed(String(e[1])) and best_mix.is_empty():
			best_mix = e
		if not is_mixed(String(e[1])) and best_pure.is_empty():
			best_pure = e
	if best_mix.is_empty():
		return [r[0][1], "the best army found"]
	if not best_pure.is_empty() and float(best_pure[0]) > float(best_mix[0]) + 0.05:
		return [best_pure[1], "one drill looks clearly best (%d%% to %d%% for the best mix)" % [int(best_pure[0] * 100), int(best_mix[0] * 100)]]
	return [best_mix[1], "a mixed army (%d%% expected)" % int(best_mix[0] * 100)]


## The template for one battle: the best most of the time, the second or third now and then.
## `allowed` (optional) limits the choice to templates the army can field.
static func pick(enemy: Dictionary, field: String, rng_val: float, allowed: Array = []) -> Array:
	var r := ranked(enemy, [field])
	if not allowed.is_empty():
		r = r.filter(func(e): return allowed.has(e[1]))
	if r.is_empty():
		return []
	var i := 0
	if r.size() > 1 and rng_val > 0.7:
		i = 1
	if r.size() > 2 and rng_val > 0.9:
		i = 2
	return r[i]


## A template's companies scaled to n: [["Drill", "Type"], ...] (largest shares first).
static func companies_for(tname: String, n: int) -> Array:
	var comp: Dictionary = templates().get(tname, {})
	var total := 0.0
	for k in comp:
		total += float(comp[k])
	var keys := comp.keys()
	keys.sort_custom(func(a, b): return float(comp[a]) > float(comp[b]))
	var counts := {}
	var given := 0
	for k in keys:
		var c := int(floor(float(comp[k]) / total * n))
		counts[k] = c
		given += c
	var i := 0
	while given < n and not keys.is_empty():
		counts[keys[i % keys.size()]] += 1
		given += 1
		i += 1
	var out := []
	# interleave so a minority is spread along the line, not bunched on one flank
	var left := counts.duplicate()
	while out.size() < n:
		for k in keys:
			if int(left[k]) > 0:
				var parts := String(k).split("/")
				out.append([parts[0], parts[1] if parts.size() > 1 else "Even"])
				left[k] = int(left[k]) - 1
				if out.size() >= n:
					break
	return out
