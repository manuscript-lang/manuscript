import json, random, pathlib

def fmt(v): return f"{v // 10}.{v % 10}"

def solve(s):
    assigns, students, out = {}, {}, []
    arity = {"assign": 4, "student": 2, "score": 4, "report": 1}
    dig = lambda x: x.isascii() and x.isdigit()
    for line in s.split("\n"):
        t = line.split()
        if not t: continue
        c = t[0]
        if c not in arity or len(t) != arity[c]: out.append("error: bad command"); continue
        if c == "assign":
            if not (dig(t[2]) and dig(t[3]) and int(t[2]) > 0 and int(t[3]) > 0): out.append("error: bad number"); continue
            if t[1] in assigns: out.append(f"error: assignment exists {t[1]}"); continue
            assigns[t[1]] = (int(t[2]), int(t[3])); out.append("ok")
        elif c == "student":
            if t[1] in students: out.append(f"error: student exists {t[1]}"); continue
            students[t[1]] = {}; out.append("ok")
        elif c == "score":
            if t[1] not in students: out.append(f"error: unknown student {t[1]}"); continue
            if t[2] not in assigns: out.append(f"error: unknown assignment {t[2]}"); continue
            mx = assigns[t[2]][0]
            if not (dig(t[3]) and int(t[3]) <= mx): out.append("error: bad points"); continue
            students[t[1]][t[2]] = int(t[3]); out.append("ok")
        else:
            if not students: out.append("no students"); continue
            T = sum(w for _, w in assigns.values())
            def tenths(st, a):
                mx = assigns[a][0]; p = students[st].get(a, 0)
                return (2000 * p + mx) // (2 * mx)
            fin = {}
            for st in students:
                S = sum(assigns[a][1] * tenths(st, a) for a in assigns)
                fin[st] = (2 * S + T) // (2 * T) if T else 0
            order = sorted(students, key=lambda x: (-fin[x], x.encode()))
            for st in order:
                f = fin[st]; rank = 1 + sum(1 for o in fin.values() if o > f)
                L = "A" if f >= 900 else "B" if f >= 800 else "C" if f >= 700 else "D" if f >= 600 else "F"
                out.append(f"{rank} {st} {fmt(f)} {L}")
            vals = sorted(fin.values()); n = len(vals)
            med = vals[n // 2] if n % 2 else (vals[n // 2 - 1] + vals[n // 2] + 1) // 2
            out.append(f"class: n={n} min={fmt(vals[0])} max={fmt(vals[-1])} mean={fmt((2 * sum(vals) + n) // (2 * n))} median={fmt(med)}")
            cnt = {k: 0 for k in "ABCDF"}
            for f in vals: cnt["A" if f >= 900 else "B" if f >= 800 else "C" if f >= 700 else "D" if f >= 600 else "F"] += 1
            out.append("grades: " + " ".join(f"{k}={cnt[k]}" for k in "ABCDF"))
            for a in sorted(assigns, key=lambda x: x.encode()):
                sm = sum(tenths(st, a) for st in students)
                out.append(f"assignment {a} mean={fmt((2 * sm + n) // (2 * n))}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(39)
def rand_script(ns, na, extra=0):
    L = []
    for i in range(na): L.append(f"assign a{i:02d} {rnd.choice([10, 20, 25, 50, 100, 7, 13])} {rnd.choice([1, 5, 10, 15, 20, 30])}")
    for i in range(ns): L.append(f"student s{rnd.randint(0, 999):03d}")
    names = [l.split()[1] for l in L if l.startswith("student")]
    mx = {l.split()[1]: int(l.split()[2]) for l in L if l.startswith("assign")}
    for _ in range(ns * na):
        a = rnd.choice(list(mx)); s = rnd.choice(names)
        L.append(f"score {s} {a} {min(mx[a], max(0, int(rnd.gauss(mx[a] * .78, mx[a] * .2))))}")
    for _ in range(extra): L.append(rnd.choice(["score nobody a00 5", "score " + names[0] + " zz 5", "score " + names[0] + " a00 9999", "assign x", "report"]))
    L.append("report")
    return "\n".join(L) + "\n"
examples = [case("basic", "assign hw1 20 30\nassign exam 50 70\nstudent ann\nstudent bob\nstudent cy\nscore ann hw1 20\nscore ann exam 41\nscore bob hw1 10\nscore bob exam 46\nreport\n")]
hidden = examples + [
    case("empty", "report\n"),
    case("no-students", "assign a 10 1\nreport\n"),
    case("no-assignments", "student a\nstudent b\nreport\n"),
    case("errors", "assign a 0 5\nassign a 5 0\nassign a x 5\nassign a 5\nassign a 10 5\nassign a 10 5\nstudent s\nstudent s\nscore t a 1\nscore s b 1\nscore s a 11\nscore s a -1\nscore s a 1.5\nscore s a 10\nscore s a\nscore s a 3 4\nnonsense\nreport\n"),
    case("rounding", "assign a 3 1\nassign b 7 2\nstudent x\nstudent y\nstudent z\nscore x a 1\nscore x b 1\nscore y a 2\nscore y b 3\nscore z a 3\nscore z b 7\nreport\n"),
    case("ties-and-ranks", "assign a 10 1\nstudent bob\nstudent amy\nstudent cat\nstudent dan\nstudent eve\nscore bob a 9\nscore amy a 9\nscore cat a 10\nscore dan a 5\nscore eve a 5\nreport\n"),
    case("replace-score", "assign a 100 1\nstudent s\nscore s a 50\nscore s a 91\nreport\nscore s a 10\nreport\n"),
    case("letter-boundaries", "assign a 1000 1\nstudent p\nstudent q\nstudent r\nstudent s\nstudent t\nstudent u\nstudent v\nstudent w\nscore p a 900\nscore q a 899\nscore r a 800\nscore s a 799\nscore t a 700\nscore u a 699\nscore v a 600\nscore w a 599\nreport\n"),
    case("even-median", "assign a 100 1\nstudent a\nstudent b\nstudent c\nstudent d\nscore a a 10\nscore b a 21\nscore c a 50\nscore d a 99\nreport\n"),
    case("whitespace", "  assign\ta  10   2  \n\n\tstudent   s\nscore s\ta 7\n   report\n"),
    case("random-small", rand_script(6, 3)),
    case("random-large", rand_script(150, 12, 40)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
