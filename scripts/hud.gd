class_name Hud
extends CanvasLayer
## Controls, the company builder and the results, all built in code and sized for a phone.

signal new_match_requested
signal batch_requested(n: int)
signal speed_changed(scale: float)
signal pause_toggled(paused: bool)
signal fit_requested
signal campaign_requested
signal next_round_requested
signal campaign_abandoned
signal field_chosen(layout: String)
signal army_pick(t: int, i: int)
signal fall_back_to(no: int)

const PRESET_LIST := ["Regulars", "Skirmishers", "Shock", "Militia", "Veterans", "Balanced", "Random"]
const TYPE_LIST := ["Even", "Marksman", "Grenadier", "Runner", "Ironside", "Brawler", "Random"]
const BATCH_N := 10

var manager: MatchManager
var status_label: Label
var team_labels: Array[Label] = []
var teams_overlay: Control
var results_overlay: Control
var results_box: VBoxContainer
var results_title: Label
var speed_buttons: Array[Button] = []
var pause_btn: Button
var size_labels: Array[Label] = []
var size_sliders: Array = [null, null]
var _strip := [null, null]         # the company strip per side
var _bat_chips := [{}, {}]
var _army_locked := [[], []]   # controls that would break the army mapping: locked in a campaign
var front: Array = []          # the campaign's front, field 1 first
var _army_boxes := [null, null]
var _next_head: Label = null
var _army_secret := false     # the computer's picks are hidden on the round panel
var _next_help: Label = null
var _fb_chips := {}           # field no -> chip
var _slot_chips := [{}, {}]
var _co_title := [null, null]
var _totals := [null, null]
var persona_sliders := [{}, {}]
var persona_vals := [{}, {}]
var type_sliders := [{}, {}]
var type_vals := [{}, {}]
var persona_chips := [{}, {}]
var type_chips := [{}, {}]
var help_labels := [{}, {}]
var _acc_help := [null, null]   # the accuracy slider's line, rewritten with the rifle's numbers
var _updating := false
var _tick := 0.0
var _root: Control
var _paused := false
var _top: Control
var round_label: Label
var _round_text := ""
var _batch_text := ""
var campaign_on := false
var _plan_label: Label   # which field the companies are being set up for
var _type_controls := [[], []]   # chips and sliders locked while a campaign runs
var _campaign_btn: Button
var _fight_btn: Button
var _top_campaign_btn: Button
var _fight_btn0: Button
var _setup_note: Label
var _top_fight_btn: Button
var _batch_btn: Button
var _head_campaign_btn: Button
var _field_chips := {}
var campaign_men := 10        # men a company in the next campaign (10 or 20)
var _men_chips := {}
var cam: CameraRig = null
var _field_help: Label = null


## Light the chip of the field on the map and say what it is.
func mark_field(layout: String) -> void:
	for n in _field_chips:
		_field_chips[n].button_pressed = n == layout
	if _field_help != null:
		_field_help.text = "%s: %s" % [layout, Field.LAYOUT_HELP.get(layout, "")]


## Who picks each side's personality between campaign rounds: "you" or "computer"
var commanders := ["you", "computer"]
var _commander_chips := [{}, {}]
var _persona_controls := [[], []]


func setup(m: MatchManager) -> void:
	manager = m
	# web manners: everything you can press or drag shows the pointing hand, and the open field
	# (which you grab to turn the view) shows the move cross. Hooked on the tree so panels
	# built later - results, round summaries - get it too.
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	get_tree().node_added.connect(_cursor_for)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	var top := VBoxContainer.new()
	_top = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 44   # under the back-to-apps pill
	top.offset_left = 8
	top.offset_right = -8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)

	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	_top_campaign_btn = _button("» Start a campaign")
	_accent(_top_campaign_btn)
	_top_campaign_btn.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			campaign_abandoned.emit()
		else:
			campaign_requested.emit())
	row.add_child(_top_campaign_btn)
	var teams_btn := _button("Edit Battalion")
	teams_btn.pressed.connect(func(): _close_overlays(); teams_overlay.visible = true)
	row.add_child(teams_btn)
	var fight := _button("» New battle")
	_style(fight, "go")
	fight.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			next_round_requested.emit()
		else:
			new_match_requested.emit())
	row.add_child(fight)
	_top_fight_btn = fight
	for s in [1.0, 2.0, 4.0]:
		var b := _button("%d×" % int(s))
		b.toggle_mode = true
		b.pressed.connect(func(): _set_speed(s); speed_changed.emit(s))
		speed_buttons.append(b)
		row.add_child(b)
	speed_buttons[0].button_pressed = true
	pause_btn = _button("Pause")
	pause_btn.pressed.connect(func():
		_paused = not _paused
		pause_btn.text = "Resume" if _paused else "Pause"
		pause_toggled.emit(_paused))
	row.add_child(pause_btn)
	var fit := _button("Fit view")
	fit.pressed.connect(func(): fit_requested.emit())
	row.add_child(fit)
	var batch := _button("Sim ×%d" % BATCH_N)
	batch.pressed.connect(func(): _close_overlays(); batch_requested.emit(BATCH_N))
	row.add_child(batch)
	_batch_btn = batch

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(status_label)
	round_label = Label.new()
	round_label.add_theme_font_size_override("font_size", 15)
	round_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	round_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	round_label.add_theme_constant_override("shadow_offset_x", 1)
	round_label.add_theme_constant_override("shadow_offset_y", 1)
	round_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_label.visible = false
	top.add_child(round_label)
	for t in 2:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.35))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(l)
		team_labels.append(l)

	_build_teams_overlay()
	_build_results_overlay()


## Buttons that look like buttons: an outline on every state, a filled face when toggled on.
func _make_theme() -> Theme:
	var th := Theme.new()
	var mk := func(bg: Color, border: Color, fg: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(7)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		return sb
	th.set_stylebox("normal", "Button", mk.call(Color(0.16, 0.18, 0.22, 0.95), Color(0.75, 0.75, 0.7), Color.WHITE))
	th.set_stylebox("hover", "Button", mk.call(Color(0.24, 0.27, 0.32, 0.97), Color(0.95, 0.95, 0.9), Color.WHITE))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.88, 0.86, 0.78), Color(1, 1, 0.95), Color.BLACK))
	th.set_stylebox("hover_pressed", "Button", mk.call(Color(0.95, 0.93, 0.85), Color(1, 1, 0.95), Color.BLACK))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.12, 0.13, 0.15, 0.8), Color(0.4, 0.4, 0.4), Color.GRAY))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.95, 0.95, 0.92))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.08))
	th.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.1, 0.08))
	th.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	return th


func _accent(b: Button) -> void:
	_style(b, "gold")



## Colour says what a button does: green goes on (next round, fight, again), red ends
## something (abandon, cancel), gold opens a campaign; the rest stay neutral. The glyph in
## front says the same thing in another way.
func _style(b: Button, kind: String) -> void:
	var bg: Color
	var border: Color
	var fg := Color(0.98, 0.98, 0.95)
	match kind:
		"go":
			bg = Color(0.16, 0.42, 0.2)
			border = Color(0.55, 0.9, 0.55)
		"stop":
			bg = Color(0.5, 0.14, 0.12)
			border = Color(0.95, 0.55, 0.5)
		"gold":
			bg = Color(0.72, 0.5, 0.12)
			border = Color(1.0, 0.85, 0.5)
			fg = Color(0.1, 0.08, 0.04)
		_:
			for st in ["normal", "hover", "pressed"]:
				b.remove_theme_stylebox_override(st)
			for c in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.remove_theme_color_override(c)
			return
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", sb)
	var sb2: StyleBoxFlat = sb.duplicate()
	sb2.bg_color = bg.lightened(0.18)
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)


