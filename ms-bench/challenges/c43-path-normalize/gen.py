import json, random, pathlib

def clean(p):
    ab = p.startswith("/")
    st = []
    for s in p.split("/"):
        if s == "" or s == ".": continue
        if s == "..":
            if st and st[-1] != "..": st.pop()
            elif not ab: st.append("..")
        else: st.append(s)
    return ab, st

def show(ab, st):
    if ab: return "/" + "/".join(st)
    return "/".join(st) if st else "."

def base(p):
    q = p.rstrip("/")
    if q == "": return "/"
    return q[q.rfind("/") + 1:]

def solve(s):
    out = []
    for line in s.split("\n"):
        t = line.replace("\t", " ").split()
        if not t: continue
        c, a = t[0], t[1:]
        n = len(a)
        if c == "clean" and n == 1: out.append(show(*clean(a[0])))
        elif c == "join" and n >= 1: out.append(show(*clean("/".join(a))))
        elif c == "resolve" and n == 2:
            if not a[0].startswith("/"): out.append("error: cwd not absolute")
            else: out.append(show(*clean(a[1] if a[1].startswith("/") else a[0] + "/" + a[1])))
        elif c == "rel" and n == 2:
            (x, xs), (y, ys) = clean(a[0]), clean(a[1])
            if x != y: out.append("error: cannot relativize"); continue
            k = 0
            while k < len(xs) and k < len(ys) and xs[k] == ys[k]: k += 1
            if ".." in xs[k:]: out.append("error: cannot relativize"); continue
            r = [".."] * (len(xs) - k) + ys[k:]
            out.append("/".join(r) if r else ".")
        elif c == "base" and n == 1: out.append(base(a[0]))
        elif c == "dir" and n == 1:
            i = a[0].rfind("/")
            out.append("." if i < 0 else show(*clean(a[0][:i + 1])))
        elif c == "ext" and n == 1:
            b = base(a[0])
            i = b.rfind(".")
            out.append(b[i:] if i > 0 else "(none)")
        elif c == "common" and n >= 1:
            cs = [clean(x) for x in a]
            if len({x for x, _ in cs}) > 1: out.append("error: mixed"); continue
            pre = cs[0][1]
            for _, st in cs[1:]:
                k = 0
                while k < len(pre) and k < len(st) and pre[k] == st[k]: k += 1
                pre = pre[:k]
            out.append(show(cs[0][0], pre))
        else: out.append("error: bad command")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(43)

def cmds(*xs): return "".join(x + "\n" for x in xs)
examples = [case("basic", cmds("clean /a/./b/../c//d/", "clean ../x/../../y", "join a b/../c /d", "resolve /home/me ../you/./f.txt", "rel /a/b /a/c/d", "base /a/b.tar.gz", "dir /a/b/", "ext /a/b.tar.gz", "common /a/b/c /a/b/d /a/e", "frob"))]

def rpath():
    segs = [rnd.choice(["a", "b", "c", "..", ".", "", "dd", "a.b", ".h", "x.tar.gz", "..", "e"]) for _ in range(rnd.randint(1, 6))]
    p = "/".join(segs)
    if rnd.random() < .5: p = "/" + p
    if rnd.random() < .2: p += "/"
    if p.strip("/") == "" and rnd.random() < .5: p = "/"
    return p or "x"
def rcmd():
    c = rnd.choice(["clean", "join", "resolve", "rel", "base", "dir", "ext", "common", "rel", "rel", "common"])
    if c in ("clean", "base", "dir", "ext"): return f"{c} {rpath()}"
    if c in ("join", "common"):
        if c == "common" and rnd.random() < .7:
            pre = "/".join(rnd.choice("abc") for _ in range(rnd.randint(0, 3)))
            ab = rnd.random() < .6
            ps = [("/" if ab else "") + pre + "/" + "/".join(rnd.choice("abcd") for _ in range(rnd.randint(0, 3))) for _ in range(rnd.randint(1, 4))]
            return "common " + " ".join(p.replace("//", "/") if rnd.random() < .5 else p for p in ps)
        return f"{c} " + " ".join(rpath() for _ in range(rnd.randint(1, 4)))
    if c == "resolve": return f"resolve {rpath() if rnd.random()<.2 else '/' + rpath().lstrip('/')} {rpath()}"
    ab = rnd.random() < .7
    f = lambda: ("/" if ab else "") + "/".join(rnd.choice(["a", "b", "c", "..", "."]) for _ in range(rnd.randint(0, 4)))
    return f"rel {f() or 'a'} {f() or 'b'}"
