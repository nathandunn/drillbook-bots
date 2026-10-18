class_name Kit
extends RefCounted
## What a man carries: his firearm (or bow, or none), his hand weapon, his armour and his horse.
## A SoldierType says what a man is good at; a Kit says what he has. The 1860s types all carry the
## rifle-musket and bayonet; the 1640s types (Era "1640s") carry the pike-and-shot kit, priced from
## English Civil War accounts (see the Pike & Shot Bots notes).
##
## gun:       rifle | matchlock | firelock | bow | pistol | carbine | ""   ("" = no missile weapon)
## reload:    seconds for a trained man (the rifle keeps its own rule in Soldier.apply_type). A figure
##            stands for five men in ranks that fire in turn, so a musket company's fire is the ranks'
##            countermarch, not one man's minute with his match and rammer
## range:     metres he will fire out to
## spread:    multiplies the aim spread: a smoothbore throws a ball far wider than a rifle
## ammo:      rounds (or arrows) carried
## misfire:   chance the piece fails to go off (a matchlock's pan flashes, the match goes out)
## kill:      chance a hit in the body kills outright rather than wounds
## melee:     bayonet | sword | pike | lance | bill
## reach:     metres his hand weapon reaches (a pike 4.5 m; a bayonet 1.9)
## armour:    chance a ball that hits him is turned by the plate (arrows: much more; blades: less)
## mounted:   rides a horse
## value:     what a man is worth in men of the line (sets the number of men a company)
## kit_d / pay_d / food_d: pence per man - kit once, pay and food (fodder too) per day

const ERAS := ["1860s", "1640s"]

const RIFLE := {"gun": "rifle", "reload": 20.0, "range": 100.0, "spread": 1.0, "ammo": 20, "misfire": 0.0, "kill": 0.62,
	"melee": "bayonet", "reach": 1.9, "armour": 0.0, "mounted": false, "value": 1.0}

