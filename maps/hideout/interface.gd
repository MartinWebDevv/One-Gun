extends CanvasLayer
const G = preload("res://maps/hideout/geometry.gd")
const Session = preload("res://maps/hideout/session.gd")
signal action(id: String, value: Variant)
var session: RefCounted
var training: Node
var scrap: Node
var shell: Control
var panel: PanelContainer
var contents: VBoxContainer
var context: Label
var toast: Label
var ready_panel: PanelContainer
var ready_label: Label
var ready_accept: Button
var ready_cancel: Button
var friends_orb: Button
var friend_hint: Label
var menu_hint: Label
var page := ""
var toast_left := 0.0
var ui_font: Font
var local_summary: Label
var reticle: Label
var ready_shell: Control

func _ready() -> void:
	ui_font = load("res://fonts/cinematic/barlow_condensed/BarlowCondensed-ExtraBold.ttf")
	layer = 20
	get_viewport().size_changed.connect(_resize)
	shell = Control.new()
	add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 20
	shell.theme = theme
	friends_orb=preload("res://UI/components/friends_quick_access_orb.gd").new()
	shell.add_child(friends_orb)
	friends_orb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	friends_orb.offset_left=-126
	friends_orb.offset_right=-22
	friends_orb.offset_top=22
	friends_orb.offset_bottom=126
	friends_orb.pressed.connect(func(): action.emit("page","friends"))
	SocialManager.social_updated.connect(friends_orb.refresh_counts)
	friend_hint=_label("F1 / FRIENDS",17,G.CYAN)
	shell.add_child(friend_hint)
	friend_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	friend_hint.offset_left=-138
	friend_hint.offset_right=-10
	friend_hint.offset_top=132
	friend_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	menu_hint=_label("ESC / MENU    ALT / CURSOR",17,G.PAPER)
	shell.add_child(menu_hint)
	menu_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_hint.offset_left=-255
	menu_hint.offset_right=-22
	menu_hint.offset_top=158
	menu_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	reticle = _label("+",28,G.PAPER)
	shell.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -10
	reticle.offset_right = 10
	reticle.offset_top = -20
	reticle.offset_bottom = 20
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context = _label("",25,G.GOLD)
	shell.add_child(context)
	context.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	context.offset_left = -560
	context.offset_right = 560
	context.offset_top = -157
	context.offset_bottom = -117
	context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ready_layer := CanvasLayer.new()
	ready_layer.layer = 60
	add_child(ready_layer)
	ready_shell = Control.new()
	ready_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ready_layer.add_child(ready_shell)
	ready_panel = PanelContainer.new()
	ready_shell.add_child(ready_panel)
	ready_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ready_panel.offset_left = -390
	ready_panel.offset_right = 200
	ready_panel.offset_top = 95
	ready_panel.add_theme_stylebox_override("panel",_style(Color("152a26"),G.GREEN,2))
	var ready_rows := VBoxContainer.new()
	ready_panel.add_child(ready_rows)
	ready_label = _label("",29,G.GREEN)
	ready_rows.add_child(ready_label)
	var ready_buttons := HBoxContainer.new()
	ready_rows.add_child(ready_buttons)
	ready_accept = _button(ready_buttons,"[R] READY","ready",null,G.GREEN)
	ready_cancel = _button(ready_buttons,"[X] DECLINE","cancel",null,G.PAPER)
	ready_panel.visible = false
	toast = _label("",20,G.PAPER)
	shell.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_left = -660
	toast.offset_right = 660
	toast.offset_top = -200
	toast.offset_bottom = -160
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel = PanelContainer.new()
	shell.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -556
	panel.offset_right = -30
	panel.offset_top = 93
	panel.offset_bottom = -83
	panel.add_theme_stylebox_override("panel",_style(Color("352c49"),Color("705b87"),1))
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contents = VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation",14)
	scroll.add_child(contents)
	panel.visible = false
	_resize()

func _resize() -> void:
	if not is_instance_valid(shell): return
	var factor := minf(get_viewport().get_visible_rect().size.x / 1600.0, get_viewport().get_visible_rect().size.y / 900.0)
	shell.set_anchors_preset(Control.PRESET_TOP_LEFT)
	shell.scale = Vector2.ONE * factor
	shell.size = get_viewport().get_visible_rect().size / factor
	ready_shell.scale = shell.scale
	ready_shell.size = shell.size

