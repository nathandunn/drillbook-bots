extends SceneTree
## Starts a battle (City, 4 companies of 10 a side) and counts the meshes that would be drawn.
var main: Node
var frames := 0

func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)

func _count(n: Node, acc: Dictionary) -> void:
	if n is VisualInstance3D and (n as Node3D).is_visible_in_tree():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			acc["mesh"] += 1
		elif n is GPUParticles3D or n is CPUParticles3D:
			acc["particles"] += 1
		elif n is Label3D:
			acc["label"] += 1
	for c in n.get_children():
		_count(c, acc)

func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		main._rebuild_field("City")
	if frames == 8:
		main._start_next()
	if frames == 400:
		var acc := {"mesh": 0, "particles": 0, "label": 0}
		_count(root, acc)
		var men := 0
		for s in main.manager.soldiers:
			if s.alive:
				men += 1
		print("DRAWS visible meshes %d, particle systems %d, 3D labels %d, men alive %d" % [acc["mesh"], acc["particles"], acc["label"], men])
		return true
	return false