func _cursor_for(n: Node) -> void:
	if n is BaseButton or n is Slider:
		(n as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if n is Slider:
			(n as Slider).scrollable = false   # the wheel scrolls the page, never a value under it
	elif n is ScrollContainer or n is PanelContainer or n is Label:
		# reading, not grabbing the field: the plain arrow over the panels
		(n as Control).mouse_default_cursor_shape = Control.CURSOR_ARROW


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 15)
	return b


func _overlay(title_text: String) -> Array:
	var ov := PanelContainer.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.offset_top = 44
	ov.offset_left = 6
	ov.offset_right = -6
	ov.offset_bottom = -6
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.97)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	ov.add_theme_stylebox_override("panel", sb)
	ov.visible = false
	ov.visibility_changed.connect(func(): _top.visible = not (teams_overlay != null and teams_overlay.visible or results_overlay != null and results_overlay.visible))
	_root.add_child(ov)
	var vb := VBoxContainer.new()
	ov.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var close := _button("« Close")
	close.custom_minimum_size = Vector2(96, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func(): ov.visible = false)
	head.add_child(close)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.max_lines_visible = 2
	head.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 28   # a thumb dragging the page scrolls it; a slider only moves on a deliberate touch
	vb.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return [ov, box, title]


func _build_teams_overlay() -> void:
	var parts := _overlay("Edit Battalion")
	teams_overlay = parts[0]
	var box: VBoxContainer = parts[1]
	_setup_note = Label.new()
	_setup_note.add_theme_font_size_override("font_size", 16)
	_setup_note.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	_setup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_note.visible = false
	box.add_child(_setup_note)
	_plan_label = Label.new()
	_plan_label.add_theme_font_size_override("font_size", 15)
	_plan_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.95))
	_plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_plan_label)
	var head := HFlowContainer.new()
	box.add_child(head)
	_head_campaign_btn = _button("» Start a campaign (to the end)")
	_head_campaign_btn.custom_minimum_size = Vector2(0, 46)
	_accent(_head_campaign_btn)
	_head_campaign_btn.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			campaign_abandoned.emit()
		else:
			campaign_requested.emit())
	head.add_child(_head_campaign_btn)
	var fight0 := _button("» Fight one battle")
	fight0.custom_minimum_size = Vector2(0, 46)
	_style(fight0, "go")
	fight0.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			next_round_requested.emit()
		else:
			new_match_requested.emit())
	head.add_child(fight0)
	_fight_btn0 = fight0
	var note := Label.new()
	note.text = "Nobody takes orders. Build a battalion: up to six companies a side, each with its own men, type, drill and place in the line (or in reserve). A drill is a short set of written rules for when to volley, charge, take cover and give ground; each company's sergeant reads his own. The captain only sends in the reserve. Simulation: one battle, or Sim x10 for the numbers. Campaign: five rounds along a front of ten fields - the men who stand or run carry over, the dead do not; recruits fill the ranks until the last round, which is fought with what is left. Types and drills may both be changed between rounds - by you, or by the computer for a side you hand it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	box.add_child(note)
	var cols := HFlowContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	for t in 2:
		cols.add_child(_build_team_panel(t))
	_section(box, "The field, for a single battle or Sim x10")
	var frow := HFlowContainer.new()
	box.add_child(frow)
	for fname in Field.ALL_FIELDS:
		var fb := Button.new()
		fb.text = fname
		fb.toggle_mode = true
		fb.custom_minimum_size = Vector2(0, 36)
		fb.add_theme_font_size_override("font_size", 13)
		fb.tooltip_text = Field.LAYOUT_HELP.get(fname, "")
		fb.pressed.connect(func(): field_chosen.emit(fname))
		frow.add_child(fb)
		_field_chips[fname] = fb
	var fhelp := Label.new()
	fhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fhelp.add_theme_font_size_override("font_size", 12)
	fhelp.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	box.add_child(fhelp)
	_field_help = fhelp
	_section(box, "The campaign")
	var fnote := Label.new()
	fnote.text = "A war along a front of eleven fields drawn at random from the thirteen; it opens on the middle field. Each army is twelve companies of ten, patterned on the companies set up here (A-D, then repeated), and the freshest four fight by default - between battles, put in or stand down as many as you like (a computer army guesses its own number, unseen; you see it when the battle opens). No recruits: the dead are gone, the living fight on, and a company cut under three joins another. Each win pushes the fight one field into the loser's country. The war is won by winning on the enemy's last field - or when the enemy has nobody left."
	fnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fnote.add_theme_font_size_override("font_size", 13)
	fnote.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	box.add_child(fnote)
	var srow := HFlowContainer.new()
	box.add_child(srow)
	var sl := Label.new()
	sl.text = "Companies in the campaign: "
	sl.add_theme_font_size_override("font_size", 14)
	srow.add_child(sl)
	for men in [10, 20]:
		var b := Button.new()
		b.text = "%d men (%d a side)" % [men, men * 4]
		b.toggle_mode = true
		b.button_pressed = campaign_men == men
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			campaign_men = men
			for k in _men_chips:
				_men_chips[k].button_pressed = k == men)
		srow.add_child(b)
		_men_chips[men] = b
	var foot := HFlowContainer.new()
	box.add_child(foot)
	var fight := _button("» Fight with these companies")
	fight.custom_minimum_size = Vector2(0, 46)
	_style(fight, "go")
	fight.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			next_round_requested.emit()
		else:
			new_match_requested.emit())
	foot.add_child(fight)
	_fight_btn = fight
	var camp := _button("» Start a campaign (to the end)")
	camp.custom_minimum_size = Vector2(0, 46)
	_accent(camp)
	camp.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			campaign_abandoned.emit()
		else:
			campaign_requested.emit())
	foot.add_child(camp)
	_campaign_btn = camp
	var close2 := _button("« Close")
	close2.custom_minimum_size = Vector2(96, 46)
	close2.pressed.connect(func(): teams_overlay.visible = false)
	foot.add_child(close2)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	box.add_child(pad)


