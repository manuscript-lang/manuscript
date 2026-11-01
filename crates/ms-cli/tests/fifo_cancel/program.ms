import open, read_file from "@std/os/fs.ms"
import arguments from "@std/os/process.ms"
import stdout, open_read from "@std/io/io.ms"
import TaskGroup from "@std/concurrency/tasks.ms"

fn read_whole(path: String) Int:
    let read = read_file(path)
    if let bytes = read:
        return bytes.length()

    return -1

fn open_then_read(path: String) Int:
    let opened = open(path, "r", 420)

    if var file = opened:
        let _data = file.read_file()
        file.close().get(none)
        return 1

    return -1

fn open_io_then_read(path: String) Int:
    let opened = open_read(path)

    if let file = opened:
        let _data = file.read()
        file.close()
        return 1

    return -1

export fn main() Int:
    let path = arguments()[0].clone()
    var group = TaskGroup[Int](timeout: 300.milliseconds)
    let first = path.clone()
    let second = path.clone()
    let third = path.clone()
    var a = group.spawn(fn var ch: read_whole(first.clone()))
    var b = group.spawn(fn var ch: open_then_read(second.clone()))
    var d = group.spawn(fn var ch: open_io_then_read(third.clone()))
    var c = group.spawn(fn var ch: 5)
    (
        stdout()
        .write(
            "{c.result().get(-9)} {a.result().is_error()} {b.result().is_error()} {d.result().is_error()}\n"
        )
        .get()
    )
    group.close().get(none)
    return 0
