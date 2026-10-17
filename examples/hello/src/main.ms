import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(data: message.to_bytes()).is_error():
        return 1

    return 0
