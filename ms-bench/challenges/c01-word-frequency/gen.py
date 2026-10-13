import json, random, re
from collections import Counter

def solve(s):
    c = Counter(w.lower() for w in re.findall(r"[A-Za-z]+", s))
    top = sorted(c.items(), key=lambda kv: (-kv[1], kv[0]))[:10]
    return "".join(f"{w} {n}\n" for w, n in top)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(1)
vocab = ["a", "Be", "see", "Dog", "ant", "zed", "Zed", "x", "tree", "tRee", "mid", "end", "it's", "don't", "a1b", "e-mail"]
big = " ".join(rnd.choice(vocab) for _ in range(5000))
ties = " ".join(f"w{chr(97 + i)}" for i in range(26)).replace("w", "")
examples = [case("basic", "the cat and the hat\n"), case("case", "Go go GO gO\nstop\n")]
hidden = [
    case("empty", ""), case("only-separators", "123 ... --- \n\n"), case("basic", "the cat and the hat\n"),
    case("case", "Go go GO gO\nstop\n"), case("ties-alpha", ties + "\n"),
    case("more-than-10", " ".join(f"{chr(97+i)}" * (i + 1) for i in range(15)) + "\n"),
    case("punct", "it's don't e-mail a1b!\nIT'S\n"), case("no-trailing-newline", "x y x"),
    case("crlf", "one\r\ntwo\r\none\r\n"), case("big", big),
    case("unicode-separates", "café café cafe naïve\n"),
]
import pathlib
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
