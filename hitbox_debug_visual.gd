class_name HitboxDebugVisual
extends MeshInstance3D

# Runtime-only testing visualization. It mirrors a CollisionShape3D without
# changing physics and is globally controlled by GameConfig.visible_hitboxes.

var source: CollisionShape3D
var idle_color := Color(0.1, 0.95, 1.0, 0.18)
var active_color := Color(0.1, 0.95, 1.0, 0.18)
var active := false
var _signature := ""
var _material: StandardMaterial3D


func setup(shape_source: CollisionShape3D, color: Color, hot_color := Color.TRANSPARENT) -> void:
	source = shape_source
	idle_color = color
	active_color = hot_color if hot_color.a > 0.0 else color
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_mesh(true)


func set_active(value: bool) -> void:
	active = value


func _process(_delta: float) -> void:
	visible = GameConfig.visible_hitboxes and source != null and is_instance_valid(source)
	if not visible:
		return
	transform = source.transform
	_refresh_mesh(false)
	var color := active_color if active else idle_color
	_material.albedo_color = color
	_material.emission_enabled = active
	_material.emission = Color(color.r, color.g, color.b)
	_material.emission_energy_multiplier = 1.35


func _refresh_mesh(force: bool) -> void:
	if source == null or source.shape == null:
		mesh = null
		return
	var shape := source.shape
	var signature := str(shape.get_instance_id())
	if shape is BoxShape3D:
		signature += ":" + str(shape.size)
	elif shape is CapsuleShape3D:
		signature += ":" + str(shape.radius) + ":" + str(shape.height)
	elif shape is SphereShape3D:
		signature += ":" + str(shape.radius)
	elif shape is CylinderShape3D:
		signature += ":" + str(shape.radius) + ":" + str(shape.height)
	if not force and signature == _signature:
		return
	_signature = signature
	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = shape.size
		mesh = box
	elif shape is CapsuleShape3D:
		var capsule := CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		mesh = capsule
	elif shape is SphereShape3D:
		var sphere := SphereMesh.new()
		sphere.radius = shape.radius
		sphere.height = shape.radius * 2.0
		mesh = sphere
	elif shape is CylinderShape3D:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = shape.radius
		cylinder.bottom_radius = shape.radius
		cylinder.height = shape.height
		mesh = cylinder
	else:
		mesh = null
