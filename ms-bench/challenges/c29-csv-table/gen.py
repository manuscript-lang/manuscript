import json, random, pathlib, re

def parse_row(line):
    fields, i, n = [], 0, len(line)
    while True:
        if i < n and line[i] == '"':
            i += 1; buf = []
            while i < n:
                if line[i] == '"':
                    if i + 1 < n and line[i + 1] == '"': buf.append('"'); i += 2; continue
                    i += 1; break
                buf.append(line[i]); i += 1
            fields.append("".join(buf))
        else:
            j = line.find(",", i)
            if j < 0: j = n
            fields.append(line[i:j]); i = j
        if i < n and line[i] == ",":
            i += 1
            if i == n: fields.append(""); break
            continue
        break
    return fields

def solve(s):
    rows = [parse_row(l) for l in s.split("\n") if l != ""]
    if not rows: return ""
    ncol = len(rows[0])
    norm = [(r + [""] * ncol)[:ncol] for r in rows]
    head, data = norm[0], norm[1:]
    num = [bool(data) and all(re.fullmatch(r"-?[0-9]+", r[c]) for r in data) for c in range(ncol)]
    w = [max(len(r[c]) for r in norm) for c in range(ncol)]
    def fmt(r):
        cells = [r[c].rjust(w[c]) if num[c] else r[c].ljust(w[c]) for c in range(ncol)]
        return " | ".join(cells).rstrip(" ")
    out = [fmt(head), "-+-".join("-" * x for x in w)] + [fmt(r) for r in data]
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(29)
def q(v):
    return '"' + v.replace('"', '""') + '"'
def enc(v):
    if "," in v or '"' in v or rnd.random() < .1: return q(v)
    return v
def rand_csv(ncol, nrow, numeric_cols=()):
    head = [f"col{c}" + rnd.choice(["", "x", " long header"]) for c in range(ncol)]
    ls = [",".join(enc(h) for h in head)]
    for _ in range(nrow):
        cells = []
        for c in range(ncol):
            if c in numeric_cols and rnd.random() < .97: v = str(rnd.randint(-999, 99999))
            else: v = rnd.choice(["", "a", "hello world", "x,y", 'say "hi"', "  sp  ", "12", "-", "-3", "007", "q" * rnd.randint(1, 15)])
            cells.append(enc(v))
        k = rnd.random()
        if k < .05: cells = cells[:-1] or cells
        elif k < .1: cells.append("extra")
        ls.append(",".join(cells))
        if rnd.random() < .03: ls.append("")
    return "\n".join(ls) + "\n"
examples = [
    case("basic", 'name,qty,note\napple,3,"red, sweet"\nkiwi,12,\nfig,-5,"say ""hi"""\n'),
    case("numeric-only", "a,b\n1,22\n333,4\n"),
]
hidden = examples + [
    case("empty", ""),
    case("blank-only", "\n\n"),
    case("header-only", "id,name\n"),
    case("header-only-single", "x\n"),
    case("ragged", "a,b,c\n1\n1,2,3,4,5\n,,\n"),
    case("trailing-comma", "a,b,\n1,2,\n3,4,5\n"),
    case("numeric-with-blank-cell", "n,m\n1,2\n,3\n4,5\n"),
    case("negative-and-zeros", "n\n-1\n007\n0\n-0\n"),
    case("not-numeric", "n\n1\n+2\n3.5\n-\n"),
    case("quoted-edge", 'a,b\n"","x"\n"a,b","c""d"\n"""",","\n'),
    case("spaces-kept", "a,b\n  x  ,y  \n z,  \n"),
    case("no-trailing-newline", "k,v\nx,1"),
    case("single-column", "name\nalice\nbob\n"),
    case("random-small", rand_csv(3, 8, (1,))),
    case("random-wide", rand_csv(8, 60, (0, 3, 5))),
    case("random-large", rand_csv(6, 2500, (1, 4))),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
