// conform: tags=diagnostics
// conform: phase=check
import JsonError from "@std/data/json.ms"
fn describe(cause: Error) String:
    match cause:
        JsonError(json):
            return json.message()
        _:
            return cause.message()
