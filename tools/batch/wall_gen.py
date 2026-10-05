"""Can anything beat the Fabian wall? Twelve companies of twenty, every one Fabian Screen /
Marksman, against twelve-company challengers, on every field, from both sides.

  python3 tools/batch/wall_gen.py $G /opt/wall /opt/wjobs   ->  ls /opt/wjobs/*.sh | xargs -P 56 -n 1 bash
  python3 tools/batch/wall_an.py /opt/wall
"""
import shlex, os, sys
G, OUT, JOBS = sys.argv[1], sys.argv[2], sys.argv[3]
FIELDS = ["Open Plain", "Walled Farm", "Hedgerows", "Churchyard", "Sunken Road", "Woodland", "Orchard",
          "Village", "Crossroads", "Ridge", "City", "Suburb", "River Crossing"]


def rep(*parts):
    """Twelve companies cycling through the given Drill/Type parts."""
    return ",".join(parts[i % len(parts)] for i in range(12))


WALL = rep("Fabian Screen/Marksman")
CHALLENGERS = {
    "Hammer": rep("Hammer/Brawler"),
    "Anvil+Hammer": rep("Anvil/Marksman", "Hammer/Brawler"),
    "Ninjas": rep("Ninjas/Runner"),
    "Linebreaker": rep("Linebreaker/Grenadier"),
    "Sniper": rep("Sniper/Marksman"),
    "Skirmishers": rep("Skirmishers/Marksman"),
    "Veterans": rep("Veterans/Ironside"),
    "Line": rep("Line/Even"),
    "Thin Red Line": rep("Thin Red Line/Marksman"),
    "Shock": rep("Shock/Grenadier"),
    "Mixed bag": rep("Anvil/Marksman", "Hammer/Brawler", "Ninjas/Runner", "Sniper/Marksman"),
    "Fabian+Hammer": rep("Fabian Screen/Marksman", "Fabian Screen/Marksman", "Hammer/Brawler"),
    "Fabian mirror": WALL,
}
os.makedirs(JOBS, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
i = 0
for name, mix in CHALLENGERS.items():
    for fi, f in enumerate(FIELDS):
        for side in (0, 1):
            tag = f"{name}__{f}__{side}".replace(" ", "_").replace("+", "P")
            a = [G, "--headless", "--path", ".", "--", "--sim=2", "--csize=20", f"--seed={31 + fi}", "--cap=480", f"--field={f}"]
            a += [f"--redmix={WALL}", f"--bluemix={mix}"] if side == 0 else [f"--redmix={mix}", f"--bluemix={WALL}"]
            open(f"{JOBS}/{i:03d}.sh", "w").write(" ".join(shlex.quote(x) for x in a) + f" > {shlex.quote(OUT + '/' + tag + '.txt')} 2>&1\n")
            i += 1
print(i)
