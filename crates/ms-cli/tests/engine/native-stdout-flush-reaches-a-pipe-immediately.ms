import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/os/time.ms"

export fn main() Int:
    stdout().write("first\n").get()
    let _flushed = stdout().flush().wait()
    let _ = sleep(nanoseconds(3000000000)).wait()
    return 0
