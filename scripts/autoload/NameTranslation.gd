
extends Translation
## Names the game builds from parts and keeps in the save in English:
## heroes ("Roth the Duskrunner"), items ("Savage Mace of the Storm"),
## relics ("Ember Sigil of Renewal") and rift wardens ("Grelm, Greater
## Warden"). The .po can't list every combination, so this translation
## recognises those shapes and assembles the name from its translated parts:
## "Alacakaranlık Koşucusu Roth", "Vahşi Gürz (Fırtına)". Anything else
## gets "" (no match), so the .po and plain English stay in charge.

var _classes := {}    # class/role display names -> true
var _prefixes := {}
var _nouns := {}
var _suffixes := {}
var _relic_types := {}
var _relic_nouns := {}


func _init(lang: String = "tr") -> void:
	locale = lang
	for c in GameData.CLASSES:
		_classes[str(c["name"])] = true
	for c in GameData.CLASS_POOL:
		_classes[str(c["name"])] = true
	for list in GameData.ITEM_AFFIX_PREFIX.values():
		for w in list:
			_prefixes[str(w)] = true
	for list in GameData.ITEM_NOUNS.values():
		for w in list:
			_nouns[str(w)] = true
	for list in GameData.ITEM_AFFIX_SUFFIX.values():
		for w in list:
			_suffixes[str(w)] = true
	for w in GameData.RELIC_SPECIAL_SUFFIX.values():
		_suffixes[str(w)] = true
	for list in GameData.ITEM_EFFECTS.values():
		for e in list:
			_suffixes[str(e["suffix"])] = true
	for w in GameData.RELIC_TYPES:
		_relic_types[str(w)] = true
	for w in Combat.RARITY_NOUNS:
		_relic_nouns[str(w)] = true


func _t(s: String) -> String:
	return String(TranslationServer.translate(s))


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message).strip_edges()
	if s.length() < 4 or s.length() > 60:
		return &""
	# A hero: "Roth the Duskrunner" -> "Alacakaranlık Koşucusu Roth"
	var at := s.find(" the ")
	if at > 0:
		var cls := s.substr(at + 5)
		if _classes.has(cls):
			return StringName("%s %s" % [_t(cls), s.substr(0, at)])
	# A rift warden: "Grelm, Greater Warden" -> "Grelm, Büyük Bekçi"
	if s.ends_with(" Warden") and s.contains(", "):
		var parts := s.trim_suffix(" Warden").rsplit(", ", true, 1)
		if parts.size() == 2 and not parts[1].contains(" "):
			return StringName("%s, %s %s" % [parts[0], _t(parts[1]), _t("Warden")])
	# An item or relic: "<prefix> <noun>[ <of suffix>]" -> "<prefix> <noun> (<suffix>)"
	var suffix := ""
	var head := s
	var of_at := s.find(" of ")
	if of_at > 0:
		suffix = s.substr(of_at + 1)
		head = s.substr(0, of_at)
		if not _suffixes.has(suffix):
			return &""
	var words := head.split(" ")
	if words.size() != 2:
		return &""
	var is_item := _prefixes.has(words[0]) and _nouns.has(words[1])
	var is_relic := _relic_types.has(words[0]) and _relic_nouns.has(words[1])
	if not is_item and not is_relic:
		return &""
	var noun := _t("item:" + words[1])   # a noun that clashes with another word
	if noun.begins_with("item:"):
		noun = _t(words[1])
	var out := "%s %s" % [_t(words[0]), noun]
	if suffix != "":
		out += " (%s)" % _t(suffix)
	return StringName(out)
