import open, read_file from "@std/os/fs.ms"
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import milliseconds from "@std/os/time.ms"

fn read_whole(path: String) Int:
    let read = read_file(path).wait()
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
    let opened = open(path, "r", 420)

    if var file = opened:
        if var input = file.reader():
            let _data = input.read().wait()
            let _closed = input.close()

        return 1

    return -1

export fn main() Int:
    let path = arguments()[0].clone()
    let first = path.clone()
    let second = path.clone()
    let third = path.clone()
    let a = promise(fn: ok(read_whole(first.clone())))
    let b = promise(fn: ok(open_then_read(second.clone())))
    let d = promise(fn: ok(open_io_then_read(third.clone())))
    let c = promise(fn: ok(5))
    let limit = milliseconds(300)
    let c_result = c.with(options: PromiseOptions(timeout: limit.clone())).wait()
    let a_result = a.with(options: PromiseOptions(timeout: limit.clone())).wait()
    let b_result = b.with(options: PromiseOptions(timeout: limit.clone())).wait()
    let d_result = d.with(options: PromiseOptions(timeout: limit.clone())).wait()
    (
        stdout()
        .write(
            "{c_result.get(-9)} {a_result.is_error()} {b_result.is_error()} {d_result.is_error()}\n"
        )
        .get()
    )
    return 0