const KITS := {
	"Musketeer": {"era": "1640s", "gun": "matchlock", "reload": 20.0, "range": 75.0, "spread": 1.7, "ammo": 12, "misfire": 0.12, "kill": 0.66,
		"melee": "sword", "reach": 1.6, "melee_mult": 0.85, "armour": 0.0, "value": 1.0,
		"kit_d": 240, "pay_d": 8, "food_d": 4, "rank": "Line",
		"note": "Matchlock musket on a rest, twelve charges in a bandolier, a sword. A heavy ball that wrecks a man, thrown wide; about one in eight fails to fire"},
	"Firelock": {"era": "1640s", "gun": "firelock", "reload": 18.0, "range": 75.0, "spread": 1.6, "ammo": 12, "misfire": 0.06, "kill": 0.66,
		"melee": "sword", "reach": 1.6, "melee_mult": 0.85, "armour": 0.0, "value": 1.0,
		"kit_d": 300, "pay_d": 8, "food_d": 4, "rank": "Line",
		"note": "Snaphance (flint) musket: dearer, quicker to load and half the misfires of a matchlock"},
	"Pikeman": {"era": "1640s", "gun": "", "reload": 0.0, "range": 0.0, "spread": 1.0, "ammo": 0, "misfire": 0.0, "kill": 0.0,
		"melee": "pike", "reach": 4.5, "melee_mult": 0.85, "armour": 0.15, "value": 1.0, "brace": true,
		"kit_d": 360, "pay_d": 8, "food_d": 4, "rank": "Line",
		"note": "Sixteen-foot pike, corslet and pot helmet. Strikes from four and a half metres; a formed body of pikes facing horse is a hedge no horse will ride into"},
	"Archer": {"era": "1640s", "gun": "bow", "reload": 8.0, "range": 95.0, "spread": 2.0, "ammo": 24, "misfire": 0.0, "kill": 0.36,
		"melee": "sword", "reach": 1.6, "melee_mult": 0.8, "armour": 0.0, "value": 1.0, "pen": 0.35,
		"kit_d": 160, "pay_d": 12, "food_d": 4, "rank": "Back",
		"note": "Longbow and two sheaves of arrows. Shoots six times to the musket's once and further, but an arrow seldom goes through plate; a skilled man, paid as one"},
	"Clubman": {"era": "1640s", "gun": "", "reload": 0.0, "range": 0.0, "spread": 1.0, "ammo": 0, "misfire": 0.0, "kill": 0.0,
		"melee": "bill", "reach": 2.4, "melee_mult": 0.65, "armour": 0.0, "value": 0.8,
		"kit_d": 24, "pay_d": 4, "food_d": 4, "rank": "Front",
		"note": "Farmer conscripts with bills, flails and straightened scythes: almost free to arm, but they still eat. Cheap enough to come five companies for one of horse"},
	"Pike and shot": {"era": "1640s", "mixed": {"Pikeman": 1, "Musketeer": 2}, "value": 1.0,
		"kit_d": 280, "pay_d": 8, "food_d": 4, "rank": "Line",
		"note": "A Dutch-style company: the middle third pikes, musketeers on both sleeves. Fires with two men in three and braces against horse with the rest"},
	"Dragoon": {"era": "1640s", "gun": "carbine", "reload": 28.0, "range": 55.0, "spread": 2.2, "ammo": 10, "misfire": 0.08, "kill": 0.6,
		"melee": "sword", "reach": 1.6, "melee_mult": 0.8, "armour": 0.0, "mounted": true, "value": 1.25,
		"kit_d": 1320, "pay_d": 18, "food_d": 8, "rank": "Line",
		"note": "Mounted shot on cheap nags: ride to the hedge, shoot from the saddle. Fast, but no match for real horse"},
	"Harquebusier": {"era": "1640s", "gun": "pistol", "reload": 45.0, "range": 14.0, "spread": 2.4, "ammo": 2, "misfire": 0.1, "kill": 0.55,
		"melee": "sword", "reach": 2.0, "melee_mult": 1.0, "armour": 0.2, "mounted": true, "value": 1.25,
		"kit_d": 3280, "pay_d": 24, "food_d": 10, "rank": "Line",
		"note": "The 1640s horseman: buff coat, back and breast, a brace of pistols fired at a few paces, then the sword at the gallop"},
	"Cuirassier": {"era": "1640s", "gun": "pistol", "reload": 45.0, "range": 12.0, "spread": 2.4, "ammo": 2, "misfire": 0.1, "kill": 0.55,
		"melee": "sword", "reach": 2.0, "melee_mult": 1.15, "armour": 0.45, "mounted": true, "value": 1.5,
		"kit_d": 4800, "pay_d": 30, "food_d": 12, "rank": "Line",
		"note": "What became of the knight: armoured to the knee on a great horse, pistols instead of a lance. Nearly proof against balls; so dear that few were kept"},
	"Hussar": {"era": "1640s", "gun": "pistol", "reload": 45.0, "range": 12.0, "spread": 2.4, "ammo": 1, "misfire": 0.1, "kill": 0.55,
		"melee": "lance", "reach": 3.4, "melee_mult": 1.1, "armour": 0.2, "mounted": true, "value": 1.5, "lance": true,
		"kit_d": 6000, "pay_d": 30, "food_d": 12, "rank": "Line",
		"note": "Polish winged hussar: a five-metre lance that hits like a cannonball on the first contact, then the sabre. Kircholm, 1605"},
	"Saker": {"era": "1640s", "gun": "", "reload": 0.0, "range": 0.0, "spread": 1.0, "ammo": 0, "misfire": 0.0, "kill": 0.0,
		"melee": "sword", "reach": 1.6, "melee_mult": 0.6, "armour": 0.0, "value": 2.5, "guns": true,
		"kit_d": 4500, "pay_d": 12, "food_d": 9, "rank": "Back",
		"note": "Sakers (5-pounders) with their gunners and draught horses: roundshot that skips through ranks. A gun for every five men"},
}

