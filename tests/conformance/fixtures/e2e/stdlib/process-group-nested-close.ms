# conform: tags=stdlib-processes,tier-io
# conform: phase=run
# conform: timeout=30
# A group closing its child stops the child's own children, three levels down, even when the middle one is busy.
from "@std/channels.ms" import Channel
from "@std/fs.ms" import filesystem
from "@std/io.ms" import stdout
from "@std/processes.ms" import ProcessGroup
from "@std/time.ms" import duration, sleep

def marker() -> String:
    let root = filesystem().temporary_root().get("/tmp")
    return root + "/ms_group_nested_marker"

def leaf(ch: Channel[Unit, Unit]) -> Int:
    sleep(duration(2000000000))

    let _ = filesystem().write_file(marker(), "outlived\n")
    return 0

def middle(ch: Channel[Unit, Unit]) -> Int:
    with let group = ProcessGroup[Int]():
        var g = group.spawn(leaf).get()
        var spin = 0
        while True:
            spin += 1

    return 0

def top(ch: Channel[Unit, Unit]) -> Int:
    with let group = ProcessGroup[Int]():
        var m = group.spawn(middle).get()
        var c = ch
        let _ = c.send(())
        sleep(duration(300000000))

    # Leaving the block closed the middle process; the leaf must be gone with it.
    sleep(duration(3000000000))
    return 0

export def main() -> Int:
    let _ = filesystem().remove(marker())

    with let group = ProcessGroup[Int, Unit, Unit]():
        var c = group.spawn(top).get()
        let _ = c.channel.receive()
        c.result().get()

    (
        stdout().write(
            "leaf survived: " + filesystem().read_file(
                marker()
            ).is_ok().to_string() + "\n"
        ).get()
    )

    let _ = filesystem().remove(marker())
    return 0
