"""Read the play lab: win % of each army under each play (against the panel on the general's
choice), and what the general's choice ended up doing."""
import json, glob, os, sys, collections
D = sys.argv[1] if len(sys.argv) > 1 else "/opt/play"
W = collections.defaultdict(lambda: [0, 0, 0, 0])        # (cand, play) -> wins, losses, kills, deaths
ENDS = collections.defaultdict(collections.Counter)       # cand -> play the auto general ended on
for f in glob.glob(D + "/*.txt"):
    c, pl, o, fld, side = os.path.basename(f)[:-4].split("__")
    side = int(side)
    s = [l for l in open(f) if l.startswith("SUMMARY")]
    if not s:
        continue
    j = json.loads(s[0][8:])
    w = W[(c, pl)]
    w[0] += j["wins"][side]; w[1] += j["wins"][1 - side]
    w[2] += sum(j["kills"][side]); w[3] += sum(j["kills"][1 - side])
    if pl == "Generals_choice":
        for b in j["battles"]:
            if b.get("plays"):
                ENDS[c][b["plays"][side]] += 1
cands = sorted({c for c, _ in W})
plays = ["Generals_choice", "General_advance", "Hammer_and_anvil", "Hold_and_receive", "Feint_and_draw", "All-out_charge", "Drill_book"]
print("win % (battles)".ljust(12) + "".join(p.replace("_", " ")[:12].rjust(13) for p in plays))
for c in cands:
    row = c.replace("+", " ").ljust(12)
    for p in plays:
        w = W[(c, p)]
        n = w[0] + w[1]
        row += (f"{100 * w[0] / n:3.0f}% ({n:2d})" if n else "-").rjust(13)
    print(row)
print("\nthe general's choice ended the battle on:")
for c in cands:
    print("  " + c.replace("+", " ").ljust(12) + ", ".join(f"{p} {n}" for p, n in ENDS[c].most_common()))
