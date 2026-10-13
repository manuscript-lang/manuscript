import json, random, pathlib, itertools

class Bad(Exception): pass

# atom: ("lit", byte) ("any",) ("star",) ("class", neg, [(lo,hi)...])
def parse_class(p, i):
    """p[i] is the char after '['; returns (atom, next index)."""
    neg = False
    if i < len(p) and p[i] == "!": neg = True; i += 1
    items = []
    def get(i):
        if i >= len(p): raise Bad()
        if p[i] == "\\":
            if i + 1 >= len(p): raise Bad()
            return ord(p[i + 1]), i + 2
        return ord(p[i]), i + 1
    while True:
        if i >= len(p): raise Bad()
        if p[i] == "]":
            if not items: raise Bad()
            return ("class", neg, items), i + 1
        c, i = get(i)
        if i + 1 < len(p) and p[i] == "-" and p[i + 1] != "]":
            d, i = get(i + 1)
            if d < c: raise Bad()
            items.append((c, d))
        else:
            items.append((c, c))

def parse(p):
    """returns list of elements; element = list of alternatives; alternative = list of atoms"""
    elems, cur, i = [], [], 0
    def flush():
        nonlocal cur
        if cur: elems.append([cur]); cur = []
    while i < len(p):
        ch = p[i]
        if ch == "\\":
            if i + 1 >= len(p): raise Bad()
            cur.append(("lit", ord(p[i + 1]), True)); i += 2
        elif ch == "?": cur.append(("any",)); i += 1
        elif ch == "*": cur.append(("star",)); i += 1
        elif ch == "[":
            a, i = parse_class(p, i + 1); cur.append(a)
        elif ch == "}": raise Bad()
        elif ch == "{":
            flush()
            i += 1
            alts, alt = [], []
            while True:
                if i >= len(p): raise Bad()
                c = p[i]
                if c == "}": alts.append(alt); i += 1; break
                if c == "{": raise Bad()
                if c == ",": alts.append(alt); alt = []; i += 1
                elif c == "\\":
                    if i + 1 >= len(p): raise Bad()
                    alt.append(("lit", ord(p[i + 1]), True)); i += 2
                elif c == "?": alt.append(("any",)); i += 1
                elif c == "*": alt.append(("star",)); i += 1
                elif c == "[":
                    a, i = parse_class(p, i + 1); alt.append(a)
                else: alt.append(("lit", ord(c), False)); i += 1
            elems.append(alts)
        else:
            cur.append(("lit", ord(ch), False)); i += 1
    flush()
    return elems

def expansions(elems):
    for combo in itertools.product(*elems):
        yield [a for alt in combo for a in alt]

def split_atoms(atoms):
    segs, cur = [], []
    for a in atoms:
        if a[0] == "lit" and a[1] == 47: segs.append(cur); cur = []
        else: cur.append(a)
    segs.append(cur)
    return segs

def seg_match(atoms, s):
    n, m = len(atoms), len(s)
    if m and s[0] == ".":
        if not atoms or atoms[0][0] == "lit" and atoms[0][1] != 46 or atoms[0][0] != "lit": return False
    # dp over atoms
    cur = [False] * (m + 1)
    cur[0] = True
    for a in atoms:
        nxt = [False] * (m + 1)
        if a[0] == "star":
            run = False
            for j in range(m + 1):
                run = run or cur[j]
                nxt[j] = run
        else:
            for j in range(m):
                if not cur[j]: continue
                c = ord(s[j])
                if a[0] == "lit": ok = c == a[1]
                elif a[0] == "any": ok = True
                else:
                    inn = any(lo <= c <= hi for lo, hi in a[2])
                    ok = inn != a[1]
                if ok: nxt[j + 1] = True
        cur = nxt
    return cur[m]

def is_globstar(atoms):
    return len(atoms) == 2 and atoms[0] == ("star",) and atoms[1] == ("star",)

def match_segs(ps, xs):
    memo = {}
    def go(i, j):
        if (i, j) in memo: return memo[(i, j)]
        if i == len(ps): r = j == len(xs)
        elif is_globstar(ps[i]):
            r = go(i + 1, j)
            if not r and j < len(xs) and not xs[j].startswith("."): r = go(i, j + 1)
        elif j < len(xs): r = seg_match(ps[i], xs[j]) and go(i + 1, j + 1)
        else: r = False
        memo[(i, j)] = r
        return r
    return go(0, 0)

