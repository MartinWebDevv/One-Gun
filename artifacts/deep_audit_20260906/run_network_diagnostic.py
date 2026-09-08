from run_audit import *
with ThreadPoolExecutor(max_workers=2) as pool:
    host=pool.submit(run,'online_diagnostic_host',['--scene','res://artifacts/deep_audit_20260906/online_diagnostic.tscn','--','--role=host','--mode=match'],{},120)
    time.sleep(.5)
    client=pool.submit(run,'online_diagnostic_client',['--scene','res://artifacts/deep_audit_20260906/online_diagnostic.tscn','--','--role=client','--mode=match'],{},120)
    host.result();client.result()
