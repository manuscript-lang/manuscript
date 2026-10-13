import json, random, pathlib, re

DIMS = {
    "length": {"mm": 10, "cm": 100, "m": 10000, "km": 10000000, "in": 254, "ft": 3048, "yd": 9144, "mi": 16093440},
    "mass": {"mg": 1, "g": 1000, "kg": 1000000, "oz": 28350, "lb": 453592},
    "time": {"ms": 1, "s": 1000, "min": 60000, "h": 3600000, "d": 86400000},
    "volume": {"ml": 1, "l": 1000, "tsp": 5, "tbsp": 15, "cup": 240, "gal": 3785},
}
TEMPS = ("c", "f", "k")
BUILTIN = {}
for d, us in DIMS.items():
    for u, f in us.items(): BUILTIN[u] = (d, f)
for u in TEMPS: BUILTIN[u] = ("temperature", 0)

def rnd_div(n, d):
    """round n/d half away from zero, d > 0"""
    q = (2 * abs(n) + d) // (2 * d)
    return -q if n < 0 else q

def fmt(m):
    if m == 0: return "0"
    s = "-" if m < 0 else ""
    a = abs(m)
    whole, frac = divmod(a, 1000)
    if frac == 0: return f"{s}{whole}"
    return f"{s}{whole}." + f"{frac:03d}".rstrip("0")

def parse_num(t):
    m = re.fullmatch(r"(-?)([0-9]+)(?:\.([0-9]{1,3}))?", t)
    if not m: return None
    v = int(m.group(2)) * 1000 + (int((m.group(3) or "").ljust(3, "0")) if m.group(3) else 0)
    return -v if m.group(1) else v

def to_c(u, sv):
    if u == "c": return (sv, 1)
    if u == "f": return ((sv - 32000) * 5, 9)
    return (sv - 273150, 1)

def from_c(u, cn, cd):
    if u == "c": return rnd_div(cn, cd)
    if u == "f": return rnd_div(cn * 9 + 32000 * 5 * cd, 5 * cd)
    return rnd_div(cn + 273150 * cd, cd)

def solve(s):
    units = dict(BUILTIN)
    user = set()
    out = []
    for line in s.split("\n"):
        t = line.replace("\t", " ").split()
        if not t: continue
        cmd = t[0]
        if cmd == "define":
            if len(t) != 5 or t[2] != "=": out.append("error: syntax"); continue
            name, v, u = t[1], t[3], t[4]
            if not re.fullmatch(r"[a-z][a-z0-9_]*", name): out.append(f"error: bad name {name}"); continue
            if name in units: out.append(f"error: unit exists {name}"); continue
            if not re.fullmatch(r"[0-9]+", v) or not (1 <= int(v) <= 1000): out.append(f"error: bad number {v}"); continue
            if u in user: out.append(f"error: not a builtin unit {u}"); continue
            if u not in BUILTIN: out.append(f"error: unknown unit {u}"); continue
            d, f = BUILTIN[u]
            if d == "temperature": out.append("error: cannot define temperature unit"); continue
            units[name] = (d, int(v) * f); user.add(name); out.append("ok"); continue
        if cmd == "convert" or cmd == "compare":
            if len(t) != 5 or (cmd == "convert" and t[3] != "to"): out.append("error: syntax"); continue
            if cmd == "convert": vt, ut = [t[1]], [t[2], t[4]]
            else: vt, ut = [t[1], t[3]], [t[2], t[4]]
            vals = []
            bad = None
            for x in vt:
                v = parse_num(x)
                if v is None: bad = x; break
                vals.append(v)
            if bad is not None: out.append(f"error: bad number {bad}"); continue
            unk = next((u for u in ut if u not in units), None)
            if unk is not None: out.append(f"error: unknown unit {unk}"); continue
            if any(abs(v) > 100000000 for v in vals): out.append("error: out of range"); continue
            d1, d2 = units[ut[0]][0], units[ut[1]][0]
            if d1 != d2: out.append(f"error: dimension mismatch {d1} vs {d2}"); continue
            if cmd == "convert":
                v = vals[0]; fu, tu = ut
                if d1 == "temperature":
                    cn, cd = to_c(fu, v)
                    if cn < -273150 * cd: out.append("error: below absolute zero"); continue
                    r = from_c(tu, cn, cd)
                else:
                    r = rnd_div(v * units[fu][1], units[tu][1])
                out.append(f"{fmt(v)} {fu} = {fmt(r)} {tu}")
            else:
                (a, b), (ua, ub) = vals, ut
                if d1 == "temperature":
                    an, ad = to_c(ua, a); bn, bd = to_c(ub, b)
                    if an < -273150 * ad or bn < -273150 * bd: out.append("error: below absolute zero"); continue
                    x, y = an * bd, bn * ad
                else:
                    x, y = a * units[ua][1], b * units[ub][1]
                rel = "<" if x < y else (">" if x > y else "=")
                out.append(f"{fmt(a)} {ua} {rel} {fmt(b)} {ub}")
            continue
        out.append("error: syntax")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}

