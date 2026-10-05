"""Read the mix lab: per candidate army, wins against the panel, K/D, and what each kind of
company in it contributed (share of the army's kills, kills per man it lost)."""
import json, glob, os, sys, collections
D = sys.argv[1] if len(sys.argv) > 1 else "/opt/mix"
W = collections.defaultdict(lambda: [0, 0, 0, 0])            # (cand, opp) -> wins, losses, kills, deaths
ROLE = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0, 0]))   # cand -> drill -> kills, fell, men
for f in glob.glob(D + "/*.txt"):
    c, o, fld, side = os.path.basename(f)[:-4].split("__")
    side = int(side)
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    j = json.loads(s[0][8:])
    w = W[(c, o)]
    w[0] += j["wins"][side]; w[1] += j["wins"][1 - side]
    w[2] += sum(j["kills"][side]); w[3] += sum(j["kills"][1 - side])
    cos = j["companies"][side]
    cst = j["co_stats"][side]
    for k, st in cst.items():
        dr = cos[int(k)]["persona"]
        r = ROLE[c][dr]
        r[0] += st["kills"]; r[1] += st["fell"]; r[2] += st["men"]
cands = sorted({c for c, _ in W}, key=lambda c: -sum(W[(c, o)][0] for o in {o for _, o in W}) / max(1, sum(W[(c, o)][0] + W[(c, o)][1] for o in {o for _, o in W})))
opps = sorted({o for _, o in W})
print("army".ljust(14) + "won-lost   win%   K/D   " + " ".join(o.replace('+', ' ')[:7].rjust(7) for o in opps))
for c in cands:
    t = [sum(W[(c, o)][i] for o in opps) for i in range(4)]
    n = max(t[0] + t[1], 1)
    print(c.replace('+', ' ').ljust(14) + f"{t[0]:3d}-{t[1]:3d}  {100 * t[0] / n:4.0f}%  {t[2] / max(t[3], 1):4.2f}   " + " ".join(f"{W[(c, o)][0]}-{W[(c, o)][1]}".rjust(7) for o in opps))
print("\nwho did the work in the mixed armies (share of the army's kills / kills per man lost):")
for c in cands:
    roles = ROLE[c]
    if len(roles) < 2:
        continue
    tot = sum(r[0] for r in roles.values()) or 1
    print("  " + c.replace('+', ' ').ljust(14) + "  ".join(f"{dr}: {100 * r[0] / tot:.0f}% of kills, {r[0] / max(r[1], 1):.2f} K/D" for dr, r in roles.items()))
