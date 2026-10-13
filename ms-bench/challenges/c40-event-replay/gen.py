import json, random, pathlib

def make():
    log, out = {}, []
    dig = lambda x: x.isascii() and x.isdigit()
    def apply(st, ev, ver, strict=True):
        # returns (error_message_or_None); st is dict(state, items)
        typ, a = ev[0], ev[1:]
        state = st["state"]
        if typ == "created":
            if state != "none": return f"invalid created in {state} at v{ver}"
            st["state"] = "open"
        elif typ == "item_added":
            if state != "open": return f"invalid item_added in {state} at v{ver}"
            q, p = int(a[1]), int(a[2])
            old = st["items"].get(a[0], (0, 0))
            st["items"][a[0]] = (old[0] + q, p)
        elif typ == "item_removed":
            if state != "open": return f"invalid item_removed in {state} at v{ver}"
            if a[0] not in st["items"]: return f"no such item {a[0]} at v{ver}"
            del st["items"][a[0]]
        elif typ == "paid":
            if state != "open": return f"invalid paid in {state} at v{ver}"
            if not st["items"]: return f"empty order at v{ver}"
            tot = sum(q * p for q, p in st["items"].values())
            if int(a[0]) != tot: return f"wrong amount expected={tot} at v{ver}"
            st["state"] = "paid"
        elif typ == "shipped":
            if state != "paid": return f"invalid shipped in {state} at v{ver}"
            st["state"] = "shipped"
        elif typ == "cancelled":
            if state not in ("open", "paid"): return f"invalid cancelled in {state} at v{ver}"
            st["state"] = "cancelled"
        return None
    argc = {"created": 0, "item_added": 3, "item_removed": 1, "paid": 1, "shipped": 0, "cancelled": 0}
    def summary(i, st, ver):
        tot = sum(q * p for q, p in st["items"].values())
        out.append(f"{i} state={st['state']} v={ver} items={len(st['items'])} total={tot}")
        for k in sorted(st["items"], key=lambda x: x.encode()):
            q, p = st["items"][k]; out.append(f"  {k} x{q} @{p}")
    def replay(i, n):
        st = {"state": "none", "items": {}}
        for k, ev in enumerate(log[i][:n]): apply(st, ev, k + 1)
        return st
    def feed(line):
        t = line.split()
        if not t: return
        if t[0] == "show":
            if len(t) != 2: out.append("error: bad line"); return
            if t[1] not in log: out.append(f"error: unknown aggregate {t[1]}"); return
            summary(t[1], replay(t[1], len(log[t[1]])), len(log[t[1]])); return
        if t[0] == "at":
            if len(t) != 3: out.append("error: bad line"); return
            if t[1] not in log: out.append(f"error: unknown aggregate {t[1]}"); return
            if not dig(t[2]) or int(t[2]) > len(log[t[1]]): out.append("error: bad version"); return
            summary(t[1], replay(t[1], int(t[2])), int(t[2])); return
        if len(t) < 3: out.append("error: bad line"); return
        i, ver, typ, a = t[0], t[1], t[2], t[3:]
        if not dig(ver): out.append("error: bad version"); return
        cur = len(log.get(i, []))
        if int(ver) != cur + 1: out.append(f"{i}: conflict v={ver} expected={cur + 1}"); return
        if typ not in argc: out.append(f"{i}: unknown event {typ}"); return
        if len(a) != argc[typ] or (typ == "item_added" and (not dig(a[1]) or not dig(a[2]) or int(a[1]) == 0)) or (typ == "paid" and not dig(a[0])):
            out.append(f"{i}: bad arguments for {typ}"); return
        st = replay(i, cur) if i in log else {"state": "none", "items": {}}
        err = apply(st, [typ] + a, cur + 1)
        if err: out.append(f"{i}: {err}"); return
        log.setdefault(i, []).append([typ] + a)
        out.append(f"{i}: {typ} -> {st['state']} v={cur + 1}")
    return feed, out, log

