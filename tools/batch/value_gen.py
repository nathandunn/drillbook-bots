"""Exchange-rate lab: what is a rider, or a gunner, worth in men of the line? 6 Regulars + 2
companies of X (sized at a trial worth v: a company of X has 10/v men) against a panel of
pure armies, on six fields, both sides; and 8 Regulars against the same panel as the baseline.
The worth at which X's army does as well as the baseline is X's price.

  python3 tools/batch/value_gen.py $G /opt/val /opt/vjobs   ->   python3 tools/batch/value_an.py /opt/val
"""
import os, shlex, sys
UNITS = {"Cavalry": "Cavalry/Cavalry", "Gunner": "Artillery/Gunner"}
VALUES = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0]
PANEL = ["Regulars/Even", "Line/Even", "Anvil/Marksman", "Shock/Grenadier", "Hammer/Brawler", "Fabian Screen/Marksman"]
FIELDS = ["Open Plain", "Village", "Woodland", "Ridge", "Walled Farm", "Hedgerows"]
RE = "Regulars/Even"


def army(x):
    return ",".join([RE, RE, RE, x, RE, RE, x, RE]) if x else ",".join([RE] * 8)


if __name__ == "__main__":
    G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    cases = [("base", None, 1.0)] + [(k, u, v) for k, u in UNITS.items() for v in VALUES]
    i = 0
    for name, unit, v in cases:
        for p in PANEL:
            for fi, f in enumerate(FIELDS):
                for side in (0, 1):
                    tag = f"{name}__{v}__{p.split('/')[0].replace(' ', '_')}__{f.replace(' ', '_')}__{side}"
                    me, them = army(unit), ",".join([p] * 8)
                    a = [G, "--headless", "--path", ".", "--", "--sim=1", "--csize=10", f"--seed={301 + fi * 7 + side}", "--cap=360",
                         f"--field={f}", f"--value=Cavalry:{v},Gunner:{v}"]
                    a += [f"--redmix={me}", f"--bluemix={them}"] if side == 0 else [f"--redmix={them}", f"--bluemix={me}"]
                    open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
                    i += 1
    print(i)
