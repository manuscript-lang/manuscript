# conform: tags=diagnostics,stdlib-workers,tier-core
# conform: phase=check
import ReadStream from "@std/io.ms"
import worker_channel from "@std/workers.ms"

type Job:
    id: Int
    run: fn(Int) Int

fn sink() Unit:
    var ch = worker_channel[Int, Job]()
    let got = ch.receive()

fn stream() Unit:
    var ch = worker_channel[ReadStream, Int]()
    let got = ch.receive()

fn plain() Unit:
    var ch = worker_channel[Map[Int, List[String]], Float?]()
    let got = ch.receive()

export fn main() Int:
    return 0
