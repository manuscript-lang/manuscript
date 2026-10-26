# conform: tags=closures,with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
from "@std/core.ms" import Closeable
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup, cancelled
from "@std/time.ms" import duration, sleep

def say(text: String) -> Unit:
    let _ = stdout().write(text + "\n")

# Reports, as its task unwinds, whether the task counts as cancelled.
type Reporter:
    name: String

impl Closeable for Reporter:
    var def close() -> Unit:
        say(f"{self.name} cleanup sees cancelled: {cancelled()}")

def sleep_with_reporter() -> Int:
    with let reporter = Reporter("timeout"):
        sleep(duration(60000000000))
    return 0

def returns_normally() -> Int:
    with let reporter = Reporter("normal"):
        say(f"normal body sees cancelled: {cancelled()}")
    return 1

export def main() -> Int:
    say(f"outside a group: {cancelled()}")

    with let group = TaskGroup[Int]():
        group.spawn(lambda ch: returns_normally())

        let _ = group.results()

    with let group = TaskGroup[Int](timeout: some(duration(20000000))):
        group.spawn(lambda ch: sleep_with_reporter())

        let _ = group.wait()

    return 0
