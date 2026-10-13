import json, random, pathlib, re, datetime

def valid_date(s):
    m = re.fullmatch(r"([0-9]{4})-([0-9]{2})-([0-9]{2})", s)
    if not m: return None
    y, mo, d = map(int, m.groups())
    if not (1970 <= y <= 2100): return None
    try: return datetime.date(y, mo, d)
    except ValueError: return None

def solve(s):
    tasks, nid, out = {}, 1, []
    dig = lambda x: x.isascii() and x.isdigit()
    def fmt(d): return d.isoformat()
    for line in s.split("\n"):
        t = line.split()
        if not t: continue
        c = t[0]
        n = len(t)
        okc = {"add": n >= 4, "done": n == 2, "drop": n == 2, "prio": n == 3, "snooze": n == 3, "list": n == 2, "summary": n == 2, "agenda": n == 3}
        if not okc.get(c): out.append("error: bad command"); continue
        if c == "add":
            if t[1] not in ("1", "2", "3"): out.append("error: bad priority"); continue
            due = None
            if t[2] != "-":
                due = valid_date(t[2])
                if due is None: out.append("error: bad date"); continue
            tasks[nid] = {"p": int(t[1]), "due": due, "title": " ".join(t[3:]), "done": False}
            out.append(f"added {nid}"); nid += 1; continue
        if c in ("done", "drop", "prio", "snooze"):
            k = int(t[1]) if dig(t[1]) else None
            if k not in tasks: out.append(f"error: no such task {t[1]}"); continue
            tk = tasks[k]
            if c == "done":
                if tk["done"]: out.append(f"error: already done {t[1]}"); continue
                tk["done"] = True; out.append("ok")
            elif c == "drop": del tasks[k]; out.append("ok")
            elif c == "prio":
                if t[2] not in ("1", "2", "3"): out.append("error: bad priority"); continue
                tk["p"] = int(t[2]); out.append("ok")
            else:
                if not dig(t[2]): out.append("error: bad days"); continue
                if tk["done"]: out.append(f"error: already done {t[1]}"); continue
                if tk["due"] is None: out.append(f"error: no due date {t[1]}"); continue
                tk["due"] += datetime.timedelta(days=int(t[2])); out.append(f"ok {fmt(tk['due'])}")
            continue
        today = valid_date(t[1])
        if today is None: out.append("error: bad date"); continue
        opn = [(k, v) for k, v in tasks.items() if not v["done"]]
        if c == "list":
            if not opn: out.append("no open tasks"); continue
            def key(kv):
                k, v = kv; od = v["due"] is not None and v["due"] < today
                return (0 if od else 1, v["p"], v["due"] or datetime.date(9999, 12, 31), k)
            for k, v in sorted(opn, key=key):
                od = v["due"] is not None and v["due"] < today
                out.append(f"{'!' if od else '.'} {k} p{v['p']} {fmt(v['due']) if v['due'] else '-'} {v['title']}")
        elif c == "summary":
            done = sum(1 for v in tasks.values() if v["done"])
            od = sum(1 for k, v in opn if v["due"] and v["due"] < today)
            td = sum(1 for k, v in opn if v["due"] and v["due"] == today)
            up = sum(1 for k, v in opn if v["due"] and v["due"] > today)
            nd = sum(1 for k, v in opn if not v["due"])
            out.append(f"open={len(opn)} done={done} overdue={od} today={td} upcoming={up} nodue={nd}")
            fut = [v["due"] for k, v in opn if v["due"] and v["due"] >= today]
            if fut:
                m = min(fut); out.append(f"next: {fmt(m)} x{fut.count(m)}")
            else: out.append("next: none")
        else:
            if not (dig(t[2]) and 1 <= int(t[2]) <= 60): out.append("error: bad days"); continue
            for i in range(int(t[2])):
                d = today + datetime.timedelta(days=i)
                ids = [k for k, v in sorted(opn, key=lambda kv: (kv[1]["p"], kv[0])) if v["due"] == d]
                out.append(f"{fmt(d)}: {','.join(map(str, ids)) if ids else '-'}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(38)
def rdate(lo=2023, hi=2025):
    d = datetime.date(lo, 1, 1) + datetime.timedelta(days=rnd.randint(0, 365 * (hi - lo)))
    return d.isoformat()
def rand_script(n):
    L = []; words = ["write", "call", "buy", "fix", "plan", "review", "ship"]
    for _ in range(n):
        r = rnd.random()
        if r < .35: L.append(f"add {rnd.choice(['1','2','3','3','2','0','4','x'])} {rnd.choice([rdate(2024,2025)] * 3 + ['-', '2024-02-30', '2024-13-01'])} {rnd.choice(words)} {rnd.choice(words)}")
        elif r < .45: L.append(f"done {rnd.randint(1, 20)}")
        elif r < .5: L.append(f"drop {rnd.randint(1, 20)}")
        elif r < .57: L.append(f"prio {rnd.randint(1, 20)} {rnd.randint(1, 3)}")
        elif r < .67: L.append(f"snooze {rnd.randint(1, 20)} {rnd.choice([0, 1, 7, 30, 400])}")
        elif r < .8: L.append(f"list {rdate(2024, 2025)}")
        elif r < .9: L.append(f"summary {rdate(2024, 2025)}")
        else: L.append(f"agenda {rdate(2024, 2025)} {rnd.choice([1, 5, 14, 61, 0])}")
    return "\n".join(L) + "\n"
examples = [case("basic", "add 2 2024-02-28 Write report\nadd 1 - Call mom\nadd 1 2024-03-01 Pay rent\nsnooze 1 2\ndone 2\nlist 2024-03-01\nsummary 2024-03-01\nagenda 2024-02-29 3\n")]
hidden = examples + [
    case("empty", "list 2024-01-01\nsummary 2024-01-01\nagenda 2024-01-01 2\n"),
    case("add-errors", "add\nadd 1 -\nadd 1 - x\nadd 4 - x\nadd 0 - x\nadd 1 2024-1-01 x\nadd 1 2024-02-30 x\nadd 1 2023-02-29 x\nadd 1 2024-02-29 leap\nadd 1 1969-12-31 x\nadd 1 2101-01-01 x\nadd 1 2100-02-29 x\nadd 1 2100-12-31 end\nadd 1 1970-01-01 start\nadd 1 2024-04-31 x\nadd 1 2024-06-30 ok\nadd 1 2024-00-10 x\nadd 1 2024-05-00 x\nadd 1 ２０２４-05-05 x\nlist 2024-01-01\n"),
    case("title-spacing", "add 3   -\tmany   spaced\twords  here \nlist 2000-01-01\nadd 1 - a\nlist 2000-01-01\n"),
    case("state-errors", "add 1 - a\nadd 2 2024-01-01 b\ndone 1\ndone 1\ndone 3\ndone x\ndone 001\ndone 0\ndone -1\ndrop 1\ndrop 1\nadd 1 - c\nprio 1 2\nprio 2 9\nprio 9 9\nprio 3 1\nsnooze 2 x\nsnooze 1 1\nsnooze 3 1\nsnooze 9 q\nsnooze 2 0\ndone 2\nsnooze 2 1\nlist 2024-01-01\nsummary 2024-01-01\n"),
    case("snooze-dates", "add 1 2024-02-28 a\nadd 1 2023-12-31 b\nadd 1 2099-12-31 c\nadd 1 2024-02-29 d\nsnooze 1 1\nsnooze 1 1\nsnooze 1 365\nsnooze 2 1\nsnooze 3 1\nsnooze 4 366\nsnooze 4 36524\nsnooze 4 0001\n"),
    case("ordering", "add 3 2024-05-01 low-overdue\nadd 1 2024-06-01 high-future\nadd 2 - mid-nodue\nadd 1 - high-nodue\nadd 2 2024-05-10 mid-soon\nadd 3 2024-04-01 low-overdue-older\nadd 1 2024-05-10 high-soon\nadd 1 2024-05-10 high-soon-2\nadd 2 2024-05-01 mid-overdue\nlist 2024-05-05\nlist 2024-05-10\nlist 2024-04-01\nlist 2025-01-01\n"),
    case("summary-edges", "add 1 2024-03-10 a\nadd 2 2024-03-10 b\nadd 3 2024-03-12 c\nadd 3 - d\nadd 1 2024-03-09 e\ndone 3\nsummary 2024-03-10\nsummary 2024-03-11\nsummary 2024-03-13\nsummary 2024-03-10x\nsummary 2024-3-10\nsummary\nsummary a b\n"),
    case("agenda", "add 2 2024-02-28 a\nadd 1 2024-02-29 b\nadd 3 2024-02-29 c\nadd 1 2024-03-01 d\nadd 1 2024-12-31 e\nadd 2 2025-01-01 f\nadd 1 2025-01-01 g\ndone 4\nagenda 2024-02-27 5\nagenda 2024-12-30 3\nagenda 2024-02-27 0\nagenda 2024-02-27 61\nagenda 2024-02-27 60\nagenda 2024-02-27 x\nagenda 2024-02-31 2\n"),
    case("year-boundary", "add 1 2100-12-31 last\nagenda 2100-12-30 4\nadd 1 1970-01-01 first\nagenda 1970-01-01 1\nsnooze 1 1\nlist 2100-12-31\n"),
    case("random-small", rand_script(60)),
    case("random-large", rand_script(1500)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
