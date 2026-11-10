import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/time.ms"

fn main() Unit:
    print("first")

    _flushed := stdout().flush()
    _ := sleep(nanoseconds(3000000000)).wait()
