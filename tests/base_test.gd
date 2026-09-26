extends Node
## Base for a headless test (tests/test_*.gd, run by tests/run_tests.tscn).
## Override run(); call check() for each assertion. Tests share the live
## autoloads (GameState/Combat/GameData), so each should GameState.reset()
## and use GameState.active_slot = 9 — the runner deletes that slot's file.

var fails := 0
var passes := 0


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("  FAIL ", what)


func run() -> void:
	pass
