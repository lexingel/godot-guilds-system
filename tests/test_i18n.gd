extends "res://tests/base_test.gd"
## Turkish: the translation loads and switches with the locale, and every
## translated line keeps its English's %s / %d slots in the same order
## (Godot's % fills them in order, so a mismatch would garble the text).


func _slots(s: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string(r"%[-+0#]*\d*(?:\.\d+)?[sdfxXc%]")   # no space flag: "5% dodge" is prose
	for m in re.search_all(s):
		if m.get_string() != "%%":
			out.append(m.get_string())
	return out


func run() -> void:
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("tr")
	check(tr("New Game") == "Yeni Oyun", "Turkish loads: New Game → %s" % tr("New Game"))
	check(tr("Victory!") == "Zafer!", "and switches with the locale")
	check((tr("%d kills") % 5) == "5 öldürme", "formatted lines translate before the numbers go in")
	var kw := func(text: String) -> Array:
		var hits := []
		for k in GameData.keyword_regexes():
			if (k[2] as RegEx).search(text) != null:
				hits.append(k[0])
		return hits
	check(kw.call("+%5 kaçınma şansı").has("Dodge"), "Turkish glossary hovers: kaçınma → Dodge")
	check(kw.call("İlk vuruş hasarı").has("First-strike"), "İlk vuruş → First-strike (dotted capital İ)")
	check(kw.call("Ekip iyileşiyor.").has("Mend") and kw.call("İyileştirme").has("Mend"), "iyileş… → Mend")
	check(kw.call("ön sırada").has("Formation"), "ön sıra → Formation")
	check(not kw.call("hızlı").has("Speed"), "hız doesn't catch hızlı (fast)")
	check(kw.call("◆ Sıyrılma").has("Evasion") and not kw.call("◆ Sıyrılma").has("Dodge"), "Sıyrılma → Evasion, not Dodge")
	check(not kw.call("darbeden sıyrıldı").has("Evasion"), "the dodge log's sıyrıldı stays unhovered")
	check(kw.call("turda ilk davrandığında").has("Turn order") and kw.call("ekip bu tur önce davranır").has("Turn order"), "ilk/önce davran… → Turn order")
	TranslationServer.set_locale("en")
	check(kw.call("+5% dodge chance").has("Dodge") and not kw.call("kaçınma şansı").has("Dodge"), "English glossary back to English only")
	check(tr("New Game") == "New Game", "English stays English")
	TranslationServer.set_locale(was)

	var t: Translation = load("res://locale/tr.po")
	check(t != null and t.get_message_count() > 500, "the Turkish file has its lines (%d)" % (t.get_message_count() if t else 0))
	var bad: Array[String] = []
	var done := 0
	for msgid in t.get_message_list():
		var msg := String(t.get_message(msgid))
		if msg == "":
			continue
		done += 1
		if _slots(String(msgid)) != _slots(msg):
			bad.append("%s => %s" % [msgid, msg])
	check(bad.is_empty(), "every translated line keeps its slots in order (%d checked)%s" % [done, "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 3))])
	check(GameData.LANGUAGES.any(func(l): return str(l[0]) == "tr"), "Turkish is offered in Settings")
