import control from "@std/process.ms"

export fn main() Int:
    let _outcome = control().replace(
        program: "/bin/sh", arguments: ["sh", "-c", "echo replaced $MS_REPLACED"],
        environment: {"MS_REPLACED": "yes"}
    )
    return 1
