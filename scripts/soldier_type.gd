class_name SoldierType
extends RefCounted
## What a soldier *is*: four properties that always add up to 1, so every type costs the same
## and a strength is paid for somewhere else - the budget idea shared with Dodgeball Bots and
## Legion Bots. An even split (0.25 each) reproduces the base numbers exactly.

const PROPS: Array[String] = ["run", "melee", "accuracy", "stamina"]

const PROP_HELP := {
	"run": "Running and walking speed",
	"melee": "Bayonet: hit chance, parry and damage",
	"accuracy": "Musketry: hit chance at range and a quicker, cleaner reload",
	"stamina": "Wind: how long he can run and stay steady; recovers faster",
}

const PRESETS := {
	"Even":      {"run": 0.25, "melee": 0.25, "accuracy": 0.25, "stamina": 0.25},
	"Marksman":  {"run": 0.15, "melee": 0.12, "accuracy": 0.53, "stamina": 0.20},
	"Grenadier": {"run": 0.15, "melee": 0.50, "accuracy": 0.15, "stamina": 0.20},
	"Runner":    {"run": 0.50, "melee": 0.15, "accuracy": 0.15, "stamina": 0.20},
	"Ironside":  {"run": 0.18, "melee": 0.22, "accuracy": 0.15, "stamina": 0.45},
}

const TYPE_HELP := {
	"Even": "No strengths, no holes - the reference build",
	"Marksman": "Hits at range, reloads clean; soft with the bayonet",
	"Grenadier": "Big man for the charge; a poor shot",
	"Runner": "Fast on his feet, and that's the whole of it",
	"Ironside": "Never tires; ordinary at everything else",
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
		props[p] = float(props[p]) / total


## Set one property and take the difference out of (or give back to) the others in
## proportion, so dragging one slider visibly moves the rest.
func set_and_rebalance(p: String, v: float) -> void:
	v = clampf(v, 0.0, 0.85)
	var rest := 1.0 - v
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
