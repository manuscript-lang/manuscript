import Process from "@std/cli.ms"

export fn main(process: Process) -> Int:
    let message = "Arguments: {process.arguments.length()}\n"
    match process.stdout.write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
