import json, random, pathlib

def check(line):
    st = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for i, ch in enumerate(line, 1):
        if ch in "([{": st.append((ch, i))
        elif ch in pairs:
            if not st or st[-1][0] != pairs[ch]: return f"error {i}"
            st.pop()
    return f"error {st[0][1]}" if st else "ok"

def case(name, s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    return {"name": name, "stdin": s, "stdout": "".join(check(l) + "\n" for l in lines)}

rnd = random.Random(2)
def rand_line(n): return "".join(rnd.choice("()[]{}ab ") for _ in range(n))
def balanced(depth):
    if depth == 0: return ""
    o, c = rnd.choice(["()", "[]", "{}"])
    return o + balanced(depth - 1) + c + balanced(depth // 2)
examples = [case("basic", "(a[b]c)\n(]\n((x)\n")]
hidden = [
    case("basic", "(a[b]c)\n(]\n((x)\n"), case("empty-line", "\n()\n\n"), case("no-trailing-newline", "([)]"),
    case("only-close", "}\n"), case("wrong-kind", "{[}]\n"), case("unclosed-earliest", "([{\n"),
    case("unclosed-middle", "(a)[b{c\n"), case("no-brackets", "hello world\n"), case("empty-input", ""),
    case("random", "\n".join(rand_line(rnd.randint(0, 30)) for _ in range(300)) + "\n"),
    case("deep-balanced", "\n".join(balanced(rnd.randint(1, 12)) for _ in range(50)) + "\n"),
    case("deep-10000", "(" * 10000 + ")" * 10000 + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
