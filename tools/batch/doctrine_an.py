"""Read the doctrine lab into the computer general's table (JSON on stdout):
  {"templates": {name: {drill: companies}}, "wins": {template: {opp drill: {field: [won, fought]}}}}
and a readable summary on stderr."""
import json, glob, os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
from mixlab_gen import D  # noqa: E402
from doctrine_gen import TEMPLATES  # noqa: E402
DIR = sys.argv[1]
W = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0])))
for f in glob.glob(DIR + "/*.txt"):
    t, d, fld, side = os.path.basename(f)[:-4].split("__")
    side = int(side)
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    j = json.loads(s[0][8:])
    c = W[t.replace("+", " ")][d.replace("_", " ")][fld.replace("_", " ")]
    c[0] += j["wins"][side]; c[1] += j["wins"][side] + j["wins"][1 - side]
tpl = {}
for t in TEMPLATES:
    comp = collections.Counter()
    for tok in t.split():
        comp[D[tok[:2]]] += int(tok[2:])
    tpl[t] = dict(comp)
print(json.dumps({"templates": tpl, "wins": W}, indent=0, sort_keys=True))
# summary: each template's win % per opponent drill (all fields) and per field (all drills)
opps = sorted({d for t in W for d in W[t]})
fields = sorted({f for t in W for d in W[t] for f in W[t][d]})
def pct(cells):
    w = sum(c[0] for c in cells); n = sum(c[1] for c in cells)
    return f"{100 * w / n:3.0f}" if n else "  -"
print("template".ljust(14) + "".join(o[:6].rjust(7) for o in opps) + "   all", file=sys.stderr)
for t in W:
    print(t.ljust(14) + "".join(pct(W[t][o].values()).rjust(7) for o in opps) + pct([c for o in W[t] for c in W[t][o].values()]).rjust(6), file=sys.stderr)
print("\ntemplate".ljust(15) + "".join(f[:6].rjust(7) for f in fields), file=sys.stderr)
for t in W:
    print(t.ljust(14) + "".join(pct([W[t][o][f] for o in W[t] if f in W[t][o]]).rjust(7) for f in fields), file=sys.stderr)
