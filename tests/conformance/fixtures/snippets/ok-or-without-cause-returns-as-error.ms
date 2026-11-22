// conform: tags=optional,try-result,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

fn a(s: String) Int!:
    return s.parse_int().ok_or(Error("missing"))

fn b(s: String) Result[Int, Error]:
    return s.parse_int().ok_or(Error("missing"))

fn main() Void:
    stdout().write(f"{a("4").get_or(0)} {b("x").is_ok()}\n").get()
    if e := a("x"):
        stdout().write(f"ok {e}\n").get()
