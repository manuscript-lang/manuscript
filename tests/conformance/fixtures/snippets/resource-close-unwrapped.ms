# conform: tags=with-cleanup,tier-core
# conform: phase=run
# conform: origin=a resource unwrapped or passed through a call closes at scope end
from "@std/core.ms" import Closeable, TextError
from "@std/io.ms" import stdout

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        stdout().write(f"close {self.name}\n").get()

def make(name: String) -> Result[Res, TextError]:
    return ok(Res(name))

def keep(r: Res) -> Res:
    return r

def via_try() -> Result[Unit, TextError]:
    let r = try make("try")
    stdout().write(f"body {r.name}\n").get()
    return ok(())

def via_get() -> Unit:
    let r = make("get").get()
    stdout().write(f"body {r.name}\n").get()

def via_optional_get() -> Unit:
    let o: Optional[Res] = some(Res("optional"))
    let r = o.get(Res("default"))
    stdout().write(f"body {r.name}\n").get()

def via_passthrough() -> Unit:
    let r = keep(Res("keep"))
    stdout().write(f"body {r.name}\n").get()

export def main() -> Int:
    let _ = via_try()
    via_get()
    via_optional_get()
    via_passthrough()
    return 0
