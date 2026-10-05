"""Read /opt/wall: per challenger, wins against the Fabian wall overall and field by field."""
import json, glob, os, sys, collections
D = sys.argv[1] if len(sys.argv) > 1 else "/opt/wall"
W = collections.defaultdict(lambda: [0, 0, 0, 0, 0])   # (name, field) -> [chal wins, wall wins, draws, chal kills, wall kills]
for f in glob.glob(D + "/*.txt"):
    name, field, side = os.path.basename(f)[:-4].split("__")
    side = int(side)
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    j = json.loads(s[0][8:])
    ch = 1 - side if False else (1 if side == 0 else 0)   # side 0: wall is red, challenger blue
    for b in j["battles"]:
        w = b["winner"]
        k = W[(name, field)]
        if w == ch: k[0] += 1
        elif w == 1 - ch: k[1] += 1
        else: k[2] += 1
    kills = j.get("kills", [[0, 0], [0, 0]])
    W[(name, field)][3] += sum(kills[ch])
    W[(name, field)][4] += sum(kills[1 - ch])
names = sorted({n for n, _ in W})
fields = sorted({f for _, f in W})
rows = []
for n in names:
    t = [0, 0, 0, 0, 0]
    for f in fields:
        for i in range(5):
            t[i] += W[(n, f)][i]
    rows.append((t[0] / max(t[0] + t[1] + t[2], 1), n, t))
rows.sort(reverse=True)
print("challenger            won-lost-drawn vs the wall   K/D")
for p, n, t in rows:
    print(f"{n.replace('_', ' '):20s} {t[0]:3d}-{t[1]:3d}-{t[2]:2d}  {100 * p:3.0f}%   {t[3] / max(t[4], 1):.2f}")
print("\nfield by field (challenger wins of 4):")
print(" " * 20 + " ".join(f[:6].rjust(6) for f in fields))
for p, n, t in rows:
    print(n.replace('_', ' ')[:20].ljust(20) + " ".join(str(W[(n, f)][0]).rjust(6) for f in fields))
