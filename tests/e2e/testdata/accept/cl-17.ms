import panic from "@std/faults.ms"

fn failed_initializer() Never:
    let _impossible: Int = panic(message: "initializer cannot return")

fn returned_failure() Int:
    return panic(message: "result cannot return")

fn endless() Int:
    while true:
        continue
