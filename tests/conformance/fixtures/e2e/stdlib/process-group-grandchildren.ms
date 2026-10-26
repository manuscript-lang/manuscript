# conform: tags=stdlib-processes,tier-io
# conform: phase=run
# conform: timeout=30
# Leaving a ProcessGroup block stops the children's own children too.
from "@std/channels.ms" import Channel
from "@std/fs.ms" import filesystem
from "@std/io.ms" import stdout
from "@std/processes.ms" import ProcessGroup
from "@std/time.ms" import duration, sleep

def marker() -> String:
    let root = filesystem().temporary_root().get("/tmp")
    return root + "/ms_group_grandchild_marker"

def grandchild(ch: Channel[Unit, Unit]) -> Int:
    sleep(duration(2000000000))

    let _ = filesystem().write_file(marker(), "outlived\n")
    return 0

def child(ch: Channel[Unit, Unit]) -> Int:
    with let group = ProcessGroup[Int]():
        var g = group.spawn(grandchild).get()
        var c = ch
        let _ = c.send(())
        g.result().get()

    return 0

export def main() -> Int:
    let _ = filesystem().remove(marker())

    with let group = ProcessGroup[Int, Unit, Unit]():
        var c = group.spawn(child).get()
        let _ = c.channel.receive()

    sleep(duration(3500000000))
    (
        stdout().write(
            "grandchild survived: " + filesystem().read_file(
                marker()
            ).is_ok().to_string() + "\n"
        ).get()
    )

    let _ = filesystem().remove(marker())
    return 0
