import filesystem from "@std/fs.ms"
import arguments from "@std/process.ms"
import TaskGroup from "@std/tasks.ms"
import stdout from "@std/io.ms"

fn read_pipe(path: String) Int:
    let _data = filesystem().read_file(path)
    return 1

fn cancel_read(path: String) Int:
    var group = TaskGroup[Int](timeout: 10.milliseconds)
    let task = group.spawn(fn ch: read_pipe(path.clone()))
    if task.result().is_error():
        return 1

    group.close().get(none)
    return 0

export fn main() Int:
    let path = arguments() [0].clone()
    if cancel_read(path.clone()) != 1:
        return 1

    let before = filesystem().list("/proc/self/fd").get().length()
    var cancelled = 0
    for i in 0..10:
        cancelled += cancel_read(path.clone())

    let after = filesystem().list("/proc/self/fd").get().length()
    stdout().write("{cancelled} {before} {after}\n").get()
    return 0
