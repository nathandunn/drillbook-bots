"""The computer general's table: candidate armies (templates) against an army of each drill, on
every field, from both sides, both generals on their own choice. doctrine_an.py turns the results
into data/ai_table.json, which the computer reads to choose its army and its companies.

  python3 tools/batch/doctrine_gen.py $G /opt/doc /opt/djobs   ->   python3 tools/batch/doctrine_an.py /opt/doc > data/ai_table.json
"""
import shlex, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from mixlab_gen import army  # noqa: E402
TEMPLATES = ["An8", "Ha8", "Sh8", "Fa8", "An4 Ha4", "Ha4 Sn4", "Sh4 Sk4", "An4 Sh4", "An3 Ha3 Sn2", "Ha3 Sh3 Ni2"]
HERE = os.path.dirname(__file__)
DRILLS = [l.strip().split("|") for l in open(os.path.join(HERE, "drill_types.txt")) if "|" in l]
FIELDS = ["Hedgerows", "Churchyard", "Sunken Road", "Woodland", "Open Plain", "Walled Farm", "Orchard", "Village",
          "Crossroads", "Ridge", "City", "Suburb", "River Crossing"]
if __name__ == "__main__":
    G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    i = 0
    for t in TEMPLATES:
        for d, ty in DRILLS:
            opp = ",".join([f"{d}/{ty}"] * 8)
            for fi, f in enumerate(FIELDS):
                for side in (0, 1):
                    tag = f"{t.replace(' ', '+')}__{d.replace(' ', '_')}__{f.replace(' ', '_')}__{side}"
                    a = [G, "--headless", "--path", ".", "--", "--sim=1", "--csize=10", f"--seed={201 + fi * 7 + side}", "--cap=360", f"--field={f}"]
                    a += [f"--redmix={army(t)}", f"--bluemix={opp}"] if side == 0 else [f"--redmix={opp}", f"--bluemix={army(t)}"]
                    open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
                    i += 1
    print(i)
