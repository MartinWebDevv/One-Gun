from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parent.parent
out=root/'artifacts/hideout_migration'
out.mkdir(exist_ok=True)
(out/'.gdignore').touch()
render='--render' in sys.argv
compact='--compact' in sys.argv
name=('ui_compact' if compact else 'ui_render') if render else 'ui_headless'
startup=subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow=0
command=[str(root/'Godot_v4.7.1-stable_win64.exe'),'--path',str(root),'--log-file',str(out/(name+'.log'))]
command+=['--resolution','1280x720' if compact else '1920x1080','--windowed'] if render else ['--headless']
command+=['res://tools/hideout_ui_validation.tscn','--','--hideout-test']
if render: command+=['--capture-hideout']
if compact: command+=['--compact-capture']
result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,startupinfo=startup,timeout=180)
text=(out/(name+'.log')).read_text(encoding='utf-8',errors='replace') if (out/(name+'.log')).exists() else result.stdout.decode('utf-8',errors='replace')
print(text[-18000:])
sys.exit(1 if result.returncode or 'SCRIPT ERROR:' in text or '\nERROR:' in text or 'HIDEOUT_UI_COMPLETE' not in text else 0)
