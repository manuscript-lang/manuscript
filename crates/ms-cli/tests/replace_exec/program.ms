import replace from "@std/process.ms"

export fn main() Int:
    let _outcome = replace(
        program: "/bin/sh", arguments: ["sh", "-c", "echo replaced $MS_REPLACED"],
        environment: {"MS_REPLACED": "yes"}
    )
    return 1
