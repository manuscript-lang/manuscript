import expect_equal from "@std/test/test.ms"
import Closeable from "@std/core.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import TaskChannel, TaskGroup from "@std/concurrency/tasks.ms"

type Door:
    closes: Shared[List[Int]]

impl Closeable for Door:
    var fn close() Unit!:
        var held = lock(self.closes)
        held.value.append(1)
        return ok(unit)

fn open_doors(ch: TaskChannel[Unit, Door]) Int:
    var count = 0

    while true:
        let next = ch.receive().get(none)
        if next.is_none(): break

        count = count + 1

    return count

test "a resource moves through a task channel and is closed once":
    let closes: Shared[List[Int]] = share(List[Int]())
    var group = TaskGroup[Int, Door, Unit]()
    let task = group.spawn(open_doors)
    try task.channel.send(Door(closes: closes))

    var channel = task.channel.clone()
    channel.close()
    try expect_equal(try task.result(), 1)
    try expect_equal(closes.get().length(), 1)
