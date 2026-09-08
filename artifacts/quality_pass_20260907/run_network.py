from run_checks import *
jobs=[('online_'+mode,'run_online_smoke.ps1',['-Mode',mode,'-TimeoutMilliseconds','90000']) for mode in ['match','lobby','named_lobby','exit_flow','client_exit','online_bots','overtime','one_of_us','playpen']]
jobs += [('online_late_spectator','run_online_late_spectator.ps1',['-TimeoutMilliseconds','90000']),('online_dedicated','run_dedicated_server_smoke.ps1',['-TimeoutMilliseconds','90000']),('online_version_mismatch','run_version_mismatch_smoke.ps1',[])]
results=[]
for label,script,extra in jobs:
    command=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools'/script)]+extra
    start=time.time(); log=OUT/(label+'.log')
    with log.open('w',encoding='utf-8') as f:
        p=subprocess.run(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    content=log.read_text(encoding='utf-8',errors='replace')
    errors=[l for l in content.splitlines() if re.search(r'^SCRIPT ERROR:|^ERROR:|FAIL|timed out',l)]
    markers=[l for l in content.splitlines() if 'PASS' in l]
    result=dict(label=label,code=p.returncode,seconds=round(time.time()-start,2),errors=errors,markers=markers,log=str(log))
    results.append(result); (OUT/(label+'.json')).write_text(json.dumps(result,indent=2))
    print(json.dumps(result),flush=True)
(OUT/'online_summary.json').write_text(json.dumps(results,indent=2))
print('ONLINE AUDIT COMPLETE',len(results),flush=True)