func _build_team_panel(t: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(330, 0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = MatchManager.TEAM_COLORS[t].darkened(0.75)
	fsb.bg_color.a = 0.55
	fsb.border_color = MatchManager.TEAM_COLORS[t].lightened(0.15)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(8)
	fsb.content_margin_left = 8
	fsb.content_margin_right = 8
	fsb.content_margin_top = 6
	fsb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", fsb)
	var panel := VBoxContainer.new()
	frame.add_child(panel)
	var name_l := Label.new()
	name_l.text = "%s battalion" % MatchManager.TEAM_NAMES[t]
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.45))
	panel.add_child(name_l)

	# a whole battalion at a tap, then company by company
	var bl := Label.new()
	bl.text = "Battalion (fills every company; edit any after)"
	bl.add_theme_font_size_override("font_size", 15)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(bl)
	var brow := HFlowContainer.new()
	panel.add_child(brow)
	for bn in MatchManager.BATTALIONS:
		var b := Button.new()
		b.text = bn
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = MatchManager.BATTALION_HELP.get(bn, "")
		b.pressed.connect(func():
			manager.set_battalion(t, bn, int(manager.companies[t][manager.sel[t]]["size"]), true)
			_refresh_sliders(t))
		brow.add_child(b)
		_bat_chips[t][bn] = b
		_army_locked[t].append(b)
		_type_controls[t].append(b)
	var tot := Label.new()
	tot.add_theme_font_size_override("font_size", 13)
	tot.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	tot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(tot)
	_totals[t] = tot
	# the company strip: one card per company; tap one to edit it below
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 6)
	panel.add_child(strip)
	_strip[t] = strip
	var ops := HFlowContainer.new()
	panel.add_child(ops)
	var add := _button("+ Add company")
	_army_locked[t].append(add)
	add.pressed.connect(func(): manager.add_company(t); _refresh_sliders(t))
	ops.add_child(add)
	_type_controls[t].append(add)
	var rem := _button("× Remove this company")
	_army_locked[t].append(rem)
	_style(rem, "stop")
	rem.pressed.connect(func(): manager.remove_company(t); _refresh_sliders(t))
	ops.add_child(rem)
	_type_controls[t].append(rem)
	var dup := _button("Apply this company to all")
	_army_locked[t].append(dup)
	dup.pressed.connect(func(): _apply_to_all(t))
	ops.add_child(dup)
	_type_controls[t].append(dup)

	var co_t := Label.new()
	co_t.add_theme_font_size_override("font_size", 17)
	co_t.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.55))
	panel.add_child(co_t)
	_co_title[t] = co_t
	var sll := Label.new()
	sll.text = "Where it stands (from %s's own left)" % MatchManager.TEAM_NAMES[t]
	sll.add_theme_font_size_override("font_size", 14)
	sll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(sll)
	var srow := HFlowContainer.new()
	panel.add_child(srow)
	for sn in MatchManager.SLOTS:
		var b := Button.new()
		b.text = sn
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			manager.companies[t][manager.sel[t]]["slot"] = sn
			manager.companies[t][manager.sel[t]]["slot_set"] = true   # a campaign remembers it
			_refresh_sliders(t))
		srow.add_child(b)
		_slot_chips[t][sn] = b
		_type_controls[t].append(b)

	# size
	var size_row := HBoxContainer.new()
	panel.add_child(size_row)
	var sl := Label.new()
	sl.text = "Men: %d" % int(manager.team_sizes[t])
	sl.custom_minimum_size = Vector2(90, 0)
	sl.add_theme_font_size_override("font_size", 15)
	size_row.add_child(sl)
	size_labels.append(sl)
	var size_slider := HSlider.new()
	size_slider.min_value = 1
	size_slider.max_value = MatchManager.MAX_SIZE
	size_slider.step = 1
	size_slider.value = int(manager.team_sizes[t])
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.custom_minimum_size = Vector2(0, 40)
	size_slider.tick_count = 5
	size_slider.ticks_on_borders = true
	size_slider.value_changed.connect(func(v: float):
		if _updating:
			return
		var room: int = MatchManager.MAX_SIDE - (manager.side_total(t) - int(manager.team_sizes[t]))
		manager.team_sizes[t] = mini(int(v), room)
		_refresh_sliders(t))
	size_sliders[t] = size_slider
	_army_locked[t].append(size_slider)
	_type_controls[t].append(size_slider)
	size_row.add_child(size_slider)

	# type
	var tl := Label.new()
	tl.text = "Type (the four share one budget)"
	tl.add_theme_font_size_override("font_size", 15)
	panel.add_child(tl)
	panel.add_child(_chip_row(t, TYPE_LIST, true))
	var thelp := Label.new()
	thelp.name = "TypeHelp"
	thelp.text = SoldierType.TYPE_HELP.get(manager.team_type_names[t], "")
	thelp.add_theme_font_size_override("font_size", 12)
	thelp.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	thelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(thelp)
	for p in SoldierType.PROPS:
		panel.add_child(_slider_row(t, p, SoldierType.PROP_HELP[p], true))

	# who picks the personality each campaign round
	var cl := Label.new()
	cl.text = "Commander (campaign rounds)"
	cl.add_theme_font_size_override("font_size", 15)
	panel.add_child(cl)
	var crow := HFlowContainer.new()
	panel.add_child(crow)
	for who in ["you", "computer"]:
		var b := Button.new()
		b.text = "You choose" if who == "you" else "Computer chooses"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 14)
		b.button_pressed = commanders[t] == who
		b.pressed.connect(func(): _set_commander(t, who))
		crow.add_child(b)
		_commander_chips[t][who] = b
	var chelp := Label.new()
	chelp.text = "The computer picks a drill and a type for every company each round - never the same for all four - answering what the other battalion fielded, the ground, and what has worked this campaign."
	chelp.add_theme_font_size_override("font_size", 12)
	chelp.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	chelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(chelp)

	# the drill: what the company does, written as rules
	var pl := Label.new()
	pl.text = "Drill (how the company fights)"
	pl.add_theme_font_size_override("font_size", 15)
	panel.add_child(pl)
	panel.add_child(_chip_row(t, Drill.names(), false))
	var phelp := Label.new()
	phelp.name = "PersonaHelp"
	phelp.text = manager.team_drills[t].about if manager.team_drills[t] != null else ""
	phelp.add_theme_font_size_override("font_size", 12)
	phelp.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	phelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(phelp)
	var read := _button("Read the drill")
	read.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	read.pressed.connect(func(): show_drill(t))
	panel.add_child(read)
	help_labels[t] = {"type": thelp, "persona": phelp}
	_refresh_sliders(t)
	return frame


## A row of toggle chips, one per preset: a tap picks it, the chosen one stays lit.
func _chip_row(t: int, names: Array, is_type: bool) -> Control:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in names:
		var b := Button.new()
		b.text = n
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			if is_type:
				_on_type(t, n)
			else:
				_on_preset(t, n))
		row.add_child(b)
		if is_type:
			type_chips[t][n] = b
			_type_controls[t].append(b)
		else:
			persona_chips[t][n] = b
			_persona_controls[t].append(b)
	return row


func _slider_row(t: int, key: String, help: String, is_type: bool) -> Control:
	var vb := VBoxContainer.new()
	var row := HBoxContainer.new()
	vb.add_child(row)
	var l := Label.new()
	l.text = key.capitalize()
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0 if not is_type else 0.85
	s.step = 0.01
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 30)
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(44, 0)
	v.add_theme_font_size_override("font_size", 13)
	row.add_child(v)
	var h := Label.new()
	h.text = help
	h.add_theme_font_size_override("font_size", 11)
	h.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(h)
	if is_type and key == "accuracy":
		_acc_help[t] = h
	if is_type:
		type_sliders[t][key] = s
		type_vals[t][key] = v
		_type_controls[t].append(s)
		s.value_changed.connect(func(val: float): _on_type_slider(t, key, val))
	else:
		persona_sliders[t][key] = s
		persona_vals[t][key] = v
		_persona_controls[t].append(s)
		s.value_changed.connect(func(val: float): _on_slider(t, key, val))
	return vb


func _on_preset(t: int, preset_name: String) -> void:
	manager.set_drill(t, preset_name)
	_refresh_sliders(t)


