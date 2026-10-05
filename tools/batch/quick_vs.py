# One drill against six opponents on four fields, both sides, four times each (192 battles):
#   python3 tools/batch/quick_vs.py "Drill" Type   (paths for the trial machine)
import subprocess, sys, json, itertools, concurrent.futures as cf
G = "/opt/Godot_v4.4.1-stable_linux.x86_64"
REPO = "/opt/drillbook-bots"
drill, dtype = sys.argv[1], sys.argv[2]
OPP = [("Regulars", "Even"), ("Line", "Even"), ("Fabian Screen", "Marksman"), ("Hammer", "Brawler"), ("Thin Red Line", "Marksman"), ("Sniper", "Marksman")]
FIELDS = ["Open Plain", "Walled Farm", "Woodland", "Village"]
jobs = []
for (o, ot), f, side, rep in itertools.product(OPP, FIELDS, (0, 1), range(4)):
    a = [G, "--headless", "--path", REPO, "--", "--sim=1", "--seed=%d" % (7 + len(jobs)), "--cap=300", "--field=" + f]
    a += ([f"--red={drill}", f"--redtype={dtype}", f"--blue={o}", f"--bluetype={ot}"] if side == 0 else [f"--blue={drill}", f"--bluetype={dtype}", f"--red={o}", f"--redtype={ot}"])
    jobs.append((o, f, side, a))
def run(j):
    o, f, side, a = j
    out = subprocess.run(a, capture_output=True, text=True, timeout=600).stdout
    s = [l for l in out.splitlines() if l.startswith("SUMMARY")]
    if not s: return (o, f, None, 0, 0)
    d = json.loads(s[0][8:])
    me = side
    w = d["battles"][0]["winner"]
    return (o, f, 1 if w == me else (0 if w == 1 - me else 0.5), sum(d["kills"][me]), sum(d["kills"][1 - me]))
res = list(cf.ThreadPoolExecutor(60).map(run, jobs))
by = {}
for o, f, w, k, dd in res:
    b = by.setdefault(o, [0, 0, 0, 0])
    if w is not None: b[0] += w; b[1] += 1
    b[2] += k; b[3] += dd
tw = sum(b[0] for b in by.values()); tn = sum(b[1] for b in by.values()); tk = sum(b[2] for b in by.values()); td = sum(b[3] for b in by.values())
print(f"{drill}: {tw:.0f}/{tn} wins, K/D {tk/max(td,1):.2f}  | " + ", ".join(f"{o} {b[0]:.0f}/{b[1]}" for o, b in by.items()))
