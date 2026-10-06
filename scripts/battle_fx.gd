class_name BattleFx
extends Node3D
## What a battle sounds and looks like up close: the shots and the volleys - and the blood: a spray where the ball goes in, a drip behind a
## wounded man, a pool under the dead. Not built at all in a headless run.
##
## Cheap on purpose (a phone runs this): every splash of blood on the ground is one instance of
## a single MultiMesh (one draw call for all of them), every flying drop another, and sounds
## come from a small pool of players, rate-limited so a volley of forty is one volley sound and
## a few cracks, not forty voices.

const SOUND_DIR := "res://audio/"
## Recorded sound (Freesound, CC0 - see CREDITS.md), sliced into short pieces.
const SETS := {
	"shot": ["musket_1", "musket_2", "musket_3", "musket_4"],
	"volley": ["musket_bed"],
	"die": ["die_1", "die_2", "die_3", "die_4", "die_5", "die_6"],
	"bugle": ["bugle_1", "bugle_2"],
	"charge": ["charge_1", "charge_2"],
	"stab": ["stab_1"],
}
const LOOPS := ["drum_loop", "talk_loop"]
const VOICES := 20            # sounds at once
const DRUM_DB := -4.0
const TALK_DB := -16.0
const SPLATS := 700           # blood on the ground, oldest overwritten first
const DROPS := 240            # drops in the air

var muted := false
var muted_sim := false        # quiet while a battle is simulated
var gore := true

var _streams := {}            # set -> [AudioStream]
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
var _budget := 0.0            # sounds allowed this instant (refills in real time)
var _shot_budget := 0.0
var _die_budget := 0.0
var _charge_quiet := 0.0      # real seconds until another battle cry may sound
var _bugle_quiet := 0.0
var _bugle: AudioStreamPlayer  # the general's bugle is heard everywhere, not placed on the field
var _loop_players := []       # [side] -> {"drum": player, "talk": player}
var _loop_want := [{"drum": false, "talk": false}, {"drum": false, "talk": false}]

var _splat_mm: MultiMesh
var _splat_n := 0
var _splat_grow := []         # [index, pos, basis, from, to, t, dur]
var _drop_mm: MultiMesh
var _drops := []              # [pos, vel, life]
var field: Field


func _ready() -> void:
	for s in SETS:
		var arr := []
		for nm in SETS[s]:
			var path := "%s%s.ogg" % [SOUND_DIR, nm]
			if ResourceLoader.exists(path):
				arr.append(load(path))
		_streams[s] = arr
	# every sound is placed in the world and heard from the camera, so the closer you zoom in the louder it is
	for i in VOICES:
		_players.append(_new_player())
	_bugle = AudioStreamPlayer.new()
	_bugle.volume_db = -7.0
	add_child(_bugle)
	for t in 2:
		var d := {}
		for nm in LOOPS:
			var path := "%s%s.ogg" % [SOUND_DIR, nm]
			var p := _new_player()
			if ResourceLoader.exists(path):
				var st: AudioStreamOggVorbis = load(path)
				st.loop = true
				p.stream = st
			p.volume_db = -60.0
			d[nm.get_slice("_", 0)] = p
		_loop_players.append(d)
	# blood on the ground: a flat dark-red disc, scaled and turned per splash
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.01
	disc.radial_segments = 10
	disc.rings = 1
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(1, 1, 1)
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 0.35
	gm.metallic_specular = 0.6
	disc.material = gm
	_splat_mm = MultiMesh.new()
	_splat_mm.transform_format = MultiMesh.TRANSFORM_3D
	_splat_mm.use_colors = true
	_splat_mm.mesh = disc
	_splat_mm.instance_count = SPLATS
	_splat_mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _splat_mm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	# drops in the air: tiny red boxes
	var cube := BoxMesh.new()
	cube.size = Vector3(0.1, 0.1, 0.1)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.55, 0.02, 0.02)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = dm
	_drop_mm = MultiMesh.new()
	_drop_mm.transform_format = MultiMesh.TRANSFORM_3D
	_drop_mm.mesh = cube
	_drop_mm.instance_count = DROPS
	_drop_mm.visible_instance_count = 0
	_build_smoke()
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = _drop_mm
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dmi)


func _new_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = 18.0
	p.max_distance = 420.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.panning_strength = 0.8
	p.bus = "Master"
	add_child(p)
	return p


## Told every frame by the battle: where a side is, whether it is marching up (the drums), and whether the
## enemy is still far off (talk in the ranks).
func side_state(t: int, centre: Vector3, marching: bool, quiet: bool) -> void:
	if t >= _loop_players.size():
		return
	for k in _loop_players[t]:
		(_loop_players[t][k] as AudioStreamPlayer3D).global_position = centre + Vector3(0, 1.5, 0)
	_loop_want[t]["drum"] = marching
	_loop_want[t]["talk"] = quiet