## The drill's text, as written, in the results overlay: what the company will do and when.
func show_drill(t: int) -> void:
	var d: Drill = manager.team_drills[t]
	if d == null:
		return
	for c in results_box.get_children():
		c.queue_free()
	results_title.text = "%s - the drill" % d.name
	var who := Label.new()
	who.text = "%s company %s fights this drill. Rules are read top to bottom; the first that holds and can be done decides. Anything no rule decides falls to the dials." % [MatchManager.TEAM_NAMES[t], manager.companies[t][manager.sel[t]]["name"]]
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_theme_font_size_override("font_size", 13)
	who.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.45))
	results_box.add_child(who)
	var code := Label.new()
	code.text = d.source.strip_edges()
	code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code.add_theme_font_size_override("font_size", 13)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "Courier New", "monospace"])
	code.add_theme_font_override("font", mono)
	code.add_theme_color_override("font_color", Color(0.9, 0.9, 0.82))
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.13)
	sb.border_color = MatchManager.TEAM_COLORS[t].lightened(0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", sb)
	frame.add_child(code)
	results_box.add_child(frame)
	if not d.errors.is_empty():
		var err := Label.new()
		err.text = "Problems: " + "; ".join(d.errors)
		err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		results_box.add_child(err)
	var row := HFlowContainer.new()
	results_box.add_child(row)
	var back := _button("« Back to Edit Company")
	back.pressed.connect(func(): _close_overlays(); teams_overlay.visible = true)
	row.add_child(back)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	results_box.add_child(pad)
	_close_overlays()
	results_overlay.visible = true


func _on_slider(t: int, trait_name: String, v: float) -> void:
	if _updating:
		return
	manager.team_personalities[t].set_trait(trait_name, v)
	manager.team_preset_names[t] = manager.team_personalities[t].label()
	_refresh_sliders(t)


func _on_type(t: int, preset_name: String) -> void:
	if preset_name == "Custom":
		return
	manager.team_types[t] = SoldierType.preset(preset_name)
	manager.team_type_names[t] = preset_name
	_refresh_sliders(t)


func _on_type_slider(t: int, prop: String, v: float) -> void:
	if _updating:
		return
	manager.team_types[t].set_and_rebalance(prop, v)
	manager.team_type_names[t] = manager.team_types[t].label()
	_refresh_sliders(t)


## Copy the selected company's type, personality and size to every company of the side.
func _apply_to_all(t: int) -> void:
	manager.store_company(t)
	var src: Dictionary = manager.companies[t][manager.sel[t]]
	for co in manager.companies[t]:
		if co == src:
			continue
		co["persona"] = (src["persona"] as Personality).jittered(manager.rng, 0.0)
		co["persona_name"] = src["persona_name"]
		co["drill"] = src.get("drill")
		co["type"] = (src["type"] as SoldierType).copy()
		co["type_name"] = src["type_name"]
		co["size"] = src["size"]
	_refresh_sliders(t)


func selected_company(t: int) -> int:
	return manager.sel[t]


## The company strip: a card per company, the selected one pressed.
func _rebuild_strip(t: int) -> void:
	var strip: HFlowContainer = _strip[t]
	if strip == null:
		return
	for ch in strip.get_children():
		ch.queue_free()
	var cos: Array = manager.companies[t]
	for c in cos.size():
		var co: Dictionary = cos[c]
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = c == manager.sel[t]
		b.text = "%s · %d men\n%s / %s\n%s\n%s" % [co["name"], int(co["size"]), co["persona_name"], co["type_name"], co["slot"], MatchManager.mark_for(c)["name"]]
		b.custom_minimum_size = Vector2(118, 0)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			manager.store_company(t)
			manager.select_company(t, c)
			_refresh_sliders(t))
		strip.add_child(b)
	var tl: Label = _totals[t]
	tl.text = "%d men in %d companies (up to %d men, %d companies a side)" % [manager.side_total(t), cos.size(), MatchManager.MAX_SIDE, MatchManager.EDIT_COMPANIES]
	(_co_title[t] as Label).text = "Company %s" % cos[manager.sel[t]]["name"]
	var slot: String = cos[manager.sel[t]]["slot"]
	for sn in _slot_chips[t]:
		_slot_chips[t][sn].button_pressed = sn == slot
	var label := manager.battalion_label(t)
	for bn in _bat_chips[t]:
		_bat_chips[t][bn].button_pressed = bn == label
	_cursor_for_tree(strip)


func _cursor_for_tree(n: Node) -> void:
	for ch in n.get_children():
		_cursor_for(ch)


func _refresh_sliders(t: int) -> void:
	manager.store_company(t)
	_rebuild_strip(t)
	_updating = true
	if size_sliders[t] != null:
		size_sliders[t].value = int(manager.team_sizes[t])
		size_labels[t].text = "Men: %d" % int(manager.team_sizes[t])
	for tr in Personality.TRAITS:
		if persona_sliders[t].has(tr):
			persona_sliders[t][tr].value = manager.team_personalities[t].get_trait(tr)
			persona_vals[t][tr].text = "%.2f" % manager.team_personalities[t].get_trait(tr)
	for p in SoldierType.PROPS:
		if type_sliders[t].has(p):
			type_sliders[t][p].value = manager.team_types[t].get_prop(p)
			type_vals[t][p].text = "%.2f" % manager.team_types[t].get_prop(p)
	var pn: String = manager.team_preset_names[t]
	var tn: String = manager.team_type_names[t]
	for n in persona_chips[t]:
		persona_chips[t][n].button_pressed = (n == pn)
	for n in type_chips[t]:
		type_chips[t][n].button_pressed = (n == tn)
	if _acc_help[t] != null:
		var sk: float = manager.team_types[t].skill("accuracy")
		_acc_help[t].text = "Musketry and reload. On the range he hits a man %d%% at 50 m, %d%% at 100 m (spread %.1f mrad; a trained marksman 99/84, a raw recruit 49/22). In the smoke of a battle, standing: %d%% at 20 m, %d%% at 50 m. Reloads in %d s (never under %d s); %d rounds in the box." % [
			int(round(100.0 * Ballistics.p_range(sk, 50.0))), int(round(100.0 * Ballistics.p_range(sk, 100.0))),
			Ballistics.sigma_range(sk), int(round(100.0 * Ballistics.p_range(sk, 20.0, true))), int(round(100.0 * Ballistics.p_range(sk, 50.0, true))),
				int(round(Soldier.RELOAD * 1.2 / (0.8 + 0.4 * sk))), int(Soldier.RELOAD), Soldier.AMMO]
	if help_labels[t].has("persona"):
		var dd: Drill = manager.team_drills[t]
		help_labels[t]["persona"].text = dd.about if dd != null else ""
		help_labels[t]["type"].text = SoldierType.TYPE_HELP.get(tn, "Custom build - the sliders are yours")
	_updating = false


func _build_results_overlay() -> void:
	var parts := _overlay("Result")
	results_overlay = parts[0]
	results_box = parts[1]
	results_title = parts[2]


func _close_overlays() -> void:
	teams_overlay.visible = false
	results_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_H or event.physical_keycode == KEY_HOME):
		var shut := not ((teams_overlay != null and teams_overlay.visible) or (results_overlay != null and results_overlay.visible))
		if shut and not _typing():
			fit_requested.emit()
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel"):
		return
	var open := (teams_overlay != null and teams_overlay.visible) or (results_overlay != null and results_overlay.visible)
	if open:
		_close_overlays()
		get_viewport().set_input_as_handled()


func on_match_started() -> void:
	_close_overlays()
	_setup_note.visible = false
	set_status("The lines are drawn.")


func _set_speed(s: float) -> void:
	for i in speed_buttons.size():
		speed_buttons[i].button_pressed = is_equal_approx([1.0, 2.0, 4.0][i], s)


func set_status(text: String) -> void:
	status_label.text = text


## ?debug=1 (or --debug): frame rate, draw calls and the rest, top right, twice a second.
var _dbg_label: Label = null
var _dbg_t := 0.0


func enable_debug() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_dbg_label = Label.new()
	_dbg_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dbg_label.position = Vector2(-330, 54)
	_dbg_label.custom_minimum_size = Vector2(320, 0)
	_dbg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dbg_label.add_theme_font_size_override("font_size", 13)
	_dbg_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_dbg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_dbg_label.add_theme_constant_override("outline_size", 4)
	_dbg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_dbg_label)


func _update_debug(delta: float) -> void:
	_dbg_t -= delta
	if _dbg_t > 0.0:
		return
	_dbg_t = 0.5
	var men := manager.alive_soldiers().size() if manager != null else 0
	_dbg_label.text = "%d fps · %d draw calls · %d objects drawn\n%.0fk triangles · %d nodes · %d men\nscript+process %.1f ms · physics %.1f ms · ×%.0f speed" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), men,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Engine.time_scale]


