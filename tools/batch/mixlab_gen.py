"""Which mixtures of companies win? Eight-company armies (10 men each) of chosen mixes against a
fixed panel of opponents, on five fields, from both sides.

  python3 tools/batch/mixlab_gen.py $G /opt/mix /opt/mjobs    ->   python3 tools/batch/mixlab_an.py /opt/mix
"""
import shlex, os, sys
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
D = {"Sn": "Sniper/Marksman", "Fa": "Fabian Screen/Marksman", "An": "Anvil/Marksman", "Ha": "Hammer/Brawler",
     "Sh": "Shock/Grenadier", "Ni": "Ninjas/Shinobi", "Sk": "Skirmishers/Marksman", "Li": "Line/Even",
     "Lb": "Linebreaker/Grenadier"}


def army(spec):
    """'Sn6 Ni2' -> eight companies, spread so the minority is not all on one flank."""
    parts = []
    for tok in spec.split():
        parts += [D[tok[:2]]] * int(tok[2:])
    # interleave: e.g. Sn Sn Sn Ni Sn Sn Sn Ni
    major = [p for p in parts if p == parts[0]]
    minor = [p for p in parts if p != parts[0]]
    out = []
    step = len(parts) / max(len(minor), 1)
    mi = 0
    for i in range(len(parts)):
        if minor and mi < len(minor) and i >= int((mi + 0.5) * step):
            out.append(minor[mi]); mi += 1
        elif major:
            out.append(major.pop())
        else:
            out.append(minor[mi]); mi += 1
    return ",".join(out)


CANDS = ["Sn8", "Fa8", "An8", "Ha8", "Sh8", "Sk8", "Ni8",
         "Sn7 Ni1", "Sn6 Ni2", "Sn4 Ni4", "Fa6 Ni2", "An6 Ni2", "Sk6 Ni2",
         "Sn6 Ha2", "Sn4 Ha4", "Fa6 Ha2", "Sn6 Sh2", "An4 Ha4", "An3 Ha3 Ni2", "Sn4 Ha2 Ni2", "Fa4 Sn4"]
PANEL = ["Sn8", "Fa8", "An8", "Ha8", "Sh8", "Li8", "Lb8", "An4 Ha4"]
FIELDS = ["Open Plain", "Walled Farm", "Woodland", "Village", "City"]
os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
i = 0
for c in CANDS:
    for p in PANEL:
        for fi, f in enumerate(FIELDS):
            for side in (0, 1):
                tag = f"{c.replace(' ', '+')}__{p.replace(' ', '+')}__{f.replace(' ', '_')}__{side}"
                a = [G, "--headless", "--path", ".", "--", "--sim=1", "--csize=10", f"--seed={101 + fi * 7 + side}", "--cap=360", f"--field={f}"]
                a += [f"--redmix={army(c)}", f"--bluemix={army(p)}"] if side == 0 else [f"--redmix={army(p)}", f"--bluemix={army(c)}"]
                open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
                i += 1
print(i)
