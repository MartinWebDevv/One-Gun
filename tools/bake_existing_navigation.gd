extends SceneTree

const TARGETS := {
	"city": {
		"scene": "res://maps/test/CityMap.tscn",
		"output": "res://navigation/CityMapNavigation.tres",
		"radius": 0.45,
		"climb": 0.8,
	},
	"forest": {
		"scene": "res://maps/test/ForestMap.tscn",
		"output": "res://navigation/ForestMapNavigation.tres",
		"radius": 0.6,
		"climb": 0.7,
	},
	"western": {
		"scene": "res://maps/test/WesternV2Map.tscn",
		"output": "res://navigation/WesternV2MapNavigation.tres",
		"radius": 0.45,
		"climb": 0.7,
	},
	"cat_tower": {
		"scene": "res://maps/test/catTower.tscn",
		"output": "res://navigation/CatTowerNavigation.tres",
		# Cat Tower keeps the region in the Game Area branch for organization,
		# but runs it top-level because NavigationServer does not support the
		# branch's 7x scale for query geometry. Bake in world-space dimensions.
		"radius": 0.55,
		"height": 2.5,
		"climb": 0.85,
		"cell_size": 0.25,
		"cell_height": 0.25,
	},
	"space_station_prototype": {
		"scene": "res://maps/test/SpaceStationPrototype.tscn",
		"output": "res://navigation/SpaceStationPrototypeNavigation.tres",
		"source_node": "Graybox",
		"radius": 0.55,
		"height": 2.5,
		"climb": 0.7,
		"cell_size": 0.25,
		"cell_height": 0.25,
	},
}


func _initialize() -> void:
	call_deferred("_bake_target")


func _bake_target() -> void:
	var target_name := OS.get_environment("ONEGUN_NAV_BAKE_TARGET").to_lower()
	if not TARGETS.has(target_name):
		push_error("Set ONEGUN_NAV_BAKE_TARGET to city, forest, western, cat_tower, or space_station_prototype")
		quit(1)
		return
	var target: Dictionary = TARGETS[target_name]
	var packed := load(str(target["scene"])) as PackedScene
	if packed == null:
		push_error("Could not load map: %s" % target["scene"])
		quit(1)
		return
	var map := packed.instantiate() as Node3D
	map.process_mode = Node.PROCESS_MODE_DISABLED
	var round_manager := map.get_node_or_null("RoundManager")
	if round_manager != null:
		round_manager.set_script(null)
	root.add_child(map)
	current_scene = map
	await process_frame

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = float(target["radius"])
	nav_mesh.agent_height = float(target.get("height", 2.5))
	nav_mesh.agent_max_climb = float(target["climb"])
	nav_mesh.agent_max_slope = 48.0
	nav_mesh.cell_size = float(target.get("cell_size", 0.25))
	nav_mesh.cell_height = float(target.get("cell_height", 0.25))
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	var source := NavigationMeshSourceGeometryData3D.new()
	var source_root: Node = map
	var source_node_path := str(target.get("source_node", ""))
	if source_node_path != "":
		source_root = map.get_node_or_null(source_node_path)
		if source_root == null:
			push_error("Navigation source node does not exist: %s" % source_node_path)
			quit(1)
			return
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, source_root)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	var polygons := nav_mesh.get_polygon_count()
	if polygons <= 0:
		push_error("Navigation bake produced no polygons for %s" % target_name)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://navigation"))
	var save_error := ResourceSaver.save(nav_mesh, str(target["output"]))
	print("NAV_BAKE target=%s polygons=%d output=%s save_error=%d" % [
		target_name, polygons, target["output"], save_error])
	quit(0 if save_error == OK else 1)
