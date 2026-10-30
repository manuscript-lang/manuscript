# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
# Cancelling a task must drop every owned value its frames hold, whatever shape holds it.
# CI runs this program against the counting runtime (scripts/leak-check.sh): any live block fails.
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"
import nanoseconds, sleep from "@std/time.ms"
import Channel from "@std/channels.ms"

type Box:
    name: String
    items: List[String]

type Pair:
    a: Box
    b: Map[String, List[Int]]

fn nap() Unit:
    sleep(nanoseconds(10000000000))

fn t_record() Int:
    var b = Box(
        name: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        items: ["a", "b"]
    )
    b.items.append("c")
    nap()
    return b.items.length()

fn t_field_move() Int:
    var p = Pair(a: Box(name: "n", items: ["q"]), b: {"k": [1, 2]})
    let taken = p.a
    nap()
    return taken.items.length()

fn t_map_loop() Int:
    var m = Map[String, List[Int]]()

    for i in 0..100:
        m.add("key{i}", [i, i])
        if i == 50:
            nap()

    return m.length()

fn t_consume_in_loop() Int:
    var acc = List[String]()
    var total = 0

    for i in 0..10:
        let s = "v{i}"
        acc.append(s.clone())
        nap()
        total += s.length()

    return total

fn t_optional() Int:
    let o: List[String]? = some(["a", "b"])
    nap()
    return o.get([]).length()

fn t_closure() Int:
    let words = ["a", "b", "c"]
    let f = fn: words.length()
    nap()
    return f()

fn t_match() Int:
    let r: List[Int]? = some([1, 2, 3])

    match r:
        some(v):
            nap()
            return v.length()
        none:
            return 0

fn t_chan(ch: Channel[Unit, Unit]) Int:
    var c = ch
    let held = ["xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"]
    let _got = c.receive()
    return held.length()

fn t_nested(depth: Int) Int:
    let s = "depth-{depth}-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    if depth == 0:
        nap()
        return s.length()

    return t_nested(depth - 1) + s.length()

fn run_one(which: Int) Unit:
    let group = TaskGroup[Int](timeout: some(nanoseconds(1000000)))

    if which == 0: group.spawn(fn ch: t_record())
    else if which == 1: group.spawn(fn ch: t_field_move())
    else if which == 2: group.spawn(fn ch: t_map_loop())
    else if which == 3: group.spawn(fn ch: t_consume_in_loop())
    else if which == 4: group.spawn(fn ch: t_optional())
    else if which == 5: group.spawn(fn ch: t_closure())
    else if which == 6: group.spawn(fn ch: t_match())
    else if which == 7: group.spawn(fn ch: t_chan(ch))
    else: group.spawn(fn ch: t_nested(5))

    let _ = group.wait()

export fn main() Int:
    for which in 0..9:
        run_one(which)
        stdout().write("case {which} released\n").get()

    return 0
