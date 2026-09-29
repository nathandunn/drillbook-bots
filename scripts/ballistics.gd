class_name Ballistics
extends RefCounted
## The .58 rifle-musket and its Minié ball: a real flight, not a dice roll.
##
## The ball leaves at 340 m/s (between the US Springfield's ~950 ft/s and the Enfield's
## quoted 1,250 ft/s) and loses speed to the air, v = V0·e^(-K·x). It falls under gravity for
## as long as it is in the air. The rifle is sighted for 100 yards - the battle sight - so the
## ball rises a hand's breadth above the line of sight in the first 50 m, crosses it at 91 m
## and drops away after. With the 300-yard leaf the same numbers give a mid-range rise of
## ~43 in, which is what the 1860 comparative firings recorded.
##
## Aim is an angular spread (mrad, one standard deviation, each axis). A trained marksman on
## the range groups at 1.8 mrad, a recruit who has never fired a practice round at 7; that
## reproduces the 1860 trials (96 % at 100 yd, ~64 % at 200, ~46 % at 300 on a 2 ft wide
## target) at the good end. Battle is not the range: smoke, noise, haste and fear open every
## man's spread about sixfold, which is why armies that shot well on the range still fired
## hundreds of rounds for every man they hit.

const V0 := 340.0          # m/s at the muzzle
const K := 0.0012          # per metre: velocity decay to the air
const G := 9.81
const ZERO := 91.44        # the battle sight: 100 yards
const SIGMA_GOOD := 1.8    # mrad: a trained marksman on the range
const SIGMA_POOR := 7.0    # mrad: a recruit on the range
const BATTLE := 6.5        # how much wider every man shoots when it is real
const BODY_W := 0.5        # a man's width, front on
const BODY_H := 1.75       # standing
const KNEEL_H := 1.2       # on one knee
const AIM_H := 1.1         # the point of aim: the belt buckle to the chest

static var _tan_zero := drop(ZERO) / ZERO


## Seconds for the ball to travel x metres.
static func time_to(x: float) -> float:
	return (exp(K * x) - 1.0) / (K * V0)


## How far the ball has fallen under gravity after x metres of flight.
static func drop(x: float) -> float:
	var t := time_to(x)
	return 0.5 * G * t * t


## Height of the ball above the line of sight at x metres, on the battle sight.
static func rise(x: float) -> float:
	return x * _tan_zero - drop(x)


## A man's spread on the range, in mrad, from his accuracy skill (0..1).
static func sigma_range(skill: float) -> float:
	return SIGMA_GOOD * pow(SIGMA_POOR / SIGMA_GOOD, 1.0 - clampf(skill, 0.0, 1.0))


## P(hit) on a standing man at d metres, on the range, from a rest: for the setup panel.
static func p_range(skill: float, d: float, battle := false) -> float:
	var s := sigma_range(skill) * 0.001 * d * (BATTLE if battle else 1.0)
	var px := _p_between(-BODY_W * 0.5, BODY_W * 0.5, 0.0, s)
	var py := _p_between(-AIM_H, BODY_H - AIM_H, rise(d), s)
	return px * py


## P(lo < X < hi) for X ~ N(mu, s).
static func _p_between(lo: float, hi: float, mu: float, s: float) -> float:
	if s <= 0.0:
		return 1.0 if lo <= mu and mu <= hi else 0.0
	return _cdf((hi - mu) / s) - _cdf((lo - mu) / s)


static func _cdf(z: float) -> float:
	return 0.5 * (1.0 + _erf(z / sqrt(2.0)))


## Abramowitz & Stegun 7.1.26: good to 1.5e-7.
static func _erf(x: float) -> float:
	var sgn := 1.0 if x >= 0.0 else -1.0
	x = absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return sgn * y


## Normal sample, Box-Muller.
static func gauss(rng: RandomNumberGenerator) -> float:
	var u1 := maxf(rng.randf(), 1e-9)
	var u2 := rng.randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
