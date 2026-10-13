import json, random, pathlib, re
from collections import defaultdict

def split_fields(line):
    fields, i, n = [], 0, len(line)
    while True:
        if i < n and line[i] == '"':
            i += 1; buf = []
            while i < n:
                if line[i] == '"':
                    if i + 1 < n and line[i + 1] == '"': buf.append('"'); i += 2; continue
                    i += 1; break
                buf.append(line[i]); i += 1
            fields.append("".join(buf))
        else:
            j = line.find(",", i)
            if j < 0: j = n
            fields.append(line[i:j]); i = j
        if i < n and line[i] == ",":
            i += 1
            if i == n: fields.append(""); break
            continue
        break
    return [f.strip(" \t") for f in fields]

def leap(y): return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
def parse_date(s):
    m = re.fullmatch(r"([0-9]{4})-([0-9]{2})-([0-9]{2})", s)
    if m: y, mo, d = int(m[1]), int(m[2]), int(m[3])
    else:
        m = re.fullmatch(r"([0-9]{2})/([0-9]{2})/([0-9]{4})", s)
        if not m: return None
        mo, d, y = int(m[1]), int(m[2]), int(m[3])
    if not 1 <= mo <= 12: return None
    dim = [31, 29 if leap(y) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
    if not 1 <= d <= dim: return None
    return f"{y:04d}-{mo:02d}-{d:02d}"

NUM = re.compile(r"(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.([0-9]{1,2}))?")
def parse_amount(s):
    neg = False
    if len(s) >= 2 and s[0] == "(" and s[-1] == ")":
        neg = True; s = s[1:-1]
        if s.startswith("-"): return None
    elif s.startswith("-"):
        neg = True; s = s[1:]
    if s.startswith("$"): s = s[1:]
    m = NUM.fullmatch(s)
    if not m: return None
    if len(re.sub(r"[^0-9]", "", s)) > 12: return None
    whole = s.split(".")[0].replace(",", "")
    frac = (m[1] or "").ljust(2, "0")
    c = int(whole) * 100 + int(frac or "0")
    return -c if neg else c

def money(c):
    sign = "-" if c < 0 else ""
    c = abs(c)
    return f"{sign}{c // 100:,}.{c % 100:02d}"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    seen_header, seen, tx, errs, dups = False, set(), [], [], 0
    for n, line in enumerate(lines, 1):
        t = line.strip(" \t")
        if not t or t[0] == "#": continue
        if not seen_header: seen_header = True; continue
        f = split_fields(line)
        if len(f) != 4: errs.append((n, "field count")); continue
        date = parse_date(f[0])
        if date is None: errs.append((n, "bad date")); continue
        if not f[1]: errs.append((n, "bad account")); continue
        amt = parse_amount(f[3])
        if amt is None: errs.append((n, "bad amount")); continue
        key = (date, f[1], f[2], amt)
        if key in seen: dups += 1; continue
        seen.add(key); tx.append(key)
    acc = defaultdict(lambda: [0, 0, 0, 0]); months = defaultdict(int)
    for d, a, desc, amt in tx:
        r = acc[a]; r[0] += amt; r[3] += 1
        if amt > 0: r[1] += amt
        if amt < 0: r[2] += -amt
        months[d[:7]] += amt
    out = [f"transactions: {len(tx)}", f"duplicates: {dups}", f"errors: {len(errs)}", "accounts:"]
    for a in sorted(acc):
        r = acc[a]; out.append(f"  {a} balance={money(r[0])} credits={money(r[1])} debits={money(r[2])} count={r[3]}")
    out.append("months:")
    for m in sorted(months): out.append(f"  {m} net={money(months[m])}")
    if tx:
        best = tx[0]
        for t in tx:
            if abs(t[3]) > abs(best[3]): best = t
        out.append(f"largest: {best[0]} | {best[1]} | {best[2]} | {money(best[3])}")
    if errs:
        out.append("errors:")
        out += [f"  line {n}: {r}" for n, r in errs]
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(32)
HDR = "date,account,description,amount\n"
accounts = ["checking", "savings", "card", "Cash", "brokerage"]
descs = ["Payroll", "Rent", "Coffee", "Groceries", "Coffee, beans", 'The "Big" Sale', "Refund", "x"]
def fmt_amount(c):
    neg = c < 0; v = abs(c)
    style = rnd.randrange(6)
    whole, frac = v // 100, v % 100
    if style == 0: s = f"{whole}.{frac:02d}"
    elif style == 1: s = f"{whole:,}.{frac:02d}"
    elif style == 2: s = f"${whole:,}" if frac == 0 else f"${whole:,}.{frac:02d}"
    elif style == 3: s = f"{whole}" if frac == 0 else (f"{whole}.{frac // 10}" if frac % 10 == 0 else f"{whole}.{frac:02d}")
    elif style == 4: s = f"{whole:,}.{frac:02d}"
    else: s = f"${whole}.{frac:02d}"
    if neg: s = rnd.choice(["(%s)", "-%s", "(%s)"]) % s if not s.startswith("$") else rnd.choice(["(%s)", "-%s"]) % s
    return s
def q(f): return '"' + f.replace('"', '""') + '"' if ("," in f or '"' in f) else f
def rand_date():
    y = rnd.choice([2023, 2024, 2024, 2000, 1900]); m = rnd.randint(1, 12); d = rnd.randint(1, 28)
    return rnd.choice([f"{y:04d}-{m:02d}-{d:02d}", f"{m:02d}/{d:02d}/{y:04d}"])
def rand_ledger(n, bad=.12):
    ls, rows = [HDR.rstrip("\n")], []
    for _ in range(n):
        r = rnd.random()
        if rows and r < .06: ls.append(rnd.choice(rows)); continue
        if r < .09: ls.append(rnd.choice(["", "   ", "# comment, here", "  # indented comment"])); continue
        amt = rnd.randint(-250000, 900000) if rnd.random() < .9 else rnd.choice([0, 1, -1, 99999999])
        rec = [rand_date(), rnd.choice(accounts), rnd.choice(descs), fmt_amount(amt)]
        if rnd.random() < bad:
            k = rnd.randrange(8)
            if k == 0: rec[0] = rnd.choice(["2023-02-29", "13/01/2024", "2024-1-5", "2024-04-31", "yesterday", "02/30/2024", "1900-02-29"])
            elif k == 1: rec[1] = ""
            elif k == 2: rec[3] = rnd.choice(["1,23", "12.345", "$-3", "abc", "", "5.", ".5", "1e3", "(-5)", "1234567890123"])
            elif k == 3: rec = rec[:3]
            elif k == 4: rec.append("extra")
            elif k == 5: rec[0] = " " + rec[0] + "\t"
            elif k == 6: rec[1] = "  " + rec[1] + " "
            else: rec[3] = "(" + rec[3] + ")" if not rec[3].startswith("(") else rec[3]
        line = ",".join(q(f) for f in rec)
        rows.append(line); ls.append(line)
    return "\n".join(ls) + "\n"
examples = [
    case("basic", HDR + '2024-01-05,checking,Payroll,"2,500.00"\n01/07/2024, checking ,"Coffee, beans",(12.40)\n2024-01-05,checking,Payroll,"2,500.00"\n2024-02-30,savings,Interest,1.20\n# a note\n2024-02-01,savings,Deposit,$300\n2024-02-02,savings,x\n'),
    case("tiny", HDR + "2024-03-01,a,x,1\n2024-03-02,a,y,-1.5\n"),
]
hidden = examples + [
    case("empty", ""),
    case("header-only", HDR),
    case("comments-before-header", "# exported\n\n" + HDR + "2024-01-01,a,b,5\n"),
    case("date-validation", HDR + "2024-02-29,a,leap,1\n2023-02-29,a,noleap,1\n1900-02-29,a,century,1\n2000-02-29,a,quad,1\n04/31/2024,a,x,1\n2024-13-01,a,x,1\n2024-00-10,a,x,1\n0000-01-01,a,year0,1\n12/31/2024,a,ok,1\n1/2/2024,a,short,1\n"),
    case("amount-forms", HDR + '2024-01-01,a,1,12\n2024-01-01,a,2,-12.5\n2024-01-01,a,3,"$1,234.50"\n2024-01-01,a,4,-$3\n2024-01-01,a,5,(45.00)\n2024-01-01,a,6,"($1,000)"\n2024-01-01,a,7,"1,23"\n2024-01-01,a,8,12.345\n2024-01-01,a,9,$-3\n2024-01-01,a,10,--1\n2024-01-01,a,11,1e3\n2024-01-01,a,12,.5\n2024-01-01,a,13,5.\n2024-01-01,a,14,\n2024-01-01,a,15,"12,345,678"\n2024-01-01,a,16,"-(5)"\n2024-01-01,a,17,0.07\n'),
    case("quoting", HDR + '2024-01-01,"my, account","say ""hi""",5\n2024-01-01,"unterminated,x,5\n2024-01-01,a,"b",1,2\n2024-01-01,a,"",3\n'),
    case("duplicates", HDR + "2024-01-01,a,x,5\n01/01/2024,a,x,5.00\n2024-01-01,a,x,5.01\n2024-01-01,A,x,5\n2024-01-01,a,X,5\n2024-01-01,a,x,5\n"),
    case("largest-tie-and-sign", HDR + "2024-01-01,a,first,-100\n2024-01-02,a,second,100\n2024-01-03,a,small,3\n"),
    case("grouping", HDR + '2024-05-01,a,big,"12,345,678.90"\n2024-05-02,a,neg,"(1,000,000.01)"\n2024-05-03,b,zero,0\n'),
    case("no-trailing-newline", HDR + "2024-01-01,a,b,5"),
    case("random-small", rand_ledger(30)),
    case("random-mid", rand_ledger(400)),
    case("random-large", rand_ledger(4000, .08)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
