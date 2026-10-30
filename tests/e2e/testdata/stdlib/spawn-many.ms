import {Worker, WorkerGroup, worker_channel} from "@std/workers.ms"
import {expect_equal} from "@std/test.ms"

fn echo() Unit:
    var ch = worker_channel[Int, Int]()
    if let n = ch.receive().get(none):
        let _ = ch.send(n + 1)

test "spawn_many starts workers from one entry":
    let group = WorkerGroup[Int, Int]()
    var workers = try group.spawn_many(echo, 3)
    try expect_equal(workers.length(), 3)
    for i in 0..3:
        let _ = workers[i].channel.send(i)

    for i in 0..3:
        let got = try workers[i].channel.receive()
        try expect_equal(got.get(-1), i + 1)
