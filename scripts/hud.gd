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
signal epic_requested
signal field_chosen(layout: String)
signal army_pick(t: int, i: int)
signal fall_back_to(no: int)
signal simulate_requested
signal simulate_rest_requested

const PRESET_LIST := ["Regulars", "Skirmishers", "Shock", "Militia", "Veterans", "Balanced", "Random"]
const TYPE_LIST := ["Even", "Marksman", "Grenadier", "Runner", "Ironside", "Brawler", "Scout", "Shinobi", "Random"]
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
var _sound_btn: Button
var _blood_btn: Button
var size_labels: Array[Label] = []
var size_sliders: Array = [null, null]
var _strip := [null, null]         # the company strip per side
var _bat_chips := [{}, {}]
var _army_locked := [[], []]   # controls that would break the army mapping: locked in a campaign
var front: Array = []          # the campaign's front, field 1 first
var _army_boxes := [null, null]
var _next_head: Label = null
var _war_over := false       # the war-end panel stays until a new campaign is begun
var _army_secret := false     # the computer's picks are hidden on the round panel
var _next_help: Label = null
var _fb_chips := {}           # field no -> chip
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
var _top_epic_btn: Button
var _sim_rest_btn: Button
var _setup_epic_btn: Button
var epic_on := false
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
		if is_instance_valid(_field_chips[n]):
			_field_chips[n].button_pressed = n == layout
	if _field_help != null and is_instance_valid(_field_help):
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
	_top_epic_btn = _button("» Start an epic")
	_accent(_top_epic_btn)
	_top_epic_btn.pressed.connect(func():
		_close_overlays()
		epic_requested.emit())
	row.add_child(_top_epic_btn)
	var teams_btn := _button("Armies")
	teams_btn.pressed.connect(func(): open_setup(""))
	row.add_child(teams_btn)
	var fight := _button("» Choose companies")
	_style(fight, "go")
	fight.pressed.connect(func(): show_pick())
	row.add_child(fight)
	_top_fight_btn = fight
	for s in [1.0, 2.0, 4.0, 8.0]:
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
	_sim_rest_btn = _button("Sim the rest")
	_sim_rest_btn.tooltip_text = "Finish this battle unseen, at full speed, and go straight to the result"
	_sim_rest_btn.pressed.connect(func(): simulate_rest_requested.emit())
	row.add_child(_sim_rest_btn)
	var fit := _button("Fit view")
	fit.pressed.connect(func(): fit_requested.emit())
	row.add_child(fit)
	_sound_btn = _button("Sound on")
	_sound_btn.tooltip_text = "Turn the sound of the battle on or off (M)"
	_sound_btn.pressed.connect(func(): toggle_sound())
	row.add_child(_sound_btn)
	_blood_btn = _button("Blood on")
	_blood_btn.tooltip_text = "Show or hide the blood (B)"
	_blood_btn.pressed.connect(func(): toggle_blood())
	row.add_child(_blood_btn)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 14)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(clock_row)
	clock_row.add_child(status_label)
	round_label = Label.new()
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.add_theme_font_size_override("font_size", 15)
	round_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	round_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	round_label.add_theme_constant_override("shadow_offset_x", 1)
	round_label.add_theme_constant_override("shadow_offset_y", 1)
	round_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_label.visible = false
	clock_row.add_child(round_label)
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
	_build_pick_overlay()


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


## Every control says what it does when the pointer rests on it.
const TIPS := {
	"» Start a campaign": "A war along a front of eleven fields: win a battle and the fight moves into the enemy's country; take their last field, or leave them nobody, to win",
	"Armies": "Set up both armies: who commands each side, and every company's drill and type",
	"» Choose companies": "Pick the field and which companies go into the next battle",
	"Pause": "Stop the battle (the view still moves)",
	"Resume": "Carry on with the battle",
	"Fit view": "Show the whole field, Red on the left (H)",
	"« Close": "Close this panel (Esc)",
	"» Single battle": "One battle with the companies you choose - fresh men every time",
	"You": "You command this side: you set its drills and choose which companies go in",
	"Computer": "The computer commands this side: in a campaign it chooses its own drills and companies, in secret",
	"Read the drill": "Show the drill's written rules: what the sergeant and each man do, and when",
	"Fine-tune the type": "Set the four skills of this company's men by hand (they share one budget)",
	"Copy company": "Give every company in this army this company's drill and type",
	"« Back to the armies": "Back to the Armies screen",
	"Freshest four": "Send in the four companies with the most men left",
	"Everyone": "Send in every company that still has men",
	"» Fight": "Start the battle with the companies chosen",
	"× Abandon campaign": "End the war now; the armies go back to full strength",
	"» Another battle": "Fight again with the same companies",
	"» Sim ×": "Run the same battle that many times again, fast, and see the numbers",
	"» New campaign": "Start a new war with the armies as they are set up",
	"» Start an epic": "One field for the whole war. Each side has 50 companies (the twelve on the Armies screen, repeated); before each battle you send in up to 10, the computer chooses its own. What is left of a company fights again later. The war ends when a side has nobody left.",
	"» New epic": "Start a new epic war on the field on the map",
	"» Choose companies for battle": "On to the next battle: choose the companies",
	"View": "Show or hide the view controls",
}


func _tip_for(b: BaseButton) -> void:
	if b.tooltip_text != "" or not (b is Button):
		return
	var tx: String = (b as Button).text
	if tx.ends_with("×") and tx.length() <= 3:
		b.tooltip_text = "Battle speed: %s real time" % tx
		return
	var best := ""
	for k in TIPS:
		if tx.begins_with(k) and k.length() > best.length():
			best = k
	if best != "":
		b.tooltip_text = TIPS[best]


## The hover text of a company card: its drill and type in words.
func _card_tip(a: Dictionary) -> String:
	var d: Drill = Drill.named(String(a["drill"]))
	return "Company %s - %s: %s\nType %s: %s" % [a["name"], a["drill"], d.about if d != null else "", a["type"], SoldierType.TYPE_HELP.get(String(a["type"]), "a build of your own")]


