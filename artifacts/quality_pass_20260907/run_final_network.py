from run_checks import *
jobs=[('ticket_server','run_match_server_smoke.ps1',[]),('version_3','run_version_mismatch_smoke.ps1',[]),('protocol3_match','run_online_smoke.ps1',['-Mode','match','-TimeoutMilliseconds','90000']),('protocol3_dedicated','run_dedicated_server_smoke.ps1',['-TimeoutMilliseconds','90000'])]
for label,script,args in jobs:
    started=time.time()
    with (OUT/(label+'.log')).open('w') as f:
        result=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ROOT/'tools'/script),*args],stdout=f,stderr=subprocess.STDOUT,timeout=180)
    text=(OUT/(label+'.log')).read_text(errors='replace')
    row={'label':label,'code':result.returncode,'seconds':round(time.time()-started,2),'errors':[line for line in text.splitlines() if line.startswith(('ERROR:','SCRIPT ERROR:'))],'markers':[line for line in text.splitlines() if 'PASS' in line]}
    (OUT/(label+'.json')).write_text(json.dumps(row,indent=2));print(json.dumps(row),flush=True)
