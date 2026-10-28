# conform: tags=closures,with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
import Closeable from "@std/core.ms"
import stdout from "@std/io.ms"
import {TaskGroup, cancelled} from "@std/tasks.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn say(text: String) Unit:
    let _ = stdout().write(text + "\n")

# Reports, as its task unwinds, whether the task counts as cancelled.
type Reporter:
    name: String

impl Closeable for Reporter:
    var fn close() Unit:
        say("{self.name} cleanup sees cancelled: {cancelled()}")

fn sleep_with_reporter() Int:
    with let reporter = Reporter("timeout"):
        sleep(nanoseconds(60000000000))
    return 0

fn returns_normally() Int:
    with let reporter = Reporter("normal"):
        say("normal body sees cancelled: {cancelled()}")
    return 1

export fn main() Int:
    say("outside a group: {cancelled()}")

    with let group = TaskGroup[Int]():
        group.spawn(fn ch: returns_normally())

        let _ = group.results()

    with let group = TaskGroup[Int](timeout: some(nanoseconds(20000000))):
        group.spawn(fn ch: sleep_with_reporter())

        let _ = group.wait()

    return 0
