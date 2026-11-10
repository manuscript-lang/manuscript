import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/time.ms"

export fn main() Int:
    print("first")

    let _flushed = stdout().flush()
    let _ = sleep(nanoseconds(3000000000)).wait()
    return 0
