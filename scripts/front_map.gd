class_name FrontMap
extends Control
## The front after a battle, animated: the fields in a row, Red's country on the left (field 1)
## and Blue's on the right (field N). The fight marker slides from the field just fought to the
## next one, the conquered ground takes the winner's colour as it passes, and each army's
## strength bar drains from what it had before the battle to what it has left.

var fields: Array = []          # field names, field 1 first
var from_no := 1                # the field just fought (1-based)
var to_no := 1                  # where the fight goes next (== from_no on a draw)
var winner := -1                # the battle's winner, -1 drawn
var men_before := [0, 0]
var men_after := [0, 0]
var men_full := [240, 240]
var over := false
var campaign_winner := -1
var forts: Dictionary = {}     # field no -> the side whose fort stands there

const ANIM := 1.8               # seconds
var _t := 0.0

const RED := Color(0.8, 0.22, 0.2)
const BLUE := Color(0.2, 0.35, 0.8)


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play() -> void:
	if fields.is_empty():
		custom_minimum_size = Vector2(0, 46)
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _t < 1.0:
		_t = minf(_t + delta / ANIM, 1.0)
		queue_redraw()


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _draw() -> void:
	var n := fields.size()
	var font := get_theme_default_font()
	var w := size.x
	var pad := 6.0
	if n == 0:
		_draw_bars(font, w, pad, 6.0)   # no front (an epic): the armies only
		return
	var cell := (w - pad * 2.0) / n
	var top := 22.0
	var h := 46.0
	# the marker's position (1-based, fractional) as it moves
	var e := _ease(clampf(_t / 0.75, 0.0, 1.0))
	var mpos := lerpf(float(from_no), float(to_no), e)
	if over and campaign_winner >= 0:
		# the war is won: the marker runs off the loser's end of the line
		var end := float(n) + 0.9 if campaign_winner == 0 else 0.1
		if to_no == from_no:
			mpos = lerpf(float(from_no), end, e)
	draw_string(font, Vector2(pad, 14), "Red's country", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RED.lightened(0.4))
	draw_string(font, Vector2(w - pad - 90, 14), "Blue's country", HORIZONTAL_ALIGNMENT_RIGHT, 90, 12, BLUE.lightened(0.4))
	for i in n:
		var no := i + 1
		var x := pad + i * cell
		var col := Color(0.25, 0.25, 0.25)
		# behind the marker is Red's ground, ahead of it Blue's; the marker's own field is contested
		if float(no) < mpos - 0.5:
			col = RED.darkened(0.25)
		elif float(no) > mpos + 0.5:
			col = BLUE.darkened(0.25)
		else:
			col = Color(0.55, 0.45, 0.15)
		draw_rect(Rect2(x + 1, top, cell - 2, h), col)
		draw_rect(Rect2(x + 1, top, cell - 2, h), Color(0, 0, 0, 0.5), false, 1.0)
		var label := String(fields[i])
		var short := label.substr(0, 4) if cell < 60.0 else label.substr(0, 9)
		draw_string(font, Vector2(x + 3, top + 16), str(no), HORIZONTAL_ALIGNMENT_LEFT, cell - 4, 11, Color(1, 1, 1, 0.7))
		if forts.has(no):
			var fcol: Color = (RED if int(forts[no]) == 0 else BLUE).lightened(0.55)
			draw_string(font, Vector2(x + 3, top + 30), "fort", HORIZONTAL_ALIGNMENT_LEFT, cell - 4, 10, fcol)
		draw_string(font, Vector2(x + 3, top + h - 8), short, HORIZONTAL_ALIGNMENT_LEFT, cell - 4, 10, Color(1, 1, 1, 0.85))
	# the fight marker: crossed swords over the contested field
	var mx := pad + (mpos - 0.5) * cell
	var my := top + h + 12.0
	var mc := Color(0.98, 0.85, 0.3)
	draw_line(Vector2(mx - 8, my - 8), Vector2(mx + 8, my + 8), mc, 3.0)
	draw_line(Vector2(mx + 8, my - 8), Vector2(mx - 8, my + 8), mc, 3.0)
	draw_line(Vector2(mx, top + h), Vector2(mx, my - 9), mc, 1.5)
	_draw_bars(font, w, pad, top + h + 30.0)


## The armies: bars draining from before to after.
func _draw_bars(font: Font, w: float, pad: float, y0: float) -> void:
	var s := _ease(clampf((_t - 0.3) / 0.7, 0.0, 1.0))
	for t in 2:
		var y := y0 + t * 18.0
		var full := maxf(float(men_full[t]), 1.0)
		var now := lerpf(float(men_before[t]), float(men_after[t]), s)
		var bw := w - pad * 2.0 - 120.0
		var c := RED if t == 0 else BLUE
		draw_rect(Rect2(pad + 120.0, y, bw, 12), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(pad + 120.0, y, bw * clampf(float(men_before[t]) / full, 0.0, 1.0), 12), c.darkened(0.55))
		draw_rect(Rect2(pad + 120.0, y, bw * clampf(now / full, 0.0, 1.0), 12), c)
		draw_string(font, Vector2(pad, y + 11), "%s  %d men" % ["Red" if t == 0 else "Blue", int(round(now))], HORIZONTAL_ALIGNMENT_LEFT, 116, 12, c.lightened(0.4))
