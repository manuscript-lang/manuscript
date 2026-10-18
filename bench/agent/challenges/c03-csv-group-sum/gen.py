import json, random, re, pathlib
from decimal import Decimal

AMT = re.compile(r"^[0-9]+(\.[0-9]{1,2})?$")

def parse(line):
    if line.startswith('"'):
        end = line.find('"', 1)
        if end < 0 or line[end + 1:end + 2] != ",": return None
        cat, amt = line[1:end], line[end + 2:]
    else:
        parts = line.split(",")
        if len(parts) != 2: return None
        cat, amt = parts
    if '"' in cat or "," in amt or not cat or not AMT.match(amt): return None
    return cat, Decimal(amt)

def solve(s):
    tot, bad = {}, 0
    for line in s.split("\n"):
        line = line.rstrip("\r")
        if line.strip() == "": continue
        r = parse(line)
        if r is None: bad += 1; continue
        tot[r[0]] = tot.get(r[0], Decimal(0)) + r[1]
    out = "".join(f"{k}: {v:.2f}\n" for k, v in sorted(tot.items(), key=lambda kv: kv[0].encode()))
    return out + (f"skipped: {bad}\n" if bad else "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(3)
cats = ["food", "Rent", "a,b", "z", "x y", "café"]
def line():
    c = rnd.choice(cats); a = f"{rnd.randint(0, 999)}.{rnd.randint(0, 99):02d}" if rnd.random() < .7 else str(rnd.randint(0, 50))
    return (f'"{c}"' if "," in c else c) + "," + a
big = "\n".join(line() for _ in range(2000)) + "\n"
examples = [case("basic", 'fruit,1.50\n"a,b",2\nfruit,0.5\noops\nveg,x\n')]
hidden = examples + [
    case("empty", ""), case("blank-lines", "\n\na,1\n\n"), case("all-invalid", "x\ny,\n,3\na,b,c\n"),
    case("float-trap", "a,0.1\na,0.2\na,0.7\n"), case("big-sum", "a,99999999999.99\na,0.01\n"),
    case("byte-order", "b,1\nB,1\na,1\n"), case("amount-forms", "a,1.\na,.5\na,1.234\na,-1\na,+1\na, 1\na,1\n"),
    case("quoted-cat", '"x,y,z",1\n"x,y,z",2.25\n"",1\n"a"b",1\n'), case("no-trailing-newline", "a,1\na,2"),
    case("crlf", "a,1\r\nb,2\r\n"), case("big", big), case("unicode", "café,1\ncafe,2\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
