extends RefCounted
static var cache: Dictionary={}
static func get_icon(id: String) -> Texture2D:
	id=id.to_lower()
	if not cache.has(id):
		var path := "res://UI/icons/menu/"+id+".svg"
		if not ResourceLoader.exists(path): return null
		cache[id]=load(path)
	return cache[id]
