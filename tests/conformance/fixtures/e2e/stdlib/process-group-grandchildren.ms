# conform: tags=stdlib-processes,tier-io
# conform: phase=run
# conform: timeout=30
# Leaving a ProcessGroup block stops the children's own children too.
import Channel from "@std/io/channels.ms"
import read_file, remove, temporary_root, write_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import ProcessGroup from "@std/os/processes.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn marker() String:
    let root = temporary_root().get("/tmp")
    return root + "/ms_group_grandchild_marker"

fn grandchild(var ch: Channel[Unit, Unit]) Int:
    sleep(nanoseconds(2000000000))

    let _ = write_file(marker(), "outlived\n")
    return 0

fn child(var ch: Channel[Unit, Unit]) Int:
    var group = ProcessGroup[Int]()
    var g = group.spawn(grandchild).get()
    let _ = ch.send(unit)
    g.result().get()
    group.close().get(none)
    return 0

export fn main() Int:
    let _ = remove(marker())
    var group = ProcessGroup[Int, Unit, Unit]()
    var c = group.spawn(child).get()
    let _ = c.channel.receive()
    group.close().get(none)
    sleep(nanoseconds(3500000000))
    stdout().write(
        "grandchild survived: " + read_file(marker()).is_ok().to_string() + "\n"
    ).get()

    let _ = remove(marker())
    return 0
