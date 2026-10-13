import json, random, pathlib, re

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")

def render(line, vars_):
    out, i = [], 0
    while i < len(line):
        two = line[i:i + 2]
        if two == "{{": out.append("{"); i += 2
        elif two == "}}": out.append("}"); i += 2
        elif line[i] == "{":
            j = line.find("}", i + 1)
            if j >= 0 and IDENT.match(line[i + 1:j]):
                name = line[i + 1:j]
                out.append(vars_.get(name, f"<undefined:{name}>")); i = j + 1
            else:
                out.append("{"); i += 1
        else:
            out.append(line[i]); i += 1
    return "".join(out)

def solve(s):
    lines = s.split("\n")
    if "---" not in lines: return ""
    k = lines.index("---")
    vars_ = {}
    for l in lines[:k]:
        if "=" in l:
            n, v = l.split("=", 1)
            if IDENT.match(n): vars_[n] = v
    tpl = lines[k + 1:]
    if tpl and tpl[-1] == "": tpl = tpl[:-1]   # text after the last newline is not a line
    return "".join(render(l, vars_) + "\n" for l in tpl)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(27)
names = ["name", "user", "x", "_tmp", "a1", "Title", "count", "path"]
def rand_tpl(nlines):
    atoms = ["{%s}", "{{", "}}", "{", "}", " ", "text", "{%s}", "{ %s}", "{%s ", "{1x}", "{}", "{a-b}", "=", "x{%s}y", "{{%s}}"]
    ls = []
    for _ in range(nlines):
        ls.append("".join((a % rnd.choice(names + ["nope"])) if "%s" in a else a for a in (rnd.choice(atoms) for _ in range(rnd.randint(0, 12)))))
    return ls
def rand_case(ndefs, nlines):
    defs = []
    for _ in range(ndefs):
        n = rnd.choice(names)
        defs.append(f"{n}={rnd.choice(['', 'v', 'hello world', 'a=b', '{x}', '{{', '}', ' pad '])}")
    return "\n".join(defs) + "\n---\n" + "\n".join(rand_tpl(nlines)) + "\n"
examples = [
    case("basic", "who=World\ngreeting=Hello\n---\n{greeting}, {who}!\n{{literal}} {missing} { oops }\ndone\n"),
    case("repeat", "n=7\n---\n{n}{n} {n}\n"),
]
hidden = examples + [
    case("empty", ""),
    case("no-separator", "a=1\nb=2\n"),
    case("no-template", "a=1\n---\n"),
    case("empty-lines-kept", "a=1\n---\n\n{a}\n\n\nend\n"),
    case("bad-definitions", "a=1\n1a=2\n=3\nno equals\nb c=4\n_ok=5\nA=6\n---\n{a}{1a}{_ok}{A}{b}\n"),
    case("redefinition-and-equals", "a=1\na=x=y\ne=\n---\n[{a}][{e}]\n"),
    case("value-not-rescanned", "a={b}\nb=B\nc={{\n---\n{a} {c}\n"),
    case("brace-edge-cases", "x=X\n---\n{{{x}}}\n{{{{\n}}}}}\n}x{\n{x\n{x}}\n{ x}\n{x }\n{}\n{{x}}\n{x{x}\n"),
    case("no-trailing-newline", "a=1\n---\n{a}"),
    case("second-separator-is-template", "a=1\n---\n{a}\n---\n{a}\n"),
    case("random-small", rand_case(5, 12)),
    case("random-mid", rand_case(30, 300)),
    case("random-large", rand_case(60, 3000)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
