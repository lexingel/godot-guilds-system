# Tests

Headless checks for the game rules (no UI). Run from the project root:

    godot --headless --path . res://tests/run_tests.tscn          # everything
    godot --headless --path . res://tests/run_tests.tscn -- relic # files whose name contains "relic"

Each `test_*.gd` extends `base_test.gd`, overrides `run()` and calls `check()`.
Tests share the live autoloads, so reset `GameState` and use save slot 9 (the
runner deletes it afterwards). A GDScript runtime error stops a test without
failing a check, so also watch for `SCRIPT ERROR` in the output — CI fails on it. The same suite runs on every push
(`.github/workflows/tests.yml`).

`sim/balance_sim.tscn` plays ~600 full rifts across five party profiles and
prints clear rates; run it after balance changes (about a minute).
