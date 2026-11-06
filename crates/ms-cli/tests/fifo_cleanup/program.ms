import list, read_file from "@std/os/fs.ms"
import arguments from "@std/os/env.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import milliseconds from "@std/os/time.ms"
import stdout from "@std/io/io.ms"

fn read_pipe(path: String) Int:
    let _data = read_file(path).wait()
    return 1

fn cancel_read(path: String) Int:
    let task = promise(fn: ok(read_pipe(path.clone())))
    if task.with(options: PromiseOptions(timeout: milliseconds(10))).wait().is_error():
        return 1

    return 0

export fn main() Int:
    let path = arguments()[0].clone()
    if cancel_read(path.clone()) != 1:
        return 1

    let before = list("/proc/self/fd").get().length()
    var cancelled = 0
    for i in 0..10:
        cancelled += cancel_read(path.clone())

    let after = list("/proc/self/fd").get().length()
    stdout().write("{cancelled} {before} {after}\n").get()
    return 0
