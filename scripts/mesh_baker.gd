class_name MeshBaker
extends RefCounted
## Merges many small coloured meshes into one, so the web renderer (no automatic batching) draws
## one thing instead of dozens: each part's material colour becomes its vertex colour under one
## shared material.

static var _vc_mat: StandardMaterial3D = null
static var _cache := {}


## One material for everything baked: albedo from the vertex colours.
static func vertex_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.roughness = 0.85
	return _vc_mat


## Collect the MeshInstance3D under `root` (root itself included if it is one), skipping the
## nodes in `skip` and their subtrees, as [mesh, transform relative to root, colour].
static func collect(root: Node3D, skip: Array) -> Array:
	var out := []
	_walk(root, Transform3D.IDENTITY, root, skip, out)
	return out


static func _walk(n: Node, xf: Transform3D, root: Node3D, skip: Array, out: Array) -> void:
	if n != root and skip.has(n):
		return
	var t := xf
	if n != root and n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.material_override is StandardMaterial3D:
			out.append([mi.mesh, t, (mi.material_override as StandardMaterial3D).albedo_color])
	for c in n.get_children():
		_walk(c, t, root, skip, out)


## Build one ArrayMesh from collected parts (cached by `key` when one is given).
static func build(parts: Array, key: String = "") -> ArrayMesh:
	if key != "" and _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		var col: Color = p[2]
		var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base := verts.size()
		var basis := xf.basis
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((basis * nm[k]).normalized() if k < nm.size() else Vector3.UP)
			cols.append(col)
		if ix.is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			for k in ix.size():
				idx.append(base + ix[k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	if not verts.is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, vertex_material())
	if key != "":
		_cache[key] = am
	return am


## Replace the meshes under `root` (minus `skip`) with one baked MeshInstance3D child of `root`,
## or with root's own mesh if root is a MeshInstance3D. Frees the originals.
static func bake_into(root: Node3D, skip: Array, key: String = "") -> MeshInstance3D:
	var parts := collect(root, skip)
	if parts.is_empty():
		return null
	var am := build(parts, key)
	var result: MeshInstance3D = null
	var doomed := []
	_meshes_under(root, skip, doomed)
	if root is MeshInstance3D:
		(root as MeshInstance3D).mesh = am
		(root as MeshInstance3D).material_override = null
		result = root as MeshInstance3D
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = am
		root.add_child(mi)
		result = mi
	for d in doomed:
		var dn := d as MeshInstance3D
		if dn.get_child_count() == 0:
			dn.get_parent().remove_child(dn)
			dn.free()
		else:
			# a part that carries other (already counted) children: keep the node, drop its look
			dn.mesh = null
	return result


## The MeshInstance3D below `n` (not `n` itself), children before parents, each once.
static func _meshes_under(n: Node, skip: Array, out: Array) -> void:
	for c in n.get_children():
		if skip.has(c):
			continue
		_meshes_under(c, skip, out)
		if c is MeshInstance3D:
			out.append(c)
