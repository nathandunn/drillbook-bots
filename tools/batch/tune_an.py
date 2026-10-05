import json, glob, os, sys, collections
D = sys.argv[1]
W = collections.defaultdict(lambda: [0, 0, 0, 0])   # (cand, opp) -> wins, losses, kills, deaths
for f in glob.glob(D + "/*.txt"):
    c, o, fld, side = os.path.basename(f)[:-4].split("__")
    side = int(side)
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    j = json.loads(s[0][8:])
    me = side
    w = W[(c, o)]
    w[0] += j["wins"][me]; w[1] += j["wins"][1 - me]
    w[2] += sum(j["kills"][me]); w[3] += sum(j["kills"][1 - me])
cands = sorted({c for c, _ in W}); opps = sorted({o for _, o in W})
print("candidate".ljust(16) + "total      K/D   " + " ".join(o[:9].rjust(9) for o in opps))
for c in cands:
    t = [sum(W[(c, o)][i] for o in opps) for i in range(4)]
    print(c.replace("_", " ")[:16].ljust(16) + f"{t[0]:3d}-{t[1]:3d}  {t[2] / max(t[3], 1):5.2f}   " + " ".join(f"{W[(c, o)][0]}-{W[(c, o)][1]}".rjust(9) for o in opps))
