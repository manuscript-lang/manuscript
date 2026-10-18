import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"

    match stdout().write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
