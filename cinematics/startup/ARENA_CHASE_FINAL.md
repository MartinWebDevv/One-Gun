# Arena Chase final preview

Run `startup_intro_arena_chase_final.tscn` directly from the Godot editor.

- The opening arena wide establishes all six competitors; the acquisition cut
  isolates Blue and the closest contender for a clean gun handoff and aim line.
- The scene is standalone and is not referenced by `project.godot`,
  `app_bootstrap.gd`, or the approved five-shot startup preview.
- Any deliberate input skips to the logo. Press the logo prompt again to test
  the intentionally unlinked handoff card. `R` replays and `Esc` exits.
- The authored rock cue has one fixed `-11.5 dB` level on the Master bus. It
  ignores the game Music slider but still respects Master/OS mute controls.
- Eliminations use silent cinematic confetti and emit no death/party sound.

