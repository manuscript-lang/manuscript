from "@std/fs.ms" import filesystem
from "@std/io.ms" import stdout, files
from "@std/tasks.ms" import TaskGroup

def read_whole(path: String) -> Int:
    let read = filesystem().read_file(path)
    if let bytes = read:
        return bytes.length()

    return -1

def open_then_read(path: String) -> Int:
    let opened = filesystem().open(path, "r", 420)
    if let file = opened:
        let _data = file.read_file()
        file.close()
        return 1

    return -1

def open_io_then_read(path: String) -> Int:
    let opened = files().open(path)
    if let file = opened:
        let _data = file.read()
        file.close()
        return 1

    return -1

export def main() -> Int:
    let path = arguments()[0].clone()
    with let group = TaskGroup[Int](timeout: 300.milliseconds):
        let first = path.clone()
        let second = path.clone()
        let third = path.clone()
        let a = group.spawn(lambda ch: read_whole(first.clone()))
        let b = group.spawn(lambda ch: open_then_read(second.clone()))
        let d = group.spawn(lambda ch: open_io_then_read(third.clone()))
        let c = group.spawn(lambda ch: 5)
        stdout().write(f"{c.result().get(-9)} {a.result().is_error()} {b.result().is_error()} {d.result().is_error()}\n").get()
    return 0
