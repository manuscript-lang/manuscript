import json, random, re, pathlib

SYM = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
       (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
VAL = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}

def to_roman(n):
    out = ""
    for v, s in SYM:
        while n >= v: out += s; n -= v
    return out

def from_roman(s):
    total = 0
    for i, c in enumerate(s):
        v = VAL[c]
        total += -v if i + 1 < len(s) and VAL[s[i + 1]] > v else v
    return total

def solve_line(line):
    if re.fullmatch(r"[0-9]+", line):
        if line[0] == "0": return "invalid"
        n = int(line)
        return to_roman(n) if 1 <= n <= 3999 else "invalid"
    if not re.fullmatch(r"[IVXLCDM]+", line): return "invalid"
    n = from_roman(line)
    return str(n) if 1 <= n <= 3999 and to_roman(n) == line else "invalid"

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(7)
allnums = "\n".join(str(n) for n in range(1, 4000))
allrom = "\n".join(to_roman(n) for n in range(1, 4000))
examples = [
    case("basic", "1994\nMCMXCIV\nIIII\n0\n4000\nxiv\n3999\n"),
    case("small", "4\nIV\n9\nXLII\n"),
]
junk = ["IIII", "VV", "IC", "VX", "IL", "XM", "MMMM", "IIX", "XXXX", "CCCC", "DD", "LL", "IVI", "IXI", "MCMC", "CMC", "XCX", "VIV", "IIV", "MMMMCMXCIX", "mcm", "MCMXCIV ", " MCMXCIV", "M C", "A", "I I", "0IV"]
hidden = examples + [
    case("every-number", allnums + "\n"),
    case("every-numeral", allrom + "\n"),
    case("non-canonical", "\n".join(junk) + "\n"),
    case("range-edges", "0\n1\n3999\n4000\n10000\n999999999\n"),
    case("leading-zeros", "01\n007\n00\n0004\n03999\n"),
    case("spaces-and-junk", "12 \n 12\n1 2\n-5\n+5\n3.5\nXII.\n"),
    case("blank-lines", "\n  \n7\n\n VII\nVII\n"),
    case("subtractives", "XL\nXC\nCD\nCM\nXLIX\nCDXCIX\nMCDXLIV\nMMCDXXI\n"),
    case("random", "\n".join(rnd.choice([str(rnd.randint(1, 3999)), to_roman(rnd.randint(1, 3999)), "".join(rnd.choice("IVXLCDM") for _ in range(rnd.randint(1, 6)))]) for _ in range(400)) + "\n"),
    case("no-trailing-newline", "XIV\n14"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
