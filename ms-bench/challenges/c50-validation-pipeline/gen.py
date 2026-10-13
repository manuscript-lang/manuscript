import json, random, pathlib, re

NAME = re.compile(r"[a-z_][a-z0-9_]*\Z")
INT = re.compile(r"-?[0-9]+\Z")
# word -> (arg count after the word, kinds); kinds: f field, i int, n nonneg int, t any token
STEPS = {
    "trim": "f", "lower": "f", "default": "ft", "required": "f", "int": "fii", "len": "fnn",
    "oneof": "ft", "pattern": "ft", "unique": "f", "less": "ff", "needs": "ftf",
}

def ws_split(l): return l.replace("\t", " ").split()

def parse_steps(lines):
    steps = []
    for no, line in lines:
        t = ws_split(line)
        if not t: continue
        w = t[0]
        if w not in STEPS: return None, f"pipeline error: line {no}: unknown step {w}"
        kinds = STEPS[w]
        ok = len(t) == 1 + len(kinds)
        if ok:
            for k, a in zip(kinds, t[1:]):
                if k == "f" and not NAME.match(a): ok = False
                if k == "i" and not INT.match(a): ok = False
                if k == "n" and not re.fullmatch(r"[0-9]+", a): ok = False
            if ok and w in ("int", "len") and int(t[2]) > int(t[3]): ok = False
        if not ok: return None, f"pipeline error: line {no}: bad arguments for {w}"
        steps.append({"w": w, "t": t, "label": " ".join(t)})
    return steps, None

def glob(mask, s):
    m, n = len(mask), len(s)
    dp = [[False] * (n + 1) for _ in range(m + 1)]
    dp[0][0] = True
    for i in range(1, m + 1):
        c = mask[i - 1]
        for j in range(n + 1):
            if c == "*": dp[i][j] = dp[i - 1][j] or (j > 0 and dp[i][j - 1])
            elif j == 0: dp[i][j] = False
            else:
                ch = s[j - 1]
                if c == "9": good = "0" <= ch <= "9"
                elif c == "a": good = "a" <= ch <= "z" or "A" <= ch <= "Z"
                else: good = ch == c
                dp[i][j] = dp[i - 1][j - 1] and good
    return dp[m][n]

def run_step(st, rec, seen):
    w, t = st["w"], st["t"]
    f = t[1]
    v = rec.get(f)
    if w == "trim":
        if v is not None: rec[f] = v.strip(" \t")
    elif w == "lower":
        if v is not None: rec[f] = "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in v)
    elif w == "default":
        if v is None or v == "": rec[f] = t[2]
    elif w == "required":
        if v is None or v == "": return f"{f} is required"
    elif w == "int":
        if v is None: return None
        if not INT.match(v): return f"{f} is not an integer"
        if not (int(t[2]) <= int(v) <= int(t[3])): return f"{f} out of range {int(t[2])}..{int(t[3])}"
    elif w == "len":
        if v is None: return None
        if not (int(t[2]) <= len(v) <= int(t[3])): return f"{f} length out of range {int(t[2])}..{int(t[3])}"
    elif w == "oneof":
        if v is None: return None
        if v not in t[2].split("|"): return f"{f} not one of {t[2]}"
    elif w == "pattern":
        if v is None: return None
        if not glob(t[2], v): return f"{f} does not match {t[2]}"
    elif w == "unique":
        if v is None: return None
        if v in seen.get(f, {}): return f"{f} duplicates record {seen[f][v]}"
    elif w == "less":
        a, b = rec.get(t[1]), rec.get(t[2])
        if a is None or b is None: return None
        if not INT.match(a): return f"{t[1]} is not an integer"
        if not INT.match(b): return f"{t[2]} is not an integer"
        if not int(a) < int(b): return f"{t[1]} must be less than {t[2]}"
    elif w == "needs":
        if v is None or v != t[2]: return None
        o = rec.get(t[3])
        if o is None or o == "": return f"{t[3]} is required when {f}={t[2]}"
    return None

