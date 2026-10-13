import json, random, pathlib

def solve(s):
    counters, out, fence = [0] * 7, [], False
    for line in s.split("\n"):
        if line.startswith("```"):
            fence = not fence; continue
        if fence: continue
        n = 0
        while n < len(line) and line[n] == "#": n += 1
        if not (1 <= n <= 6): continue
        rest = line[n:]
        if not rest.startswith(" "): continue
        title = rest.lstrip(" ").rstrip(" ")
        if not title: continue
        counters[n] += 1
        for k in range(n + 1, 7): counters[k] = 0
        num = ".".join(str(c) for c in counters[1:n + 1])
        out.append("  " * (n - 1) + f"{num} {title}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(28)
words = ["Intro", "Setup", "Usage", "API", "FAQ", "Notes", "v2 changes", "C# tips", "a # b", "Done #", "x"]
def rand_doc(n):
    ls, lvl = [], 1
    for _ in range(n):
        r = rnd.random()
        if r < .45:
            lvl = max(1, min(6, lvl + rnd.choice([-2, -1, 0, 1, 1, 2])))
            ls.append("#" * lvl + " " * rnd.randint(1, 3) + rnd.choice(words) + rnd.choice(["", "", " ", "  "]))
        elif r < .55: ls.append(rnd.choice(["#nospace", "####### seven", "# ", "#   ", "#\ttab", " # indented", "##", "text # not heading"]))
        elif r < .65:
            ls.append("```" + rnd.choice(["", "py", "sh"]))
        elif r < .75: ls.append("# fenced?" if rnd.random() < .5 else "## also fenced?")
        else: ls.append(rnd.choice(["", "plain text", "- list item", "> quote", "===="]))
    return "\n".join(ls) + "\n"
examples = [
    case("basic", "# Guide\nIntro text\n## Install\n```sh\n# not a heading\n```\n## Use\n### Flags\n#hashtag\n# Appendix\n"),
    case("skipped-levels", "# A\n### B\n## C\n#### D\n# E\n###### F\n"),
]
hidden = examples + [
    case("empty", ""),
    case("no-headings", "just text\n#nope\n####### x\n# \n"),
    case("only-h1", "# a\n# b\n# c\n"),
    case("starts-deep", "### x\n## y\n# z\n### w\n"),
    case("six-levels", "# 1\n## 2\n### 3\n#### 4\n##### 5\n###### 6\n###### 6b\n##### 5b\n"),
    case("spaces", "#    padded title   \n##  two  words \n#\tTab\n  # indented\n"),
    case("fences", "# a\n```\n# b\n```\n# c\n```py\n## d\n``` \n## e\n"),
    case("unclosed-fence", "# a\n```\n# b\n# c\n"),
    case("hashes-in-title", "# C# and F#\n## ## inner\n### trailing ###\n"),
    case("no-trailing-newline", "# a\n## b"),
    case("random-small", rand_doc(30)),
    case("random-mid", rand_doc(400)),
    case("random-large", rand_doc(4000)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
