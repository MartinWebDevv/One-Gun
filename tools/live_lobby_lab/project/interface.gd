extends CanvasLayer
const G = preload("res://geometry.gd")
const Session = preload("res://session.gd")
signal action(id: String, value: Variant)
var session: RefCounted
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
var pending_mask: Color
var ui_font: Font
var local_summary: Label

func _ready() -> void:
	ui_font = load("res://art/heading.ttf")
	layer = 20
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
	var brand := _label("ONE GUN  /  UNLISTED",30,G.GOLD)
	brand.custom_minimum_size.x = 420
	row.add_child(brand)
	subtitle = _label("PLATFORM 01   /   PRIVATE WHEN ALONE",20,G.PAPER)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(subtitle)
	row.add_child(_label("OFFLINE LAB   /   SESSION ONLY",21,G.CYAN))
	var reticle := _label("+",28,G.PAPER)
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
	help = _label("WASD  MOVE     MOUSE  LOOK     SPACE  JUMP     SHIFT  DASH     E  INTERACT     TAB  EVENTS     P  PARTY     L  LOCKER     ESC  MENU",19,G.PAPER)
	footer.add_child(help)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats = _label("",18,G.PAPER)
	shell.add_child(stats)
	stats.position = Vector2(34,137)
	ready_panel = PanelContainer.new()
	shell.add_child(ready_panel)
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
	_copy("UNLISTED / PLATFORM 01",18,G.CYAN)
	match which:
		"intro":
			_copy("YOUR WAY\nUNDERGROUND.",63,G.GOLD)
			_copy("No names. No faces. One gun.",27)
			_copy("A disused station. A place to gather. An event that could take you anywhere.")
			_copy("Explore this standalone lobby study. Every invitation, event and departure is simulated locally.",20,G.CYAN)
			_button(contents,"ENTER THE HIDEOUT","enter")
			_copy("Movement uses the game's scale and camera framing. The masked runner is temporary art.",18)
			_button(contents,"QUIT LAB","quit",null,G.PAPER)
		"events":
			_copy("CHOOSE AN EVENT",43,G.GOLD)
			_copy("One room. Any destination.",24)
			if session.phase != Session.Phase.HOME:
				_copy("An event rehearsal is active. Return to the room to explore, or cancel it below.",22,G.GREEN)
				_button(contents,"BACK TO THE ROOM","close")
				_button(contents,"CANCEL REHEARSAL","cancel",null,G.ORANGE)
			else:
				_button(contents,"01  /  PUBLIC EVENT","public")
				_copy("An 8-second demo search. Practice or visit your locker while you wait.",18)
				_button(contents,"02  /  PRIVATE EVENT","page","private")
				_button(contents,"03  /  JOIN AN EVENT","page","join")
				_button(contents,"04  /  LOCAL + BOTS","page","local")
				_copy("Rehearsals stay inside the lab. No server or playable arena is loaded.",18,G.CYAN)
		"private":
			_copy("YOUR EVENT",46,G.GOLD)
			_copy("Choose a destination for the departure rehearsal. Your demo party follows you.")
			_map_picker()
			_copy("INVITE CODE / LAB-01",30,G.CYAN)
			_copy("This sample code works only in this prototype. All event settings here are temporary.",18)
			_button(contents,"REHEARSE PRIVATE EVENT","rehearse","Private event")
			_button(contents,"BACK","page","events",G.PAPER)
		"join":
			_copy("FOLLOW AN ALIAS",43,G.CYAN)
			_copy("ECHO'S HIDEOUT",31,G.PAPER)
			_copy("Demo invitation  /  LAB-01\nDestination: "+session.destination)
			_copy("A local invitation preview. This button rehearses joining and departing; it does not contact a friend.",20)
			_button(contents,"ACCEPT DEMO INVITATION","rehearse","Join event")
			_button(contents,"BACK","page","events",G.PAPER)
		"local":
			_copy("LOCAL + BOTS",46,G.GOLD)
			_copy("Setup preview / one controllable pilot in this slice.",20,G.CYAN)
			_map_picker()
			_option("LOCAL HUMANS",["1 player","2 players (split preview)"],session.local_humans-1,"humans")
			var bot_row := HBoxContainer.new()
			contents.add_child(bot_row)
			bot_row.add_child(_label("BOTS",23,G.PAPER))
			var count := SpinBox.new()
			count.min_value = 0
			count.max_value = Session.ACTOR_CAP-session.local_humans
			count.value = session.bots
			count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bot_row.add_child(count)
			count.value_changed.connect(func(v): action.emit("bots",int(v)))
			_option("DIFFICULTY",["Easy","Normal","Hard","Expert"],["Easy","Normal","Hard","Expert"].find(session.difficulty),"difficulty")
			local_summary = _copy("%d humans + %d bots / 10 actor cap. P2, AI and combat are not instantiated in this setup preview." % [session.local_humans,session.bots],19)
			_button(contents,"REHEARSE LOCAL DEPARTURE","rehearse","Local + bots")
			_button(contents,"BACK","page","events",G.PAPER)
		"party":
			_copy("YOUR PEOPLE",48,G.CYAN)
			_copy("%d / 10 DEMO MEMBERS" % (session.guests.size()+1),23)
			_copy(session.alias_name+"  /  YOU",25,G.GREEN)
			for guest in session.guests:
				_copy(guest+"  /  SIMULATED",22)
			var invite := _button(contents,"SIMULATE FRIEND ARRIVAL","add_friend",null,G.CYAN)
			invite.disabled = session.guests.size()>=9 or session.phase != Session.Phase.HOME
			var leave := _button(contents,"REMOVE LAST DEMO FRIEND","remove_friend",null,G.PAPER)
			leave.disabled = session.guests.is_empty() or session.phase != Session.Phase.HOME
			_copy("Visitors enter through the arrival doors and gather around the pit. No invitations are sent. Party membership stays in memory during departure and return.",18)
		"locker":
			pending_mask = session.mask_color
			_copy("KEEP YOUR SECRET",43,G.PINK)
			_copy("Try a mask color. Confirm keeps it for this test session; Back discards your preview.")
			for choice in [["ACID / ORIGINAL",G.GOLD],["CYAN / SIGNAL",G.CYAN],["MAGENTA / STATIC",G.PINK],["ORANGE / EMBER",G.ORANGE]]:
				_button(contents,choice[0],"preview_mask",choice[1],choice[1])
			_button(contents,"CONFIRM MASK","confirm_mask",null,G.PINK)
			_copy("Prototype colors only. No account inventory or saved cosmetics are accessed.",18,G.CYAN)
		"pause":
			_copy("TAKE A BREATHER",43,G.GOLD)
			_button(contents,"BACK TO THE ROOM","close")
			_button(contents,"EVENT BOARD","page","events")
			_button(contents,"YOUR PEOPLE","page","party",G.CYAN)
			_button(contents,"LOCKER","page","locker",G.PINK)
			_button(contents,"RESPAWN AT ARRIVALS","respawn",null,G.PAPER)
			_button(contents,"TOGGLE LOW / HIGH","quality",null,G.PAPER)
			_button(contents,"TOGGLE SPRINT PRACTICE","sprint",null,G.PAPER)
			_copy("The demo queue keeps running while this menu is open. R accepts; X cancels from anywhere.",18,G.GREEN)
			_button(contents,"QUIT LAB","quit",null,G.ORANGE)
		"away":
			_copy("NEXT STOP",27,G.GREEN)
			_copy(session.destination.to_upper(),49,G.GOLD)
			_copy("DEPARTURE REHEARSED",25,G.CYAN)
			_copy("The live game would take over here. No arena was loaded and no connection was made.",22)
			_copy("Your %d demo party member(s), mask and practice score are still held in this lab session." % (session.guests.size()+1))
			_button(contents,"RETURN WITH YOUR PARTY","return",null,G.GREEN)
	if which not in ["intro","away","pause"]:
		_button(contents,"BACK TO THE ROOM / ESC","close",null,G.PAPER)
	for child in contents.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func _map_picker() -> void:
	_option("DESTINATION STUDY",Session.MAPS,Session.MAPS.find(session.destination),"destination")

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
	var phase_text: String = ["AT HOME","SEARCHING / DEMO","READY CHECK / DEMO","DEPARTING / DEMO","DESTINATION PREVIEW"][session.phase]
	status.text = "%s  /  %s" % [session.alias_name,phase_text]
	subtitle.text = "PLATFORM 01   /   %d HERE   /   %s" % [session.guests.size()+1,session.destination.to_upper()]
	stats.text = "%s  /  %d FPS     DASH %d/3     RANGE %d/%d" % ["LOW" if low else "HIGH",fps,charges,session.hits,session.shots]
	ready_panel.visible = session.phase in [Session.Phase.FOUND,Session.Phase.DEPARTING]
	ready_accept.visible = session.phase == Session.Phase.FOUND
	ready_cancel.text = "[X] DECLINE" if session.phase == Session.Phase.FOUND else "[X] CANCEL DEPARTURE"
	if session.phase == Session.Phase.FOUND:
		ready_label.text = "MATCH FOUND / DEMO    %ds\n%s" % [ceili(session.remaining),session.destination.to_upper()]
	elif session.phase == Session.Phase.DEPARTING:
		ready_label.text = "DEPARTING IN %d / DEMO\nYOUR PARTY TRAVELS TOGETHER" % ceili(session.remaining)
	elif session.phase == Session.Phase.SEARCHING:
		status.text += "  %ds / [X] CANCEL" % ceili(session.remaining)

func update_local_summary() -> void:
	if page == "local" and is_instance_valid(local_summary):
		local_summary.text = "%d humans + %d bots / 10 actor cap. P2, AI and combat are not instantiated in this setup preview." % [session.local_humans,session.bots]