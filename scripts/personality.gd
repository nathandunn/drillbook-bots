class_name Personality
extends RefCounted
## Six 0..1 traits. Nobody gives a soldier orders: the formation, its spacing, the use of
## cover, when to fire, whether to fire together or run in with the bayonet, and when to fall
## back all come out of these through the brain in soldier.gd and the sergeant in
## match_manager.gd (who is just the steadiest man alive on his side).

const TRAITS: Array[String] = ["aggression", "discipline", "cohesion", "cover", "patience", "nerve"]

const TRAIT_HELP := {
	"aggression": "Close the distance; charge with the bayonet",
	"discipline": "Fire on the sergeant's volley and keep the line, rather than act alone",
	"cohesion": "How tightly the line stands (from loose skirmish order to shoulder to shoulder)",
	"cover": "Look for walls, fences and trees to fire from",
	"patience": "Hold fire until the enemy is close",
	"nerve": "Stand under losses; low nerve breaks and runs",
}

const PRESETS := {
	"Regulars":    {"aggression": 0.45, "discipline": 0.90, "cohesion": 0.85, "cover": 0.20, "patience": 0.60, "nerve": 0.65},
	"Skirmishers": {"aggression": 0.35, "discipline": 0.35, "cohesion": 0.15, "cover": 0.95, "patience": 0.45, "nerve": 0.50},
	"Shock":       {"aggression": 0.95, "discipline": 0.60, "cohesion": 0.70, "cover": 0.10, "patience": 0.25, "nerve": 0.85},
	"Militia":     {"aggression": 0.30, "discipline": 0.20, "cohesion": 0.40, "cover": 0.60, "patience": 0.15, "nerve": 0.25},
	"Veterans":    {"aggression": 0.55, "discipline": 0.75, "cohesion": 0.60, "cover": 0.55, "patience": 0.80, "nerve": 0.90},
	"Balanced":    {"aggression": 0.50, "discipline": 0.50, "cohesion": 0.50, "cover": 0.50, "patience": 0.50, "nerve": 0.50},
}

const PRESET_HELP := {
	"Regulars": "Tight line, volleys on command, steady",
	"Skirmishers": "Loose, in cover, fire at will",
	"Shock": "One volley then the bayonet",
	"Militia": "Ragged, jumpy, quick to run",
	"Veterans": "Patient, steady, use what cover the line allows",
	"Balanced": "Middle of everything",
}

var traits: Dictionary = {}


func _init(from: Dictionary = {}) -> void:
	for t in TRAITS:
		traits[t] = clampf(float(from.get(t, 0.5)), 0.0, 1.0)


static func preset(preset_name: String) -> Personality:
	if preset_name == "Random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var d := {}
		for t in TRAITS:
			d[t] = rng.randf()
		return Personality.new(d)
	return Personality.new(PRESETS.get(preset_name, PRESETS["Balanced"]))


func get_trait(t: String) -> float:
	return float(traits.get(t, 0.5))


func set_trait(t: String, v: float) -> void:
	traits[t] = clampf(v, 0.0, 1.0)


func copy() -> Personality:
	return Personality.new(traits)


## Same personality with per-man noise so a company of twenty isn't twenty clones.
func jittered(rng: RandomNumberGenerator, spread: float = 0.1) -> Personality:
	var d := {}
	for t in TRAITS:
		d[t] = clampf(get_trait(t) + rng.randf_range(-spread, spread), 0.0, 1.0)
	return Personality.new(d)


func label() -> String:
	var best := "Custom"
	var best_d := 0.3
	for n in PRESETS:
		var d := 0.0
		for t in TRAITS:
			d += absf(get_trait(t) - float(PRESETS[n][t]))
		d /= TRAITS.size()
		if d < best_d:
			best_d = d
			best = n
	return best


func to_dict() -> Dictionary:
	return traits.duplicate()
