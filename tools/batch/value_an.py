"""Read the exchange-rate lab (value_gen.py): win % of 6 Regulars + 2 X at each trial worth,
against the baseline of 8 Regulars, and the worth at which they match (interpolated)."""
import collections, glob, json, os, sys
DIR = sys.argv[1]
W = collections.defaultdict(lambda: [0.0, 0])
for f in glob.glob(DIR + "/*.txt"):
    name, v, p, fld, side = os.path.basename(f)[:-4].split("__")
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    w = json.loads(s[0][8:])["wins"]; side = int(side)
    r = 1.0 if w[side] > w[1 - side] else 0.0 if w[1 - side] > w[side] else 0.5
    W[(name, float(v))][0] += r; W[(name, float(v))][1] += 1
base = W[("base", 1.0)][0] / max(W[("base", 1.0)][1], 1)
print(f"Baseline: 8 Regulars win {base:.0%} of {W[('base', 1.0)][1]} battles against the panel\n")
for unit in ("Cavalry", "Gunner"):
    rows = sorted((v, w / n, n) for (nm, v), (w, n) in W.items() if nm == unit and n)
    print(f"{unit}: 6 Regulars + 2 companies of {unit}, each man worth v men (a company of 10/v men)")
    for v, p, n in rows:
        print(f"  v={v:<4} {p:4.0%}  ({n} battles)")
    # the worth at which the army matches the baseline: rates fall as v rises
    price = None
    for (v0, p0, _), (v1, p1, _) in zip(rows, rows[1:]):
        if (p0 - base) * (p1 - base) <= 0 and p0 != p1:
            price = v0 + (base - p0) * (v1 - v0) / (p1 - p0)
            break
    if price is None and rows:
        price = rows[0][0] if rows[0][1] < base else rows[-1][0]
        print(f"  (no crossing: at the edge of the trials)")
    print(f"  => worth about {price:.2f} men of the line\n")
    print(f"PRICE {unit} {price:.2f}")
