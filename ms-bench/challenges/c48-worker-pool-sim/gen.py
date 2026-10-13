import json, random, pathlib

def solve(s):
    lines = [l.split() for l in s.split("\n") if l.split()]
    W, Q, R = int(lines[0][1]), int(lines[0][2]), int(lines[0][3])
    tasks = []
    for t in lines[1:]:
        fails, high = 0, False
        for x in t[4:]:
            if x == "high": high = True
            else: fails = int(x[len("fails="):])
        tasks.append({"id": t[1], "arr": int(t[2]), "cost": int(t[3]), "fails": fails, "high": high,
                      "attempts": 0, "res": None})
    order = sorted(range(len(tasks)), key=lambda i: (tasks[i]["arr"], i))
    run = [None] * W            # (task index, start, end) per worker
    busy = [0] * W
    qh, qn = [], []
    ai = 0
    makespan = 0
    def start(w, i, t):
        tk = tasks[i]; tk["attempts"] += 1
        run[w] = (i, t, t + tk["cost"]); busy[w] += tk["cost"]
    while True:
        cands = [r[2] for r in run if r is not None]
        if ai < len(order): cands.append(tasks[order[ai]]["arr"])
        if not cands: break
        t = min(cands)
        # 1. completions, ascending worker index
        for w in range(W):
            r = run[w]
            if r is not None and r[2] == t:
                i, st, en = r; tk = tasks[i]; run[w] = None
                makespan = max(makespan, en)
                if tk["attempts"] <= tk["fails"]:
                    if tk["attempts"] < R + 1: (qh if tk["high"] else qn).append(i)
                    else: tk["res"] = f"{tk['id']} failed attempts={tk['attempts']} end={en}"
                else:
                    tk["res"] = f"{tk['id']} ok worker={w + 1} start={st} end={en} attempts={tk['attempts']}"
        # 2. dispatch queued tasks to idle workers (lowest index first)
        for w in range(W):
            if run[w] is None and (qh or qn):
                start(w, (qh if qh else qn).pop(0), t)
        # 3. arrivals at t in input order
        while ai < len(order) and tasks[order[ai]]["arr"] == t:
            i = order[ai]; ai += 1
            idle = next((w for w in range(W) if run[w] is None), None)
            if idle is not None: start(idle, i, t)
            elif len(qh) + len(qn) < Q: (qh if tasks[i]["high"] else qn).append(i)
            else: tasks[i]["res"] = f"{tasks[i]['id']} rejected at={t}"
    out = [tk["res"] for tk in tasks]
    for w in range(W): out.append(f"worker {w + 1} busy={busy[w]}")
    ok = sum(1 for tk in tasks if " ok " in tk["res"]); fl = sum(1 for tk in tasks if " failed " in tk["res"])
    rj = sum(1 for tk in tasks if " rejected " in tk["res"])
    out.append(f"summary ok={ok} failed={fl} rejected={rj} makespan={makespan}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}

rnd = random.Random(48)
def rand_pool(n, W, Q, R, span, maxcost, pf=.2, ph=.25):
    L = [f"pool {W} {Q} {R}"]
    for i in range(n):
        t = f"task t{i} {rnd.randint(0, span)} {rnd.randint(1, maxcost)}"
        extra = []
        if rnd.random() < pf: extra.append(f"fails={rnd.choice([1, 1, 2, 3, 5])}")
        if rnd.random() < ph: extra.append("high")
        rnd.shuffle(extra)
        L.append(" ".join([t] + extra))
    return "\n".join(L) + "\n"

examples = [case("basic", "pool 2 1 1\ntask a 0 5\ntask b 0 3\ntask c 1 2\ntask d 2 4 high\ntask e 2 1 fails=1\n")]
hidden = examples + [
    case("no-tasks", "pool 3 2 1\n"),
    case("single-worker", "pool 1 5 0\ntask a 0 3\ntask b 1 2\ntask c 2 1\ntask d 10 4\n"),
    case("idle-gap", "pool 2 0 0\ntask a 0 2\ntask b 10 3\ntask c 10 1\ntask d 10 1\n"),
    case("lowest-worker", "pool 3 0 0\ntask a 0 4\ntask b 0 2\ntask c 0 6\ntask d 2 1\ntask e 3 1\ntask f 4 1\n"),
    case("queue-full", "pool 1 2 0\ntask a 0 10\ntask b 1 1\ntask c 2 1\ntask d 3 1\ntask e 4 1\ntask f 11 1\ntask g 11 1\n"),
    case("zero-queue", "pool 2 0 0\ntask a 0 3\ntask b 0 3\ntask c 0 1\ntask d 3 1\ntask e 3 1\ntask f 3 1\n"),
    case("priority", "pool 1 4 0\ntask a 0 5\ntask n1 1 1\ntask h1 2 1 high\ntask n2 3 1\ntask h2 4 1 high\ntask n3 4 1\n"),
    case("unsorted-input", "pool 2 1 0\ntask late 9 1\ntask first 0 4\ntask mid 3 2\ntask also0 0 4\ntask tie 3 1\ntask tie2 3 1\n"),
    case("retries", "pool 2 3 2\ntask a 0 3 fails=1\ntask b 0 2 fails=2\ntask c 0 2 fails=3\ntask d 1 1 fails=2 high\ntask e 1 4\n"),
    case("retry-no-retries", "pool 2 2 0\ntask a 0 2 fails=1\ntask b 0 2\ntask c 1 2 fails=1\n"),
    case("simultaneous-completions", "pool 3 3 1\ntask a 0 4 fails=1\ntask b 0 4\ntask c 0 4 fails=1 high\ntask d 1 1\ntask e 1 1 high\ntask f 4 2\ntask g 4 2\n"),
    case("retry-bypasses-capacity", "pool 1 1 3\ntask a 0 2 fails=2\ntask b 1 1\ntask c 2 1\ntask d 3 1\n"),
    case("tabs-and-blanks", "\n  pool\t2  1\t0 \n\ntask\ta 0   2\t\n  task b 0 2  high  fails=0\n\n"),
    case("fails-token-order", "pool 2 2 1\ntask a 0 2 high fails=1\ntask b 0 2 fails=1 high\ntask c 0 2 fails=0\n"),
    case("random-small", rand_pool(30, 3, 4, 2, 20, 6)),
    case("random-pressure", rand_pool(120, 2, 3, 1, 40, 5)),
    case("random-large", rand_pool(1500, 8, 20, 2, 1600, 12)),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
