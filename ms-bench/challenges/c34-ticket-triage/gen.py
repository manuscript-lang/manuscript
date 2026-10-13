import json, random, pathlib, re

B = " \t"
def tokens(s): return re.findall(r"[a-z0-9]+", s)

def norm_subject(s):
    s = s.lower()
    while True:
        s = s.lstrip(B)
        if s.startswith("re:"): s = s[3:]
        elif s.startswith("fwd:"): s = s[4:]
        else: break
    return " ".join(x for x in re.split(r"[ \t]+", s) if x)

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    section, now, vips, routes, problems = None, 0, set(), [], []
    ids, tickets, by_key, merged = set(), [], {}, 0
    raw_tickets = []
    for n, raw in enumerate(lines, 1):
        l = raw.strip(B)
        if not l or l[0] == "#": continue
        if l[0] == "[":
            if l == "[rules]": section = "r"
            elif l == "[tickets]": section = "t"
            else: section = None; problems.append(f"line {n}: unknown section")
            continue
        if section == "r":
            t = re.split(r"[ \t]+", l)
            ok = False
            if t[0] == "now" and len(t) == 2 and re.fullmatch(r"[0-9]{1,9}", t[1]): now = int(t[1]); ok = True
            elif t[0] == "vip" and len(t) == 2: vips.add(t[1].lower()); ok = True
            elif t[0] == "route" and len(t) == 4 and re.fullmatch(r"[a-z0-9]+", t[1].lower()) and t[3] in ("1", "2", "3", "4", "5") and t[1].isascii():
                routes.append((t[1].lower(), t[2], int(t[3]))); ok = True
            if not ok: problems.append(f"line {n}: bad rule")
        elif section == "t":
            p = [x.strip(B) for x in l.split("|", 4)]
            if len(p) < 5 or not p[0] or " " in p[0] or "\t" in p[0] or not p[1] or not re.fullmatch(r"[0-9]{1,9}", p[2]) or not p[3]:
                problems.append(f"line {n}: bad ticket"); continue
            if p[0] in ids: problems.append(f"line {n}: duplicate id"); continue
            ids.add(p[0]); raw_tickets.append(p)
    queues, by_key = {}, {}
    for id_, rep, created, subj, body in raw_tickets:
        key = (rep.lower(), norm_subject(subj))
        if key in by_key: by_key[key]["merged"] += 1; merged += 1; continue
        toks = set(tokens((subj + " " + body).lower()))
        q, pr = "general", 3
        for w, qq, pp in routes:
            if w in toks: q, pr = qq, pp; break
        if rep.lower() in vips: pr = max(1, pr - 1)
        if now - int(created) >= 1440: pr = max(1, pr - 1)
        e = {"id": id_, "pr": pr, "created": int(created), "subj": subj, "merged": 0}
        by_key[key] = e; queues.setdefault(q, []).append(e)
    out = []
    for q in sorted(queues):
        es = sorted(queues[q], key=lambda e: (e["pr"], e["created"], e["id"]))
        out.append(f"queue {q} ({len(es)})")
        for e in es:
            out.append(f"  {e['id']} P{e['pr']} {e['subj']}" + (f" (+{e['merged']} merged)" if e["merged"] else ""))
    out.append(f"summary: tickets={sum(len(v) for v in queues.values())} merged={merged} problems={len(problems)}")
    if problems: out += ["problems:"] + ["  " + p for p in problems]
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(34)
RULES = "[rules]\nnow 5000\nvip Dana\nvip  EVE \nroute refund billing 2\nroute invoice billing 3\nroute crash eng 1\nroute login auth 2\nroute slow eng 4\nroute password auth 3\nroute 404 web 3\n"
subjects = ["App crash on start", "refund please", "cannot login", "Invoice 404 missing", "slow dashboard", "Question", "password reset", "feature idea", "Crash!", "login ISSUE"]
bodies = ["", "see attached", "it is slow and also crashes", "need refund now", "thanks", "pipe | in | body", "login fails: password wrong"]
names = ["alice", "Bob", "dana", "Dana", "eve", "frank", "G"]
def rand_ticket(i):
    subj = rnd.choice(subjects)
    if rnd.random() < .7: subj += f" #{rnd.randint(1, 40)}"
    for _ in range(rnd.choice([0, 0, 0, 1, 2])): subj = rnd.choice(["Re: ", "RE:", "fwd: ", "  re:  ", "Fwd:Re: "]) + subj
    if rnd.random() < .2: subj = subj.replace(" ", rnd.choice(["  ", "\t"]))
    return f"t{i if rnd.random() < .95 else rnd.randint(0, i)}|{rnd.choice(names)}|{rnd.randint(0, 6500)}|{subj}|{rnd.choice(bodies)}"
