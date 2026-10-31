# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
# Cancelling a task parked after a closing `var` binding must drop what the binding holds, closed by hand or not.
# CI runs this program against the counting runtime (scripts/leak-check.sh): any live block fails.
import Closeable from "@std/core.ms"
import stdout from "@std/io.ms"
import TaskGroup from "@std/tasks.ms"
import nanoseconds, sleep from "@std/time.ms"

type G:
    held: Bool
    items: List[String]

impl Closeable for G:
    var fn close() Unit!:
        if self.held:
            self.held = false
        return ok(unit)

fn body() Int:
    while true:
        var g = G(true, [])
        (
            g.items.append(
                "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            )
        )
        g.close().get(none)
        sleep(nanoseconds(10000000000))

    return 0

fn body_open() Int:
    var g = G(true, [])
    g.items.append("yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy")
    sleep(nanoseconds(10000000000))
    return g.items.length()

fn run_one(closed: Bool) Unit:
    let group = TaskGroup[Int](timeout: nanoseconds(1000000))

    if closed: group.spawn(fn ch: body())
    else: group.spawn(fn ch: body_open())

    let _ = group.wait()

export fn main() Int:
    run_one(true)
    run_one(false)
    stdout().write("released\n").get()
    return 0