func _process(delta: float) -> void:
	_pad_tick(delta)
	if _dbg_label != null:
		_update_debug(delta)
	_tick -= delta
	if _tick > 0.0 or manager == null:
		return
	_tick = 0.25
	for t in 2:
		var os: Array = manager.orders[t]
		if os.is_empty() or manager.stats.is_empty():
			continue
		var st: Dictionary = manager.stats
		var fighting := manager.fighting(t).size()
		var alive := manager.alive_count(t)
		var modes := []
		for c in mini(os.size(), (manager.companies[t] as Array).size()):   # between battles the companies may already be the next lot
			if manager.fighting_company(t, c).is_empty():
				modes.append("%s lost" % manager.companies[t][c]["name"])
			elif manager.is_reserve(t, c):
				modes.append("%s reserve" % manager.companies[t][c]["name"])
			else:
				modes.append("%s %s" % [manager.companies[t][c]["name"], String(os[c].get("mode", "")).replace("_", " ")])
		team_labels[t].text = "%s: %d standing (%d in line) · %s · shots %d/%d" % [
			MatchManager.TEAM_NAMES[t], alive, fighting, ", ".join(modes), st["hits"][t], st["shots"][t]]
	if manager.running:
		var clock := "%d:%02d" % [int(manager.elapsed) / 60, int(manager.elapsed) % 60]
		status_label.text = (_batch_text + " · " + clock) if _batch_text != "" else clock


func show_result(res: Dictionary) -> void:
	for c in results_box.get_children():
		c.queue_free()
	results_title.text = "%s - %s (%d:%02d)" % [
		("%s wins" % res["winner_name"]) if res["winner"] >= 0 else "Draw", res["reason"], int(res["duration"]) / 60, int(res["duration"]) % 60]
	var st: Dictionary = res["stats"]
	for t in 2:
		var l := Label.new()
		var acc := float(st["hits"][t]) / maxf(float(st["shots"][t]), 1.0) * 100.0
		var tacc := float(st["thrust_hits"][t]) / maxf(float(st["thrusts"][t]), 1.0) * 100.0
		l.text = "%s (%s, %s): %d of %d standing, %d ran. Shots %d, hits %d (%d%%), friendly hits %d. Volleys %d, charges %d, fall-backs %d. Killed by ball %d, by bayonet %d (%d thrusts, %d%% landed)." % [
			MatchManager.TEAM_NAMES[t], res["presets"][t], res["types"][t], res["alive"][t], res["sizes"][t], st["routed"][t],
			st["shots"][t], st["hits"][t], int(acc), st["friendly"][t], st["volleys"][t], st["charges"][t], st["fallbacks"][t],
			st["kills"][t][0], st["kills"][t][1], st["thrusts"][t], int(tacc)]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.4))
		results_box.add_child(l)
	# the companies
	_section(results_box, "The companies")
	var cg := GridContainer.new()
	cg.columns = 6
	cg.add_theme_constant_override("h_separation", 10)
	results_box.add_child(cg)
	for h in ["Company", "Fielded as", "Stood", "Ran", "Fell", "Kills (bayonet)"]:
		_cell(cg, h, true)
	var cstats := {}
	for m in res["soldiers"]:
		var key := "%d:%d" % [int(m["team"]), int(m.get("company", 0))]
		if not cstats.has(key):
			cstats[key] = [0, 0, 0, 0, 0]
		var cs: Array = cstats[key]
		if not m["alive"]:
			cs[2] += 1
		elif m["routed"] or m["gone"]:
			cs[1] += 1
		else:
			cs[0] += 1
		cs[3] += int(m["kills"])
		cs[4] += int(m["bayonet_kills"])
	var cos: Array = res.get("companies", [[], []])
	for t in 2:
		for c in (cos[t] as Array).size():
			var co: Dictionary = cos[t][c]
			var cs: Array = cstats.get("%d:%d" % [t, c], [0, 0, 0, 0, 0])
			var col: Color = MatchManager.TEAM_COLORS[t].lightened(0.45)
			_cell(cg, "%s %s" % [MatchManager.TEAM_NAMES[t], co["name"]], true, col)
			_cell(cg, "%s / %s, %s" % [co["persona"], co["type"], co["slot"]], false, col)
			_cell(cg, str(cs[0]), false)
			_cell(cg, str(cs[1]), false)
			_cell(cg, str(cs[2]), false)
			_cell(cg, "%d (%d)" % [cs[3], cs[4]], false)
	# the men, best first
	var men: Array = res["soldiers"].duplicate()
	men.sort_custom(func(a, b): return a["kills"] > b["kills"] or (a["kills"] == b["kills"] and a["hits"] > b["hits"]))
	var shown := 0
	for m in men:
		if shown >= 12:
			break
		if m["kills"] == 0 and m["hits"] == 0:
			continue
		var l := Label.new()
		l.text = "  %s: %d kills (%d bayonet), %d/%d shots hit%s" % [m["name"], m["kills"], m["bayonet_kills"], m["hits"], m["shots"],
			"" if m["alive"] else " - fell", ]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[m["team"]].lightened(0.5))
		results_box.add_child(l)
		shown += 1
	var row := HFlowContainer.new()
	results_box.add_child(row)
	var again := _button("» Next battle")
	_style(again, "go")
	again.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	row.add_child(again)
	var teams := _button("Edit Battalion")
	teams.pressed.connect(func(): _close_overlays(); teams_overlay.visible = true)
	row.add_child(teams)
	results_overlay.visible = true


