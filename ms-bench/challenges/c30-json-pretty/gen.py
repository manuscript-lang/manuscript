import json, random, pathlib

WS = " \t\n\r"

class Bad(Exception): pass

def pretty(s):
    pos = 0
    def ws():
        nonlocal pos
        while pos < len(s) and s[pos] in WS: pos += 1
    def lit(w):
        nonlocal pos
        if s[pos:pos + len(w)] != w: raise Bad
        pos += len(w); return w
    def string():
        nonlocal pos
        start = pos
        if pos >= len(s) or s[pos] != '"': raise Bad
        pos += 1
        while True:
            if pos >= len(s): raise Bad
            c = s[pos]
            if c == '"': pos += 1; return s[start:pos]
            if ord(c) < 0x20: raise Bad
            if c == "\\":
                pos += 1
                if pos >= len(s): raise Bad
                e = s[pos]
                if e in '"\\/bfnrt': pos += 1
                elif e == "u":
                    h = s[pos + 1:pos + 5]
                    if len(h) != 4 or any(x not in "0123456789abcdefABCDEF" for x in h): raise Bad
                    pos += 5
                else: raise Bad
            else: pos += 1
    def digits():
        nonlocal pos
        a = pos
        while pos < len(s) and "0" <= s[pos] <= "9": pos += 1
        if pos == a: raise Bad
    def number():
        nonlocal pos
        start = pos
        if pos < len(s) and s[pos] == "-": pos += 1
        if pos < len(s) and s[pos] == "0": pos += 1
        elif pos < len(s) and "1" <= s[pos] <= "9": digits()
        else: raise Bad
        if pos < len(s) and s[pos] == ".":
            pos += 1; digits()
        if pos < len(s) and s[pos] in "eE":
            pos += 1
            if pos < len(s) and s[pos] in "+-": pos += 1
            digits()
        return s[start:pos]
    def value(ind):
        nonlocal pos
        if pos >= len(s): raise Bad
        c = s[pos]
        if c == "{":
            pos += 1; ws()
            if pos < len(s) and s[pos] == "}": pos += 1; return "{}"
            items = []
            while True:
                ws(); k = string(); ws()
                if pos >= len(s) or s[pos] != ":": raise Bad
                pos += 1; ws()
                items.append("  " * (ind + 1) + k + ": " + value(ind + 1)); ws()
                if pos < len(s) and s[pos] == ",": pos += 1; continue
                if pos < len(s) and s[pos] == "}": pos += 1; break
                raise Bad
            return "{\n" + ",\n".join(items) + "\n" + "  " * ind + "}"
        if c == "[":
            pos += 1; ws()
            if pos < len(s) and s[pos] == "]": pos += 1; return "[]"
            items = []
            while True:
                ws(); items.append("  " * (ind + 1) + value(ind + 1)); ws()
                if pos < len(s) and s[pos] == ",": pos += 1; continue
                if pos < len(s) and s[pos] == "]": pos += 1; break
                raise Bad
            return "[\n" + ",\n".join(items) + "\n" + "  " * ind + "]"
        if c == '"': return string()
        if c == "t": return lit("true")
        if c == "f": return lit("false")
        if c == "n": return lit("null")
        return number()
    ws()
    v = value(0)
    ws()
    if pos != len(s): raise Bad
    return v

def solve(s):
    try:
        out = pretty(s) + "\n"
    except Bad:
        out = "invalid\n"
    # Cross-check against the standard library for inputs it treats the same way.
    try:
        json.loads(s, parse_constant=lambda c: (_ for _ in ()).throw(ValueError()))
        ok = True
    except (ValueError, RecursionError):
        ok = False
    assert ok == (out != "invalid\n"), (s[:80], out[:40])
    return out

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(30)
def rstr():
    pieces = ["a", "b c", "key", "", "x\\ty", "q\\\"uote", "back\\\\slash", "\\u00e9", "\\/", "[{]}", ",:", "  "]
    return '"' + "".join(rnd.choice(pieces) for _ in range(rnd.randint(0, 3))) + '"'