func _tick_loops(real: float) -> void:
	var silent := muted or muted_sim
	for t in _loop_players.size():
		for k in _loop_players[t]:
			var p: AudioStreamPlayer3D = _loop_players[t][k]
			if p.stream == null:
				continue
			var on: bool = (not silent) and bool(_loop_want[t][k])
			var top := DRUM_DB if k == "drum" else TALK_DB
			var target := top if on else -60.0
			# fade in or out over about half a second
			p.volume_db = move_toward(p.volume_db, target, real * 90.0)
			if on and not p.playing:
				p.play(randf() * 5.0)
			elif not on and p.playing and p.volume_db <= -59.0:
				p.stop()


## A new battle: the ground is clean again.
func clear() -> void:
	_splat_n = 0
	_splat_grow.clear()
	_splat_mm.visible_instance_count = 0
	_drops.clear()
	_drop_mm.visible_instance_count = 0
	_smoke_mm.visible_instance_count = 0
	_smoke_rev = -1
	for p in _players:
		p.stop()
	for t in _loop_players.size():
		_loop_want[t] = {"drum": false, "talk": false}
		for k in _loop_players[t]:
			(_loop_players[t][k] as AudioStreamPlayer3D).stop()
			(_loop_players[t][k] as AudioStreamPlayer3D).volume_db = -60.0


func _process(delta: float) -> void:
	_draw_smoke()
	# sounds run on real time, whatever the battle speed
	var real := delta / maxf(Engine.time_scale, 0.001)
	_budget = minf(_budget + real * 10.0, 4.0)
	_shot_budget = minf(_shot_budget + real * 7.0, 3.0)
	_die_budget = minf(_die_budget + real * 6.0, 2.0)
	_charge_quiet = maxf(_charge_quiet - real, 0.0)
	_bugle_quiet = maxf(_bugle_quiet - real, 0.0)
	_tick_loops(real)
	# drops fly and fall; where one lands it leaves a spot
	var g := 9.8
	var i := 0
	while i < _drops.size():
		var d: Array = _drops[i]
		d[1] = (d[1] as Vector3) + Vector3(0, -g * delta, 0)
		d[0] = (d[0] as Vector3) + (d[1] as Vector3) * delta
		d[2] = float(d[2]) - delta
		var p: Vector3 = d[0]
		var ground := field.height_at(p.x, p.z) if field != null else 0.0
		if p.y <= ground or float(d[2]) <= 0.0:
			if p.y <= ground + 0.1:
				_splat(Vector3(p.x, ground, p.z), randf_range(0.12, 0.25), 0.0)
			_drops.remove_at(i)
			continue
		i += 1
	var n := mini(_drops.size(), DROPS)
	for k in n:
		_drop_mm.set_instance_transform(k, Transform3D(Basis(), _drops[k][0]))
	_drop_mm.visible_instance_count = n
	# pools spreading under the dead
	i = 0
	while i < _splat_grow.size():
		var s: Array = _splat_grow[i]
		s[5] = float(s[5]) + delta
		var f := clampf(float(s[5]) / float(s[6]), 0.0, 1.0)
		var r := lerpf(float(s[3]), float(s[4]), 1.0 - pow(1.0 - f, 2.0))
		var b: Basis = s[2]
		_splat_mm.set_instance_transform(int(s[0]), Transform3D(b.scaled(Vector3(r, 1.0, r * 0.8)), s[1]))
		if f >= 1.0:
			_splat_grow.remove_at(i)
			continue
		i += 1


# ---------------------------------------------------------------- sound

func _play(set_name: String, pos: Vector3, vol_db: float = 0.0, pitch_spread: float = 0.08, cost: float = 1.0) -> void:
	if muted or muted_sim or _budget < cost:
		return
	var arr: Array = _streams.get(set_name, [])
	if arr.is_empty():
		return
	_budget -= cost
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = arr[randi() % arr.size()]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	p.play()


func shot(pos: Vector3) -> void:
	if _shot_budget < 1.0:
		return   # in a volley the volley sound speaks for most of them
	_shot_budget -= 1.0
	_play("shot", pos + Vector3(0, 1.5, 0), -2.0, 0.1, 0.5)


func volley(pos: Vector3) -> void:
	_shot_budget = 0.0
	_play("volley", pos + Vector3(0, 1.5, 0), 2.0, 0.05, 0.5)


## The general's order: a short bugle call (not more than one every 3 seconds).
func bugle() -> void:
	if muted or muted_sim or _bugle_quiet > 0.0:
		return
	var arr: Array = _streams.get("bugle", [])
	if arr.is_empty():
		return
	_bugle_quiet = 3.0
	_bugle.stream = arr[randi() % arr.size()]
	_bugle.pitch_scale = randf_range(0.97, 1.03)
	_bugle.play()