func show_batch(summary: Dictionary) -> void:
	for c in results_box.get_children():
		c.queue_free()
	var d: Dictionary = summary["data"]
	var n: int = maxi(int(d["matches"]), 1)
	var tot: Dictionary = d["totals"]
	var kills: Array = d["kills"]
	var wins: Array = d["wins"]
	results_title.text = "Batch of %d - %s %d, %s %d, drawn %d" % [n, MatchManager.TEAM_NAMES[0], wins[0], MatchManager.TEAM_NAMES[1], wins[1], d["draws"]]

	# the companies
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	results_box.add_child(grid)
	_cell(grid, "", false)
	for t in 2:
		_cell(grid, "%s" % MatchManager.TEAM_NAMES[t], true, MatchManager.TEAM_COLORS[t].lightened(0.4))
	var rows: Array = [
		["Company", ["%s / %s, %d men" % [d["presets"][0], d["types"][0], d["sizes"][0]], "%s / %s, %d men" % [d["presets"][1], d["types"][1], d["sizes"][1]]]],
		["Wins", ["%d of %d" % [wins[0], n], "%d of %d" % [wins[1], n]]],
	]
	# the butcher's bill: what each side did and what it cost, per battle
	var kd := [float(kills[0][0] + kills[0][1]), float(kills[1][0] + kills[1][1])]
	rows.append(["Kills per battle", ["%.1f" % (kd[0] / n), "%.1f" % (kd[1] / n)]])
	rows.append(["Deaths per battle", ["%.1f" % (kd[1] / n), "%.1f" % (kd[0] / n)]])
	rows.append(["Kill / death", ["%.2f" % (kd[0] / maxf(kd[1], 1.0)), "%.2f" % (kd[1] / maxf(kd[0], 1.0))]])
	for r in rows:
		_cell(grid, r[0], true)
		for t in 2:
			_cell(grid, r[1][t], false, MatchManager.TEAM_COLORS[t].lightened(0.5))
	_section(results_box, "Musketry, per battle")
	var g2 := _stat_grid()
	_stat_row(g2, "Shots fired", [tot["shots"][0] / n, tot["shots"][1] / n])
	_stat_row(g2, "Hit rate", ["%d%%" % int(float(tot["hits"][0]) / maxf(float(tot["shots"][0]), 1.0) * 100.0), "%d%%" % int(float(tot["hits"][1]) / maxf(float(tot["shots"][1]), 1.0) * 100.0)])
	_stat_row(g2, "Volleys called", [tot["volleys"][0] / n, tot["volleys"][1] / n])
	_stat_row(g2, "Killed by ball", [kills[0][0] / n, kills[1][0] / n])
	_stat_row(g2, "Friendly hits", [tot["friendly"][0] / n, tot["friendly"][1] / n])
	_section(results_box, "The bayonet, per battle")
	var g3 := _stat_grid()
	_stat_row(g3, "Charges", [tot["charges"][0] / n, tot["charges"][1] / n])
	_stat_row(g3, "Thrusts", [tot["thrusts"][0] / n, tot["thrusts"][1] / n])
	_stat_row(g3, "Thrusts landed", ["%d%%" % int(float(tot["thrust_hits"][0]) / maxf(float(tot["thrusts"][0]), 1.0) * 100.0), "%d%%" % int(float(tot["thrust_hits"][1]) / maxf(float(tot["thrusts"][1]), 1.0) * 100.0)])
	_stat_row(g3, "Killed by bayonet", [kills[0][1] / n, kills[1][1] / n])
	_section(results_box, "Nerve, per battle")
	var g4 := _stat_grid()
	_stat_row(g4, "Fall-backs ordered", [tot["fallbacks"][0] / n, tot["fallbacks"][1] / n])
	_stat_row(g4, "Men who ran", [tot["routed"][0] / n, tot["routed"][1] / n])
	_stat_row(g4, "Killed, all told", [(kills[1][0] + kills[1][1]) / n, (kills[0][0] + kills[0][1]) / n])
	# company by company, per battle
	var cst: Array = d.get("co_stats", [{}, {}])
	var ccos: Array = d.get("companies", [[], []])
	_section(results_box, "The companies, per battle")
	var cg := GridContainer.new()
	cg.columns = 6
	cg.add_theme_constant_override("h_separation", 10)
	results_box.add_child(cg)
	for h in ["Company", "Fielded as", "Stood / ran / fell", "Shots", "Hits", "Kills (bayonet)"]:
		_cell(cg, h, true)
	for t in 2:
		for c in (ccos[t] as Array).size():
			var co: Dictionary = ccos[t][c]
			var st: Dictionary = (cst[t] as Dictionary).get(c, {})
			if st.is_empty():
				continue
			var col: Color = MatchManager.TEAM_COLORS[t].lightened(0.45)
			_cell(cg, "%s %s" % [MatchManager.TEAM_NAMES[t], co["name"]], true, col)
			_cell(cg, "%s / %s, %s" % [co["persona"], co["type"], co["slot"]], false, col)
			_cell(cg, "%.1f / %.1f / %.1f" % [float(st["stood"]) / n, float(st["ran"]) / n, float(st["fell"]) / n], false)
			_cell(cg, "%.1f" % (float(st["shots"]) / n), false)
			_cell(cg, "%d%%" % int(100.0 * float(st["hits"]) / maxf(float(st["shots"]), 1.0)), false)
			_cell(cg, "%.1f (%.1f)" % [float(st["kills"]) / n, float(st["bayonet"]) / n], false)
	# the drills: which rule decided how often - the way to see whether a drill does what was meant
	var tally: Array = d.get("tally", [{}, {}])
	for t in 2:
		for dn in (tally[t] as Dictionary):
			var dr: Drill = Drill.named(String(dn))
			if dr == null:
				continue
			_section(results_box, "%s: %s - rules that decided, per battle" % [MatchManager.TEAM_NAMES[t], dr.name])
			var gt := GridContainer.new()
			gt.columns = 2
			gt.add_theme_constant_override("h_separation", 10)
			var per: Dictionary = tally[t][dn]
			for rules in [dr.sergeant_rules, dr.man_rules]:
				for r in rules:
					var cnt: int = int(per.get(r["line"], per.get(str(r["line"]), 0)))
					_cell(gt, "%d" % int(round(float(cnt) / n)), true, MatchManager.TEAM_COLORS[t].lightened(0.45))
					gt.get_child(gt.get_child_count() - 1).custom_minimum_size = Vector2(44, 0)
					(gt.get_child(gt.get_child_count() - 1) as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
					_cell(gt, ("sergeant: " if rules == dr.sergeant_rules else "man: ") + String(r["text"]), false)
			results_box.add_child(gt)
	_section(results_box, "The battles (avg %d:%02d)" % [int(d["avg_duration"]) / 60, int(d["avg_duration"]) % 60])
	var g5 := GridContainer.new()
	g5.columns = 5
	g5.add_theme_constant_override("h_separation", 14)
	results_box.add_child(g5)
	for h in ["#", "Winner", "How", "Time", "Standing"]:
		_cell(g5, h, true)
	for b in d.get("battles", []):
		_cell(g5, str(b["match"]), false)
		var w: int = int(b["winner"])
		_cell(g5, b["winner_name"], false, MatchManager.TEAM_COLORS[w].lightened(0.5) if w >= 0 else Color(0.8, 0.8, 0.8))
		_cell(g5, b["reason"], false)
		_cell(g5, "%d:%02d" % [int(b["duration"]) / 60, int(b["duration"]) % 60], false)
		_cell(g5, "%d - %d" % [b["alive"][0], b["alive"][1]], false)

	var row := HFlowContainer.new()
	results_box.add_child(row)
	var again := _button("» New battle")
	_style(again, "go")
	again.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
	row.add_child(again)
	var batch := _button("» Sim ×%d again" % BATCH_N)
	_style(batch, "go")
	batch.pressed.connect(func(): _close_overlays(); batch_requested.emit(BATCH_N))
	row.add_child(batch)
	var teams := _button("Edit Battalion")
	teams.pressed.connect(func(): _close_overlays(); teams_overlay.visible = true)
	row.add_child(teams)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	results_box.add_child(pad)
	results_overlay.visible = true


func batch_progress(i: int, n: int) -> void:
	_batch_text = "Sim %d of %d" % [i, n] if n > 0 else ""
	if n > 0:
		status_label.text = _batch_text


func set_round(r: int, layout: String, men: Array, field_no: int = 0) -> void:
	var n := front.size()
	_round_text = "Battle %d - field %d of %d, %s · armies: Red %d men, Blue %d men" % [r, field_no, n, layout, men[0], men[1]]
	if field_no >= n:
		_round_text += " · a Red win here takes Blue's country"
	elif field_no > 0:
		_round_text += " · a Red win pushes on to %s" % front[field_no]
	if field_no <= 1:
		_round_text += ", a Blue win here takes Red's country"
	elif field_no > 0:
		_round_text += ", a Blue win back to %s" % front[field_no - 2]
	round_label.text = _round_text
	round_label.visible = true


## The setup panel, with a line at the top saying why it is open. Nothing runs until a
## button here (or the top row) says so.
## The field the companies are being set up for, at the top of Edit Company. In a campaign
## it names the round as well; a single battle just names the ground.
func set_plan(field_no: int, layout: String, round_no: int = 0, total: int = 0) -> void:
	var help: String = Field.LAYOUT_HELP.get(layout, "")
	if round_no > 0:
		_plan_label.text = "Planning battle %d, on field %d of %d: %s - %s" % [round_no, field_no, total, layout, help]
	else:
		_plan_label.text = "Planning a battle on %s - %s" % [layout, help]


func open_setup(why: String) -> void:
	_close_overlays()
	_setup_note.text = why
	_setup_note.visible = why != ""
	teams_overlay.visible = true
	status_label.text = "Nothing running - choose under Edit Battalion."


func _set_commander(t: int, who: String) -> void:
	commanders[t] = who
	for w in _commander_chips[t]:
		_commander_chips[t][w].button_pressed = (w == who)
	_apply_locks()


## A computer-commanded side's type and personality are the computer's to set; everything
## else stays open between rounds.
func _apply_locks() -> void:
	for t in 2:
		var ai: bool = campaign_on and String(commanders[t]) == "computer"
		for c in _type_controls[t]:
			if c is Button:
				c.disabled = ai
			if c is HSlider:
				c.editable = not ai
		for c in _persona_controls[t]:
			if c is Button:
				c.disabled = ai
			if c is HSlider:
				c.editable = not ai
		# in a campaign the companies are the army's: no adding, removing or resizing (where each stands is still yours)
		for c in _army_locked[t]:
			if c is Button:
				c.disabled = campaign_on or ai
			if c is HSlider:
				c.editable = not campaign_on and not ai


func campaign_started() -> void:
	campaign_on = true
	_apply_locks()
	_top_campaign_btn.text = "× Abandon campaign"
	_head_campaign_btn.text = "× Abandon campaign"
	_fight_btn0.text = "» Next round"
	_top_fight_btn.text = "» Next round"
	_batch_btn.visible = false
	_fight_btn.text = "» Next round with these companies"
	_campaign_btn.text = "× Abandon campaign"
	for b in [_top_campaign_btn, _head_campaign_btn, _campaign_btn]:
		_style(b, "stop")


func campaign_ended() -> void:
	campaign_on = false
	round_label.visible = false
	_apply_locks()
	_top_campaign_btn.text = "» Start a campaign"
	_head_campaign_btn.text = "» Start a campaign (to the end)"
	_fight_btn0.text = "» Fight one battle"
	_top_fight_btn.text = "» New battle"
	_batch_btn.visible = true
	_fight_btn.text = "» Fight with these companies"
	_campaign_btn.text = "» Start a campaign (to the end)"
	for b in [_top_campaign_btn, _head_campaign_btn, _campaign_btn]:
		_accent(b)


## Between rounds (and at the end): what the round cost each side, the score so far, and
## what marches next.
func show_round(sm: Dictionary) -> void:
	for c in results_box.get_children():
		c.queue_free()
	var res: Dictionary = sm["result"]
	var over: bool = sm["over"]
	var cw: int = int(sm.get("campaign_winner", -1))
	if over:
		results_title.text = "The war is over - %s wins" % MatchManager.TEAM_NAMES[cw]
	else:
		results_title.text = "Battle %d on %d. %s - %s" % [sm["round"], sm["field_no"], sm["field"],
			("%s wins" % res["winner_name"]) if res["winner"] >= 0 else "drawn, the front holds"]
	# the front, animated: where the fight was, where it goes, what each army has left
	var fm := FrontMap.new()
	fm.fields = sm["front"]
	fm.from_no = int(sm["field_no"])
	fm.to_no = int(sm["next_field_no"])
	fm.winner = int(res["winner"])
	fm.men_before = sm["men_before"]
	fm.men_after = sm["men_after"]
	fm.men_full = [sm["men_full"], sm["men_full"]]
	fm.over = over
	fm.campaign_winner = cw
	results_box.add_child(fm)
	fm.play()
	if over:
		var why := Label.new()
		why.text = String(sm.get("why", ""))
		why.add_theme_font_size_override("font_size", 15)
		why.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[cw].lightened(0.45))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		results_box.add_child(why)
	_section(results_box, "This battle")
	var g2 := _stat_grid()
	var c: Array = sm["counts"]
	_stat_row(g2, "Stood their ground", [c[0]["stood"], c[1]["stood"]])
	_stat_row(g2, "Ran (and live)", [c[0]["ran"], c[1]["ran"]])
	_stat_row(g2, "Fell - gone for good", [c[0]["fell"], c[1]["fell"]])
	var st: Dictionary = res["stats"]
	_stat_row(g2, "Killed by ball / bayonet", ["%d / %d" % [st["kills"][0][0], st["kills"][0][1]], "%d / %d" % [st["kills"][1][0], st["kills"][1][1]]])
	_stat_row(g2, "Battles won, killed in the war", ["%d, %d" % [sm["wins"][0], sm["kills"][0]], "%d, %d" % [sm["wins"][1], sm["kills"][1]]])
	_stat_row(g2, "Men left in the army", [sm["men_after"][0], sm["men_after"][1]])
	for note in sm.get("merges", []):
		var ml := Label.new()
		ml.text = String(note)
		ml.add_theme_font_size_override("font_size", 12)
		ml.add_theme_color_override("font_color", Color(0.8, 0.78, 0.65))
		results_box.add_child(ml)
	if not over:
		_section(results_box, "Next: field %d of %d, %s" % [int(sm["next_field_no"]), (sm["front"] as Array).size(), sm["next_field"]])
		_next_head = results_box.get_child(results_box.get_child_count() - 1) as Label
		var fl := Label.new()
		fl.text = "%s  (It is on the map now.)" % Field.LAYOUT_HELP.get(sm["next_field"], "")
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.add_theme_font_size_override("font_size", 13)
		fl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		results_box.add_child(fl)
		_next_help = fl
		_fb_chips = {}
		var fb: Dictionary = sm.get("fall_back", {})
		if not fb.is_empty():
			var side: String = MatchManager.TEAM_NAMES[int(fb["side"])]
			var fbl := Label.new()
			fbl.text = "%s may fall back further and make a stand on ground of its choosing - every field given up is the enemy's, and losing on %s's last field loses the war." % [side, side]
			fbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fbl.add_theme_font_size_override("font_size", 13)
			fbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.55))
			results_box.add_child(fbl)
			var fr := HFlowContainer.new()
			fr.add_theme_constant_override("h_separation", 6)
			fr.add_theme_constant_override("v_separation", 6)
			results_box.add_child(fr)
			var fronts: Array = sm["front"]
			var order := range(int(fb["lo"]), int(fb["hi"]) + 1)
			if int(fb["side"]) == 0:
				order.reverse()   # Red falls back toward field 1: nearest first
			for no in order:
				var b := Button.new()
				b.toggle_mode = true
				b.button_pressed = no == int(sm["next_field_no"])
				b.text = "%d. %s" % [no, fronts[no - 1]]
				b.add_theme_font_size_override("font_size", 12)
				b.focus_mode = Control.FOCUS_NONE
				var n2: int = no
				b.pressed.connect(func(): fall_back_to.emit(n2))
				fr.add_child(b)
				_fb_chips[no] = b
			_cursor_for_tree(fr)
		# the armies: tap a company to put it forward or stand it down (any number fight)
		_army_secret = true
		for t in 2:
			var head := "%s's army - the lit companies fight next" % MatchManager.TEAM_NAMES[t]
			if String(commanders[t]) == "computer":
				head += " - how many and which it sends in is kept secret until the battle"
			else:
				head += "; tap to put a company in or stand it down - as many as you like"
			_section(results_box, head)
			var ab := HFlowContainer.new()
			ab.add_theme_constant_override("h_separation", 6)
			ab.add_theme_constant_override("v_separation", 6)
			results_box.add_child(ab)
			_army_boxes[t] = ab
			update_army(t, sm["armies"][t])
		var nl := Label.new()
		nl.text = "Drills and types of the companies going in can be changed under Edit Battalion."
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
		results_box.add_child(nl)
	_section(results_box, "The battles so far")
	var g5 := GridContainer.new()
	g5.columns = 4
	g5.add_theme_constant_override("h_separation", 14)
	results_box.add_child(g5)
	for h in ["#", "Field", "Winner", "How"]:
		_cell(g5, h, true)
	for b in sm["history"]:
		_cell(g5, str(b["round"]), false)
		_cell(g5, b["field"], false)
		var w: int = int(b["winner"])
		_cell(g5, b["winner_name"], false, MatchManager.TEAM_COLORS[w].lightened(0.5) if w >= 0 else Color(0.8, 0.8, 0.8))
		_cell(g5, "%s, %d:%02d" % [b["reason"], int(b["duration"]) / 60, int(b["duration"]) % 60], false)
	var row := HFlowContainer.new()
	results_box.add_child(row)
	if over:
		var again := _button("» New campaign")
		_accent(again)
		again.pressed.connect(func(): _close_overlays(); campaign_requested.emit())
		row.add_child(again)
		var sim := _button("« Back to simulation")
		sim.pressed.connect(func(): _close_overlays(); new_match_requested.emit())
		row.add_child(sim)
	else:
		var nxt := _button("» Next battle")
		_style(nxt, "go")
		nxt.pressed.connect(func(): _close_overlays(); next_round_requested.emit())
		row.add_child(nxt)
		var teams := _button("Edit Battalion")
		teams.pressed.connect(func(): _close_overlays(); teams_overlay.visible = true)
		row.add_child(teams)
		var quit := _button("× Abandon campaign")
		_style(quit, "stop")
		quit.pressed.connect(func(): _close_overlays(); campaign_abandoned.emit())
		row.add_child(quit)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	results_box.add_child(pad)
	results_overlay.visible = true


