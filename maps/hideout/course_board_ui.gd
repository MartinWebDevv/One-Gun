extends RefCounted
## Viewer-specific pages over a replaceable records provider; no network calls.
static func build(ui: CanvasLayer, training: Node) -> void:
	ui._copy("CIRCUIT RECORDS",43,ui.G.GREEN)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",8)
	ui.contents.add_child(tabs)
	for tab in [["lobby","LOBBY"],["personal","YOUR BEST"],["world","WORLD"]]:
		var button: Button=ui._button(tabs,tab[1],"course_tab",tab[0],ui.G.GREEN if training.board_tab==tab[0] else ui.G.PAPER)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",21)
	ui._option("RUN TYPE",["Standard Run","Power-Up Run"],int(training.board_assisted),"course_category")
	ui._copy(training.rules_caption(),18,ui.G.CYAN)
	var bucket: String=training.records_bucket(training.board_assisted)
	match training.board_tab:
		"lobby":
			ui._copy("THIS LOBBY",27)
			var list := VBoxContainer.new()
			list.name="CourseLiveRows"
			list.add_theme_constant_override("separation",14)
			ui.contents.add_child(list)
			refresh_live(ui,training)

		"personal":
			ui._copy(training.lab.session.alias_name.to_upper(),27,ui.G.CYAN)
			var best: int=training.records.personal_best(bucket,training.viewer_id())
			ui._copy(training.format_time(best/1000.0) if best>=0 else "SET YOUR FIRST TIME",42,ui.G.GREEN)
			ui.contents.get_child(ui.contents.get_child_count()-1).name="PersonalLiveBest"
			ui._copy("YOUR BEST EVER ON THIS COURSE",23)
			ui._copy("Your completed personal best is kept on this PC for this course and movement setup.",20)
		"world":
			ui._copy("WORLD TIMES",30)
			if not training.records.world_available():
				ui._copy("COMING SOON",26,ui.G.CYAN)
				ui._copy("World rankings are coming in a future update. Lobby times and Your Best are available now.",21)
			else:
				for row in training.records.world_rows(bucket): ui._copy("%s / %s" % [row.name,training.format_time(row.time_ms/1000.0)],24)
	if training.records.save_error!=OK: ui._copy("Your latest best is available this session, but could not be saved on this PC.",19,ui.G.ORANGE)
	ui._button(ui.contents,"COURSE / HOW TO RUN","page","agility",ui.G.GREEN)

static func refresh_live(ui: CanvasLayer, training: Node) -> void:
	if ui.page!="course_board": return
	var bucket: String=training.records_bucket(training.board_assisted)
	var personal: Label=ui.contents.get_node_or_null("PersonalLiveBest")
	if personal:
		var best: int=training.records.personal_best(bucket,training.viewer_id())
		personal.text=training.format_time(best/1000.0) if best>=0 else "SET YOUR FIRST TIME"
	var list: VBoxContainer=ui.contents.get_node_or_null("CourseLiveRows")
	if list==null: return
	var rows: Array=training.records.lobby_rows(bucket)
	while list.get_child_count()>rows.size():
		var child: Node=list.get_child(list.get_child_count()-1)
		list.remove_child(child)
		child.queue_free()
	while list.get_child_count()<rows.size():
		var label: Label=ui._label("",23,ui.G.PAPER)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		list.add_child(label)
	for i in rows.size():
		var row: Dictionary=rows[i]
		var best: String=training.format_time(row.time_ms/1000.0) if row.time_ms>=0 else "NO FINISH"
		var last: String=training.format_time(row.last_ms/1000.0) if row.last_ms>=0 else "—"
		var live: String=training.live_status(str(row.id),training.board_assisted)
		var text: String="%02d / %s%s\nBEST %s / LAST %s\n%d FINISHES / LAST RUN: %d FALLS" % [i+1,row.name," / YOU" if row.id==training.viewer_id() else "",best,last,row.finishes,row.falls]
		if not live.is_empty(): text+="\n"+live
		list.get_child(i).text=text
		list.get_child(i).add_theme_color_override("font_color",ui.G.GREEN if row.id==training.viewer_id() else ui.G.PAPER)
