extends Node
## Runs every tests/test_*.gd in order and exits non-zero on any failure:
##   godot --headless --path . res://tests/run_tests.tscn
## Pass a name fragment after -- to run a subset:  ... -- relic

const TEST_SLOT := 9


func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		only = a
	var files: Array = Array(DirAccess.get_files_at("res://tests")).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd") and (only == "" or f.contains(only)))
	files.sort()
	var total_pass := 0
	var total_fail := 0
	for f in files:
		GameState.active_slot = TEST_SLOT
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			# A test that doesn't compile fails loudly instead of hanging the run.
			print("FAIL %-34s does not compile" % f.trim_suffix(".gd"))
			total_fail += 1
			continue
		var t: Node = script.new()
		add_child(t)
		# Each test starts from its own seed, so what it rolls doesn't depend
		# on which tests ran before it (a test may seed again itself).
		seed(hash(f))
		await t.run()
		print("%s %-34s %3d passed%s" % ["ok  " if t.fails == 0 else "FAIL", f.trim_suffix(".gd"), t.passes, "" if t.fails == 0 else ", %d failed" % t.fails])
		total_pass += t.passes
		total_fail += t.fails
		t.queue_free()
	var slot_file := "user://save_slot_%d.json" % TEST_SLOT
	for p in [slot_file, slot_file + ".bak", slot_file + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("\n%d test files · %d checks passed · %d failed" % [files.size(), total_pass, total_fail])
	get_tree().quit(1 if total_fail > 0 else 0)