rnd = random.Random(49)
ALL = list(BUILTIN)
def rnum():
    r = rnd.random()
    if r < .3: return str(rnd.randint(0, 500))
    if r < .6: return f"{rnd.randint(0, 2000)}.{rnd.randint(1, 99)}"
    if r < .7: return "-" + str(rnd.randint(0, 300))
    if r < .8: return f"{rnd.randint(0, 99999)}.{rnd.randint(0, 999):03d}"
    if r < .9: return f"-{rnd.randint(0, 100)}.{rnd.randint(0, 9)}"
    return rnd.choice(["0", "0.5", "100000", "-100000", "100000.001", "1e3", ".5", "5.", "+3", "1.2345", "abc", "-"])
def rline(user):
    r = rnd.random()
    pool = ALL + user
    if r < .55:
        a = rnd.choice(pool)
        if rnd.random() < .85:
            same = [u for u in pool if (units_dim(u, user) == units_dim(a, user))]
            b = rnd.choice(same)
        else: b = rnd.choice(pool + ["zz"])
        return f"convert {rnum()} {a} to {b}"
    if r < .8:
        a = rnd.choice(pool)
        same = [u for u in pool if (units_dim(u, user) == units_dim(a, user))]
        return f"compare {rnum()} {a} {rnum()} {rnd.choice(same)}"
    if r < .93:
        nm = rnd.choice(["pace", "stone", "pint", "hand", "x1", "foot_2", "A", "kg", "m", "l2", "stride", "jug"])
        return f"define {nm} = {rnd.choice(['1', '2', '12', '1000', '1001', '0', '2.5'])} {rnd.choice(ALL + ['pace', 'zz'])}"
    return rnd.choice(["convert 5 m", "convert 5 m in cm", "frob 1", "define x", "compare 1 m 2 m 3", "convert", "units length"])
def units_dim(u, user):
    return BUILTIN[u][0] if u in BUILTIN else "user"

def rand_script(n):
    user = []
    lines = ["define pace = 3 ft", "define jug = 2 gal"]
    user = ["pace", "jug"]
    for _ in range(n): lines.append(rline(user))
    return "\n".join(lines) + "\n"

