# conform: tags=diagnostics,stdlib-workers,tier-core
# conform: phase=check
import Shared, share from "@std/shared.ms"
import WorkerGroup, worker_channel from "@std/workers.ms"

type Box:
    held: Shared[List[Int]]

fn sink() Unit:
    var ch = worker_channel[Int, Box]()
    let got = ch.receive()

export fn main() Int:
    var group = WorkerGroup[Box, Int]()
    var w = group.spawn(sink).get()
    let sent = w.channel.send(Box(held: share([1])))
    group.close()
    return 0