big = [rcmd() for _ in range(600)]

hidden = examples + [
    case("clean-basics", cmds("clean a", "clean .", "clean ..", "clean /", "clean //", "clean ///a///b///", "clean ./a", "clean a/.", "clean a/./b/./c", "clean ./././", "clean a/b/..", "clean a/b/../..", "clean a/b/../../..", "clean a/../..", "clean ../..", "clean ../../a/..", "clean ./..", "clean .../a", "clean a/.../..", "clean ..a/b", "clean a..")),
    case("clean-absolute", cmds("clean /..", "clean /../..", "clean /../a", "clean /a/../..", "clean /a/b/../../../c", "clean /./.", "clean //a//..//b", "clean /a/./b/../c//d/", "clean /a/b/c/../../..", "clean /a/b/c/../../../..")),
    case("join", cmds("join a", "join a b c", "join a /b", "join /a b", "join /a /b", "join a .. ..", "join /a .. ..", "join . .", "join a/ /b/", "join .. a", "join a b/../c /d", "join / a", "join // a")),
    case("resolve", cmds("resolve /a b", "resolve /a /b", "resolve /a ../b", "resolve /a/b ../../../c", "resolve a b", "resolve a /b", "resolve /a .", "resolve / ..", "resolve /a/b/ ./c/", "resolve //x y", "resolve x ../..", "resolve /a")),
    case("rel", cmds("rel /a/b /a/c/d", "rel /a/b /a/b", "rel /a/b /a", "rel /a /a/b/c", "rel /a/b /c", "rel / /a", "rel /a /", "rel / /", "rel a b", "rel a a/b", "rel a/b/c a/d", "rel a ../b", "rel ../a b", "rel ../a ../b", "rel ../a ../a/c", "rel ../a ..", "rel .. ..", "rel . a", "rel a .", "rel /a a", "rel a /a", "rel a/../.. ../b", "rel /a/./b/../c /a//d/", "rel ./ .")),
    case("base", cmds("base a", "base /a", "base /a/", "base a/b/c.txt", "base a//", "base /", "base //", "base ///", "base .", "base ..", "base a/..", "base a/.", "base .hidden", "base a/.hidden/", "base a.b/c", "base x/y/")),
    case("dir", cmds("dir a", "dir /a", "dir /a/", "dir a/b", "dir a/b/", "dir a//b", "dir /", "dir //", "dir a/b/c/d", "dir ..", "dir ../a", "dir a/..", "dir a/../b", "dir ./a", "dir /a/./b", "dir /a/b/..", "dir a/../../b", "dir /../a")),
    case("ext", cmds("ext a.txt", "ext a.tar.gz", "ext a.", "ext .bashrc", "ext .a.b", "ext ..", "ext .", "ext a", "ext a/b.c/d", "ext a.b/", "ext /x/.hidden", "ext /x/.hidden.txt", "ext a..b", "ext file.TXT/", "ext /", "ext a.b.", "ext ...")),
    case("common", cmds("common /a/b/c", "common a/./b/../c", "common /a/b/c /a/b/d /a/e", "common /a/b /a/b", "common /a/b/c /a/b", "common /a /b", "common a b", "common a/b a/c", "common a/b/c a/b/c/d a/b", "common /a /b/c", "common a /a", "common /a a", "common a b /c", "common ../a ../b", "common ../a b", "common /a/../b /b/c", "common a/.. b/..", "common / /a", "common . a", "common /a/b/ //a//b//c")),
    case("bad-commands", cmds("clean", "clean a b", "join", "resolve /a", "resolve /a b c", "rel a", "rel a b c", "base", "dir a b", "ext", "common", "CLEAN a", "clean_ a", "norm a", "x", "clean a b c d")),
    case("whitespace", "\n  clean\t/a//b/..  \n\n\tjoin   a\t\tb  \n   \nrel  /a   /b\t\n"),
    case("random-large", cmds(*big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