def solve(s):
    out = []
    for line in s.split("\n"):
        t = line.replace("\t", " ").split()
        if not t: continue
        if len(t) != 2: out.append("error: bad line"); continue
        try: elems = parse(t[0])
        except Bad: out.append("error: invalid pattern"); continue
        xs = t[1].split("/")
        ok = any(match_segs(split_atoms(e), xs) for e in expansions(elems))
        out.append("match" if ok else "no match")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(42)

def lines(pairs): return "".join(f"{a} {b}\n" for a, b in pairs)

examples = [case("basic", lines([("src/*.ms", "src/main.ms"), ("src/*.ms", "src/a/main.ms"), ("**/test_*.go", "a/b/test_x.go"), ("**/x", "a/.hidden/x"), ("*.{go,rs}", "lib.rs"), ("[!a-c]at", "bat"), ("a[", "a")]))]

PIECES = [("a", "a"), ("b", "b"), ("*", None), ("?", "a"), ("[ab]", "b"), ("[!a]", "c"), ("[a-c]", "c"), (".", "."), ("{a,b}", "b"), ("{,x}", ""), ("\\*", "*"), ("a*", "aXY"), ("x", "x"), ("*", None)]
def rand_pair():
    ps, xs = [], []
    for _ in range(rnd.randint(1, 4)):
        if rnd.random() < .15:
            ps.append("**")
            xs += [rnd.choice(["p", "q", ".r", "s"]) for _ in range(rnd.randint(0, 3))]
            continue
        p, x = "", ""
        for _ in range(rnd.randint(1, 3)):
            pc, xc = rnd.choice(PIECES)
            if xc is None: xc = "".join(rnd.choice("abx") for _ in range(rnd.randint(0, 3)))
            p += pc; x += xc
        ps.append(p); xs.append(x)
    path = "/".join(xs)
    if rnd.random() < .3 and path:
        i = rnd.randrange(len(path))
        path = path[:i] + rnd.choice("abx./") + path[i + 1:]
    if not path: path = "a"
    return "/".join(ps), path
big = [rand_pair() for _ in range(700)]

