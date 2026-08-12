# One Gun

A local arena shooter where **exactly one gun** exists per match and authored melee supplies replenish after pickup. Whoever holds the gun can end anyone in one shot — everyone else's job is to take it from them, dodge it, or beat them to death first.

Play solo against bots, or splitscreen with a friend (plus bots to fill out the arena). Rounds → sets → match, with house rules you can tune and save as presets.

## Requirements

- [Godot 4.7.1](https://godotengine.org/download) (Forward+ rendering, Jolt physics)

## Running the game

Clone/download this repo, open it in the Godot 4.7.1 editor, and run the project.

## Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump | Space | A / Cross |
| Sprint | Shift | Bumper/trigger (configurable hold or toggle) |
| Dash | Ctrl | Button (configurable) |
| Fire / Swing | Left click | Right trigger |
| Aim down sights | Right click | Left trigger |
| Interact / pick up | E or F | Face button |
| Throw item/weapon | G | Button |
| Cycle weapon/item slot | Q / E | Bumpers |

Full control bindings and match settings are configurable in-game under Player Settings and the match lobby.

## Documentation

Project docs live in [`docs/`](docs):

- [`docs/GAME_RULES.md`](docs/GAME_RULES.md) — mechanics, numbers, and match settings
- [`docs/DESIGN.md`](docs/DESIGN.md) — the design intent behind those mechanics
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — technical breakdown of how the systems fit together
- [`docs/TODO.md`](docs/TODO.md) — known gaps and planned work
