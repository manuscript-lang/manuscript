import json, random, re, pathlib, datetime

def valid_date(s):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", s): return False
    try: d = datetime.date(int(s[:4]), int(s[5:7]), int(s[8:]))
    except ValueError: return False
    return 2000 <= d.year <= 2099

def hm(s):
    m = re.fullmatch(r"([0-9]{2}):([0-9]{2})", s)
    if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59: return None
    return int(m.group(1)) * 60 + int(m.group(2))

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    rooms, used, book, out = {}, set(), {}, []
    order = []
    for l in lines:
        if l.replace(" ", "") == "": continue
        t = l.split(" ")
        c = t[0]
        if c == "room":
            if len(t) != 3: out.append("error: usage")
            elif not re.fullmatch(r"[a-z][a-z0-9]{0,9}", t[1]): out.append("error: bad room name")
            elif not re.fullmatch(r"[0-9]{1,6}", t[2]) or not 1 <= int(t[2]) <= 500: out.append("error: bad capacity")
            elif t[1] in rooms: out.append("error: room exists")
            else: rooms[t[1]] = int(t[2]); out.append("ok")
        elif c == "book":
            if len(t) != 7: out.append("error: usage"); continue
            _, i, r, d, st, en, at = t
            if not re.fullmatch(r"[a-z0-9-]+", i): out.append("error: bad id"); continue
            if i in used: out.append("error: duplicate id"); continue
            used.add(i)
            a, b = hm(st), hm(en)
            if r not in rooms: out.append("error: unknown room")
            elif not valid_date(d): out.append("error: bad date")
            elif a is None or b is None: out.append("error: bad time")
            elif b <= a: out.append("error: bad range")
            elif a % 15 or b % 15: out.append("error: not aligned")
            elif a < 480 or b > 1200: out.append("error: outside hours")
            elif b - a > 240: out.append("error: too long")
            elif not re.fullmatch(r"[0-9]{1,6}", at) or int(at) < 1: out.append("error: bad attendees")
            elif int(at) > rooms[r]: out.append("error: over capacity")
            else:
                hit = next((x for x in order if book[x]["act"] and book[x]["room"] == r and book[x]["date"] == d and a < book[x]["b"] and book[x]["a"] < b), None)
                if hit: out.append(f"error: conflict with {hit}")
                else:
                    book[i] = dict(room=r, date=d, st=st, en=en, a=a, b=b, n=int(at), act=True)
                    order.append(i); out.append(f"ok {i}")
        elif c == "cancel":
            if len(t) != 2: out.append("error: usage")
            elif t[1] not in book: out.append("error: unknown booking")
            elif not book[t[1]]["act"]: out.append("error: already cancelled")
            else: book[t[1]]["act"] = False; out.append("ok")
        elif c == "report":
            if len(t) != 1: out.append("error: usage"); continue
            for name in sorted(rooms, key=lambda x: x.encode()):
                bs = sorted((x for x in order if book[x]["room"] == name and book[x]["act"]), key=lambda x: (book[x]["date"], book[x]["a"], x.encode()))
                mins = sum(book[x]["b"] - book[x]["a"] for x in bs)
                days = len({book[x]["date"] for x in bs})
                util = 0 if days == 0 else (mins * 200 + 720 * days) // (1440 * days)
                out.append(f"{name} cap={rooms[name]} active={len(bs)} minutes={mins} util={util}%")
                for x in bs:
                    k = book[x]; out.append(f"  {k['date']} {k['st']}-{k['en']} {x} attendees={k['n']}")
            act = sum(1 for x in order if book[x]["act"])
            out.append(f"bookings active={act} cancelled={len(order) - act}")
        else: out.append("error: unknown command")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(20)
def L(*a): return "\n".join(a) + "\n"
big = ["room alpha 10", "room beta 4", "room gamma 25", "room delta 8"]
live = []
for i in range(700):
    k = rnd.random()
    if k < 0.8:
        st = rnd.randrange(8 * 60, 19 * 60, 15); en = min(1200, st + rnd.choice([30, 45, 60, 90, 120]))
        a = rnd.choice(["2024-03-04", "2024-03-05", "2024-03-06"])
        big.append(f"book id{i} {rnd.choice(['alpha','beta','gamma','delta'])} {a} {st//60:02d}:{st%60:02d} {en//60:02d}:{en%60:02d} {rnd.randint(1, 12)}")
        live.append(f"id{i}")
    elif k < 0.95 and live: big.append(f"cancel {rnd.choice(live)}")
    else: big.append("report")
