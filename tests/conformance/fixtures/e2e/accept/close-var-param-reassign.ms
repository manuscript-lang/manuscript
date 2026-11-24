// conform: tags=scope-cleanup,records,tier-io
// conform: phase=run
// A var parameter that is assigned closes the value it replaces; the caller closes the final one.
import Closeable from "@std/core.ms"

type R:
    name String

fn move R.close() Void!:
    print(f"close {self.name}")

fn replace(var r R) Void:
    r = R("new")

fn replace_local() Void:
    var _r = R("local-old")
    _r = R("local-new")

fn replace_field(var w W) Void:
    w.r = R("field-new")

type W:
    r R

fn main() Void:
    var v = R("old")
    replace(v)
    print("after replace")
    replace_local()

    var w = W(R("field-old"))
    replace_field(w)
    print("end")
