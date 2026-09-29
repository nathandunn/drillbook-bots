class_name CameraRig
extends Node3D
## Orbit camera. Drag (mouse or one finger) to turn and tilt, wheel or pinch to zoom.
## Until the viewer zooms by hand the rig keeps the *whole field* in frame at whatever angle
## they choose - the distance is solved each frame from the field's corners - so the first
## thing anyone does is pick their vantage, not hunt for the edges. "Fit" puts that back.

const FIELD_CORNERS := [
	Vector3(-Field.HALF_X - 1.0, 0, -Field.HALF_Z - 1.0), Vector3(Field.HALF_X + 1.0, 0, -Field.HALF_Z - 1.0),
	Vector3(-Field.HALF_X - 1.0, 0, Field.HALF_Z + 1.0), Vector3(Field.HALF_X + 1.0, 0, Field.HALF_Z + 1.0),
	Vector3(-Field.HALF_X, 6.0, -Field.HALF_Z), Vector3(Field.HALF_X, 6.0, Field.HALF_Z),
	Vector3(Field.HALF_X, 6.0, -Field.HALF_Z), Vector3(-Field.HALF_X, 6.0, Field.HALF_Z),
]

var yaw := 0.35
var pitch := 0.95
var dist := 120.0
var fit_all := true
var _cam: Camera3D
var _dragging := false
var _touches := {}
var _pinch_d := 0.0
var _focus := Vector3(0, 0, 0)
## Inset the top of the frame so the HUD's control row never sits on the far edge of the field.
var top_inset := 0.10


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.keep_aspect = Camera3D.KEEP_WIDTH   # a portrait phone still frames the field
	_cam.far = 600.0
	_cam.near = 0.3
	add_child(_cam)
	_apply()


func _process(_delta: float) -> void:
	if fit_all:
		dist = _fit_distance()
	_apply()


func refit() -> void:
	fit_all = true


func _basis() -> Basis:
	var p := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return Basis.looking_at(-p, Vector3.UP)


## The smallest distance along the current view direction that puts every field corner
## inside the frustum, with the HUD inset taken off the top.
func _fit_distance() -> float:
	var vp := get_viewport()
	if vp == null:
		return dist
	var size := vp.get_visible_rect().size
	if size.y <= 0.0:
		return dist
	var aspect := size.x / size.y
	var half_h: float
	var half_v: float
	if _cam.keep_aspect == Camera3D.KEEP_WIDTH:
		half_h = tan(deg_to_rad(_cam.fov) * 0.5)
		half_v = half_h / aspect
	else:
		half_v = tan(deg_to_rad(_cam.fov) * 0.5)
		half_h = half_v * aspect
	var b := _basis()
	var inv := b.inverse()
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var need := 20.0
	for c in FIELD_CORNERS:
		var local: Vector3 = inv * (c - _focus)   # camera-space, before the pull-back along -z
		# camera at focus + dir*d looks down -z; a point's depth is d - local.z... local.z is
		# negative in front. Solve d so that |x| <= half_h * depth and y within the inset frame.
		var x := absf(local.x)
		var y := local.y
		var z := local.z   # depth from the focus plane, negative forward
		# depth at distance d: depth = d + z (z<0 toward the far side)... camera forward is -z:
		# a point at local (x,y,z) seen from a camera at (0,0,d) has depth d - z.
		# |x| <= half_h*(d - z)  ->  d >= x/half_h + z
		need = maxf(need, x / half_h + z)
		# top of frame is inset: y <= half_v*(1 - 2*top_inset)*(d - z)
		var top := half_v * (1.0 - 2.0 * top_inset)
		need = maxf(need, y / top + z)
		need = maxf(need, -y / half_v + z)
	return clampf(need + 2.0, 20.0, 500.0)


func _apply() -> void:
	pitch = clampf(pitch, 0.2, 1.5)
	dist = clampf(dist, 8.0, 500.0)
	var p := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	_cam.position = _focus + p
	_cam.look_at(_focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
			# the field is grabbed and turned: a grab hand while dragging, the move cross otherwise
			Input.set_default_cursor_shape(Input.CURSOR_DRAG if _dragging else Input.CURSOR_MOVE)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			dist *= 0.9
			fit_all = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			dist *= 1.1
			fit_all = false
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch += event.relative.y * 0.006
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts := _touches.values()
			_pinch_d = pts[0].distance_to(pts[1])
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			yaw -= event.relative.x * 0.008
			pitch += event.relative.y * 0.008
		elif _touches.size() == 2:
			var pts := _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch_d > 0.0:
				dist *= _pinch_d / maxf(d, 1.0)
				fit_all = false
			_pinch_d = d
