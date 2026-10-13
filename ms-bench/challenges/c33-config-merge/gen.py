import json, random, pathlib, re

KEY = re.compile(r"[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)*\Z")
INT = re.compile(r"-?[0-9]{1,15}\Z")

def scalar(piece):
    if piece in ("true", "false"): return ("b", piece == "true")
    if INT.match(piece): return ("i", int(piece))
    if len(piece) >= 2 and piece[0] == '"' and piece[-1] == '"': return ("s", piece[1:-1])
    return ("s", piece)

def parse_value(v):
    if v in ("true", "false"): return ("b", v == "true")
    if INT.match(v): return ("i", int(v))
    if v.startswith('"'):
        out, i = [], 1
        while i < len(v):
            c = v[i]
            if c == "\\" and i + 1 < len(v) and v[i + 1] in '"\\': out.append(v[i + 1]); i += 2; continue
            if c == '"':
                return ("s", "".join(out)) if i == len(v) - 1 else None
            out.append(c); i += 1
        return None
    if v.startswith("["):
        if not v.endswith("]") or len(v) < 2: return None
        inner = v[1:-1]
        if inner.strip(" \t") == "": return ("l", [])
        items = []
        for p in inner.split(","):
            p = p.strip(" \t")
            if not p: return None
            items.append(scalar(p))
        return ("l", items)
    return ("s", v)

def plain(v):
    k, x = v
    if k == "s": return x
    if k == "i": return str(x)
    if k == "b": return "true" if x else "false"
    return ",".join(plain(i) for i in x)

def render(v):
    k, x = v
    if k == "s": return '"' + x.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if k == "l": return "[" + ", ".join(render(i) for i in x) + "]"
    return plain(v)

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    layer, vals, src, errs = "base", {}, {}, []
    for n, raw in enumerate(lines, 1):
        l = raw.strip(" \t")
        if not l or l[0] == "#": continue
        if l.startswith("@@"): layer = l[2:].strip(" \t") or "unnamed"; continue
        if l[0] == "!":
            k = l[1:].strip(" \t")
            if not KEY.match(k): errs.append(f"line {n}: syntax error"); continue
            for x in [x for x in vals if x == k or x.startswith(k + ".")]:
                del vals[x]; del src[x]
            continue
        eq = l.find("=")
        if eq < 0: errs.append(f"line {n}: syntax error"); continue
        app = eq > 0 and l[eq - 1] == "+"
        key = l[:eq - 1 if app else eq].strip(" \t")
        if not KEY.match(key): errs.append(f"line {n}: syntax error"); continue
        v = parse_value(l[eq + 1:].strip(" \t"))
        if v is None: errs.append(f"line {n}: syntax error"); continue
        if app:
            cur = vals.get(key, ("l", []))
            if cur[0] != "l": errs.append(f"line {n}: cannot append to non-list"); continue
            vals[key] = ("l", cur[1] + (v[1] if v[0] == "l" else [v]))
        else:
            vals[key] = v
        src[key] = layer
    memo, kerrs = {}, {}
    def resolve(key):
        if key in memo: return memo[key]
        v = vals[key]
        if v[0] != "s": memo[key] = v; return v
        text, out, i = v[1], [], 0
        while i < len(text):
            if text.startswith("${", i):
                j = text.find("}", i + 2)
                if j >= 0 and KEY.match(text[i + 2:j]):
                    name = text[i + 2:j]
                    if name in vals: out.append(plain(resolve(name)))
                    else:
                        out.append(text[i:j + 1]); kerrs.setdefault(key, []).append(f"key {key}: unresolved ${{{name}}}")
                    i = j + 1; continue
            out.append(text[i]); i += 1
        memo[key] = ("s", "".join(out)); return memo[key]
    out = []
    for key in sorted(vals): out.append(f"{key} = {render(resolve(key))}  # {src[key]}")
    msgs = errs + [m for k in sorted(kerrs) for m in kerrs[k]]
    if msgs: out += ["errors:"] + ["  " + m for m in msgs]
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(33)
segs = ["db", "cache", "web", "log", "app", "net", "x", "y_1", "limits", "timeout", "host", "port", "name"]
def rkey(): return ".".join(rnd.choice(segs) for _ in range(rnd.randint(1, 3)))
def rscalar():
    return rnd.choice(["true", "false", "0", "-0", "007", "42", "-17", "12345678901234", "1234567890123456", "hello", "two words", '"quoted, text"', '"say \\"hi\\""', '"back\\\\slash"', '""', "", "${db.host}", "x-${port}-y", "${nope}", "$${x}", "${", "${a b}", "${}", "50%"])
