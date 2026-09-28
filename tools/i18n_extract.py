"""Collects every translatable English line into locale/<lang>.po, keeping
translations already there, and writes locale/<lang>_review.csv (English,
translation, where it's used) for review in a spreadsheet.

  python tools/i18n_extract.py            # tr
  python tools/i18n_extract.py --stats    # counts only

A line is translatable when it goes through tr() / TranslationServer.translate()
or is prose text in the UI code (Labels and Buttons translate their own text).
Game content (names, descriptions) in scripts/autoload/game_data is collected
from its name/desc/label/... fields.
"""
import csv, glob, os, re, sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANG = "tr"
PO = os.path.join(ROOT, "locale", LANG + ".po")
CSV = os.path.join(ROOT, "docs", "translation", LANG + "_review.csv")   # outside the Godot project tree (docs/ has a .gdignore)

UI_FILES = ["scripts/ui/*.gd", "scripts/survivors/SurvivorsView.gd", "scripts/autoload/AudioManager.gd"]
ALL_FILES = ["scripts/**/*.gd"]
CONTENT_FIELDS = ("name", "desc", "hint", "label", "title", "text", "flavor", "subtitle", "foe", "finale", "rule")


def literals(line):
    spans, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "#":
            break
        if c == '"':
            if line.startswith('"""', i):
                break
            j = i + 1
            while j < n and line[j] != '"':
                j += 2 if line[j] == "\\" else 1
            spans.append((i, j + 1))
            i = j + 1
            continue
        if c == "'":
            j = i + 1
            while j < n and line[j] != "'":
                j += 2 if line[j] == "\\" else 1
            i = j + 1
            continue
        i += 1
    return spans


def prose(s):
    if s.startswith(("res://", "user://", "http")):
        return False
    s = re.sub(r"\[/?[a-z_]+(=[^\]]*)?\]", "", s)   # BBCode tags carry no words
    if not re.search(r"[A-Za-z]{2,}", s):
        return False
    if re.fullmatch(r"[a-z0-9_:|./%sdf\-]*", s):
        return False
    return True


def key_like(line, a, b):
    """The literal is a dictionary key, a match pattern, a comparison or an
    API name, not text anyone reads."""
    before = line[:a].rstrip()
    after = line[b:].lstrip()
    if after.startswith(":"):
        return True
    # x["key"] is indexing; a list literal ["A", ..., "Z"] is content
    if re.search(r"[\w\])]\[$", before) or before.endswith("&") or before.endswith("^"):
        return True
    if re.search(r"(==|!=|\bin|\bhas\(|\bget\(|\berase\(|_meta\(|override\(|connect\(|\bmatch|print\(|printerr\(|split\(|\bbus\s*=|theme_type_variation\s*=|contains\(|begins_with\(|ends_with\()\s*$", before):
        return True
    if re.search(r"(==|!=)", after[:3]):
        return True
    return False


def collect():
    found = OrderedDict()   # msgid -> set of "file:line"
    def add(msgid, where):
        if msgid.strip() == "":
            return
        found.setdefault(msgid, set()).add(where)
    ui = set()
    for pat in UI_FILES:
        ui.update(os.path.normcase(os.path.abspath(p)) for p in glob.glob(os.path.join(ROOT, pat)))
    files = sorted(set(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)))
    for f in files:
        rel = os.path.relpath(f, ROOT).replace("\\", "/")
        is_ui = os.path.normcase(os.path.abspath(f)) in ui
        is_data = "/game_data/" in rel
        lines = open(f, encoding="utf-8").read().split("\n")
        for li, line in enumerate(lines, 1):
            s = line.lstrip()
            if s.startswith("#"):
                continue
            for (a, b) in literals(line):
                lit = line[a + 1:b - 1]
                before = line[:a]
                where = "%s:%d" % (rel, li)
                if re.search(r"(\btr|translate)\(\s*$", before):
                    add(lit, where)
                    continue
                if not prose(lit) or key_like(line, a, b):
                    continue
                if is_ui or is_data:
                    # the UI, and game_data (all content: names, word lists,
                    # labels) — keys and ids are filtered out above
                    add(lit, where)
                else:   # content fields ("name": ..., "desc": ...) anywhere
                    m = re.search(r'"(%s)"\s*:\s*$' % "|".join(CONTENT_FIELDS), before)
                    if m:
                        add(lit, where)
    for msgid in extra_ids():
        add(msgid, "locale/extra_msgids.txt")
    return found


