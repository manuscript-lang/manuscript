import json, random, re, pathlib

def shift(text, key_for, sign):
    out, i = [], 0
    for ch in text:
        if "a" <= ch <= "z" or "A" <= ch <= "Z":
            base = ord("a") if ch >= "a" else ord("A")
            k = key_for(i)
            out.append(chr((ord(ch) - base + sign * k) % 26 + base))
            i += 1
        else:
            out.append(ch)
    return "".join(out)

def solve_line(line):
    parts = line.split(" ", 3)
    if len(parts) < 4 or parts[3] == "": return "error: bad command"
    cipher, mode, key, text = parts
    if cipher not in ("caesar", "vigenere"): return "error: bad cipher"
    if mode not in ("enc", "dec"): return "error: bad mode"
    sign = 1 if mode == "enc" else -1
    if cipher == "caesar":
        if not re.fullmatch(r"-?[0-9]{1,7}", key): return "error: bad key"
        k = int(key)
        return shift(text, lambda i: k, sign)
    if not re.fullmatch(r"[A-Za-z]+", key): return "error: bad key"
    ks = [ord(c.lower()) - 97 for c in key]
    return shift(text, lambda i: ks[i % len(ks)], sign)

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return "".join(solve_line(l) + "\n" for l in lines if l.strip(" ") != "")

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(9)
alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ      .,!?0123456789"
def text(n): return "".join(rnd.choice(alpha) for _ in range(n)).strip(" ") or "x"
big = []
for _ in range(200):
    c = rnd.choice(["caesar", "vigenere"])
    k = str(rnd.randint(-100, 100)) if c == "caesar" else "".join(rnd.choice("abcXYZ") for _ in range(rnd.randint(1, 8)))
    big.append(f"{c} {rnd.choice(['enc', 'dec'])} {k} {text(rnd.randint(1, 80))}")
examples = [
    case("basic", "caesar enc 3 Hello, World!\ncaesar dec 3 Khoor, Zruog!\nvigenere enc Key Attack at dawn\nvigenere dec Key Kxrkgi kx bkal\nrot13 enc 13 x\ncaesar enc 3x abc\ncaesar enc\n"),
    case("wraparound", "caesar enc 1 xyz XYZ\ncaesar enc -1 abc ABC\n"),
]
hidden = examples + [
    case("big-shifts", "caesar enc 26 Same\ncaesar enc 27 Same\ncaesar enc -27 Same\ncaesar dec 1000000 Mixed Case 123\ncaesar enc -0 zero\ncaesar enc 0000012 padded\n"),
    case("key-advances-on-letters-only", "vigenere enc ab a-b c d!e\nvigenere enc bcd aaa aaa aaa\nvigenere dec bcd bbb bbb bbb\n"),
    case("vigenere-key-case", "vigenere enc KEY hello world\nvigenere enc key hello world\nvigenere enc aA zZ\nvigenere enc Z abc\n"),
    case("non-letters", "caesar enc 5 1234 !@#$ ... ---\ncaesar enc 3 café naïve\nvigenere enc abc über\n"),
    case("spaces-in-text", "caesar enc 1 a  b   c\ncaesar enc 1  lead\ncaesar enc 1 trail \nvigenere enc a   x\n"),
    case("bad-command", "caesar\ncaesar enc\ncaesar enc 3\ncaesar enc 3 \nvigenere dec key \nx\n"),
    case("bad-cipher", "Caesar enc 3 abc\nrot13 enc 3 abc\nrot enc 3 abc\n vigenere enc k abc\n"),
    case("bad-mode", "caesar encrypt 3 abc\ncaesar ENC 3 abc\nvigenere de k abc\nvigenere  k abc\n"),
    case("bad-key", "caesar enc +3 abc\ncaesar enc 3.5 abc\ncaesar enc abc abc\ncaesar enc - abc\ncaesar enc 12345678 abc\nvigenere enc k3 abc\nvigenere enc - abc\nvigenere enc k-y abc\ncaesar enc 3 abc\n"),
    case("check-order", "x y z w\ncaesar y z w\ncaesar enc z w\nvigenere enc 5 w\nvigenere enc 5\n"),
    case("blank-lines", "\n  \ncaesar enc 1 a\n\n   \ncaesar dec 1 b\n"),
    case("big", "\n".join(big) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
