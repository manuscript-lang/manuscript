import Result from "@std/result.ms"
import { ExecutionError, parallel } from "@std/tasks.ms"

fn combine() -> Result[String, ExecutionError]:
    let first = fn() -> String: return "hello"
    let second = fn() -> Int: return 42

    let [text, number] = try parallel(tasks: [first, second])
    return ok(value: "{text} {number}")
