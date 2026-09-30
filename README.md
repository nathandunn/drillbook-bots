# Drillbook Bots — personalities written as drills

A fork of [Volley Bots](https://github.com/nathandunn/volley-bots) with the battalions of
[Battalion Bots](https://github.com/nathandunn/battalion-bots): **1-6 companies a side** (default
4 × 10, up to 20 men a company and 80 a side) on the 112 × 200 m field, each company with its own
size, type (run / melee / accuracy / stamina on one budget), place in the line (Left, Centre-left,
Centre-right, Right, Reserve) and **drill**. The six personality sliders are replaced by drills:
short, readable rule files in `drills/*.drill` that say what the sergeant and each man do and when.
Each company has its own sergeant reading its own drill; a captain per side only sends in the
reserve. Battalion presets: Line, Light, Assault column, Mixed, Old guard, and **Your drills**
(Sniper, Line, Linebreaker, Ninjas - the default for Red).

Per company, not per side: the exchange (`winning/losing the exchange`), `phase is`,
`my losses over`, `volley called`, `mode is`, `charging`. Per side: `enemy broken/breaking`,
`outnumbers`, `mates running`. A sergeant's `enemy …` words look at the ten enemy men nearest
his company.

```
drill "Thin Red Line"
about "Shoulder to shoulder. Volleys from sixty paces, never charges first, never runs."
type Marksman
dials aggression 0.30 discipline 0.95 cohesion 0.90 cover 0.10 patience 0.60 nerve 0.95

sergeant:
  when enemy charging and enemy within 40  -> hold; form tight; stand fast; volley at 30
  when my losses over 60%                  -> fall back 25
  when enemy within 60 paces               -> hold; form tight; volley when 70% loaded
  otherwise                                -> advance slow; form tight; hold fire

man:
  when volley called and loaded            -> fire
  otherwise                                -> keep slot tight
```

Rules are read top to bottom; the first whose condition holds - and whose action can be done -
decides the tick. Anything no rule decides falls to the Volley Bots engine, driven by the
`dials`, so a short drill is still a whole soldier. `scripts/drill.gd` holds the whole
vocabulary (conditions: enemy within/beyond/charging/in cover/broken/uphill/visible,
outnumbers, losses, loaded, in cover, tired, winded, courage, volley called, mode, the
exchange, no harm for Ns, time, round, field, phase, chance, `for Ns`; actions for the sergeant
and for the man). There is no eval - only those words.

- In the app: Edit Battalion → pick a company card → drill chips, **Read the drill** shows the
  text; Sim ×10 lists, per drill a side fielded, how often each rule decided.
- Lint: `godot --headless --path . -- --lint=drills/x.drill`. Battles: `--redbat="Your drills"`,
  `--red="Thin Red Line"` (every company of that side), `--companies=4 --csize=10`.
- Seed drills Regulars, Skirmishers, Shock, Militia, Veterans reproduce the Volley Bots presets
  within batch noise; Thin Red Line and Fabian Screen are worked examples.

Spec: `claude/drillbook-bots-spec.md` in the Ai Sim Framework project. What follows is the
Volley Bots README.

---

# Volley Bots — a line of twenty, single-shot rifles and bayonets

AI battle in Godot 4 (3D, web export). Two companies of up to **20 men a side** meet on
rolling ground - every field has its hills - with stone walls, fences, big rocks, roofless
ruins you can fight from inside, and trees. Mid-19th-century kit: a
muzzle-loading rifle (one shot, ~9 s to reload, poor at range), a bayonet, two legs and a
temper. Nobody takes orders — formation, spacing, cover, when to fire, whether to fire
together or go in with the bayonet, and when to fall back all come out of the men's
personalities.

Part of the Precog sim suite (sibling of Rock Bots / Legion Bots / Dodgeball Bots).

## What you choose

**Type** — four properties that always add up to 1, so a strength is paid for somewhere else:

| property | what it buys |
|---|---|
| run | walking and running speed |
| melee | bayonet hit chance, parry and damage |
| accuracy | musketry hit chance at range, and a quicker reload |
| stamina | how long he can run and stay steady; recovers faster |

Presets: Even, Marksman, Grenadier, Runner, Ironside.

**Personality** — six traits, 0..1:

| trait | drives |
|---|---|
| aggression | closing the distance, and the bayonet charge |
| discipline | firing on the sergeant's volley and keeping the line, rather than acting alone |
| cohesion | how tightly the line stands (0.8 m shoulder to shoulder → ~4 m skirmish order) |
| cover | looking for a wall, fence or tree to fire from (kneeling behind it) |
| patience | holding fire until the enemy is close (75 m → 25 m) |
| nerve | standing under losses; low nerve breaks and runs for the rear |

Presets: Regulars, Skirmishers, Shock, Militia, Veterans, Balanced, Random. Every man gets a
little jitter on both, so twenty of a preset are twenty different men.

## How the line thinks

There is a **sergeant** on each side: simply the steadiest man alive (highest discipline +
nerve). Every half second he publishes what the line is doing — where it stands (`line_z`),
how far apart (`spacing`, from the men's mean cohesion), the mode (`advance` / `hold` /
`charge` / `fallback` / `at_will`) and whether he has just called a **volley**. His "orders"
are a 50/50 blend of his own traits and the line's mean, so one iron sergeant steadies a
company of militia — a little.

Each man then decides, every 0.2 s, how much of that to follow:

- **Formation** — a disciplined, cohesive man stands on his slot in the line; a loose one
  drifts off it by up to a couple of metres. Slots are handed out left-to-right each tick so
  the line never crosses itself.
- **Cover** — a man whose `cover` outweighs his `discipline` leaves the line for the nearest
  wall or fence facing the enemy (within 4–16 m of his slot) and kneels there; a cover-minded
  sergeant halts the whole line on a wall row if it is within range of the enemy.
- **Firing** — a disciplined man waits for the volley (a few are slow on the word); the rest
  fire at will once the enemy is inside their own patience range. Everyone fires at point
  blank. A man with a friend in his line of fire holds if he is disciplined, and may shoot
  him if he is not. A volley frightens the men around the mark far more than the same balls
  one at a time (`volley_pressure`) — that is what volleys are for.
- **Fire and fall back** — a man with low aggression and middling nerve who has just fired
  with the enemy inside 22 m backs off ten metres to reload.
- **The charge** — the sergeant calls it when the enemy is inside his charge range
  (12 + 32 × aggression m), the volley has just gone or most rifles are empty, and the odds
  are not against him. Men with aggression or discipline follow; the rest keep firing. A man
  with blood up charges on his own at 10 m; an empty rifle and an enemy at 7 m is a bayonet
  fight whatever his traits. Charging men keep together (nobody runs 3 m ahead of his mates),
  and a line coming on with the bayonet frightens the men it is coming at.
- **Falling back and breaking** — losses above the sergeant's break point
  (25 % + 50 % × nerve) with courage low send the line back 22 m to rally and reload. Each
  man's own courage is his nerve less losses, wounds, nearby deaths and being outnumbered;
  below 0.1 he runs for the rear, and off the field if nothing steadies him.

- **The sergeant can count** — taking two balls for every one he gives while the enemy sits
  behind walls is a firefight lost: a sergeant with any blood in him closes with the bayonet
  (the charge range opens by 20 m), a shy one finds walls of his own or pulls out of range.
  If nobody has hurt anybody for 25 s, a sergeant with any aggression **presses** to twenty
  paces, walls or no walls.
- **Skirmishers do not stand a charge** — a man with low aggression and discipline, and less
  than iron nerve, fires once and gives ten metres before the bayonet arrives. Loose order
  cannot receive a charge: a man with nobody at his elbow feels three bayonets as thirty.
  A man who has just run cannot hold a rifle steady for four seconds.

The fight ends when one side has nobody left standing in the line. If nobody has hurt anybody
for 45 s (after two minutes), or the clock runs out (seven minutes), **the ground decides**: the
side whose line stands further into the enemy's country holds the field; harm done breaks a
tie. A company that only ever gives ground has lost it.

## The ground

Each of the ten fields is a set of smooth domes (`Field.HILLS`) - a ridge, a knoll, a hollow,
a sunken road. A hill **hides** what is behind it (the line of fire is walked over the
ground; a crest just in front of the target hides all but his head, 0.5), **slows** the man
climbing it (a 1-in-2 slope costs 40 % of his pace; downhill hurries him), and **steadies**
the aim of the man on top (+5 % per metre of height over the target, up to +25 %; firing
uphill costs up to 15 %). A line that cannot see the enemy goes and finds him; nobody holds
a position facing a hill. Ruins are four walls with a doorway in each flank and no roof, so
the fight inside is in plain view.

## The rifle

The shot is flown, not rolled (`ballistics.gd`). The .58 rifle-musket throws a Minié ball at
340 m/s that slows in the air (v = V0·e^(-0.0012·x)) and falls under gravity the whole way.
It is sighted for 100 yards, so the ball rides 8-10 cm above the line of sight out to 50 m,
crosses it at 91 m and drops away beyond (11 cm low at 110 m, a metre low at 200 m) - a miss
keeps falling until it meets a man or the ground, and the tracer draws the arc.

Aim is an angular spread: **a trained marksman groups at 1.8 mrad on the range, a raw recruit
at 7** - the accuracy slider runs between them. At the good end that reproduces the 1860
comparative firings (US Ordnance, in Fuller's *The Rifled Musket*): 94 % at 100 yd, 64 % at
200, 43 % at 300 on a 2 ft wide target, against the recorded 96 %, 64-82 %, 46-58 %. On a
man, on the range: marksman 99 % at 50 m / 84 % at 100 m; even 84 / 50; recruit 49 / 22.

Battle is not the range: every spread is **6.5×** wider (smoke, noise, haste - armies that
shot well at Hythe still fired hundreds of rounds per man hit), and wider again for firing on
the move (×2 walking, ×3.3 running), winded (×1.6), worn out (×1.3), wounded (×1.25), afraid
(up to ×1.8), on the word of a volley (×1.1); narrower kneeling at a wall (×0.8) and looking
down on the enemy (to ×0.8). Frightened men shoot high. A moving target has to be led, and
the lead is guessed. The ball either meets the silhouette (0.5 m wide, 1.75 m standing, 1.2
kneeling) or it does not; cover between takes a share of what would have hit (a low wall
0.45, a tall piece's edge 0.3, a crest 0.5). A hit in the body or head kills 62 % of the time,
in the legs 20 %; otherwise a wound (−45 HP of 100, slower and shakier). A miss flies on and
hits the first man, either side, whose body is where the ball is. Nobody reloads at the run.

The bayonet: 0.6 × own melee / (0.5 + 0.6 × theirs), ×1.3 with the weight of a charge behind
it, ×1.25 against a man caught reloading; 45 × melee damage per thrust, one every ~0.9 s.

## The camera

Until you zoom by hand the rig keeps the **whole field in frame at whatever angle you
choose** — the distance is solved every frame from the field's corners — so the first thing
you do is pick your vantage, not hunt for the edges. Drag to turn and tilt, wheel or pinch to
zoom; *Fit view* puts the auto-fit back.

## Two modes

**Simulation** — one battle, or *Sim ×10* for the numbers (the status line counts "Sim 3 of 10").

**Campaign** — five rounds along a front of ten fields (Hedgerows, Churchyard, Sunken Road,
Woodland, Open Plain, Walled Farm, Orchard, Village, Crossroads, Ridge). The fight opens on
field 5; each round's winner pushes it one field into the loser's country. A man who stands or runs survives to the next round with his name and his kills (`*n`
after his name is the rounds he has survived); the dead are gone. Rounds 1–4 are filled back to
full strength with recruits; the last round is fought with the remainder only. Between rounds
you may change personalities and types alike - or hand a side to the computer. The computer
fights by **doctrine** (the line, a skirmish screen, a storming party, the old guard, the
swarm…, nine in all, each a personality and a type), scoring each against the traits the
enemy last fielded - not the preset name, so a home-made company is read the same way - the
ground (open or thick with cover), and how that doctrine has fared this campaign; the best is
fielded 60 % of the time, the second and third the rest, so there is never one answer. Most
rounds won takes
the campaign (kills break a tie). If a side has nobody left the campaign ends there.

## Running it

- Browser: `?size=N` (1–20, asked on first load), `?red=Shock&blue=Regulars`,
  `?redtype=Marksman&bluetype=Grenadier`.
- Headless batch: `godot --headless --path . -- --sim=20 --red=Regulars --blue=Skirmishers
  --seed=1 --cap=400` prints a battle a line and a `SUMMARY {...}` JSON. `--redtraits=
  aggression:0.1,cover:1` overrides traits on top of a preset; `--field="Open Plain"` picks
  the ground.
- Headless through the HUD (checks the panels build): `-- --ui --batch=3` or `-- --ui --campaign`.
- Build: `./build.sh` (Godot 4.7.2 + web templates) writes `dist/`, boots the pack headless
  to prove it, gzips the big three. `Dockerfile` + `nginx.conf` + `headers.caddy` are the
  same shape as Legion Bots.

## Balance, v0 (4-battle seeds, Even types unless said)

| red | blue | result |
|---|---|---|
| Regulars | Skirmishers | 1–3, skirmishers in cover shoot 20 % to the line's 8 % |
| Shock | Regulars | 2–2, decided in the bayonet fight |
| Regulars | Militia | 4–0, the militia break under volleys (17 of 20 ran) |
| Militia | Veterans | 3–1 — veterans are too patient in the open (range 35 m) |
| Regulars/Marksman | Regulars/Grenadier | 4–0 in a firefight, as it should be |
| Shock/Grenadier | Shock/Runner | 4–0 in a melee, as it should be |

Battles run 35–120 s at 20 a side. The levers are the constants at the top of `soldier.gd`
and the sergeant in `match_manager.gd`.

Known strong build: skirmishers with cover 1, nerve 1, cohesion 0 and the Marksman type, on
a field with walls. Twenty riflemen behind stone who never break beat everything sent at
them head-on except a mirror of themselves; on the Open Plain a storming party takes them
about two times in three. Personality traits carry no budget (the type does), so nerve 1
costs nothing - that is the exploit, and a trait budget is the honest fix if it is wanted.