big.append("report")
examples = [case("basic", L("room alpha 10", "room beta 4", "book b1 alpha 2024-03-04 09:00 10:30 6", "book b2 alpha 2024-03-04 10:00 11:00 2", "book b3 beta 2024-03-04 09:00 10:00 5", "book b4 alpha 2024-03-04 10:30 11:30 3", "cancel b1", "book b5 alpha 2024-03-04 09:10 10:00 1", "report"))]
hidden = examples + [
    case("room-errors", L("room", "room a", "room a 1 2", "room A 5", "room 1a 5", "room abcdefghij 5", "room abcdefghijk 5", "room a 0", "room a 501", "room a 500", "room a 5", "room b 1x", "room b -1", "room b 0000010", "room b 1234567", "room b  5", "report")),
    case("book-order", L("room r 10", "book", "book x r 2024-03-04 09:00 10:00", "book X r 2024-03-04 09:00 10:00 1", "book bad_id r 2024-03-04 09:00 10:00 1", "book a1 nope 2024-03-04 09:00 10:00 1", "book a1 nope 2024-03-04 09:00 10:00 1", "book a2 r 2024-13-04 09:00 10:00 1", "book a3 r 2024-03-04 9:00 10:00 1", "book a4 r 2024-03-04 10:00 10:00 1", "book a5 r 2024-03-04 10:15 10:00 1", "book a6 r 2024-03-04 09:10 10:00 1", "book a7 r 2024-03-04 07:45 09:00 1", "book a8 r 2024-03-04 19:00 20:15 1", "book a9 r 2024-03-04 08:00 12:15 1", "book a10 r 2024-03-04 08:00 12:00 0", "book a11 r 2024-03-04 08:00 12:00 11", "book a12 r 2024-03-04 08:00 12:00 10", "book a12 r 2024-03-04 08:00 12:00 10", "report")),
    case("dates", L("room r 5", "book d1 r 2000-01-01 09:00 10:00 1", "book d2 r 1999-12-31 09:00 10:00 1", "book d3 r 2099-12-31 09:00 10:00 1", "book d4 r 2100-01-01 09:00 10:00 1", "book d5 r 2024-02-29 09:00 10:00 1", "book d6 r 2023-02-29 09:00 10:00 1", "book d7 r 2100-02-29 09:00 10:00 1", "book d8 r 2024-4-1 09:00 10:00 1", "book d9 r 2024-04-31 09:00 10:00 1", "book d10 r 2024-00-10 09:00 10:00 1", "report")),
    case("conflicts", L("room r 5", "room s 5", "book c1 r 2024-03-04 09:00 11:00 1", "book c2 r 2024-03-04 12:00 13:00 1", "book c3 r 2024-03-04 10:00 12:30 1", "book c4 r 2024-03-04 11:00 12:00 1", "book c5 r 2024-03-04 08:00 09:00 1", "book c6 s 2024-03-04 09:00 11:00 1", "book c7 r 2024-03-05 09:00 11:00 1", "cancel c1", "book c8 r 2024-03-04 09:00 11:00 1", "book c9 r 2024-03-04 08:00 20:00 1", "report")),
    case("cancel", L("room r 5", "book k1 r 2024-03-04 09:00 10:00 1", "book k2 r 2024-03-04 09:00 10:00 1", "cancel", "cancel k1 k1", "cancel k2", "cancel nope", "cancel k1", "cancel k1", "book k1 r 2024-03-04 09:00 10:00 1", "book k3 r 2024-03-04 09:00 10:00 1", "report")),
    case("limits", L("room r 500", "book m1 r 2024-03-04 08:00 12:00 500", "book m2 r 2024-03-04 12:00 16:01 1", "book m3 r 2024-03-04 12:00 16:15 1", "book m4 r 2024-03-04 12:00 16:00 501", "book m5 r 2024-03-04 12:00 16:00 0000001", "book m6 r 2024-03-04 12:00 16:00 1234567", "book m7 r 2024-03-04 12:00 16:00 007", "book m8 r 2024-03-04 16:00 20:00 12", "book m9 r 2024-03-04 20:00 20:00 12", "book m0 r 2024-03-04 20:00 20:15 1", "report")),
    case("util-rounding", L("room r 9", "room s 9", "room t 9", "book u1 r 2024-03-04 08:00 08:15 1", "book u2 s 2024-03-04 08:00 08:15 1", "book u3 s 2024-03-05 08:00 08:15 1", "book u4 t 2024-03-04 08:00 12:00 1", "book u5 t 2024-03-04 12:00 14:30 1", "book u6 t 2024-03-05 09:00 10:00 1", "report")),
    case("report-order", L("room zed 5", "room a2 5", "room a10 5", "book z3 zed 2024-03-05 09:00 10:00 1", "book z1 zed 2024-03-04 11:00 12:00 1", "book z2 zed 2024-03-04 09:00 10:00 1", "book b1 a2 2024-03-04 09:00 10:00 1", "book A1 a2 2024-03-04 09:00 10:00 1", "book a1 a10 2024-03-04 09:00 10:00 03", "report", "report")),
    case("unknown-and-blank", L("", "   ", "hello", "Room a 5", "report extra", "room a 5", " room a 5", "", "report")),
    case("empty", ""),
    case("big", L(*big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