def rnum():
    return rnd.choice(["0", "-0", "7", "-12", "3.14", "-0.5", "1e5", "2E-3", "1.5e+10", "100", "0.0", "123456789012345678901234567890"])
def rval(depth, maxd, sp):
    r = rnd.random()
    if depth >= maxd or r < .35:
        return rnd.choice([rstr, rnum, lambda: "true", lambda: "false", lambda: "null"])()
    j = lambda: rnd.choice(["", "", " ", "\n", "\t "]) if sp else ""
    if r < .65:
        n = rnd.randint(0, 4)
        return "[" + j() + (j() + "," + j()).join(rval(depth + 1, maxd, sp) for _ in range(n)) + j() + "]"
    n = rnd.randint(0, 4)
    return "{" + j() + (j() + "," + j()).join(rstr() + j() + ":" + j() + rval(depth + 1, maxd, sp) for _ in range(n)) + j() + "}"
def mutate(s):
    if not s: return s
    i = rnd.randrange(len(s))
    k = rnd.randrange(4)
    if k == 0: return s[:i] + s[i + 1:]
    if k == 1: return s[:i] + rnd.choice('{}[],:"\\ x1-.e') + s[i:]
    if k == 2: return s[:i] + rnd.choice('{}[],:"\\ x1-.e') + s[i + 1:]
    return s[:i]
big = rval(0, 7, True)
while len(big) < 6000: big = "[" + big + "," + rval(0, 6, True) + "]"
deep = "[" * 150 + "1" + "]" * 150
mutants = []
for _ in range(60):
    base = rval(0, 4, True)
    mutants.append(mutate(base))
examples = [
    case("basic", '{"a":[1,2,{"b":null}],"c":"x\\ty", "d":{}, "e":[]}\n'),
    case("invalid", '{"a": 1,}\n'),
]
bad_docs = [
    "{", "[", "]", "}", '{"a"}', '{"a":}', '{"a":1 "b":2}', "[1 2]", "[1,]", "[,1]", "{,}", '{a:1}', "{'a':1}",
    '"unterminated', '"bad \\x escape"', '"bad \\u12G4"', '"short \\u12"', '"tab\there"', '"line\nbreak"', "'single'",
    "01", "1.", ".5", "+1", "-", "--1", "1e", "1e+", "1.e5", "0x10", "NaN", "Infinity", "-Infinity", "tru", "True", "nul", "nullx",
    "[1] 2", "{} {}", "[1]]", '{"a":1}}', "1 2", "\x0b[]", '{"a":[1,2}', '[{"a":1]', "", " ", "[" * 3 + "]" * 2,
]
hidden = examples + [
    case("scalar-number", " -12.5e+3 \n"),
    case("string-escapes-kept", '{"k":["\\n\\r\\t\\b\\f\\\\\\"\\/\\u0041\\uBEEF\\ubeef"],"k":"dup"}'),
    case("empty-and-nested", '[{},[],{"a":{}},[[]],[[1,2],[3,[4,[5]]],{"k":[{"x":1},{"y":[]}]}]]'),
    case("whitespace-variants", '\r\n{ "a" :\t[ 1 ,\n2 ] ,\r\n"b" : { } }\r\n'),
    case("number-forms", "[0,-0,0.5,10,1e2,1E+2,1e-2,0e0,-1.25E10,true,false,null]"),
    case("deep", "[" * 150 + '{"x":1}' + "]" * 150),
    case("bad-leading-zero", "[01]"),
    case("bad-escape", '["fine","a\\x"]'),
    case("bad-control-char", '{"a":"x\ty"}'),
    case("trailing-garbage", '{"a":1} x'),
    case("random-large", big),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
import sys
if "--stress" in sys.argv:
    # Extra local-only battery (not part of the benchmark): every invalid input above plus random mutants.
    extra = [case(f"bad-{i}", b) for i, b in enumerate(bad_docs)] + [case(f"mutant-{i}", m) for i, m in enumerate(mutants)]
    extra += [case(f"valid-{i}", rval(0, 5, True)) for i in range(40)]
    pathlib.Path(sys.argv[sys.argv.index("--stress") + 1]).write_text(json.dumps(extra))