def solve(s):
    feed, out, _ = make()
    for line in s.split("\n"): feed(line)
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(40)
def rand_script(n, ids):
    feed, out, log = make()
    L = []; skus = ["pen", "ink", "cap", "bag", "Axe"]
    def add(l): L.append(l); feed(l)
    for _ in range(n):
        i = rnd.choice(ids); r = rnd.random()
        if r < .06: add(f"show {i}"); continue
        if r < .09: add(f"at {i} {rnd.randint(0, 6)}"); continue
        cur = len(log.get(i, []))
        v = cur + 1 if rnd.random() < .95 else rnd.randint(0, 6)
        st = out[-1] if False else None
        t = rnd.random()
        if cur == 0 and rnd.random() < .85: ev = "created"
        elif t < .55: ev = f"item_added {rnd.choice(skus)} {rnd.choice([1, 2, 5, 1, 2, 0])} {rnd.choice([10, 25, 0, 10])}"
        elif t < .65: ev = f"item_removed {rnd.choice(skus)}"
        elif t < .75:
            items = None
            tot = 0
            if i in log:
                d = {}
                for e in log[i]:
                    if e[0] == "item_added": d[e[1]] = (d.get(e[1], (0, 0))[0] + int(e[2]), int(e[3]))
                    elif e[0] == "item_removed": d.pop(e[1], None)
                tot = sum(q * p for q, p in d.values())
            ev = "paid " + str(tot if rnd.random() < .8 else tot + 1)
        elif t < .78: ev = "shipped"
        elif t < .8: ev = "cancelled"
        elif t < .84: ev = "created"
        else: ev = rnd.choice(["refund 5", "paid x", "item_added pen 1", "paid"])
        add(f"{i} {v} {ev}")
    for i in ids: add(f"show {i}")
    return "\n".join(L) + "\n"
examples = [case("basic", "o1 1 created\no1 1 created\no1 2 item_added pen 3 50\no1 3 item_added ink 1 700\no1 4 paid 100\no1 4 paid 850\no1 5 item_added cap 1 5\nshow o1\nat o1 2\n")]
full = "a 1 created\na 2 item_added x 2 10\na 3 item_added y 1 5\na 4 item_added x 1 12\na 5 item_removed y\na 6 paid 36\na 7 shipped\na 8 cancelled\n"
hidden = examples + [
    case("empty", "show nobody\nat nobody 0\n"),
    case("lifecycle", full + "show a\nat a 0\nat a 1\nat a 2\nat a 3\nat a 4\nat a 5\nat a 6\nat a 7\nat a 8\nat a 9\nat a x\nat a\nshow\nshow a b\n"),
    case("version-checks", "a 2 created\na 1 created\na 1 created\na 3 created\na 0 created\na x created\na 01 item_added p 1 1\na 02 shipped\na -1 created\na\na 2\nb 1\nb\nshow b\nshow a\n"),
    case("bad-arguments", "a 1 created\na 2 item_added p 0 5\na 3 item_added p 1\na 4 item_added p 1 5 6\na 5 item_added p x 5\na 6 item_added p 1 -5\na 7 item_added p 1 5.5\na 8 item_removed\na 9 paid\na 10 paid 1 2\na 11 paid x\na 12 created extra\na 13 shipped now\na 14 frob\nshow a\n"),
    case("state-rules", "a 1 shipped\na 1 paid 0\na 1 item_added p 1 1\na 1 item_removed p\na 1 cancelled\na 1 created\na 2 shipped\na 2 paid 0\na 2 item_removed p\na 2 item_added p 1 1\na 3 item_removed q\na 3 item_removed p\na 4 paid 0\na 4 created\na 4 item_added p 2 3\na 5 paid 5\na 5 paid 6\na 6 created\na 6 item_added p 1 1\na 6 shipped\na 6 shipped\n"),
    case("terminal", "a 1 created\na 2 cancelled\na 3 created\na 3 cancelled\na 3 shipped\nb 1 created\nb 2 item_added z 1 1\nb 3 paid 1\nb 4 cancelled\nb 5 shipped\nb 5 paid 1\nb 5 created\nb 5 item_added z 1 1\nshow a\nshow b\n"),
    case("item-merge-and-order", "a 1 created\na 2 item_added Zed 1 3\na 3 item_added apple 2 5\na 4 item_added Zed 4 7\na 5 item_added _x 1 1\na 6 item_added 10 1 1\na 7 item_added 9 1 1\nshow a\nat a 3\nat a 4\n"),
    case("whitespace", "  a   1\tcreated \n\n\tshow   a\nat a\t0\n   a 2 item_added  p  1   1\nshow a\n"),
    case("random-small", rand_script(60, ["o1", "o2"])),
    case("random-large", rand_script(1500, [f"o{i}" for i in range(40)])),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
