from run_checks import *
if __name__=='__main__':
    names='combat_rules_validation camera_collision_validation character_size_hitbox_validation female_player_v2_validation player_v2_asset_validation new_character_integration_validation goldfish_bag_character_validation cosmetic_body_binding_validation decoy_validation damage_direction_indicator_validation cat_tower_validation city_asset_replacement_validation city_environment_map_validation enterable_city_buildings_validation space_station_prototype_validation player_capacity_validation high_priority_09_18_validation gameplay_packet_validation new_game_modes_validation all_gun_overtime_validation overtime_transition_validation playpen_validation input_remap_validation hat_fitting_tool_validation'.split()
    scripts='menu_systems_validation equipped_cosmetic_visibility_validation social_system_validation progression_catalog_validation victory_move_integration_validation winners_circle_validation supabase_ui_validation supabase_main_menu_validation validate_trippy_mountains_map validate_trippy_mountains_runtime'.split()
    jobs=[(n,['--scene','res://tools/'+n+'.tscn'],{},240) for n in names]
    jobs += [(n,['--script','res://tools/'+n+'.gd'],{},240) for n in scripts]
    jobs += [('migration_solo',['--scene','res://tools/godot_47_migration_validation.tscn'],{'ONEGUN_MIGRATION_SPLIT':'0'},180),('migration_split',['--scene','res://tools/godot_47_migration_validation.tscn'],{'ONEGUN_MIGRATION_SPLIT':'1'},180)]
    jobs += [('hideout_shared_regression',['--scene','res://tools/live_lobby_preview/live_lobby_preview.tscn','--','--live-lobby-validate'],{},360)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(run,*job) for job in jobs]
        results=[f.result() for f in as_completed(futures)]
    (OUT/'headless_summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print('HEADLESS AUDIT COMPLETE',len(results),flush=True)
