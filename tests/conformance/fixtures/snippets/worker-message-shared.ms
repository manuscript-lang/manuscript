# conform: tags=diagnostics,stdlib-workers,tier-core
# conform: phase=check
from "@std/shared.ms" import Shared, share
from "@std/workers.ms" import WorkerGroup, worker_channel

type Box:
    held: Shared[List[Int]]

def sink() -> Unit:
    var ch = worker_channel[Int, Box]()
    let got = ch.receive()

export def main() -> Int:
    var group = WorkerGroup[Box, Int]()
    var w = group.spawn(sink).get()
    let sent = w.channel.send(Box(held: share([1])))
    group.close()
    return 0
