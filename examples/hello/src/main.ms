import (
    arguments from "@std/os/env.ms",
    stdout from "@std/io/io.ms",
)

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1

    return 0
