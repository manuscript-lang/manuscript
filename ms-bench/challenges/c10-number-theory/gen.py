import json, math, random, re, pathlib

NUM = re.compile(r"[0-9]{1,18}")
DIG = "0123456789abcdefghijklmnopqrstuvwxyz"

def factor(n):
    parts, p = [], 2
    while p * p <= n:
        if n % p == 0:
            e = 0
            while n % p == 0: n //= p; e += 1
            parts.append(f"{p}^{e}" if e > 1 else str(p))
        p += 1
    if n > 1: parts.append(str(n))
    return " * ".join(parts)

def isprime(n):
    if n < 2: return "neither"
    p = 2
    while p * p <= n:
        if n % p == 0: return "composite"
        p += 1
    return "prime"

def tobase(n, b):
    if n == 0: return "0"
    s = ""
    while n: s = DIG[n % b] + s; n //= b
    return s

def solve_line(line):
    t = line.split(" ")
    cmd = t[0]
    arity = {"gcd": 3, "lcm": 3, "isprime": 2, "factor": 2, "base": 4}
    if cmd not in arity: return "error: unknown command"
    if len(t) != arity[cmd]: return "error: bad arguments"
    if cmd == "base":
        v, fr, to = t[1], t[2], t[3]
        for b in (fr, to):
            if not NUM.fullmatch(b) or not 2 <= int(b) <= 36: return "error: bad base"
        fr, to = int(fr), int(to)
        if v == "" or any(c.lower() not in DIG[:fr] for c in v) or not re.fullmatch(r"[0-9A-Za-z]+", v):
            return "error: bad digit"
        return tobase(int(v.lower(), fr), to)
    if not all(NUM.fullmatch(x) for x in t[1:]): return "error: bad arguments"
    nums = [int(x) for x in t[1:]]
    if cmd in ("gcd", "lcm") and any(n > 10**9 for n in nums): return "error: out of range"
    if cmd in ("isprime", "factor") and nums[0] > 10**10: return "error: out of range"
    if cmd == "gcd": return str(math.gcd(*nums))
    if cmd == "lcm": return str(math.lcm(*nums))
    if cmd == "isprime": return isprime(nums[0])
    if nums[0] < 2: return "error: n must be at least 2"
    return factor(nums[0])

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(10)
mix = []
for _ in range(150):
    c = rnd.choice(["gcd", "lcm", "isprime", "factor", "base"])
    if c in ("gcd", "lcm"): mix.append(f"{c} {rnd.randint(0, 10**6)} {rnd.randint(0, 10**6)}")
    elif c == "base":
        fr, to = rnd.randint(2, 36), rnd.randint(2, 36)
        mix.append(f"base {tobase(rnd.randint(0, 10**15), fr)} {fr} {to}")
    else: mix.append(f"{c} {rnd.randint(0, 10**rnd.randint(1, 10))}")
examples = [
    case("basic", "gcd 12 18\nlcm 4 6\nisprime 97\nfactor 360\nbase ff 16 2\nbase 12 2 10\nfactor 1\npow 2 3\ngcd 4\n"),
    case("primes", "isprime 0\nisprime 1\nisprime 2\nisprime 91\n"),
]
hidden = examples + [
    case("gcd-lcm-zero", "gcd 0 0\ngcd 0 7\ngcd 7 0\nlcm 0 5\nlcm 5 0\nlcm 0 0\nlcm 1 1\ngcd 1000000000 999999999\nlcm 1000000000 999999999\nlcm 999999937 999999929\n"),
    case("leading-zeros", "gcd 0012 0018\nfactor 0360\nisprime 007\ngcd 000000000000000000 5\n"),
    case("factor-edge", "factor 2\nfactor 3\nfactor 4\nfactor 9973\nfactor 10000000000\nfactor 9999999967\nfactor 9999999999\nfactor 0\n"),
    case("isprime-big", "isprime 9999999967\nisprime 9999999969\nisprime 10000000000\nisprime 3215031751\nisprime 4294967297\n"),
    case("base-digits", "base 0 2 36\nbase 000 10 2\nbase zz 36 10\nbase ZZ 36 10\nbase Ff 16 10\nbase 777 8 16\nbase 1010 2 2\nbase 999999999999999999 10 36\nbase 255 10 16\n"),
    case("base-errors", "base 2 2 10\nbase g 16 10\nbase  10 2\nbase 10 1 2\nbase 10 2 37\nbase 10 x 2\nbase 10 2 +2\nbase 10 10\nbase 10 2 3 4\nbase - 10 2\nbase 1_0 10 2\n"),
    case("argument-errors", "gcd 1 2 3\ngcd 1\ngcd\ngcd  4 6\ngcd -1 2\ngcd +1 2\ngcd 1.5 2\ngcd a 2\ngcd 1234567890123456789 2\nisprime\nfactor 1 2\nisprime \n"),
    case("range-errors", "gcd 1000000001 2\nlcm 2 1000000001\nisprime 10000000001\nfactor 10000000001\nfactor 123456789012345678\nfactor abc\n"),
    case("unknown", "GCD 1 2\nprime 7\n gcd 1 2\ngcd 1 2\nbase16 ff\n"),
    case("blank-lines", "\n  \ngcd 6 4\n\n   \nfactor 12\n"),
    case("mixed-big", "\n".join(mix) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
