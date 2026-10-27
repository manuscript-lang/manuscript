from "@std/io.ms" import stdout
from "@std/time.ms" import sleep, nanoseconds

export def main() -> Int:
    stdout().write("first\n").get()
    stdout().flush().get()
    sleep(nanoseconds(3000000000))
    return 0
