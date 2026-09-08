from run_checks import *
run('cover_regression',['--scene','res://tools/combat_cover_validation.tscn'],{},45)
run('projectile_solo',['--scene','res://tools/projectile_crosshair_render_validation.tscn'],{},90,True)
run('projectile_split',['--scene','res://tools/projectile_crosshair_render_validation.tscn'],{'ONEGUN_PROJECTILE_SPLIT':'1'},90,True)