def messy(i):
    return rnd.choice(["", "# note", "   ", "[tickets]", "t9|x|1|only|four", "|nobody|5|s|b", "tx y|n|5|s|b", "tz|n|abc|s|b", "tq|n|5||b", "tw|n|1234567890|s|b", "[rules]", "now 6000", "now x", "vip", "vip a b", "route x y", "route crash q 9", "route CRASH eng2 2", "bogus 1", "[other]", "[tickets]"])
def rand_input(n, noise=.12):
    ls = [RULES.rstrip("\n"), "[tickets]"]
    for i in range(n):
        ls.append(messy(i) if rnd.random() < noise else rand_ticket(i))
    return "\n".join(ls) + "\n"
examples = [
    case("basic", "[rules]\nnow 3000\nvip Dana\nroute refund billing 2\nroute crash eng 1\n[tickets]\nt1|alice|100|App crash on start|stack trace attached\nt2|Dana|2900|Re: refund please|where is my money\nt3|alice|150|RE: re: app crash on start|same here\nt4|bob|2990|hello\nt5|bob|2990|Question|just asking\n"),
    case("small", "[rules]\nroute printer hardware 4\n[tickets]\na|x|0|Printer jam|\nb|y|1|printer? PRINTER|\n"),
]
hidden = examples + [
    case("empty", ""),
    case("no-rules", "[tickets]\nb|x|5|second|\na|y|5|first|\nc|z|1|early|\n"),
    case("routing-first-match", "[rules]\nroute b q2 2\nroute a q1 1\n[tickets]\nt|u|0|a b|\nu|u|0|b a|\nv|u|0|ab|a-b\n"),
    case("priority-adjust", "[rules]\nnow 2000\nvip v\nroute hot q 1\nroute warm q 2\n[tickets]\n1|v|2000|hot|\n2|v|0|warm a|\n3|w|0|warm b|\n4|w|560|warm c|\n5|w|561|warm d|\n6|w|3000|warm e|\n7|v|0|none|\n8|v|0|hot again|\n"),
    case("dedup", "[rules]\n[tickets]\n1|Al|9|Hello  World|\n2|al|8|re: RE:  hello world|x\n3|AL|7|Fwd: hello\tworld|\n4|bo|7|hello world|\n5|al|7|Hello World again|\n6|al|9|reply: hello world|\n"),
    case("dup-ids", "[tickets]\n1|a|1|x|\n1|b|2|y|\n2|a|1|re: x|\n2|c|1|z|\n"),
    case("sections", "x|y|1|s|b\n[rules]\nroute s q 1\n[tickets]\n1|a|1|s|\n[bogus]\n2|a|1|s|\nroute t q 2\n[rules]\nroute t q 5\n[tickets]\n3|a|1|t|\n"),
    case("whitespace", "  [rules]  \n\tnow\t100  \n route   cat   pets   2 \n [tickets]\n  1 | A | 5 |  The cat  | purr \n"),
    case("body-pipes-and-limits", "[tickets]\n1|a|999999999|s|b|c|d\n2|a|1000000000|s|b\n3|a|0|t|\n"),
    case("random-small", rand_input(30)),
    case("random-mid", rand_input(400)),
    case("random-large", rand_input(4000, .05)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
