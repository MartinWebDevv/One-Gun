from pathlib import Path
import os, sys, subprocess, time, json, re
from concurrent.futures import ThreadPoolExecutor, as_completed
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
EXE=ROOT/'Godot_v4.7.1-stable_win64.exe'

def run(label, args, env_extra=None, timeout=180, render=False):
    data=OUT/'userdata'/label; data.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy(); env.update(APPDATA=str(data), LOCALAPPDATA=str(data))
    env.update(env_extra or {})
    command=[str(EXE),'--path',str(ROOT)]
    command+=['--windowed','--resolution','1600x900','--position','-3000,-3000'] if render else ['--headless']
    command+=args
    start=time.time(); log=OUT/(label+'.log')
    startup=subprocess.STARTUPINFO(); startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow=0
    timed=False
    with log.open('w',encoding='utf-8') as f:
        p=subprocess.Popen(command,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT,startupinfo=startup)
        try: code=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired: p.kill(); p.wait(); code=-999; timed=True
    text=log.read_text(encoding='utf-8',errors='replace')
    errors=[line for line in text.splitlines() if re.search(r'^(?:SCRIPT ERROR:|ERROR:)|(?:VALIDATION.*FAIL|FAILED:)',line)]
    markers=[line for line in text.splitlines() if re.search(r'PASS|VALIDATION|validation|PROFILE|profile',line)][-8:]
    result=dict(label=label,code=code,seconds=round(time.time()-start,2),timeout=timed,errors=errors,markers=markers,command=command,log=str(log))
    (OUT/(label+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:result[k] for k in ('label','code','seconds','errors','markers')}),flush=True)
    return result

if __name__=='__main__':
    names='combat_rules_validation camera_collision_validation character_size_hitbox_validation female_player_v2_validation player_v2_asset_validation new_character_integration_validation goldfish_bag_character_validation cosmetic_body_binding_validation decoy_validation damage_direction_indicator_validation cat_tower_validation city_asset_replacement_validation city_environment_map_validation enterable_city_buildings_validation space_station_prototype_validation player_capacity_validation high_priority_09_18_validation gameplay_packet_validation new_game_modes_validation all_gun_overtime_validation overtime_transition_validation playpen_validation input_remap_validation hat_fitting_tool_validation'.split()
    scripts='menu_systems_validation equipped_cosmetic_visibility_validation social_system_validation progression_catalog_validation victory_move_integration_validation winners_circle_validation supabase_ui_validation supabase_main_menu_validation validate_trippy_mountains_map validate_trippy_mountains_runtime'.split()
    jobs=[(n,['--scene','res://tools/'+n+'.tscn'],{},240) for n in names]
    jobs += [(n,['--script','res://tools/'+n+'.gd'],{},240) for n in scripts]
    jobs += [('migration_solo',['--scene','res://tools/godot_47_migration_validation.tscn'],{'ONEGUN_MIGRATION_SPLIT':'0'},180),('migration_split',['--scene','res://tools/godot_47_migration_validation.tscn'],{'ONEGUN_MIGRATION_SPLIT':'1'},180)]
    jobs += [('hideout_full',['--scene','res://tools/live_lobby_preview/live_lobby_preview.tscn','--','--live-lobby-validate'],{},360)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(run,*job) for job in jobs]
        results=[f.result() for f in as_completed(futures)]
    (OUT/'headless_summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print('HEADLESS AUDIT COMPLETE',len(results),flush=True)
