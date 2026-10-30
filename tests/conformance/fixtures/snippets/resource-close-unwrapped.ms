# conform: tags=scope-cleanup,tier-core
# conform: phase=run
# conform: origin=a resource unwrapped or passed through a call closes at scope end
import Closeable, TextError from "@std/core.ms"
import stdout from "@std/io.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit:
        stdout().write("close {self.name}\n").get()

fn make(name: String) Result[Res, TextError]:
    return ok(Res(name))

fn keep(r: Res) Res:
    return r

fn via_try() Result[Unit, TextError]:
    let r = try make("try")
    stdout().write("body {r.name}\n").get()
    return ok(unit)

fn via_get() Unit:
    let r = make("get").get()
    stdout().write("body {r.name}\n").get()

fn via_optional_get() Unit:
    let o: Optional[Res] = some(Res("optional"))
    let r = o.get(Res("default"))
    stdout().write("body {r.name}\n").get()

fn via_passthrough() Unit:
    let r = keep(Res("keep"))
    stdout().write("body {r.name}\n").get()

export fn main() Int:
    let _ = via_try()
    via_get()
    via_optional_get()
    via_passthrough()
    return 0