def extra_ids():
    """Lines the code builds at runtime (e.g. "front".capitalize()), listed
    one per line in locale/extra_msgids.txt."""
    path = os.path.join(ROOT, "locale", "extra_msgids.txt")
    if not os.path.exists(path):
        return []
    return [l for l in open(path, encoding="utf-8").read().split("\n") if l.strip() and not l.startswith("#")]


def po_escape(s):
    # the literal is already in GDScript escape form (\n, \", \\), which is PO's
    return s


def read_po(path):
    out = {}
    if not os.path.exists(path):
        return out
    cur_id, cur_str, mode = None, None, None
    for raw in open(path, encoding="utf-8").read().split("\n"):
        line = raw.strip()
        if line.startswith("msgid "):
            if cur_id is not None:
                out[cur_id] = cur_str
            cur_id, cur_str, mode = line[7:-1], "", "id"
        elif line.startswith("msgstr "):
            cur_str, mode = line[8:-1], "str"
        elif line.startswith('"') and mode:
            if mode == "id":
                cur_id += line[1:-1]
            else:
                cur_str += line[1:-1]
        elif line == "":
            mode = None
    if cur_id is not None:
        out[cur_id] = cur_str
    out.pop("", None)
    return out


HEADER = '''msgid ""
msgstr ""
"Project-Id-Version: Guildhold\\n"
"Language: %s\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"

'''


def main():
    found = collect()
    have = read_po(PO)
    # --merge batch.json: {English: translation}, both in the source's escaped
    # form (backslash-n, backslash-quote), added over what the .po has.
    if "--merge" in sys.argv:
        import json
        batch = json.load(open(sys.argv[sys.argv.index("--merge") + 1], encoding="utf-8"))
        unknown = [k for k in batch if k not in found]
        for k in unknown:
            print("not in the code (skipped):", k)
        # Godot's % fills slots in order, so a translation must keep the
        # English's %s/%d sequence; one that doesn't is refused.
        spec = re.compile(r"%[-+0#]*\d*(?:\.\d+)?[sdfxXc%]")   # no space flag: "5% dodge" is prose
        slots = lambda t: [x for x in spec.findall(t) if x != "%%"]
        for k, v in list(batch.items()):
            if v and slots(k) != slots(v):
                print("slots out of order (skipped):", k, "=>", v)
                del batch[k]
        have.update({k: v for k, v in batch.items() if k in found and v})
    if "--stats" in sys.argv:
        done = sum(1 for k in found if have.get(k))
        print("%d lines, %d translated, %d to go" % (len(found), done, len(found) - done))
        return
    os.makedirs(os.path.dirname(PO), exist_ok=True)
    with open(PO, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % LANG)
        for msgid, where in found.items():
            f.write("#: %s\n" % " ".join(sorted(where)[:3]))
            f.write('msgid "%s"\n' % po_escape(msgid))
            f.write('msgstr "%s"\n\n' % have.get(msgid, ""))
    with open(CSV, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["English", "Türkçe", "Where"])
        for msgid, where in found.items():
            w.writerow([msgid.replace("\\n", "\n").replace('\\"', '"'), have.get(msgid, "").replace("\\n", "\n").replace('\\"', '"'), sorted(where)[0]])
    done = sum(1 for k in found if have.get(k))
    print("%d lines, %d translated -> %s" % (len(found), done, os.path.relpath(PO, ROOT)))


if __name__ == "__main__":
    main()
