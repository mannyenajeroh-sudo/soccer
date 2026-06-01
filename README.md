# STREET 3

Arcade 3v3 street football (Godot 4.3+). Custom ball physics, walled arena, FIFA Street-style feel.

## Play now

See **[PLAYABLE.md](PLAYABLE.md)** for controls, rules, and test checklist.

```
Open project → F5 → Play → Match
```

## Autoloads

| Name | Role |
|------|------|
| PitchConstants | Arena size, goals, clamps |
| GameState | Score, timer, phases |
| PossessionManager | Ball possession |
| GameplayAI | AI spatial weights |
| GameplayRules | Possession contests |
| ScreenShake | Goal-only camera trauma |
| SoundManager | Audio |
| TimeDilation | Slow-mo on big shots |
| ProgressionSystem | XP |
| AdMobBridge | Reward ads (menu) |

## Sacred: do not change

`BallPhysics.gd` integrator constants: `K_DRAG`, `K_MAGNUS`, `E_BOUNCE`, `MU_*`, `GRAVITY`.

## Project layout

- `scenes/Main.tscn` — menu
- `scenes/MatchScene.tscn` — 3v3 match
- `scenes/Player.tscn` — player prefab
- `scripts/` — all gameplay code

## Production Bible

`STREET3_Production_Bible_REVISED.pdf` in project root.
