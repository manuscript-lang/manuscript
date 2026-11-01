import stdout from "@std/io/io.ms"
import sleep, nanoseconds from "@std/os/time.ms"

export fn main() Int:
    stdout().write("first\n").get()
    stdout().flush().get()
    sleep(nanoseconds(3000000000))
    return 0