examples = [case("basic", "convert 1 in to mm\nconvert 100 c to f\nconvert 3 kg to m\nconvert 1.0005 km to m\ndefine mile2 = 2 mi\nconvert 1 mile2 to km\ncompare 1 ft 12 in\n")]
hidden = examples + [
    case("length", "convert 1 mi to km\nconvert 1 km to mi\nconvert 12 in to ft\nconvert 1 yd to ft\nconvert 2.5 m to cm\nconvert 0 m to mm\nconvert 1 mm to km\nconvert 100000 km to mm\nconvert -3.75 ft to in\n"),
    case("mass-volume-time", "convert 1 lb to oz\nconvert 1 kg to lb\nconvert 1 oz to g\nconvert 1 gal to l\nconvert 1 cup to tbsp\nconvert 3 tsp to ml\nconvert 1 d to h\nconvert 90 min to h\nconvert 1 ms to d\nconvert 1.5 h to min\nconvert 7 d to s\n"),
    case("rounding", "convert 1 mm to cm\nconvert 0.005 cm to mm\nconvert 1 ft to m\nconvert -1 ft to m\nconvert 1.5 mg to g\nconvert 1 ms to s\nconvert 0.001 ms to s\nconvert 1 mg to oz\nconvert -1 mg to oz\nconvert 2 mg to oz\nconvert 1 s to d\nconvert 1 tsp to gal\n"),
    case("number-formats", "convert 5 m to m\nconvert 5.0 m to m\nconvert 5.10 m to m\nconvert 007 m to cm\nconvert -0 m to cm\nconvert -0.0 m to cm\nconvert 0.001 m to m\nconvert 12.345 m to cm\nconvert 1.2345 m to cm\nconvert +5 m to cm\nconvert .5 m to cm\nconvert 5. m to cm\nconvert 1e3 m to cm\nconvert 1,5 m to cm\nconvert abc m to cm\nconvert - m to cm\nconvert -.5 m to cm\n"),
    case("temperature", "convert 0 c to f\nconvert 100 c to f\nconvert -40 c to f\nconvert 32 f to c\nconvert 212 f to c\nconvert 0 c to k\nconvert 0 k to c\nconvert 300 k to f\nconvert 98.6 f to c\nconvert 98.6 f to k\nconvert 72 f to f\nconvert 36.6 c to c\nconvert 0 f to c\nconvert -0.001 c to k\nconvert 12.345 k to k\n"),
    case("absolute-zero", "convert -273.15 c to k\nconvert -273.151 c to k\nconvert -459.67 f to c\nconvert -459.671 f to c\nconvert 0 k to f\nconvert -0.001 k to c\nconvert -500 f to k\ncompare -273.15 c 0 k\ncompare -300 c 1 k\ncompare 1 k -300 c\ncompare -459.67 f 0 k\n"),
    case("dimension-mismatch", "convert 1 m to kg\nconvert 1 c to m\nconvert 1 s to ml\nconvert 1 kg to f\ncompare 1 m 1 kg\ncompare 1 c 1 s\nconvert 1 zz to m\nconvert 1 m to zz\nconvert 1 zz to yy\nconvert 1 M to cm\n"),
    case("error-precedence", "convert 1.2345 zz to kg\nconvert 1.2345 m to zz\nconvert 200000 m to kg\nconvert 200000 zz to kg\nconvert 200000 c to c\nconvert -500 c to m\nconvert 1 m to 2 m\nconvert 1 m cm\nconvert 1 m TO cm\ncompare x zz kg y\ncompare 1 zz 2.5555 m\ncompare 1 m x kg\ncompare 200000 m 1 kg\ncompare 1 m 200000 kg\ncompare 200000 m 5 m\n"),
    case("range", "convert 100000 m to mm\nconvert 100000.001 m to mm\nconvert -100000 m to mm\nconvert -100000.001 m to mm\nconvert 99999.999 km to mi\nconvert 100000 mi to mm\nconvert 100000 gal to ml\nconvert 100000 d to ms\nconvert 100000 lb to mg\n"),
    case("define", "define pace = 3 ft\nconvert 10 pace to m\nconvert 1 m to pace\ndefine pace = 4 ft\ndefine m = 4 ft\ndefine Pace = 4 ft\ndefine 2x = 4 ft\ndefine x_1 = 4 ft\ndefine stone = 14 lb\nconvert 1 stone to kg\nconvert 11 stone to lb\nconvert 1 stone to m\ndefine big = 1000 mi\nconvert 100000 big to mm\nconvert 1 mm to big\ncompare 1 big 1000 mi\ncompare 1 big 999.999 mi\ncompare 1 big 99999 mi\n"),
    case("define-errors", "define a = 0 m\ndefine a = 1001 m\ndefine a = 1.5 m\ndefine a = -3 m\ndefine a = 007 m\ndefine b = 2 a\ndefine b = 2 zz\ndefine b = 2 c\ndefine b = 2 k\ndefine c = 2 m\ndefine = 2 m\ndefine d 2 m\ndefine d = 2\ndefine d = 2 m x\nconvert 1 a to cm\nconvert 1 b to cm\nconvert 1 d to cm\n"),
    case("compare", "compare 1 m 100 cm\ncompare 1 m 99 cm\ncompare 1 m 101 cm\ncompare 1 km 1 mi\ncompare 0 c 32 f\ncompare 0 c 273.15 k\ncompare 100 c 200 f\ncompare 5.50 kg 5.5 kg\ncompare -1 ft -12.5 in\ncompare 0 s -0 ms\ncompare 1 d 24 h\n"),
    case("syntax-and-whitespace", "\n  convert\t1   m \t to  cm  \n\nCONVERT 1 m to cm\nconvert 1 m to cm extra\nconvert 1 m to\nunits\ndefine\nfoo bar baz\n   \n\tcompare 2 h 120 min\ncompare 1 m\n"),
    case("random-small", rand_script(60)),
    case("random-large", rand_script(1800)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
