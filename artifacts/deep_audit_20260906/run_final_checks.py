from run_audit import *
def private():
    with ThreadPoolExecutor(max_workers=2) as pool:
        host=pool.submit(run,'private_lobby_host',['--scene','res://artifacts/deep_audit_20260906/private_lobby_probe.tscn','--','--host'],{},25)
        time.sleep(.5)
        client=pool.submit(run,'private_lobby_client',['--scene','res://artifacts/deep_audit_20260906/private_lobby_probe.tscn'],{},25)
        host.result();client.result()
with ThreadPoolExecutor(max_workers=3) as pool:
    jobs=[pool.submit(private),
    pool.submit(run,'standalone_lobby_lab',['--path',str(ROOT/'tools/live_lobby_lab/project'),'--','--validate'],{},180),
    pool.submit(run,'render_character_customization',['--scene','res://tools/character_customization_validation.tscn'],{'ONEGUN_CUSTOMIZATION_CAPTURE_DIR':str(OUT/'customization_captures'),'ONEGUN_CUSTOMIZATION_WINDOW':'1280x720'},180,True)]
    for job in jobs: job.result()
