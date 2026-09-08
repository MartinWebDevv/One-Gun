"""Run Godot preview checks without opening another visible editor window."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'tools/live_lobby_preview/artifacts'
OUT.mkdir(exist_ok=True)
(OUT / '.gdignore').touch()
EXE = ROOT / 'Godot_v4.7.1-stable_win64.exe'
mode = sys.argv[1] if len(sys.argv)>1 else 'validate'
cmd = [str(EXE), '--path', str(ROOT), '--log-file', str(OUT / (mode+'.log'))]
if mode == 'import': cmd += ['--headless', '--editor', '--import', '--quit']
elif mode == 'bake': cmd += ['--headless', '--quit-after', '2', 'res://tools/live_lobby_preview/build_station.tscn', '--', '--bake-live-lobby']
elif mode in ('validate','playtest'):
    cmd += (['--headless'] if mode == 'validate' else ['--windowed','--resolution','1920x1080','--position','-3000,-3000'])
    cmd += ['res://tools/live_lobby_preview/live_lobby_preview.tscn', '--', '--live-lobby-validate']
    if mode == 'playtest': cmd += ['--record-proof']
    cmd += sys.argv[2:]
elif mode == 'smoke': cmd += ['--headless', '--quit-after', '120', 'res://tools/live_lobby_preview/live_lobby_preview.tscn']
elif mode == 'capture': cmd += ['--windowed', '--resolution', '1920x1080', '--position', '-3000,-3000', 'res://tools/live_lobby_preview/live_lobby_preview.tscn', '--', '--live-lobby-capture'] + sys.argv[2:]
else: raise SystemExit('Unknown check mode')
startup = subprocess.STARTUPINFO()
startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
startup.wShowWindow = 0
result = subprocess.run(cmd, startupinfo=startup, timeout=360, capture_output=True)
print('GODOT EXIT:', result.returncode)
log = OUT / (mode+'.log')
if log.exists():
    lines = log.read_text(encoding='utf-8',errors='replace').splitlines()
    print('\n'.join(lines[-100:]).encode('ascii',errors='replace').decode())
has_errors = log.exists() and any('SCRIPT ERROR:' in line or line.startswith('ERROR:') for line in lines)
raise SystemExit(result.returncode or (1 if has_errors else 0))
