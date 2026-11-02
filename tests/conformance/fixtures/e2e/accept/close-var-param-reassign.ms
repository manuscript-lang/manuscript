# conform: tags=scope-cleanup,records,tier-io
# conform: phase=run
# A var parameter that is assigned closes the value it replaces; the caller closes the final one.
import Closeable from "@std/core.ms"
import stdout from "@std/io/io.ms"

type R:
    name: String

impl Closeable for R:
    var fn close() Unit!:
        stdout().write("close {self.name}\n").get()
        return ok(unit)

fn replace(var r: R) Unit:
    r = R("new")

fn replace_local() Unit:
    var _r = R("local-old")
    _r = R("local-new")

fn replace_field(var w: W) Unit:
    w.r = R("field-new")

type W:
    r: R

export fn main() Int:
    var v = R("old")
    replace(var v)
    stdout().write("after replace\n").get()
    replace_local()

    var w = W(R("field-old"))
    replace_field(var w)
    stdout().write("end\n").get()
    return 0
