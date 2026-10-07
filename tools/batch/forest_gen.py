"""Mixture lab: random eight-company armies drawn from every drill/type, against random
armies, on random fields, both generals fixed on "General advance". forest_an.py fits a random
forest to the results and searches for the best mixtures.

  N=1500 FORT=0 python3 tools/batch/forest_gen.py $G /opt/fr /opt/fjobs   ->   python3 tools/batch/forest_an.py /opt/fr
FORT=1: every battle has a fort, held by a random side.
"""
import json, os, random, shlex, sys
HERE = os.path.dirname(__file__)
UNITS = [l.strip().split("|") for l in open(os.path.join(HERE, "drill_types.txt")) if "|" in l]
UNITS = [f"{d}/{t}" for d, t in UNITS]
FIELDS = ["Hedgerows", "Churchyard", "Sunken Road", "Woodland", "Open Plain", "Walled Farm", "Orchard", "Village",
          "Crossroads", "Ridge", "City", "Suburb", "River Crossing"]
PLAY = "General advance"


def random_army(rng, n=8):
    """1 to 4 different units, a random split of n companies, spread along the line."""
    k = rng.choice([1, 2, 2, 3, 3, 4])
    picks = rng.sample(UNITS, k)
    cuts = sorted(rng.sample(range(1, n), k - 1))
    sizes = [b - a for a, b in zip([0] + cuts, cuts + [n])]
    comp = {u: s for u, s in zip(picks, sizes)}
    line = []
    left = dict(comp)
    while len(line) < n:
        for u in sorted(left, key=lambda u: -left[u]):
            if left[u] > 0:
                line.append(u); left[u] -= 1
    return comp, line


if __name__ == "__main__":
    G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
    N = int(os.environ.get("N", "1500")); FORT = os.environ.get("FORT", "0") == "1"
    rng = random.Random(int(os.environ.get("SEED", "7")) + (1000 if FORT else 0))
    os.makedirs(JOBS, exist_ok=True); os.makedirs(OUT, exist_ok=True)
    meta = []
    for i in range(N):
        rc, rl = random_army(rng); bc, bl = random_army(rng)
        f = rng.choice(FIELDS); fort = rng.randint(0, 1) if FORT else -1
        a = [G, "--headless", "--path", ".", "--", "--sim=1", "--csize=10", f"--seed={rng.randint(1, 10**6)}", "--cap=360",
             f"--field={f}", f"--redmix={','.join(rl)}", f"--bluemix={','.join(bl)}", f"--redplay={PLAY}", f"--blueplay={PLAY}"]
        if FORT:
            a.append(f"--fort={fort}")
        open(f"{JOBS}/{i:04d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(f'{OUT}/{i:04d}.txt')} 2>&1\n")
        meta.append({"i": i, "red": rc, "blue": bc, "field": f, "fort": fort})
    json.dump(meta, open(f"{OUT}/meta.json", "w"))
    print(N)
