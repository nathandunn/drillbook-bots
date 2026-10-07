class_name SoldierType
extends RefCounted
## What a soldier *is*: five properties that always add up to the same budget, so every type costs the same
## and a strength is paid for somewhere else - the budget idea shared with Dodgeball Bots and
## Legion Bots. An even split (0.25 each) reproduces the base numbers exactly.

const PROPS: Array[String] = ["run", "melee", "accuracy", "stamina", "stealth"]
const BUDGET := 1.25   # five even shares of 0.25

const PROP_HELP := {
	"run": "Running and walking speed",
	"melee": "Bayonet: hit chance, parry and damage",
	"accuracy": "Musketry: hit chance at range and a quicker, cleaner reload",
	"stamina": "Wind: how long he can run and stay steady; recovers faster",
	"stealth": "How hard he is to notice: seen later, from closer, above all kneeling, in cover or creeping",
}

const PRESETS := {
	"Even":      {"run": 0.25, "melee": 0.25, "accuracy": 0.25, "stamina": 0.25, "stealth": 0.25},
	"Marksman":  {"run": 0.15, "melee": 0.12, "accuracy": 0.53, "stamina": 0.20, "stealth": 0.25},
	"Grenadier": {"run": 0.15, "melee": 0.40, "accuracy": 0.25, "stamina": 0.35, "stealth": 0.10},
	"Runner":    {"run": 0.50, "melee": 0.15, "accuracy": 0.15, "stamina": 0.20, "stealth": 0.25},
	"Ironside":  {"run": 0.18, "melee": 0.22, "accuracy": 0.15, "stamina": 0.45, "stealth": 0.25},
	"Brawler":   {"run": 0.35, "melee": 0.50, "accuracy": 0.00, "stamina": 0.15, "stealth": 0.25},
	"Scout":     {"run": 0.32, "melee": 0.20, "accuracy": 0.15, "stamina": 0.13, "stealth": 0.45},
	"Shinobi":   {"run": 0.38, "melee": 0.45, "accuracy": 0.02, "stamina": 0.06, "stealth": 0.34},
	"Gunner":    {"run": 0.20, "melee": 0.20, "accuracy": 0.30, "stamina": 0.40, "stealth": 0.15},
	"Cavalry":   {"run": 0.55, "melee": 0.50, "accuracy": 0.05, "stamina": 0.15, "stealth": 0.00},
}

const TYPE_HELP := {
	"Even": "No strengths, no holes - the reference build",
	"Marksman": "Hits at range, reloads clean; soft with the bayonet",
	"Grenadier": "Big man for the charge; a poor shot",
	"Runner": "Fast on his feet, and that's the whole of it",
	"Ironside": "Never tires; ordinary at everything else",
	"Brawler": "All bayonet and legs: the best in a melee and quick to get there; can barely shoot",
	"Scout": "Hard to see and quick: noticed late, above all creeping or in cover; little else",
	"Shinobi": "Fast and hard to see, deadly with the blade; tires fast and can barely shoot",
	"Gunner": "Serves the guns (a field gun for every five men): roundshot out to 400 m that skips through ranks and breaches fort walls",
	"Cavalry": "On horseback: twice as fast as a running man, a fearful charge with the sabre - but a big target that cannot take cover or kneel",
}

const CURVE := 0.8
const EVEN := 0.25

var props: Dictionary = {}


func _init(from: Dictionary = {}) -> void:
	for p in PROPS:
		props[p] = maxf(float(from.get(p, EVEN)), 0.0)
	normalize()


static func preset(preset_name: String) -> SoldierType:
	if preset_name == "Random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var d := {}
		for p in PROPS:
			d[p] = rng.randf_range(0.05, 1.0)
		return SoldierType.new(d)
	return SoldierType.new(PRESETS.get(preset_name, PRESETS["Even"]))


func get_prop(p: String) -> float:
	return float(props.get(p, EVEN))


func normalize() -> void:
	var total := 0.0
	for p in PROPS:
		total += float(props[p])
	if total <= 0.0001:
		for p in PROPS:
			props[p] = EVEN
		return
	for p in PROPS:
		props[p] = float(props[p]) / total * BUDGET


## Set one property and take the difference out of (or give back to) the others in
## proportion, so dragging one slider visibly moves the rest.
func set_and_rebalance(p: String, v: float) -> void:
	v = clampf(v, 0.0, 0.85)
	var rest := BUDGET - v
	var others_total := 0.0
	for q in PROPS:
		if q != p:
			others_total += float(props[q])
	if others_total <= 0.0001:
		for q in PROPS:
			props[q] = rest / float(PROPS.size() - 1)
	else:
		for q in PROPS:
			if q != p:
				props[q] = float(props[q]) / others_total * rest
	props[p] = v


## An even share scores 1.0; more is better linearly, less falls away on a curve.
func factor(p: String) -> float:
	var v := get_prop(p)
	if v >= EVEN:
		return 1.0 + (v - EVEN) / EVEN
	return pow(v / EVEN, CURVE)


## The same property as a 0..1 skill: nothing at 0, half at an even share, all at 0.5 and up.
func skill(p: String) -> float:
	return clampf(get_prop(p) / (EVEN * 2.0), 0.0, 1.0)


func copy() -> SoldierType:
	return SoldierType.new(props)


func jittered(rng: RandomNumberGenerator, spread: float = 0.03) -> SoldierType:
	var d := {}
	for p in PROPS:
		d[p] = maxf(get_prop(p) + rng.randf_range(-spread, spread), 0.02)
	return SoldierType.new(d)


func label() -> String:
	var best := "Custom"
	var best_d := 0.06
	for n in PRESETS:
		var d := 0.0
		for p in PROPS:
			d += absf(get_prop(p) - float(PRESETS[n][p]))
		d /= float(PROPS.size())
		if d < best_d:
			best_d = d
			best = n
	return best


func to_dict() -> Dictionary:
	return props.duplicate()
