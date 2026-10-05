"""Try drill variants against a fixed set of opponents, all fields, both sides.
  python3 tools/batch/tune_gen.py $G /opt/tune /opt/tjobs "Ninjas|Scout" "Ninjas2|Scout" ...
  python3 tools/batch/tune_an.py /opt/tune
"""
import shlex, os, sys
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
CANDS = [c.split("|") for c in sys.argv[4:]]
OPP = [("Regulars", "Even"), ("Line", "Even"), ("Hammer", "Brawler"), ("Fabian Screen", "Marksman"),
       ("Thin Red Line", "Marksman"), ("Shock", "Grenadier"), ("Anvil", "Marksman"), ("Sniper", "Marksman")]
FIELDS = ["Open Plain", "Walled Farm", "Woodland", "Village", "Hedgerows"]
os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
i = 0
for cn, ct in CANDS:
    for on, ot in OPP:
        for f in FIELDS:
            for side in (0, 1):
                tag = f"{cn}-{ct}__{on}__{f}__{side}".replace(" ", "_")
                a = [G, "--headless", "--path", ".", "--", "--sim=2", f"--seed={11 + i % 7}", "--cap=300", f"--field={f}"]
                a += [f"--red={cn}", f"--redtype={ct}", f"--blue={on}", f"--bluetype={ot}"] if side == 0 else [f"--blue={cn}", f"--bluetype={ct}", f"--red={on}", f"--redtype={ot}"]
                open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
                i += 1
print(i)
