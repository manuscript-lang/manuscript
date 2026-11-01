# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
# Cancelling a task must drop every owned value its frames hold, whatever shape holds it.
# CI runs this program against the counting runtime (scripts/leak-check.sh): any live block fails.
import stdout from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import Channel from "@std/io/channels.ms"

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
    let o: List[String]? = ["a", "b"]
    nap()
    return o.get([]).length()

fn t_closure() Int:
    let words = ["a", "b", "c"]
    let f = fn: words.length()
    nap()
    return f()

fn t_match() Int:
    let r: List[Int]? = [1, 2, 3]

    match r:
        v:
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

fn t_var_reassign() Int:
    var s = "start-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    for i in 0..3:
        s = "{s}-{i}"
        nap()

    return s.length()

fn t_var_list_swap() Int:
    var a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    var b = [4, 5]
    let tmp = a
    a = b
    b = tmp
    nap()
    return a.length() + b.length()

fn t_partial() Int:
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

fn t_conditional(flag: Bool) Int:
    var keep = ["kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk"]

    if flag:
        let other = keep
        nap()
        return other.length()

    nap()
    return keep.length()

fn t_loop_break() Int:
    var out = List[List[Int]]()

    for i in 0..10:
        out.append([i, i, i])

        if i == 5:
            nap()
            break

    return out.length()

fn t_while_sleep() Int:
    var n = 0
    var _buf = "bufxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

    while true:
        n += 1
        _buf = "{_buf}{n}"
        nap()

    return n

fn run_one(which: Int) Unit:
    let group = TaskGroup[Int](timeout: nanoseconds(1000000))

    if which == 0: group.spawn(fn ch: t_var_reassign())
    else if which == 1: group.spawn(fn ch: t_var_list_swap())
    else if which == 2: group.spawn(fn ch: t_partial())
    else if which == 3: group.spawn(fn ch: t_conditional(true))
    else if which == 4: group.spawn(fn ch: t_conditional(false))
    else if which == 5: group.spawn(fn ch: t_loop_break())
    else: group.spawn(fn ch: t_while_sleep())

    let _ = group.wait()

export fn main() Int:
    for which in 0..7:
        run_one(which)
        stdout().write("case {which} released\n").get()

    return 0
