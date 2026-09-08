"""Fail if the standalone runtime acquires a live dependency or network action."""
from pathlib import Path
import re

LAB = Path(__file__).resolve().parent
PROJECT = LAB / "project"
REPO = LAB.parents[1]
errors = []
config = (PROJECT / "project.godot").read_text(encoding="utf-8")
if "[autoload]" in config:
    errors.append("Lab project must not register autoloads.")
if 'config/custom_user_dir_name="OneGunLiveLobbyLab"' not in config:
    errors.append("Lab must keep its separate user-data namespace.")
if not (LAB / ".gdignore").exists():
    errors.append("Missing parent-project import boundary.")
if "tools/**" not in (REPO / "export_presets.cfg").read_text(encoding="utf-8"):
    errors.append("Parent export presets no longer exclude developer tools.")

network = re.compile(r"(?:HTTPRequest|HTTPClient|ENetMultiplayerPeer|WebSocketPeer|WebRTCPeerConnection|StreamPeerTCP|TCPServer|PacketPeerUDP|UDPServer|MultiplayerSpawner|MultiplayerSynchronizer)\s*\.\s*new\s*\(|@rpc\b|\.rpc(?:_id)?\s*\(|OS\.(?:execute|create_process|shell_open)\s*\(")
live = re.compile(r"\b(?:GameConfig|GameEvents|NetworkManager|SocialManager|SupabaseManager|PlayerPrefs|ProgressionManager)\s*\.")
for path in PROJECT.glob("*.gd"):
    code = "\n".join(line.split("#",1)[0] for line in path.read_text(encoding="utf-8").splitlines())
    if network.search(code):
        errors.append(f"Network/process action in {path.name}")
    if live.search(code):
        errors.append(f"Live singleton dependency in {path.name}")
    for resource in re.findall(r'(?:load|preload)\("([^"]+)"', code):
        if not resource.startswith("res://") or ".." in resource:
            errors.append(f"Resource escapes standalone root in {path.name}: {resource}")
    if re.search(r'https?://|wss?://|uid://|(?<![A-Za-z])[A-Za-z]:[\\/]',code):
        errors.append(f"External endpoint/absolute resource reference in {path.name}")

for name in ["project.godot","app_bootstrap.gd","main_menu.gd","main_menu.tscn","game_setup.gd","game_setup.tscn","network_manager.gd"]:
    if "live_lobby_lab" in (REPO/name).read_text(encoding="utf-8"):
        errors.append(f"Live game file references the lab: {name}")

if errors:
    raise SystemExit("ISOLATION FAILED\n"+"\n".join(errors))
print("ISOLATION PASS: zero autoloads, no live singleton calls, no network/process actions, local resource loads, separate user data, ignored by the parent importer, excluded from exports, no startup/menu references.")
