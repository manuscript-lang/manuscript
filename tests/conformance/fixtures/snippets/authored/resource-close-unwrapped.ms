// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// conform: origin=a resource unwrapped or passed through a call closes at scope end
import Closeable from "@std/core.ms"

type Res:
    name: String

fn var Res.close() Void!:
    print("close {self.name}")

fn make(name: String) Res!Error:
    return ok(Res(name))

fn keep(r: Res) Res:
    return r

fn via_try() Void!Error:
    r := make("try")?
    print("body {r.name}")

fn via_get() Void:
    r := make("get").get()
    print("body {r.name}")

fn via_optional_get() Void:
    o: Res? := Res("optional")
    r := o.get(Res("default"))
    print("body {r.name}")

fn via_passthrough() Void:
    r := keep(Res("keep"))
    print("body {r.name}")

fn main() Void:
    void via_try()
    via_get()
    via_optional_get()
    via_passthrough()
