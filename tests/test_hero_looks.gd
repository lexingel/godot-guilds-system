extends "res://tests/base_test.gd"
## Colour variants: heroes who'd look identical wear different ones.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var hs: Array[Hero] = []
	for i in 3:
		var h := Combat.gen_hero("C", 5)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		h.cls_id = "mage"
		h.pool_id = "apprentice"
		GameState.heroes.append(h)
		hs.append(h)
	var other := Combat.gen_hero("C", 5)
	other.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	other.cls_id = "warrior"
	other.pool_id = "squire"
	GameState.heroes.append(other)
	GameState.refresh_looks()
	check(hs[0].look == 0 and hs[1].look == 1 and hs[2].look == 2, "the first keeps the art, the others get the next variants (%d %d %d)" % [hs[0].look, hs[1].look, hs[2].look])
	check(other.look == 0, "a hero with their own portrait keeps it as drawn")
	var offer := Combat.gen_hero("C", 5)
	offer.cls_id = "mage"
	offer.pool_id = "apprentice"
	check(GameState.look_for(offer) == 3, "a recruit offer previews the variant it would wear")
	# The first leaves: the others keep theirs (no one changes colour).
	GameState.heroes.erase(hs[0])
	GameState.refresh_looks()
	check(hs[1].look == 1 and hs[2].look == 2, "looks stay put when someone leaves")
	# An evolution to a new portrait picks again.
	hs[2].pool_id = "cinderling"
	GameState.refresh_looks()
	check(hs[2].look == 0 and hs[2].look_of == GameData.portrait_for_hero("mage", "cinderling"), "an evolution picks a look for the new portrait")
	var back := Hero.from_dict(hs[1].to_dict())
	check(back.look == 1 and back.look_of == hs[1].look_of, "the look is saved")
	check(UiKit.look_material(0) == null and UiKit.look_material(1) != null and UiKit.look_material(5) == UiKit.look_material(1), "variants past the last wrap round")
