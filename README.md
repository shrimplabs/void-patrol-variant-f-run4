# Void Patrol

Void Patrol is a Godot 4 top-down space shooter built as an autonomous agent
game-development run.

Fight through escalating enemy waves, collect power-ups, survive the boss, and
push your score across repeated loops.

## Controls

- Move: WASD or arrow keys
- Fire: Space
- Start / confirm: Enter or Space
- Pause / menu back: Escape

## Run

Open the project in Godot 4.6 or newer and run `scenes/main.tscn`.

From a terminal with Godot on your PATH:

```sh
godot --path .
```

## Test

```sh
godot --headless --path . --script check_scripts.gd --quit
```

## Agent Artifacts

This repository intentionally preserves generated development artifacts from
the autonomous build run, including agent notes, validation state, research
notes, and scratch validation scripts. They are kept as provenance for studying
how the project was produced.
