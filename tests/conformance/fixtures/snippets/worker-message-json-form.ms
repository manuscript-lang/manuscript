# conform: tags=diagnostics,stdlib-workers,tier-core
# conform: phase=check
from "@std/io.ms" import ReadStream
from "@std/workers.ms" import worker_channel

type Job:
    id: Int
    run: Callable[[Int], Int]

def sink() -> Unit:
    var ch = worker_channel[Int, Job]()
    let got = ch.receive()

def stream() -> Unit:
    var ch = worker_channel[ReadStream, Int]()
    let got = ch.receive()

def plain() -> Unit:
    var ch = worker_channel[Map[Int, List[String]], Optional[Float]]()
    let got = ch.receive()

export def main() -> Int:
    return 0
