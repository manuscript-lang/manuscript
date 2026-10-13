import json, random, re, pathlib, itertools

def solve_line(line):
    if " " not in line: return "error"
    cmd, rest = line.split(" ", 1)
    if cmd == "E":
        if not re.fullmatch(r"[A-Za-z]+", rest): return "error"
        return "".join(f"{len(list(g))}{k}" for k, g in itertools.groupby(rest))
    if cmd == "D":
        if not re.fullmatch(r"([1-9][0-9]*[A-Za-z])+", rest): return "error"
        return "".join(ch * int(n) for n, ch in re.findall(r"([1-9][0-9]*)([A-Za-z])", rest))
    return "error"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(6)
def runs(n):
    return "".join(rnd.choice("abcXYZ") * rnd.randint(1, 12) for _ in range(n))
big_lines = []
for _ in range(150):
    t = runs(rnd.randint(1, 40))
    big_lines.append("E " + t)
    big_lines.append("D " + solve_line("E " + t))
examples = [
    case("basic", "E aaabccdddd\nD 3a1b2c\nE ab1\nD 0a\nX hello\nD 2a3a\n"),
    case("round-trip", "E zzzzzzzzzzzzy\nD 12z1y\n"),
]
hidden = examples + [
    case("single", "E a\nD 1a\n"),
    case("case-sensitive", "E aAaA\nE aaAA\nD 2a2A\n"),
    case("long-run", "E " + "q" * 5000 + "\nD 99999x\n"),
    case("multi-digit", "D 10a11b100c\nD 12345Z\n"),
    case("leading-zero", "D 01a\nD 00a\nD 10a05b\n"),
    case("bad-decode", "D a\nD 3\nD 3a2\nD \nD 3a b\nD 3 a\nD -1a\nD 1a!\n"),
    case("bad-encode", "E ab c\nE a-b\nE 12\nE a1\nE héllo\n"),
    case("bad-command", "e aaa\nd 3a\nEE aaa\nE\nD\nencode aaa\n"),
    case("blank-lines", "\n  \nE aab\n\n   \nD 2a\n"),
    case("same-letter-pairs", "D 2a3a1a\nD 1a1a1a\n"),
    case("big", "\n".join(big_lines) + "\n"),
    case("no-trailing-newline", "E aabb\nD 2a"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
