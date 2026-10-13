import sys, json, random, pathlib, re
sys.setrecursionlimit(100000)

LIMIT = 10 ** 15
class Syn(Exception): pass

def num(n):
    assert abs(n) <= LIMIT, n
    return ("num", n)
ZERO, ONE, TWO, MONE = num(0), num(1), num(2), num(-1)

def parse_line(line):
    toks = re.findall(r"[()]|[^\s()]+", line.replace("\t", " "))
    pos = [0]
    def peek(): return toks[pos[0]] if pos[0] < len(toks) else None
    def nxt():
        t = peek()
        if t is None: raise Syn()
        pos[0] += 1; return t
    def atom(t):
        if re.fullmatch(r"-?[0-9]+", t): return num(int(t))
        if re.fullmatch(r"[a-z][a-z0-9_]*", t): return ("var", t)
        raise Syn()
    def expr():
        t = nxt()
        if t == ")": raise Syn()
        if t != "(": return atom(t)
        head = nxt()
        if head not in ("+", "-", "*", "neg", "^"): raise Syn()
        args = []
        while peek() != ")":
            if peek() is None: raise Syn()
            if head == "^" and len(args) == 1:
                t2 = nxt()
                if not re.fullmatch(r"[0-9]+", t2): raise Syn()
                args.append(int(t2))
            else:
                args.append(expr())
        nxt()
        if head == "neg" and len(args) == 1: return ("neg", args[0])
        if head == "^" and len(args) == 2: return ("pow", args[0], args[1])
        if head in "+-*" and head != "neg" and len(args) == 2: return ({"+": "add", "-": "sub", "*": "mul"}[head], args[0], args[1])
        raise Syn()
    e = expr()
    if peek() is not None: raise Syn()
    return e

def simp(e):
    k = e[0]
    if k in ("num", "var"): return e
    if k == "neg": return rw(("neg", simp(e[1])))
    if k == "pow": return rw(("pow", simp(e[1]), e[2]))
    return rw((k, simp(e[1]), simp(e[2])))

def isnum(e): return e[0] == "num"

def rw(e):
    k = e[0]
    if k == "add":
        l, r = e[1], e[2]
        if isnum(l) and isnum(r): return num(l[1] + r[1])
        if l == ZERO: return r
        if r == ZERO: return l
        if l == r: return simp(("mul", TWO, l))
        if r[0] == "neg": return simp(("sub", l, r[1]))
        if l[0] == "neg": return simp(("sub", r, l[1]))
    elif k == "sub":
        l, r = e[1], e[2]
        if isnum(l) and isnum(r): return num(l[1] - r[1])
        if r == ZERO: return l
        if l == ZERO: return simp(("neg", r))
        if l == r: return ZERO
        if r[0] == "neg": return simp(("add", l, r[1]))
    elif k == "mul":
        l, r = e[1], e[2]
        if isnum(l) and isnum(r): return num(l[1] * r[1])
        if l == ZERO or r == ZERO: return ZERO
        if l == ONE: return r
        if r == ONE: return l
        if l == MONE: return simp(("neg", r))
        if r == MONE: return simp(("neg", l))
        if l == r: return simp(("pow", l, 2))
        if isnum(r): return simp(("mul", r, l))
        if l[0] == "neg" and r[0] == "neg": return simp(("mul", l[1], r[1]))
        if l[0] == "neg": return simp(("neg", ("mul", l[1], r)))
        if r[0] == "neg": return simp(("neg", ("mul", l, r[1])))
        if l[0] == "pow" and r[0] == "pow" and l[1] == r[1]: return simp(("pow", l[1], l[2] + r[2]))
        if l[0] == "pow" and l[1] == r: return simp(("pow", r, l[2] + 1))
        if r[0] == "pow" and r[1] == l: return simp(("pow", l, r[2] + 1))
    elif k == "neg":
        x = e[1]
        if isnum(x): return num(-x[1])
        if x[0] == "neg": return x[1]
        if x[0] == "sub": return simp(("sub", x[2], x[1]))
    elif k == "pow":
        b, n = e[1], e[2]
        if n == 0: return ONE
        if n == 1: return b
        if isnum(b): return num(b[1] ** n)
        if b[0] == "pow": return simp(("pow", b[1], b[2] * n))
        if b[0] == "neg":
            if n % 2 == 0: return simp(("pow", b[1], n))
            return simp(("neg", ("pow", b[1], n)))
        assert n <= 1000
    return e

def show(e):
    k = e[0]
    if k == "num": return str(e[1])
    if k == "var": return e[1]
    if k == "neg": return f"(neg {show(e[1])})"
    if k == "pow": return f"(^ {show(e[1])} {e[2]})"
    return f"({ {'add': '+', 'sub': '-', 'mul': '*'}[k] } {show(e[1])} {show(e[2])})"

def run_line(line):
    try:
        return show(simp(parse_line(line)))
    except Syn:
        return "error: syntax"

def solve(s):
    return "".join(run_line(l) + "\n" for l in s.split("\n") if l.strip(" \t"))

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}

rnd = random.Random(47)
def rgen(d, vs=("x", "y", "z")):
    if d <= 0 or rnd.random() < .2:
        return rnd.choice([str(rnd.choice([0, 0, 1, 1, -1, 2, 3, -2, 5, 10])), rnd.choice(vs), rnd.choice(vs)])
    r = rnd.random()
    if r < .22: return f"(+ {rgen(d-1)} {rgen(d-1)})"
    if r < .38: return f"(- {rgen(d-1)} {rgen(d-1)})"
    if r < .6: return f"(* {rgen(d-1)} {rgen(d-1)})"
    if r < .72: return f"(neg {rgen(d-1)})"
    if r < .8: return f"(^ {rgen(d-1)} {rnd.choice([0, 1, 2, 2, 3, 4])})"
    # duplicated child to provoke l == r
    a = rgen(d - 1)
    return f"({rnd.choice(['+', '-', '*'])} {a} {a})"

