# Batch tools

Run on a big Linux box (an EC2 c7i.8xlarge does 500 battles in ~15 min) from the repo root,
with Godot 4.4.1 at $G, after `$G --headless --path . --import`:

- Round-robin of every drill (each side all companies on one drill, the drill's own type),
  both fields, both sides, `--sim=2` per job:
  `cp tools/batch/drill_types.txt . && python3 tools/batch/rr_gen.py $G /opt/rr /opt/jobs`
  then `ls /opt/jobs/*.sh | xargs -P 30 -n 1 bash`; summary: copy `drill_types.txt` to /opt
  and `python3 tools/batch/rr_an.py` (reads /opt/rr; wins, kills, deaths, K/D).
- Mixed battalions (`mixes.json`, drill/type/slot per company) against every drill:
  `python3 tools/batch/mix_gen.py $G /opt/mx /opt/mjobs`, run as above, then `mix_an.py`
  (reads /opt/mx, /opt/mixes.json, /opt/drill_types.txt).