## The army picker: a card per company - men left, drill, type; lit if it fights next.
func update_army(t: int, view: Array) -> void:
	var ab: HFlowContainer = _army_boxes[t]
	if ab == null or not is_instance_valid(ab):
		return
	for ch in ab.get_children():
		ch.queue_free()
	for i in view.size():
		var a: Dictionary = view[i]
		var b := Button.new()
		b.toggle_mode = true
		var secret := String(commanders[t]) == "computer" and _army_secret
		b.button_pressed = bool(a["fights"]) and not secret
		b.text = "%s · %d men\n%s / %s" % [a["name"], int(a["men"]), a["drill"], a["type"]]
		if String(a.get("slot", "")) != "":
			b.text += "\n%s" % a["slot"]
		b.custom_minimum_size = Vector2(104, 0)
		b.add_theme_font_size_override("font_size", 12)
		b.disabled = int(a["men"]) == 0 or String(commanders[t]) == "computer"
		var idx := i
		b.pressed.connect(func(): army_pick.emit(t, idx))
		ab.add_child(b)
	_cursor_for_tree(ab)


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	parent.add_child(sp)
	parent.add_child(l)


func _stat_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	results_box.add_child(g)
	_cell(g, "", false)
	for t in 2:
		_cell(g, MatchManager.TEAM_NAMES[t], true, MatchManager.TEAM_COLORS[t].lightened(0.4))
	return g


