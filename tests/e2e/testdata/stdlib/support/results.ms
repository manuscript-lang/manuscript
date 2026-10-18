import panic from "@std/faults.ms"

export fn value[T, E: Error](result: Result[T, E]) -> T:
    match result:
    ok(found): return found
    error(cause): return panic(message: cause.message())