func _cursor_for(n: Node) -> void:
	if n is BaseButton:
		_tip_for(n as BaseButton)
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
	ov.visibility_changed.connect(func(): _top.visible = not _any_overlay())
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
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size = Vector2(160, 0)   # a wrapping label in a row needs a width to wrap to
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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


# ---------------------------------------------------------------- the Armies screen
## Two steps, as in a roster game: the Armies screen is where a company is made - its drill
## (how it fights) and its type (what its men are good at) - and Choose Companies, before
## every battle, is only who goes in. A company looks the same card on both.

var game: Node = null               # main: owns the armies
var _sel := [0, 0]                  # the company being edited, per side
var _side_box := [null, null]       # per side: the panel's contents
var _roster_box := [null, null]
var _editor_box := [null, null]
var _finetune := [false, false]
var _type_val_labels := [{}, {}]
var _type_sliders := [{}, {}]
var _type_help := [null, null]
var _setup_scroll: ScrollContainer
var _setup_camp_btn: Button
var _setup_single_btn: Button
var _men_note: Label

var _pick_overlay: Control
var _pick_box: VBoxContainer
var _pick_title: Label
var _pick_scroll: ScrollContainer


func _any_overlay() -> bool:
	return (teams_overlay != null and teams_overlay.visible) or (results_overlay != null and results_overlay.visible) \
		or (_pick_overlay != null and _pick_overlay.visible)


func _build_teams_overlay() -> void:
	var parts := _overlay("Armies")
	teams_overlay = parts[0]
	var box: VBoxContainer = parts[1]
	_setup_scroll = box.get_parent() as ScrollContainer
	_setup_note = Label.new()
	_setup_note.add_theme_font_size_override("font_size", 16)
	_setup_note.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	_setup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_note.visible = false
	box.add_child(_setup_note)
	var note := Label.new()
	note.text = "Twelve companies an army - point at anything for what it means."
	_hover(note, "Each army is twelve companies. Make each one here: its drill (how it fights - written rules for when to fire, charge, take cover and give ground) and its type (what its men are good at). Before every battle you only choose which companies go in; they line up by themselves, left to right in letter order, and a fifth and more form a second line.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	box.add_child(note)
	var srow := HFlowContainer.new()
	box.add_child(srow)
	var sl := Label.new()
	sl.text = "Men in a company: "
	sl.add_theme_font_size_override("font_size", 14)
	srow.add_child(sl)
	for men in [10, 20]:
		var b := Button.new()
		b.text = "%d" % men
		b.tooltip_text = "Companies of %d men - %d a side with four companies in (set before a campaign starts)" % [men, men * 4]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(56, 36)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			if game != null:
				game.set_company_men(men)
			refresh_setup())
		srow.add_child(b)
		_men_chips[men] = b
	_men_note = Label.new()
	_men_note.add_theme_font_size_override("font_size", 12)
	_men_note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	srow.add_child(_men_note)
	var cols := HFlowContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("h_separation", 8)
	cols.add_theme_constant_override("v_separation", 8)
	box.add_child(cols)
	for t in 2:
		var frame := _side_frame(t)
		var vb := VBoxContainer.new()
		frame.add_child(vb)
		_side_box[t] = vb
		cols.add_child(frame)
	var foot := HFlowContainer.new()
	box.add_child(foot)
	_setup_camp_btn = _button("» Start a campaign")
	_setup_camp_btn.custom_minimum_size = Vector2(0, 46)
	_accent(_setup_camp_btn)
	_setup_camp_btn.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			show_pick()
		else:
			campaign_requested.emit())
	foot.add_child(_setup_camp_btn)
	_setup_epic_btn = _button("» Start an epic")
	_setup_epic_btn.custom_minimum_size = Vector2(0, 46)
	_accent(_setup_epic_btn)
	_setup_epic_btn.pressed.connect(func():
		_close_overlays()
		epic_requested.emit())
	foot.add_child(_setup_epic_btn)
	_setup_single_btn = _button("» Single battle")
	_setup_single_btn.custom_minimum_size = Vector2(0, 46)
	_style(_setup_single_btn, "go")
	_setup_single_btn.pressed.connect(func():
		if campaign_on:
			_close_overlays()
			campaign_abandoned.emit()
		else:
			show_pick())
	foot.add_child(_setup_single_btn)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	box.add_child(pad)


func _side_frame(t: int) -> PanelContainer:
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
	return frame


## Rebuild the Armies screen from the armies (keeping the page where it was scrolled to).
func refresh_setup() -> void:
	if game == null or teams_overlay == null:
		return
	var keep := _setup_scroll.scroll_vertical
	for men in _men_chips:
		_men_chips[men].button_pressed = int(game.COMPANY_MEN) == men
		_men_chips[men].disabled = campaign_on
	_men_note.text = "  (%d a side with four companies in; fixed once a campaign starts)" % (int(game.COMPANY_MEN) * 4)
	for t in 2:
		_fill_side(t)
	_setup_epic_btn.visible = not campaign_on
	if campaign_on:
		_setup_camp_btn.text = "» Back to choosing companies"
		_style(_setup_camp_btn, "go")
		_setup_single_btn.text = "× Abandon epic" if epic_on else "× Abandon campaign"
		_style(_setup_single_btn, "stop")
	else:
		_setup_camp_btn.text = "» Start a campaign"
		_accent(_setup_camp_btn)
		_setup_single_btn.text = "» Single battle"
		_style(_setup_single_btn, "go")
	_restore_scroll(_setup_scroll, keep)


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = v


## A computer commander sets its own drills and types in a campaign.
func _locked(t: int) -> bool:
	return campaign_on and String(commanders[t]) == "computer"


