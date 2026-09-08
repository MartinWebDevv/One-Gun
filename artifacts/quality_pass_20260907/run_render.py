from run_checks import *
jobs=[
 ('render_projectile_solo',['--scene','res://tools/projectile_crosshair_render_validation.tscn'],{}),
 ('render_projectile_split',['--scene','res://tools/projectile_crosshair_render_validation.tscn'],{'ONEGUN_PROJECTILE_SPLIT':'1'}),
 ('render_new_characters',['--scene','res://tools/new_character_render_validation.tscn'],{}),
 ('render_player_v2',['--scene','res://tools/player_v2_render_validation.tscn'],{'ONE_GUN_V2_RENDER_OUTPUT':str(OUT/'player_v2_captures')}),
 ('render_ads',['--scene','res://tools/ads_camera_render_validation.tscn'],{}),
 ('render_menu_clicks',['--script','res://tools/menu_pointer_click_validation.gd'],{}),
 ('render_winners_circle',['--script','res://tools/winners_circle_validation.gd'],{}),
 ('render_hat_interactions',['--script','res://tools/hat_preview_interaction_validation.gd'],{}),
 ('render_hats',['--scene','res://tools/hat_render_validation.tscn'],{}),
 ('render_gameplay_hat_camera',['--scene','res://tools/gameplay_hat_camera_validation.tscn'],{'ONEGUN_GAMEPLAY_CAMERA_CAPTURE_DIR':str(OUT/'camera_captures')}),
 ('render_customization',['--scene','res://tools/character_customization_validation.tscn'],{'ONEGUN_CUSTOMIZATION_CAPTURE_DIR':str(OUT/'customization_captures'),'ONEGUN_CUSTOMIZATION_WINDOW':'1280x720'}),
]
results=[]
for label,args,env in jobs: results.append(run(label,args,env,360,True))
(OUT/'render_summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('RENDER AUDIT COMPLETE',len(results),flush=True)