func _stat_row(g: GridContainer, label_text: String, vals: Array) -> void:
	_cell(g, label_text, false)
	for t in 2:
		_cell(g, str(vals[t]), false, MatchManager.TEAM_COLORS[t].lightened(0.55))


func _cell(g: GridContainer, text: String, bold: bool, color: Color = Color(0.92, 0.92, 0.88)) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15 if bold else 14)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(90, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)


# ---------------------------------------------------------------- the camera pad

## Hold a button to keep turning, panning or zooming; Fit fits the whole field again.
var _pad_hold := {}          # button id -> held
var _pad_box: Control = null
const PAD_KEYS := {
	"rot_l": [KEY_Q], "rot_r": [KEY_E], "tilt_u": [KEY_R], "tilt_d": [KEY_F],
	"pan_u": [KEY_W, KEY_UP], "pan_d": [KEY_S, KEY_DOWN], "pan_l": [KEY_A, KEY_LEFT], "pan_r": [KEY_D, KEY_RIGHT],
	"zoom_in": [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD], "zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
}
const PAD_KEY_LABEL := {
	"rot_l": "Q", "rot_r": "E", "tilt_u": "R", "tilt_d": "F", "pan_u": "W", "pan_d": "S",
	"pan_l": "A", "pan_r": "D", "zoom_in": "+", "zoom_out": "-", "fit": "H",
}


## A text box has the keys: the view keys stand aside.
func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func build_cam_pad() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.position = Vector2(-12, -12)
	holder.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(holder)
	var toggle := _button("View")
	toggle.custom_minimum_size = Vector2(0, 40)
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	holder.add_child(grid)
	holder.add_child(toggle)
	_pad_box = grid
	toggle.pressed.connect(func(): grid.visible = not grid.visible)
	var cells := [
		["rot_l", "« Turn", "Turn left (Q)"], ["pan_u", "^", "Pan away (W or Up)"], ["rot_r", "Turn »", "Turn right (E)"], ["zoom_in", "+", "Zoom in (+ or =)"],
		["pan_l", "<", "Pan left (A or Left)"], ["fit", "Fit", "Fit the whole field, Red on the left (H)"], ["pan_r", ">", "Pan right (D or Right)"], ["zoom_out", "−", "Zoom out (-)"],
		["tilt_u", "Tilt ^", "Look down more (R)"], ["pan_d", "v", "Pan toward (S or Down)"], ["tilt_d", "Tilt v", "Look along the ground (F)"], ["", "", ""],
	]
	for c in cells:
		if c[0] == "":
			grid.add_child(Control.new())
			continue
		var b := Button.new()
		b.text = c[1]
		b.tooltip_text = c[2]
		b.custom_minimum_size = Vector2(56, 52)
		b.add_theme_font_size_override("font_size", 22 if String(c[1]).length() == 1 else 14)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.11, 0.13, 0.6)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override("normal", sb)
		var id: String = c[0]
		var kl := Label.new()   # the key, small, in the corner
		kl.text = PAD_KEY_LABEL[id]
		kl.add_theme_font_size_override("font_size", 10)
		kl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		kl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		kl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		kl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		kl.position = Vector2(-4, -2)
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(kl)
		if id == "fit":
			b.pressed.connect(func(): fit_requested.emit())
		else:
			b.button_down.connect(func(): _pad_hold[id] = true)
			b.button_up.connect(func(): _pad_hold.erase(id))
		grid.add_child(b)
	_cursor_for_tree(holder)


func _pad_tick(delta: float) -> void:
	# a panel open over the field (Edit Battalion, a result): no view controls, no camera moves
	var open := (teams_overlay != null and teams_overlay.visible) or (results_overlay != null and results_overlay.visible)
	if _pad_box != null:
		var holder := _pad_box.get_parent() as Control
		if holder.visible == open:
			holder.visible = not open
			_pad_hold.clear()
	if cam != null:
		cam.input_blocked = open
	if cam == null or open:
		return
	var held := _pad_hold.duplicate()
	if not _typing():
		for id in PAD_KEYS:
			for k in PAD_KEYS[id]:
				if Input.is_physical_key_pressed(k):
					held[id] = true
	if held.is_empty():
		return
	var rate := delta / maxf(Engine.time_scale, 0.001)   # the pad runs on real time, not battle time
	for id in held:
		match id:
			"rot_l":
				cam.rotate_view(1.4 * rate)
			"rot_r":
				cam.rotate_view(-1.4 * rate)
			"tilt_u":
				cam.rotate_view(0.0, 0.8 * rate)
			"tilt_d":
				cam.rotate_view(0.0, -0.8 * rate)
			"zoom_in":
				cam.zoom_view(1.0 - 0.9 * rate)
			"zoom_out":
				cam.zoom_view(1.0 + 0.9 * rate)
			"pan_l":
				cam.pan_view(Vector2(-500.0, 0.0) * rate)
			"pan_r":
				cam.pan_view(Vector2(500.0, 0.0) * rate)
			"pan_u":
				cam.pan_view(Vector2(0.0, 500.0) * rate)
			"pan_d":
				cam.pan_view(Vector2(0.0, -500.0) * rate)


## After a fall-back: the round panel's "Next" names the new field.
func show_next_field(no: int, total: int, layout: String) -> void:
	if _next_head != null and is_instance_valid(_next_head):
		_next_head.text = "Next: field %d of %d, %s" % [no, total, layout]
	if _next_help != null and is_instance_valid(_next_help):
		_next_help.text = "%s  (It is on the map now.)" % Field.LAYOUT_HELP.get(layout, "")
	for k in _fb_chips:
		var b: Button = _fb_chips[k]
		if is_instance_valid(b):
			b.set_pressed_no_signal(int(k) == no)
