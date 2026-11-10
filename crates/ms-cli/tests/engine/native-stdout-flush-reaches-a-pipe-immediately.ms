import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/time.ms"

fn main() Unit:
    print("first")

    let _flushed = stdout().flush()
    let _ = sleep(nanoseconds(3000000000)).wait()
