# conform: tags=stdlib-processes,tier-io
# conform: phase=run
# conform: timeout=30
# A group closing its child stops the child's own children, three levels down, even when the middle one is busy.
import Channel from "@std/channels.ms"
import filesystem from "@std/fs.ms"
import stdout from "@std/io.ms"
import ProcessGroup from "@std/processes.ms"
import nanoseconds, sleep from "@std/time.ms"

fn marker() String:
    let root = filesystem().temporary_root().get("/tmp")
    return root + "/ms_group_nested_marker"

fn leaf(ch: Channel[Unit, Unit]) Int:
    sleep(nanoseconds(2000000000))

    let _ = filesystem().write_file(marker(), "outlived\n")
    return 0

fn middle(ch: Channel[Unit, Unit]) Int:
    var group = ProcessGroup[Int]()
    var _g = group.spawn(leaf).get()
    var _spin = 0
    while true:
        _spin += 1
    group.close().get(none)
    return 0

fn top(ch: Channel[Unit, Unit]) Int:
    var group = ProcessGroup[Int]()
    var _m = group.spawn(middle).get()
    var c = ch
    let _ = c.send(unit)
    sleep(nanoseconds(300000000))
    group.close().get(none)

    # Leaving the block closed the middle process; the leaf must be gone with it.
    sleep(nanoseconds(3000000000))
    return 0

export fn main() Int:
    let _ = filesystem().remove(marker())
    var group = ProcessGroup[Int, Unit, Unit]()
    var c = group.spawn(top).get()
    let _ = c.channel.receive()
    c.result().get()
    group.close().get(none)
    stdout().write(
        "leaf survived: " + filesystem().read_file(
            marker()
        ).is_ok().to_string() + "\n"
    ).get()

    let _ = filesystem().remove(marker())
    return 0
