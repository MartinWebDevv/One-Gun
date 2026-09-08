extends CanvasLayer
const G = preload("res://tools/live_lobby_preview/geometry.gd")
const Session = preload("res://tools/live_lobby_preview/session.gd")
signal action(id: String, value: Variant)
var session: RefCounted
var training: Node
var scrap: Node
var shell: Control
var panel: PanelContainer
var contents: VBoxContainer
var subtitle: Label
var status: Label
var context: Label
var toast: Label
var ready_panel: PanelContainer
var ready_label: Label
var ready_accept: Button
var ready_cancel: Button
var stats: Label
var help: Label
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
	var head := PanelContainer.new()
	shell.add_child(head)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = 72
	head.add_theme_stylebox_override("panel",_style(Color("122126"),Color("435254"),0))
	var row := HBoxContainer.new()
	head.add_child(row)
	row.add_theme_constant_override("separation",24)
	var brand := _label("ONE GUN  /  THE HIDEOUT",30,G.GOLD)
	brand.custom_minimum_size.x = 420
	row.add_child(brand)
	subtitle = _label("INVITE ONLY",20,G.PAPER)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(subtitle)
	row.add_child(_label("F6 PREVIEW   /   NO MATCH LINK",21,G.CYAN))
	reticle = _label("+",28,G.PAPER)
	shell.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -10
	reticle.offset_right = 10
	reticle.offset_top = -20
	reticle.offset_bottom = 20
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status = _label("",24,G.PAPER)
	shell.add_child(status)
	status.position = Vector2(34,100)
	context = _label("",25,G.GOLD)
	shell.add_child(context)
	context.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	context.offset_left = -560
	context.offset_right = 560
	context.offset_top = -122
	context.offset_bottom = -82
	context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var footer := PanelContainer.new()
	shell.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -64
	footer.add_theme_stylebox_override("panel",_style(Color("122126"),Color("435254"),0))
	help = _label("SAVED MOVEMENT CONTROLS     E  KIOSK     TAB  GAME BOARD     H  PLAYER HUB     P  SQUAD     L  LOCKER     ESC  MENU",19,G.PAPER)
	footer.add_child(help)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats = _label("",18,G.PAPER)
	shell.add_child(stats)
	stats.position = Vector2(34,137)
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
	ready_accept = _button(ready_buttons,"[R] ACCEPT","accept",null,G.GREEN)
	ready_cancel = _button(ready_buttons,"[X] DECLINE","cancel",null,G.PAPER)
	ready_panel.visible = false
	toast = _label("",20,G.PAPER)
	shell.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_left = -660
	toast.offset_right = 660
	toast.offset_top = -167
	toast.offset_bottom = -128
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel = PanelContainer.new()
	shell.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -556
	panel.offset_right = -30
	panel.offset_top = 93
	panel.offset_bottom = -83
	panel.add_theme_stylebox_override("panel",_style(Color(0.055,0.105,0.12,0.98),Color("72765e"),1))
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
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font",ui_font)
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
	b.custom_minimum_size.y = 49
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font",ui_font)
	b.add_theme_font_size_override("font_size",24)
	b.add_theme_color_override("font_color",color)
	b.add_theme_color_override("font_hover_color",G.PAPER)
	b.add_theme_stylebox_override("normal",_style(Color("26363a"),Color("475553"),1))
	b.add_theme_stylebox_override("hover",_style(Color("394745"),color,2))
	b.add_theme_stylebox_override("pressed",_style(Color("4a5143"),color,2))
	b.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),color,2))
	parent.add_child(b)
	b.pressed.connect(func(): action.emit(id,value))
	return b

