import json, random, re, pathlib, datetime

def money(c): return f"{c // 100}.{c % 100:02d}"

def valid_date(s):
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", s): return None
    try: d = datetime.date(int(s[:4]), int(s[5:7]), int(s[8:]))
    except ValueError: return None
    return d if 1970 <= d.year <= 2099 else None

def hm(s):
    m = re.fullmatch(r"([0-9]{2}):([0-9]{2})", s)
    if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59: return None
    return int(m.group(1)) * 60 + int(m.group(2))

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    rates, shifts, out, section = {}, {}, [], None
    accepted = 0; rejected = 0
    for n, l in enumerate(lines, 1):
        if l.strip(" ") == "": continue
        why = None
        if l == "[rates]": section = "rates"; continue
        if l == "[shifts]": section = "shifts"; continue
        if l.startswith("["): section = None; why = "unknown section"
        elif section is None: why = "outside section"
        elif section == "rates":
            m = re.fullmatch(r"([a-z]+)=([0-9]{1,6})", l)
            if not m or not 1 <= int(m.group(2)) <= 100000: why = "bad rate"
            elif m.group(1) in rates: why = "duplicate employee"
            else: rates[m.group(1)] = int(m.group(2))
        else:
            f = l.split(",")
            if len(f) != 5: why = "malformed row"
            else:
                emp, date, st, en, br = f
                d = valid_date(date); a, b = hm(st), hm(en)
                if emp not in rates: why = "unknown employee"
                elif d is None: why = "bad date"
                elif a is None or b is None: why = "bad time"
                elif b <= a: why = "end not after start"
                elif not re.fullmatch(r"[0-9]{1,3}", br): why = "bad break"
                elif int(br) >= b - a: why = "break too long"
                elif any(a < e2 and s2 < b for s2, e2, _ in shifts.get((emp, date), [])): why = "overlapping shift"
                else:
                    shifts.setdefault((emp, date), []).append((a, b, b - a - int(br)))
                    accepted += 1
        if why: out.append(f"line {n}: rejected: {why}"); rejected += 1
    per = {}
    for (emp, date), lst in shifts.items():
        day = (valid_date(date) - datetime.date(1970, 1, 1)).days
        week = day - (day + 3) % 7
        per.setdefault(emp, {}).setdefault(week, 0)
        per[emp][week] += sum(x[2] for x in lst)
    grand = 0
    for emp in sorted(per, key=lambda x: x.encode()):
        r = rates[emp]; reg = ot = tot = 0
        for w, M in per[emp].items():
            rm = min(M, 2400); om = M - rm
            reg += (rm * r + 30) // 60
            ot += (om * r * 3 + 60) // 120
            tot += M
        grand += reg + ot
        out.append(f"{emp} | weeks={len(per[emp])} | worked={tot // 60}:{tot % 60:02d} | regular={money(reg)} | overtime={money(ot)} | total={money(reg + ot)}")
    out.append(f"payroll employees={len(per)} shifts={accepted} rejected={rejected} total={money(grand)}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(19)
def doc(rates, shifts): return "[rates]\n" + "".join(r + "\n" for r in rates) + "[shifts]\n" + "".join(r + "\n" for r in shifts)
big = []
emps = ["ann", "bob", "cy", "dee", "eve", "fay", "gus"]
for _ in range(500):
    d = datetime.date(2024, 1, 1) + datetime.timedelta(days=rnd.randint(0, 40))
    sh = rnd.randint(6, 12); ln = rnd.randint(3, 9)
    big.append(f"{rnd.choice(emps)},{d.isoformat()},{sh:02d}:{rnd.choice([0, 15, 30, 45]):02d},{sh + ln:02d}:{rnd.choice([0, 15, 30, 45]):02d},{rnd.choice([0, 15, 30, 45, 60])}")
examples = [
    case("basic", doc(["ann=2500", "bob=1800"], ["ann,2024-03-04,09:00,17:30,30", "ann,2024-03-05,08:00,18:00,0", "bob,2024-03-04,09:00,12:00,0", "bob,2024-03-04,11:00,13:00,0", "cy,2024-03-04,09:00,10:00,0"])),
    case("overtime", doc(["ann=2000"], [f"ann,2024-03-{d:02d},08:00,17:00,0" for d in (4, 5, 6, 7, 8)] + ["ann,2024-03-09,08:00,10:30,30"])),
]
hidden = examples + [
    case("week-boundaries", doc(["ann=3000"], ["ann,2024-03-03,08:00,18:00,0", "ann,2024-03-04,08:00,18:00,0", "ann,2024-03-10,00:00,23:59,0", "ann,2024-03-11,08:00,09:00,0"])),
    case("overtime-rounding", doc(["ann=1001", "bob=999"], ["ann,2024-03-04,00:00,23:59,0", "ann,2024-03-05,00:00,23:59,0", "ann,2024-03-06,00:00,01:01,0", "bob,2024-03-04,00:00,23:59,0", "bob,2024-03-05,00:00,23:59,1", "bob,2024-03-06,00:00,00:01,0"])),
    case("exactly-forty", doc(["ann=1500"], [f"ann,2024-03-{d:02d},09:00,17:00,0" for d in (4, 5, 6, 7, 8)])),
    case("touching-and-overlap", doc(["ann=1000"], ["ann,2024-03-04,09:00,12:00,0", "ann,2024-03-04,12:00,15:00,0", "ann,2024-03-04,11:59,12:01,0", "ann,2024-03-04,08:00,09:00,0", "ann,2024-03-04,08:59,09:01,0", "ann,2024-03-04,07:00,18:00,0", "ann,2024-03-05,09:00,12:00,0"])),
    case("shift-errors", doc(["ann=1000"], ["ann,2024-03-04,9:00,12:00,0", "ann,2024-03-04,09:00,24:00,0", "ann,2024-03-04,09:60,12:00,0", "ann,2024-03-04,12:00,12:00,0", "ann,2024-03-04,13:00,12:00,0", "ann,2024-03-04,09:00,10:00,60", "ann,2024-03-04,09:00,10:00,59", "ann,2024-03-04,09:00,10:00,1000", "ann,2024-03-04,09:00,10:00,x", "ann,2024-03-04,09:00,10:00,", "ann,2024-03-04,09:00,10:00,-1", "ann,2024-03-04,09:00,10:00", "ann,2024-03-04,09:00,10:00,0,0"])),
    case("date-errors", doc(["ann=1000"], ["ann,2024-02-30,09:00,10:00,0", "ann,2024-2-3,09:00,10:00,0", "ann,1969-12-31,09:00,10:00,0", "ann,2100-01-01,09:00,10:00,0", "ann,2099-12-31,09:00,10:00,0", "ann,1970-01-01,09:00,10:00,0", "ann,2024-02-29,09:00,10:00,0", "ann,2023-02-29,09:00,10:00,0", "ann,24-03-04,09:00,10:00,0"])),
    case("rate-errors", "[rates]\nann=0\nann=100001\nann=100000\nann=5\nANN=5\nbob=\nbob\n=5\nbob=1x\nbob=1234567\ncy = 5\n[shifts]\nann,2024-03-04,09:00,10:00,0\n"),
    case("sections", "ann=5\n[rates]\nann=1000\n[extra]\nbob=5\n[shifts]\nann,2024-03-04,09:00,10:00,0\n[Rates]\n[shifts]\nann,2024-03-05,09:00,10:00,0\n[rates]\nbob=900\nbob,2024-03-06,09:00,10:00,0\n[shifts]\nbob,2024-03-06,09:00,10:00,0\n"),
    case("unknown-and-late-rate", doc(["ann=1000"], ["bob,2024-03-04,09:00,10:00,0", "ann,2024-03-04,09:00,10:00,0"]) + "[rates]\nbob=2000\n[shifts]\nbob,2024-03-04,09:00,10:00,0\n"),
    case("no-shifts", doc(["ann=1000"], [])),
    case("blank-lines-numbering", "\n  \n[rates]\n\nann=1000\n  \n[shifts]\n\nbad\nann,2024-03-04,09:00,10:00,0\n"),
    case("empty-input", ""),
    case("big", doc([f"{e}={rnd.randint(1200, 4500)}" for e in emps], big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
