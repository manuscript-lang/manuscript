import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/time.ms"

fn main() Void:
    print("first")

    _flushed := stdout().flush()
    void sleep(nanoseconds(3000000000)).wait()