func _fill_side(t: int) -> void:
	var vb: VBoxContainer = _side_box[t]
	for ch in vb.get_children():
		ch.queue_free()
	var name_l := Label.new()
	name_l.text = "%s army" % MatchManager.TEAM_NAMES[t]
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.45))
	vb.add_child(name_l)
	# who commands it
	var crow := HFlowContainer.new()
	vb.add_child(crow)
	var cl := Label.new()
	cl.text = "Commander: "
	cl.add_theme_font_size_override("font_size", 14)
	crow.add_child(cl)
	for who in ["you", "computer"]:
		var b := _chip("You" if who == "you" else "Computer", commanders[t] == who)
		b.pressed.connect(func(): _set_commander(t, who); refresh_setup())
		crow.add_child(b)
	_hover(cl, "In a campaign the computer chooses its own drills, types and how many companies go in - in secret." if commanders[t] == "computer" else "You choose everything, before every battle.")
	var locked := _locked(t)
	# quick fill
	var fl := Label.new()
	fl.text = "Fill the whole army like:"
	fl.add_theme_font_size_override("font_size", 14)
	vb.add_child(fl)
	var frow := HFlowContainer.new()
	vb.add_child(frow)
	for bn in MatchManager.BATTALIONS:
		var b := _chip(bn, false)
		b.tooltip_text = MatchManager.BATTALION_HELP.get(bn, "")
		b.disabled = locked
		b.pressed.connect(func(): game.fill_army(t, bn); refresh_setup())
		frow.add_child(b)
	# the companies
	var rl := Label.new()
	rl.text = "The companies - tap one to change it"
	rl.add_theme_font_size_override("font_size", 14)
	vb.add_child(rl)
	var roster := HFlowContainer.new()
	roster.add_theme_constant_override("h_separation", 6)
	roster.add_theme_constant_override("v_separation", 6)
	vb.add_child(roster)
	_roster_box[t] = roster
	_fill_roster(t)
	var ed := VBoxContainer.new()
	vb.add_child(ed)
	_editor_box[t] = ed
	_fill_editor(t)
	_cursor_for_tree(vb)


func _fill_roster(t: int) -> void:
	var roster: HFlowContainer = _roster_box[t]
	if roster == null or not is_instance_valid(roster):
		return
	for ch in roster.get_children():
		ch.queue_free()
	var ar: Array = game.armies[t]
	for i in ar.size():
		var a: Dictionary = ar[i]
		var b := _company_card(a, campaign_on)
		b.button_pressed = i == _sel[t]
		b.tooltip_text = _card_tip(a) + "\nClick to change this company's drill and type."
		var idx := i
		b.pressed.connect(func(): _sel[t] = idx; _fill_roster(t); _fill_editor(t))
		roster.add_child(b)
	_cursor_for_tree(roster)


