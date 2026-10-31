# conform: tags=optional,try-result,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io.ms"
fn a(s: String) Int!:
    return s.parse_int().ok_or()
fn b(s: String) Result[Int, Error]:
    return s.parse_int().ok_or()
export fn main() Int:
    stdout().write("{a("4").get(0)} {b("x").is_ok()}\n").get()
    if let e = a("x"):
        stdout().write("ok {e}\n").get()
    return 0
