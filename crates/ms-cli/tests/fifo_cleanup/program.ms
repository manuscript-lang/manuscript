import list, read_file, read_symlink from "@std/os/fs.ms"
import arguments from "@std/os/env.ms"
import promise, PromiseOptions from "@std/concurrency/promise.ms"
import milliseconds, sleep from "@std/time.ms"

fn read_pipe(path: String) Int:
    let _data = read_file(path).wait()
    return 1

fn cancel_read(path: String) Int:
    let task = promise(fn: ok(read_pipe(path.clone())))
    if task.with(options: PromiseOptions(timeout: milliseconds(10))).wait().is_error():
        return 1

    return 0

// Descriptors that refer to the FIFO. The total descriptor count is not a fair measure: the
// runtime lazily starts an event loop (an epoll and a wake pipe) for each worker thread, and a
// loaded machine starts them at different times.
fn open_on(path: String) Int:
    var count = 0
    for entry in list("/proc/self/fd").get():
        if read_symlink("/proc/self/fd/{entry.name}").get("") == path: count += 1
    return count

export fn main() Int:
    let path = arguments()[0].clone()
    var cancelled = 0
    for i in 0..10:
        cancelled += cancel_read(path.clone())

    // A cancelled read may still be closing its descriptor; one that leaked never does.
    var open = open_on(path.clone())
    var waited = 0

    while open > 0 and waited < 200:
        let _slept = sleep(milliseconds(10)).wait()
        waited += 1
        open = open_on(path.clone())

    print("{cancelled} {open}")
    return 0
