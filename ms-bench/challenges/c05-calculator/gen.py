import json, random, pathlib, re, sys
sys.setrecursionlimit(20000)

class Syn(Exception): pass
class Div(Exception): pass

def evaluate(line):
    toks = []
    for m in re.finditer(r"\s*(?:(\d+)|(\S))", line):
        if m.group(1): toks.append(("n", int(m.group(1))))
        elif m.group(2): toks.append(("o", m.group(2)))
    pos = [0]
    def peek(): return toks[pos[0]] if pos[0] < len(toks) else None
    def nxt(): t = peek(); pos[0] += 1; return t
    div = [False]
    def expr():
        v = term()
        while peek() in (("o", "+"), ("o", "-")):
            op = nxt()[1]; r = term(); v = v + r if op == "+" else v - r
        return v
    def term():
        v = unary()
        while peek() == ("o", "*") or peek() == ("o", "/"):
            op = nxt()[1]; r = unary()
            if op == "*": v = v * r
            elif r == 0: div[0] = True; v = 0
            else: q = abs(v) // abs(r); v = q if (v < 0) == (r < 0) else -q
        return v
    def unary():
        if peek() == ("o", "-"): nxt(); return -unary()
        return atom()
    def atom():
        t = nxt()
        if t is None: raise Syn()
        if t[0] == "n": return t[1]
        if t == ("o", "("):
            v = expr()
            if nxt() != ("o", ")"): raise Syn()
            return v
        raise Syn()
    try:
        v = expr()
        if peek() is not None: raise Syn()
    except Syn:
        return "error: syntax"
    return "error: division by zero" if div[0] else str(v)

def solve(s):
    return "".join(evaluate(l) + "\n" for l in s.split("\n") if l.strip())

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(5)
def rexpr(d):
    if d == 0 or rnd.random() < .25: return str(rnd.randint(0, 99))
    r = rnd.random()
    if r < .15: return "-" + rexpr(d - 1)
    if r < .3: return "(" + rexpr(d - 1) + ")"
    return rexpr(d - 1) + rnd.choice([" + ", "-", " * ", "/", " - "]) + rexpr(d - 1)
examples = [case("basic", "1 + 2 * 3\n(1+2)*3\n10 / (5 - 5)\n2 +\n-7 / 2\n")]
good = [l for l in (rexpr(5) for _ in range(400))]
hidden = examples + [
    case("precedence", "2+3*4\n2*3+4\n10-2-3\n100/10/5\n2*(3+4)*5\n"), case("unary", "-2*3\n--4\n-(3+4)\n3--2\n- 5\n"),
    case("truncation", "-7/2\n7/-2\n-7/-2\n7/2\n0/5\n-1/2\n"), case("spaces", "  1\t+  2  \n\t(  3 )\n"),
    case("blank", "\n   \n1\n\n"), case("div-zero", "1/0\n0/0\n(1+2)/(3-3)\n1/0+2\n5*(2/0)\n"),
    case("syntax", "\n".join(["()", "1+", "+1", "(1", "1)", "1 2", "a", "1+*2", "2**3", "(", ")", "1 + (2", "3 $ 4", "1/0 +"])  + "\n"),
    case("syntax-beats-div", "1/0 +\n(1/0\n1/0 2\n"), case("random-valid", "\n".join(good) + "\n"),
    case("deep-parens", "(" * 200 + "7" + ")" * 200 + "\n"), case("big-numbers", "9999999999 * 99999999\n9223372036854775807\n-9223372036854775807 - 1\n"),
    case("no-trailing-newline", "1+1"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
