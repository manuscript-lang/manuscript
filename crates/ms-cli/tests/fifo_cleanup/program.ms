from "@std/fs.ms" import filesystem
from "@std/process.ms" import arguments
from "@std/tasks.ms" import TaskGroup
from "@std/io.ms" import stdout

def read_pipe(path: String) -> Int:
    let _data = filesystem().read_file(path)
    return 1

def cancel_read(path: String) -> Int:
    var group = TaskGroup[Int](timeout: 10.milliseconds)
    let task = group.spawn(lambda ch: read_pipe(path.clone()))
    if task.result().is_error():
        return 1

    group.close()
    return 0

export def main() -> Int:
    let path = arguments() [0].clone()
    if cancel_read(path.clone()) != 1:
        return 1

    let before = filesystem().list("/proc/self/fd").get().length()
    var cancelled = 0
    for i in 0..10:
        cancelled += cancel_read(path.clone())

    let after = filesystem().list("/proc/self/fd").get().length()
    stdout().write(f"{cancelled} {before} {after}\n").get()
    return 0
