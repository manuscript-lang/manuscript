// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// conform: origin=a resource unwrapped or passed through a call closes at scope end
import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    var fn close() Unit!:
        print("close {self.name}")
        return ok(unit)

fn make(name: String) Res!Error:
    return ok(Res(name))

fn keep(r: Res) Res:
    return r

fn via_try() Unit!Error:
    r := try make("try")
    print("body {r.name}")
    return ok(unit)

fn via_get() Unit:
    r := make("get").get()
    print("body {r.name}")

fn via_optional_get() Unit:
    o: Res? = Res("optional")
    r := o.get(Res("default"))
    print("body {r.name}")

fn via_passthrough() Unit:
    r := keep(Res("keep"))
    print("body {r.name}")

export fn main() Int:
    _ := via_try()
    via_get()
    via_optional_get()
    via_passthrough()
    return 0
