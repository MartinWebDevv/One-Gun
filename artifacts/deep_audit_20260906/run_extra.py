from run_audit import *
jobs=[('resource_audit',['--scene','res://artifacts/deep_audit_20260906/resource_audit.tscn'],{},240),('bounds_diagnostic',['--scene','res://artifacts/deep_audit_20260906/bounds_diagnostic.tscn'],{},60),('projectile_probe_refined',['--scene','res://artifacts/deep_audit_20260906/projectile_probe.tscn'],{},30),('trippy_camera_current',['--scene','res://tools/trippy_camera_presentation_validation.tscn'],{},60),('startup_flow',['--scene','res://tools/startup_production_flow_validation.tscn'],{},90),('client_package_source',['--script','res://tools/validate_client_package.gd'],{},90)]
with ThreadPoolExecutor(max_workers=2) as pool:
    results=[f.result() for f in as_completed([pool.submit(run,*j) for j in jobs])]
(OUT/'extra_summary.json').write_text(json.dumps(results,indent=2))
