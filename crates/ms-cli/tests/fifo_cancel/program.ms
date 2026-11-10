import OpenMode, OpenOptions, open, read_file from "@std/os/fs.ms"
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import milliseconds from "@std/time.ms"

fn read_whole(path: String) Int:
    read := read_file(path).wait()
    if bytes := read:
        return bytes.length()

    return -1

fn open_then_read(path: String) Int:
    opened := open(path, OpenMode.Read, OpenOptions(permissions: 420))

    if var file = opened:
        _data := file.read_file()
        file.close().get(none)
        return 1

    return -1

fn open_io_then_read(path: String) Int:
    opened := open(path, OpenMode.Read, OpenOptions(permissions: 420))

    if var file = opened:
        if var input = file.reader():
            _data := input.next()
            _closed := input.close()

        return 1

    return -1

export fn main() Int:
    path := arguments()[0].clone()
    first := path.clone()
    second := path.clone()
    third := path.clone()
    a := promise(fn: ok(read_whole(first.clone())))
    b := promise(fn: ok(open_then_read(second.clone())))
    d := promise(fn: ok(open_io_then_read(third.clone())))
    c := promise(fn: ok(5))
    limit := milliseconds(300)
    c_result := c.with(options: PromiseOptions(timeout: limit.clone())).wait()
    a_result := a.with(options: PromiseOptions(timeout: limit.clone())).wait()
    b_result := b.with(options: PromiseOptions(timeout: limit.clone())).wait()
    d_result := d.with(options: PromiseOptions(timeout: limit.clone())).wait()
    (
        stdout()
        .write(
            "{c_result.get(-9)} {a_result.is_error()} {b_result.is_error()} {d_result.is_error()}\n"
        )
        .get()
    )
    return 0
