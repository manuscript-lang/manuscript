// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn tail(value Result[Int, TextError]) Result[Int, Error] {
    output := try value
    return ok(output)
}
// expect-error: MS1000 5:15-5:24 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
// expect-fix: 5:15-5:24 "value?"
