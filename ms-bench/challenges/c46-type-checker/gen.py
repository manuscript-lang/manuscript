import sys
sys.setrecursionlimit(50000)
import json, random, pathlib

KEYWORDS = {"let", "in", "if", "then", "else", "true", "false", "and", "or", "not"}
BUILTINS = {
    "len": (["Str"], "Int"), "str": (["Int"], "Str"), "abs": (["Int"], "Int"),
    "min": (["Int", "Int"], "Int"), "max": (["Int", "Int"], "Int"),
    "concat": (["Str", "Str"], "Str"), "even": (["Int"], "Bool"),
}
CMP = ("<", "<=", ">", ">=", "==", "!=")

class Err(Exception):
    def __init__(self, msg, col): self.msg, self.col = msg, col

def is_digit(c): return "0" <= c <= "9"
def is_start(c): return "a" <= c <= "z" or "A" <= c <= "Z" or c == "_"
def is_ident(c): return is_start(c) or is_digit(c)

def lex(line):
    toks, i, n = [], 0, len(line)
    while i < n:
        c, col = line[i], i + 1
        if c in " \t": i += 1; continue
        if is_digit(c):
            j = i
            while j < n and is_digit(line[j]): j += 1
            toks.append(("int", line[i:j], col)); i = j
        elif is_start(c):
            j = i
            while j < n and is_ident(line[j]): j += 1
            w = line[i:j]
            toks.append((w if w in KEYWORDS else "id", w, col)); i = j
        elif c == '"':
            j = line.find('"', i + 1)
            if j < 0: raise Err("unterminated string", col)
            toks.append(("str", line[i:j + 1], col)); i = j + 1
        elif line[i:i + 2] in ("<=", ">=", "==", "!="):
            toks.append((line[i:i + 2], line[i:i + 2], col)); i += 2
        elif c in "+-*<>(),=":
            toks.append((c, c, col)); i += 1
        else:
            raise Err(f"unexpected character '{c}'", col)
    return toks

def parse(toks, eof):
    pos = [0]
    def peek(): return toks[pos[0]][0] if pos[0] < len(toks) else None
    def col(): return toks[pos[0]][2] if pos[0] < len(toks) else eof
    def nxt(): t = toks[pos[0]]; pos[0] += 1; return t
    def expect(k):
        if peek() != k: raise Err("syntax error", col())
        return nxt()
    def expr():
        k = peek()
        if k == "let":
            t = nxt(); name = expect("id"); expect("="); e1 = expr(); expect("in"); e2 = expr()
            return ("let", t[2], name[1], e1, e2)
        if k == "if":
            t = nxt(); c = expr(); expect("then"); a = expr(); expect("else"); b = expr()
            return ("if", t[2], c, a, b)
        return orx()
    def orx():
        l = andx()
        while peek() == "or":
            nxt(); r = andx(); l = ("bin", l[1], "or", l, r)
        return l
    def andx():
        l = notx()
        while peek() == "and":
            nxt(); r = notx(); l = ("bin", l[1], "and", l, r)
        return l
    def notx():
        if peek() == "not":
            t = nxt(); return ("not", t[2], notx())
        return cmp()
    def cmp():
        l = add()
        if peek() in CMP:
            op = nxt()[0]; r = add(); l = ("bin", l[1], op, l, r)
        return l
    def add():
        l = mul()
        while peek() in ("+", "-"):
            op = nxt()[0]; r = mul(); l = ("bin", l[1], op, l, r)
        return l
    def mul():
        l = unary()
        while peek() == "*":
            nxt(); r = unary(); l = ("bin", l[1], "*", l, r)
        return l
    def unary():
        if peek() == "-":
            t = nxt(); return ("neg", t[2], unary())
        return atom()
    def atom():
        k = peek()
        if k == "int": return ("int", nxt()[2])
        if k == "str": return ("str", nxt()[2])
        if k in ("true", "false"): return ("bool", nxt()[2])
        if k == "id":
            t = nxt()
            if peek() == "(":
                nxt(); args = []
                if peek() != ")":
                    args.append(expr())
                    while peek() == ",":
                        nxt(); args.append(expr())
                expect(")")
                return ("call", t[2], t[1], args)
            return ("var", t[2], t[1])
        if k == "(":
            t = nxt(); e = expr(); expect(")")
            return (e[0], t[2]) + e[2:]
        raise Err("syntax error", col())
    e = expr()
    if pos[0] < len(toks): raise Err("syntax error", col())
    return e

def need(t, want, col):
    if t != want: raise Err(f"expected {want}, found {t}", col)