def messy(s):
    out = []
    for ch in s:
        if ch in "()" and rnd.random() < .3: out.append(rnd.choice([" ", "\t", "  "]) + ch)
        elif ch == " " and rnd.random() < .3: out.append(rnd.choice(["  ", "\t", " \t "]))
        else: out.append(ch)
    return "".join(out)

def rand_lines(n, d, msy=0.0, bad=0.0):
    L = []
    for _ in range(n):
        for _try in range(50):
            s = rgen(rnd.randint(1, d))
            try:
                simp(parse_line(s)); break
            except (AssertionError, OverflowError):
                continue
        if rnd.random() < msy: s = messy(s)
        if rnd.random() < bad:
            i = rnd.randrange(len(s)); s = s[:i] + rnd.choice(["", "(", ")", " 1.5 ", " q! "]) + s[i + 1:]
        L.append(s)
    return "\n".join(L) + "\n"

def deep(n, kind):
    s = "x"
    for i in range(n):
        s = f"({kind} {s} {'y' if i % 2 else '1'})"
    return s

examples = [case("basic", "(+ x 0)\n(* (+ 1 2) y)\n(- z z)\n(* x x)\n(neg (neg a))\n")]
hidden = examples + [
    case("atoms", "x\n42\n-7\n007\n-0\nfoo_bar2\n  y  \n"),
    case("add-rules", "(+ 2 3)\n(+ 0 x)\n(+ x 0)\n(+ x x)\n(+ x (neg y))\n(+ (neg y) x)\n(+ (neg x) (neg x))\n(+ (neg x) (neg y))\n(+ 0 0)\n(+ (+ x 0) (+ 0 x))\n"),
    case("sub-rules", "(- 7 10)\n(- x 0)\n(- 0 x)\n(- x x)\n(- x (neg y))\n(- (neg x) y)\n(- 0 (- a b))\n(- (* a 1) (+ a 0))\n(- 0 0)\n(- 0 (neg x))\n"),
    case("mul-rules", "(* 3 4)\n(* 0 x)\n(* x 0)\n(* 1 x)\n(* x 1)\n(* -1 x)\n(* x -1)\n(* x x)\n(* x 5)\n(* 5 x)\n(* 2 3 )\n(* (neg x) (neg y))\n(* (neg x) y)\n(* x (neg y))\n(* (neg x) 3)\n(* 3 (neg x))\n"),
    case("neg-rules", "(neg 5)\n(neg -5)\n(neg (neg x))\n(neg (- a b))\n(neg (neg (neg x)))\n(neg (+ a b))\n(neg 0)\n(neg (* 2 x))\n"),
    case("pow-rules", "(^ x 0)\n(^ x 1)\n(^ 2 10)\n(^ -2 3)\n(^ 0 5)\n(^ 1 1000)\n(^ (^ x 2) 3)\n(^ (neg x) 2)\n(^ (neg x) 3)\n(^ (neg x) 1)\n(^ (neg x) 0)\n(^ x 007)\n(^ (^ x 3) 0)\n(^ (- a a) 2)\n"),
    case("power-merge", "(* (^ x 2) (^ x 3))\n(* (^ x 2) x)\n(* x (^ x 2))\n(* (^ x 2) (^ y 3))\n(* (* x x) x)\n(* (* x x) (* x x))\n(* (^ x 2) (^ x 2))\n(* x (* x x))\n(* (* x x) (^ x 2))\n"),
    case("cascades", "(+ (* x 1) (* 1 x))\n(- (+ x 0) (* x 1))\n(* (+ x 0) (- y y))\n(+ (- a a) (* 0 q))\n(* (+ 1 1) (+ x x))\n(neg (- 0 (neg x)))\n(* (neg (- x y)) (- y x))\n(- (* (neg x) (neg x)) (^ x 2))\n(+ (* 2 x) (* x 2))\n(* (+ x x) (+ x x))\n"),
    case("whitespace", "  ( +   x\t0 )\n(*\tx\t\ty)\n(+(* 1 x)(* y 1))\n(neg(neg x))\n( ^ x   2  )\n\t(  -  a   b  )  \n"),
    case("syntax-errors", "\n".join(["(", ")", "()", "(+ x)", "(+ x y z)", "(neg)", "(neg x y)", "(* x)", "(^ x)", "(^ x y)", "(^ x -1)", "(^ x 1.5)", "(^ x (+ 1 1))", "(^ x 2 3)", "(foo x y)", "(x + y)", "+ x y", "(+ x y) z", "x y", "(+ x y", "(+ x y))", "1.5", "-", "+5", "X", "x-1", "(+ 1x 2)", "(- - 1)", "(neg neg)", "(+ (neg) 1)", "(+ , 1)", "((+ x y) 1)", "(+ x (^ y))", "007x", "(+ x $)"]) + "\n"),
    case("blank-lines", "\n  \n(+ x 0)\n\t\n\nx\n"),
    case("deep-add", deep(150, "+") + "\n" + deep(150, "-") + "\n" + deep(120, "*") + "\n"),
    case("random-small", rand_lines(80, 3)),
    case("random-large", rand_lines(350, 6, msy=.3, bad=.05)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
