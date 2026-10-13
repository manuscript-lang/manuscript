import json, random, re, pathlib

PRI = ["low", "normal", "high", "urgent"]
IDRE = re.compile(r"[A-Z]+-[0-9]+")
AGRE = re.compile(r"[a-z]+")
STAT = ["new", "assigned", "in_progress", "resolved", "closed"]

def solve(s):
    lines = s.split("\n")
    if lines and lines[-1] == "": lines.pop()
    T = {}
    out = []
    ARITY = {"assign": 3, "start": 2, "resolve": 2, "close": 2, "reopen": 2, "escalate": 2, "show": 2, "report": 1}
    for l in lines:
        if l.strip(" ") == "": continue
        t = l.split(" ")
        c = t[0]
        if c != "open" and c not in ARITY: out.append("error: unknown command"); continue
        if c == "open":
            parts = l.split(" ", 3)
            if len(parts) < 4 or parts[3] == "": out.append("error: usage"); continue
            _, tid, pri, title = parts
            if not IDRE.fullmatch(tid): out.append("error: bad id"); continue
            if pri not in PRI: out.append("error: bad priority"); continue
            if tid in T: out.append(f"error: {tid} already exists"); continue
            T[tid] = dict(pri=PRI.index(pri), title=title, agent=None, status="new", reopened=0)
            out.append("ok"); continue
        if len(t) != ARITY[c]: out.append("error: usage"); continue
        if c == "report":
            counts = {s: 0 for s in STAT}
            for v in T.values(): counts[v["status"]] += 1
            out.append(" ".join(f"{s}={counts[s]}" for s in STAT))
            by = {}
            for tid, v in T.items():
                if v["status"] in ("assigned", "in_progress"): by.setdefault(v["agent"], []).append(tid)
            order = lambda ids: sorted(ids, key=lambda i: (-T[i]["pri"], i.encode()))
            for a in sorted(by, key=lambda x: x.encode()): out.append(f"{a}: " + " ".join(order(by[a])))
            un = [i for i, v in T.items() if v["status"] == "new"]
            if un: out.append("unassigned: " + " ".join(order(un)))
            continue
        tid = t[1]
        if c == "assign" and not AGRE.fullmatch(t[2]): out.append("error: bad agent"); continue
        if tid not in T: out.append(f"error: unknown ticket {tid}"); continue
        v = T[tid]; st = v["status"]
        if c == "assign":
            if st in ("resolved", "closed"): out.append(f"error: {tid} is {st}"); continue
            v["agent"] = t[2]
            if st == "new": v["status"] = "assigned"
            out.append("ok")
        elif c == "start":
            if st == "new": out.append(f"error: {tid} has no assignee")
            elif st == "assigned": v["status"] = "in_progress"; out.append("ok")
            elif st == "in_progress": out.append(f"error: {tid} already in progress")
            else: out.append(f"error: {tid} is {st}")
        elif c == "resolve":
            if st == "in_progress": v["status"] = "resolved"; out.append("ok")
            else: out.append(f"error: {tid} cannot be resolved from {st}")
        elif c == "close":
            if st == "resolved": v["status"] = "closed"; out.append("ok")
            else: out.append(f"error: {tid} cannot be closed from {st}")
        elif c == "reopen":
            if st in ("resolved", "closed"): v["status"] = "in_progress"; v["reopened"] += 1; out.append("ok")
            else: out.append(f"error: {tid} cannot be reopened from {st}")
        elif c == "escalate":
            if st == "closed": out.append(f"error: {tid} is closed")
            elif v["pri"] == 3: out.append(f"error: {tid} is already urgent")
            else: v["pri"] += 1; out.append("ok")
        elif c == "show":
            out.append(f"{tid} [{PRI[v['pri']]}] {st} agent={v['agent'] or '-'} reopened={v['reopened']}: {v['title']}")
    return "".join(x + "\n" for x in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(8)
ids = [f"{p}-{n}" for p in ("T", "BUG", "OPS") for n in (1, 2, 3, 10, 11, 100)]
verbs = ["assign"] * 4 + ["start"] * 4 + ["resolve"] * 3 + ["close"] * 2 + ["reopen", "escalate", "escalate", "show", "show", "report"]
big = [f"open {i} {rnd.choice(PRI)} Ticket {i} about thing {rnd.randint(1, 99)}" for i in ids]
for _ in range(900):
    v = rnd.choice(verbs)
    tid = rnd.choice(ids + ["X-9"] if rnd.random() < .03 else ids)
    if v == "assign": big.append(f"assign {tid} {rnd.choice(['ann', 'bob', 'cy', 'dee'])}")
    elif v == "report": big.append("report")
    else: big.append(f"{v} {tid}")
examples = [
    case("basic", "open T-1 high Login page broken\nopen T-2 low Typo in footer\nassign T-1 ann\nstart T-1\nresolve T-2\nshow T-1\nescalate T-1\nescalate T-1\nreport\n"),
    case("lifecycle", "open A-1 normal Fix it\nassign A-1 bob\nstart A-1\nresolve A-1\nclose A-1\nreopen A-1\nshow A-1\n"),
]
hidden = examples + [
    case("open-errors", "open\nopen T-1\nopen T-1 low\nopen t-1 low x\nopen T1 low x\nopen T- low x\nopen T-1 LOW x\nopen T-1 medium x\nopen T-1 low x\nopen T-1 high y\nopen T-2 low \n"),
    case("title-spacing", "open T-1 low   spaced   title \nshow T-1\nopen T-2 low a\nshow T-2\n"),
    case("assign-rules", "open T-1 low a\nassign T-1 Ann\nassign T-1 ann1\nassign T-9 ann\nassign T-1 ann\nassign T-1 bob\nshow T-1\nstart T-1\nresolve T-1\nassign T-1 cy\nclose T-1\nassign T-1 cy\nassign T-1\nassign T-1 a b\n"),
    case("start-rules", "open T-1 low a\nstart T-1\nassign T-1 ann\nstart T-1\nstart T-1\nresolve T-1\nstart T-1\nclose T-1\nstart T-1\n"),
    case("resolve-close-rules", "open T-1 low a\nresolve T-1\nclose T-1\nassign T-1 ann\nresolve T-1\nclose T-1\nstart T-1\nclose T-1\nresolve T-1\nresolve T-1\nclose T-1\nclose T-1\n"),
    case("reopen-rules", "open T-1 low a\nreopen T-1\nassign T-1 ann\nreopen T-1\nstart T-1\nreopen T-1\nresolve T-1\nreopen T-1\nshow T-1\nresolve T-1\nclose T-1\nreopen T-1\nshow T-1\nclose T-1\nreopen T-1\nreopen T-1\nshow T-1\n"),
    case("escalate-rules", "open T-1 low a\nescalate T-1\nshow T-1\nescalate T-1\nescalate T-1\nescalate T-1\nshow T-1\nassign T-1 ann\nstart T-1\nresolve T-1\nclose T-1\nescalate T-1\nopen T-2 urgent b\nescalate T-2\n"),
    case("usage-and-unknown", "show\nshow T-1 T-2\nreport now\nstart\nclose A B\nOPEN T-1 low x\nlist\nunknown T-1\nshow T-404\nshow t-1\nstart T-404\n"),
    case("check-order", "assign T-9 Bad\nassign T-9 ann\nxyz\nopen T-1 low x\nassign T-1 Bad\n"),
    case("report-grouping", "open B-2 low a\nopen B-1 urgent b\nopen A-10 high c\nopen A-9 high d\nopen C-1 normal e\nopen N-2 low f\nopen N-1 low g\nopen N-3 urgent h\nassign B-2 zed\nassign B-1 zed\nassign A-10 amy\nassign A-9 amy\nassign C-1 zed\nstart B-1\nstart A-9\nassign A-9 zed\nreport\n"),
    case("report-empty", "report\nopen T-1 low a\nassign T-1 ann\nstart T-1\nresolve T-1\nreport\nclose T-1\nreport\n"),
    case("blank-lines", "\n  \nopen T-1 low a\n\nshow T-1\n  \n"),
    case("big-session", "\n".join(big) + "\n"),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
