extends SceneTree
## Compares the spatial index against a brute-force pass over every piece, on every field.

func _brute_walk(f: Field, a: Vector2, b: Vector2) -> bool:
	for pc in f.pieces:
		if Field._segment_hits_rect(a, b, (pc["rect"] as Rect2).grow(0.35)):
			return false
	return true

func _brute_blocked(f: Field, p: Vector2, pad: float) -> bool:
	for pc in f.pieces:
		if (pc["rect"] as Rect2).grow(pad).has_point(p):
			return true
	return false

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad := 0
	var total := 0
	for name in Field.ALL_FIELDS:
		var f := Field.new()
		f.layout_name = name
		f._ready()
		var hb := 0.0
		for k in 3000:
			var a := Vector2(rng.randf_range(-56, 56), rng.randf_range(-100, 100))
			var b := a + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
			total += 2
			if f.walk_clear(a, b) != _brute_walk(f, a, b):
				bad += 1
				if bad < 4:
					print("walk mismatch ", name, " ", a, " ", b, " idx=", f.walk_clear(a, b), " seg pieces=", f._pieces_on_segment(a, b).size())
			if f.blocked(Vector3(a.x, 0, a.y), 0.5) != _brute_blocked(f, a, 0.5):
				bad += 1000000
			hb = maxf(hb, absf(f.height_at(a.x, a.y) - f._height_exact(a.x, a.y)))
		print("%-15s pieces %3d  max height error %.3f m" % [name, f.pieces.size(), hb])
		f.free()
	print("INDEX CHECK: %d mismatches in %d queries" % [bad, total])
	quit()