def parse_record(line):
    rec = {}
    for piece in line.split(","):
        i = piece.find("=")
        if i < 0 or not NAME.match(piece[:i]): return None, f"bad field '{piece}'"
        k = piece[:i]
        if k in rec: return None, f"duplicate key {k}"
        rec[k] = piece[i + 1:]
    return rec, None

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    sep = next((i for i, l in enumerate(lines) if l.strip(" \t") == "---"), None)
    step_lines = [(i + 1, l) for i, l in enumerate(lines[:sep] if sep is not None else lines)]
    rec_lines = lines[sep + 1:] if sep is not None else []
    steps, err = parse_steps(step_lines)
    if err: return err + "\n"
    out = []
    seen = {}
    fails = [0] * len(steps); parse_fails = 0; ok_count = 0; total = 0
    uniq = [st["t"][1] for st in steps if st["w"] == "unique"]
    for line in rec_lines:
        if not line.strip(" \t"): continue
        total += 1
        rec, perr = parse_record(line)
        if perr:
            parse_fails += 1; out.append(f"record {total}: FAILED parse: {perr}"); continue
        failed = False
        for i, st in enumerate(steps):
            msg = run_step(st, rec, seen)
            if msg:
                fails[i] += 1; failed = True
                out.append(f"record {total}: FAILED step {i + 1} ({st['label']}): {msg}"); break
        if failed: continue
        ok_count += 1
        for f in uniq:
            if f in rec: seen.setdefault(f, {}).setdefault(rec[f], total)
        out.append(f"record {total}: ok " + ",".join(f"{k}={rec[k]}" for k in sorted(rec, key=lambda x: x.encode())))
    out.append(f"summary records={total} ok={ok_count} failed={total - ok_count}")
    if parse_fails: out.append(f"failed at parse: {parse_fails}")
    for i, st in enumerate(steps):
        if fails[i]: out.append(f"failed at step {i + 1} ({st['label']}): {fails[i]}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}

PIPE = """trim name
lower email
default role user
required name
required email
len name 2 12
pattern email *@*.*
oneof role admin|user|guest
int age 0 120
unique email
less age retire
needs role admin level
---
"""
rnd = random.Random(50)
GOOD_NAMES = ["ann", "bob", "Cy", "  eve ", "Frank", "hal", " gwen", "ivy  "]
def rand_records(n):
    L = []
    for i in range(n):
        role = rnd.choice(["admin", "user", "guest", None, None])
        age = rnd.randint(0, 100)
        f = {"name": rnd.choice(GOOD_NAMES), "email": rnd.choice([f"U{i}@X.IO", f"u{i}@x.io"]), "age": str(age)}
        if role: f["role"] = role
        if rnd.random() < .6: f["retire"] = str(age + rnd.randint(1, 30))
        if role == "admin": f["level"] = str(rnd.randint(1, 5))
        r = rnd.random()
        if r < .35:
            bad = rnd.choice(["name", "email", "email-dup", "role", "age", "agerange", "retire", "level", "parse", "dupkey", "drop-name", "drop-email"])
            if bad == "name": f["name"] = rnd.choice(["", "d", "waytoolongname12345"])
            elif bad == "email": f["email"] = rnd.choice(["nope", "a@b", ""])
            elif bad == "email-dup": f["email"] = rnd.choice(["u1@x.io", "U1@X.IO", "u2@x.io"])
            elif bad == "role": f["role"] = rnd.choice(["root", "", "ADMIN"])
            elif bad == "age": f["age"] = rnd.choice(["x", "-", " 5", "5.5"])
            elif bad == "agerange": f["age"] = rnd.choice(["121", "-1", "9999"])
            elif bad == "retire": f["retire"] = str(max(age - rnd.randint(0, 3), 0)) if rnd.random() < .7 else "z"
            elif bad == "level": f["role"] = "admin"; f.pop("level", None)
            elif bad == "drop-name": f.pop("name")
            elif bad == "drop-email": f.pop("email")
        keys = list(f)
        rnd.shuffle(keys)
        line = ",".join(f"{k}={f[k]}" for k in keys)
        if r >= .35 and r < .40: line += ",oops"
        if r >= .40 and r < .43: line += ",age=1"
        L.append(line)
    return "\n".join(L) + "\n"

examples = [case("basic", "trim name\nrequired name\nint age 0 120\n---\nname= bob ,age=30\nname=,age=5\nname=al,age=200\nname=cy,age=x\n")]
hidden = examples + [
    case("full-pipeline", PIPE + "name= ann ,email=ANN@Example.COM,age=30,retire=65\nname=bob,email=bob@x.io,role=admin,level=3\nname=bob,email=bob@x.io\nname=cy,email=nope\nname=d,email=d@e.f\nname=eve,email=eve@e.f,role=root\nname=zed,email=ann@example.com\nname=fay,email=fay@e.f,role=admin\nname=gus,email=gus@e.f,age=40,retire=30\nname=hal,email=hal@e.f,age=abc\n"),
    case("no-steps", "---\na=1\nb=2,a=3\n\nz=\n"),
    case("no-records", "required a\n---\n"),
    case("no-separator", "required a\nint b 1 2\n"),
    case("transforms", "trim a\nlower a\ndefault b fallback\ndefault c -\n---\na=  HeLLo World \t,b=\na=X,b=given,c=\nc=1\nA=1\n"),
    case("required-vs-empty", "required a\n---\na=\na=x\nb=1\na= \n"),
    case("int-step", "int n -10 10\n---\nn=0\nn=-10\nn=10\nn=11\nn=-11\nn=+5\nn=5.0\nn=\nn=007\nn=-0\nn=1 \nm=1\nn=99999999999\n"),
    case("len-step", "len s 2 4\n---\ns=a\ns=ab\ns=abcd\ns=abcde\ns=\nt=1\ns=a b\ns=   \n"),
    case("oneof-step", "oneof color red|green|\n---\ncolor=red\ncolor=green\ncolor=\ncolor=Red\ncolor=re\nsize=1\n"),
    case("pattern-step", "pattern code aaa-9999\npattern mail *@*.*\npattern id 9*\npattern any *\n---\ncode=abc-1234,mail=a@b.c,id=1,any=\ncode=ab-12345,mail=a@b.c,id=1\ncode=ABC-12x4,mail=a@b.c,id=1\ncode=abc-1234,mail=a@b,id=1\ncode=abc-1234,mail=@.,id=1x\ncode=abc-1234,mail=a@b.c.d,id=\ncode=abc-1234,mail=a@b.c,id=99\ncode=abc*1234\n"),
    case("unique", "unique k\nlower k\nrequired v\n---\nk=A,v=1\nk=a,v=1\nk=B,v=\nk=B,v=2\nk=B,v=3\nv=9\nv=8\nk=b,v=1\nk=C,v=1\nk=c,v=1\n"),
    case("unique-two-fields", "unique a\nunique b\n---\na=1,b=1\na=2,b=1\na=1,b=2\na=3,b=3\na=3\nb=3\nc=1\n"),
    case("less-step", "less lo hi\n---\nlo=1,hi=2\nlo=2,hi=2\nlo=3,hi=2\nlo=x,hi=2\nlo=1,hi=y\nlo=x,hi=y\nlo=1\nhi=1\nlo=-5,hi=-4\nlo=09,hi=10\nlo=,hi=1\n"),
    case("needs-step", "needs kind big size\n---\nkind=big,size=1\nkind=big,size=\nkind=big\nkind=small\nsize=1\nkind=Big\nkind=big,size= \n"),
    case("first-failure-wins", "required a\nint a 1 5\nlen a 2 3\noneof a 1|22|333\nless a b\n---\na=\na=x\na=7\na=1\na=22,b=1\na=22,b=x\na=2\n"),
    case("parse-errors", "required a\n---\na=1\nbad\na=1,,b=2\n=1\na=1,a=2\na=1,\nA=1\na b=1\n a=1\na=1=2\nb==\n,a=1\n"),
    case("whitespace-records", "trim a\n---\n  \n\t\na= x \n   a=y\na=z   \n"),
    case("pipeline-error-unknown", "required a\nfrobnicate b\nint x 1 2\n---\na=1\n"),
    case("pipeline-error-args", "\n\nrequired a\nint x 5 1\n---\na=1\n"),
    case("pipeline-error-args-2", "required\n---\na=1\n"),
    case("pipeline-error-field", "required Bad\n---\na=1\n"),
    case("pipeline-error-int", "int x 1 a\n---\n"),
    case("pipeline-error-len", "len x -1 3\n---\n"),
    case("pipeline-error-extra", "trim a b\n---\n"),
    case("pipeline-error-first", "int x 1\nbogus\n---\n"),
    case("step-labels", "  trim   a\t\nint\tn   -5   5\n---\na= 1 ,n=9\n"),
    case("random-small", PIPE + rand_records(40)),
    case("random-large", PIPE + rand_records(1500)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
