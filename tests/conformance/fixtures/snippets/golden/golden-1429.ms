// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn crash() TextError:
    return TextError((1 / 0).to_string())
fn main() Unit:
    value: Int? := none
    result := value.ok_or_else(crash)
