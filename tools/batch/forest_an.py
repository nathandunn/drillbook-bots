"""Fit a random forest to the mixture lab (forest_gen.py) and search for the best mixtures.
Each battle is one row from Red's side and its mirror from Blue's; the target is 1 for a win,
0 for a loss, 0.5 for a draw. A candidate army's strength is its mean predicted result against
the armies seen in the lab, on every field (and, with forts, holding the fort / attacking it).

  python3 tools/batch/forest_an.py /opt/fr   (summary on stdout)
"""
import itertools, json, os, random, sys
import numpy as np
from sklearn.ensemble import RandomForestRegressor
sys.path.insert(0, os.path.dirname(__file__))
from forest_gen import UNITS, FIELDS  # noqa: E402

DIR = sys.argv[1]
meta = json.load(open(f"{DIR}/meta.json"))
U = {u: i for i, u in enumerate(UNITS)}
F = {f: i for i, f in enumerate(FIELDS)}
NU, NF = len(UNITS), len(FIELDS)
FORT = any(m["fort"] >= 0 for m in meta)


def vec(comp):
    v = np.zeros(NU)
    for u, n in comp.items():
        v[U[u]] = n
    return v


def row(me, them, field, fort_rel):
    """fort_rel: 1 I hold the fort, -1 they do, 0 none."""
    f = np.zeros(NF); f[F[field]] = 1
    return np.concatenate([vec(me), vec(them), f, [fort_rel]])


X, y, armies = [], [], []
fought = draws = 0
for m in meta:
    p = f"{DIR}/{m['i']:04d}.txt"
    if not os.path.exists(p):
        continue
    s = [l for l in open(p) if l.startswith("SUMMARY")]
    if not s:
        continue
    w = json.loads(s[0][8:])["wins"]
    r = 1.0 if w[0] > w[1] else 0.0 if w[1] > w[0] else 0.5
    fought += 1; draws += r == 0.5
    fr = 0 if m["fort"] < 0 else (1 if m["fort"] == 0 else -1)
    X.append(row(m["red"], m["blue"], m["field"], fr)); y.append(r)
    X.append(row(m["blue"], m["red"], m["field"], -fr)); y.append(1 - r)
    armies += [m["red"], m["blue"]]
X, y = np.array(X), np.array(y)
rf = RandomForestRegressor(n_estimators=400, min_samples_leaf=3, max_features=0.4, oob_score=True, n_jobs=-1, random_state=1)
rf.fit(X, y)
oob = rf.oob_prediction_
acc = np.mean((oob > 0.5) == (y > 0.5))
print(f"# Mixture lab{' with forts' if FORT else ''}: {fought} battles ({draws} draws), both generals on General advance")
print(f"Random forest: 400 trees on {len(y)} rows (each battle from both sides); out-of-bag: picks the winner {acc:.0%} of the time, R2 {rf.oob_score_:.2f}\n")

# which units matter
imp = rf.feature_importances_
names = [f"own {u}" for u in UNITS] + [f"enemy {u}" for u in UNITS] + [f"field {f}" for f in FIELDS] + ["fort"]
print("## What decides a battle (forest importance, top 12)")
for i in np.argsort(-imp)[:12]:
    print(f"- {names[i]}: {imp[i]:.3f}")

# each unit's worth: predicted result as the share of that unit rises, the rest random
rng = random.Random(3)
opps = [armies[i] for i in rng.sample(range(len(armies)), min(300, len(armies)))]
fort_cases = [1, -1] if FORT else [0]


def strength(comp, k=None, fields=None, forts=None):
    rows = []
    sample = opps if k is None else rng.sample(opps, k)
    for o in sample:
        for f in (fields or [rng.choice(FIELDS)]):
            for fr in (forts or fort_cases):
                rows.append(row(comp, o, f, fr))
    return float(np.mean(rf.predict(np.array(rows))))


print("\n## Pure armies (8 companies of one unit), predicted win % against the lab's armies")
pure = sorted(((strength({u: 8}, k=150), u) for u in UNITS), reverse=True)
for s, u in pure:
    print(f"- {u}: {s:.0%}")

# search: every army of 1-3 units in steps of 2 companies (plus the pure ones), screened then refined
cands = [{u: 8} for u in UNITS]
for a, b in itertools.combinations(UNITS, 2):
    for n in (2, 4, 6):
        cands.append({a: n, b: 8 - n})
for a, b, c in itertools.combinations(UNITS, 3):
    for na, nb in ((2, 2), (2, 4), (4, 2)):
        cands.append({a: na, b: nb, c: 8 - na - nb})
screen = sorted(((strength(c, k=40), i) for i, c in enumerate(cands)), reverse=True)[:40]
final = sorted(((strength(cands[i], k=300), i) for _, i in screen), reverse=True)


def label(c):
    return " + ".join(f"{n} {u}" for u, n in sorted(c.items(), key=lambda kv: -kv[1]))


print(f"\n## Best mixtures (searched {len(cands)} armies of 1-3 units; top 10 after refining)")
for s, i in final[:10]:
    print(f"- {s:.0%}  {label(cands[i])}")
best = cands[final[0][1]]

print("\n## Best mixture by field (from the 40 finalists)")
for f in FIELDS:
    sc = sorted(((strength(cands[i], k=150, fields=[f]), i) for _, i in final), reverse=True)
    print(f"- {f}: {label(cands[sc[0][1]])} ({sc[0][0]:.0%})")

if FORT:
    for fr, what in ((1, "holding the fort"), (-1, "attacking the fort")):
        sc = sorted(((strength(cands[i], k=200, forts=[fr]), i) for _, i in screen), reverse=True)
        print(f"\n## Best {what} (from the 40 finalists)")
        for s, i in sc[:5]:
            print(f"- {s:.0%}  {label(cands[i])}")

print("\n## Each unit as a share of the best army (swap 2 of its companies for 2 of this unit)")
base = strength(best, k=300)
main = max(best, key=best.get)
for u in UNITS:
    c = dict(best); c[main] -= 2
    if c[main] == 0:
        del c[main]
    c[u] = c.get(u, 0) + 2
    print(f"- +2 {u}: {strength(c, k=300) - base:+.0%}")