hidden = examples + [
    case("star-qmark", lines([("*", "abc"), ("*", "a/b"), ("*", ""), ("a*c", "abc"), ("a*c", "ac"), ("a*c", "abcd"), ("a?c", "ac"), ("a?c", "abc"), ("a?c", "a/c"), ("a*b*c", "aXbYbZc"), ("*a*a*a", "aaaa"), ("*a*a*a", "aa"), ("a/*/c", "a/b/c"), ("a/*/c", "a//c"), ("a/*", "a/"), ("a/*", "a")])),
    case("globstar", lines([("**", "a/b/c"), ("**", "a"), ("**", "/a"), ("a/**", "a"), ("a/**", "a/b/c"), ("a/**/c", "a/c"), ("a/**/c", "a/x/y/c"), ("a/**/c", "a/x/y/d"), ("**/b/**", "a/b/c"), ("**/b/**", "b"), ("**/**/x", "x"), ("**/**/x", "p/q/x"), ("a**", "abc"), ("a**", "a/b"), ("**b", "ab"), ("**b", "a/b"), ("\\*\\*", "**"), ("\\*\\*", "a"), ("\\**", "*x"), ("a/**/", "a/b/"), ("a/**/", "a/")])),
    case("dot-rule", lines([("*", ".hidden"), (".*", ".hidden"), ("?hidden", ".hidden"), ("[.]hidden", ".hidden"), ("\\.hidden", ".hidden"), ("*", "."), ("*", ".."), (".*", ".."), ("..", ".."), ("a/*", "a/.b"), ("a/.*", "a/.b"), ("a*", "a.b"), ("**", ".a"), ("**", "a/.b/c"), ("**/c", ".a/c"), (".a/**/c", ".a/x/c"), ("**/.a", "x/.a"), ("[!a].x", ".x"), ("{*,.*}", ".x"), ("{*,.x}", ".x")])),
    case("classes", lines([("[abc]", "b"), ("[abc]", "d"), ("[!abc]", "d"), ("[!abc]", "a"), ("[a-c]x", "bx"), ("[a-c]x", "dx"), ("[c-a]", "b"), ("[-a]", "-"), ("[a-]", "-"), ("[a-]", "a"), ("[a-]", "b"), ("[a\\-c]", "b"), ("[a\\-c]", "-"), ("[]]", "]"), ("[]", "a"), ("[!]", "a"), ("[\\]]", "]"), ("[a", "a"), ("[a\\]", "a"), ("[!!]", "a"), ("[!!]", "!"), ("[{a,b}]", "{"), ("[{a,b}]", "a"), ("[*?]", "?"), ("[a-c-e]", "d"), ("[a-c-e]", "-"), ("[+--]", ","), ("[0-9a-f]*", "9z"), ("[/]", "/"), ("a[/]b", "a/b"), ("[!/]", "/")])),
    case("braces", lines([("{a,b}", "a"), ("{a,b}", "c"), ("{a,}", ""), ("x{a,}", "x"), ("x{a,}", "xa"), ("x{}", "x"), ("{a}", "a"), ("{a,b}{c,d}", "bc"), ("{a,b}{c,d}", "cb"), ("*.{go,rs,ms}", "x.ms"), ("src/{a,b}/*.c", "src/b/x.c"), ("src/{a,b/c}/x", "src/b/c/x"), ("{a,b/c}", "b/c"), ("{**,x}/y", "p/q/y"), ("{a,b", "a"), ("a}", "a"), ("{a,{b,c}}", "a"), ("a,b", "a,b"), ("a,b", "a"), ("{a\\,b,c}", "a,b"), ("{a\\,b,c}", "a"), ("{a,b\\}", "a"), ("{[}],x}", "}"), ("{[}],x}", "x"), ("{a,[b}", "a"), ("{*,a}b", "ab"), ("\\{a,b\\}", "{a,b}"), ("\\}", "}"), ("{a,b}}", "a")])),
    case("escapes", lines([("a\\*b", "a*b"), ("a\\*b", "axb"), ("a\\?", "a?"), ("a\\[b", "a[b"), ("\\\\", "\\"), ("a\\/b", "a/b"), ("a\\", "a"), ("\\", "x"), ("\\a", "a"), ("\\.x", ".x"), ("\\.*", ".xyz"), ("\\*", "*"), ("\\*", "a"), ("a\\/**", "a/b/c"), ("x\\/\\/y", "x//y"), ("/a", "/a"), ("/a", "a"), ("a/", "a/"), ("a/", "a"), ("//", "//"), ("/**", "/a/b")])),
    case("slashes", lines([("a//b", "a//b"), ("a/*/b", "a//b"), ("a/**/b", "a//b"), ("/*", "/a"), ("/*", "/"), ("*/", "a/"), ("*/", "/"), ("**/", "a/b/"), ("**/", "a/b"), ("/**/a", "/a"), ("/**/a", "/x/a"), ("**/a", "/a"), ("/", "/"), ("/", "//"), ("a/b", "a/b/"), ("a/b/", "a/b/")])),
    case("bad-lines", "a\n\n   \na b c\nonly\ta\tb\tc\n  x  y  \n\t*.c\tfoo.c\t\n\n"),
    case("invalid-over-match", lines([("a{b,c}[", "ab"), ("*{x", "a"), ("a}{b", "a"), ("{a,b}[z-a]", "a"), ("**[", "x"), ("a\\", "a"), ("{a,b}\\", "a"), ("{a,b}{", "a"), ("[[]", "["), ("[[]]", "[]"), ("[a-\\]]", "b"), ("[\\a-c]", "b"), ("[a-\\c]", "b")])),
    case("complex", lines([("src/**/*.{c,h}", "src/a/b/x.h"), ("src/**/*.{c,h}", "src/x.c"), ("src/**/*.{c,h}", "src/a/.b/x.c"), ("src/**/[!_]*.c", "src/a/_x.c"), ("src/**/[!_]*.c", "src/a/x.c"), ("**/*.min.js", "a/b/c.min.js"), ("**/*.min.js", "a/b/.min.js"), ("**/node_modules/**", "x/node_modules/y/z"), ("**/node_modules/**", "x/.node_modules/y"), ("{lib,src}/**/test?.{go,rs}", "src/p/q/test1.rs"), ("{lib,src}/**/test?.{go,rs}", "lib/test1.go"), ("{lib,src}/**/test?.{go,rs}", "lib/test12.go"), ("a*b*c*d", "abcd"), ("a*b*c*d", "aXXbYYcZZd"), ("a*b*c*d", "aXXbYYcZZ"), ("*.*", "a.b"), ("*.*", "ab"), ("*.*", ".b")])),
    case("random-large", lines(big)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
