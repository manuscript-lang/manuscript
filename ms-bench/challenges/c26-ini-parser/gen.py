import json, random, pathlib

def solve(s):
    lines = s.split("\n")
    if "---" in lines:
        k = lines.index("---"); doc, qs = lines[:k], lines[k + 1:]
    else:
        doc, qs = lines, []
    data, sec = {}, ""
    for raw in doc:
        l = raw.strip(" \t")
        if not l or l[0] in ";#": continue
        if l[0] == "[" and l[-1] == "]":
            sec = l[1:-1].strip(" \t"); continue
        if "=" in l:
            k, v = l.split("=", 1)
            k, v = k.strip(" \t"), v.strip(" \t")
            if len(v) >= 2 and v[0] == '"' and v[-1] == '"': v = v[1:-1]
            if k: data[(sec, k)] = v
    out = []
    for q in qs:
        q = q.strip(" \t")
        if not q: continue
        if "." in q: sec, key = q.split(".", 1)
        else: sec, key = "", q
        out.append(data.get((sec, key), "<missing>"))
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(26)
def rand_ini(nsec, nkeys, nq):
    doc, keys = [], []
    names = ["", ] + [f"sec{i}" for i in range(nsec)]
    for _ in range(nkeys):
        sec = rnd.choice(names); key = f"k{rnd.randint(0, 12)}"
        keys.append((sec, key))
    cur = None
    for sec, key in keys:
        if sec != cur and sec != "":
            doc.append(rnd.choice(["[%s]", "[ %s ]", " [%s]"]) % sec); cur = sec
        elif sec == "" and cur is not None:
            doc.append(f"[{sec}]"); cur = ""
        v = rnd.choice(["", "x", "hello world", '"quoted value"', '" pad "', "a=b", "12", '"', '""'])
        doc.append(rnd.choice(["%s=%s", "%s = %s", "  %s  =  %s  ", "%s\t=\t%s"]) % (key, v))
        if rnd.random() < .15: doc.append(rnd.choice(["; note", "# note", "", "junk line", "=novalue", " = x"]))
    qs = []
    for _ in range(nq):
        sec, key = rnd.choice(keys) if rnd.random() < .85 else (rnd.choice(names), "zz")
        qs.append(f"{sec}.{key}" if sec else key)
    return "\n".join(doc) + "\n---\n" + "\n".join(qs) + "\n"
examples = [
    case("basic", "name = demo\n[server]\nhost = \"example.com\"\nport=8080\n; comment\n[client]\nhost = local host\n---\nname\nserver.host\nserver.port\nclient.host\nclient.port\nnope.x\n"),
    case("overrides", "a=1\na=2\n[s]\nb=1\n[t]\nb=9\n[s]\nb=3\n---\na\ns.b\nt.b\n"),
]
hidden = examples + [
    case("empty", ""),
    case("no-queries", "a=1\n[x]\nb=2\n"),
    case("no-separator-text", "a=1\n---"),
    case("quotes", 'a = "x y"\nb = ""\nc = "\nd = "unterminated\ne = say "hi"\nf = "a"b"\n---\na\nb\nc\nd\ne\nf\n'),
    case("whitespace-and-comments", "  ; c\n\t# c\n  [ sp ace ]  \n\t key \t=\t val ue \t\n=nokey\nnoequals\n---\n sp ace.key \n\n"),
    case("equals-in-value", "url = http://x/?a=b&c=d\n---\nurl\n"),
    case("empty-section-name", "[]\nk=in-empty\n[a]\nk=in-a\n---\n.k\na.k\nk\n"),
    case("global-vs-section", "k=global\n[s]\nk=section\n---\nk\ns.k\nk.s\n"),
    case("first-separator-wins", "a=1\n---\na\n---\n"),
    case("dotted-query-splits-first", "[a]\nb=1\n---\na.b.c\na.b\n"),
    case("random-small", rand_ini(3, 20, 12)),
    case("random-mid", rand_ini(8, 150, 120)),
    case("random-large", rand_ini(30, 1200, 1500)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
