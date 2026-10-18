import panic from "@std/faults.ms"

fn failed_initializer() Never:
    let _impossible: Int = panic("initializer cannot return")

fn returned_failure() Int:
    return panic("result cannot return")

fn endless() Int:
    while true:
        continue
