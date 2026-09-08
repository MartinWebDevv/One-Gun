from run_audit import *
def lobby():
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs=[pool.submit(run,'lobby_authority_'+role,['--script','res://tools/lobby_network_validation.gd','--','--role='+role],{},45) for role in ['host','client']]
        for job in jobs: job.result()
def renders():
    run('render_accessibility',['--scene','res://tools/accessibility_render_validation.tscn'],{},30,True)
    run('render_smoke_cloud',['--scene','res://tools/smoke_cloud_render_validation.tscn'],{'ONE_GUN_SMOKE_RENDER_OUTPUT':str(OUT/'smoke_cloud.png')},30,True)
with ThreadPoolExecutor(max_workers=2) as pool:
    jobs=[pool.submit(lobby),pool.submit(renders)]
    for job in jobs: job.result()
