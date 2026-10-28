# conform: tags=stdlib-processes,tier-io
# conform: phase=run
# conform: timeout=30
# Leaving a ProcessGroup block stops the children's own children too.
import Channel from "@std/channels.ms"
import filesystem from "@std/fs.ms"
import stdout from "@std/io.ms"
import ProcessGroup from "@std/processes.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn marker() String:
    let root = filesystem().temporary_root().get("/tmp")
    return root + "/ms_group_grandchild_marker"

fn grandchild(ch: Channel[Unit, Unit]) Int:
    sleep(nanoseconds(2000000000))

    let _ = filesystem().write_file(marker(), "outlived\n")
    return 0

fn child(ch: Channel[Unit, Unit]) Int:
    with let group = ProcessGroup[Int]():
        var g = group.spawn(grandchild).get()
        var c = ch
        let _ = c.send(unit)
        g.result().get()

    return 0

export fn main() Int:
    let _ = filesystem().remove(marker())

    with let group = ProcessGroup[Int, Unit, Unit]():
        var c = group.spawn(child).get()
        let _ = c.channel.receive()

    sleep(nanoseconds(3500000000))
    stdout().write(
        "grandchild survived: " + filesystem().read_file(
            marker()
        ).is_ok().to_string() + "\n"
    ).get()

    let _ = filesystem().remove(marker())
    return 0
