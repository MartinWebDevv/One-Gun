extends Node
func _ready()->void:_run.call_deferred()
func _run()->void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/deep_audit_20260906/resource_manifest.json"))
	var failures:Array=[]
	var count:=0
	for path in manifest:
		var resource=load(path)
		if resource==null:failures.append(path)
		count+=1
		if count%25==0:print("RESOURCE_AUDIT_PROGRESS ",count)
		resource=null
		await get_tree().process_frame
	print("RESOURCE_AUDIT ",JSON.stringify({"count":count,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
