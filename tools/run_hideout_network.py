from pathlib import Path
import subprocess,time,sys
root=Path(__file__).resolve().parent.parent
out=root/'artifacts/hideout_migration'
out.mkdir(exist_ok=True)
(out/'.gdignore').touch()
startup=subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow=0
procs=[]
for role in ("host","client"):
    (out/(role+".log")).write_text("")
try:
    for role in ('host','client'):
        command=[str(root/'Godot_v4.7.1-stable_win64.exe'),'--headless','--path',str(root),'--log-file',str(out/(role+'.log')),'res://tools/hideout_network_validation.tscn','--','--hideout-test','--hideout-'+role]
        procs.append(subprocess.Popen(command,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,startupinfo=startup))
        if role=='host':
            deadline=time.monotonic()+60
            while time.monotonic()<deadline:
                path=out/'host.log'
                if path.exists() and 'HIDEOUT_HOST_READY' in path.read_text(encoding='utf-8',errors='replace'): break
                if procs[0].poll() is not None: break
                time.sleep(0.2)
    codes=[p.wait(timeout=240) for p in procs]
    failed=any(codes)
    for role in ('host','client'):
        path=out/(role+'.log')
        text=path.read_text(encoding='utf-8',errors='replace') if path.exists() else 'MISSING LOG'
        print(role.upper(),text[-16000:])
        failed |= 'SCRIPT ERROR:' in text or '\nERROR:' in text or 'HIDEOUT_COMPLETE' not in text
    sys.exit(1 if failed else 0)
finally:
    for p in procs:
        if p.poll() is None: p.terminate();p.wait(timeout=10)
