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
	ui._option("RUN TYPE",["Standard movement","With powerups / effects"],int(training.board_assisted),"course_category")
	ui._copy(training.rules_caption(),18,ui.G.CYAN)
	var bucket: String=training.records_bucket(training.board_assisted)
	match training.board_tab:
		"lobby":
			ui._copy("THIS LOBBY",27)
			var rows: Array=training.records.lobby_rows(bucket)
			var rank := 0
			for row in rows:
				if row.time_ms>=0: rank+=1
				var value: String = training.format_time(row.time_ms/1000.0) if row.time_ms>=0 else "NO RUN YET"
				var prefix := "%02d" % rank if row.time_ms>=0 else "—"
				ui._copy("%s  /  %s\n%s" % [prefix,row.name,value],24,ui.G.GREEN if row.id==training.viewer_id() else ui.G.PAPER)
			ui._copy("Only people currently in this lobby appear here.",18)
		"personal":
			ui._copy(training.lab.session.alias_name.to_upper(),27,ui.G.CYAN)
			var best: int=training.records.personal_best(bucket,training.viewer_id())
			ui._copy(training.format_time(best/1000.0) if best>=0 else "SET YOUR FIRST TIME",42,ui.G.GREEN)
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
