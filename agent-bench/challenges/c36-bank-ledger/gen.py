import json, random, pathlib

FEE = 5

def solve(s):
    acc, out, fees = {}, [], 0
    def digits(t): return t.isascii() and t.isdigit()
    def amt_ok(t): return digits(t) and int(t) > 0
    for line in s.split("\n"):
        t = line.split()
        if not t: continue
        c = t[0]
        arity = {"open": 3, "deposit": 3, "withdraw": 3, "transfer": 4, "freeze": 2, "unfreeze": 2, "report": 1}
        if c not in arity or len(t) != arity[c]:
            out.append("error: bad command"); continue
        if c == "report":
            tb = 0
            for k in sorted(acc, key=lambda x: x.encode()):
                a = acc[k]; tb += a["bal"]
                out.append(f"{k} balance={a['bal']} limit={a['lim']} ops={a['ops']} rejected={a['rej']} frozen={'yes' if a['fz'] else 'no'}")
            out.append(f"total balance={tb} fees={fees}"); continue
        if c == "open":
            if not digits(t[2]): out.append("error: invalid limit"); continue
            if t[1] in acc: out.append(f"error: account exists {t[1]}"); continue
            acc[t[1]] = {"bal": 0, "lim": int(t[2]), "ops": 0, "rej": 0, "fz": False}
            out.append("ok"); continue
        if c in ("freeze", "unfreeze"):
            if t[1] not in acc: out.append(f"error: unknown account {t[1]}"); continue
            acc[t[1]]["fz"] = c == "freeze"; out.append("ok"); continue
        ids = t[1:3] if c == "transfer" else t[1:2]
        amount = t[-1]
        bad = next((i for i in ids if i not in acc), None)
        if bad is not None: out.append(f"error: unknown account {bad}"); continue
        def rej(i, msg): acc[i]["rej"] += 1; out.append(msg)
        if c == "transfer" and ids[0] == ids[1]: rej(ids[0], "error: same account"); continue
        if not amt_ok(amount): rej(ids[0], "error: invalid amount"); continue
        fz = next((i for i in ids if acc[i]["fz"]), None)
        if fz is not None: rej(fz, f"error: account frozen {fz}"); continue
        n = int(amount); fee = 0
        if c == "deposit":
            a = acc[ids[0]]; a["bal"] += n; a["ops"] += 1; out.append(f"ok {a['bal']}"); continue
        a = acc[ids[0]]
        new = a["bal"] - n
        if a["bal"] >= 0 and new < 0: new -= FEE; fee = FEE
        if new < -a["lim"]: rej(ids[0], f"error: overdraft limit exceeded {ids[0]}"); continue
        a["bal"] = new; a["ops"] += 1; fees += fee
        sfx = f" fee={fee}" if fee else ""
        if c == "withdraw": out.append(f"ok {new}{sfx}")
        else:
            b = acc[ids[1]]; b["bal"] += n; b["ops"] += 1
            out.append(f"ok {new} {b['bal']}{sfx}")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(36)
def rand_script(n, ids, hot=False):
    L = []
    for i in ids: L.append(f"open {i} {rnd.choice([0, 0, 10, 50, 200])}")
    for _ in range(n):
        r = rnd.random(); a = rnd.choice(ids); b = rnd.choice(ids)
        amt = str(rnd.choice([1, 5, 7, 20, 40, 100, 250, 0, "x", "007", "-3", "2.5"] if rnd.random() < .15 else [rnd.randint(1, 120)]))
        if r < .25: L.append(f"deposit {a} {amt}")
        elif r < .5: L.append(f"withdraw {a} {amt}")
        elif r < .8: L.append(f"transfer {a} {b} {amt}")
        elif r < .82: L.append(f"freeze {a}")
        elif r < .9: L.append(f"unfreeze {a}")
        elif r < .92: L.append(f"deposit zz {amt}")
        elif r < .95: L.append("report")
        else: L.append(rnd.choice(["bogus 1", "deposit a", "report now", "open q"]))
    L.append("report")
    return "\n".join(L) + "\n"
examples = [case("basic", "open a 20\nopen b 0\ndeposit a 10\nwithdraw a 25\nwithdraw a 10\ntransfer a b 3\nfreeze b\ndeposit b 1\nreport\n")]
hidden = examples + [
    case("empty-report", "report\n"),
    case("open-errors", "open a 5\nopen a 9\nopen b -1\nopen c\nopen d x\nopen e 0x1\nopen f 007\nreport\n"),
    case("amount-forms", "open a 0\ndeposit a 007\ndeposit a 0\ndeposit a +5\ndeposit a 1.5\ndeposit a\ndeposit a  3\nwithdraw a -2\nreport\n"),
    case("fee-once", "open a 100\nwithdraw a 10\nwithdraw a 10\ndeposit a 30\nwithdraw a 5\ndeposit a 5\nwithdraw a 1\nreport\n"),
    case("fee-boundary", "open a 15\nwithdraw a 10\nwithdraw a 11\nwithdraw a 10\nopen b 0\nwithdraw b 1\ndeposit b 7\nwithdraw b 7\nwithdraw b 1\nreport\n"),
    case("transfer-order", "open a 0\nopen b 0\nfreeze a\nfreeze b\ntransfer x y 1\ntransfer x a 1\ntransfer a y 1\ntransfer a a 1\ntransfer a a 0\ntransfer a b 0\ntransfer b a 1\ntransfer a b 1\nreport\n"),
    case("transfer-fee", "open a 30\nopen b 0\ntransfer a b 10\ntransfer a b 10\ntransfer a b 10\ntransfer b a 2\nreport\n"),
    case("frozen-lifecycle", "open a 10\ndeposit a 5\nfreeze a\nwithdraw a 1\ndeposit a 1\nunfreeze a\nunfreeze zz\nfreeze zz\nwithdraw a 1\nreport\n"),
    case("whitespace-bad", "\n  open   a\t10  \n\n\tdeposit a 4\nOPEN b 1\nwithdraw a 1 2\nreport extra\n   report   \n"),
    case("byte-order", "open b 0\nopen B 0\nopen a 0\nopen _ 0\nopen 10 0\nopen 9 0\nreport\n"),
    case("random-small", rand_script(60, ["a", "b", "c"])),
    case("random-large", rand_script(1500, [f"acct{i}" for i in range(12)])),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
