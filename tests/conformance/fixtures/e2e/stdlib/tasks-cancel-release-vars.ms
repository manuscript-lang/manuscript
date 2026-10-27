# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
# Cancelling a task must drop every owned value its frames hold, whatever shape holds it.
# CI runs this program against the counting runtime (scripts/leak-check.sh): any live block fails.
from "@std/collections.ms" import range
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import nanoseconds, sleep
from "@std/channels.ms" import Channel

type Box:
    name: String
    items: List[String]

type Pair:
    a: Box
    b: Map[String, List[Int]]

def nap() -> Unit:
    sleep(nanoseconds(10000000000))

def t_record() -> Int:
    var b = Box(
        name: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        items: ["a", "b"]
    )
    b.items.append("c")
    nap()
    return b.items.length()

def t_field_move() -> Int:
    var p = Pair(a: Box(name: "n", items: ["q"]), b: {"k": [1, 2]})
    let taken = p.a
    nap()
    return taken.items.length()

def t_map_loop() -> Int:
    var m = Map[String, List[Int]]()

    for i in range(0, 100):
        m.add(f"key{i}", [i, i])
        if i == 50:
            nap()

    return m.length()

def t_consume_in_loop() -> Int:
    var acc = List[String]()
    var total = 0

    for i in range(0, 10):
        let s = f"v{i}"
        acc.append(s.clone())
        nap()
        total += s.length()

    return total

def t_optional() -> Int:
    let o: Optional[List[String]] = some(["a", "b"])
    nap()
    return o.get([]).length()

def t_closure() -> Int:
    let words = ["a", "b", "c"]
    let f = lambda: words.length()
    nap()
    return f()

def t_match() -> Int:
    let r: Optional[List[Int]] = some([1, 2, 3])

    match r:
        case some(v):
            nap()
            return v.length()
        case none:
            return 0

def t_chan(ch: Channel[Unit, Unit]) -> Int:
    var c = ch
    let held = ["xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]
    let got = c.receive()
    return held.length()

def t_nested(depth: Int) -> Int:
    let s = f"depth-{depth}-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    if depth == 0:
        nap()
        return s.length()

    return t_nested(depth - 1) + s.length()

def t_var_reassign() -> Int:
    var s = "start-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    for i in range(0, 3):
        s = f"{s}-{i}"
        nap()

    return s.length()

def t_var_list_swap() -> Int:
    var a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    var b = [4, 5]
    let tmp = a
    a = b
    b = tmp
    nap()
    return a.length() + b.length()

def t_partial() -> Int:
    var p = Pair(
        a: Box(
            name: "namexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            items: ["q"]
        ),
        b: {"k": [1, 2]}
    )
    let nm = p.a.name.clone()
    nap()
    p.a.name = nm
    return p.b.length()

def t_conditional(flag: Bool) -> Int:
    var keep = ["kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"]

    if flag:
        let other = keep
        nap()
        return other.length()

    nap()
    return keep.length()

def t_loop_break() -> Int:
    var out = List[List[Int]]()

    for i in range(0, 10):
        out.append([i, i, i])

        if i == 5:
            nap()
            break

    return out.length()

def t_while_sleep() -> Int:
    var n = 0
    var buf = "bufxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    while True:
        n += 1
        buf = f"{buf}{n}"
        nap()

    return n

def run_one(which: Int) -> Unit:
    with let group = TaskGroup[Int](timeout: some(nanoseconds(1000000))):
        if which == 0: group.spawn(lambda ch: t_var_reassign())
        elif which == 1: group.spawn(lambda ch: t_var_list_swap())
        elif which == 2: group.spawn(lambda ch: t_partial())
        elif which == 3: group.spawn(lambda ch: t_conditional(True))
        elif which == 4: group.spawn(lambda ch: t_conditional(False))
        elif which == 5: group.spawn(lambda ch: t_loop_break())
        else: group.spawn(lambda ch: t_while_sleep())

        let _ = group.wait()

export def main() -> Int:
    for which in range(0, 7):
        run_one(which)
        stdout().write(f"case {which} released\n").get()

    return 0