## The 1860s types, priced in the same pence for the budget (rough: a rifle-musket ~£3, horse and
## forage the dear part), so a budget can be shown in either era.
const PRICE_1860 := {
	"Even": [700, 12, 6], "Marksman": [900, 13, 6], "Grenadier": [760, 14, 6], "Runner": [700, 12, 6], "Ironside": [760, 14, 6],
	"Brawler": [700, 13, 6], "Scout": [760, 13, 6], "Shinobi": [760, 13, 6], "Gunner": [6000, 14, 10], "Cavalry": [4200, 24, 12],
}


static func has(type_name: String) -> bool:
	return KITS.has(type_name)


## The kit a man of this type carries; for a mixed company, the kit of the man at `slot` of `n`.
static func of(type_name: String, slot: int = 0, n: int = 1) -> Dictionary:
	if not KITS.has(type_name):
		var k := RIFLE.duplicate()
		k["mounted"] = type_name == "Cavalry"
		return k
	var kit: Dictionary = KITS[type_name]
	if kit.has("mixed"):
		return of(mixed_part(type_name, slot, n))
	var out := RIFLE.duplicate()
	out.merge(kit, true)
	return out


## Which part of a mixed company the man at `slot` of `n` belongs to: the middle third pikes.
static func mixed_part(type_name: String, slot: int, n: int) -> String:
	var mix: Dictionary = KITS[type_name]["mixed"]
	var pikes := int(round(float(n) * float(mix.get("Pikeman", 0)) / float(mix.values().reduce(func(a, b): return a + b, 0))))
	var first := (n - pikes) / 2
	return "Pikeman" if slot >= first and slot < first + pikes else "Musketeer"


static func era_of(type_name: String) -> String:
	return String(KITS[type_name].get("era", "1860s")) if KITS.has(type_name) else "1860s"


static func types_for(era: String) -> Array:
	var out := []
	if era == "1640s":
		for n in KITS:
			out.append(n)
	return out


static func value(type_name: String) -> float:
	return float(KITS[type_name].get("value", 1.0)) if KITS.has(type_name) else -1.0


static func is_guns(type_name: String) -> bool:
	return type_name == "Gunner" or (KITS.has(type_name) and bool(KITS[type_name].get("guns", false)))


static func is_mounted(type_name: String) -> bool:
	return type_name == "Cavalry" or (KITS.has(type_name) and bool(KITS[type_name].get("mounted", false)))


## [kit, pay a day, food a day] in pence for one man (one figure stands for MEN_PER_FIGURE).
static func price(type_name: String) -> Array:
	if KITS.has(type_name):
		var k: Dictionary = KITS[type_name]
		return [int(k["kit_d"]), int(k["pay_d"]), int(k["food_d"])]
	return PRICE_1860.get(type_name, [700, 12, 6])


## A figure on the field stands for this many soldiers on the muster roll.
const MEN_PER_FIGURE := 5

const RATIONS := {
	"Half": {"food": 0.5, "nerve": -0.12, "help": "Saves money; the men are sour and slow to stand, the horses weak (horse slower)"},
	"Full": {"food": 1.0, "nerve": 0.0, "help": "2 lb bread, 1 lb cheese or meat, beer; hay and oats for the horses"},
	"Generous": {"food": 1.3, "nerve": 0.06, "help": "Meat most days and plenty of beer: content soldiers stand longer"},
}


## What a company of `figures` men of this type costs for `days` in the field, in pence:
## {kit, pay, food, total}.
static func company_cost(type_name: String, figures: int, days: int, rations: String) -> Dictionary:
	var pr := price(type_name)
	var men := figures * MEN_PER_FIGURE
	var r: Dictionary = RATIONS.get(rations, RATIONS["Full"])
	var kit := men * int(pr[0])
	var pay := men * int(pr[1]) * days
	var food := int(round(float(men * int(pr[2]) * days) * float(r["food"])))
	return {"kit": kit, "pay": pay, "food": food, "total": kit + pay + food}


## "£1,234" (whole pounds; 240 pence to the pound).
static func pounds(d: int) -> String:
	var l := int(round(float(d) / 240.0))
	var s := str(l)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return "£" + s + out