def check(e, env):
    k = e[0]
    if k == "int": return "Int"
    if k == "bool": return "Bool"
    if k == "str": return "Str"
    if k == "var":
        if e[2] not in env: raise Err(f"unbound variable {e[2]}", e[1])
        return env[e[2]]
    if k == "neg":
        need(check(e[2], env), "Int", e[2][1]); return "Int"
    if k == "not":
        need(check(e[2], env), "Bool", e[2][1]); return "Bool"
    if k == "bin":
        op, l, r = e[2], e[3], e[4]
        lt = check(l, env); rt = check(r, env)
        if op == "+":
            if lt not in ("Int", "Str"): raise Err(f"expected Int or Str, found {lt}", l[1])
            need(rt, lt, r[1]); return lt
        if op in ("-", "*"):
            need(lt, "Int", l[1]); need(rt, "Int", r[1]); return "Int"
        if op in ("<", "<=", ">", ">="):
            need(lt, "Int", l[1]); need(rt, "Int", r[1]); return "Bool"
        if op in ("==", "!="):
            need(rt, lt, r[1]); return "Bool"
        need(lt, "Bool", l[1]); need(rt, "Bool", r[1]); return "Bool"
    if k == "call":
        name, args = e[2], e[3]
        if name not in BUILTINS: raise Err(f"unknown function {name}", e[1])
        params, ret = BUILTINS[name]
        if len(args) != len(params):
            raise Err(f"wrong number of arguments for {name}: expected {len(params)}, found {len(args)}", e[1])
        for a, p in zip(args, params): need(check(a, env), p, a[1])
        return ret
    if k == "let":
        t1 = check(e[3], env)
        env2 = dict(env); env2[e[2]] = t1
        return check(e[4], env2)
    if k == "if":
        need(check(e[2], env), "Bool", e[2][1])
        tt = check(e[3], env); et = check(e[4], env)
        need(et, tt, e[4][1]); return tt

def run_line(line):
    try:
        toks = lex(line)
        e = parse(toks, len(line.rstrip(" \t")) + 1)
        return check(e, {})
    except Err as x:
        return f"error: {x.msg} at {x.col}"

def solve(s):
    return "".join(run_line(l) + "\n" for l in s.split("\n") if l.strip(" \t"))

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}

rnd = random.Random(46)
NAMES = ["x", "y", "n", "s", "flag", "total"]
def gen(t, d, env):
    vs = [k for k, v in env.items() if v == t]
    if d <= 0 or rnd.random() < 0.2:
        if vs and rnd.random() < 0.6: return rnd.choice(vs)
        if t == "Int": return str(rnd.randint(0, 99))
        if t == "Bool": return rnd.choice(["true", "false"])
        return '"' + rnd.choice(["a", "hi", "", "x y", "abc"]) + '"'
    r = rnd.random()
    if t == "Int":
        if r < .25: return f"({gen('Int', d - 1, env)} {rnd.choice(['+', '-', '*'])} {gen('Int', d - 1, env)})"
        if r < .35: return f"-{gen('Int', d - 1, env)}"
        if r < .5: return f"len({gen('Str', d - 1, env)})"
        if r < .6: return f"{rnd.choice(['min', 'max'])}({gen('Int', d - 1, env)}, {gen('Int', d - 1, env)})"
        if r < .7: return f"abs({gen('Int', d - 1, env)})"
    if t == "Str":
        if r < .3: return f"({gen('Str', d - 1, env)} + {gen('Str', d - 1, env)})"
        if r < .5: return f"str({gen('Int', d - 1, env)})"
        if r < .6: return f"concat({gen('Str', d - 1, env)}, {gen('Str', d - 1, env)})"
    if t == "Bool":
        if r < .25: return f"({gen('Int', d - 1, env)} {rnd.choice(CMP)} {gen('Int', d - 1, env)})"
        if r < .35: return f"({gen('Bool', d - 1, env)} {rnd.choice(['and', 'or'])} {gen('Bool', d - 1, env)})"
        if r < .45: return f"(not {gen('Bool', d - 1, env)})"
        if r < .55: return f"even({gen('Int', d - 1, env)})"
        if r < .65:
            u = rnd.choice(["Int", "Str", "Bool"])
            return f"({gen(u, d - 1, env)} {rnd.choice(['==', '!='])} {gen(u, d - 1, env)})"
    if r < .8:
        nm = rnd.choice(NAMES); t1 = rnd.choice(["Int", "Str", "Bool"]); e2 = dict(env); e2[nm] = t1
        return f"(let {nm} = {gen(t1, d - 1, env)} in {gen(t, d - 1, e2)})"
    return f"(if {gen('Bool', d - 1, env)} then {gen(t, d - 1, env)} else {gen(t, d - 1, env)})"

