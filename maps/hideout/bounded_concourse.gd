extends RefCounted
## The old circular overshoot would place invisible floor above the new lower room.
static func build(parent: Node3D, material: Material) -> void:
	var angles: Array[float]=[]
	for i in range(128): angles.append(TAU*i/128.0)
	var corner := atan2(27.0,30.0)
	for angle in [corner,PI-corner,PI+corner,TAU-corner]: angles.append(angle)
	angles.sort()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(angles.size()):
		var a := angles[i]
		var b := angles[(i+1)%angles.size()]
		var da := Vector3(sin(a),0,cos(a))
		var db := Vector3(sin(b),0,cos(b))
		var ra := minf(27.0/maxf(absf(da.x),0.00001),30.0/maxf(absf(da.z),0.00001))
		var rb := minf(27.0/maxf(absf(db.x),0.00001),30.0/maxf(absf(db.z),0.00001))
		var points := [da*10.2,da*ra,db*rb,db*10.2]
		for index in [0,2,1,0,3,2]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(points[index].x,points[index].z)*0.14)
			surface.add_vertex(points[index])
	var mesh := MeshInstance3D.new()
	mesh.name="Concourse"
	mesh.mesh=surface.commit()
	mesh.material_override=material
	parent.add_child(mesh)
	mesh.create_trimesh_collision()
