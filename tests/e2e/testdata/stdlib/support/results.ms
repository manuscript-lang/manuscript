import panic from "@std/faults.ms"

export fn value[T, E: Error](result: Result[T, E]) -> T:
    if let found = result: return found

    return panic(message: result.unwrap_error().message())
