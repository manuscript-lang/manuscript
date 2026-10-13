import json, random, re, pathlib, sys
sys.set_int_max_str_digits(0)

def solve_line(line):
    t = line.split(" ")
    if len(t) != 3 or t[0] not in ("add", "sub", "mul"): return "error: bad command"
    if not all(re.fullmatch(r"[0-9]+", x) for x in t[1:]): return "error: bad number"
    a, b = int(t[1]), int(t[2])
    return str({"add": a + b, "sub": a - b, "mul": a * b}[t[0]])

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(11)
def digits(n, z=0):
    return "".join(rnd.choice("0123456789") for _ in range(n))
big = []
for _ in range(60):
    op = rnd.choice(["add", "sub", "mul"])
    n = rnd.randint(1, 200 if op == "mul" else 500)
    big.append(f"{op} {digits(n)} {digits(rnd.randint(1, n))}")
examples = [
    case("basic", "add 999999999999999999999 1\nsub 5 12\nmul 123456789123456789 987654321987654321\nadd 007 0000\nadd 12 x\ndiv 4 2\nsub 100\n"),
    case("carry", "add 99999999999999999999999999 1\nsub 100000000000000000000 1\n"),
]
hidden = examples + [
    case("zeros", "add 0 0\nsub 0 0\nmul 0 0\nmul 0 123456789012345678901234567890\nsub 5 5\nsub 000 0\nadd 000 000\n"),
    case("negative", "sub 1 1000000000000000000000000000000\nsub 999999999999999999999 1000000000000000000000\nsub 0 1\n"),
    case("leading-zeros", "add 0000000000000000000000000000001 0000000000000000000000000000009\nmul 0001 000000000000000000000000000000000000002\nsub 0010 0000009\n"),
    case("unequal-lengths", "add 1 " + "9" * 100 + "\nadd " + "9" * 100 + " 1\nsub " + "1" + "0" * 99 + " 1\nsub 1 " + "1" + "0" * 99 + "\n"),
    case("mul-powers", "mul 1" + "0" * 50 + " 1" + "0" * 50 + "\nmul " + "9" * 60 + " " + "9" * 60 + "\nmul 1 " + "7" * 100 + "\n"),
    case("bad-number", "add -1 2\nadd 1 +2\nadd 1.5 2\nadd 1 2a\nadd  5\nadd 5 \nmul 0x10 1\nsub 1e5 1\nadd ٤ 1\n"),
    case("bad-command", "add 1\nadd 1 2 3\nADD 1 2\nneg 1 2\n add 1 2\nadd  1 2\nadd\nx\n"),
    case("check-order", "div x y\nadd x\nadd x y\n"),
    case("blank-lines", "\n  \nadd 1 2\n\n  \nmul 3 4\n"),
    case("big", "\n".join(big) + "\n"),
    case("long-add", "add " + "9" * 500 + " " + "9" * 500 + "\nadd " + "1" * 500 + " " + "9" * 500 + "\n"),
    case("no-trailing-newline", "add 1 2\nadd 3 4"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