def rline(keys):
    r = rnd.random()
    k = rnd.choice(keys) if keys and rnd.random() < .6 else rkey()
    if r < .55: return f"{k} = {rscalar()}"
    if r < .70: return f"{k}{rnd.choice(['', ' '])}+={rnd.choice([' ', ''])}{rnd.choice(['1', 'a', '[x, y]', '[]', '[1,2,3]', 'true', '\"q\"', '[a,,b]', ''])}"
    if r < .78: return f"{k} = [{rnd.choice(['', ' ', 'a, b', '1, true, \"s\"', ' x ,y ', '1,,2', 'a,', ',a', '\"p,q\"'])}]"
    if r < .84: return "!" + k
    if r < .88: return rnd.choice(["", "   ", "# comment", "  # indented", "\t"])
    if r < .92: return rnd.choice(["oops", "= value", "BadKey = 1", "a..b = 1", "1a = 2", "k = \"open", "k = \"a\"b\"", "k = [open", "a b = 1", "!", "!Bad", "@@"])
    return f"@@ {rnd.choice(['defaults', 'staging', 'prod', 'local', ' spaced name ', ''])}"
def rand_cfg(n, nkeys=0):
    keys = [rkey() for _ in range(nkeys)]
    return "\n".join(rline(keys) for _ in range(n)) + "\n"
examples = [
    case("basic", 'host = "db.local"\nport = 5432\nname = x\nurl = ${host}:${port}/main\ntags = [a, b]\n@@ prod\nhost = "db.prod"\ntags += c\n!port\ndebug = maybe?\noops\nname += 1\n'),
    case("layers", "a = 1\n@@ one\na = 2\nb = true\n@@ two\nb = false\nc = hi\n"),
]
hidden = examples + [
    case("empty", ""),
    case("only-comments", "# nothing\n\n  \n"),
    case("value-types", 'i = 007\nn = -0\nneg = -42\nbig = 123456789012345\ntoo_big = 1234567890123456\nb = true\nB = true\nt = TRUE\ns = hello world\ne =\nq = "a \\"b\\" \\\\ \\n"\n'),
    case("quoted-errors", 'a = "open\nb = "x" y"\nc = "x\\"\nd = "x\\\\"\ne = "ok"\nf = "a"b"\n'),
    case("lists", 'a = []\nb = [ ]\nc = [1, true, "x y", z]\nd = [1,,2]\ne = [,]\nf = [open\ng = ["p,q"]\nh = [ "x" ,"" ]\n'),
    case("append", 'l += 1\nl += [2, 3]\nl += x\ns = str\ns += 1\nn = 5\nn += [1]\nz = []\nz += []\nz += [a]\n'),
    case("unset-prefix", "a = 1\na.b = 2\na.b.c = 3\nab = 4\n@@ x\n!a\n@@ y\na.b = 5\n!\n!a.b.c\n"),
    case("interpolation", 'host = h\nport = 80\nflag = true\nlist = [1, a, true]\nurl = http://${host}:${port}/${flag}/${list}\nnested = [${url}]\nchain = <${url}>\nmiss = ${nope} and ${also.missing} and ${host}\nweird = $${host} ${ ${host} ${bad key} ${host\nplain = no refs\n'),
    case("source-tracking", "a = 1\n@@ l1\nb = 2\na = 3\n@@ l2\n!b\n@@ l3\nb = 4\na += 5\n@@ l4\nc = 6\n"),
    case("whitespace-and-keys", "  k1   =   spaced value   \n\tk2=tab\t\nk3 += x\nK4 = bad\n_ok = 1\nx.y.z = deep\nx..y = no\n.x = no\nx. = no\n"),
    case("random-small", rand_cfg(40, 6)),
    case("random-mid", rand_cfg(400, 30)),
    case("random-large", rand_cfg(3500, 120)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
