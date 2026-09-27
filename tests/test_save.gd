extends "res://tests/base_test.gd"
## Save versioning and export/import.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "Backup Test"
	GameState.coins = 1234
	var h := Combat.gen_hero("C", 4)
	GameState.heroes.append(h)
	var text := GameState.export_save_text()
	var d: Dictionary = JSON.parse_string(text)
	check(int(d.get("save_version", 0)) == GameState.SAVE_VERSION, "save stamped with SAVE_VERSION")
	check(GameState.import_save_text("not json", 9) != "", "garbage refused")
	check(GameState.import_save_text("{\"coins\": 5}", 9) != "", "a save without a guild refused")
	var newer := d.duplicate()
	newer["save_version"] = GameState.SAVE_VERSION + 1
	check(GameState.import_save_text(JSON.stringify(newer), 9) != "", "a save from a newer version refused")
	# Round trip through the text: change state, import the old text back.
	GameState.coins = 1
	check(GameState.import_save_text(text, 9) == "", "import accepted")
	check(GameState.load_save() and GameState.coins == 1234 and GameState.guild_name == "Backup Test" and GameState.heroes.size() == 1, "imported save loads back exactly")
	# Unversioned (pre-versioning) saves migrate.
	var old := d.duplicate()
	old.erase("save_version")
	check(GameState.import_save_text(JSON.stringify(old), 9) == "" and GameState.load_save() and GameState.coins == 1234, "an unversioned save still loads")

	# A damaged save falls back to the one before it (.bak).
	GameState.import_save_text(text, 9)
	check(GameState.load_save(), "baseline loads")
	GameState.coins = 777
	GameState.save()   # previous save becomes .bak
	var f := FileAccess.open("user://save_slot_9.json", FileAccess.WRITE)
	f.store_string("{\"guild_na")   # truncated mid-write
	f.close()
	check(GameState.load_save() and GameState.restored_from_backup and GameState.coins == 1234, "a truncated save restores the previous one")
	check(not GameState.slot_summary(9).get("empty", true), "the slot still shows its guild")
	GameState.coins = 5
	GameState.save()
	check(GameState.load_save() and not GameState.restored_from_backup and GameState.coins == 5, "saving again replaces the damaged file")
	# Importing over a slot keeps what was there as .bak.
	check(GameState.import_save_text(text, 9) == "" and FileAccess.file_exists("user://save_slot_9.json.bak"), "the replaced save is kept")
	GameState.delete_slot(9)
	check(not FileAccess.file_exists("user://save_slot_9.json.bak") and GameState.slot_summary(9).get("empty", false), "deleting a slot removes its backup too")
	# Exporting stamps the day.
	GameState.import_save_text(text, 9)
	GameState.load_save()
	GameState.export_save_text()
	check(GameState.last_export_day == GameState.day, "export remembers the day")
	GameState.delete_slot(9)
