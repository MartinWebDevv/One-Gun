extends RefCounted
const G=preload("res://maps/hideout/geometry.gd")
static func apply(station: Node3D, powered: bool) -> void:
	var color: Color=G.ORANGE if powered else G.GREEN
	var mat:=G.material("course_selected_"+str(powered),color,0.3)
	for name in ["CourseStartDoor","CourseFinishDoor"]:
		var door:=station.find_child(name,true,false)
		if door==null: continue
		door.get_node("Sign/Title").modulate=color
		door.get_node("Sign/Rule").material_override=mat
		for trim in door.find_children("ModeTrim*","MeshInstance3D",true,false): trim.material_override=mat
	for index in range(2):
		var button:=station.find_child("CourseModeButton%d" % index,true,false)
		if button==null or not button.has_node("SelectionState"): continue
		var selected: bool=(index==1)==powered
		button.get_node("SelectionState").text="SELECTED" if selected else "SELECT"
		button.get_node("SelectionAccent").visible=selected
