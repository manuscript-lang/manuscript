import json, random, re, pathlib

NAME = r"[a-z][a-z0-9_]*"

class Err(Exception): pass

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    cfg = {}
    layer, section = None, "global"
    for i, raw in enumerate(lines, 1):
        l = raw.strip(" ")
        if l.startswith("--- ") and l[4:].strip(" ") != "":
            layer, section = l[4:].strip(" "), "global"
            continue
        if l == "" or l.startswith("#"): continue
        where = f"{layer or 'input'}:{i}"
        if layer is None: return f"error: {where}: expected layer header\n"
        if l.startswith("["):
            m = re.fullmatch(rf"\[({NAME})\]", l)
            if not m: return f"error: {where}: bad section name\n"
            section = m.group(1)
        elif l.startswith("@"):
            m = re.fullmatch(rf"@unset ({NAME})\.({NAME})", l)
            if not m: return f"error: {where}: bad directive\n"
            cfg.pop(f"{m.group(1)}.{m.group(2)}", None)
        elif "=" in l:
            k, v = l.split("=", 1)
            k, v = k.strip(" "), v.strip(" ")
            if not re.fullmatch(NAME, k): return f"error: {where}: bad key\n"
            cfg[f"{section}.{k}"] = v
        else:
            return f"error: {where}: invalid line\n"
    done, active = {}, set()
    def resolve(key):
        if key in done: return done[key]
        if key in active: raise Err(f"{key}: cycle")
        active.add(key)
        raw, out, i = cfg[key], [], 0
        while i < len(raw):
            c = raw[i]
            if c == "$" and raw[i + 1:i + 2] == "$": out.append("$"); i += 2
            elif c == "$" and raw[i + 1:i + 2] == "{":
                j = raw.find("}", i + 2)
                if j < 0: raise Err(f"{key}: bad reference")
                ref = raw[i + 2:j]
                if not re.fullmatch(rf"{NAME}\.{NAME}", ref): raise Err(f"{key}: bad reference")
                if ref not in cfg: raise Err(f"{key}: unknown reference ${{{ref}}}")
                out.append(resolve(ref)); i = j + 1
            else: out.append(c); i += 1
        active.discard(key)
        done[key] = "".join(out)
        return done[key]
    try:
        for key in sorted(cfg): resolve(key)
    except Err as e:
        return f"error: {e}\n"
    out, cur = [], None
    for key in sorted(cfg):
        sec, k = key.split(".", 1)
        if sec != cur:
            if cur is not None: out.append("")
            out.append(f"[{sec}]"); cur = sec
        out.append(f"{k} = {done[key]}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(18)
big = "--- base\n"
for L in range(4):
    big += f"--- layer{L}\n"
    for sec in ["global", "db", "cache", "web", "log"]:
        big += f"[{sec}]\n"
        for k in range(rnd.randint(3, 8)):
            if rnd.random() < .15:
                big += f"@unset {sec}.k{rnd.randint(0, 8)}\n"
            elif rnd.random() < .3:
                big += f"k{k} = pre-${{{rnd.choice(['db', 'web', 'log'])}.k0}}-post {rnd.randint(0, 99)}\n"
            else:
                big += f"k{k} = value {rnd.randint(0, 999)}\n"
        if sec != "global": big += "k0 = base-" + sec + "\n"
big += "\n"
big = big.replace("--- base\n", "# generated\n", 1)
examples = [
    case("basic", "# defaults\n--- defaults\nname = demo\n[server]\nhost = localhost\nport = 8080\ndebug = true\nurl = http://${server.host}:${server.port}/${global.name}\n--- production\n[server]\nhost = example.com\nport = 443\n@unset server.debug\nprice = $$5 for $name\n"),
    case("cycle", "--- a\nx = ${global.y}\ny = ${global.x}\n"),
]
hidden = examples + [
    case("empty", ""),
    case("override-order", "--- a\nk = 1\n[s]\nk = a\n--- b\n[s]\nk = b\n--- c\nk = 3\n"),
    case("section-resets-per-layer", "--- a\n[s]\nx = 1\n--- b\ny = 2\n"),
    case("whitespace-and-equals", "--- a\n   key   =   spaced value   \neq = a=b=c\nhash = x # not a comment\nempty =\n[s]\nv = 1\n"),
    case("unset-and-reset", "--- a\nx = 1\ny = 2\n@unset global.x\n@unset global.nope\n--- b\n@unset global.y\nx = 9\n"),
    case("chained-references", "--- a\na = 1\nb = ${global.a}2\nc = ${global.b}3\n[s]\nd = ${global.c}-${global.a}\n"),
    case("dollar-forms", "--- a\na = $$\nb = $$${global.a}\nc = $x $ {y} $\nd = $$$$\ne = ${global.a}$\n"),
    case("deep-cycle-reports-reentered-key", "--- a\n[a]\nk = ${b.k}\n[b]\nk = ${c.k}\n[c]\nk = ${b.k}\n"),
    case("unknown-reference", "--- a\n[z]\nok = fine\n[a]\nv = ${z.nope}\n"),
    case("bad-reference", "--- a\nz = ${global.y\n"),
    case("first-error-in-sorted-order", "--- a\n[b]\nk = ${x.y}\n[a]\nk = ${global.q\n"),
    case("missing-layer-header", "# fine\nx = 1\n--- a\n"),
    case("bad-directive", "--- a\n@unset x\n"),
    case("bad-key", "--- one\nok = 1\n--- two\nBad = 2\n"),
    case("invalid-line", "--- a\njust words\n"),
    case("layer-header-spaces", "---  padded name  \nx = 1\n--- \n"),
    case("big", big),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
