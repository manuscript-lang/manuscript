import json, random, pathlib

def solve(s):
    books, members, loans, holds, fines, out = {}, set(), {}, {}, {}, []
    arity = {"book": 3, "member": 2, "checkout": 4, "return": 4, "renew": 4, "hold": 3, "overdue": 2, "report": 1}
    dig = lambda x: x.isascii() and x.isdigit()
    for line in s.split("\n"):
        t = line.split()
        if not t: continue
        c = t[0]
        if c not in arity or len(t) != arity[c]: out.append("error: bad command"); continue
        if c == "book":
            if not dig(t[2]) or int(t[2]) == 0: out.append("error: bad copies"); continue
            books[t[1]] = books.get(t[1], 0) + int(t[2]); holds.setdefault(t[1], []); out.append("ok"); continue
        if c == "member":
            if t[1] in members: out.append(f"error: member exists {t[1]}")
            else: members.add(t[1]); fines[t[1]] = 0; out.append("ok")
            continue
        if c == "report":
            out.append(f"members={len(members)} books={len(books)}")
            for m in sorted(members, key=str.encode):
                out.append(f"{m} loans={sum(1 for (mm, b) in loans if mm == m)} fines={fines[m]}")
            for b in sorted(books, key=str.encode):
                out.append(f"{b} copies={books[b]} out={sum(1 for (mm, bb) in loans if bb == b)} holds={len(holds[b])}")
            continue
        if c in ("overdue", "checkout", "return", "renew") and not dig(t[-1]): out.append("error: bad day"); continue
        if c == "overdue":
            day = int(t[1])
            rows = sorted(((m, b, day - l["due"]) for (m, b), l in loans.items() if day > l["due"]), key=lambda r: (r[0].encode(), r[1].encode()))
            if not rows: out.append("none")
            for m, b, late in rows: out.append(f"{m} {b} late={late}")
            continue
        m, b = t[1], t[2]
        if m not in members: out.append(f"error: unknown member {m}"); continue
        if b not in books: out.append(f"error: unknown book {b}"); continue
        out_n = sum(1 for (mm, bb) in loans if bb == b)
        avail = books[b] - out_n; q = holds[b]
        if c == "checkout":
            day = int(t[3])
            if (m, b) in loans: out.append("error: already borrowed"); continue
            if sum(1 for (mm, bb) in loans if mm == m) >= 3: out.append("error: loan limit reached"); continue
            if any(day > l["due"] for (mm, bb), l in loans.items() if mm == m): out.append("error: has overdue loans"); continue
            if avail <= 0: out.append("error: no copies available"); continue
            ok = q.index(m) < avail if m in q else avail > len(q)
            if not ok: out.append("error: reserved for holds"); continue
            if m in q: q.remove(m)
            loans[(m, b)] = {"due": day + 14, "ren": 0}
            out.append(f"ok due={day + 14}")
        elif c == "return":
            day = int(t[3])
            if (m, b) not in loans: out.append("error: not borrowed"); continue
            l = loans.pop((m, b)); fine = 10 * max(0, day - l["due"]); fines[m] += fine
            out.append(f"ok fine={fine}")
        elif c == "renew":
            day = int(t[3])
            if (m, b) not in loans: out.append("error: not borrowed"); continue
            l = loans[(m, b)]
            if day > l["due"]: out.append("error: overdue"); continue
            if l["ren"] >= 2: out.append("error: renewal limit"); continue
            if q: out.append("error: held by others"); continue
            l["due"] += 14; l["ren"] += 1; out.append(f"ok due={l['due']}")
        else:
            if (m, b) in loans: out.append("error: already borrowed"); continue
            if m in q: out.append("error: already on hold"); continue
            if avail > len(q): out.append("error: copies available"); continue
            q.append(m); out.append(f"ok position={len(q)}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(37)
def rand_script(n, nm, nb):
    ms = [f"m{i}" for i in range(nm)]; bs = [f"b{i}" for i in range(nb)]
    L = [f"member {m}" for m in ms] + [f"book {b} {rnd.randint(1, 2)}" for b in bs]
    day = 1
    for _ in range(n):
        day += rnd.choice([0, 0, 1, 2, 3, 5]) if rnd.random() < .9 else -rnd.randint(1, 5)
        day = max(day, 0)
        r = rnd.random(); m = rnd.choice(ms); b = rnd.choice(bs)
        if r < .33: L.append(f"checkout {m} {b} {day}")
        elif r < .6: L.append(f"return {m} {b} {day}")
        elif r < .72: L.append(f"renew {m} {b} {day}")
        elif r < .85: L.append(f"hold {m} {b}")
        elif r < .87: L.append(f"overdue {day}")
        elif r < .9: L.append("report")
        elif r < .93: L.append(rnd.choice([f"checkout {m} {b} x", f"checkout {m} zz {day}", f"hold ghost {b}", f"return {m} {b}", "book b0 0", "frob", "member m0"]))
        else: L.append(f"checkout {m} {b} {day}")
    L.append("report")
    return "\n".join(L) + "\n"
examples = [case("basic", "book dune 1\nmember ann\nmember bob\ncheckout ann dune 1\nhold bob dune\nrenew ann dune 5\nreturn ann dune 20\ncheckout bob dune 21\noverdue 40\nreport\n")]
hidden = examples + [
    case("empty", "report\noverdue 3\n"),
    case("setup-errors", "book a 0\nbook a x\nbook a\nbook a 2\nbook a 1\nmember m\nmember m\nmember\nreport\ncheckout m a\ncheckout m a -1\n"),
    case("loan-limit", "member m\nbook a 1\nbook b 1\nbook c 1\nbook d 1\ncheckout m a 0\ncheckout m b 0\ncheckout m c 0\ncheckout m d 0\ncheckout m c 0\nreturn m a 0\ncheckout m d 1\nreport\n"),
    case("overdue-blocks", "member m\nbook a 3\nbook b 3\ncheckout m a 0\ncheckout m b 14\ncheckout m b 15\nreturn m a 15\ncheckout m b 15\ncheckout m b 16\nreturn m a 15\noverdue 14\noverdue 15\noverdue 100\n"),
    case("renewals", "member m\nbook a 1\ncheckout m a 0\nrenew m a 14\nrenew m a 20\nrenew m a 42\nrenew m a 28\nrenew m a 43\nreturn m a 43\nreturn m a 43\nrenew m a 1\nreport\n"),
    case("hold-reservation", "member x\nmember y\nmember z\nmember w\nbook b 1\nbook c 2\ncheckout x b 0\nhold y b\nhold z b\nhold x b\nhold y b\nhold w b\nreturn x b 1\ncheckout w b 2\ncheckout z b 2\ncheckout y b 3\ncheckout z b 3\nreturn y b 4\ncheckout w b 5\ncheckout z b 5\nreport\ncheckout x c 6\ncheckout y c 6\nhold z c\nhold w c\nreturn x c 7\nreturn y c 7\ncheckout x c 8\ncheckout w c 8\ncheckout z c 8\ncheckout x c 8\nreport\n"),
    case("hold-free-copy", "member x\nmember y\nbook b 3\nhold x b\ncheckout y b 0\ncheckout x b 0\nhold y b\nhold x b\nreturn y b 1\nhold y b\nreport\n"),
    case("fines", "member m\nmember n\nbook a 1\nbook b 1\ncheckout m a 5\nreturn m a 19\ncheckout m a 20\nreturn m a 100\ncheckout n b 100\nreturn n b 50\nreport\noverdue 0\n"),
    case("whitespace", "  member\tm \n\n\tbook   a   1\ncheckout   m a\t4 \nreport  \noverdue\t\t20\nReport\n"),
    case("random-small", rand_script(80, 3, 3)),
    case("random-large", rand_script(2000, 8, 6)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