func _style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(8)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font",ui_font if size>=30 else ThemeManager.font_med)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _copy(text: String, size := 19, color := G.PAPER) -> Label:
	var l := _label(text,size,color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(l)
	return l

func _button(parent: Node, text: String, id: String, value: Variant = null, color := G.GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 54
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("h_separation",18)
	var icon_id: String=str(value) if id=="page" else id
	if icon_id in ["respawn","settings","release_notes","quit","leave"]:
		b.icon=preload("res://UI/menu_icons.gd").get_icon(icon_id)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font",ui_font)
	b.add_theme_font_size_override("font_size",24)
	b.add_theme_color_override("icon_hover_color",G.INK)
	b.add_theme_color_override("icon_pressed_color",G.INK)
	b.add_theme_color_override("font_color",G.PAPER)
	b.add_theme_color_override("font_hover_color",G.INK)
	b.add_theme_color_override("font_pressed_color",G.INK)
	b.add_theme_stylebox_override("normal",_style(Color("2c243c"),Color("554560"),1))
	b.add_theme_stylebox_override("hover",_style(G.ORANGE,G.ORANGE,2))
	b.add_theme_stylebox_override("pressed",_style(G.ORANGE.darkened(0.12),G.ORANGE,2))
	b.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),color,2))
	parent.add_child(b)
	b.pressed.connect(func(): action.emit(id,value))
	return b

func show_page(which: String) -> void:
	page = which
	friends_orb.visible=which.is_empty()
	friend_hint.visible=which.is_empty()
	menu_hint.visible=which.is_empty()
	for child in contents.get_children():
		contents.remove_child(child)
		child.queue_free()
	panel.visible = not which.is_empty()
	if which.is_empty(): return
	_copy("THE HIDEOUT",18,G.CYAN)
	match which:
		"events","private","join","local","party":
			preload("res://maps/hideout/game_board_ui.gd").build(self,which)
		"scrap":
			if NetworkManager.is_online():
				_build_online_scrap()
				_button(contents,"BACK TO THE ROOM","close")
				return
			_copy("THE SCRAP YARD",43,G.ORANGE)
			_copy("One round. One gun. Two melee. One item and one power spawn. No Extra Life or Sticky Hands.",21)
			if scrap.state==scrap.State.IDLE:
				_button(contents,"JOIN AS PLAYER 2 / VS PRACTICE BOT","scrap_join","solo")
				_button(contents,"LOCAL TWO PLAYERS / SPLIT SCREEN","scrap_join","local",G.CYAN)
				_copy("P2 requires a separate controller. P1 keeps saved controls. Player 2 calls on the shared menu; both views show the result.",19)
				_button(contents,"WATCH A DEMO DUEL","scrap_join","watch",G.PAPER)
				_button(contents,"WALK INTO THE STANDS","scrap_watch",null,G.PAPER)
			elif scrap.state==scrap.State.CALLING:
				_copy("PLAYER 2 CALLS",35,G.CYAN)
				_copy("Correct: you start with the gun. Wrong: you start with melee. Player 1 gets the other weapon.",23)
				_button(contents,"HEADS","scrap_coin","heads",G.CYAN)
				_button(contents,"TAILS","scrap_coin","tails",G.ORANGE)
			elif scrap.state==scrap.State.RESULT:
				_copy(scrap.result_text,32,G.GREEN)
				_copy("Round over. Return to the foyer to rematch or make room for the next challenger.",22)
			else: _copy("Round in progress / spectators use the outer stands.",23)
			if scrap.state!=scrap.State.IDLE: _button(contents,"END ROUND / RETURN TO FOYER","scrap_leave",null,G.PAPER)
		"sparring":
			if NetworkManager.is_online():
				_copy("PLAY PEN",43,G.CYAN)
				_copy("Practice with the players in your Hideout. Gear stays inside the barrier.",22)
				_button(contents,"BACK TO THE ROOM","close")
				return
			_copy("SPARRING PARTNER",43,G.CYAN)
			_copy("A local test partner for the walk-in Play Pen. Death returns you to the entrance line; leaving clears all gear.",22)
			_button(contents,"PASSIVE TARGET","sparring","target",G.PAPER)
			_button(contents,"DUEL / FIRES BACK","sparring","duel",G.ORANGE)
			_button(contents,"DISABLE PARTNER","sparring","off",G.PAPER)
		"range_settings":
			_copy("FIRING RANGE",43,G.CYAN)
			_copy("Each lane has its own target. Distances are measured from the painted firing line.",22)
			for lane in range(3):
				_copy("LANE %d / %d HITS" % [lane+1,training.hits[lane]],25,G.PAPER)
				var picker := OptionButton.new()
				picker.custom_minimum_size.y=48
				for distance in training.Space.DISTANCES: picker.add_item(str(distance)+" metres")
				picker.select(training.range_indices[lane])
				contents.add_child(picker)
				picker.item_selected.connect(func(index): action.emit("range_distance",Vector2i(lane,index)))
			_button(contents,"RESET HIT COUNTERS","range_reset_hits",null,G.PAPER)
			_copy("At a lane console, Interact cycles 5 > 10 > 15 > 25 > 30 > 40 > 50 > 75 > 90 > 100 > 5 metres.",19)
		"course_board":
			preload("res://maps/hideout/course_board_ui.gd").build(self,training)
		"agility":
			_copy("AGILITY TIME TRIAL",43,G.GREEN)
			_copy("One start door. One finish door. Launch, vault, jump to a wide landing, sweep around the turn, cut past low cover and dash for the finish.",22)
			_copy("Falls return to the last checkpoint and add 2 seconds. The clock keeps running online; death or leaving early cancels the run. Power-assisted runs and different movement settings have separate records.",20)
			_button(contents,"LOBBY TIMES / YOUR BEST","page","course_board",G.CYAN)
			_button(contents,"RETURN TO START DOOR","course_restart",null,G.GREEN)
		"pause":
			_copy("MENU",38,G.PAPER)
			_button(contents,"Respawn at Arrivals","respawn",null,G.PAPER)
			_button(contents,"Player Settings","page","settings",G.PAPER)
			_button(contents,"Release Notes","page","release_notes",G.PAPER)
			_button(contents,"Quit Game","quit",null,G.ORANGE)
			if NetworkManager.is_online(): _button(contents,"Leave Hideout","leave",null,G.ORANGE)
			var shortcuts:=GridContainer.new()
			shortcuts.name="PauseShortcuts"
			shortcuts.columns=2
			shortcuts.add_theme_constant_override("h_separation",24)
			shortcuts.add_theme_constant_override("v_separation",5)
			contents.add_child(shortcuts)
			for text in ["TAB  Game Board","H  Player Hub","P  Squad","L  Locker","F1  Friends","F2  Scrap Yard","F3  Play Pen","F4  Firing Range","F5  Agility","F6  Course Records"]:
				var hint:=_label(text,18,Color("c3b6cc"))
				hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				shortcuts.add_child(hint)
			_copy("ESC  Back to the room",17,Color("c3b6cc"))
		"confirm_leave":
			_copy("LEAVE THIS HIDEOUT?",38,G.ORANGE)
			_copy("Hosting ends this session for everyone." if NetworkManager.is_host() else "You will return to your own Hideout.",22)
			_button(contents,"CONFIRM LEAVE","confirm_leave",null,G.ORANGE)
		"confirm_quit":
			_copy("QUIT ONE GUN?",38,G.ORANGE)
			_button(contents,"CONFIRM QUIT","confirm_quit",null,G.ORANGE)

	if which not in ["intro","away","pause"]:
		_button(contents,"BACK TO THE ROOM / ESC","close",null,G.PAPER)
	for child in contents.get_children():
		if child is Button and not child.disabled:
			if which=="pause":
				child.focus_mode=Control.FOCUS_NONE
			else:
				child.grab_focus()
				break