## The battle cry, once per charge order (and not again for a few seconds, whoever charges).
func charge(pos: Vector3) -> void:
	if _charge_quiet > 0.0:
		return
	_charge_quiet = 5.0
	_play("charge", pos + Vector3(0, 1.5, 0), 0.0, 0.06, 0.5)


## A man struck down (or only wounded, more quietly); steel going in when it was a bayonet or a blade.
func wound_sound(at: Vector3, killed: bool, melee: bool) -> void:
	if melee:
		_play("stab", at, 0.0 if killed else -5.0, 0.12, 0.3)
	if _die_budget >= 1.0 and (killed or randf() < 0.35):
		_die_budget -= 1.0
		_play("die", at, -1.0 if killed else -8.0, 0.1, 0.3)


func sergeant(_pos: Vector3) -> void:
	pass


func clash(_pos: Vector3) -> void:
	pass


func rout(_pos: Vector3) -> void:
	pass


# ---------------------------------------------------------------- blood

## A man hit at `at`, the blow coming along `dir`: blood sprays out of the far side.
func hit(at: Vector3, dir: Vector3, killed: bool, melee: bool = false) -> void:
	wound_sound(at, killed, melee)
	if gore:
		var d := dir
		d.y = 0.0
		d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		var n := 12 if killed else 8
		for k in n:
			if _drops.size() >= DROPS:
				break
			var v := d * randf_range(1.5, 3.5) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.2), randf_range(-1, 1))
			_drops.append([at, v, 1.5])
		# the first splash where he stands
		var g := field.height_at(at.x, at.z) if field != null else 0.0
		_splat(Vector3(at.x, g, at.z) + d * 0.6, randf_range(0.45, 0.75), 0.0)
	pass


## A wounded man bleeds as he goes: a drop on the ground behind him.
func drip(pos: Vector3) -> void:
	if not gore:
		return
	var g := field.height_at(pos.x, pos.z) if field != null else 0.0
	_splat(Vector3(pos.x + randf_range(-0.2, 0.2), g, pos.z + randf_range(-0.2, 0.2)), randf_range(0.15, 0.28), 0.0)


## Under a man who has fallen: a pool that spreads over a few seconds.
func pool(pos: Vector3) -> void:
	if not gore:
		return
	var g := field.height_at(pos.x, pos.z) if field != null else 0.0
	_splat(Vector3(pos.x, g, pos.z), randf_range(1.6, 2.4), randf_range(4.0, 7.0))


func _splat(pos: Vector3, radius: float, grow_time: float) -> void:
	var idx := _splat_n % SPLATS
	_splat_n += 1
	_splat_mm.visible_instance_count = mini(_splat_n, SPLATS)
	var b := Basis(Vector3.UP, randf() * TAU)
	var p := pos + Vector3(0, 0.02 + 0.0004 * float(idx % 25), 0)   # stacked a hair apart: no flicker
	var shade := randf_range(0.28, 0.5)
	_splat_mm.set_instance_color(idx, Color(shade, 0.015, 0.02))
	if grow_time > 0.0:
		_splat_mm.set_instance_transform(idx, Transform3D(b.scaled(Vector3(0.05, 1, 0.05)), p))
		_splat_grow.append([idx, p, b, 0.05, radius, 0.0, grow_time])
	else:
		_splat_mm.set_instance_transform(idx, Transform3D(b.scaled(Vector3(radius, 1, radius * randf_range(0.6, 1.0))), p))


# ---------------------------------------------------------------- the smoke, drawn

const SMOKE_MAX := 1600
var _smoke_mm: MultiMesh
var _smoke_rev := -1


func _build_smoke() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 6.0)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = gr
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = m
	_smoke_mm = MultiMesh.new()
	_smoke_mm.transform_format = MultiMesh.TRANSFORM_3D
	_smoke_mm.use_colors = true
	_smoke_mm.mesh = q
	_smoke_mm.instance_count = SMOKE_MAX
	_smoke_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _smoke_mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _draw_smoke() -> void:
	if field == null or field.smoke.is_empty() or field.smoke_rev == _smoke_rev:
		return
	_smoke_rev = field.smoke_rev
	var sz := field.smoke_size()
	var n := 0
	for j in sz.y:
		for i in sz.x:
			var v: float = field.smoke[j * sz.x + i]
			if v < 0.1:
				continue
			if n >= SMOKE_MAX:
				break
			var c := field.smoke_cell_centre(i, j)
			var g := field.height_at(clampf(c.x, -Field.HALF_X, Field.HALF_X), clampf(c.y, -Field.HALF_Z, Field.HALF_Z))
			var s := 0.8 + minf(v, 6.0) * 0.12
			_smoke_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(c.x, g + 2.4, c.y)))
			_smoke_mm.set_instance_color(n, Color(0.94, 0.94, 0.91, 0.8 * (1.0 - exp(-0.35 * v))))
			n += 1
	_smoke_mm.visible_instance_count = n
