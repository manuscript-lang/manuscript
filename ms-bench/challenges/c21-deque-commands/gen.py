import json, random, pathlib
from collections import deque

def solve(s):
    d, out = deque(), []
    for line in s.split("\n"):
        p = line.split(" ")
        if not line.strip():
            continue
        c = p[0]
        if c == "push_back": d.append(p[1])
        elif c == "push_front": d.appendleft(p[1])
        elif c == "pop_back": out.append(d.pop() if d else "empty")
        elif c == "pop_front": out.append(d.popleft() if d else "empty")
        elif c == "back": out.append(d[-1] if d else "empty")
        elif c == "front": out.append(d[0] if d else "empty")
        elif c == "size": out.append(str(len(d)))
        elif c == "dump": out.append("[" + " ".join(d) + "]")
    return "".join(o + "\n" for o in out)

def case(name, s): return {"name": name, "stdin": s, "stdout": solve(s)}
rnd = random.Random(21)
def rand_ops(n, vocab):
    cmds = ["push_back", "push_front", "pop_back", "pop_front", "back", "front", "size", "dump"]
    wts = [5, 5, 3, 3, 1, 1, 1, 1]
    ops = []
    for _ in range(n):
        c = rnd.choices(cmds, wts)[0]
        ops.append(f"{c} {rnd.choice(vocab)}" if c.startswith("push") else c)
    return "\n".join(ops) + "\n"
examples = [
    case("basic", "push_back a\npush_back b\npush_front c\ndump\npop_back\npop_front\nsize\npop_front\npop_front\n"),
    case("empty-ops", "pop_back\nfront\nsize\ndump\n"),
]
hidden = examples + [
    case("empty-input", ""),
    case("only-pushes", "push_back 1\npush_front 2\npush_back -3\n"),
    case("single-element", "push_front x\nfront\nback\ndump\npop_back\ndump\nsize\n"),
    case("blank-lines", "\npush_back a\n\n\ndump\n\n"),
    case("no-trailing-newline", "push_back q\ndump"),
    case("tokens", "push_back foo-bar\npush_back 007\npush_front [x]\ndump\nback\n"),
    case("drain-both-ends", "push_back 1\npush_back 2\npush_back 3\npush_back 4\npop_front\npop_back\npop_front\npop_back\npop_back\nsize\n"),
    case("random-small", rand_ops(60, ["a", "b", "c", "1", "22"])),
    case("random-wide", rand_ops(1500, [str(i) for i in range(50)])),
    case("random-large", rand_ops(6000, [f"item{i}" for i in range(500)])),
]
root = pathlib.Path(__file__).parent
for d, cs in (("examples", examples), ("hidden", hidden)):
    (root / d).mkdir(exist_ok=True)
    (root / d / "cases.json").write_text(json.dumps(cs, indent=1) + "\n")