func _option(title: String, values: Array, selected: int, id: String) -> void:
	_copy(title,19,G.PAPER)
	var select := OptionButton.new()
	select.custom_minimum_size.y = 44
	for value in values: select.add_item(value)
	select.select(maxi(selected,0))
	contents.add_child(select)
	select.item_selected.connect(func(i): action.emit(id,i))

func show_toast(message: String) -> void:
	toast.text = message
	toast_left = 5

func update_readouts(delta: float, _fps: int, _charges: int, _low: bool) -> void:
	toast_left = maxf(0,toast_left-delta)
	toast.visible = toast_left > 0
	ready_panel.visible = shell.visible and NetworkManager.is_online() and NetworkManager._prelaunch_active
	ready_accept.visible = not NetworkManager._prelaunch_active
	ready_accept.text = "GAME BOARD" if NetworkManager.can_manage_lobby() else ("NOT READY" if session.local_ready else "READY UP")
	ready_cancel.visible = NetworkManager._prelaunch_active and NetworkManager.can_manage_lobby()
	ready_cancel.text = "CANCEL START"
	ready_label.text = "STARTING IN %d" % NetworkManager._prelaunch_seconds if NetworkManager._prelaunch_active else ("HOST CONTROLS MATCH START" if NetworkManager.can_manage_lobby() else "READY" if session.local_ready else "NOT READY")

func update_local_summary() -> void:
	pass

func _build_online_scrap() -> void:
	_copy("THE SCRAP YARD",43,G.ORANGE)
	_copy("One round. One gun. Two melee. One item and one power spawn.",21)
	if scrap == null: return
	_copy(scrap.result_text if scrap.state == scrap.State.RESULT else scrap.status_text(),25)
	if not scrap.is_fighter_id(NetworkManager.local_actor_id()) and (scrap.state == scrap.State.IDLE or (scrap.state == scrap.State.CALLING and scrap.fighter_ids.size() < 2)):
		_button(contents,"JOIN THE SCRAP","scrap_join","online")
	if scrap.can_call(NetworkManager.local_actor_id()):
		_button(contents,"HEADS","scrap_coin","heads",G.CYAN)
		_button(contents,"TAILS","scrap_coin","tails",G.ORANGE)
	if scrap.is_fighter_id(NetworkManager.local_actor_id()):
		_button(contents,"LEAVE DUEL","scrap_leave",null,G.PAPER)
	_copy("Spectators can watch from the outer stands.",21)