## The card a company is everywhere: its letter, its drill, its type (and men, when they count).
func _company_card(a: Dictionary, show_men: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	var men := (" · %d" % (a["men"] as Array).size()) if show_men else ""
	var rk: String = String(a.get("rank", "Auto"))
	if rk == "Auto" or rk == "":
		rk = MatchManager.default_rank(String(a["type"]))
	b.text = "%s%s\n%s\n%s\n%s" % [a["name"], men, a["drill"], a["type"], rk]
	b.custom_minimum_size = Vector2(96, 0)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _fill_editor(t: int) -> void:
	var ed: VBoxContainer = _editor_box[t]
	if ed == null or not is_instance_valid(ed):
		return
	for ch in ed.get_children():
		ch.queue_free()
	_type_sliders[t] = {}
	_type_val_labels[t] = {}
	var i: int = _sel[t]
	var a: Dictionary = game.armies[t][i]
	var locked := _locked(t)
	var head := Label.new()
	head.text = "Company %s" % a["name"]
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", MatchManager.TEAM_COLORS[t].lightened(0.55))
	ed.add_child(head)
	if locked:
		_small(ed, "The computer commands this army in the campaign: it sets the drills and types.")
	# 1. the drill
	var dl := Label.new()
	dl.text = "Drill - how it fights"
	dl.add_theme_font_size_override("font_size", 15)
	ed.add_child(dl)
	var drow := HFlowContainer.new()
	ed.add_child(drow)
	for n in Drill.names():
		var b := _chip(n, n == String(a["drill"]))
		var dn: Drill = Drill.named(n)
		b.tooltip_text = (dn.about if dn != null else n) + "  (its own type: %s)" % (dn.type_name if dn != null else "")
		b.disabled = locked
		b.pressed.connect(func(): game.set_company(t, i, n, ""); _fill_roster(t); _fill_editor(t))
		drow.add_child(b)
	var d: Drill = Drill.named(String(a["drill"]))
	_hover(dl, "%s: %s" % [a["drill"], d.about if d != null else ""])
	var read := _button("Read the drill")
	read.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	read.pressed.connect(func(): show_drill_named(String(a["drill"]), t))
	ed.add_child(read)
	# 2. the type
	var tl := Label.new()
	tl.text = "Type - what its men are good at"
	tl.add_theme_font_size_override("font_size", 15)
	ed.add_child(tl)
	var trow := HFlowContainer.new()
	ed.add_child(trow)
	for n in TYPE_LIST:
		var b := _chip(n, n == String(a["type"]))
		b.tooltip_text = String(SoldierType.TYPE_HELP.get(n, n))
		b.disabled = locked
		b.pressed.connect(func(): game.set_company(t, i, "", n); _fill_roster(t); _fill_editor(t))
		trow.add_child(b)
	_type_help[t] = tl   # the type's description and numbers show when pointed at
	# 3. where it stands in the order of battle
	var rkl := Label.new()
	rkl.text = "Rank - where it stands"
	rkl.add_theme_font_size_override("font_size", 15)
	ed.add_child(rkl)
	_hover(rkl, "Front: first in the line - bayonet men. Line: the main line. Back: behind the others, firing past them - shooters; a back rank stays behind the front while the front stands. Held back: kept in reserve; the captain sends it in where the line is going worst or after a running enemy. Auto: by its type (Brawler, Grenadier, Ironside, Shinobi in front; Marksman, Scout at the back; the rest in the line).")
	var rrow := HFlowContainer.new()
	ed.add_child(rrow)
	var cur_rank: String = String(a.get("rank", "Auto"))
	for rn in MatchManager.RANKS:
		var label: String = rn if rn != "Auto" else "Auto (%s)" % MatchManager.default_rank(String(a["type"]))
		var rb := _chip(label, rn == cur_rank or (cur_rank == "" and rn == "Auto"))
		rb.disabled = locked
		var rr: String = rn
		rb.pressed.connect(func(): game.set_company_rank(t, i, rr); _fill_roster(t); _fill_editor(t))
		rrow.add_child(rb)
	var ft := _chip("Fine-tune the type" + (" (hide)" if _finetune[t] else ""), _finetune[t])
	ft.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ft.pressed.connect(func(): _finetune[t] = not _finetune[t]; _fill_editor(t))
	ed.add_child(ft)
	if _finetune[t]:
		_small(ed, "The four always add up to the same budget: more of one is less of the others.")
		for p in SoldierType.PROPS:
			var row := HBoxContainer.new()
			ed.add_child(row)
			var l := Label.new()
			l.text = String(p).capitalize()
			l.custom_minimum_size = Vector2(84, 0)
			l.add_theme_font_size_override("font_size", 14)
			row.add_child(l)
			var s := HSlider.new()
			s.min_value = 0.0
			s.max_value = 0.85
			s.step = 0.01
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.custom_minimum_size = Vector2(0, 30)
			s.editable = not locked
			s.tooltip_text = String(SoldierType.PROP_HELP[p])
			row.add_child(s)
			var v := Label.new()
			v.custom_minimum_size = Vector2(44, 0)
			v.add_theme_font_size_override("font_size", 13)
			row.add_child(v)
			_type_sliders[t][p] = s
			_type_val_labels[t][p] = v
			var pp: String = p
			s.value_changed.connect(func(val: float): _on_type_slider2(t, pp, val))
			_hover(l, SoldierType.PROP_HELP[p])
	_update_type_bits(t)
	# 3. the rest of the army
	var cp := _button("Copy company %s to the whole army" % a["name"])
	cp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cp.disabled = locked
	cp.pressed.connect(func(): game.copy_to_all(t, i); _fill_roster(t); _fill_editor(t))
	ed.add_child(cp)
	_cursor_for_tree(ed)


func _on_type_slider2(t: int, p: String, v: float) -> void:
	if _updating:
		return
	var a: Dictionary = game.armies[t][_sel[t]]
	var ty: SoldierType = a["type_obj"]
	ty.set_and_rebalance(p, v)
	a["type"] = ty.label()
	_update_type_bits(t)
	_fill_roster(t)


## The type's help line and slider readings, without rebuilding (a slider being dragged stays put).
func _update_type_bits(t: int) -> void:
	var a: Dictionary = game.armies[t][_sel[t]]
	var ty: SoldierType = a["type_obj"]
	var sk: float = ty.skill("accuracy")
	if _type_help[t] != null and is_instance_valid(_type_help[t]):
		_hover(_type_help[t], "")
		_type_help[t].tooltip_text = "%s. On the range he hits a man %d%% of the time at 100 m; reloads in %d s." % [
			SoldierType.TYPE_HELP.get(String(a["type"]), "A build of your own"),
			int(round(100.0 * Ballistics.p_range(sk, 100.0))), int(round(Soldier.RELOAD * 1.2 / (0.8 + 0.4 * sk)))]
	_updating = true
	for p in _type_sliders[t]:
		_type_sliders[t][p].value = ty.get_prop(p)
		_type_val_labels[t][p].text = "%.2f" % ty.get_prop(p)
	_updating = false


func _chip(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _small(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


## The drill's text, as written: what the company will do and when.
func show_drill_named(dn: String, t: int) -> void:
	var d: Drill = Drill.named(dn)
	if d == null:
		return
	for c in results_box.get_children():
		c.queue_free()
	results_title.text = "%s - the drill" % d.name
	var who := Label.new()
	who.text = "Rules are read top to bottom; the first that holds and can be done decides. Anything no rule decides falls to the dials."
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
	var back := _button("« Back to the armies")
	back.pressed.connect(func(): _close_overlays(); open_setup(""))
	row.add_child(back)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	results_box.add_child(pad)
	_close_overlays()
	results_overlay.visible = true


# ---------------------------------------------------------------- Choose Companies

func _build_pick_overlay() -> void:
	var parts := _overlay("Choose companies")
	_pick_overlay = parts[0]
	_pick_box = parts[1]
	_pick_title = parts[2]
	_pick_scroll = _pick_box.get_parent() as ScrollContainer


func close_pick() -> void:
	if _pick_overlay != null:
		_pick_overlay.visible = false


func refresh_pick() -> void:
	if _pick_overlay != null and _pick_overlay.visible:
		show_pick()


## Before every battle: who goes in. In a campaign, also where (the fall-back after a loss);
## in a single battle, the field.
func show_pick() -> void:
	if game == null:
		return
	var keep := _pick_scroll.scroll_vertical if _pick_overlay.visible else 0
	for c in _pick_box.get_children():
		c.queue_free()
	var camp: bool = campaign_on
	if camp:
		var rno: int = int(game.campaign_round) + 1
		var fno: int = int(game.campaign_field)
		_pick_title.text = "Battle %d - field %d of %d, %s" % [rno, fno, front.size(), front[fno - 1]]
		if epic_on:
			_pick_title.text = "Epic battle %d on %s - up to %d companies a side" % [rno, front[fno - 1], int(game.EPIC_PICK)]
		var rl := _small(_pick_box, _round_text + "  (point here for the field)")
		_hover(rl, "%s: %s  (It is on the map behind this panel.)" % [front[fno - 1], Field.LAYOUT_HELP.get(front[fno - 1], "")])
		var fb: Dictionary = game._fall_back
		if not fb.is_empty():
			var side: String = MatchManager.TEAM_NAMES[int(fb["side"])]
			_section(_pick_box, "%s may fall back and choose its ground" % side)
			_hover(_pick_box.get_child(_pick_box.get_child_count() - 1), "Every field given up is the enemy's, and losing on %s's last field loses the war." % side)
			var fr := HFlowContainer.new()
			_pick_box.add_child(fr)
			var order := range(int(fb["lo"]), int(fb["hi"]) + 1)
			if int(fb["side"]) == 0:
				order.reverse()   # Red falls back toward field 1: nearest first
			for no in order:
				var b := _chip("%d. %s" % [no, front[no - 1]], no == fno)
				var n2: int = no
				b.pressed.connect(func(): fall_back_to.emit(n2))
				fr.add_child(b)
	else:
		_pick_title.text = "Single battle - choose who goes in"
		_section(_pick_box, "The field")
		var frow := HFlowContainer.new()
		_pick_box.add_child(frow)
		_field_chips = {}
		for fname in Field.ALL_FIELDS:
			var fb2 := _chip(fname, false)
			fb2.tooltip_text = Field.LAYOUT_HELP.get(fname, "")
			fb2.pressed.connect(func(): field_chosen.emit(fname))
			frow.add_child(fb2)
			_field_chips[fname] = fb2
		_field_help = _small(_pick_box, "")
		_field_help.visible = false   # each field's description shows on its button
		mark_field(game.field.layout_name)
	for t in 2:
		var ar: Array = game.armies[t]
		var secret: bool = camp and String(commanders[t]) == "computer"
		var n := 0
		var men := 0
		for a in ar:
			if a["fights"] and (a["men"] as Array).size() > 0:
				n += 1
				men += (a["men"] as Array).size()
		if secret:
			_section(_pick_box, "%s - the computer chooses in secret" % MatchManager.TEAM_NAMES[t])
		elif camp and epic_on:
			var left := 0
			var standing := 0
			for a in ar:
				left += (a["men"] as Array).size()
				if (a["men"] as Array).size() > 0:
					standing += 1
			_section(_pick_box, "%s - %d of up to %d companies going in, %d men  (army: %d companies, %d men left)" % [
				MatchManager.TEAM_NAMES[t], n, int(game.EPIC_PICK), men, standing, left])
		else:
			_section(_pick_box, "%s - %d companies, %d men going in" % [MatchManager.TEAM_NAMES[t], n, men])
		var qrow := HFlowContainer.new()
		_pick_box.add_child(qrow)
		if not secret:
			var fresh := _chip("Freshest ten" if camp and epic_on else "Freshest four", false)
			fresh.pressed.connect(func(): game.pick_freshest(t))
			qrow.add_child(fresh)
			if not (camp and epic_on):
				var all := _chip("Everyone", false)
				all.pressed.connect(func(): game.pick_all(t))
				qrow.add_child(all)
			var hint := Label.new()
			hint.text = "  or tap companies in and out (they line up left to right, A first)"
			hint.add_theme_font_size_override("font_size", 12)
			hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
			qrow.add_child(hint)
		var ab := HFlowContainer.new()
		ab.add_theme_constant_override("h_separation", 6)
		ab.add_theme_constant_override("v_separation", 6)
		_pick_box.add_child(ab)
		for i in ar.size():
			var a: Dictionary = ar[i]
			var b := _company_card(a, camp)
			b.button_pressed = bool(a["fights"]) and not secret
			b.disabled = secret or (a["men"] as Array).is_empty()
			b.tooltip_text = "Company %s: what it is and how many go in is the computer's secret until the battle." % a["name"] if secret \
				else _card_tip(a) + ("\nIt has no men left." if (a["men"] as Array).is_empty() else "\nClick to send it in or stand it down.")
			if secret:
				b.text = "%s · %d\ndrill unknown\n" % [a["name"], (a["men"] as Array).size()]   # its drills are its own business
			var idx := i
			b.pressed.connect(func(): army_pick.emit(t, idx))
			ab.add_child(b)
		# the play: one plan the whole army follows (or the general's own choice)
		if secret:
			var sl := _small(_pick_box, "Plan: the computer's general decides - and may change his mind (shown during the battle)")
			sl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
		elif manager != null:
			var prow := HFlowContainer.new()
			prow.add_theme_constant_override("h_separation", 6)
			_pick_box.add_child(prow)
			var pl := Label.new()
			pl.text = "Plan:"
			pl.add_theme_font_size_override("font_size", 13)
			_hover(pl, "One play the whole army carries out together, over each company's own drill. When one company charges, the others go in with it (except under Drill book).")
			prow.add_child(pl)
			for pname in General.PLAYS:
				var pc := _chip(pname, String(manager.plays[t]) == pname)
				pc.tooltip_text = General.HELP.get(pname, "")
				var side := t
				var pn: String = pname
				pc.pressed.connect(func():
					manager.plays[side] = pn
					show_pick())
				prow.add_child(pc)
			if String(manager.plays[t]) != General.CHOICE:
				var ad := _chip("General may change it", bool(manager.adapt[t]))
				ad.tooltip_text = "On: your plan is how the battle opens, and the general changes it if the battle turns (he says why at the top). Off: your plan holds to the end."
				var side2 := t
				ad.pressed.connect(func():
					manager.adapt[side2] = not bool(manager.adapt[side2])
					show_pick())
				prow.add_child(ad)
	var row := HFlowContainer.new()
	_pick_box.add_child(row)
	var fight := _button("» Fight")
	fight.custom_minimum_size = Vector2(120, 46)
	_style(fight, "go")
	fight.pressed.connect(func():
		_close_overlays()
		if campaign_on:
			next_round_requested.emit()
		else:
			new_match_requested.emit())
	row.add_child(fight)
	var simb := _button("Simulate battle")
	simb.custom_minimum_size = Vector2(0, 46)
	simb.tooltip_text = "Fight this battle at full speed without drawing it, straight to the results"
	simb.pressed.connect(func(): _close_overlays(); simulate_requested.emit())
	row.add_child(simb)
	if not camp:
		var sim := _button("Sim ×%d" % BATCH_N)
		sim.custom_minimum_size = Vector2(0, 46)
		sim.tooltip_text = "Fight it %d times, fast, and see the numbers" % BATCH_N
		sim.pressed.connect(func(): _close_overlays(); batch_requested.emit(BATCH_N))
		row.add_child(sim)
	var armies_b := _button("Armies")
	armies_b.custom_minimum_size = Vector2(0, 46)
	armies_b.pressed.connect(func(): open_setup(""))
	row.add_child(armies_b)
	if camp:
		var quit := _button("× Abandon campaign")
		quit.custom_minimum_size = Vector2(0, 46)
		_style(quit, "stop")
		quit.pressed.connect(func(): _close_overlays(); campaign_abandoned.emit())
		row.add_child(quit)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	_pick_box.add_child(pad)
	_cursor_for_tree(_pick_box)
	if not _pick_overlay.visible:
		_close_overlays()
		_pick_overlay.visible = true
	_restore_scroll(_pick_scroll, keep)


func _build_results_overlay() -> void:
	var parts := _overlay("Result")
	results_overlay = parts[0]
	results_box = parts[1]
	results_title = parts[2]


func _close_overlays() -> void:
	teams_overlay.visible = false
	results_overlay.visible = false
	if _pick_overlay != null:
		_pick_overlay.visible = false


func toggle_sound() -> void:
	var fx: BattleFx = manager.fx if manager != null else null
	if fx == null:
		return
	fx.muted = not fx.muted
	_sound_btn.text = "Sound off" if fx.muted else "Sound on"


func toggle_blood() -> void:
	var fx: BattleFx = manager.fx if manager != null else null
	if fx == null:
		return
	fx.gore = not fx.gore
	fx.visible = fx.gore
	_blood_btn.text = "Blood on" if fx.gore else "Blood off"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not _typing():
		if event.physical_keycode == KEY_M:
			toggle_sound()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_B:
			toggle_blood()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_H or event.physical_keycode == KEY_HOME):
		var shut := not _any_overlay()
		if shut and not _typing():
			fit_requested.emit()
			get_viewport().set_input_as_handled()
			return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _war_over and results_overlay.visible:
		return
	if _any_overlay():
		_close_overlays()
		get_viewport().set_input_as_handled()


func on_match_started() -> void:
	_close_overlays()
	_setup_note.visible = false
	set_status("The lines are drawn.")


func _set_speed(s: float) -> void:
	for i in speed_buttons.size():
		speed_buttons[i].button_pressed = is_equal_approx([1.0, 2.0, 4.0, 8.0][i], s)


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
	update_sim_cover()
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
		var txt := "%s: %d/%d standing (%d in line) · %s · shots %d/%d" % [
			MatchManager.TEAM_NAMES[t], alive, int(manager.side_n[t]), fighting, ", ".join(modes), st["hits"][t], st["shots"][t]]
		var g: General = manager.generals[t]
		if g != null:
			txt += "\n" + g.label()
		team_labels[t].text = txt
	if _sim_rest_btn != null:
		_sim_rest_btn.visible = manager.running
	if manager.running:
		var clock := "%d:%02d" % [int(manager.elapsed) / 60, int(manager.elapsed) % 60]
		if manager.pursuit_since >= 0.0:
			var lost := 0 if manager.fighting(0).is_empty() else 1
			clock += "  ·  %s has broken - %d running for the rear, %s in pursuit (%d s)" % [MatchManager.TEAM_NAMES[lost],
				manager.alive_count(lost), MatchManager.TEAM_NAMES[1 - lost], int(MatchManager.PURSUIT - (manager.elapsed - manager.pursuit_since))]
		status_label.text = (_batch_text + " · " + clock) if _batch_text != "" else clock


func show_result(res: Dictionary) -> void:
	_war_over = false
	_results_close().visible = true
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
	# the books: by company, then by type
	var rows := battle_unit_rows(res)
	unit_table(results_box, "The companies", rows)
	type_table(results_box, "By troop type", rows)
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
	var again := _button("» Another battle")
	_style(again, "go")
	again.pressed.connect(func(): show_pick())
	row.add_child(again)
	var teams := _button("Armies")
	teams.pressed.connect(func(): open_setup(""))
	row.add_child(teams)
	results_overlay.visible = true


func show_batch(summary: Dictionary) -> void:
	_war_over = false
	_results_close().visible = true
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
	var again := _button("» Choose companies")
	_style(again, "go")
	again.pressed.connect(func(): show_pick())
	row.add_child(again)
	var batch := _button("» Sim ×%d again" % BATCH_N)
	_style(batch, "go")
	batch.pressed.connect(func(): _close_overlays(); batch_requested.emit(BATCH_N))
	row.add_child(batch)
	var teams := _button("Armies")
	teams.pressed.connect(func(): open_setup(""))
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
	if epic_on:
		_round_text = "Epic battle %d on %s · men left in the armies: Red %d, Blue %d" % [r, layout, men[0], men[1]]
		round_label.text = _round_text
		round_label.visible = true
		return
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


func set_plan(_field_no: int, _layout: String, _round_no: int = 0, _total: int = 0) -> void:
	pass


## The Armies screen, with a line at the top saying why it is open.
func open_setup(why: String) -> void:
	_close_overlays()
	_setup_note.text = why
	_setup_note.visible = why != ""
	refresh_setup()
	teams_overlay.visible = true
	status_label.text = "Nothing running." if not campaign_on else status_label.text


func _set_commander(t: int, who: String) -> void:
	commanders[t] = who


func campaign_started(epic := false) -> void:
	campaign_on = true
	epic_on = epic
	_top_epic_btn.visible = false
	_top_campaign_btn.text = "× Abandon epic" if epic else "× Abandon campaign"
	_style(_top_campaign_btn, "stop")


func campaign_ended() -> void:
	campaign_on = false
	_top_epic_btn.visible = true
	round_label.visible = false
	_top_campaign_btn.text = "» Start a campaign"
	_accent(_top_campaign_btn)


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
		if sm.get("epic", false):
			results_title.text = "Epic battle %d on %s - %s" % [sm["round"], sm["field"],
				("%s wins" % res["winner_name"]) if res["winner"] >= 0 else "drawn"]
	# the front, animated: where the fight was, where it goes, what each army has left
	var is_epic: bool = sm.get("epic", false)
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
	if is_epic:
		fm.fields = []   # an epic has no front: only each army's bar, draining to what it has left
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
	var own: Array = st.get("own_kills", [0, 0])
	if int(own[0]) + int(own[1]) > 0:
		_stat_row(g2, "Fell to their own side's stray balls", [own[0], own[1]])
		_hover(g2.get_child(g2.get_child_count() - 3), "Men killed by a ball from their own side - a miss flies on and hits whoever is in its path. These count in 'Fell' but not in the enemy's kills.")
	_stat_row(g2, "Battles won, killed in the war", ["%d, %d" % [sm["wins"][0], sm["kills"][0]], "%d, %d" % [sm["wins"][1], sm["kills"][1]]])
	_stat_row(g2, "Men left in the army", [sm["men_after"][0], sm["men_after"][1]])
	var b_rows := battle_unit_rows(res)
	unit_table(results_box, "This battle, company by company", b_rows)
	type_table(results_box, "This battle, by troop type", b_rows)
	var w_rows: Array = sm.get("war_units", [])
	if not w_rows.is_empty():
		unit_table(results_box, "The war so far, company by company" if not over else "The whole war, company by company", w_rows, true)
		type_table(results_box, "The war so far, by troop type" if not over else "The whole war, by troop type", w_rows)
	for note in sm.get("merges", []):
		var ml := Label.new()
		ml.text = String(note)
		ml.add_theme_font_size_override("font_size", 12)
		ml.add_theme_color_override("font_color", Color(0.8, 0.78, 0.65))
		results_box.add_child(ml)
	if not over and is_epic:
		_section(results_box, "Next: battle %d on %s - the same field" % [int(sm["round"]) + 1, sm["next_field"]])
	elif not over:
		_section(results_box, "Next: field %d of %d, %s" % [int(sm["next_field_no"]), (sm["front"] as Array).size(), sm["next_field"]])
		_next_head = results_box.get_child(results_box.get_child_count() - 1) as Label
		var fl := Label.new()
		fl.text = "%s  (It is on the map now.)" % Field.LAYOUT_HELP.get(sm["next_field"], "")
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.add_theme_font_size_override("font_size", 13)
		fl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
		results_box.add_child(fl)
		_next_help = fl
		fl.visible = false
		_hover(_next_head, "%s  (It is on the map now.)" % Field.LAYOUT_HELP.get(sm["next_field"], ""))
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
	_war_over = over
	_results_close().visible = not over   # the war is over: the only way on is a new one
	if over:
		var again := _button("» New epic" if is_epic else "» New campaign")
		_accent(again)
		again.pressed.connect(func():
			_war_over = false
			_results_close().visible = true
			_close_overlays()
			if is_epic:
				epic_requested.emit()
			else:
				campaign_requested.emit())
		row.add_child(again)
	else:
		var nxt := _button("» Choose companies for battle %d" % (int(sm["round"]) + 1))
		_style(nxt, "go")
		nxt.pressed.connect(func(): show_pick())
		row.add_child(nxt)
		var teams := _button("Armies")
		teams.pressed.connect(func(): open_setup(""))
		row.add_child(teams)
		var quit := _button("× Abandon campaign")
		_style(quit, "stop")
		quit.pressed.connect(func(): _close_overlays(); campaign_abandoned.emit())
		row.add_child(quit)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 30)
	results_box.add_child(pad)
	results_overlay.visible = true


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
		kl.add_theme_font_size_override("font_size", 11)
		kl.add_theme_color_override("font_color", Color(1, 0.92, 0.6, 0.85))
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		kl.anchor_left = 0.0
		kl.anchor_top = 0.0
		kl.anchor_right = 1.0
		kl.anchor_bottom = 1.0
		kl.offset_left = 0.0
		kl.offset_top = 0.0
		kl.offset_right = -5.0
		kl.offset_bottom = -2.0
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
	# a panel open over the field (Armies, Choose Companies, a result): no view controls, no camera moves
	var open := _any_overlay()
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


func _cursor_for_tree(n: Node) -> void:
	for ch in n.get_children():
		_cursor_for(ch)


# ---------------------------------------------------------------- the books: by company and by type

## A battle's men, added up by company: the rows the tables below are drawn from.
func battle_unit_rows(res: Dictionary) -> Array:
	var cos: Array = res.get("companies", [[], []])
	var rows := {}
	for m in res["soldiers"]:
		var t: int = m["team"]
		var c: int = int(m.get("company", 0))
		var key := "%d:%d" % [t, c]
		if not rows.has(key):
			var co: Dictionary = cos[t][c] if c < (cos[t] as Array).size() else {"name": "?", "persona": "?", "type": "?"}
			rows[key] = {"team": t, "name": co["name"], "drill": co["persona"], "type": co["type"], "battles": 1,
				"men": 0, "fell": 0, "ran": 0, "shots": 0, "hits": 0, "thrusts": 0, "thrust_hits": 0, "kills": 0, "bkills": 0}
		var u: Dictionary = rows[key]
		u["men"] += 1
		if not m["alive"]:
			u["fell"] += 1
		elif m["routed"] or m["gone"]:
			u["ran"] += 1
		u["shots"] += int(m["shots"])
		u["hits"] += int(m["hits"])
		u["thrusts"] += int(m.get("thrusts", 0))
		u["thrust_hits"] += int(m.get("thrust_hits", 0))
		u["kills"] += int(m["kills"])
		u["bkills"] += int(m["bayonet_kills"])
	var out := []
	for t in 2:
		for c in 64:
			if rows.has("%d:%d" % [t, c]):
				out.append(rows["%d:%d" % [t, c]])
	return out


const BOOK_HEAD := ["Company", "Men", "Fell", "Ran", "Shots", "Hit %", "Bayonet", "Kills", "K/D"]


func _book_row(g: GridContainer, label: String, u: Dictionary, col: Color, extra := "") -> void:
	var acc := 100.0 * float(u["hits"]) / maxf(float(u["shots"]), 1.0)
	var tacc := 100.0 * float(u["thrust_hits"]) / maxf(float(u["thrusts"]), 1.0)
	_bcell(g, label + extra, col)
	_bcell(g, str(u["men"]))
	_bcell(g, str(u["fell"]))
	_bcell(g, str(u["ran"]))
	_bcell(g, str(u["shots"]))
	_bcell(g, ("%d%%" % int(round(acc))) if int(u["shots"]) > 0 else "-")
	_bcell(g, ("%d (%d%%)" % [int(u["thrusts"]), int(round(tacc))]) if int(u["thrusts"]) > 0 else "-")
	_bcell(g, "%d (%d bay.)" % [int(u["kills"]), int(u["bkills"])] if int(u["bkills"]) > 0 else str(u["kills"]))
	_bcell(g, "%.1f" % (float(u["kills"]) / float(u["fell"])) if int(u["fell"]) > 0 else ("%d / 0" % int(u["kills"])))


func _bcell(g: GridContainer, text: String, color: Color = Color(0.9, 0.9, 0.86), bold := false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13 if bold else 12)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(46, 0)
	g.add_child(l)


func _book_grid(parent: Control, first: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = BOOK_HEAD.size()
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 2)
	# on a narrow phone the table slides sideways rather than being cut off
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	sc.add_child(g)
	for i in BOOK_HEAD.size():
		_bcell(g, first if i == 0 else BOOK_HEAD[i], Color(0.95, 0.88, 0.6), true)
	return g


## Company by company: who went in, what they shot, what they hit, what it cost.
func unit_table(parent: Control, title: String, rows: Array, show_battles := false) -> void:
	_section(parent, title)
	_hover(parent.get_child(parent.get_child_count() - 1), "Men = men who went in%s. Hit %% = shots that struck someone. Bayonet = thrusts (how many landed). K/D = kills for each man lost." % (" (over all the battles)" if show_battles else ""))
	var g := _book_grid(parent, "Company")
	for u in rows:
		var col: Color = MatchManager.TEAM_COLORS[int(u["team"])].lightened(0.45)
		var extra := ("  %d battles" % int(u["battles"])) if show_battles else ""
		_book_row(g, "%s %s - %s / %s" % [MatchManager.TEAM_NAMES[int(u["team"])], u["name"], u["drill"], u["type"]], u, col, extra)


## The same, added up by troop type for each side - which kind of man earns his keep.
func type_table(parent: Control, title: String, rows: Array) -> void:
	_section(parent, title)
	var g := _book_grid(parent, "Type")
	for t in 2:
		var by := {}
		var order := []
		for u in rows:
			if int(u["team"]) != t:
				continue
			var ty: String = u["type"]
			if not by.has(ty):
				by[ty] = {"team": t, "companies": 0, "men": 0, "fell": 0, "ran": 0, "shots": 0, "hits": 0, "thrusts": 0, "thrust_hits": 0, "kills": 0, "bkills": 0}
				order.append(ty)
			var b: Dictionary = by[ty]
			b["companies"] += 1
			for f in ["men", "fell", "ran", "shots", "hits", "thrusts", "thrust_hits", "kills", "bkills"]:
				b[f] += int(u[f])
		for ty in order:
			var b: Dictionary = by[ty]
			_book_row(g, "%s %s" % [MatchManager.TEAM_NAMES[t], ty], b, MatchManager.TEAM_COLORS[t].lightened(0.45), "  (%d co.)" % int(b["companies"]))


func _results_close() -> Button:
	return results_title.get_parent().get_child(0) as Button


# ---------------------------------------------------------------- simulating

var _sim_cover: PanelContainer = null
var _sim_label: Label = null


## While a battle is simulated the field is not drawn: a plain cover with the clock instead.
func show_sim_cover(on: bool) -> void:
	if _sim_cover == null:
		_sim_cover = PanelContainer.new()
		_sim_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.08, 0.1, 0.97)
		_sim_cover.add_theme_stylebox_override("panel", sb)
		_sim_label = Label.new()
		_sim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sim_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_sim_label.add_theme_font_size_override("font_size", 22)
		_sim_cover.add_child(_sim_label)
		_root.add_child(_sim_cover)
	_sim_cover.visible = on
	_sim_cover.mouse_filter = Control.MOUSE_FILTER_STOP


func update_sim_cover() -> void:
	if _sim_cover == null or not _sim_cover.visible or manager == null:
		return
	var e := int(manager.elapsed)
	_sim_label.text = "Simulating the battle...\n%d:%02d of the fight\n%d Red and %d Blue still standing" % [e / 60, e % 60, manager.alive_count(0), manager.alive_count(1)]


## A description that shows when the pointer rests on it, rather than taking room on the page.
func _hover(n: Node, text: String) -> void:
	var c := n as Control
	if c == null:
		return
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_default_cursor_shape = Control.CURSOR_HELP
	if text != "":
		c.tooltip_text = text
