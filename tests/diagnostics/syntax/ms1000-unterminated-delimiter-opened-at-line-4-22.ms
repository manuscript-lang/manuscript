// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn tail(value: Result[
// expect-error: MS1000 6:1 unterminated delimiter '[' opened at line 4:22; add the matching ']' before the end of the file
