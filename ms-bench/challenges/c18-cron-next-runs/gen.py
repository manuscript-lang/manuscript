import json, random, re, pathlib, datetime

RANGES = [("minute", 0, 59), ("hour", 0, 23), ("day-of-month", 1, 31), ("month", 1, 12), ("day-of-week", 0, 6)]

def parse_field(text, lo, hi):
    vals = set()
    for item in text.split(","):
        step = 1
        body = item
        m = re.fullmatch(r"(.*)/([0-9]{1,2})", item)
        if m:
            body, step = m.group(1), int(m.group(2))
            if step < 1: return None
            if body == "*" or re.fullmatch(r"[0-9]{1,2}-[0-9]{1,2}", body): pass
            else: return None
        if body == "*": a, b = lo, hi
        elif re.fullmatch(r"[0-9]{1,2}", body):
            if m: return None
            a = b = int(body)
        else:
            r = re.fullmatch(r"([0-9]{1,2})-([0-9]{1,2})", body)
            if not r: return None
            a, b = int(r.group(1)), int(r.group(2))
            if a > b: return None
        if a < lo or b > hi: return None
        vals.update(range(a, b + 1, step))
    return vals

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    out = []
    for n, l in enumerate(lines, 1):
        if l.strip(" ") == "": continue
        t = l.split(" ")
        pre = f"line {n}:"
        if len(t) != 7: out.append(f"{pre} error: bad line"); continue
        m = re.fullmatch(r"([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})", t[0])
        start = None
        if m:
            try: start = datetime.datetime(*map(int, m.groups()))
            except ValueError: start = None
            if start and not 1970 <= start.year <= 2099: start = None
        if start is None: out.append(f"{pre} error: bad start"); continue
        if not re.fullmatch(r"[0-9]{1,2}", t[1]) or not 1 <= int(t[1]) <= 20: out.append(f"{pre} error: bad count"); continue
        count = int(t[1])
        sets, bad = [], None
        for (name, lo, hi), txt in zip(RANGES, t[2:]):
            v = parse_field(txt, lo, hi)
            if v is None: bad = name; break
            sets.append(v)
        if bad: out.append(f"{pre} error: bad {bad}"); continue
        mi, ho, dom, mo, dow = sets
        runs = []
        day0 = start.date()
        for k in range(3001):
            d = day0 + datetime.timedelta(days=k)
            if d.month not in mo or d.day not in dom or (d.isoweekday() % 7) not in dow: continue
            for h in sorted(ho):
                for mn in sorted(mi):
                    t2 = datetime.datetime(d.year, d.month, d.day, h, mn)
                    if t2 > start:
                        runs.append(t2)
                        if len(runs) == count: break
                if len(runs) == count: break
            if len(runs) == count: break
        if not runs: out.append(f"{pre} never"); continue
        out.append(f"{pre} {len(runs)} runs")
        out.extend(r.strftime("%Y-%m-%d %H:%M") for r in runs)
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(18)
def rand_line():
    f = lambda lo, hi: rnd.choice(["*", f"*/{rnd.randint(1, 7)}", str(rnd.randint(lo, hi)), f"{lo}-{rnd.randint(lo, hi)}".replace(f"{lo}-{lo}", str(lo)), f"{rnd.randint(lo, hi)},{rnd.randint(lo, hi)}"])
    fields = [f(0, 59), f(0, 23), f(1, 31), f(1, 12), f(0, 6)]
    fields = [x if parse_field(x, lo, hi) is not None else "*" for x, (_, lo, hi) in zip(fields, RANGES)]
    d = datetime.datetime(1970, 1, 1) + datetime.timedelta(minutes=rnd.randint(0, 60 * 24 * 365 * 129))
    return f"{d.strftime('%Y-%m-%dT%H:%M')} {rnd.randint(1, 20)} " + " ".join(fields)
examples = [
    case("basic", "2024-02-28T23:59 3 0 0 * * *\n2024-01-31T12:00 2 30 8 29 2 *\n2024-03-01T00:00 2 0 12 * * 1-5/2\n"),
    case("weekdays", "2024-02-28T23:59 3 */15 9-17 * * 1-5\n"),
]
hidden = examples + [
    case("start-excluded", "2024-05-05T10:30 3 30 10 * * *\n2024-05-05T10:29 1 30 10 * * *\n"),
    case("every-minute-rollover", "2023-12-31T23:58 4 * * * * *\n"),
    case("leap-day", "2023-03-01T00:00 5 0 0 29 2 *\n"),
    case("never", "2024-01-01T00:00 3 0 0 31 2 *\n2024-01-01T00:00 3 0 0 31 4,6,9,11 *\n"),
    case("window-limit", "2024-01-01T00:00 10 0 0 29 2 *\n"),
    case("lists-and-steps", "2024-01-01T00:00 8 0,30 8-10,14 * * *\n2024-01-01T00:00 6 5-25/10 */6 1,15 * *\n"),
    case("dow-and-dom-both", "2024-01-01T00:00 4 0 0 13 * 5\n"),
    case("sunday-saturday", "2024-02-24T00:00 4 0 12 * * 0,6\n"),
    case("month-names-rejected-and-fields", "2024-01-01T00:00 1 0 0 * JAN *\n2024-01-01T00:00 1 60 0 * * *\n2024-01-01T00:00 1 0 24 * * *\n2024-01-01T00:00 1 0 0 0 * *\n2024-01-01T00:00 1 0 0 32 * *\n2024-01-01T00:00 1 0 0 * 13 *\n2024-01-01T00:00 1 0 0 * * 7\n"),
    case("bad-syntax", "2024-01-01T00:00 1 */0 * * * *\n2024-01-01T00:00 1 5/2 * * * *\n2024-01-01T00:00 1 5-3 * * * *\n2024-01-01T00:00 1 1,,2 * * * *\n2024-01-01T00:00 1 1, * * * * *\n2024-01-01T00:00 1 -1 * * * *\n2024-01-01T00:00 1 *-5 * * * *\n2024-01-01T00:00 1 1-2-3 * * * *\n2024-01-01T00:00 1 */1/2 * * * *\n2024-01-01T00:00 1 001 * * * *\n2024-01-01T00:00 1 * 1 - * * *\n"),
    case("bad-start-count-tokens", "2024-02-30T00:00 1 * * * * *\n2024-01-01 00:00 1 * * * * *\n1969-12-31T23:59 1 * * * * *\n2100-01-01T00:00 1 * * * * *\n2024-01-01T24:00 1 * * * * *\n2024-1-1T00:00 1 * * * * *\n2024-01-01T00:00 0 * * * * *\n2024-01-01T00:00 21 * * * * *\n2024-01-01T00:00 x * * * * *\n2024-01-01T00:00 001 * * * * *\n2024-01-01T00:00 1 * * * *\n2024-01-01T00:00 1 * * * * * *\n2024-01-01T00:00  1 * * * * *\n"),
    case("check-order", "x y z\nx 99 bad bad bad bad bad\n2024-01-01T00:00 99 bad bad bad bad bad\n2024-01-01T00:00 1 bad bad bad bad bad\n2024-01-01T00:00 1 0 bad bad bad bad\n"),
    case("blank-lines-numbering", "\n  \n2024-01-01T00:00 1 0 12 * * *\n\n2024-01-01T00:00 1 bad\n"),
    case("year-edges", "1970-01-01T00:00 2 0 0 * * 4\n2099-12-31T23:59 3 * * * * *\n2099-12-31T23:58 2 59 23 31 12 *\n"),
    case("random", "\n".join(rand_line() for _ in range(40)) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
