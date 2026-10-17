from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
p = str(ROOT / "scripts" / "ui" / "battle_fx.gd")
with open(p, encoding="utf-8") as f:
    lines = f.read().splitlines(True)
# find second 'var vs := Vector2(390, 820)' and 'static func _edge_rect'
vs_idx = []
edge_idx = None
for i, line in enumerate(lines):
    if "var vs := Vector2(390, 820)" in line:
        vs_idx.append(i)
    if line.startswith("static func _edge_rect"):
        edge_idx = i
print("vs", vs_idx, "edge", edge_idx)
if len(vs_idx) >= 2 and edge_idx and edge_idx > vs_idx[1]:
    cut = vs_idx[1]
    out = lines[:cut] + lines[edge_idx:]
    with open(p, "w", encoding="utf-8") as f:
        f.write("".join(out))
    print("removed", edge_idx - cut, "lines; now", len(out))
else:
    print("skip")
