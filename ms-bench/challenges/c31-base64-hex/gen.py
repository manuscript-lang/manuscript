import json, random, pathlib, base64, binascii

ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

def b64e(data):
    out = []
    for i in range(0, len(data), 3):
        ch = data[i:i + 3]
        n = int.from_bytes(ch + b"\0" * (3 - len(ch)), "big")
        quad = [ALPHA[(n >> s) & 63] for s in (18, 12, 6, 0)]
        if len(ch) == 1: quad[2] = quad[3] = "="
        elif len(ch) == 2: quad[3] = "="
        out.append("".join(quad))
    return "".join(out)

def b64d(t):
    if len(t) % 4: return None
    body = t.rstrip("=")
    pad = len(t) - len(body)
    if pad > 2 or any(c not in ALPHA for c in body): return None
    vals = [ALPHA.index(c) for c in body]
    out = bytearray()
    for i in range(0, len(vals), 4):
        g = vals[i:i + 4]
        if len(g) == 1: return None
        n = 0
        for v in g: n = n * 64 + v
        n <<= 6 * (4 - len(g))
        b = n.to_bytes(3, "big")
        keep = len(g) - 1 if len(g) < 4 else 3
        if any(b[keep:]): return None
        out += b[:keep]
    if pad and len(t) and (len(body) % 4) != 4 - pad: return None
    return bytes(out)

def hexd(t):
    if len(t) % 2 or any(c not in "0123456789abcdefABCDEF" for c in t): return None
    return bytes.fromhex(t)

def printable(b):
    return b is not None and all(32 <= x <= 126 for x in b)

def run(cmd, text):
    if cmd == "b64e": return b64e(text.encode())
    if cmd == "hexe": return text.encode().hex()
    if cmd in ("b64d", "hexd"):
        b = b64d(text) if cmd == "b64d" else hexd(text)
        return b.decode() if printable(b) else "error"
    return "error"

def solve(s):
    out = []
    for line in s.split("\n"):
        if not line.strip(" "): continue
        cmd, _, text = line.partition(" ")
        out.append(run(cmd, text))
    return "".join(o + "\n" for o in out)

# sanity: compare with the standard library on canonical inputs
for n in range(0, 40):
    d = bytes(range(32 + n % 90, 32 + n % 90 + n % 7))
    assert b64e(d) == base64.b64encode(d).decode()
    assert b64d(base64.b64encode(d).decode()) == d
def lib_b64d(t):
    try:
        d = base64.b64decode(t, validate=True)
    except (binascii.Error, ValueError):
        return None
    return d if base64.b64encode(d).decode() == t else None

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(31)
PRINT = "".join(chr(c) for c in range(32, 127))
def rtext(lo=0, hi=20): return "".join(rnd.choice(PRINT) for _ in range(rnd.randint(lo, hi)))
def rand_lines(n):
    ls = []
    for _ in range(n):
        t = rtext()
        k = rnd.randrange(8)
        if k == 0: ls.append("b64e " + t)
        elif k == 1: ls.append("hexe " + t)
        elif k == 2: ls.append("b64d " + base64.b64encode(t.encode()).decode())
        elif k == 3: ls.append("hexd " + t.encode().hex().upper())
        elif k == 4:
            e = list(base64.b64encode(t.encode()).decode() or "QUJD")
            e[rnd.randrange(len(e))] = rnd.choice(ALPHA + "=-_ ")
            ls.append("b64d " + "".join(e))
        elif k == 5:
            e = list(t.encode().hex() or "41")
            e[rnd.randrange(len(e))] = rnd.choice("0123456789abcdefg ")
            ls.append("hexd " + "".join(e)[: rnd.choice([100, 100, 3])])
        elif k == 6: ls.append("b64d " + "".join(rnd.choice(ALPHA + "=") for _ in range(rnd.choice([4, 8, 12]))))
        else: ls.append("hexd " + "".join(rnd.choice("0123456789abcdef") for _ in range(rnd.choice([2, 4, 6]))))
    return "\n".join(ls) + "\n"
examples = [
    case("basic", "b64e Hello, World!\nb64d SGVsbG8sIFdvcmxkIQ==\nhexe Hi there\nhexd 4869207468657265\nb64d SGVsbG8\nhexd 4g\nb64d QR==\nhexd 00\nb64e\nnope x\n"),
    case("padding-lengths", "b64e a\nb64e ab\nb64e abc\nb64e abcd\nhexe abc\n"),
]
hidden = examples + [
    case("empty-input", ""),
    case("empty-text", "b64e\nb64e \nb64d\nb64d \nhexe\nhexd\nhexd \n"),
    case("spaces-in-text", "b64e   leading and trailing  \nhexe a  b\nb64d IGEgYiA=\nhexd 20202020\n"),
    case("b64-canonical-bits", "b64d QQ==\nb64d QR==\nb64d QUI=\nb64d QUJ=\nb64d QUJD\nb64d QQ=\nb64d Q===\nb64d ====\n"),
    case("b64-bad-chars-and-padding", "b64d QQ==QQ==\nb64d =QQQ\nb64d QU=B\nb64d QUJD=\nb64d QUJ-\nb64d QU JD\nb64d QUJDQQ\nb64d QUJDQQ=\n"),
    case("hex-forms", "hexd 4a4B4c\nhexd 4A4b4C\nhexd 4a4\nhexd 4a4z\nhexd 0x41\nhexd 41 42\nhexd 7e\nhexd 7f\nhexd 1f\nhexd 20\n"),
    case("non-printable-result", "b64d AAAA\nb64d /w==\nb64d Cg==\nb64d IA==\nb64d fg==\nb64d fw==\n"),
    case("unknown-and-blank", "\nb64e x\n  \nB64E x\nencode x\nhexe\n b64e x\n"),
    case("all-printable-roundtrip", "b64e " + PRINT + "\nhexe " + PRINT + "\nb64d " + base64.b64encode(PRINT.encode()).decode() + "\nhexd " + PRINT.encode().hex() + "\n"),
    case("no-trailing-newline", "b64e last"),
    case("random-small", rand_lines(40)),
    case("random-large", rand_lines(3000)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
# cross-check the hand decoder against the library on random strings
for _ in range(20000):
    t = "".join(rnd.choice(ALPHA[:6] + "=Q") for _ in range(rnd.choice([0, 4, 4, 8, 12])))
    mine = b64d(t)
    assert mine == lib_b64d(t), t
