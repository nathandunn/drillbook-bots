class_name Era
extends RefCounted
## The two wars Drillbook can fight: the 1860s (rifle-musket and bayonet - the original game) and the
## 1640s (pike and shot: matchlocks, pikes, harquebusiers, cuirassiers, hussars, sakers, archers and
## clubmen, every company bought on a budget that has to pay for its kit, its wages and its food).

const NAMES := ["1860s", "1640s"]
const HELP := {
	"1860s": "Rifle-muskets and bayonets: the original Drillbook war",
	"1640s": "Pike and shot: matchlocks, pikes, horse with pistol and sword, sakers - and a budget for kit, wages and food",
}

## The 1640s types on the company editor, in the order shown.
const TYPES_1640 := ["Musketeer", "Firelock", "Pikeman", "Pike and shot", "Archer", "Clubman", "Dragoon", "Harquebusier", "Cuirassier", "Hussar", "Saker"]

## Twenty-company armies of the 1640s: [drill, type] per company, A to T. The first four are the ones
## that go in first. Each fits a £12,000 budget at ten men a company, 90 days, full rations.
const ARMIES := {
	"Swedish brigade": [["Salvee", "Musketeer"], ["Pike Block", "Pikeman"], ["Salvee", "Musketeer"], ["Charge Home", "Harquebusier"],
		["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Shot", "Musketeer"], ["Charge Home", "Harquebusier"],
		["Pike and Shot", "Pike and shot"], ["Dragoons", "Dragoon"], ["Gallop", "Harquebusier"], ["Artillery", "Saker"],
		["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Salvee", "Musketeer"], ["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Charge Home", "Harquebusier"], ["Dragoons", "Dragoon"], ["Artillery", "Saker"]],
	"Spanish tercio": [["Pike and Shot", "Pike and shot"], ["Pike Block", "Pikeman"], ["Pike and Shot", "Pike and shot"], ["Caracole", "Cuirassier"],
		["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Shot", "Musketeer"], ["Caracole", "Cuirassier"],
		["Pike and Shot", "Pike and shot"], ["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Artillery", "Saker"],
		["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Caracole", "Cuirassier"], ["Shot", "Musketeer"], ["Artillery", "Saker"]],
	"New Model Army": [["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Shot", "Musketeer"], ["Charge Home", "Harquebusier"],
		["Charge Home", "Harquebusier"], ["Shot", "Firelock"], ["Pike Block", "Pikeman"], ["Dragoons", "Dragoon"],
		["Shot", "Musketeer"], ["Charge Home", "Harquebusier"], ["Shot", "Firelock"], ["Artillery", "Saker"],
		["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Shot", "Musketeer"], ["Charge Home", "Harquebusier"], ["Shot", "Firelock"], ["Pike Block", "Pikeman"], ["Dragoons", "Dragoon"], ["Shot", "Musketeer"]],
	"Cavalier horse": [["Gallop", "Harquebusier"], ["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Gallop", "Harquebusier"],
		["Caracole", "Cuirassier"], ["Shot", "Musketeer"], ["Gallop", "Harquebusier"], ["Pike Block", "Pikeman"],
		["Shot", "Musketeer"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Artillery", "Saker"],
		["Shot", "Musketeer"], ["Pike Block", "Pikeman"], ["Shot", "Musketeer"], ["Gallop", "Harquebusier"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Shot", "Musketeer"], ["Pike Block", "Pikeman"]],
	"Dutch companies": [["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Charge Home", "Harquebusier"],
		["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"],
		["Charge Home", "Harquebusier"], ["Dragoons", "Dragoon"], ["Charge Home", "Harquebusier"], ["Artillery", "Saker"],
		["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Charge Home", "Harquebusier"], ["Dragoons", "Dragoon"], ["Artillery", "Saker"]],
	"Peasant host": [["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Pike and Shot", "Pike and shot"],
		["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"],
		["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Charge Home", "Harquebusier"], ["Clubmen", "Clubman"],
		["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Pike and Shot", "Pike and shot"], ["Pike and Shot", "Pike and shot"], ["Charge Home", "Harquebusier"]],
	"The old ways": [["Archers", "Archer"], ["Pike Block", "Pikeman"], ["Archers", "Archer"], ["Lance Charge", "Hussar"],
		["Archers", "Archer"], ["Pike Block", "Pikeman"], ["Archers", "Archer"], ["Lance Charge", "Hussar"],
		["Archers", "Archer"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Archers", "Archer"],
		["Archers", "Archer"], ["Archers", "Archer"], ["Archers", "Archer"], ["Pike Block", "Pikeman"], ["Pike Block", "Pikeman"], ["Lance Charge", "Hussar"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"]],
	"Polish-Lithuanian": [["Lance Charge", "Hussar"], ["Shot", "Musketeer"], ["Lance Charge", "Hussar"], ["Dragoons", "Dragoon"],
		["Shot", "Musketeer"], ["Clubmen", "Clubman"], ["Lance Charge", "Hussar"], ["Clubmen", "Clubman"],
		["Shot", "Musketeer"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Artillery", "Saker"],
		["Shot", "Musketeer"], ["Shot", "Musketeer"], ["Shot", "Musketeer"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Clubmen", "Clubman"], ["Dragoons", "Dragoon"], ["Charge Home", "Harquebusier"]],
}
const ARMY_HELP := {
	"Swedish brigade": "Gustavus Adolphus: salvoes at close range, pikes beside the shot, aggressive horse and a regimental gun",
	"Spanish tercio": "Deep pike-and-shot squares, more pikes, cuirassiers who caracole. Old, slow, hard",
	"New Model Army": "Disciplined shot and pike, Ironside horse that charges home and re-forms, dragoons, firelocks to guard the guns",
	"Cavalier horse": "Rupert's Royalists: four troops of horse who charge first and think later, and too few foot",
	"Dutch companies": "Mixed companies throughout - every one with its own pikes in the middle and shot on the sleeves",
	"Peasant host": "Clubmen and pressed men stiffened with a few trained-band companies: numbers, and little else",
	"The old ways": "What if 1595 had gone the other way: longbows, pikes and winged hussars",
	"Polish-Lithuanian": "Three banners of winged hussars backed by shot, dragoons and peasant levies. Kircholm, 1605",
}

## The muster's money, per side: budget in whole pounds (at ten men a company; doubled at twenty),
## days in the field and rations.
const BUDGETS := [6000, 9000, 12000, 15000, 20000]
const DAYS := [30, 60, 90, 180]
const DEFAULT_BUDGET := 12000
const DEFAULT_DAYS := 90

## The 1640s war: twenty companies raised once and never replaced, up to ten into any one battle,
## and ten battles to carry the front - so every company spent is one fewer for the end.
const COMPANIES := 20
const PICK := 10
const BATTLES := 10
const LETTERS := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"]


## The drills shown for an era: its own, and the drills that suit any war.
static func drill_ok(d: Drill, era: String) -> bool:
	if d == null:
		return false
	if d.era == "1640s":
		return era == "1640s"
	if era == "1640s":
		return d.name in ["Regulars", "Skirmishers", "Shock", "Militia", "Veterans", "Artillery"]
	return true


static func types(era: String, base: Array) -> Array:
	if era == "1640s":
		return TYPES_1640
	return base