func show_page(which: String) -> void:
	page = which
	for child in contents.get_children():
		contents.remove_child(child)
		child.queue_free()
	panel.visible = not which.is_empty()
	if which.is_empty(): return
	_copy("THE HIDEOUT",18,G.CYAN)
	match which:
		"events","private","join","local","party":
			preload("res://tools/live_lobby_preview/game_board_ui.gd").build(self,which)
		"scrap":
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
			preload("res://tools/live_lobby_preview/course_board_ui.gd").build(self,training)
		"agility":
			_copy("AGILITY TIME TRIAL",43,G.GREEN)
			_copy("One start door. One finish door. Launch, vault, jump to a wide landing, sweep around the turn, cut past low cover and dash for the finish.",22)
			_copy("Falls return to the last checkpoint and add 2 seconds. Menus pause the clock; death or leaving early cancels the run. Power-assisted runs and different movement settings have separate records.",20)
			_button(contents,"LOBBY TIMES / YOUR BEST","page","course_board",G.CYAN)
			_button(contents,"RETURN TO START DOOR","course_restart",null,G.GREEN)
		"pause":
			_copy("TAKE A BREATHER",43,G.GOLD)
			_button(contents,"BACK TO THE ROOM","close")
			_button(contents,"GAME BOARD","page","events")
			_button(contents,"YOUR SQUAD","page","party",G.CYAN)
			_button(contents,"PLAYER HUB","page","hub",G.PINK)
			_button(contents,"THE SCRAP YARD / 1V1","page","scrap",G.ORANGE)
			_button(contents,"PLAY PEN / SPARRING","page","sparring",G.CYAN)
			_button(contents,"FIRING RANGE / DISTANCES","page","range_settings",G.CYAN)
			_button(contents,"AGILITY / TIME TRIAL","page","agility",G.GREEN)
			_button(contents,"COURSE RECORD BOARD","page","course_board",G.CYAN)
			_button(contents,"RESPAWN AT ARRIVALS","respawn",null,G.PAPER)
			_button(contents,"TOGGLE LOW PREVIEW / SAVED QUALITY","quality",null,G.PAPER)
			_copy("The demo queue keeps running while this menu is open. R accepts; X cancels from anywhere.",18,G.GREEN)
			_button(contents,"STOP PREVIEW","quit",null,G.ORANGE)
		"away":
			_copy("MATCH PREVIEW",27,G.GREEN)
			_copy(session.destination.to_upper(),49,G.GOLD)
			_copy("START REHEARSED",25,G.CYAN)
			_copy("The live game would take over here. The preview stays in this scene. Matchmaking and arena travel are still rehearsals.",22)
			_copy("Your %d demo party member(s), characters are still held in this lab session." % (session.guests.size()+1))
			_button(contents,"RETURN WITH YOUR PARTY","return",null,G.GREEN)
	if which not in ["intro","away","pause"]:
		_button(contents,"BACK TO THE ROOM / ESC","close",null,G.PAPER)
	for child in contents.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func _map_picker() -> void:
	_option("MATCH MAP",Session.MAPS,Session.MAPS.find(session.destination),"destination")

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

func update_readouts(delta: float, fps: int, charges: int, low: bool) -> void:
	toast_left = maxf(0,toast_left-delta)
	toast.visible = toast_left > 0
	var phase_text: String = ["AT HOME","SEARCHING / DEMO","READY CHECK / DEMO","STARTING / DEMO","DESTINATION PREVIEW"][session.phase]
	status.text = "%s  /  %s" % [session.alias_name,phase_text]
	subtitle.text = "%s   /   %d HERE   /   %s" % [session.access.to_upper(),session.member_count(),session.destination.to_upper()]
	stats.text = "%s  /  %d FPS     DASH %d" % ["LOW PREVIEW" if low else "SAVED QUALITY",fps,charges]
	ready_panel.visible = session.phase in [Session.Phase.FOUND,Session.Phase.DEPARTING]
	ready_accept.visible = session.phase == Session.Phase.FOUND and not session.local_ready
	ready_accept.text = "[R] CONFIRM" if session.pending=="join" else "[R] READY"
	ready_cancel.text = "[X] CANCEL"
	if session.phase == Session.Phase.FOUND:
		ready_label.text = ("JOIN TOGETHER" if session.pending=="join" else "READY CHECK")+" / F6\n"+("READY / GAME BOARD TO START" if session.local_ready else "[R] CONFIRM / [TAB] DETAILS")
	elif session.phase == Session.Phase.DEPARTING:
		ready_label.text = "MATCH STARTS IN %d / F6\nNO NEED TO WALK TO A DOOR" % ceili(session.remaining)

func update_local_summary() -> void:
	if page == "local" and is_instance_valid(local_summary):
		local_summary.text = "%d humans + %d bots / 10 actor cap. P2, AI and combat are not instantiated in this setup preview." % [session.local_humans,session.bots]