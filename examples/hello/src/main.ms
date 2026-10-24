from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

export def main() -> Int:
    let message = f"Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1

    return 0