def mutate(s):
    r = rnd.random(); i = rnd.randrange(len(s))
    if r < .5:
        try: ts = [t for t in lex(s) if t[0] in ("int", "str", "true", "false", "id")]
        except Err: ts = []
        if ts:
            t = rnd.choice(ts); a = t[2] - 1
            return s[:a] + rnd.choice(["7", '"q"', "true", "false", "zed"]) + s[a + len(t[1]):]
        r = .9
    if r < .3: return s[:i] + s[i + 1:]
    if r < .6: return s[:i] + rnd.choice(['+', '(', ')', '"', 'x', '1', ' true ', '&', 'not ', ' == ']) + s[i:]
    if r < .8: return s[:i] + rnd.choice(["true", "1", '"s"', "zz", "len"]) + s[i + 1:]
    return s.replace(rnd.choice(["+", "-", "*", "and", "<", "(", "if", "len"]), rnd.choice(["and", "+", "<", "or", "-", "max", "not"]), 1)

def rand_lines(n, mut):
    out = []
    for _ in range(n):
        t = rnd.choice(["Int", "Int", "Bool", "Str"])
        s = gen(t, rnd.randint(1, 5), {})
        if rnd.random() < mut: s = mutate(s)
        out.append(s)
    return "\n".join(out) + "\n"

examples = [case("basic", "1 + 2 * 3\nif 1 < 2 then \"a\" else \"b\"\nlet x = 5 in x + true\n1 +\n")]
big = rand_lines(500, 0.5)
hidden = examples + [
    case("literals", 'true\nfalse\n42\n007\n"hello"\n""\n"a b"\n'),
    case("arithmetic", "1 + 2\n1 - 2 * 3\n-4\n--4\n- -4 * 2\n(1)\n((((7))))\n\"a\" + \"b\"\n\"a\" + \"b\" + \"c\"\n"),
    case("operand-errors", "true + 1\n1 + true\n\"a\" + 1\n1 + \"a\"\n1 - \"x\"\n\"x\" * 2\ntrue < 1\n1 < \"a\"\n-true\n-\"s\"\nnot 1\n1 and true\ntrue or 0\n"),
    case("positions", "  (1 < 2) + 3\n(1 + 2) + true\n  -(true)\n  not (1)\n1 + (2 + (3 + true))\n\t\"s\" - 1\n1 + 2 * (3 - false) * 4\n"),
    case("equality", "1 == 1\n\"a\" != \"b\"\ntrue == false\n1 == true\n\"a\" == 1\ntrue != 0\n1 == 1 == 1\n(1 == 1) == true\n(1 < 2) == (3 < 4)\n"),
    case("let", "let x = 1 in x + 2\nlet x = 1 in let y = x + 1 in x * y\nlet x = \"a\" in let x = 5 in x + 1\nlet x = \"a\" in (let x = 5 in x) + x\nlet x = 1 in y\nz\nlet x = x in x\nlet x = 1 in x + true\nlet x = true in x - 1\n"),
    case("if", "if true then 1 else 2\nif 1 then 2 else 3\nif true then 1 else \"a\"\nif true then \"a\" else \"b\"\nif 1 < 2 then true else 5 == 5\nif 1 < 2 then 1 + true else \"z\"\nif true then 1 else 2 + \"a\"\nif if true then false else true then 1 else 2\n"),
    case("calls", "len(\"abc\")\nstr(12)\nabs(-3)\nmax(1, 2)\nmin(1,2)\nconcat(\"a\", \"b\")\neven(4)\nlen(1)\nmax(1)\nmax(1, 2, 3)\nmax(1, true)\nmax(true, 1)\nfoo(1)\nlen\nlet len = 3 in len + 1\nlet f = 3 in f(1)\nmax()\nstr(len(\"a\") + 1) + \"x\"\n"),
    case("lex-errors", "1 + $\n  @\n\"abc\n1 + \"abc\n a = 1\n1 ! 2\n1 & 2\n#\n'a'\n3 . 4\n"),
    case("syntax-errors", "1 +\n(1\n1)\n()\n1 2\n1 < 2 < 3\nlet x = 1\nlet 1 = 2 in 3\nlet if = 2 in 3\nif true then 1\nif true 1 else 2\n1 + if true then 1 else 2\nmax(1,)\nmax(,1)\nnot\n- \n1 + not true\n(let x = 1 in x) +\nlet x = 1 in\nthen\n"),
    case("syntax-before-type", "true + 1 +\n1 + true )\nlet x = true in x + 1 $\n\"a\" - 1 2\n"),
    case("blank-lines", "\n  \n\t\n1\n\n  true  \n"),
    case("deep", "(" * 120 + "1 + true" + ")" * 120 + "\n" + "-" * 150 + "5\n" + "(" * 100 + "1\n"),
    case("random-valid", rand_lines(120, 0.0)),
    case("random-large", big),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
