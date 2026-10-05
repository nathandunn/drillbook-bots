"""Which play suits which army? Each candidate army fights the panel under each play; the panel
is always left to the general's choice. Three fields, both sides.

  python3 tools/batch/playlab_gen.py $G /opt/play /opt/pjobs    ->   python3 tools/batch/playlab_an.py /opt/play
"""
import shlex, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from mixlab_gen import army  # noqa: E402  (the same army spec: 'Sn6 Ni2', 'Ni2h' held back)
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
CANDS = ["An8", "Ha8", "Sh8", "Fa8", "Sn8", "An4 Ha4", "Ha4 Sn4", "Sh4 Sk4"]
PLAYS = ["General's choice", "General advance", "Hammer and anvil", "Hold and receive", "Feint and draw",
         "All-out charge", "Drill book"]
PANEL = ["Sn8", "Fa8", "An8", "Ha8", "Sh8", "Li8", "Lb8", "An4 Ha4"]
FIELDS = ["Open Plain", "Woodland", "Village"]
os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
i = 0
for c in CANDS:
    for pl in PLAYS:
        for p in PANEL:
            for fi, f in enumerate(FIELDS):
                for side in (0, 1):
                    tag = f"{c.replace(' ', '+')}__{pl.replace(' ', '_').replace(chr(39), '')}__{p.replace(' ', '+')}__{f.replace(' ', '_')}__{side}"
                    a = [G, "--headless", "--path", ".", "--", "--sim=1", "--csize=10", f"--seed={101 + fi * 7 + side}", "--cap=360", f"--field={f}"]
                    if side == 0:
                        a += [f"--redmix={army(c)}", f"--bluemix={army(p)}", f"--redplay={pl}"]
                    else:
                        a += [f"--redmix={army(p)}", f"--bluemix={army(c)}", f"--blueplay={pl}"]
                    open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
                    i += 1
print(i)
