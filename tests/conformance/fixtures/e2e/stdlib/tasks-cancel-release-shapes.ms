# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
# Cancelling a task must drop every owned value its frames hold, whatever shape holds it.
# CI runs this program against the counting runtime (scripts/leak-check.sh): any live block fails.
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

    for i in 0..100:
        m.add(f"key{i}", [i, i])
        if i == 50:
            nap()

    return m.length()

def t_consume_in_loop() -> Int:
    var acc = List[String]()
    var total = 0

    for i in 0..10:
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
    let _got = c.receive()
    return held.length()

def t_nested(depth: Int) -> Int:
    let s = f"depth-{depth}-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    if depth == 0:
        nap()
        return s.length()

    return t_nested(depth - 1) + s.length()

def run_one(which: Int) -> Unit:
    with let group = TaskGroup[Int](timeout: some(nanoseconds(1000000))):
        if which == 0: group.spawn(lambda ch: t_record())
        elif which == 1: group.spawn(lambda ch: t_field_move())
        elif which == 2: group.spawn(lambda ch: t_map_loop())
        elif which == 3: group.spawn(lambda ch: t_consume_in_loop())
        elif which == 4: group.spawn(lambda ch: t_optional())
        elif which == 5: group.spawn(lambda ch: t_closure())
        elif which == 6: group.spawn(lambda ch: t_match())
        elif which == 7: group.spawn(lambda ch: t_chan(ch))
        else: group.spawn(lambda ch: t_nested(5))

        let _ = group.wait()

export def main() -> Int:
    for which in 0..9:
        run_one(which)
        stdout().write(f"case {which} released\n").get()

    return 0
